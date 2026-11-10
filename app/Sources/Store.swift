import Foundation
import AppKit
import UserNotifications

@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published private(set) var tasks: [DLTask] = []
    @Published private(set) var downSpeed: Int64 = 0
    @Published private(set) var upSpeed: Int64 = 0
    @Published private(set) var engineOK = false
    @Published private(set) var peers: [Peer] = []
    @Published var errorBanner: String?
    @Published private(set) var speedMode = Prefs.speedMode
    var limitMode: Bool { speedMode != "full" }
    @Published private(set) var uploadHistory: [Int64] = Array(repeating: 0, count: 60)
    @Published private(set) var engineVersion = ""
    @Published private(set) var stats = TransferStats.load()
    private var lastDone: [String: Int64] = [:]
    private var lastUp: [String: Int64] = [:]
    private var lastStatsSave = Date()
    @Published var requestedCategory: Category?
    @Published var trackerStatus = ""
    /// Last 60 samples of total download speed, for the speed graph.
    @Published private(set) var speedHistory: [Int64] = Array(repeating: 0, count: 60)

    let engine = Engine()
    private(set) var rpc = Aria2RPC(port: Prefs.rpcPort, secret: Prefs.secret)
    private var loop: Task<Void, Never>?
    private var knownStatus: [String: String] = [:]
    private var primed = false
    private var failures = 0
    private var sleepActivity: NSObjectProtocol?
    private let dockView = DockProgressView()

    /// Set by the detail panel so peers are only fetched while they're on screen.
    var peerWatchGid: String?

    private init() {}

    func start() {
        engine.start()
        if let e = engine.lastError { errorBanner = e }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        loop = Task { [weak self] in
            var first = true
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                if first, self.engineOK {
                    first = false
                    if Prefs.autoResumeAll { self.resumeAll() }
                    await self.syncTrackers(force: false)
                }
                let busy = self.tasks.contains { $0.status == "active" }
                try? await Task.sleep(nanoseconds: busy ? 1_000_000_000 : 2_000_000_000)
            }
        }
    }

    func shutdown() {
        stats.save()
        loop?.cancel()
        engine.stop()
    }

    func tasks(in c: Category) -> [DLTask] { tasks.filter(c.contains) }
    func task(_ gid: String?) -> DLTask? { tasks.first { $0.id == gid } }
    var activeCount: Int { tasks.filter { $0.status == "active" }.count }

    // MARK: polling

    func refresh() async {
        do {
            var calls: [(String, [Any])] = [
                ("aria2.tellActive", [DLTask.pollKeys]),
                ("aria2.tellWaiting", [0, 1000, DLTask.pollKeys]),
                ("aria2.tellStopped", [0, 1000, DLTask.pollKeys]),
                ("aria2.getGlobalStat", []),
            ]
            if let g = peerWatchGid { calls.append(("aria2.getPeers", [g])) }
            let r = try await rpc.multicall(calls)

            var list: [DLTask] = []
            for i in 0..<3 { list += ((r[i] as? [[String: Any]]) ?? []).map(DLTask.init) }
            let stat = r[3] as? [String: Any] ?? [:]
            let down = Int64(stat["downloadSpeed"] as? String ?? "") ?? 0
            let up = Int64(stat["uploadSpeed"] as? String ?? "") ?? 0

            notifyTransitions(list)
            if list != tasks { tasks = list }
            if down != downSpeed { downSpeed = down }
            if up != upSpeed { upSpeed = up }
            if down > 0 || speedHistory.last != 0 {
                speedHistory = Array((speedHistory + [down]).suffix(60))
            }
            if up > 0 || uploadHistory.last != 0 {
                uploadHistory = Array((uploadHistory + [up]).suffix(60))
            }
            countTransfer(list)
            if engineVersion.isEmpty, let v = try? await rpc.call("aria2.getVersion") as? [String: Any] {
                engineVersion = v["version"] as? String ?? ""
            }
            if r.count > 4 {
                let p = parsePeers(r[4], numPieces: task(peerWatchGid)?.numPieces ?? 0)
                if p != peers { peers = p }
            } else if !peers.isEmpty {
                peers = []
            }
            if !engineOK { engineOK = true; errorBanner = nil }
            failures = 0
            updateDockAndSleep()
        } catch {
            failures += 1
            if failures > 2 {
                engineOK = false
                errorBanner = "The download engine isn't responding — restarting it…"
                if !engine.isRunning { engine.start() }
            }
        }
    }

    private func parsePeers(_ raw: Any, numPieces: Int) -> [Peer] {
        guard let list = raw as? [[String: Any]] else { return [] }
        return list.map { p in
            let bits = p["bitfield"] as? String ?? ""
            let have = bits.reduce(0) { $0 + (Int(String($1), radix: 16) ?? 0).nonzeroBitCount }
            let ip = p["ip"] as? String ?? "?"
            let port = p["port"] as? String ?? ""
            return Peer(id: "\(ip):\(port)", ip: ip, port: port,
                        client: Fmt.client(fromPeerId: p["peerId"] as? String ?? ""),
                        progress: numPieces > 0 ? min(1, Double(have) / Double(numPieces)) : 0,
                        down: Int64(p["downloadSpeed"] as? String ?? "") ?? 0,
                        up: Int64(p["uploadSpeed"] as? String ?? "") ?? 0,
                        seeder: (p["seeder"] as? String) == "true")
        }
        .sorted { $0.down + $0.up > $1.down + $1.up }
    }

    private func notifyTransitions(_ list: [DLTask]) {
        defer {
            knownStatus = Dictionary(list.map { ($0.id, $0.status) }, uniquingKeysWith: { a, _ in a })
            primed = true
        }
        guard Prefs.notify, primed else { return }
        for t in list where !t.isMetadata {
            // A gid we've never seen that is already finished = it completed between two polls.
            let before = knownStatus[t.id] ?? "new"
            guard before != t.status, ["active", "waiting", "new"].contains(before) else { continue }
            if t.status == "complete" {
                notify("Download complete", t.name, path: t.path)
            } else if t.status == "error" {
                notify("Download failed", "\(t.name) — \(t.errorMessage ?? "error")", path: nil)
            }
        }
    }

    private func notify(_ title: String, _ body: String, path: String?) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        if let path { c.userInfo = ["path": path] }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    private func updateDockAndSleep() {
        let active = tasks.filter { $0.status == "active" && !$0.isSeeding }

        // Keep the Mac awake while downloading
        if Prefs.preventSleep && !active.isEmpty {
            if sleepActivity == nil {
                sleepActivity = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled], reason: "Downloading files")
            }
        } else if let a = sleepActivity {
            ProcessInfo.processInfo.endActivity(a)
            sleepActivity = nil
        }

        // Dock badge + progress bar
        let tile = NSApp.dockTile
        let badge = active.isEmpty ? nil : "\(active.count)"
        if tile.badgeLabel != badge { tile.badgeLabel = badge }
        let total = active.reduce(Int64(0)) { $0 + $1.total }
        let done = active.reduce(Int64(0)) { $0 + $1.completed }
        let progress = Prefs.dockProgress && total > 0 ? Double(done) / Double(total) : -1
        if tile.contentView !== dockView { tile.contentView = dockView }
        if dockView.progress != progress {
            dockView.progress = progress
            tile.display()
        }
    }

    // MARK: adding

    private func run(_ method: String, _ params: [Any] = []) {
        Task {
            do { try await rpc.call(method, params) } catch { errorBanner = error.localizedDescription }
            await refresh()
        }
    }

    struct AddOptions {
        var dir: String?
        var out: String?
        var connections: Int?
        var userAgent: String?
        var referer: String?
        var cookie: String?
        var authorization: String?
        var proxy: String?
        var selectFiles: [Int]?

        var aria2: [String: Any] {
            var o: [String: Any] = [:]
            if let dir, !dir.isEmpty { o["dir"] = dir }
            if let out, !out.isEmpty { o["out"] = out }
            if let c = connections { o["split"] = "\(c)"; o["max-connection-per-server"] = "\(c)" }
            if let ua = userAgent, !ua.isEmpty { o["user-agent"] = ua }
            if let r = referer, !r.isEmpty { o["referer"] = r }
            if let p = proxy, !p.isEmpty { o["all-proxy"] = p }
            var headers: [String] = []
            if let c = cookie, !c.isEmpty { headers.append("Cookie: \(c)") }
            if let a = authorization, !a.isEmpty { headers.append("Authorization: \(a)") }
            if !headers.isEmpty { o["header"] = headers }
            if let s = selectFiles, !s.isEmpty { o["select-file"] = s.map(String.init).joined(separator: ",") }
            return o
        }
    }

    func add(uris: [String], options: AddOptions = AddOptions()) {
        if let d = options.dir { Prefs.rememberDir(d) }
        for u in uris { run("aria2.addUri", [[u], options.aria2]) }
        afterAdd()
    }

    func addTorrent(_ data: Data, options: AddOptions = AddOptions()) {
        if let d = options.dir { Prefs.rememberDir(d) }
        run("aria2.addTorrent", [data.base64EncodedString(), [], options.aria2])
        afterAdd()
    }

    private func afterAdd() {
        if Prefs.showDownloadingAfterAdd { requestedCategory = .downloading }
    }

    // MARK: task actions

    func pause(_ t: DLTask) { run("aria2.forcePause", [t.id]) }
    func resume(_ t: DLTask) { run("aria2.unpause", [t.id]) }
    func pauseAll() { run("aria2.forcePauseAll") }
    func resumeAll() { run("aria2.unpauseAll") }
    func purge() { run("aria2.purgeDownloadResult") }

    func remove(_ t: DLTask, deleteFiles: Bool) {
        Task {
            if t.isLive {
                _ = try? await rpc.call("aria2.forceRemove", [t.id])
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            _ = try? await rpc.call("aria2.removeDownloadResult", [t.id])
            if deleteFiles {
                var paths = [t.path + ".aria2"]
                if t.path != t.dir { paths.insert(t.path, at: 0) }
                if t.isTorrent, let h = t.infoHash { paths.append((t.dir as NSString).appendingPathComponent("\(h).torrent")) }
                for p in paths where FileManager.default.fileExists(atPath: p) {
                    try? FileManager.default.trashItem(at: URL(fileURLWithPath: p), resultingItemURL: nil)
                }
            }
            await refresh()
        }
    }

    /// Removes the task and adds it again with the same options (Motrix's "Restart").
    func restart(_ t: DLTask) {
        Task {
            var opts: [String: Any] = [:]
            if let o = try? await rpc.call("aria2.getOption", [t.id]) as? [String: Any] {
                for k in ["dir", "out", "split", "max-connection-per-server", "user-agent", "referer", "all-proxy", "header", "select-file"] {
                    if let v = o[k] { opts[k] = v }
                }
            }
            if let h = opts["header"] as? String { opts["header"] = h.components(separatedBy: "\n").filter { !$0.isEmpty } }
            if opts["dir"] == nil { opts["dir"] = t.dir }

            let uris: [String]
            if t.isTorrent || t.isMetadata, let link = t.link {
                uris = [link]
                opts.removeValue(forKey: "out")
            } else if let u = t.uri {
                uris = [u]
            } else {
                errorBanner = "There's no saved link to restart this download."
                return
            }
            if t.isLive { _ = try? await rpc.call("aria2.forceRemove", [t.id]); try? await Task.sleep(nanoseconds: 500_000_000) }
            _ = try? await rpc.call("aria2.removeDownloadResult", [t.id])
            do { try await rpc.call("aria2.addUri", [uris, opts]) } catch { errorBanner = error.localizedDescription }
            await refresh()
        }
    }

    func setFileSelection(_ t: DLTask, selected: Set<Int>) {
        guard !selected.isEmpty else { errorBanner = "At least one file must stay selected."; return }
        run("aria2.changeOption", [t.id, ["select-file": selected.sorted().map(String.init).joined(separator: ",")]])
    }

    // MARK: global options

    func applyGlobalOptions() {
        run("aria2.changeGlobalOption", [Prefs.liveOptions])
    }

    func setSpeedMode(_ mode: String) {
        speedMode = mode
        Prefs.speedMode = mode
        applyGlobalOptions()
    }

    func toggleLimitMode() {
        setSpeedMode(limitMode ? "full" : "limited")
    }

    /// Adds bytes downloaded/uploaded since the last poll to today's totals.
    private func countTransfer(_ list: [DLTask]) {
        var down: Int64 = 0, up: Int64 = 0
        let firstPoll = lastDone.isEmpty && lastUp.isEmpty && !primedStats
        for t in list where !t.isMetadata {
            if let p = lastDone[t.id] { if t.completed > p { down += t.completed - p } }
            else if !firstPoll { down += t.completed }   // new task that already has bytes
            if let p = lastUp[t.id], t.uploaded > p { up += t.uploaded - p }
        }
        lastDone = Dictionary(list.map { ($0.id, $0.completed) }, uniquingKeysWith: { a, _ in a })
        lastUp = Dictionary(list.map { ($0.id, $0.uploaded) }, uniquingKeysWith: { a, _ in a })
        primedStats = true
        guard down > 0 || up > 0 else { return }
        stats.add(down: down, up: up)
        if Date().timeIntervalSince(lastStatsSave) > 10 { stats.save(); lastStatsSave = Date() }
    }
    private var primedStats = false

    func saveStats() { stats.save() }

    /// For settings aria2 only reads at launch (ports, key).
    func restartEngine() {
        Task {
            engineOK = false
            _ = try? await rpc.call("aria2.saveSession")
            engine.restart()
            rpc = Aria2RPC(port: Prefs.rpcPort, secret: Prefs.secret)
            try? await Task.sleep(nanoseconds: 600_000_000)
            await refresh()
        }
    }

    func resetSession() {
        Task {
            _ = try? await rpc.call("aria2.forcePauseAll")
            engine.resetSession()
            try? await Task.sleep(nanoseconds: 600_000_000)
            await refresh()
        }
    }

    func syncTrackers(force: Bool) async {
        guard force || (Prefs.autoSyncTrackers && Date().timeIntervalSince1970 - Prefs.lastTrackerSync > 86_400) else { return }
        trackerStatus = "Updating…"
        let sources = ["https://cdn.jsdelivr.net/gh/ngosang/trackerslist@master/trackers_best.txt",
                       "https://cdn.jsdelivr.net/gh/ngosang/trackerslist@master/trackers_best_ip.txt"]
        var found: [String] = []
        for s in sources {
            guard let url = URL(string: s), let (data, _) = try? await URLSession.shared.data(from: url) else { continue }
            for line in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
                let t = line.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty, !found.contains(t) { found.append(t) }
            }
        }
        guard !found.isEmpty else { trackerStatus = "Couldn't reach the tracker list."; return }
        Prefs.trackers = found.joined(separator: "\n")
        Prefs.lastTrackerSync = Date().timeIntervalSince1970
        trackerStatus = "\(found.count) trackers, updated just now"
        applyGlobalOptions()
    }

    // MARK: appearance

    func applyAppearance() {
        switch Prefs.theme {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
        NSApp.setActivationPolicy(Prefs.showInDock ? .regular : .accessory)
    }

    // MARK: Finder

    func reveal(_ t: DLTask) {
        if FileManager.default.fileExists(atPath: t.path) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: t.path)])
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: t.dir))
        }
    }

    func open(_ t: DLTask) {
        guard t.status == "complete", FileManager.default.fileExists(atPath: t.path) else { reveal(t); return }
        NSWorkspace.shared.open(URL(fileURLWithPath: t.path))
    }

    func copyLink(_ t: DLTask) {
        guard let l = t.link else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(l, forType: .string)
    }
}

/// Draws the app icon with a progress bar for the Dock.
final class DockProgressView: NSView {
    var progress: Double = -1 { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        NSApp.applicationIconImage?.draw(in: bounds)
        guard progress >= 0 else { return }
        let bar = NSRect(x: bounds.width * 0.12, y: bounds.height * 0.06, width: bounds.width * 0.76, height: bounds.height * 0.11)
        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: bar, xRadius: bar.height / 2, yRadius: bar.height / 2).fill()
        var fill = bar.insetBy(dx: 3, dy: 3)
        fill.size.width = max(fill.height, fill.width * progress)
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: fill, xRadius: fill.height / 2, yRadius: fill.height / 2).fill()
    }
}

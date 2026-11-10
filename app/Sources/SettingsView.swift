import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    /// true when shown as a page in the main window rather than the ⌘, window
    var embedded = false
    @AppStorage("settingsTab") private var tab = "general"

    private let tabs: [(id: String, title: String, icon: String)] = [
        ("general", "General", "gearshape"),
        ("transfers", "Transfers", "arrow.up.arrow.down"),
        ("bittorrent", "BitTorrent", "point.3.connected.trianglepath.dotted"),
        ("network", "Network", "network"),
        ("browser", "Browser", "globe"),
    ]

    var body: some View {
        if embedded {
            VStack(alignment: .leading, spacing: 12) {
                Text("Settings").font(.system(size: 26, weight: .bold))
                    .padding(.horizontal, 22).padding(.top, 18)
                // Full labels when they fit, icons only in a narrow window
                ViewThatFits(in: .horizontal) {
                    tabBar(labels: true)
                    tabBar(labels: false)
                }
                .padding(.horizontal, 22)
                page
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
            }
            .background(Color(nsColor: .underPageBackgroundColor).opacity(0.5))
        } else {
            TabView(selection: $tab) {
                ForEach(tabs, id: \.id) { t in
                    content(t.id).tabItem { Label(t.title, systemImage: t.icon) }.tag(t.id)
                }
            }
            .frame(width: 560)
        }
    }

    @ViewBuilder private var page: some View { content(tab) }

    private func tabBar(labels: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(tabs, id: \.id) { t in
                Button { tab = t.id } label: {
                    Group {
                        if labels { Label(t.title, systemImage: t.icon) } else { Image(systemName: t.icon) }
                    }
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, labels ? 12 : 10).padding(.vertical, 6)
                    .foregroundStyle(tab == t.id ? Color.white : Color.primary)
                    .background(Capsule().fill(tab == t.id ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.clear)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(t.title)
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.06), in: Capsule())
        .fixedSize()
    }

    @ViewBuilder private func content(_ id: String) -> some View {
        switch id {
        case "transfers": TransferSettings()
        case "bittorrent": TorrentSettings()
        case "network": NetworkSettings()
        case "browser": BrowserSettings()
        default: GeneralSettings()
        }
    }
}

// MARK: - General

struct GeneralSettings: View {
    @EnvironmentObject var store: Store
    @Local private var theme = Prefs.theme
    @Local private var showInDock = Prefs.showInDock
    @Local private var menuBarSpeed = Prefs.menuBarSpeed
    @Local private var dockProgress = Prefs.dockProgress
    @Local private var atLogin = SMAppService.mainApp.status == .enabled
    @Local private var autoResume = Prefs.autoResumeAll
    @Local private var showDownloading = Prefs.showDownloadingAfterAdd
    @Local private var confirmDelete = Prefs.confirmDelete
    @Local private var notify = Prefs.notify
    @Local private var preventSleep = Prefs.preventSleep
    @Local private var loginError: String? = nil

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $theme) {
                    Text("Match system").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                Toggle("Show in Dock (off = menu bar only)", isOn: $showInDock)
                Toggle("Show download speed in the menu bar", isOn: $menuBarSpeed)
                Toggle("Show progress bar on the Dock icon", isOn: $dockProgress)
            }
            Section("Startup") {
                Toggle("Open at login", isOn: $atLogin)
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
                Toggle("Resume all downloads when Swift DM opens", isOn: $autoResume)
            }
            Section("Downloads") {
                Toggle("Switch to Downloading after adding a download", isOn: $showDownloading)
                Toggle("Ask before removing a download", isOn: $confirmDelete)
                Toggle("Notify when downloads finish or fail", isOn: $notify)
                Toggle("Keep the Mac awake while downloading", isOn: $preventSleep)
            }
        }
        .formStyle(.grouped)
        .onChange(of: theme) { _, v in Prefs.theme = v; store.applyAppearance() }
        .onChange(of: showInDock) { _, v in Prefs.showInDock = v; store.applyAppearance() }
        .onChange(of: menuBarSpeed) { _, v in Prefs.menuBarSpeed = v; store.objectWillChange.send() }
        .onChange(of: dockProgress) { _, v in Prefs.dockProgress = v }
        .onChange(of: autoResume) { _, v in Prefs.autoResumeAll = v }
        .onChange(of: showDownloading) { _, v in Prefs.showDownloadingAfterAdd = v }
        .onChange(of: confirmDelete) { _, v in Prefs.confirmDelete = v }
        .onChange(of: notify) { _, v in Prefs.notify = v }
        .onChange(of: preventSleep) { _, v in Prefs.preventSleep = v }
        .onChange(of: atLogin) { _, on in
            do {
                if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                loginError = nil
            } catch {
                loginError = "Couldn't change the login item: \(error.localizedDescription). Move Swift DM to Applications and try again."
            }
        }
    }
}

// MARK: - Transfers

struct TransferSettings: View {
    @EnvironmentObject var store: Store
    @Local private var dir = Prefs.downloadDir
    @Local private var maxConcurrent = Prefs.maxConcurrent
    @Local private var connections = Prefs.connections
    @Local private var downLimit = Prefs.downLimitKB
    @Local private var upLimit = Prefs.upLimitKB
    @Local private var userAgent = Prefs.userAgent

    private let limits = [64, 128, 256, 512, 1024, 2048, 5120, 10240, 20480, 51200]

    var body: some View {
        Form {
            Section("Location") {
                LabeledContent("Download folder") {
                    HStack {
                        Text((dir as NSString).abbreviatingWithTildeInPath).lineLimit(1).truncationMode(.head).foregroundStyle(.secondary)
                        Button("Choose…") { choose() }
                    }
                }
            }
            Section("Tasks") {
                Stepper("Simultaneous downloads: \(maxConcurrent)", value: $maxConcurrent, in: 1...20)
                Stepper("Connections per file: \(connections)", value: $connections, in: 1...16)
            }
            Section {
                Picker("Download limit", selection: $downLimit) { ForEach(limits, id: \.self) { Text(Fmt.limit($0)).tag($0) } }
                Picker("Upload limit", selection: $upLimit) { ForEach(limits, id: \.self) { Text(Fmt.limit($0)).tag($0) } }
                Toggle("Speed limit is on", isOn: Binding(get: { store.limitMode }, set: { _ in store.toggleLimitMode() }))
            } header: {
                Text("Speed limit")
            } footer: {
                Text("Turn limits on or off anytime with the tortoise button in the sidebar, the menu bar, or ⇧⌘L.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Identity") {
                Picker("User-Agent", selection: Binding(
                    get: { Prefs.userAgentPresets.first { $0.1 == userAgent }?.0 ?? "Custom" },
                    set: { name in if let p = Prefs.userAgentPresets.first(where: { $0.0 == name }) { userAgent = p.1 } })) {
                    ForEach(Prefs.userAgentPresets, id: \.0) { Text($0.0).tag($0.0) }
                    Text("Custom").tag("Custom")
                }
                TextField("", text: $userAgent).font(.system(.caption, design: .monospaced))
            }
        }
        .formStyle(.grouped)
        .onChange(of: maxConcurrent) { _, v in Prefs.maxConcurrent = v; store.applyGlobalOptions() }
        .onChange(of: connections) { _, v in Prefs.connections = v; store.applyGlobalOptions() }
        .onChange(of: downLimit) { _, v in Prefs.downLimitKB = v; store.applyGlobalOptions() }
        .onChange(of: upLimit) { _, v in Prefs.upLimitKB = v; store.applyGlobalOptions() }
        .onChange(of: userAgent) { _, v in Prefs.userAgent = v; store.applyGlobalOptions() }
        .onAppear {
            if Prefs.downLimitKB == 0 { downLimit = 5120; Prefs.downLimitKB = 5120 }
            if Prefs.upLimitKB == 0 { upLimit = 1024; Prefs.upLimitKB = 1024 }
        }
    }

    private func choose() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.canCreateDirectories = true
        p.directoryURL = URL(fileURLWithPath: dir)
        if p.runModal() == .OK, let u = p.url {
            dir = u.path
            Prefs.downloadDir = u.path
            Prefs.rememberDir(u.path)
            store.applyGlobalOptions()
        }
    }
}

// MARK: - BitTorrent

struct TorrentSettings: View {
    @EnvironmentObject var store: Store
    @Local private var saveMetadata = Prefs.btSaveMetadata
    @Local private var autoDownload = Prefs.btAutoDownload
    @Local private var forceEncryption = Prefs.btForceEncryption
    @Local private var keepSeeding = Prefs.keepSeeding
    @Local private var seedRatio = Prefs.seedRatio
    @Local private var seedMinutes = Prefs.seedMinutes
    @Local private var trackers = Prefs.trackers
    @Local private var autoSync = Prefs.autoSyncTrackers

    var body: some View {
        Form {
            Section("Torrents") {
                Toggle("Save .torrent file for magnet links", isOn: $saveMetadata)
                Toggle("Start downloading as soon as magnet info arrives", isOn: $autoDownload)
                Toggle("Require encrypted connections", isOn: $forceEncryption)
            }
            Section("Seeding") {
                Toggle("Keep seeding after download finishes", isOn: $keepSeeding)
                if !keepSeeding {
                    Stepper("Stop at share ratio \(String(format: "%.1f", seedRatio))", value: $seedRatio, in: 0.1...10, step: 0.1)
                    Stepper("…or after \(seedMinutes) minutes", value: $seedMinutes, in: 0...10080, step: 10)
                }
            }
            Section {
                TextEditor(text: $trackers)
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 110)
                HStack {
                    Toggle("Update daily", isOn: $autoSync)
                    Spacer()
                    Text(store.trackerStatus.isEmpty ? "\(Prefs.trackerList.count) trackers" : store.trackerStatus)
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Update Now") { Task { await store.syncTrackers(force: true); trackers = Prefs.trackers } }
                }
            } header: {
                Text("Extra trackers")
            } footer: {
                Text("Added to every torrent so magnets find peers faster. The list comes from ngosang/trackerslist.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: saveMetadata) { _, v in Prefs.btSaveMetadata = v; store.applyGlobalOptions() }
        .onChange(of: autoDownload) { _, v in Prefs.btAutoDownload = v; store.applyGlobalOptions() }
        .onChange(of: forceEncryption) { _, v in Prefs.btForceEncryption = v; store.applyGlobalOptions() }
        .onChange(of: keepSeeding) { _, v in Prefs.keepSeeding = v; store.applyGlobalOptions() }
        .onChange(of: seedRatio) { _, v in Prefs.seedRatio = v; store.applyGlobalOptions() }
        .onChange(of: seedMinutes) { _, v in Prefs.seedMinutes = v; store.applyGlobalOptions() }
        .onChange(of: autoSync) { _, v in Prefs.autoSyncTrackers = v }
        .onDisappear {
            if trackers != Prefs.trackers { Prefs.trackers = trackers; store.applyGlobalOptions() }
        }
    }
}

// MARK: - Network

struct NetworkSettings: View {
    @EnvironmentObject var store: Store
    @Local private var proxyEnabled = Prefs.proxyEnabled
    @Local private var proxyServer = Prefs.proxyServer
    @Local private var proxyBypass = Prefs.proxyBypass
    @Local private var rpcPort = Prefs.rpcPort
    @Local private var btPort = Prefs.btPort
    @Local private var dhtPort = Prefs.dhtPort
    @Local private var portsChanged = false
    @Local private var magnetStatus = ""
    @Local private var confirmReset = false

    var body: some View {
        Form {
            Section("Proxy") {
                Toggle("Use a proxy for downloads", isOn: $proxyEnabled)
                TextField("Server", text: $proxyServer, prompt: Text("http://user:pass@host:port"))
                    .disabled(!proxyEnabled)
                TextField("Bypass", text: $proxyBypass, prompt: Text("localhost, *.lan, 192.168.0.0/16"))
                    .disabled(!proxyEnabled)
                Button("Apply Proxy") {
                    Prefs.proxyEnabled = proxyEnabled
                    Prefs.proxyServer = proxyServer.trimmingCharacters(in: .whitespaces)
                    Prefs.proxyBypass = proxyBypass
                    store.applyGlobalOptions()
                }
            }
            Section {
                portField("Engine (RPC) port", $rpcPort)
                portField("BitTorrent port", $btPort)
                portField("DHT port", $dhtPort)
                if portsChanged {
                    Button("Restart Engine to Apply") {
                        Prefs.rpcPort = rpcPort
                        Prefs.btPort = btPort
                        Prefs.dhtPort = dhtPort
                        portsChanged = false
                        store.restartEngine()
                    }
                }
            } header: {
                Text("Ports")
            } footer: {
                Text("If you change the engine port, update it in the Chrome extension too.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Links") {
                HStack {
                    Button("Make Swift DM the Default for Magnet Links") { setMagnetHandler() }
                    Text(magnetStatus).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Maintenance") {
                HStack {
                    Button("Show Engine Files") {
                        NSWorkspace.shared.activateFileViewerSelecting([Engine.confURL, Engine.sessionURL, Engine.logURL])
                    }
                    Button("Restart Engine") { store.restartEngine() }
                    Spacer()
                    Button("Reset Download List…", role: .destructive) { confirmReset = true }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: rpcPort) { _, _ in portsChanged = true }
        .onChange(of: btPort) { _, _ in portsChanged = true }
        .onChange(of: dhtPort) { _, _ in portsChanged = true }
        .confirmationDialog("Clear every download from the list?", isPresented: $confirmReset) {
            Button("Reset Download List", role: .destructive) { store.resetSession() }
        } message: {
            Text("Unfinished downloads are forgotten. Files already on disk are kept.")
        }
    }

    private func portField(_ label: String, _ value: Binding<Int>) -> some View {
        LabeledContent(label) {
            TextField("", value: value, format: .number.grouping(.never))
                .frame(width: 80)
                .multilineTextAlignment(.trailing)
        }
    }

    private func setMagnetHandler() {
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: "magnet") { error in
            DispatchQueue.main.async { magnetStatus = error == nil ? "Done ✓" : "Couldn't set: \(error!.localizedDescription)" }
        }
    }
}

// MARK: - Browser

struct BrowserSettings: View {
    @EnvironmentObject var store: Store
    @Local private var copied = false
    @Local private var secret = Prefs.secret

    var body: some View {
        Form {
            Section {
                Text("The Swift DM extension catches Chrome downloads and sends them here. Paste this key into the extension's popup once to connect it.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text(secret).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    Spacer()
                    Button(copied ? "Copied ✓" : "Copy Key") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(secret, forType: .string)
                        copied = true
                    }
                }
                LabeledContent("Engine address", value: "http://127.0.0.1:\(Prefs.rpcPort)/jsonrpc")
            } header: {
                Text("Chrome extension")
            }
            Section {
                Button("Make a New Key") {
                    Prefs.secret = Prefs.newSecret()
                    secret = Prefs.secret
                    copied = false
                    store.restartEngine()
                }
            } footer: {
                Text("Disconnects the extension until you paste the new key into it.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

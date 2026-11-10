import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct NewTaskRequest: Identifiable {
    let id = UUID()
    var links = ""
    var torrent: (name: String, data: Data)?
}

enum SidebarPage: Hashable {
    case dashboard
    case list(Category)
    case settings
}

struct MainView: View {
    @EnvironmentObject var store: Store
    @Local private var page: SidebarPage = .dashboard
    private var category: Category { if case .list(let c) = page { return c }; return .downloading }
    @Local private var selection: String? = nil
    @Local private var search = ""
    @Local private var showInspector = false
    @Local private var newTask: NewTaskRequest? = nil
    @Local private var confirmRemove: DLTask? = nil
    @Local private var dropping = false

    var body: some View {
        NavigationSplitView {
            Sidebar(page: Binding(get: { page }, set: { page = $0 }))
                .navigationSplitViewColumnWidth(min: 210, ideal: 225, max: 280)
        } detail: {
            if page == .settings {
                SettingsView(embedded: true)
                    .navigationTitle("Settings")
            } else if page == .dashboard {
                DashboardView(openNew: { openNew() }, showDownloads: { page = .list(.downloading) })
                    .navigationTitle("Dashboard")
            } else {
            VStack(spacing: 0) {
                if let banner = store.errorBanner {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(banner).lineLimit(2)
                        Spacer()
                        Button("Dismiss") { store.errorBanner = nil }.buttonStyle(.borderless)
                    }
                    .padding(10)
                    .background(.orange.opacity(0.12))
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        taskList
                    }
                    .padding(18)
                }
                .background(Color(nsColor: .underPageBackgroundColor).opacity(0.5))
                .overlay { if dropping { dropOverlay } }
            }
            .navigationTitle(category.rawValue)
            .searchable(text: $search, placement: .toolbar, prompt: "Search downloads")
            .toolbar { toolbar }
            .inspector(isPresented: $showInspector) {
                DetailView(gid: selection)
                    .inspectorColumnWidth(min: 300, ideal: 340, max: 480)
            }
            }
        }
        .sheet(item: $newTask) { req in NewTaskSheet(request: req) }
        .confirmationDialog("Remove “\(confirmRemove?.name ?? "")”?",
                            isPresented: Binding(get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } })) {
            Button("Remove from list") { if let t = confirmRemove { store.remove(t, deleteFiles: false) } }
            Button("Remove and move files to Trash", role: .destructive) { if let t = confirmRemove { store.remove(t, deleteFiles: true) } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newTask)) { _ in openNew() }
        .onReceive(NotificationCenter.default.publisher(for: .openTorrent)) { _ in chooseTorrent() }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsPage)) { note in
            if let tab = note.object as? String { UserDefaults.standard.set(tab, forKey: "settingsTab") }
            page = .settings
        }
        .onChange(of: store.requestedCategory) { _, c in
            if let c, case .list = page { page = .list(c) }
            store.requestedCategory = nil
        }
        .onDrop(of: [.fileURL, .url, .plainText], isTargeted: Binding(get: { dropping }, set: { dropping = $0 })) { handleDrop($0) }
        .onDeleteCommand { if let t = store.task(selection) { askRemove(t) } }
    }

    // MARK: list

    private var filtered: [DLTask] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return store.tasks(in: category).filter { q.isEmpty || $0.name.lowercased().contains(q) || ($0.uri ?? "").lowercased().contains(q) }
    }

    @ViewBuilder private var taskList: some View {
        let items = filtered
        if items.isEmpty {
            emptyState
        } else {
            LazyVStack(spacing: 10) {
                ForEach(items) { t in
                    TaskCard(task: t, selected: selection == t.id, onRemove: { askRemove(t) })
                        .onTapGesture(count: 2) { store.open(t) }
                        .onTapGesture { selection = t.id }
                        .contextMenu { contextMenu(t) }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.15)).frame(width: 96, height: 96)
                Image(systemName: search.isEmpty ? category.icon : "magnifyingglass")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }
            Text(emptyTitle).font(.title3.weight(.semibold))
            Text(emptyText).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 340)
            if category == .downloading && search.isEmpty {
                Button { openNew() } label: {
                    Label("New Download", systemImage: "plus")
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 18).padding(.vertical, 9)
                        .foregroundStyle(.white)
                        .background(Theme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
    }

    private var emptyTitle: String {
        if !search.isEmpty { return "No matches" }
        switch category {
        case .downloading: return "Nothing downloading"
        case .waiting: return "Queue is empty"
        case .completed: return "No finished downloads"
        case .stopped: return "All clear"
        }
    }

    private var emptyText: String {
        if !search.isEmpty { return "Nothing matches “\(search)”." }
        switch category {
        case .downloading: return "Press ⌘N, drop a link, magnet or .torrent anywhere here, or download something in Chrome."
        case .waiting: return "Paused and queued downloads show up here."
        case .completed: return "Finished downloads will appear here."
        case .stopped: return "No stopped or failed downloads."
        }
    }

    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
            .background(RoundedRectangle(cornerRadius: 18).fill(Theme.blue.opacity(0.08)))
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill").font(.system(size: 44)).foregroundStyle(Theme.accent)
                    Text("Drop to download").font(.title3.weight(.semibold))
                }
            }
            .padding(12)
            .allowsHitTesting(false)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Menu {
                Button("New Download…") { openNew() }
                Button("Open Torrent File…") { chooseTorrent() }
            } label: { Label("New", systemImage: "plus") } primaryAction: { openNew() }
            .help("New download (⌘N)")
            Button { store.resumeAll() } label: { Label("Resume All", systemImage: "play") }.help("Resume all")
            Button { store.pauseAll() } label: { Label("Pause All", systemImage: "pause") }.help("Pause all")
            Button { store.purge() } label: { Label("Clear", systemImage: "trash") }.help("Clear finished and stopped records")
            Button { showInspector.toggle() } label: { Label("Details", systemImage: "sidebar.right") }.help("Show details")
        }
    }

    @ViewBuilder private func contextMenu(_ t: DLTask) -> some View {
        if t.status == "complete" { Button("Open") { store.open(t) } }
        Button("Show in Finder") { store.reveal(t) }
        Button("Show Details") { selection = t.id; showInspector = true }
        if t.link != nil { Button(t.isTorrent ? "Copy Magnet Link" : "Copy Link") { store.copyLink(t) } }
        Divider()
        if t.status == "active" || t.status == "waiting" { Button("Pause") { store.pause(t) } }
        if t.status == "paused" { Button("Resume") { store.resume(t) } }
        Button("Restart") { store.restart(t) }
        Divider()
        Button("Remove…") { askRemove(t) }
        Button("Remove and Delete Files", role: .destructive) { store.remove(t, deleteFiles: true) }
    }

    // MARK: actions

    private func askRemove(_ t: DLTask) {
        if Prefs.confirmDelete { confirmRemove = t } else { store.remove(t, deleteFiles: false) }
    }

    private func openNew() {
        let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lines = clip.split(whereSeparator: \.isNewline).map(String.init)
        let useClip = !lines.isEmpty && lines.allSatisfy(NewTaskSheet.isDownloadable)
        newTask = NewTaskRequest(links: useClip ? clip : "")
    }

    private func chooseTorrent() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [UTType(filenameExtension: "torrent") ?? .data]
        guard p.runModal() == .OK, let u = p.url, let d = try? Data(contentsOf: u) else { return }
        newTask = NewTaskRequest(torrent: (u.lastPathComponent, d))
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for p in providers {
            if p.canLoadObject(ofClass: URL.self) {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in
                        if url.isFileURL, url.pathExtension.lowercased() == "torrent", let d = try? Data(contentsOf: url) {
                            newTask = NewTaskRequest(torrent: (url.lastPathComponent, d))
                        } else if !url.isFileURL {
                            newTask = NewTaskRequest(links: url.absoluteString)
                        }
                    }
                }
            } else {
                _ = p.loadObject(ofClass: String.self) { s, _ in
                    guard let s, NewTaskSheet.isDownloadable(s) else { return }
                    Task { @MainActor in newTask = NewTaskRequest(links: s) }
                }
            }
        }
        return true
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @EnvironmentObject var store: Store
    @Binding var page: SidebarPage

    var body: some View {
        List(selection: Binding<SidebarPage?>(get: { page }, set: { if let p = $0 { page = p } })) {
            Label {
                Text("Dashboard")
            } icon: {
                Image(systemName: "square.grid.2x2.fill").foregroundStyle(Theme.violet)
            }
            .tag(SidebarPage.dashboard)

            Section("Downloads") {
                ForEach(Category.allCases) { c in
                    HStack(spacing: 10) {
                        Image(systemName: c.icon + ".fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(color(c))
                            .frame(width: 20)
                        Text(c.rawValue)
                        Spacer()
                        let n = store.tasks(in: c).count
                        if n > 0 {
                            Text("\(n)")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(color(c).opacity(0.16), in: Capsule())
                                .foregroundStyle(color(c))
                        }
                    }
                    .tag(SidebarPage.list(c))
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                speedCard
                settingsRow
            }
        }
    }

    private func color(_ c: Category) -> Color {
        switch c {
        case .downloading: return Theme.blue
        case .waiting: return .orange
        case .completed: return .green
        case .stopped: return .red
        }
    }

    private var settingsRow: some View {
        let on = page == .settings
        return Button { page = .settings } label: {
            HStack(spacing: 10) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(on ? Color.white : Color.secondary)
                    .frame(width: 20)
                Text("Settings").foregroundStyle(on ? Color.white : Color.primary)
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(on ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .keyboardShortcut(",", modifiers: [.command, .option])
        .help("Settings (⌥⌘,)")
    }

    private var speedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(Fmt.speed(store.downSpeed), systemImage: "arrow.down")
                Spacer()
                Label(Fmt.speed(store.upSpeed), systemImage: "arrow.up")
            }
            .font(.caption.weight(.semibold)).monospacedDigit()
            SpeedGraph(samples: store.speedHistory, lineWidth: 1.5).frame(height: 30)
            Button { store.toggleLimitMode() } label: {
                HStack {
                    Image(systemName: store.limitMode ? "tortoise.fill" : "hare.fill")
                    Text(store.limitMode ? "Speed limit on" : "Full speed")
                    Spacer()
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .foregroundStyle(store.limitMode ? Color.orange : Theme.blue)
                .background((store.limitMode ? Color.orange : Theme.blue).opacity(0.13), in: Capsule())
            }
            .buttonStyle(.plain)
            .help(store.limitMode ? "Limits: ↓ \(Fmt.limit(Prefs.downLimitKB))  ↑ \(Fmt.limit(Prefs.upLimitKB)). Click for full speed."
                                  : "Click to apply the speed limits from Settings (⇧⌘L)")
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
        .padding(10)
    }
}

// MARK: - Task card

struct TaskCard: View {
    @EnvironmentObject var store: Store
    let task: DLTask
    let selected: Bool
    let onRemove: () -> Void
    @Local private var hover = false

    var body: some View {
        let kind = FileKind(task)
        let (statusText, statusColor) = Theme.status(for: task)

        HStack(spacing: 14) {
            KindIcon(kind: kind)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(task.name)
                        .font(.system(size: 13.5, weight: .semibold))
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 6)
                    StatusPill(text: statusText, color: statusColor)
                }
                if task.status != "complete" {
                    GradientProgress(value: task.progress, style: Theme.gradient(for: task),
                                     glow: task.status == "active" ? (task.isSeeding ? .green : Theme.blue) : .clear)
                }
                HStack {
                    Text(leftMeta).foregroundStyle(task.status == "error" ? Color.red : Color.secondary)
                    Spacer()
                    Text(rightMeta).foregroundStyle(.secondary)
                }
                .font(.system(size: 11.5)).monospacedDigit().lineLimit(1)
            }
            HStack(spacing: 6) { actions }
                .opacity(hover || selected ? 1 : 0.35)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.primary.opacity(hover ? 0.2 : 0.07)),
                              lineWidth: selected ? 1.6 : 1)
        )
        .animation(.easeOut(duration: 0.15), value: hover)
        .onHover { hover = $0 }
        .contentShape(Rectangle())
    }

    @ViewBuilder private var actions: some View {
        switch task.status {
        case "active", "waiting": CircleButton(symbol: "pause.fill", help: "Pause", tint: .orange) { store.pause(task) }
        case "paused": CircleButton(symbol: "play.fill", help: "Resume", tint: Theme.blue) { store.resume(task) }
        case "error", "removed": CircleButton(symbol: "arrow.clockwise", help: "Restart", tint: Theme.blue) { store.restart(task) }
        default: CircleButton(symbol: "magnifyingglass", help: "Show in Finder", tint: Theme.blue) { store.reveal(task) }
        }
        if task.link != nil {
            CircleButton(symbol: "link", help: task.isTorrent ? "Copy magnet link" : "Copy link", tint: Theme.violet) { store.copyLink(task) }
        }
        CircleButton(symbol: "xmark", help: "Remove", tint: .red) { onRemove() }
    }

    private var size: String {
        task.total > 0 ? "\(Fmt.bytes(task.completed)) of \(Fmt.bytes(task.total))" : Fmt.bytes(task.completed)
    }

    private var leftMeta: String {
        switch task.status {
        case "active":
            if task.isSeeding { return "Ratio \(String(format: "%.2f", task.ratio))  ·  \(task.connections) peers" }
            return "\(size)  ·  " + (task.isTorrent || task.isMetadata ? "\(task.seeders) seeds, \(task.connections) peers" : "\(task.connections) connections")
        case "waiting", "paused", "removed": return size
        case "error": return task.errorMessage ?? "Failed (error \(task.errorCode))"
        default: return "\(Fmt.bytes(task.total))  ·  \((task.dir as NSString).abbreviatingWithTildeInPath)"
        }
    }

    private var rightMeta: String {
        switch task.status {
        case "active":
            if task.isSeeding { return "↑ \(Fmt.speed(task.upload))" }
            var s = "↓ \(Fmt.speed(task.speed))"
            if let e = task.eta { s += "  ·  \(Fmt.time(e)) left" }
            return s
        case "waiting", "paused", "removed": return "\(Int(task.progress * 100))%"
        default: return ""
        }
    }
}

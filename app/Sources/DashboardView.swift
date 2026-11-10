import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Model

enum WidgetSize: String, CaseIterable {
    case small, wide, tall, large, xl, full

    var cols: Int { switch self { case .small, .tall: 1; case .wide, .large: 2; case .xl: 3; case .full: 4 } }
    var rows: Int { switch self { case .small, .wide, .full: 1; case .tall, .large, .xl: 2 } }
    var icon: String {
        switch self {
        case .small: return "square"
        case .wide: return "rectangle"
        case .tall: return "rectangle.portrait"
        case .large: return "square.grid.2x2"
        case .xl: return "rectangle.split.3x1"
        case .full: return "rectangle.split.1x2"
        }
    }
    var label: String {
        switch self {
        case .small: return "Small"
        case .wide: return "Wide"
        case .tall: return "Tall"
        case .large: return "Large"
        case .xl: return "Extra large"
        case .full: return "Full width"
        }
    }
}

enum WidgetKind: String, CaseIterable, Identifiable {
    case engine, speedMode, download, upload, activeTasks, transfer, activity, tasks, storage
    var id: String { rawValue }

    var title: String {
        switch self {
        case .engine: return "Engine"
        case .speedMode: return "Speed Mode"
        case .download: return "Download"
        case .upload: return "Upload"
        case .activeTasks: return "Active Tasks"
        case .transfer: return "Transfer"
        case .activity: return "Activity"
        case .tasks: return "Tasks"
        case .storage: return "Storage"
        }
    }

    var icon: String {
        switch self {
        case .engine: return "cpu"
        case .speedMode: return "gauge.with.dots.needle.67percent"
        case .download: return "arrow.down.circle"
        case .upload: return "arrow.up.circle"
        case .activeTasks: return "bolt.circle"
        case .transfer: return "arrow.up.arrow.down.circle"
        case .activity: return "calendar"
        case .tasks: return "list.bullet.rectangle"
        case .storage: return "internaldrive"
        }
    }

    var sizes: [WidgetSize] {
        switch self {
        case .engine, .speedMode, .storage: return [.small, .wide]
        case .download, .upload: return [.small, .wide, .tall, .large]
        case .activeTasks, .transfer: return [.small, .wide]
        case .activity: return [.wide, .full]
        case .tasks: return [.wide, .large, .xl, .full]
        }
    }
}

struct WidgetItem: Identifiable, Equatable {
    var kind: WidgetKind
    var size: WidgetSize
    var id: String { kind.rawValue }

    var encoded: String { "\(kind.rawValue):\(size.rawValue)" }
    init(_ kind: WidgetKind, _ size: WidgetSize) { self.kind = kind; self.size = size }
    init?(encoded: String) {
        let p = encoded.split(separator: ":").map(String.init)
        guard p.count == 2, let k = WidgetKind(rawValue: p[0]), let s = WidgetSize(rawValue: p[1]) else { return nil }
        self.init(k, s)
    }
}

enum DashboardPreset: String, CaseIterable, Identifiable {
    case balanced = "Balanced", taskFocus = "Task Focus", speedFocus = "Speed Focus", compact = "Compact"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .balanced: return "square.grid.3x2"
        case .taskFocus: return "rectangle.leadinghalf.inset.filled"
        case .speedFocus: return "chart.xyaxis.line"
        case .compact: return "square.grid.4x3.fill"
        }
    }

    var items: [WidgetItem] {
        switch self {
        case .balanced:
            return [.init(.engine, .small), .init(.speedMode, .small), .init(.upload, .small), .init(.download, .small),
                    .init(.activeTasks, .wide), .init(.transfer, .wide), .init(.activity, .full)]
        case .taskFocus:
            return [.init(.engine, .small), .init(.speedMode, .small), .init(.activeTasks, .small), .init(.transfer, .small),
                    .init(.upload, .small), .init(.tasks, .xl), .init(.download, .small)]
        case .speedFocus:
            return [.init(.download, .large), .init(.upload, .large),
                    .init(.engine, .small), .init(.speedMode, .small), .init(.transfer, .wide)]
        case .compact:
            return [.init(.engine, .small), .init(.speedMode, .small), .init(.download, .small), .init(.upload, .small),
                    .init(.activeTasks, .small), .init(.transfer, .small), .init(.storage, .small), .init(.tasks, .wide)]
        }
    }
}

// MARK: - Grid layout (column/row spans, first-fit packing)

private struct SpanKey: LayoutValueKey {
    static let defaultValue = WidgetSize.small
}

struct DashboardGrid: Layout {
    var rowHeight: CGFloat = 150
    var spacing: CGFloat = 14

    private func frames(width: CGFloat, subviews: Subviews) -> ([CGRect], CGFloat) {
        let columns = width >= 640 ? 4 : 2
        let colW = (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        var taken: [[Bool]] = []
        var rects: [CGRect] = []

        func free(_ r: Int, _ c: Int, _ w: Int, _ h: Int) -> Bool {
            for rr in r..<(r + h) {
                for cc in c..<(c + w) where rr < taken.count && taken[rr][cc] { return false }
            }
            return true
        }

        for sv in subviews {
            let size = sv[SpanKey.self]
            let w = min(size.cols, columns), h = size.rows
            var placed = false
            var r = 0
            while !placed {
                for c in 0...(columns - w) where free(r, c, w, h) {
                    while taken.count < r + h { taken.append(Array(repeating: false, count: columns)) }
                    for rr in r..<(r + h) { for cc in c..<(c + w) { taken[rr][cc] = true } }
                    rects.append(CGRect(x: CGFloat(c) * (colW + spacing), y: CGFloat(r) * (rowHeight + spacing),
                                        width: colW * CGFloat(w) + spacing * CGFloat(w - 1),
                                        height: rowHeight * CGFloat(h) + spacing * CGFloat(h - 1)))
                    placed = true
                    break
                }
                r += 1
            }
        }
        let height = taken.isEmpty ? 0 : CGFloat(taken.count) * (rowHeight + spacing) - spacing
        return (rects, height)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 800
        return CGSize(width: width, height: frames(width: width, subviews: subviews).1)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (rects, _) = frames(width: bounds.width, subviews: subviews)
        for (sv, r) in zip(subviews, rects) {
            sv.place(at: CGPoint(x: bounds.minX + r.minX, y: bounds.minY + r.minY), anchor: .topLeading,
                     proposal: ProposedViewSize(width: r.width, height: r.height))
        }
    }
}

// MARK: - Dashboard page

struct DashboardView: View {
    @EnvironmentObject var store: Store
    let openNew: () -> Void
    let showDownloads: () -> Void

    @Local private var items: [WidgetItem] = DashboardView.savedItems()
    @Local private var editing = false
    @Local private var draft: [WidgetItem] = []
    @Local private var draftPreset = Prefs.dashboardPreset
    @Local private var dragging: String? = nil

    static func savedItems() -> [WidgetItem] {
        let saved = Prefs.dashboardLayout.compactMap(WidgetItem.init(encoded:))
        return saved.isEmpty ? (DashboardPreset(rawValue: Prefs.dashboardPreset) ?? .balanced).items : saved
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                DashboardGrid {
                    ForEach(editing ? draft : items) { item in
                        widget(item)
                            .layoutValue(key: SpanKey.self, value: item.size)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: editing ? draft : items)
            }
            .padding(22)
        }
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.5))
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 10) {
            Text("Dashboard").font(.system(size: 26, weight: .bold))
            Spacer()
            if editing {
                HStack(spacing: 2) {
                    pillButton("xmark", help: "Discard changes") { editing = false }
                    pillButton("arrow.counterclockwise", help: "Reset to preset") {
                        draft = (DashboardPreset(rawValue: draftPreset) ?? .balanced).items
                    }
                    Button { apply() } label: {
                        Label("Apply", systemImage: "checkmark").font(.callout.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color.primary.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(3)
                .background(Color.primary.opacity(0.06), in: Capsule())

                HStack(spacing: 0) {
                    Menu {
                        ForEach(DashboardPreset.allCases) { p in
                            Button {
                                draftPreset = p.rawValue
                                draft = p.items
                            } label: {
                                Label(p.rawValue, systemImage: draftPreset == p.rawValue ? "checkmark" : p.icon)
                            }
                        }
                    } label: {
                        Label(draftPreset, systemImage: "rectangle.3.group").font(.callout.weight(.semibold))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .padding(.horizontal, 12)

                    let hidden = WidgetKind.allCases.filter { k in !draft.contains { $0.kind == k } }
                    Menu {
                        if hidden.isEmpty { Text("Every widget is already shown") }
                        ForEach(hidden) { k in
                            Button { draft.append(WidgetItem(k, k.sizes[0])) } label: { Label(k.title, systemImage: k.icon) }
                        }
                    } label: { Image(systemName: "plus") }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .padding(.trailing, 10)
                    .help("Add a widget")
                }
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.06), in: Capsule())
            } else {
                Button { openNew() } label: {
                    Label("New Download", systemImage: "plus").font(.callout.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .foregroundStyle(.white)
                        .background(Theme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                pillButton("slider.horizontal.3", help: "Customize dashboard") {
                    draft = items
                    draftPreset = Prefs.dashboardPreset
                    editing = true
                }
            }
        }
    }

    private func pillButton(_ symbol: String, help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(Color.primary.opacity(0.06), in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func apply() {
        items = draft
        Prefs.dashboardLayout = draft.map(\.encoded)
        Prefs.dashboardPreset = draftPreset
        editing = false
    }

    // MARK: widgets

    @ViewBuilder private func widget(_ item: WidgetItem) -> some View {
        let card = WidgetCard(item: item, openNew: openNew, showDownloads: showDownloads)
            .allowsHitTesting(!editing)
        if editing {
            card
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.35), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                )
                .overlay(alignment: .topTrailing) { editControls(item) }
                .opacity(dragging == item.id ? 0.4 : 1)
                .onDrag {
                    dragging = item.id
                    return NSItemProvider(object: item.id as NSString)
                }
                .onDrop(of: [.text], delegate: ReorderDrop(target: item, items: $draft, dragging: $dragging))
        } else {
            card
        }
    }

    private func editControls(_ item: WidgetItem) -> some View {
        HStack(spacing: 2) {
            Image(systemName: "line.3.horizontal")
                .frame(width: 24, height: 24)
                .help("Drag to move")
            Button {
                draft.removeAll { $0.id == item.id }
            } label: { Image(systemName: "trash").frame(width: 24, height: 24) }
            .buttonStyle(.plain)
            .help("Remove widget")
            Menu {
                ForEach(item.kind.sizes, id: \.self) { s in
                    Button {
                        if let i = draft.firstIndex(where: { $0.id == item.id }) { draft[i].size = s }
                    } label: { Label(s.label, systemImage: item.size == s ? "checkmark" : s.icon) }
                }
            } label: { Image(systemName: item.size.icon).frame(width: 24, height: 24) }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Resize")
        }
        .font(.system(size: 11, weight: .semibold))
        .padding(3)
        .background(.regularMaterial, in: Capsule())
        .padding(8)
    }
}

private struct ReorderDrop: DropDelegate {
    let target: WidgetItem
    @Binding var items: [WidgetItem]
    @Binding var dragging: String?

    func dropEntered(info: DropInfo) {
        guard let d = dragging, d != target.id,
              let from = items.firstIndex(where: { $0.id == d }),
              let to = items.firstIndex(where: { $0.id == target.id }) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            items.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

// MARK: - Card shell

struct WidgetCard: View {
    @EnvironmentObject var store: Store
    let item: WidgetItem
    let openNew: () -> Void
    let showDownloads: () -> Void

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder private var content: some View {
        switch item.kind {
        case .engine: EngineWidget()
        case .speedMode: SpeedModeWidget(size: item.size)
        case .download: SpeedWidget(title: "Download", samples: store.speedHistory, current: store.downSpeed,
                                    colors: [Theme.blue, Theme.violet], size: item.size)
        case .upload: SpeedWidget(title: "Upload", samples: store.uploadHistory, current: store.upSpeed,
                                  colors: [Theme.green, Theme.teal], size: item.size)
        case .activeTasks: ActiveTasksWidget(size: item.size)
        case .transfer: TransferWidget(size: item.size)
        case .activity: ActivityWidget(size: item.size)
        case .tasks: TasksWidget(openNew: openNew, showDownloads: showDownloads)
        case .storage: StorageWidget()
        }
    }
}

/// Title row used by every widget.
private struct WidgetTitle<Trailing: View>: View {
    let text: String
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack {
            Text(text.uppercased()).font(.system(size: 11, weight: .semibold)).kerning(0.5).foregroundStyle(.secondary)
                .lineLimit(1).fixedSize()
            Spacer()
            trailing
        }
    }
}

private extension WidgetTitle where Trailing == EmptyView {
    init(_ text: String) { self.init(text: text) { EmptyView() } }
}

/// "12.4" + "MB/s" in two sizes, like the reference design.
private struct BigValue: View {
    let value: String
    let unit: String
    var size: CGFloat = 30
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value).font(.system(size: size, weight: .bold, design: .rounded)).monospacedDigit()
            Text(unit).font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

private func splitBytes(_ n: Int64, perSecond: Bool = false) -> (String, String) {
    let s = Fmt.bytes(n)
    let parts = s.split(separator: " ", maxSplits: 1).map(String.init)
    let unit = parts.count > 1 ? parts[1] : "B"
    return (parts.first ?? "0", perSecond ? unit + "/s" : unit)
}

// MARK: - Widgets

private struct EngineWidget: View {
    @EnvironmentObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetTitle(text: "Engine") {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([Engine.logURL, Engine.confURL])
                } label: { Image(systemName: "ladybug") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Show engine log and settings files")
            }
            Text(store.engineOK ? "Ready" : "Offline").font(.system(size: 26, weight: .bold))
            Spacer(minLength: 0)
            HStack {
                Text(store.engineVersion.isEmpty ? "aria2" : "aria2 v\(store.engineVersion.split(separator: "-").first ?? "")")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Circle().fill(store.engineOK ? Theme.green : .red).frame(width: 9, height: 9)
                    .overlay(Circle().stroke((store.engineOK ? Theme.green : .red).opacity(0.25), lineWidth: 4))
            }
        }
        .padding(16)
    }
}

private struct SpeedModeWidget: View {
    @EnvironmentObject var store: Store
    let size: WidgetSize

    private let modes: [(id: String, symbol: String, color: Color, name: String)] = [
        ("full", "hare.fill", Theme.blue, "Full speed"),
        ("limited", "tortoise.fill", Theme.green, "Limited"),
        ("quiet", "moon.zzz.fill", Theme.violet, "Quiet"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetTitle(text: "Speed Mode") { EmptyView() }
            HStack(spacing: 8) {
                ForEach(modes, id: \.id) { m in
                    let on = store.speedMode == m.id
                    Button { store.setSpeedMode(m.id) } label: {
                        Image(systemName: m.symbol)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(on ? .white : m.color)
                            .frame(width: 40, height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(on ? AnyShapeStyle(LinearGradient(colors: [m.color, m.color.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                                             : AnyShapeStyle(m.color.opacity(0.12)))
                            )
                    }
                    .buttonStyle(.plain)
                    .help(m.name)
                }
            }
            Spacer(minLength: 0)
            Text(detail).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(16)
    }

    private var detail: String {
        switch store.speedMode {
        case "limited": return "Limited · ↓ \(Fmt.limit(Prefs.downLimitKB))"
        case "quiet": return "Quiet · ↓ \(Fmt.limit(Prefs.quietDownKB))"
        default: return "Full speed"
        }
    }
}

private struct SpeedWidget: View {
    let title: String
    let samples: [Int64]
    let current: Int64
    let colors: [Color]
    let size: WidgetSize

    var body: some View {
        let (v, u) = splitBytes(current, perSecond: true)
        let big = size == .large || size == .tall
        ZStack(alignment: .bottom) {
            SpeedGraph(samples: samples, lineWidth: 1.8, colors: colors)
                .frame(height: big ? nil : 56)
                .padding(.top, big ? 90 : 0)
            VStack(alignment: .leading, spacing: 2) {
                WidgetTitle(title)
                BigValue(value: v, unit: u, size: big ? 40 : 30)
                Spacer()
                if big {
                    HStack {
                        Spacer()
                        Text("Peak \(Fmt.speed(samples.max() ?? 0))")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
            .padding(16)
        }
    }
}

private struct ActiveTasksWidget: View {
    @EnvironmentObject var store: Store
    let size: WidgetSize

    var body: some View {
        let downloading = store.tasks.filter { $0.status == "active" && !$0.isSeeding }.count
        let waiting = store.tasks.filter { $0.status == "waiting" || $0.status == "paused" }.count
        let seeding = store.tasks.filter { $0.status == "active" && $0.isSeeding }.count
        VStack(alignment: .leading, spacing: 4) {
            WidgetTitle(text: "Active Tasks") {
                Circle().fill(downloading > 0 ? Theme.blue : Color.secondary.opacity(0.5)).frame(width: 9, height: 9)
            }
            Text("\(downloading + waiting + seeding)").font(.system(size: 30, weight: .bold, design: .rounded))
            Spacer(minLength: 0)
            if size == .small {
                HStack(spacing: 12) {
                    Label("\(downloading)", systemImage: "arrow.down")
                    Label("\(waiting)", systemImage: "clock")
                    Label("\(seeding)", systemImage: "arrow.up")
                }
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 0) {
                    stat(downloading, "Downloading", Theme.blue)
                    Divider().frame(height: 34)
                    stat(waiting, "Waiting", .orange)
                    Divider().frame(height: 34)
                    stat(seeding, "Seeding", Theme.green)
                }
            }
        }
        .padding(16)
    }

    private func stat(_ n: Int, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(n)").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(n > 0 ? color : .primary)
            Text(label.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 8)
    }
}

private struct TransferWidget: View {
    @EnvironmentObject var store: Store
    let size: WidgetSize
    @Local private var allTime = false

    var body: some View {
        let t = allTime ? store.stats.allTime : store.stats.today
        let (v, u) = splitBytes(t.down + t.up)
        VStack(alignment: .leading, spacing: 6) {
            WidgetTitle(text: "Transfer") {
                if size == .small {
                    // Not enough room for a segmented control: a tappable capsule instead
                    Button { allTime.toggle() } label: {
                        HStack(spacing: 3) {
                            Text(allTime ? "All Time" : "Today")
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .bold))
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .help("Switch between today and all time")
                } else {
                    Picker("", selection: Binding(get: { allTime }, set: { allTime = $0 })) {
                        Text("Today").tag(false)
                        Text("All Time").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden().controlSize(.small).fixedSize()
                }
            }
            BigValue(value: v, unit: u)
            Spacer(minLength: 0)
            if size != .small {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("UP").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        Text(Fmt.bytes(t.up)).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Theme.green)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("DOWN").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        Text(Fmt.bytes(t.down)).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Theme.blue)
                    }
                }
            }
            GeometryReader { g in
                let total = max(1, Double(t.down + t.up))
                HStack(spacing: 3) {
                    if t.up > 0 {
                        Capsule().fill(LinearGradient(colors: [Theme.green, Theme.teal], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(6, g.size.width * Double(t.up) / total))
                    }
                    Capsule().fill(t.down > 0 ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.primary.opacity(0.08)))
                }
            }
            .frame(height: size == .small ? 8 : 12)
        }
        .padding(16)
    }
}

/// Year-long grid of daily download totals (GitHub-style).
private struct ActivityWidget: View {
    @EnvironmentObject var store: Store
    let size: WidgetSize

    var body: some View {
        let weeks = size == .full ? 53 : 26
        let grid = buildGrid(weeks: weeks)
        VStack(alignment: .leading, spacing: 8) {
            WidgetTitle(text: "Activity") {
                Text("\(Fmt.bytes(grid.total)) in \(weeks == 53 ? "the last year" : "6 months")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            GeometryReader { g in
                let labelW: CGFloat = 32
                let gap: CGFloat = 3
                let cell = max(6, min(14, (g.size.width - labelW) / CGFloat(weeks) - gap))
                let step = cell + gap
                VStack(alignment: .leading, spacing: 4) {
                    ZStack(alignment: .topLeading) {
                        ForEach(grid.months, id: \.col) { m in
                            Text(m.name).font(.system(size: 10)).foregroundStyle(.secondary)
                                .offset(x: labelW + CGFloat(m.col) * step)
                        }
                    }
                    .frame(height: 12)
                    HStack(alignment: .top, spacing: 0) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(0..<7, id: \.self) { d in
                                Text(d == 1 ? "Mon" : d == 3 ? "Wed" : d == 5 ? "Fri" : "")
                                    .font(.system(size: 10)).foregroundStyle(.secondary)
                                    .frame(height: step, alignment: .leading)
                            }
                        }
                        .frame(width: labelW, alignment: .leading)
                        ZStack(alignment: .topLeading) {
                            ForEach(0..<5, id: \.self) { level in
                                HeatCells(cells: grid.cells.filter { $0.level == level }, cell: cell, step: step)
                                    .fill(color(level))
                            }
                        }
                        .frame(width: CGFloat(weeks) * step, height: 7 * step, alignment: .topLeading)
                    }
                    HStack(spacing: 3) {
                        Spacer()
                        Text("Less").font(.system(size: 10)).foregroundStyle(.secondary)
                        ForEach(0..<5, id: \.self) { l in
                            RoundedRectangle(cornerRadius: 2).fill(color(l)).frame(width: 10, height: 10)
                        }
                        Text("More").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
    }

    private func color(_ level: Int) -> Color {
        level == 0 ? Color.primary.opacity(0.07) : Theme.blue.opacity([0, 0.3, 0.5, 0.75, 1][level])
    }

    struct Cell { let col: Int; let row: Int; let level: Int }
    struct Month { let col: Int; let name: String }

    private func buildGrid(weeks: Int) -> (cells: [Cell], months: [Month], total: Int64) {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 1
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today) - 1                // 0 = Sunday
        guard let start = cal.date(byAdding: .day, value: -(weeks - 1) * 7 - weekday, to: today) else { return ([], [], 0) }

        var values: [(Int, Int, Int64)] = []
        var months: [Month] = []
        var lastMonth = -1
        var total: Int64 = 0
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM"
        for w in 0..<weeks {
            for d in 0..<7 {
                guard let date = cal.date(byAdding: .day, value: w * 7 + d, to: start), date <= today else { continue }
                let v = store.stats.day(date).down
                total += v
                values.append((w, d, v))
                if d == 0 {
                    let m = cal.component(.month, from: date)
                    if m != lastMonth {
                        if lastMonth != -1 || w == 0 { months.append(Month(col: w, name: fmt.string(from: date))) }
                        lastMonth = m
                    }
                }
            }
        }
        // Drop a month label that would collide with the next one
        months = months.enumerated().filter { i, m in i + 1 >= months.count || months[i + 1].col - m.col >= 3 }.map(\.1)
        let peak = max(1, values.map(\.2).max() ?? 1)
        let cells = values.map { w, d, v -> Cell in
            let level = v <= 0 ? 0 : min(4, 1 + Int(Double(v) / Double(peak) * 3.999))
            return Cell(col: w, row: d, level: level)
        }
        return (cells, months, total)
    }
}

private struct HeatCells: Shape {
    let cells: [ActivityWidget.Cell]
    let cell: CGFloat
    let step: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        for c in cells {
            p.addRoundedRect(in: CGRect(x: CGFloat(c.col) * step, y: CGFloat(c.row) * step, width: cell, height: cell),
                             cornerSize: CGSize(width: 2.5, height: 2.5))
        }
        return p
    }
}

private struct TasksWidget: View {
    @EnvironmentObject var store: Store
    let openNew: () -> Void
    let showDownloads: () -> Void

    var body: some View {
        let live = store.tasks.filter(\.isLive)
        VStack(alignment: .leading, spacing: 10) {
            WidgetTitle(text: "Tasks") {
                Button("View all") { showDownloads() }.buttonStyle(.link).font(.caption)
            }
            if live.isEmpty {
                VStack(spacing: 8) {
                    Text("No active tasks").foregroundStyle(.secondary)
                    Button("New task") { openNew() }.controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(live) { t in
                            HStack(spacing: 10) {
                                KindIcon(kind: FileKind(t), size: 28)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(t.name).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                                        Spacer()
                                        Text(t.status == "active" ? Fmt.speed(t.speed) : Theme.status(for: t).0)
                                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                    }
                                    GradientProgress(value: t.progress, style: Theme.gradient(for: t), height: 4)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
    }
}

private struct StorageWidget: View {
    var body: some View {
        let (free, total) = space()
        let used = total > 0 ? 1 - Double(free) / Double(total) : 0
        VStack(alignment: .leading, spacing: 8) {
            WidgetTitle("Storage")
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.08), lineWidth: 7)
                    Circle().trim(from: 0, to: used)
                        .stroke(used > 0.9 ? AnyShapeStyle(Color.red) : AnyShapeStyle(Theme.accent),
                                style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(used * 100))%").font(.system(size: 11, weight: .bold, design: .rounded))
                }
                .frame(width: 50, height: 50)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Fmt.bytes(free)).font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("free of \(Fmt.bytes(total))").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Text((Prefs.downloadDir as NSString).abbreviatingWithTildeInPath)
                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
        }
        .padding(16)
    }

    private func space() -> (Int64, Int64) {
        let v = try? URL(fileURLWithPath: Prefs.downloadDir)
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        return (v?.volumeAvailableCapacityForImportantUsage ?? 0, Int64(v?.volumeTotalCapacity ?? 0))
    }
}

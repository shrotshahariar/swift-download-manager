import SwiftUI
import AppKit

enum DetailTab: String, CaseIterable, Identifiable {
    case general = "General", activity = "Activity", files = "Files", peers = "Peers", trackers = "Trackers"
    var id: String { rawValue }
}

struct DetailView: View {
    @EnvironmentObject var store: Store
    let gid: String?
    @Local private var tab: DetailTab = .general

    var body: some View {
        if let t = store.task(gid) {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    ForEach(tabs(for: t)) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(10)
                Divider()
                ScrollView {
                    Group {
                        switch tab {
                        case .general: GeneralTab(task: t)
                        case .activity: ActivityTab(task: t)
                        case .files: FilesTab(task: t)
                        case .peers: PeersTab()
                        case .trackers: TrackersTab(task: t)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .onAppear { syncPeerWatch(t) }
            .onChange(of: tab) { _, _ in syncPeerWatch(t) }
            .onChange(of: gid) { _, _ in
                if !tabs(for: t).contains(tab) { tab = .general }
                syncPeerWatch(t)
            }
            .onDisappear { store.peerWatchGid = nil }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "info.circle").font(.system(size: 30)).foregroundStyle(.tertiary)
                Text("Select a download to see its details").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func tabs(for t: DLTask) -> [DetailTab] {
        t.isTorrent || t.isMetadata ? DetailTab.allCases : [.general, .activity, .files]
    }

    private func syncPeerWatch(_ t: DLTask) {
        store.peerWatchGid = (tab == .peers && t.isTorrent) ? t.id : nil
    }
}

private struct Row: View {
    let label: String
    let value: String
    var copyable = false
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary).frame(width: 96, alignment: .trailing)
            Text(value).textSelection(.enabled).lineLimit(4).fixedSize(horizontal: false, vertical: true)
            if copyable {
                Spacer(minLength: 4)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless).help("Copy")
            }
        }
        .font(.callout)
    }
}

private struct GeneralTab: View {
    @EnvironmentObject var store: Store
    let task: DLTask
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Row(label: "Name", value: task.name)
            HStack {
                Row(label: "Saved in", value: (task.dir as NSString).abbreviatingWithTildeInPath)
                Button { store.reveal(task) } label: { Image(systemName: "magnifyingglass") }.buttonStyle(.borderless).help("Show in Finder")
            }
            Row(label: "Status", value: statusText)
            if task.status == "error" {
                Row(label: "Error", value: "\(task.errorMessage ?? "Unknown") (code \(task.errorCode))")
            }
            Row(label: "Size", value: task.total > 0 ? Fmt.bytes(task.total) : "Unknown")
            Row(label: "GID", value: task.id, copyable: true)
            if let l = task.link { Row(label: task.isTorrent ? "Magnet" : "Link", value: l, copyable: true) }
            if task.isTorrent {
                if let h = task.infoHash { Row(label: "Info hash", value: h, copyable: true) }
                Row(label: "Pieces", value: "\(task.numPieces) × \(Fmt.bytes(task.pieceLength))")
                if let d = task.creationDate { Row(label: "Created", value: Fmt.date.string(from: d)) }
                if let c = task.comment, !c.isEmpty { Row(label: "Comment", value: c) }
            }
        }
    }

    private var statusText: String {
        switch task.status {
        case "active": return task.isSeeding ? "Seeding" : "Downloading"
        case "waiting": return "Queued"
        case "paused": return "Paused"
        case "complete": return "Completed"
        case "removed": return "Stopped"
        case "error": return "Failed"
        default: return task.status.capitalized
        }
    }
}

private struct ActivityTab: View {
    let task: DLTask
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(String(format: "%.1f", task.progress * 100))%").font(.title2.weight(.semibold)).monospacedDigit()
                    Spacer()
                    if let e = task.eta, task.status == "active" { Text(Fmt.time(e) + " left").foregroundStyle(.secondary) }
                }
                ProgressView(value: task.progress)
                Text("\(Fmt.bytes(task.completed)) of \(Fmt.bytes(task.total))").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow { Text("Download").foregroundStyle(.secondary); Text(Fmt.speed(task.speed)).monospacedDigit() }
                GridRow { Text("Upload").foregroundStyle(.secondary); Text(Fmt.speed(task.upload)).monospacedDigit() }
                GridRow { Text("Connections").foregroundStyle(.secondary); Text("\(task.connections)") }
                if task.isTorrent {
                    GridRow { Text("Seeders").foregroundStyle(.secondary); Text("\(task.seeders)") }
                    GridRow { Text("Uploaded").foregroundStyle(.secondary); Text(Fmt.bytes(task.uploaded)) }
                    GridRow { Text("Ratio").foregroundStyle(.secondary); Text(String(format: "%.2f", task.ratio)) }
                }
            }
            .font(.callout)
            if !task.bitfield.isEmpty && task.numPieces > 0 {
                Text("Pieces").font(.headline).padding(.top, 4)
                PieceMap(bitfield: task.bitfield, count: task.numPieces)
            }
        }
    }
}

/// Grid of downloaded pieces, like Motrix's activity graphic.
private struct PieceMap: View {
    let bitfield: String
    let count: Int

    var body: some View {
        let fracs = cellFractions()
        // Vector shapes, not Canvas — Canvas re-rasterises into new GPU buffers on every update.
        ZStack(alignment: .topLeading) {
            PieceCells(fractions: fracs) { $0 <= 0 }.fill(Color.secondary.opacity(0.2))
            PieceCells(fractions: fracs) { $0 > 0 && $0 < 1 }.fill(Theme.blue.opacity(0.45))
            PieceCells(fractions: fracs) { $0 >= 1 }.fill(Theme.accent)
        }
        .frame(height: CGFloat((fracs.count + 29) / 30) * 10 + 4)
    }

    /// Share of downloaded pieces in each cell (at most 1600 cells).
    private func cellFractions() -> [Double] {
        let bits = expand()
        guard !bits.isEmpty else { return [] }
        let cells = min(bits.count, 1600)
        let perCell = Double(bits.count) / Double(cells)
        return (0..<cells).map { i in
            let start = Int(Double(i) * perCell), end = max(start + 1, min(bits.count, Int(Double(i + 1) * perCell)))
            return Double(bits[start..<end].filter { $0 }.count) / Double(end - start)
        }
    }

    private func expand() -> [Bool] {
        var out: [Bool] = []
        out.reserveCapacity(count)
        for ch in bitfield {
            let n = Int(String(ch), radix: 16) ?? 0
            for b in (0..<4).reversed() where out.count < count { out.append(n & (1 << b) != 0) }
        }
        return out
    }
}

private struct PieceCells: Shape {
    let fractions: [Double]
    let include: @Sendable (Double) -> Bool

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let side: CGFloat = 8, gap: CGFloat = 2
        let cols = max(1, Int((rect.width + gap) / (side + gap)))
        for (i, f) in fractions.enumerated() where include(f) {
            let r = CGRect(x: CGFloat(i % cols) * (side + gap), y: CGFloat(i / cols) * (side + gap), width: side, height: side)
            p.addRoundedRect(in: r, cornerSize: CGSize(width: 2, height: 2))
        }
        return p
    }
}

private struct FilesTab: View {
    @EnvironmentObject var store: Store
    let task: DLTask

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if task.isTorrent && task.isLive {
                Text("Untick files you don't want. Changes apply immediately.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(task.files) { f in
                HStack(alignment: .top, spacing: 8) {
                    if task.isTorrent && task.isLive {
                        Toggle("", isOn: Binding(get: { f.selected }, set: { on in toggle(f, on) })).labelsHidden()
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(relative(f.path)).lineLimit(2).truncationMode(.middle).font(.callout)
                            .foregroundStyle(f.selected ? .primary : .secondary)
                        ProgressView(value: f.progress).controlSize(.small)
                        Text("\(Fmt.bytes(f.completed)) of \(Fmt.bytes(f.length))  ·  \(Int(f.progress * 100))%")
                            .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                Divider()
            }
        }
    }

    private func relative(_ p: String) -> String {
        if p.isEmpty { return "(not started)" }
        let prefix = task.dir.hasSuffix("/") ? task.dir : task.dir + "/"
        return p.hasPrefix(prefix) ? String(p.dropFirst(prefix.count)) : p
    }

    private func toggle(_ f: DLFile, _ on: Bool) {
        var sel = Set(task.files.filter(\.selected).map(\.index))
        if on { sel.insert(f.index) } else { sel.remove(f.index) }
        store.setFileSelection(task, selected: sel)
    }
}

private struct PeersTab: View {
    @EnvironmentObject var store: Store
    var body: some View {
        if store.peers.isEmpty {
            Text("No peers connected right now.").foregroundStyle(.secondary)
        } else {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    Text("Address"); Text("Client"); Text("Has"); Text("↓"); Text("↑")
                }
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(store.peers) { p in
                    GridRow {
                        Text(p.ip).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                        Text(p.client).lineLimit(1)
                        Text(p.seeder ? "Seed" : "\(Int(p.progress * 100))%")
                        Text(Fmt.compactSpeed(p.down))
                        Text(Fmt.compactSpeed(p.up))
                    }
                    .font(.caption).monospacedDigit()
                }
            }
        }
    }
}

private struct TrackersTab: View {
    let task: DLTask
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if task.trackers.isEmpty {
                Text("This torrent lists no trackers of its own. Swift DM still uses DHT and the shared tracker list from Settings.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(task.trackers.enumerated()), id: \.offset) { _, t in
                Text(t).font(.system(.caption, design: .monospaced)).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
            }
            Text("Plus \(Prefs.trackerList.count) shared trackers from Settings → BitTorrent.")
                .font(.caption).foregroundStyle(.secondary).padding(.top, 6)
        }
    }
}

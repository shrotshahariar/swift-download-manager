import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct NewTaskSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let request: NewTaskRequest

    @Local private var mode = 0                 // 0 = links, 1 = torrent
    @Local private var text = ""
    @Local private var rename = ""
    @Local private var dir = Prefs.downloadDir
    @Local private var connections = Prefs.connections
    @Local private var showAdvanced = false
    @Local private var userAgent = ""
    @Local private var referer = ""
    @Local private var cookie = ""
    @Local private var authorization = ""
    @Local private var proxy = ""
    @Local private var torrent: TorrentInfo? = nil
    @Local private var torrentData: Data? = nil
    @Local private var torrentName = ""
    @Local private var selected: Set<Int> = []
    @Local private var torrentError: String? = nil
    @Local private var didSetup = false

    static func isDownloadable(_ s: String) -> Bool {
        let s = s.trimmingCharacters(in: .whitespaces).lowercased()
        return ["http://", "https://", "ftp://", "sftp://", "magnet:?"].contains { s.hasPrefix($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("", selection: $mode) {
                Text("Links").tag(0)
                Text("Torrent").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)
            .frame(maxWidth: .infinity)

            if mode == 0 { linksPane } else { torrentPane }

            Divider()
            HStack {
                Text("Save to").frame(width: 90, alignment: .trailing)
                Menu {
                    ForEach(Prefs.recentDirs.filter { $0 != dir }, id: \.self) { d in
                        Button((d as NSString).abbreviatingWithTildeInPath) { dir = d }
                    }
                    if !Prefs.recentDirs.isEmpty { Divider() }
                    Button("Choose…") { chooseDir() }
                } label: {
                    Text((dir as NSString).abbreviatingWithTildeInPath).lineLimit(1).truncationMode(.head)
                }
            }
            HStack {
                Text("Connections").frame(width: 90, alignment: .trailing)
                Stepper("\(connections) per file", value: $connections, in: 1...16)
            }

            if mode == 0 {
                DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                    VStack(spacing: 8) {
                        field("User-Agent", $userAgent, Prefs.userAgent)
                        field("Referer", $referer, "https://…")
                        field("Cookie", $cookie, "name=value; name2=value2")
                        field("Authorization", $authorization, "Bearer … or Basic …")
                        field("Proxy", $proxy, "[http://][user:password@]host[:port]")
                    }
                    .padding(.top, 6)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Download") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(mode == 0 ? links.isEmpty : (torrentData == nil || selected.isEmpty))
            }
        }
        .padding(20)
        .frame(width: 560)
        .onAppear(perform: setup)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            _ = providers.first?.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.pathExtension.lowercased() == "torrent", let d = try? Data(contentsOf: url) else { return }
                Task { @MainActor in loadTorrent(name: url.lastPathComponent, data: d) }
            }
            return true
        }
    }

    // MARK: panes

    private var linksPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("One link per line — HTTP, HTTPS, FTP or magnet").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(height: 120)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            HStack {
                Text("Rename").frame(width: 90, alignment: .trailing)
                TextField(links.count > 1 ? "Only for a single link" : "Keep the original file name", text: $rename)
                    .disabled(links.count > 1)
            }
        }
    }

    @ViewBuilder private var torrentPane: some View {
        if let torrent {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "doc.fill").foregroundStyle(.secondary)
                    Text(torrent.name).font(.headline).lineLimit(1)
                    Spacer()
                    Button("Change…") { chooseTorrent() }
                }
                HStack {
                    Text("\(selected.count) of \(torrent.files.count) files · \(Fmt.bytes(selectedSize(torrent))) of \(Fmt.bytes(torrent.totalSize))")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("All") { selected = Set(torrent.files.map(\.index)) }.buttonStyle(.link)
                    Button("None") { selected = [] }.buttonStyle(.link)
                }
                List(torrent.files) { f in
                    Toggle(isOn: Binding(get: { selected.contains(f.index) },
                                         set: { if $0 { selected.insert(f.index) } else { selected.remove(f.index) } })) {
                        HStack {
                            Text(f.path).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(Fmt.bytes(f.length)).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
                .frame(height: 200)
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "arrow.down.doc").font(.system(size: 34)).foregroundStyle(.tertiary)
                Text(torrentError ?? "Drop a .torrent file here").foregroundStyle(torrentError == nil ? Color.secondary : Color.red)
                Button("Choose .torrent File…") { chooseTorrent() }
            }
            .frame(maxWidth: .infinity, minHeight: 200)
            .background(RoundedRectangle(cornerRadius: 10).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5])).foregroundStyle(.quaternary))
        }
    }

    private func field(_ label: String, _ binding: Binding<String>, _ placeholder: String) -> some View {
        HStack {
            Text(label).frame(width: 90, alignment: .trailing)
            TextField(placeholder, text: binding)
        }
    }

    // MARK: logic

    private var links: [String] {
        text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter(Self.isDownloadable)
    }

    private func selectedSize(_ t: TorrentInfo) -> Int64 {
        t.files.filter { selected.contains($0.index) }.reduce(0) { $0 + $1.length }
    }

    private func setup() {
        guard !didSetup else { return }
        didSetup = true
        text = request.links
        if let t = request.torrent { loadTorrent(name: t.name, data: t.data) }
    }

    private func loadTorrent(name: String, data: Data) {
        mode = 1
        guard let info = TorrentInfo(data: data) else {
            torrent = nil
            torrentData = nil
            torrentError = "“\(name)” isn't a valid torrent file."
            return
        }
        torrentError = nil
        torrent = info
        torrentData = data
        torrentName = name
        selected = Set(info.files.map(\.index))
    }

    private func submit() {
        var o = Store.AddOptions()
        o.dir = dir
        o.connections = connections
        if mode == 1, let data = torrentData, let t = torrent {
            if selected.count < t.files.count { o.selectFiles = selected.sorted() }
            store.addTorrent(data, options: o)
        } else {
            if links.count == 1 { o.out = rename.trimmingCharacters(in: .whitespaces) }
            o.userAgent = userAgent
            o.referer = referer
            o.cookie = cookie
            o.authorization = authorization
            o.proxy = proxy
            store.add(uris: links, options: o)
        }
        dismiss()
    }

    private func chooseDir() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.canCreateDirectories = true
        p.directoryURL = URL(fileURLWithPath: dir)
        if p.runModal() == .OK, let u = p.url { dir = u.path }
    }

    private func chooseTorrent() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [UTType(filenameExtension: "torrent") ?? .data]
        if p.runModal() == .OK, let u = p.url, let d = try? Data(contentsOf: u) {
            loadTorrent(name: u.lastPathComponent, data: d)
        }
    }
}

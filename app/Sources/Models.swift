import Foundation

struct DLFile: Identifiable, Equatable {
    let index: Int          // 1-based, as aria2 uses for select-file
    let path: String
    let length: Int64
    let completed: Int64
    let selected: Bool
    let uris: [String]
    var id: Int { index }
    var progress: Double { length > 0 ? Double(completed) / Double(length) : 0 }
}

struct Peer: Identifiable, Equatable {
    let id: String
    let ip: String
    let port: String
    let client: String
    let progress: Double
    let down: Int64
    let up: Int64
    let seeder: Bool
}

struct DLTask: Identifiable, Equatable {
    let id: String          // aria2 gid
    var status: String      // active, waiting, paused, error, complete, removed
    var name: String
    var total: Int64
    var completed: Int64
    var uploaded: Int64
    var speed: Int64
    var upload: Int64
    var connections: Int
    var seeders: Int
    var dir: String
    var path: String        // file or top folder on disk
    var uri: String?
    var errorCode: String
    var errorMessage: String?
    var isTorrent: Bool
    var isMetadata: Bool
    var isSeeding: Bool
    var infoHash: String?
    var numPieces: Int
    var pieceLength: Int64
    var bitfield: String
    var comment: String?
    var creationDate: Date?
    var trackers: [String]
    var files: [DLFile]

    var progress: Double { total > 0 ? min(1, Double(completed) / Double(total)) : 0 }
    var eta: Double? { speed > 0 && total > completed ? Double(total - completed) / Double(speed) : nil }
    var isLive: Bool { status == "active" || status == "waiting" || status == "paused" }
    var ratio: Double { completed > 0 ? Double(uploaded) / Double(completed) : 0 }

    /// A link that can recreate this download.
    var link: String? {
        if let h = infoHash, isTorrent || isMetadata {
            var m = "magnet:?xt=urn:btih:\(h)"
            if !name.isEmpty, !isMetadata, let enc = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) { m += "&dn=\(enc)" }
            for t in trackers.prefix(5) { if let e = t.addingPercentEncoding(withAllowedCharacters: .alphanumerics) { m += "&tr=\(e)" } }
            return m
        }
        return uri
    }

    init(_ d: [String: Any]) {
        func i64(_ k: String) -> Int64 { Int64(d[k] as? String ?? "") ?? 0 }
        id = d["gid"] as? String ?? UUID().uuidString
        status = d["status"] as? String ?? "waiting"
        total = i64("totalLength")
        completed = i64("completedLength")
        uploaded = i64("uploadLength")
        speed = i64("downloadSpeed")
        upload = i64("uploadSpeed")
        connections = Int(d["connections"] as? String ?? "") ?? 0
        seeders = Int(d["numSeeders"] as? String ?? "") ?? 0
        dir = d["dir"] as? String ?? Prefs.downloadDir
        errorCode = d["errorCode"] as? String ?? "0"
        errorMessage = d["errorMessage"] as? String
        if errorMessage?.isEmpty == true { errorMessage = nil }
        infoHash = d["infoHash"] as? String
        numPieces = Int(d["numPieces"] as? String ?? "") ?? 0
        pieceLength = i64("pieceLength")
        bitfield = d["bitfield"] as? String ?? ""
        isSeeding = (d["seeder"] as? String) == "true"

        let rawFiles = d["files"] as? [[String: Any]] ?? []
        files = rawFiles.map { f in
            DLFile(index: Int(f["index"] as? String ?? "") ?? 0,
                   path: f["path"] as? String ?? "",
                   length: Int64(f["length"] as? String ?? "") ?? 0,
                   completed: Int64(f["completedLength"] as? String ?? "") ?? 0,
                   selected: (f["selected"] as? String ?? "true") == "true",
                   uris: (f["uris"] as? [[String: Any]] ?? []).compactMap { $0["uri"] as? String })
        }
        let firstPath = files.first?.path ?? ""
        uri = files.first?.uris.first

        let bt = d["bittorrent"] as? [String: Any]
        isTorrent = bt != nil
        isMetadata = firstPath.hasPrefix("[METADATA]")
        comment = bt?["comment"] as? String
        if let n = bt?["creationDate"] as? NSNumber { creationDate = Date(timeIntervalSince1970: n.doubleValue) }
        else if let s = bt?["creationDate"] as? String, let n = Double(s) { creationDate = Date(timeIntervalSince1970: n) }
        else { creationDate = nil }
        trackers = (bt?["announceList"] as? [[String]] ?? []).flatMap { $0 }

        if let btName = (bt?["info"] as? [String: Any])?["name"] as? String, !btName.isEmpty {
            name = btName
            path = (dir as NSString).appendingPathComponent(btName)
        } else if isMetadata {
            name = "Fetching torrent info…"
            path = dir
        } else if !firstPath.isEmpty {
            name = (firstPath as NSString).lastPathComponent
            path = firstPath
        } else if let u = uri, let url = URL(string: u) {
            let last = url.lastPathComponent
            name = last.isEmpty || last == "/" ? (url.host ?? u) : (last.removingPercentEncoding ?? last)
            path = dir
        } else {
            name = "Unknown"
            path = dir
        }
    }

    static let pollKeys = ["gid", "status", "totalLength", "completedLength", "uploadLength", "downloadSpeed", "uploadSpeed",
                           "connections", "numSeeders", "seeder", "dir", "files", "bittorrent", "errorCode", "errorMessage",
                           "infoHash", "numPieces", "pieceLength", "bitfield"]
}

enum Category: String, CaseIterable, Identifiable {
    case downloading = "Downloading", waiting = "Waiting", completed = "Completed", stopped = "Stopped"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .downloading: return "arrow.down.circle"
        case .waiting: return "clock"
        case .completed: return "checkmark.circle"
        case .stopped: return "xmark.circle"
        }
    }
    func contains(_ t: DLTask) -> Bool {
        switch self {
        case .downloading: return t.status == "active"
        case .waiting: return t.status == "waiting" || t.status == "paused"
        case .completed: return t.status == "complete"
        case .stopped: return t.status == "error" || t.status == "removed"
        }
    }
}

enum Fmt {
    static func bytes(_ n: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .binary
        f.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        return n <= 0 ? "0 B" : f.string(fromByteCount: n)
    }
    static func speed(_ n: Int64) -> String { bytes(n) + "/s" }
    static func compactSpeed(_ n: Int64) -> String {
        let kb = Double(n) / 1024
        if kb < 1000 { return String(format: "%.0fK", kb) }
        let mb = kb / 1024
        return mb < 100 ? String(format: "%.1fM", mb) : String(format: "%.0fM", mb)
    }
    static func time(_ s: Double) -> String {
        let s = Int(s.rounded())
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m \(s % 60)s" }
        if s < 86400 { return "\(s / 3600)h \((s % 3600) / 60)m" }
        return "\(s / 86400)d \((s % 86400) / 3600)h"
    }
    static func limit(_ kb: Int) -> String {
        kb == 0 ? "Unlimited" : kb < 1024 ? "\(kb) KB/s" : "\(kb / 1024) MB/s"
    }
    static let date: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    /// Turns a BitTorrent peer id like "-qB4630-…" into "qBittorrent 4.6.3".
    static func client(fromPeerId raw: String) -> String {
        let id = raw.removingPercentEncoding ?? raw
        let names = ["qB": "qBittorrent", "TR": "Transmission", "UT": "µTorrent", "UM": "µTorrent Mac", "BT": "BitTorrent",
                     "DE": "Deluge", "LT": "libtorrent", "lt": "libTorrent", "AZ": "Vuze", "BC": "BitComet", "A2": "aria2",
                     "FD": "Free Download Manager", "XL": "Xunlei", "SD": "Thunder", "TX": "Tixati", "BI": "BiglyBT",
                     "WW": "WebTorrent", "KT": "KTorrent", "FW": "FrostWire", "PI": "PicoTorrent", "MO": "MonoTorrent"]
        let c = Array(id)
        guard c.count >= 8, c[0] == "-", c[7] == "-" else { return "Unknown" }
        let code = String(c[1...2])
        let v = c[3...5].map(String.init).joined(separator: ".")
        return "\(names[code] ?? code) \(v)"
    }
}

/// Bytes transferred per day ("yyyy-MM-dd" → [down, up]), kept for the dashboard.
struct TransferStats: Equatable {
    var days: [String: [Int64]]

    static let keyFormat: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func load() -> TransferStats { TransferStats(days: Prefs.dailyStatsRaw) }
    func save() { Prefs.dailyStatsRaw = days }

    mutating func add(down: Int64, up: Int64, on date: Date = Date()) {
        let k = Self.keyFormat.string(from: date)
        var v = days[k] ?? [0, 0]
        if v.count < 2 { v = [0, 0] }
        v[0] += down
        v[1] += up
        days[k] = v
    }

    func day(_ date: Date) -> (down: Int64, up: Int64) {
        let v = days[Self.keyFormat.string(from: date)] ?? [0, 0]
        return (v.first ?? 0, v.count > 1 ? v[1] : 0)
    }
    var today: (down: Int64, up: Int64) { day(Date()) }
    var allTime: (down: Int64, up: Int64) {
        days.values.reduce((Int64(0), Int64(0))) { ($0.0 + ($1.first ?? 0), $0.1 + ($1.count > 1 ? $1[1] : 0)) }
    }
}

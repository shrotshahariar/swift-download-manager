import Foundation

/// Just enough of a bencode reader to list the files inside a .torrent before adding it.
struct TorrentInfo {
    struct File: Identifiable {
        let index: Int      // 1-based, matches aria2's select-file
        let path: String
        let length: Int64
        var id: Int { index }
    }
    let name: String
    let files: [File]
    var totalSize: Int64 { files.reduce(0) { $0 + $1.length } }

    init?(data: Data) {
        var parser = Bencode(bytes: [UInt8](data))
        guard case .dict(let root)? = try? parser.parse(),
              case .dict(let info)? = root["info"] else { return nil }

        func str(_ v: Bencode.Value?) -> String? {
            if case .bytes(let b)? = v { return String(decoding: b, as: UTF8.self) }
            return nil
        }
        func int(_ v: Bencode.Value?) -> Int64? {
            if case .int(let n)? = v { return n }
            return nil
        }

        let name = str(info["name.utf-8"]) ?? str(info["name"]) ?? "Torrent"
        self.name = name

        if case .list(let list)? = info["files"] {
            var out: [File] = []
            for (i, item) in list.enumerated() {
                guard case .dict(let f) = item else { continue }
                var parts: [String] = []
                if case .list(let p)? = f["path.utf-8"] ?? f["path"] {
                    parts = p.compactMap { str($0) }
                }
                // BitTorrent v2 hybrid torrents include padding files; aria2 still counts them, so keep the index.
                out.append(File(index: i + 1, path: parts.joined(separator: "/"), length: int(f["length"]) ?? 0))
            }
            files = out
        } else {
            files = [File(index: 1, path: name, length: int(info["length"]) ?? 0)]
        }
    }
}

struct Bencode {
    indirect enum Value {
        case int(Int64)
        case bytes([UInt8])
        case list([Value])
        case dict([String: Value])
    }

    struct Malformed: Error {}

    let bytes: [UInt8]
    var i = 0

    init(bytes: [UInt8]) { self.bytes = bytes }

    private func peek() throws -> UInt8 {
        guard i < bytes.count else { throw Malformed() }
        return bytes[i]
    }

    mutating func parse(depth: Int = 0) throws -> Value {
        guard depth < 64 else { throw Malformed() }
        let c = try peek()
        switch c {
        case UInt8(ascii: "i"):
            i += 1
            let start = i
            while try peek() != UInt8(ascii: "e") { i += 1 }
            guard let n = Int64(String(decoding: bytes[start..<i], as: UTF8.self)) else { throw Malformed() }
            i += 1
            return .int(n)
        case UInt8(ascii: "l"):
            i += 1
            var arr: [Value] = []
            while try peek() != UInt8(ascii: "e") { arr.append(try parse(depth: depth + 1)) }
            i += 1
            return .list(arr)
        case UInt8(ascii: "d"):
            i += 1
            var dict: [String: Value] = [:]
            while try peek() != UInt8(ascii: "e") {
                guard case .bytes(let k) = try parse(depth: depth + 1) else { throw Malformed() }
                dict[String(decoding: k, as: UTF8.self)] = try parse(depth: depth + 1)
            }
            i += 1
            return .dict(dict)
        case UInt8(ascii: "0")...UInt8(ascii: "9"):
            let start = i
            while try peek() != UInt8(ascii: ":") { i += 1 }
            guard let len = Int(String(decoding: bytes[start..<i], as: UTF8.self)), len >= 0 else { throw Malformed() }
            i += 1
            guard i + len <= bytes.count else { throw Malformed() }
            defer { i += len }
            return .bytes(Array(bytes[i..<(i + len)]))
        default:
            throw Malformed()
        }
    }
}

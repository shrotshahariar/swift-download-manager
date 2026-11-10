import Foundation

struct RPCError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Minimal JSON-RPC client for aria2.
final class Aria2RPC: @unchecked Sendable {
    let url: URL
    let secret: String
    private let session: URLSession

    init(port: Int, secret: String) {
        url = URL(string: "http://127.0.0.1:\(port)/jsonrpc")!
        self.secret = secret
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 5
        cfg.httpMaximumConnectionsPerHost = 2
        session = URLSession(configuration: cfg)
    }

    private func send(_ method: String, _ params: [Any]) async throws -> Any {
        let body: [String: Any] = ["jsonrpc": "2.0", "id": "sdm", "method": method, "params": params]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await session.data(for: req)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RPCError(message: "Bad response from aria2")
        }
        if let err = obj["error"] as? [String: Any] {
            throw RPCError(message: err["message"] as? String ?? "aria2 error")
        }
        return obj["result"] ?? NSNull()
    }

    @discardableResult
    func call(_ method: String, _ params: [Any] = []) async throws -> Any {
        try await send(method, ["token:\(secret)"] + params)
    }

    /// Runs several calls in one round trip. Each element is the result or an RPCError.
    func multicall(_ calls: [(String, [Any])]) async throws -> [Any] {
        let list: [[String: Any]] = calls.map { ["methodName": $0.0, "params": ["token:\(secret)"] + $0.1] }
        guard let results = try await send("system.multicall", [list]) as? [Any] else {
            throw RPCError(message: "Bad multicall response")
        }
        return results.map { r in
            if let arr = r as? [Any], let first = arr.first { return first }
            if let d = r as? [String: Any] { return RPCError(message: d["message"] as? String ?? "error") }
            return NSNull()
        }
    }
}

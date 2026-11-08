import Foundation
import Network
import MixKeeperCore

/// 只聽 127.0.0.1。要帶 token、不接受帶 Origin 的請求（網頁打不進來）。
final class EventServer {
    static let port: UInt16 = 17917
    private static let maxBytes = 2_000_000

    private let token: String
    private let onEvent: (KeeperEvent, String) -> Void
    private var listener: NWListener?

    init(token: String, onEvent: @escaping (KeeperEvent, String) -> Void) {
        self.token = token
        self.onEvent = onEvent
    }

    func start() throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!)
        let listener = try NWListener(using: params)
        listener.newConnectionHandler = { [weak self] in self?.accept($0) }
        listener.start(queue: .main)
        self.listener = listener
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        read(connection, buffer: Data())
    }

    private func read(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = HTTPRequest(buffer) {
                self.respond(connection, status: self.handle(request))
            } else if error != nil || done || buffer.count > Self.maxBytes {
                connection.cancel()
            } else {
                self.read(connection, buffer: buffer)
            }
        }
    }

    private func respond(_ connection: NWConnection, status: String) {
        let text = "HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(text.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }

    private func handle(_ request: HTTPRequest) -> String {
        guard request.method == "POST", request.path == "/event", request.headers["origin"] == nil else { return "403 Forbidden" }
        guard request.headers["x-keeper-token"] == token else { return "401 Unauthorized" }
        guard let kind = KeeperEventKind(rawValue: request.headers["x-keeper-kind"] ?? ""),
              let json = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any] else { return "400 Bad Request" }
        let event = KeeperEvent(kind: kind,
                                cliSessionID: json["session_id"] as? String ?? "",
                                cwd: json["cwd"] as? String ?? "",
                                tty: request.headers["x-keeper-tty"] ?? "",
                                message: json["message"] as? String ?? "")
        onEvent(event, request.headers["x-keeper-entry"] ?? "")
        return "204 No Content"
    }
}

private struct HTTPRequest {
    var method: String
    var path: String
    var headers: [String: String] = [:]
    var body: Data

    /// 資料還沒收齊就回 nil。
    init?(_ data: Data) {
        guard let end = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let lines = String(decoding: data[..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        let start = lines[0].split(separator: " ")
        guard start.count >= 2 else { return nil }
        method = String(start[0])
        path = String(start[1])
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        body = data[end.upperBound...]
        guard body.count >= length else { return nil }
    }
}

enum KeeperToken {
    static func loadOrCreate() throws -> String {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/mix-keeper.token")
        if let text = try? String(contentsOf: url, encoding: .utf8), text.count >= 32 {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        var generator = SystemRandomNumberGenerator()
        let token = String((0..<48).map { _ in alphabet.randomElement(using: &generator)! })
        try token.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return token
    }
}

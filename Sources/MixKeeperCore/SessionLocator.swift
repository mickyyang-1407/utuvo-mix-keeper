import Foundation

public struct DesktopSession: Equatable {
    public var localID: String
    public var title: String
    public var scheduled: Bool = false

    public init(localID: String, title: String, scheduled: Bool = false) {
        self.localID = localID
        self.title = title
        self.scheduled = scheduled
    }
}

/// 背景 lane 與排程任務也會觸發 hook，不擋的話角色會整天跑來。
public enum CardPolicy {
    public static let shortTurn: TimeInterval = 15

    public static func shouldShow(kind: KeeperEventKind, tty: String, desktop: DesktopSession?, remote: RemoteSession? = nil,
                                  turnSeconds: TimeInterval?) -> Bool {
        guard !tty.isEmpty || desktop != nil || remote != nil else { return false }
        if desktop?.scheduled == true { return false }
        guard kind == .stop else { return true }
        if let turnSeconds, turnSeconds < shortTurn { return false }
        return true
    }
}

/// 把 hook 給的 cliSessionId 換成桌面版的 local_ ID 與標題。
public struct SessionLocator {
    public var root: URL

    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")) {
        self.root = root
    }

    public func find(cliSessionID: String) -> DesktopSession? {
        guard !cliSessionID.isEmpty else { return nil }
        let needle = Data(cliSessionID.utf8)
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
        var files: [(URL, Date)] = []
        for case let url as URL in walker where url.lastPathComponent.hasPrefix("local_") && url.pathExtension == "json" {
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            files.append((url, date))
        }
        for (url, _) in files.sorted(by: { $0.1 > $1.1 }) {
            guard let handle = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? handle.close() }
            // ID 在檔頭；有些檔案超過 100 MB，不整檔讀。
            guard let head = try? handle.read(upToCount: 4096), head.range(of: needle) != nil else { continue }
            let text = String(decoding: head, as: UTF8.self)
            return DesktopSession(localID: url.deletingPathExtension().lastPathComponent,
                                  title: Self.field("title", in: text) ?? "",
                                  scheduled: Self.field("scheduledTaskId", in: text) != nil)
        }
        return nil
    }

    static func field(_ name: String, in text: String) -> String? {
        let pattern = "\"\(name)\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return (try? JSONDecoder().decode(String.self, from: Data("\"\(text[range])\"".utf8))) ?? String(text[range])
    }
}

public struct RemoteSession: Equatable {
    public var bridgeID: String
    public var title: String

    public init(bridgeID: String, title: String) {
        self.bridgeID = bridgeID
        self.title = title
    }
}

/// remote-control 開的 session 沒有 local_ 檔；`~/.claude/sessions/<pid>.json` 有對照。
public struct RemoteSessionLocator {
    public var sessions: URL
    public var log: URL

    public init(sessions: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/sessions"),
                log: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/log/claude-remote-control.log")) {
        self.sessions = sessions
        self.log = log
    }

    public func find(cliSessionID: String) -> RemoteSession? {
        guard !cliSessionID.isEmpty,
              let files = try? FileManager.default.contentsOfDirectory(at: sessions, includingPropertiesForKeys: nil) else { return nil }
        for url in files where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["sessionId"] as? String == cliSessionID,
                  let bridge = json["bridgeSessionId"] as? String, !bridge.isEmpty else { continue }
            return RemoteSession(bridgeID: bridge, title: title(of: bridge))
        }
        return nil
    }

    /// 標題只出現在 remote-control 的 log，格式是終端機超連結：<id>?from=cli BEL 標題 ESC。
    private func title(of bridgeID: String) -> String {
        guard let text = try? String(contentsOf: log, encoding: .utf8) else { return "" }
        let parts = text.components(separatedBy: "\(bridgeID)?from=cli\u{07}").dropFirst()
        let titles = parts.compactMap { $0.components(separatedBy: "\u{1B}").first }.filter { $0 != "Attached" }
        return titles.last ?? ""
    }
}

public enum JumpTarget: Equatable {
    case desktop(URL)
    case terminalTab(tty: String)
    case bringClaudeForward
}

public enum JumpPlanner {
    private static let validLocalID = #"^local_[A-Za-z0-9-]{1,64}$"#
    private static let validTty = #"^/dev/ttys?[0-9]+$"#
    private static let validBridgeID = #"^session_[A-Za-z0-9_-]{1,80}$"#

    public static func target(tty: String, localID: String?, bridgeID: String? = nil) -> JumpTarget {
        if tty.range(of: validTty, options: .regularExpression) != nil {
            return .terminalTab(tty: tty)
        }
        if let localID, localID.range(of: validLocalID, options: .regularExpression) != nil,
           let url = URL(string: "claude://code/continue?session=\(localID)") {
            return .desktop(url)
        }
        if let bridgeID, bridgeID.range(of: validBridgeID, options: .regularExpression) != nil,
           let url = URL(string: "claude://code/\(bridgeID)") {
            return .desktop(url)
        }
        return .bringClaudeForward
    }
}

public enum GitBranch {
    public static func read(cwd: String) -> String {
        var dir = URL(fileURLWithPath: cwd)
        let fm = FileManager.default
        for _ in 0..<25 {
            let dotGit = dir.appendingPathComponent(".git")
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: dotGit.path, isDirectory: &isDir) {
                var gitDir = dotGit
                if !isDir.boolValue {
                    guard let text = try? String(contentsOf: dotGit, encoding: .utf8),
                          let line = text.split(separator: "\n").first(where: { $0.hasPrefix("gitdir:") }) else { return "" }
                    let path = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
                    gitDir = URL(fileURLWithPath: path, relativeTo: dir).standardizedFileURL
                }
                guard let head = try? String(contentsOf: gitDir.appendingPathComponent("HEAD"), encoding: .utf8) else { return "" }
                let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("ref: refs/heads/") { return String(trimmed.dropFirst("ref: refs/heads/".count)) }
                return String(trimmed.prefix(7))
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        return ""
    }
}

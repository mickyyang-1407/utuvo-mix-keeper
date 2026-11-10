import Foundation

/// 在 ~/.claude/settings.json 增刪 Mix Keeper 自己的 hook，其他設定原樣保留。
/// 只認得含 send-event.sh、且路徑帶 mix-keeper 或 MixKeeper 的指令；別人的 hook 不碰。
public enum HookInstaller {
    public static let events: [(event: String, kind: String)] = [
        ("Stop", "stop"), ("Notification", "notification"), ("PermissionRequest", "permission"),
        ("UserPromptSubmit", "submit"), ("SessionEnd", "end"),
    ]

    public static func isOurs(_ command: Any?) -> Bool {
        guard let command = command as? String, command.contains("send-event.sh") else { return false }
        return command.lowercased().contains("mix-keeper") || command.contains("MixKeeper")
    }

    public static func command(script: String, kind: String) -> String {
        "/bin/sh '\(script.replacingOccurrences(of: "'", with: "'\\''"))' \(kind)"
    }

    /// 回傳改好的設定；`script` 為 nil 表示移除。
    public static func updated(_ settings: [String: Any], script: String?) -> [String: Any] {
        var settings = settings
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            var kept: [[String: Any]] = []
            for group in groups {
                guard let commands = group["hooks"] as? [[String: Any]] else { kept.append(group); continue }
                let rest = commands.filter { !isOurs($0["command"]) }
                if rest.count == commands.count { kept.append(group) }
                else if !rest.isEmpty { var g = group; g["hooks"] = rest; kept.append(g) }
            }
            hooks[event] = kept.isEmpty ? nil : kept
        }
        if let script {
            for (event, kind) in events {
                var groups = hooks[event] as? [[String: Any]] ?? []
                groups.append(["hooks": [["type": "command", "command": command(script: script, kind: kind), "timeout": 5]]])
                hooks[event] = groups
            }
        }
        settings["hooks"] = hooks.isEmpty ? nil : hooks
        return settings
    }

    public static func isInstalled(_ settings: [String: Any]) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        return events.allSatisfy { event, _ in
            (hooks[event] as? [[String: Any]] ?? []).contains { group in
                (group["hooks"] as? [[String: Any]] ?? []).contains { isOurs($0["command"]) }
            }
        }
    }
}

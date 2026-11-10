import Foundation
import MixKeeperCore

/// 從 App 直接連接／斷開 Claude Code：把 App 內附的 hook 腳本放到固定位置，再改 ~/.claude/settings.json。
enum HookSetup {
    private static var home: URL {
        // 測試時可用 HOME 指到暫存資料夾
        ProcessInfo.processInfo.environment["HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser
    }
    private static var settingsURL: URL { home.appendingPathComponent(".claude/settings.json") }
    static var scriptURL: URL { home.appendingPathComponent("Library/Application Support/MixKeeper/send-event.sh") }

    static var isInstalled: Bool { HookInstaller.isInstalled(readSettings() ?? [:]) }

    static func set(_ on: Bool) throws {
        if on {
            guard let bundled = Bundle.main.url(forResource: "send-event", withExtension: "sh") else {
                throw NSError(domain: "MixKeeper", code: 1, userInfo: [NSLocalizedDescriptionKey: "send-event.sh not in app bundle"])
            }
            let fm = FileManager.default
            try fm.createDirectory(at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: scriptURL.path) { try fm.removeItem(at: scriptURL) }
            try fm.copyItem(at: bundled, to: scriptURL)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        }
        let before = readSettings() ?? [:]
        let after = HookInstaller.updated(before, script: on ? scriptURL.path : nil)
        try write(after)
        log("hooks \(on ? "installed" : "removed") at \(settingsURL.path)")
    }

    private static func readSettings() -> [String: Any]? {
        guard let data = try? Data(contentsOf: settingsURL) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func write(_ settings: [String: Any]) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let target = settingsURL.resolvingSymlinksInPath()   // dotfiles 常用 symlink，寫到真正的檔案
        if fm.fileExists(atPath: target.path) {
            // 毫秒時間戳；同一瞬間又改一次就加編號，備份不會撞名、也不會蓋掉前一份
            let stamp = String(Int(Date().timeIntervalSince1970 * 1000))
            var backup = target.deletingLastPathComponent().appendingPathComponent("settings.json.bak-mix-keeper-\(stamp)")
            var n = 2
            while fm.fileExists(atPath: backup.path) {
                backup = target.deletingLastPathComponent().appendingPathComponent("settings.json.bak-mix-keeper-\(stamp)-\(n)")
                n += 1
            }
            try fm.copyItem(at: target, to: backup)
        }
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try (data + Data("\n".utf8)).write(to: target, options: .atomic)
    }
}

import Foundation

public enum LanguageChoice: String, CaseIterable {
    case system, zh, en
}

/// 全部介面文字都走 `L.t(中文, 英文)`，新增文字不能只寫一種語言。
public enum L {
    private static let key = "language"

    public static var choice: LanguageChoice {
        get { UserDefaults.standard.string(forKey: key).flatMap(LanguageChoice.init) ?? .system }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    public static func resolve(_ choice: LanguageChoice, preferred: [String]) -> LanguageChoice {
        guard choice == .system else { return choice }
        return preferred.first?.lowercased().hasPrefix("zh") == true ? .zh : .en
    }

    public static var isChinese: Bool { resolve(choice, preferred: Locale.preferredLanguages) == .zh }

    public static func t(_ zh: String, _ en: String) -> String { isChinese ? zh : en }

    public static func waited(seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 1 { return t("剛剛", "Just now") }
        if minutes < 60 { return t("已等 \(minutes) 分鐘", "Waiting \(minutes) min") }
        return t("已等 \(minutes / 60) 小時 \(minutes % 60) 分", "Waiting \(minutes / 60) hr \(minutes % 60) min")
    }
}

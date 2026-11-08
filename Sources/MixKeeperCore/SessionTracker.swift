import Foundation

public enum KeeperEventKind: String {
    case stop, notification, permission, submit, end
}

public struct KeeperEvent {
    public var kind: KeeperEventKind
    public var cliSessionID: String
    public var cwd: String
    public var tty: String
    public var message: String
    public var at: Date

    public init(kind: KeeperEventKind, cliSessionID: String, cwd: String = "", tty: String = "", message: String = "", at: Date = Date()) {
        self.kind = kind
        self.cliSessionID = cliSessionID
        self.cwd = cwd
        self.tty = tty
        self.message = message
        self.at = at
    }
}

public enum CardKind: Equatable {
    case done, needsPermission, needsInput

    public var title: String {
        switch self {
        case .done: return L.t("跑完了", "Finished")
        case .needsPermission: return L.t("需要你按許可", "Needs your permission")
        case .needsInput: return L.t("在等你回話", "Waiting for your reply")
        }
    }
}

public struct KeeperCard: Equatable, Identifiable {
    public var id: String { cliSessionID }
    public var kind: CardKind
    public var cliSessionID: String
    public var cwd: String
    public var tty: String
    public var detail: String
    public var since: Date
}

/// 每個 session 最多一張卡。hook 事件進來就更新，App 只讀 `cards`。
public final class SessionTracker {
    public private(set) var cards: [KeeperCard] = []
    public private(set) var working: Set<String> = []
    private var dismissedAt: [String: Date] = [:]

    /// 許可框跳出幾秒後 Claude 會再發一次提醒，你已處理過就不用再報。
    public static let repeatQuietSeconds: TimeInterval = 30

    public init() {}

    public func handle(_ event: KeeperEvent) {
        let id = event.cliSessionID
        guard !id.isEmpty else { return }
        switch event.kind {
        case .submit:
            working.insert(id)
            remove(id)
        case .end:
            working.remove(id)
            remove(id)
        case .stop:
            working.remove(id)
            put(.done, event)
        case .permission:
            put(.needsPermission, event)
        case .notification:
            if let at = dismissedAt[id], event.at.timeIntervalSince(at) < Self.repeatQuietSeconds { return }
            let text = event.message.lowercased()
            if text.contains("permission") {
                put(.needsPermission, event)
            } else if !cards.contains(where: { $0.cliSessionID == id }) {
                // 跑完之後的「等你輸入」提醒不另開卡，跑完卡已經說了。
                put(.needsInput, event)
            }
        }
    }

    public func dismiss(_ cliSessionID: String, at date: Date = Date()) {
        remove(cliSessionID)
        dismissedAt[cliSessionID] = date
    }

    private func remove(_ id: String) {
        cards.removeAll { $0.cliSessionID == id }
    }

    private func put(_ kind: CardKind, _ event: KeeperEvent) {
        let existing = cards.first { $0.cliSessionID == event.cliSessionID }
        // 同一件事重複送來時，等待時間要從第一次算起。
        let since = existing?.kind == kind ? existing!.since : event.at
        remove(event.cliSessionID)
        cards.append(KeeperCard(kind: kind, cliSessionID: event.cliSessionID, cwd: event.cwd,
                                tty: event.tty, detail: event.message, since: since))
    }
}

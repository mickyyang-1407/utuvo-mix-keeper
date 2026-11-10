import XCTest
@testable import MixKeeperCore

final class CoreTests: XCTestCase {
    func testStopMakesDoneCardAndSubmitClearsIt() {
        let t = SessionTracker()
        t.handle(.init(kind: .submit, cliSessionID: "a"))
        XCTAssertTrue(t.working.contains("a"))
        t.handle(.init(kind: .stop, cliSessionID: "a"))
        XCTAssertEqual(t.cards.map(\.kind), [.done])
        XCTAssertFalse(t.working.contains("a"))
        t.handle(.init(kind: .submit, cliSessionID: "a"))
        XCTAssertTrue(t.cards.isEmpty)
    }

    func testIdleReminderAfterDoneDoesNotReplaceCard() {
        let t = SessionTracker()
        t.handle(.init(kind: .stop, cliSessionID: "a"))
        t.handle(.init(kind: .notification, cliSessionID: "a", message: "Claude is waiting for your input"))
        XCTAssertEqual(t.cards.map(\.kind), [.done])
    }

    func testPermissionNotificationBeatsDoneAndKeepsFirstWaitTime() {
        let t = SessionTracker()
        let first = Date(timeIntervalSince1970: 100)
        t.handle(.init(kind: .permission, cliSessionID: "a", at: first))
        t.handle(.init(kind: .notification, cliSessionID: "a", message: "Claude needs your permission to use Bash", at: Date(timeIntervalSince1970: 200)))
        XCTAssertEqual(t.cards.count, 1)
        XCTAssertEqual(t.cards[0].since, first)
    }

    func testRepeatReminderAfterDismissStaysQuietButNewPermissionShows() {
        let t = SessionTracker()
        let start = Date(timeIntervalSince1970: 1000)
        t.handle(.init(kind: .permission, cliSessionID: "a", at: start))
        t.dismiss("a", at: start.addingTimeInterval(2))
        t.handle(.init(kind: .notification, cliSessionID: "a", message: "Claude needs your permission", at: start.addingTimeInterval(6)))
        XCTAssertTrue(t.cards.isEmpty)
        t.handle(.init(kind: .notification, cliSessionID: "a", message: "Claude needs your permission", at: start.addingTimeInterval(40)))
        XCTAssertEqual(t.cards.count, 1)
        t.dismiss("a", at: start.addingTimeInterval(41))
        t.handle(.init(kind: .permission, cliSessionID: "a", at: start.addingTimeInterval(42)))
        XCTAssertEqual(t.cards.count, 1)
    }

    func testLanguageFollowsSystemUnlessChosen() {
        XCTAssertEqual(L.resolve(.system, preferred: ["zh-Hant-TW", "en"]), .zh)
        XCTAssertEqual(L.resolve(.system, preferred: ["en-US", "zh-Hant"]), .en)
        XCTAssertEqual(L.resolve(.system, preferred: ["ja-JP"]), .en)
        XCTAssertEqual(L.resolve(.zh, preferred: ["en-US"]), .zh)
        XCTAssertEqual(L.resolve(.en, preferred: ["zh-Hant"]), .en)
    }

    func testBothLanguagesHaveCardTextAndWaitTime() {
        let saved = L.choice
        defer { L.choice = saved }
        L.choice = .en
        XCTAssertEqual(CardKind.needsPermission.title, "Needs your permission")
        XCTAssertEqual(L.waited(seconds: 3700), "Waiting 1 hr 1 min")
        L.choice = .zh
        XCTAssertEqual(CardKind.needsPermission.title, "需要你按許可")
        XCTAssertEqual(L.waited(seconds: 180), "已等 3 分鐘")
    }

    func testZoneTabGivesTaipeiCoordinates() {
        let table = "# comment\nJP\t+353916+1394441\tAsia/Tokyo\nTW\t+2503+12130\tAsia/Taipei\n"
        let taipei = ZoneTab.coordinate(for: "Asia/Taipei", table: table)!
        XCTAssertEqual(taipei.latitude, 25.05, accuracy: 0.01)
        XCTAssertEqual(taipei.longitude, 121.5, accuracy: 0.01)
        XCTAssertEqual(ZoneTab.coordinate(for: "Asia/Tokyo", table: table)!.longitude, 139.745, accuracy: 0.01)
        XCTAssertNil(ZoneTab.coordinate(for: "Mars/Base", table: table))
    }

    func testDaylightFollowsTaipeiSunNotClockOnly() {
        let taipei = Coordinate(latitude: 25.05, longitude: 121.5)
        func at(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
        // 台北 11 月初日出約 06:05、日落約 17:08（UTC+8）
        XCTAssertEqual(Daylight.at(at("2026-11-08T04:00:00Z"), taipei), .day)     // 12:00
        XCTAssertEqual(Daylight.at(at("2026-11-08T08:40:00Z"), taipei), .day)     // 16:40
        XCTAssertEqual(Daylight.at(at("2026-11-08T10:00:00Z"), taipei), .night)   // 18:00
        XCTAssertEqual(Daylight.at(at("2026-11-07T21:20:00Z"), taipei), .night)   // 05:20
        XCTAssertEqual(Daylight.at(at("2026-11-07T22:30:00Z"), taipei), .day)     // 06:30
        // 夏天同一個 18:30 還亮著
        XCTAssertEqual(Daylight.at(at("2026-06-21T10:30:00Z"), taipei), .day)
        // 南半球（雪梨）11 月 19:30 還亮，同時間台北早就黑了
        let sydney = Coordinate(latitude: -33.87, longitude: 151.21)
        XCTAssertEqual(Daylight.at(at("2026-11-08T08:30:00Z"), sydney), .day)
    }

    func testAlwaysWalksHomeEvenWithCardsLeft() {
        let t0 = Date(timeIntervalSince1970: 1000)
        // 剛報完信：先在游標旁待一下
        XCTAssertFalse(HomeReturn.shouldWalkHome(awayFromHome: true, deliveredAt: t0, typedAt: nil, now: t0.addingTimeInterval(5)))
        // 15 秒後，就算卡片沒點也回家
        XCTAssertTrue(HomeReturn.shouldWalkHome(awayFromHome: true, deliveredAt: t0, typedAt: nil, now: t0.addingTimeInterval(15)))
        // 在任何 session 打字：馬上回家
        XCTAssertTrue(HomeReturn.shouldWalkHome(awayFromHome: true, deliveredAt: t0, typedAt: t0.addingTimeInterval(2), now: t0.addingTimeInterval(3)))
        // 打字在報信之前，不算（是上一輪的）
        XCTAssertFalse(HomeReturn.shouldWalkHome(awayFromHome: true, deliveredAt: t0, typedAt: t0.addingTimeInterval(-30), now: t0.addingTimeInterval(3)))
        // 被拖走、沒有報信紀錄：也回家
        XCTAssertTrue(HomeReturn.shouldWalkHome(awayFromHome: true, deliveredAt: nil, typedAt: nil, now: t0))
        // 已經在家門口：不用走
        XCTAssertFalse(HomeReturn.shouldWalkHome(awayFromHome: false, deliveredAt: t0, typedAt: nil, now: t0.addingTimeInterval(60)))
    }

    func testHookInstallerKeepsOtherHooksAndReplacesOldPaths() {
        let mine = "/bin/sh '/Users/u/Library/Application Support/MixKeeper/send-event.sh' stop"
        let theirs: [String: Any] = ["type": "command", "command": "/Users/u/Scripts/notify.py"]
        let oldClone: [String: Any] = ["type": "command", "command": "/bin/sh '/Users/u/utuvo-mix-keeper/hooks/send-event.sh' stop"]
        let settings: [String: Any] = [
            "theme": "dark",
            "hooks": ["Stop": [["hooks": [theirs, oldClone]]], "PreToolUse": [["matcher": "Bash", "hooks": [theirs]]]],
        ]
        let installed = HookInstaller.updated(settings, script: "/Users/u/Library/Application Support/MixKeeper/send-event.sh")
        XCTAssertTrue(HookInstaller.isInstalled(installed))
        XCTAssertEqual(installed["theme"] as? String, "dark")
        let stop = (installed["hooks"] as! [String: Any])["Stop"] as! [[String: Any]]
        let commands = stop.flatMap { ($0["hooks"] as! [[String: Any]]).compactMap { $0["command"] as? String } }
        XCTAssertEqual(commands, ["/Users/u/Scripts/notify.py", mine])   // 舊 clone 路徑被換掉，別人的留著
        let removed = HookInstaller.updated(installed, script: nil)
        XCTAssertFalse(HookInstaller.isInstalled(removed))
        let hooks = removed["hooks"] as! [String: Any]
        XCTAssertEqual(Set(hooks.keys), ["Stop", "PreToolUse"])
        XCTAssertEqual(((hooks["Stop"] as! [[String: Any]])[0]["hooks"] as! [[String: Any]]).count, 1)
        XCTAssertNil(HookInstaller.updated(["hooks": ["Stop": [["hooks": [oldClone]]]]], script: nil)["hooks"])
    }

    func testHookCommandQuotesPathsWithApostrophes() {
        XCTAssertEqual(HookInstaller.command(script: "/Users/o'neil/send-event.sh", kind: "stop"), "/bin/sh '/Users/o'\\''neil/send-event.sh' stop")
    }

    func testSessionsDoNotClearEachOther() {
        let t = SessionTracker()
        t.handle(.init(kind: .stop, cliSessionID: "a"))
        t.handle(.init(kind: .stop, cliSessionID: "b"))
        t.handle(.init(kind: .end, cliSessionID: "a"))
        XCTAssertEqual(t.cards.map(\.cliSessionID), ["b"])
    }

    func testJumpPlannerPrefersTtyThenDesktopThenFallback() {
        XCTAssertEqual(JumpPlanner.target(tty: "/dev/ttys012", localID: "local_abc"), .terminalTab(tty: "/dev/ttys012"))
        XCTAssertEqual(JumpPlanner.target(tty: "", localID: "local_abc-1"),
                       .desktop(URL(string: "claude://code/continue?session=local_abc-1")!))
        XCTAssertEqual(JumpPlanner.target(tty: "", localID: nil), .bringClaudeForward)
    }

    func testJumpPlannerRejectsUnsafeValues() {
        XCTAssertEqual(JumpPlanner.target(tty: "/dev/ttys1\" & do shell script \"x", localID: "local_a&b=c"), .bringClaudeForward)
    }

    func testLocatorFindsSessionAndIgnoresOthers() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let dir = root.appendingPathComponent("x/y")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try #"{"sessionId":"local_1","cliSessionId":"cli-1","title":"第一條 \"線\""}"#.write(to: dir.appendingPathComponent("local_1.json"), atomically: true, encoding: .utf8)
        try #"{"sessionId":"local_2","cliSessionId":"cli-2","title":"第二條"}"#.write(to: dir.appendingPathComponent("local_2.json"), atomically: true, encoding: .utf8)
        let locator = SessionLocator(root: root)
        XCTAssertEqual(locator.find(cliSessionID: "cli-1"), DesktopSession(localID: "local_1", title: "第一條 \"線\""))
        XCTAssertNil(locator.find(cliSessionID: "cli-9"))
        try #"{"sessionId":"local_3","cliSessionId":"cli-3","scheduledTaskId":"daily"}"#.write(to: dir.appendingPathComponent("local_3.json"), atomically: true, encoding: .utf8)
        XCTAssertEqual(locator.find(cliSessionID: "cli-3")?.scheduled, true)
    }

    func testPolicySkipsBackgroundAndScheduledRuns() {
        let desktop = DesktopSession(localID: "local_1", title: "")
        let scheduled = DesktopSession(localID: "local_2", title: "", scheduled: true)
        XCTAssertFalse(CardPolicy.shouldShow(kind: .stop, tty: "", desktop: nil, turnSeconds: 90))
        XCTAssertFalse(CardPolicy.shouldShow(kind: .permission, tty: "", desktop: scheduled, turnSeconds: nil))
        XCTAssertTrue(CardPolicy.shouldShow(kind: .stop, tty: "", desktop: desktop, turnSeconds: 90))
        XCTAssertTrue(CardPolicy.shouldShow(kind: .stop, tty: "/dev/ttys001", desktop: nil, turnSeconds: nil))
    }

    func testPolicyQuietsShortDoneOnlyNeverPermission() {
        let desktop = DesktopSession(localID: "local_1", title: "")
        XCTAssertFalse(CardPolicy.shouldShow(kind: .stop, tty: "", desktop: desktop, turnSeconds: 5))
        XCTAssertTrue(CardPolicy.shouldShow(kind: .stop, tty: "", desktop: desktop, turnSeconds: 40))
        XCTAssertTrue(CardPolicy.shouldShow(kind: .permission, tty: "", desktop: desktop, turnSeconds: 5))
    }

    func testRemoteSessionGetsCardAndJumpButPlainHeadlessDoesNot() {
        let remote = RemoteSession(bridgeID: "session_01Abc", title: "")
        XCTAssertTrue(CardPolicy.shouldShow(kind: .stop, tty: "", desktop: nil, remote: remote, turnSeconds: 90))
        XCTAssertFalse(CardPolicy.shouldShow(kind: .stop, tty: "", desktop: nil, remote: nil, turnSeconds: 90))
        XCTAssertEqual(JumpPlanner.target(tty: "", localID: nil, bridgeID: "session_01Abc"),
                       .desktop(URL(string: "claude://code/session_01Abc")!))
        XCTAssertEqual(JumpPlanner.target(tty: "", localID: nil, bridgeID: "session_01&x=1"), .bringClaudeForward)
    }

    func testRemoteLocatorReadsBridgeIDAndTitle() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try #"{"sessionId":"cli-1","bridgeSessionId":"session_01A"}"#.write(to: root.appendingPathComponent("1.json"), atomically: true, encoding: .utf8)
        try #"{"sessionId":"cli-2"}"#.write(to: root.appendingPathComponent("2.json"), atomically: true, encoding: .utf8)
        let log = root.appendingPathComponent("rc.log")
        try "x session_01A?from=cli\u{07}Attached\u{1B}]8;;\u{07}\nx session_01A?from=cli\u{07}混音守門員\u{1B}]8;;\u{07}\n".write(to: log, atomically: true, encoding: .utf8)
        let locator = RemoteSessionLocator(sessions: root, log: log)
        XCTAssertEqual(locator.find(cliSessionID: "cli-1"), RemoteSession(bridgeID: "session_01A", title: "混音守門員"))
        XCTAssertNil(locator.find(cliSessionID: "cli-2"))
    }

    func testBranchFromHeadAndWorktreeFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let git = root.appendingPathComponent("repo/.git")
        let sub = root.appendingPathComponent("repo/a/b")
        try FileManager.default.createDirectory(at: git, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "ref: refs/heads/feature/x\n".write(to: git.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
        XCTAssertEqual(GitBranch.read(cwd: sub.path), "feature/x")
    }
}

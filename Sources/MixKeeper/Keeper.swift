import AppKit
import MixKeeperCore

/// 角色行為與卡片的總管。
///
/// 規則：沒事就待在家附近；事情處理完一定走回家、進門、關門；
/// 有事就開門衝到游標旁。只會在自家門口打瞌睡，不會睡在路上。
final class Keeper {
    private static let size = NSSize(width: 112, height: 112)
    private static let dashSpeed: CGFloat = 4200
    private static let strollSpeed: CGFloat = 100
    private static let walkHomeSpeed: CGFloat = 220
    private static let yardWidth: CGFloat = 260
    private static let nearHome: CGFloat = 40

    private enum Place { case inside, outside }

    private let panel = KeeperPanel(size: Keeper.size)
    private let view: PetView
    private let house: House
    private let cardPanel = CardPanel()
    private let dust = Dust()
    private let tracker = SessionTracker()
    private let locator = SessionLocator()
    private let remoteLocator = RemoteSessionLocator()
    private var turnStarted: [String: Date] = [:]
    private var infos: [String: (branch: String, title: String, localID: String?, bridgeID: String?)] = [:]
    private var moveTimer: Timer?
    private var place = Place.inside
    private var busy = false            // 正在進出門，別的動作先等
    private var nextIdle = Date()
    private var restUntil = Date()
    private var sleepingUntil: Date?
    private var dragging = false
    private var deliveredAt: Date?
    private var typedAt: Date?
    private var statusItem: NSStatusItem?
    private var characterItems: [PetCharacter: NSMenuItem] = [:]

    init(character: PetCharacter) {
        view = PetView(frame: NSRect(origin: .zero, size: Self.size), images: loadImages(character))
        house = House(style: character.houseStyle)
        panel.contentView = view
        view.walkFrames = loadWalkFrames(character)
        log("character=\(character.rawValue) walkFrames=\(view.walkFrames.count)")
        view.onClick = { [weak self] in self?.tapped() }
        view.onDrag = { [weak self] in
            self?.dragging = true
            self?.stopWalking()
        }
        view.onDragEnd = { [weak self] in self?.dragEnded() }
        view.onPetted = { [weak self] in self?.view.heart() }
        cardPanel.onOpen = { [weak self] in self?.open($0) }
        cardPanel.onClose = { [weak self] in self?.close($0) }
        house.onClick = { [weak self] in self?.houseClicked() }
        house.onMoved = { [weak self] in self?.houseMoved() }
    }

    func start() {
        house.start()
        panel.setFrameOrigin(house.doorOrigin(for: Self.size))
        view.show(.idle)
        setupMenu()
        restUntil = Date().addingTimeInterval(2)
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
    }

    // MARK: 事件

    func receive(_ event: KeeperEvent, entry: String) {
        let id = event.cliSessionID
        if event.kind == .submit {
            turnStarted[id] = event.at
            typedAt = event.at   // 你在某個 session 打字了：人在 Claude 裡，Claw'd 回家
        }
        if event.kind == .submit || event.kind == .end {
            let had = !tracker.cards.isEmpty
            tracker.handle(event)
            defer { if had { cardsMaybeCleared() } }
            if event.kind == .end { infos[id] = nil; turnStarted[id] = nil }
            log("\(event.kind.rawValue) entry=\(entry.isEmpty ? "-" : entry)")
            refresh()
            return
        }
        let found = locator.find(cliSessionID: id)
        let remote = found == nil ? remoteLocator.find(cliSessionID: id) : nil
        let turn = turnStarted[id].map { event.at.timeIntervalSince($0) }
        let show = CardPolicy.shouldShow(kind: event.kind, tty: event.tty, desktop: found, remote: remote, turnSeconds: turn)
        log("\(event.kind.rawValue) entry=\(entry.isEmpty ? "-" : entry) tty=\(event.tty.isEmpty ? "-" : "yes") desktop=\(found == nil ? "no" : "yes") remote=\(remote == nil ? "no" : "yes") scheduled=\(found?.scheduled == true) show=\(show)")
        guard show else { return }
        infos[id] = (GitBranch.read(cwd: event.cwd), found?.title ?? remote?.title ?? "", found?.localID, remote?.bridgeID)
        let before = tracker.cards.map(\.kind)
        tracker.handle(event)
        if tracker.cards.map(\.kind) != before, !tracker.cards.isEmpty {
            deliver()
        } else {
            refresh()
        }
    }

    /// 有事：在家就開門出來，然後衝到游標旁。
    private func deliver() {
        sleepingUntil = nil
        guard !dragging else { refresh(); return }
        comeOut { [weak self] in
            guard let self, !self.tracker.cards.isEmpty else { return }
            self.view.show(.alert)
            self.dash(to: self.besideCursor()) { [weak self] in
                self?.deliveredAt = Date()
                self?.refresh()
            }
            self.refresh()
        }
    }

    private func besideCursor() -> NSPoint {
        let cursor = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(cursor) }?.visibleFrame ?? panel.frame
        var target = NSPoint(x: cursor.x + 26, y: cursor.y - Self.size.height - 26)
        target.x = min(max(target.x, screen.minX), screen.maxX - Self.size.width)
        target.y = min(max(target.y, screen.minY), screen.maxY - Self.size.height)
        return target
    }

    private func refresh() {
        let cards = tracker.cards.map(info(for:))
        cardPanel.show(place == .outside ? cards : [], beside: panel.frame)
        statusItem?.button?.title = cards.isEmpty ? "◉" : "◉ \(cards.count)"
        if cards.isEmpty, sleepingUntil == nil, place == .outside { view.show(.idle) }
    }

    private func info(for card: KeeperCard) -> CardInfo {
        let extra = infos[card.cliSessionID]
        let source: String
        if !card.tty.isEmpty {
            source = "Terminal \(card.tty.replacingOccurrences(of: "/dev/", with: ""))"
        } else if extra?.localID != nil {
            source = L.t("Claude 桌面版", "Claude Desktop")
        } else if extra?.bridgeID != nil {
            source = "Remote Control"
        } else {
            source = "Claude"
        }
        return CardInfo(id: card.cliSessionID, kind: card.kind,
                        project: URL(fileURLWithPath: card.cwd).lastPathComponent,
                        branch: extra?.branch ?? "", source: source,
                        title: extra?.title ?? "", since: card.since)
    }

    private func open(_ card: CardInfo) {
        let tty = tracker.cards.first { $0.cliSessionID == card.id }?.tty ?? ""
        let target = JumpPlanner.target(tty: tty, localID: infos[card.id]?.localID, bridgeID: infos[card.id]?.bridgeID)
        log("jump \(String(describing: target).prefix(12))")
        Jumper.jump(to: target)
        close(card)
    }

    private func close(_ card: CardInfo) {
        tracker.dismiss(card.id)
        refresh()
        cardsMaybeCleared()
    }

    /// 最後一張卡片處理完：不管在哪裡，直接回家進門。
    private func cardsMaybeCleared() {
        guard tracker.cards.isEmpty, place == .outside else { return }
        nextIdle = Date().addingTimeInterval(1.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, self.tracker.cards.isEmpty, self.place == .outside, !self.dragging, self.moveTimer == nil else { return }
            self.goHome()
        }
    }

    // MARK: 家

    /// 開門、出現在門口；已經在外面就直接繼續。
    private func comeOut(then next: @escaping () -> Void) {
        guard place == .inside else { next(); return }
        busy = true
        place = .outside
        restUntil = .distantFuture
        log("pet out")
        house.setDoor(open: true)
        panel.setFrameOrigin(house.doorOrigin(for: Self.size))
        view.facingLeft = false
        view.show(.idle)
        view.fadeIn()
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.busy = false
            next()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            if self?.place == .outside { self?.house.setDoor(open: false) }
        }
    }

    /// 走回門口、開門進去、關門，在家休息一陣子。
    private func goHome(speed: CGFloat = Keeper.walkHomeSpeed) {
        guard place == .outside, !busy else { return }
        log("goHome cards=\(tracker.cards.count) falling=\(panel.frame.minY - house.groundY > 2)")
        sleepingUntil = nil
        view.show(tracker.cards.isEmpty ? .idle : .alert)
        cardPanel.show([], beside: panel.frame)   // 走路時先收起卡片，到門口再拿出來
        // 在半空中（剛報完信）：先掉到地上、落地揚一團土，再沿地板走回家。
        if panel.frame.minY - house.groundY > 2 {
            busy = true
            walk(to: NSPoint(x: panel.frame.minX, y: house.groundY), speed: 1600, falling: true) { [weak self] in
                guard let self else { return }
                self.kickUpDust(at: self.panel.frame.origin, back: -1, count: 2, scale: 1.2)
                self.kickUpDust(at: self.panel.frame.origin, back: 1, count: 2, scale: 1.2)
                self.view.hop()
                self.busy = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.goHome(speed: speed) }
            }
            return
        }
        walk(to: house.doorOrigin(for: Self.size), speed: speed) { [weak self] in
            guard let self else { return }
            guard self.tracker.cards.isEmpty else {
                // 還有沒處理的卡片：在門口拿著等，卡片放在門口，點了一樣會跳回去
                log("waiting at door with \(self.tracker.cards.count) card(s)")
                self.view.show(.alert)
                self.refresh()
                return
            }
            self.busy = true
            self.house.setDoor(open: true)
            self.view.fadeOut { [weak self] in
                guard let self else { return }
                self.panel.orderOut(nil)
                self.place = .inside
                self.busy = false
                log("pet home")
                self.restUntil = Date().addingTimeInterval(.random(in: 60...180))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    if self?.place == .inside { self?.house.setDoor(open: false) }
                }
            }
        }
    }

    private func distanceFromDoor() -> CGFloat {
        let door = house.doorOrigin(for: Self.size)
        return hypot(panel.frame.minX - door.x, panel.frame.minY - door.y)
    }

    private func houseClicked() {
        if place == .inside {
            comeOut { [weak self] in self?.nextIdle = Date().addingTimeInterval(4) }
        }
    }

    private func houseMoved() {
        if place == .inside { panel.setFrameOrigin(house.doorOrigin(for: Self.size)) }
        nextIdle = Date().addingTimeInterval(2)
    }

    // MARK: 平常

    private func tick() {
        guard !dragging, !busy, moveTimer == nil else { return }
        let now = Date()
        if !tracker.cards.isEmpty {
            // 有卡片沒處理也一定回家，只是停在門口等，不進門。
            let away = place == .outside && (abs(panel.frame.minY - house.groundY) > 2 || distanceFromDoor() > Self.nearHome)
            if HomeReturn.shouldWalkHome(awayFromHome: away, deliveredAt: deliveredAt, typedAt: typedAt, now: now) {
                log("walk home with cards waiting")
                goHome()
            }
            return
        }
        if place == .inside {
            if now >= restUntil { comeOut { [weak self] in self?.nextIdle = Date().addingTimeInterval(3) } }
            return
        }
        if let until = sleepingUntil {
            guard now >= until else { return }
            sleepingUntil = nil
            view.show(.idle)
            nextIdle = now.addingTimeInterval(3)
            return
        }
        guard now >= nextIdle else { return }
        // 離家太遠（剛報完信、被拖走、家被搬走）：先回家，不在路上睡。
        if abs(panel.frame.minY - house.groundY) > 2 || distanceFromDoor() > Self.yardWidth + Self.nearHome {
            log("walk home from far")
            goHome()
            return
        }
        switch Int.random(in: 0..<6) {
        case 0:
            goHome()
        case 1 where distanceFromDoor() <= Self.nearHome:
            sleepingUntil = now.addingTimeInterval(.random(in: 30...90))
            view.show(.sleep)
        case 1:
            walk(to: house.doorOrigin(for: Self.size), speed: Self.strollSpeed) { [weak self] in self?.nextIdle = Date() }
        default:
            let door = house.doorOrigin(for: Self.size)
            let screen = NSScreen.screens.first { $0.frame.intersects(house.frame) }?.visibleFrame ?? house.frame
            let low = max(screen.minX, door.x - Self.yardWidth)
            let high = min(screen.maxX - Self.size.width, door.x + Self.yardWidth)
            walk(to: NSPoint(x: .random(in: low...max(low, high)), y: house.groundY), speed: Self.strollSpeed) { [weak self] in
                self?.nextIdle = Date().addingTimeInterval(.random(in: 6...16))
            }
        }
    }

    private func dash(to target: NSPoint, done: @escaping () -> Void) {
        walk(to: target, speed: Self.dashSpeed, done: done)
    }

    private func walk(to target: NSPoint, speed: CGFloat, falling: Bool = false, done: @escaping () -> Void) {
        moveTimer?.invalidate()
        if !falling { view.facingLeft = target.x < panel.frame.minX }
        let dashing = speed > 300 && !falling
        view.setWalking(!falling, speed: speed)
        // 位置自己記：視窗座標會被取整數，斜走的小位移讀回來就不見了。
        var now = panel.frame.origin
        // 只有踩在地上走、或衝刺時才揚塵；在半空中不會。
        let onGround = abs(now.y - target.y) < 1 && abs(now.y - house.groundY) < 2
        let dusty = dashing || onGround
        let back: CGFloat = target.x < now.x ? 1 : -1
        let spacing: CGFloat = dashing ? 110 : 26
        var sinceDust = spacing  // 起步就揚一團
        if dashing { kickUpDust(at: now, back: back, count: 3, scale: 1.5) }

        let finish = { [weak self] in
            guard let self else { return }
            self.panel.setFrameOrigin(target)
            self.moveTimer?.invalidate()
            self.moveTimer = nil
            self.view.setWalking(false)
            if dashing { self.kickUpDust(at: target, back: -back, count: 3, scale: 1.3) }  // 煞車
            done()
        }

        moveTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let dx = target.x - now.x, dy = target.y - now.y
            let distance = hypot(dx, dy)
            let step = speed / 60
            if distance <= step { finish(); return }
            // 衝刺一格就跨好幾團的距離，沿路補齊，塵土才連成一串。
            var travelled: CGFloat = 0
            while sinceDust + step - travelled >= spacing && travelled < step {
                let along = spacing - sinceDust
                travelled += along
                sinceDust = 0
                let point = NSPoint(x: now.x + dx / distance * travelled, y: now.y + dy / distance * travelled)
                if dusty { self.kickUpDust(at: point, back: back, count: 1, scale: dashing ? 1.2 : 0.75) }
            }
            sinceDust += step - travelled
            now = NSPoint(x: now.x + dx / distance * step, y: now.y + dy / distance * step)
            self.panel.setFrameOrigin(now)
        }
    }

    /// `origin`：角色視窗原點；塵土揚在腳後跟。
    private func kickUpDust(at origin: NSPoint, back: CGFloat, count: Int, scale: CGFloat) {
        for i in 0..<count {
            let feet = NSPoint(x: origin.x + Self.size.width / 2 + back * (18 + CGFloat(i) * 14), y: origin.y + 2)
            dust.puff(at: feet, back: back, scale: scale)
        }
    }

    private func stopWalking() {
        moveTimer?.invalidate()
        moveTimer = nil
        view.setWalking(false)
        view.show(tracker.cards.isEmpty ? .idle : .alert)
    }

    private func tapped() {
        view.hop()
        if sleepingUntil != nil {
            sleepingUntil = nil
            view.show(.idle)
            nextIdle = Date().addingTimeInterval(3)
        }
    }

    private func dragEnded() {
        dragging = false
        deliveredAt = Date()   // 有卡片的話，被拖走後也會等一下再回家
        moveTimer = nil
        sleepingUntil = nil
        nextIdle = Date().addingTimeInterval(5)
        refresh()
    }

    // MARK: 選單列

    private func setupMenu() {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            statusItem?.button?.title = "◉"
        }
        let menu = NSMenu()
        menu.addItem(MenuAction(L.t("叫過來", "Bring Here")) { [weak self] in self?.summon() })
        menu.addItem(MenuAction(L.t("回家", "Go Home")) { [weak self] in self?.goHome(speed: Self.dashSpeed / 3) })
        menu.addItem(.separator())
        characterItems = [:]
        for character in PetCharacter.allCases where !loadImages(character).isEmpty {
            let item = MenuAction(character.title) { [weak self] in self?.change(to: character) }
            characterItems[character] = item
            menu.addItem(item)
        }
        updateCharacterChecks()
        menu.addItem(.separator())
        let settings = NSMenuItem(title: L.t("設定", "Settings"), action: nil, keyEquivalent: "")
        settings.submenu = settingsMenu()
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(MenuAction(L.t("結束混音守門員", "Quit Mix Keeper")) { NSApp.terminate(nil) })
        statusItem?.menu = menu
    }

    private func settingsMenu() -> NSMenu {
        let menu = NSMenu()
        let login = MenuAction(L.t("開機自動開啟", "Open at Login")) { [weak self] in
            LoginItem.set(!LoginItem.isOn)
            self?.setupMenu()
        }
        login.state = LoginItem.isOn ? .on : .off
        menu.addItem(login)
        menu.addItem(MenuAction(L.t("把家搬回右下角", "Move Home to Corner")) { [weak self] in self?.house.moveToCorner() })
        menu.addItem(.separator())
        let names: [(LanguageChoice, String)] = [(.system, L.t("跟隨系統語言", "Match System")), (.zh, "繁體中文"), (.en, "English")]
        for (choice, name) in names {
            let item = MenuAction(name) { [weak self] in
                L.choice = choice
                self?.setupMenu()
                self?.refresh()
            }
            item.state = L.choice == choice ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    private func change(to character: PetCharacter) {
        PetCharacter.saved = character
        view.images = loadImages(character)
        view.walkFrames = loadWalkFrames(character)
        house.load(character.houseStyle)
        if place == .inside { panel.setFrameOrigin(house.doorOrigin(for: Self.size)) }
        updateCharacterChecks()
        view.show(tracker.cards.isEmpty ? (sleepingUntil == nil ? .idle : .sleep) : .alert)
    }

    private func updateCharacterChecks() {
        for (character, item) in characterItems { item.state = character == PetCharacter.saved ? .on : .off }
    }

    private func summon() {
        comeOut { [weak self] in
            guard let self else { return }
            self.sleepingUntil = nil
            self.view.show(.idle)
            self.dash(to: self.besideCursor()) { [weak self] in self?.nextIdle = Date().addingTimeInterval(20) }
        }
    }
}

private final class MenuAction: NSMenuItem {
    private let run: () -> Void

    init(_ title: String, run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func fire() { run() }
}

func log(_ text: String) {
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/log/mix-keeper.log")
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(text)\n"
    if let handle = try? FileHandle(forWritingTo: url) {
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    } else {
        try? line.write(to: url, atomically: true, encoding: .utf8)
    }
}

import AppKit
import MixKeeperCore

/// 角色的家：可拖動，位置記住；白天晚上依所在地日照換圖，門可開關。
final class House {
    static let size = NSSize(width: 168, height: 168)
    private static let originKey = "homeOrigin"

    let panel = KeeperPanel(size: House.size, level: .statusBar)
    private let view: HouseView
    private var images: [String: NSImage] = [:]
    private var doorFraction: CGFloat = 0.5
    private let coordinate = ZoneTab.current()
    private var open = false
    private(set) var daylight = Daylight.day

    var onClick: () -> Void = {}
    var onMoved: () -> Void = {}

    init(style: String) {
        view = HouseView(frame: NSRect(origin: .zero, size: House.size))
        load(style)
        panel.contentView = view
        view.onClick = { [weak self] in self?.onClick() }
        view.onDragEnd = { [weak self] in self?.saveOrigin(); self?.onMoved() }
    }

    /// 換房子款式（換角色時）。該款式的圖不在就留用原本的。
    func load(_ style: String) {
        guard let folder = assetFolder(style) ?? assetFolder("house") else { return }
        var images: [String: NSImage] = [:]
        for name in ["day-closed", "day-open", "night-closed", "night-open"] {
            images[name] = NSImage(contentsOf: folder.appendingPathComponent("\(name).png"))
        }
        guard images.count == 4 else { return }
        log("house style=\(folder.lastPathComponent)")
        self.images = images
        doorFraction = 0.5
        if let data = try? Data(contentsOf: folder.appendingPathComponent("house.json")),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Double], let x = json["doorX"] {
            doorFraction = CGFloat(x)
        }
        render()
    }

    func start() {
        panel.setFrameOrigin(savedOrigin() ?? defaultOrigin())
        updateDaylight()
        panel.orderFrontRegardless()
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.updateDaylight() }
        log("house daylight=\(daylight.rawValue) located=\(coordinate != nil)")
    }

    /// 角色站在門口時的視窗原點。
    func doorOrigin(for petSize: NSSize) -> NSPoint {
        NSPoint(x: panel.frame.minX + panel.frame.width * doorFraction - petSize.width / 2, y: panel.frame.minY)
    }

    var groundY: CGFloat { panel.frame.minY }
    var frame: NSRect { panel.frame }

    func setDoor(open: Bool) {
        self.open = open
        render()
    }

    func moveToCorner() {
        panel.setFrameOrigin(defaultOrigin())
        saveOrigin()
        onMoved()
    }

    private func updateDaylight() {
        // 測試用：MIXKEEPER_FORCE_DAYLIGHT=night 直接看夜景。
        let forced = ProcessInfo.processInfo.environment["MIXKEEPER_FORCE_DAYLIGHT"].flatMap(Daylight.init)
        let now = forced ?? Daylight.at(Date(), coordinate)
        if now != daylight { log("house daylight=\(now.rawValue)") }
        daylight = now
        render()
    }

    private func render() {
        view.image = images["\(daylight.rawValue)-\(open ? "open" : "closed")"]
    }

    private func defaultOrigin() -> NSPoint {
        let screen = NSScreen.main?.visibleFrame ?? .zero
        return NSPoint(x: screen.maxX - House.size.width - 24, y: screen.minY)
    }

    private func savedOrigin() -> NSPoint? {
        guard let values = UserDefaults.standard.array(forKey: Self.originKey) as? [Double], values.count == 2 else { return nil }
        let origin = NSPoint(x: values[0], y: values[1])
        // 那台螢幕不在了就回預設位置。
        let frame = NSRect(origin: origin, size: House.size)
        return NSScreen.screens.contains { $0.frame.intersects(frame) } ? origin : nil
    }

    private func saveOrigin() {
        UserDefaults.standard.set([Double(panel.frame.minX), Double(panel.frame.minY)], forKey: Self.originKey)
    }
}

private final class HouseView: NSView {
    private let imageLayer = CALayer()
    private var dragStart: NSPoint?
    private var windowStart: NSPoint?
    private var dragged = false

    var onClick: () -> Void = {}
    var onDragEnd: () -> Void = {}

    var image: NSImage? {
        didSet {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.25)
            imageLayer.contents = image
            CATransaction.commit()
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        imageLayer.frame = bounds
        imageLayer.contentsGravity = .resizeAspect
        layer?.addSublayer(imageLayer)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        dragStart = NSEvent.mouseLocation
        windowStart = window?.frame.origin
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart, let windowStart else { return }
        let now = NSEvent.mouseLocation
        if hypot(now.x - dragStart.x, now.y - dragStart.y) > 3 { dragged = true }
        if dragged { window?.setFrameOrigin(NSPoint(x: windowStart.x + now.x - dragStart.x, y: windowStart.y + now.y - dragStart.y)) }
    }

    override func mouseUp(with event: NSEvent) {
        dragged ? onDragEnd() : onClick()
    }
}

func assetFolder(_ name: String) -> URL? {
    let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let candidates = [Bundle.main.resourceURL?.appendingPathComponent(name), source.appendingPathComponent("assets/\(name)")].compactMap { $0 }
    return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
}

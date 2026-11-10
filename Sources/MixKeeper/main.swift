import AppKit
import MixKeeperCore

func loadImages(_ character: PetCharacter) -> [PetPose: NSImage] {
    guard let folder = assetFolder("pet") else { return [:] }
    var images: [PetPose: NSImage] = [:]
    for pose in PetPose.allCases {
        images[pose] = NSImage(contentsOf: folder.appendingPathComponent("\(character.rawValue)/\(pose.rawValue).png"))
    }
    return images
}

// 測試／自動化：MixKeeper --hooks install|uninstall|status
if let index = CommandLine.arguments.firstIndex(of: "--hooks") {
    let value = CommandLine.arguments.dropFirst(index + 1).first ?? "status"
    if value == "install" || value == "uninstall" { try HookSetup.set(value == "install") }
    print("hooks installed:", HookSetup.isInstalled, HookSetup.scriptURL.path)
    exit(0)
}

if let index = CommandLine.arguments.firstIndex(of: "--login-item") {
    let value = CommandLine.arguments.dropFirst(index + 1).first
    if value == "on" || value == "off" { LoginItem.set(value == "on") }
    print("login item enabled:", LoginItem.isOn)
    exit(0)
}

func loadWalkFrames(_ character: PetCharacter) -> [NSImage] {
    guard let folder = assetFolder("pet") else { return [] }
    var frames: [NSImage] = []
    for i in 1...4 {
        guard let image = NSImage(contentsOf: folder.appendingPathComponent("\(character.rawValue)/walk\(i).png")) else { break }
        frames.append(image)
    }
    return frames.count >= 2 ? frames : []
}

// 發文素材：MixKeeper --card-snapshot <輸出.png> [zh|en]
if let index = CommandLine.arguments.firstIndex(of: "--card-snapshot"), CommandLine.arguments.count > index + 1 {
    _ = NSApplication.shared
    if CommandLine.arguments.count > index + 2, let lang = LanguageChoice(rawValue: CommandLine.arguments[index + 2]) { L.choice = lang }
    let now = Date()
    let cards = [
        CardInfo(id: "a", kind: .needsPermission, project: "utuvo-monitor", branch: "main", source: L.t("Claude 桌面版", "Claude Desktop"),
                 title: L.t("Monitor 修正錶頭", "Fix the meter"), since: now.addingTimeInterval(-180)),
        CardInfo(id: "b", kind: .done, project: "utuvo-site", branch: "claude/home-page", source: "Remote Control",
                 title: L.t("官網首頁改版", "Home page refresh"), since: now.addingTimeInterval(-40)),
    ]
    try snapshotCards(cards, to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let keeper = Keeper(character: PetCharacter.saved)
let token = try KeeperToken.loadOrCreate()
let server = EventServer(token: token) { event, entry in keeper.receive(event, entry: entry) }
try server.start()
keeper.start()
LoginItem.setUpOnFirstLaunch()
app.run()

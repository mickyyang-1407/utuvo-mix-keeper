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

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let keeper = Keeper(character: PetCharacter.saved)
let token = try KeeperToken.loadOrCreate()
let server = EventServer(token: token) { event, entry in keeper.receive(event, entry: entry) }
try server.start()
keeper.start()
LoginItem.setUpOnFirstLaunch()
app.run()

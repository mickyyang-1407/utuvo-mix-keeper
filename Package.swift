// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MixKeeper",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "MixKeeperCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "MixKeeper", dependencies: ["MixKeeperCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "MixKeeperCoreTests", dependencies: ["MixKeeperCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)

// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CLINotify",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "CLINotifyShared", targets: ["CLINotifyShared"]),
        .executable(name: "CLINotifyApp", targets: ["CLINotifyApp"]),
        .executable(name: "clinotify", targets: ["clinotify"])
    ],
    targets: [
        .target(name: "CLINotifyShared"),
        .target(name: "CLINotifyObjCSupport"),
        .target(
            name: "CLINotifyPixelArt",
            dependencies: ["CLINotifyShared"]
        ),
        .executableTarget(
            name: "CLINotifyApp",
            dependencies: ["CLINotifyShared", "CLINotifyObjCSupport", "CLINotifyPixelArt"]
        ),
        .executableTarget(
            name: "clinotify",
            dependencies: ["CLINotifyShared"]
        ),
        .executableTarget(
            name: "pixelpreview",
            dependencies: ["CLINotifyShared", "CLINotifyPixelArt"]
        ),
        .testTarget(
            name: "CLINotifyTests",
            dependencies: ["CLINotifyShared", "CLINotifyPixelArt"]
        )
    ],
    swiftLanguageModes: [.v5]
)

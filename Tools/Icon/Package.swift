// swift-tools-version: 6.0
import PackageDescription

// Draws the Rimwatch app icon in code and writes a 1024x1024 opaque sRGB PNG.
// It draws the game's emblem ("The Rim"), whose geometry is `Emblem` in GameCore.
//
// Regenerate the icon (from the repo root):
//   swift run --package-path Tools/Icon Icon Rimwatch/Assets.xcassets/AppIcon.appiconset/AppIcon.png
// With no argument it writes AppIcon.png in the current directory.
let package = Package(
    name: "Icon",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../../GameCore"),
    ],
    targets: [
        .executableTarget(name: "Icon", dependencies: [.product(name: "GameCore", package: "GameCore")]),
    ]
)

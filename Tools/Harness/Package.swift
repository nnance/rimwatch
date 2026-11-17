// swift-tools-version: 6.0
import PackageDescription

// Runs the scripted bots from GameCore over many seeds and prints difficulty statistics.
// The bots only exist in DEBUG builds of GameCore, so build with:
//   swift build -c release -Xswiftc -DDEBUG
let package = Package(
    name: "Harness",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../../GameCore"),
    ],
    targets: [
        .executableTarget(name: "Harness", dependencies: [.product(name: "GameCore", package: "GameCore")]),
    ]
)

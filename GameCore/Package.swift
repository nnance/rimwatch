// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GameCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "GameCore", targets: ["GameCore", "RidgelineCore", "RedoubtCore", "RiftwingCore"]),
    ],
    targets: [
        .target(name: "GameCore"),
        .target(name: "RidgelineCore", dependencies: ["GameCore"]),
        .target(name: "RedoubtCore", dependencies: ["GameCore"]),
        .target(name: "RiftwingCore", dependencies: ["GameCore"]),
        .testTarget(name: "GameCoreTests", dependencies: ["GameCore"]),
        .testTarget(name: "RidgelineCoreTests", dependencies: ["GameCore", "RidgelineCore"]),
        .testTarget(name: "RedoubtCoreTests", dependencies: ["GameCore", "RedoubtCore"]),
        .testTarget(name: "RiftwingCoreTests", dependencies: ["GameCore", "RiftwingCore"]),
    ]
)

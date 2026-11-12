// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PokerChipCase",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PokerCore", targets: ["PokerCore"]),
        .library(name: "PokerNet", targets: ["PokerNet"]),
        .library(name: "PokerSession", targets: ["PokerSession"]),
    ],
    targets: [
        .target(name: "PokerCore"),
        .target(name: "PokerNet", dependencies: ["PokerCore"]),
        .target(name: "PokerSession", dependencies: ["PokerCore", "PokerNet"]),
        .testTarget(name: "PokerCoreTests", dependencies: ["PokerCore"]),
        .testTarget(name: "PokerNetTests", dependencies: ["PokerNet", "PokerCore"]),
        .testTarget(name: "PokerSessionTests", dependencies: ["PokerSession", "PokerNet", "PokerCore"]),
    ]
)

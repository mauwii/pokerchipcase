// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PokerChipCase",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PokerCore", targets: ["PokerCore"]),
        .library(name: "PokerNet", targets: ["PokerNet"]),
    ],
    targets: [
        .target(name: "PokerCore"),
        .target(name: "PokerNet", dependencies: ["PokerCore"]),
        .testTarget(name: "PokerCoreTests", dependencies: ["PokerCore"]),
        .testTarget(name: "PokerNetTests", dependencies: ["PokerNet", "PokerCore"]),
    ]
)

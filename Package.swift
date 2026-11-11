// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PokerChipCase",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PokerCore", targets: ["PokerCore"]),
    ],
    targets: [
        .target(name: "PokerCore"),
        .testTarget(name: "PokerCoreTests", dependencies: ["PokerCore"]),
    ]
)

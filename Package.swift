// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ShotCoach",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),   // macOS entry required for `swift build` / `swift test` on Mac
    ],
    products: [
        .library(name: "ShotCoachCore", targets: ["ShotCoachCore"]),
        .library(name: "ShotCoachUI",   targets: ["ShotCoachUI"]),
    ],
    targets: [
        .target(
            name: "ShotCoachCore",
            path: "Sources/ShotCoachCore"
        ),
        .target(
            name: "ShotCoachUI",
            dependencies: ["ShotCoachCore"],
            path: "Sources/ShotCoachUI"
        ),
        .target(
            name: "ShotCoachDemo",
            dependencies: ["ShotCoachCore", "ShotCoachUI"],
            path: "Sources/ShotCoachDemo"
        ),
        .testTarget(
            name: "ShotCoachCoreTests",
            dependencies: ["ShotCoachCore"],
            path: "Tests/ShotCoachCoreTests"
        ),
    ]
)

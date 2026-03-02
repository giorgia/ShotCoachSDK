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
        // ShotCoachDemo is an iOS app — it lives in DemoApp/ (source files + Xcode project).
        // It is NOT an SPM target. Build it via DemoApp/ShotCoachDemoRunner.xcodeproj.
        .testTarget(
            name: "ShotCoachCoreTests",
            dependencies: ["ShotCoachCore"],
            path: "Tests/ShotCoachCoreTests"
        ),
    ]
)

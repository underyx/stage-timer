// swift-tools-version: 6.0
import PackageDescription

// The app is built by Xcode from project.yml, not from this file. This package exists so the
// timer logic in Sources/Core, which imports nothing but Foundation and Observation, can be
// built and tested with `swift test` on any machine, Linux included, without a simulator. The app
// target compiles the same files directly; nothing imports StageTimerCore.
let package = Package(
    name: "StageTimerCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    targets: [
        .target(name: "StageTimerCore", path: "Sources/Core"),
        .testTarget(name: "StageTimerCoreTests", dependencies: ["StageTimerCore"], path: "Tests/Core"),
    ]
)

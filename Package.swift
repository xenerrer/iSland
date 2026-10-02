// swift-tools-version: 6.0
import Foundation
import PackageDescription

// With only the Command Line Tools installed, the build system sometimes forgets to hand the Swift Testing macro
// plugin to the compiler ("plugin for module 'TestingMacros' not found"), and does so intermittently. Passing its
// location explicitly makes test builds deterministic. Nothing is added where the directory does not exist
// (a full Xcode toolchain finds it by itself).
let testingPluginPath = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
let testSettings: [SwiftSetting] = FileManager.default.fileExists(atPath: testingPluginPath)
    ? [.unsafeFlags(["-plugin-path", testingPluginPath])]
    : []

let package = Package(
    name: "iSland",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "iSland", targets: ["iSland"]),
        .executable(name: "island-hook", targets: ["island-hook"]),
    ],
    targets: [
        .target(name: "IslandCore"),
        .executableTarget(name: "island-hook", dependencies: ["IslandCore"]),
        .executableTarget(name: "iSland", dependencies: ["IslandCore"]),
        .testTarget(name: "IslandCoreTests", dependencies: ["IslandCore"], swiftSettings: testSettings),
        .testTarget(name: "iSlandTests", dependencies: ["iSland", "IslandCore"], swiftSettings: testSettings),
    ],
    swiftLanguageModes: [.v5]
)

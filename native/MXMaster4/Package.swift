// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MXMaster4",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MXMaster4Core", targets: ["MXMaster4Core"]),
        .library(name: "MXMaster4IPC", targets: ["MXMaster4IPC"]),
        .library(name: "MXMaster4HID", targets: ["MXMaster4HID"]),
        .executable(name: "mx4-diagnostics", targets: ["MX4Diagnostics"]),
    ],
    targets: [
        .target(name: "MXMaster4Core"),
        .target(name: "MXMaster4IPC"),
        .target(name: "MXMaster4HID", dependencies: ["MXMaster4Core"]),
        .executableTarget(name: "MX4Diagnostics", dependencies: ["MXMaster4Core", "MXMaster4HID"]),
        .testTarget(name: "MXMaster4HIDTests", dependencies: ["MXMaster4HID"]),
        .testTarget(name: "MXMaster4CoreTests", dependencies: ["MXMaster4Core"]),
    ]
)

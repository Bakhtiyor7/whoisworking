// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Perch",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AgentCore", targets: ["AgentCore"]),
        .executable(name: "Perch", targets: ["Perch"]),
    ],
    targets: [
        // No UI. Session model, reducer, adapters, socket, discovery, hook installer.
        .target(name: "AgentCore"),
        // The notch app (AppKit + SwiftUI). Bundled into Perch.app by scripts/bundle.sh.
        .executableTarget(name: "Perch", dependencies: ["AgentCore"]),
        .testTarget(name: "AgentCoreTests", dependencies: ["AgentCore"]),
    ]
)

// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "WhoIsWorking",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AgentCore", targets: ["AgentCore"]),
        .executable(name: "WhoIsWorking", targets: ["WhoIsWorking"]),
    ],
    targets: [
        // No UI. Session model, reducer, adapters, socket, discovery, hook installer.
        .target(name: "AgentCore"),
        // The notch app (AppKit + SwiftUI). Bundled into WhoIsWorking.app by scripts/bundle.sh.
        .executableTarget(
            name: "WhoIsWorking",
            dependencies: ["AgentCore"],
            exclude: ["AgentIcons/LobeIcons-LICENSE.txt"],
            resources: [
                .embedInCode("AgentIcons/claudecode.png"),
                .embedInCode("AgentIcons/codex.png"),
            ]
        ),
        .testTarget(name: "AgentCoreTests", dependencies: ["AgentCore"]),
    ]
)

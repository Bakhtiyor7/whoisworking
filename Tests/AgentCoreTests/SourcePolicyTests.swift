import Foundation
import Testing
@testable import AgentCore

/// OSS-13. Tripwires: they fail when the source stops matching what the docs promise, so the
/// change shows up in review. They search for names, so they do not prove an absence.

private let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

/// Paths, relative to `root`, of the Swift files under `root/Sources` that match `pattern`.
private func sourceFiles(matching pattern: String, in root: URL) throws -> Set<String> {
    let regex = try NSRegularExpression(pattern: pattern)
    let sources = root.appendingPathComponent("Sources")
    let prefix = root.resolvingSymlinksInPath().path + "/"
    var found: Set<String> = []
    let walker = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
    for case let url as URL in walker where url.pathExtension == "swift" {
        let text = try String(contentsOf: url, encoding: .utf8)
        if regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
            found.insert(String(url.resolvingSymlinksInPath().path.dropFirst(prefix.count)))
        }
    }
    return found
}

/// APIs that reach the network.
private let network = [
    #"\bURLSession"#, #"\bURLRequest\b"#, #"\bNSURLConnection\b"#, #"\bimport\s+Network\b"#,
    #"\bNWConnection\b"#, #"\bNWListener\b"#, #"\bCFStream"#, #"\bCFSocket"#,
    #"\bAF_INET6?\b"#, #"\bgetaddrinfo\b"#, #"\bWKWebView\b"#, #"\bimport\s+WebKit\b"#,
].joined(separator: "|")

/// Ways to start another program. `system(` skips the enum case `system(String)` in `Ingest.swift`
/// and anything written `.system(`, such as a font or that case being thrown.
private let launch = [
    #"\bProcess\s*\("#, #"\bNSTask\b"#, #"\bposix_spawnp?\b"#, #"(?<![.\w])system\s*\((?!String\))"#,
    #"\bpopen\s*\("#, #"\bexecv[pe]*\s*\("#, #"\bfork\s*\("#, #"\bNSAppleScript\b"#,
    #"\bNSUserScriptTask\b"#, #"\bosascript\b"#,
].joined(separator: "|")

/// Asking macOS to open a file, a URL or an app.
private let workspaceOpen = #"NSWorkspace\.shared\s*\.open"#

@Suite("Source policy")
struct SourcePolicyTests {
    @Test func onlyTheUpdateCheckUsesTheNetwork() throws {
        #expect(try sourceFiles(matching: network, in: repoRoot) == ["Sources/WhoIsWorking/Updates.swift"])
    }

    @Test func onlyTwoFilesAskMacOSToOpenSomething() throws {
        #expect(try sourceFiles(matching: launch, in: repoRoot) == [])
        #expect(try sourceFiles(matching: workspaceOpen, in: repoRoot) == [
            "Sources/WhoIsWorking/AppFocuser.swift", "Sources/WhoIsWorking/Updates.swift",
        ])
    }

    @Test func thePackageHasNoDependenciesOrPlugins() throws {
        let manifest = try String(contentsOf: repoRoot.appendingPathComponent("Package.swift"), encoding: .utf8)
        for forbidden in [".package(", ".plugin(", "plugins:", ".binaryTarget(", ".systemLibrary("] {
            #expect(!manifest.contains(forbidden), "Package.swift has \(forbidden)")
        }
    }

    @Test func theHookScriptAndPluginNameNoHost() {
        for (name, text) in [("hook script", HookScript.contents), ("OpenCode plugin", OpenCodePlugin.contents)] {
            for forbidden in ["://", "http", "curl", "wget", "ssh ", "fetch(", "WebSocket", "child_process", "node:dgram", "node:tls"] {
                #expect(!text.contains(forbidden), "the \(name) has \(forbidden)")
            }
        }
        // The script's only way out is a Unix socket on this Mac.
        #expect(HookScript.contents.contains("/usr/bin/nc -U"))
        #expect(OpenCodePlugin.contents.contains(#"from "node:net""#))
    }

    /// The tripwires above only mean something if they trip.
    @Test func aNetworkCallOrALaunchInANewFileIsCaught() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("whoisworking-policy-\(UUID().uuidString)")
        let sources = root.appendingPathComponent("Sources/AgentCore")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("let session = URLSession.shared\n".utf8).write(to: sources.appendingPathComponent("Phone.swift"))
        try Data("let p = Process()\nsystem(\"ls\")\n".utf8).write(to: sources.appendingPathComponent("Shell.swift"))
        try Data("NSWorkspace.shared.open(url)\n".utf8).write(to: sources.appendingPathComponent("Opener.swift"))
        try Data("Text(\"x\").font(.system(size: 12)); let o = owningProcess(of: 1)\n".utf8)
            .write(to: sources.appendingPathComponent("Harmless.swift"))

        #expect(try sourceFiles(matching: network, in: root) == ["Sources/AgentCore/Phone.swift"])
        #expect(try sourceFiles(matching: launch, in: root) == ["Sources/AgentCore/Shell.swift"])
        #expect(try sourceFiles(matching: workspaceOpen, in: root) == ["Sources/AgentCore/Opener.swift"])
    }
}

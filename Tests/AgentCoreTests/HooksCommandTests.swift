import Foundation
import Testing
@testable import AgentCore

/// Everything runs in a temporary directory: a stand-in "default" settings file and hook script.
@Suite("Hooks command line")
struct HooksCommandTests {
    let dir: URL
    let defaultSettings: URL
    let defaultCodexHooks: URL
    let script: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("perch-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defaultSettings = dir.appendingPathComponent("default-settings.json")
        defaultCodexHooks = dir.appendingPathComponent("codex-hooks.json")
        script = dir.appendingPathComponent("Perch/perch-hook")
        try Data("{}\n".utf8).write(to: defaultSettings)
    }

    private func run(_ args: [String]) -> (Int32, String) {
        var out = ""
        let claude = defaultSettings, codex = defaultCodexHooks
        let code = HooksCommand.run(
            args, defaultSettings: { $0 == .codex ? codex : claude }, hookScript: script
        ) { out += $0 }
        return (code, out)
    }

    @Test func uninstallOnAnotherSettingsFileLeavesTheHookScriptAlone() throws {
        // The default settings use the script; a copy elsewhere is being cleaned up.
        #expect(run(["install"]).0 == 0)
        let copy = dir.appendingPathComponent("copy.json")
        try FileManager.default.copyItem(at: defaultSettings, to: copy)
        #expect(run(["uninstall", "--settings", copy.path]).0 == 0)
        #expect(FileManager.default.fileExists(atPath: script.path))
    }

    @Test func uninstallOnTheDefaultSettingsRemovesTheHookScript() {
        #expect(run(["install"]).0 == 0)
        #expect(FileManager.default.fileExists(atPath: script.path))
        #expect(run(["uninstall"]).0 == 0)
        #expect(!FileManager.default.fileExists(atPath: script.path))
    }

    @Test func installWritesTheExactScript() {
        #expect(run(["install"]).0 == 0)
        #expect(HookScript.isCurrent(at: script))
        #expect(run(["status"]).1.hasSuffix(": installed\n"))
    }

    @Test func previewChangesNothing() throws {
        let before = try Data(contentsOf: defaultSettings)
        let (code, out) = run(["preview"])
        #expect(code == 0)
        #expect(out.contains("perch-hook"))
        #expect(try Data(contentsOf: defaultSettings) == before)
        #expect(!FileManager.default.fileExists(atPath: script.path))
    }

    @Test func codexAgentWritesTheCodexHooksFile() throws {
        #expect(run(["install", "--agent", "codex"]).0 == 0)
        let codexText = try String(contentsOf: defaultCodexHooks, encoding: .utf8)
        #expect(codexText.contains(#"perch-hook\" codex"#))
        #expect(try String(contentsOf: defaultSettings, encoding: .utf8) == "{}\n")
        #expect(run(["status", "--agent", "codex"]).1.hasSuffix(": installed\n"))
    }

    @Test func theScriptStaysWhileAnotherAgentStillUsesIt() {
        #expect(run(["install"]).0 == 0)
        #expect(run(["install", "--agent", "codex"]).0 == 0)
        #expect(run(["uninstall", "--agent", "codex"]).0 == 0)
        #expect(FileManager.default.fileExists(atPath: script.path))
        #expect(run(["uninstall"]).0 == 0)
        #expect(!FileManager.default.fileExists(atPath: script.path))
    }

    @Test func unknownAgentIsRejected() {
        #expect(run(["status", "--agent", "cursor"]).0 == 2)
    }

    @Test func unknownSubcommandPrintsUsage() {
        let (code, out) = run(["frobnicate"])
        #expect(code == 2)
        #expect(out.hasPrefix("usage:"))
    }
}

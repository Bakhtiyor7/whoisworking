import Foundation
import Testing
@testable import AgentCore

/// Everything runs in a temporary directory: a stand-in "default" settings file and hook script.
@Suite("Hooks command line")
struct HooksCommandTests {
    let dir: URL
    let defaultSettings: URL
    let defaultCodexHooks: URL
    let defaultCursorHooks: URL
    let defaultAntigravityHooks: URL
    let script: URL
    var defaultPlugin: URL { dir.appendingPathComponent("opencode/plugins/whoisworking.js") }

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("whoisworking-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defaultSettings = dir.appendingPathComponent("default-settings.json")
        defaultCodexHooks = dir.appendingPathComponent("codex-hooks.json")
        defaultCursorHooks = dir.appendingPathComponent("cursor-hooks.json")
        defaultAntigravityHooks = dir.appendingPathComponent("antigravity-hooks.json")
        script = dir.appendingPathComponent("WhoIsWorking/whoisworking-hook")
        try Data("{}\n".utf8).write(to: defaultSettings)
    }

    private func run(_ args: [String]) -> (Int32, String) {
        var out = ""
        // Each agent gets its own stand-in default file.
        let files: [String: URL] = [
            "claude-code": defaultSettings, "codex": defaultCodexHooks,
            "cursor": defaultCursorHooks, "antigravity": defaultAntigravityHooks,
        ]
        let code = HooksCommand.run(
            args, defaultSettings: { files[$0.id]! }, hookScript: script, defaultPlugin: defaultPlugin
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
        #expect(out.contains("whoisworking-hook"))
        #expect(try Data(contentsOf: defaultSettings) == before)
        #expect(!FileManager.default.fileExists(atPath: script.path))
    }

    @Test func codexAgentWritesTheCodexHooksFile() throws {
        #expect(run(["install", "--agent", "codex"]).0 == 0)
        let codexText = try String(contentsOf: defaultCodexHooks, encoding: .utf8)
        #expect(codexText.contains(#"whoisworking-hook\" codex"#))
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

    @Test func cursorAndAntigravityAgentsWriteTheirOwnFiles() throws {
        #expect(run(["install", "--agent", "cursor"]).0 == 0)
        #expect(run(["install", "--agent", "antigravity"]).0 == 0)
        let cursorText = try String(contentsOf: defaultCursorHooks, encoding: .utf8)
        #expect(cursorText.contains(#"whoisworking-hook\" cursor"#))
        let antigravityText = try String(contentsOf: defaultAntigravityHooks, encoding: .utf8)
        #expect(antigravityText.contains(#"whoisworking-hook\" antigravity Stop"#))
        #expect(try String(contentsOf: defaultSettings, encoding: .utf8) == "{}\n")
        #expect(run(["status", "--agent", "cursor"]).1.hasSuffix(": installed\n"))
        #expect(run(["status", "--agent", "antigravity"]).1.hasSuffix(": installed\n"))
    }

    @Test func uninstallOnAnotherFileKeepsTheScriptEvenWhenNothingElseUsesIt() throws {
        // No default file uses the script, but a copy elsewhere is not the default: leave the script alone.
        #expect(run(["install"]).0 == 0)
        let copy = dir.appendingPathComponent("copy.json")
        try FileManager.default.copyItem(at: defaultSettings, to: copy)
        #expect(run(["uninstall"]).0 == 0)
        try HookScript.write(to: script)
        #expect(run(["uninstall", "--settings", copy.path]).0 == 0)
        #expect(FileManager.default.fileExists(atPath: script.path))
    }

    @Test func theScriptStaysWhenAHookFileCannotBeRead() throws {
        // Antigravity allows comments; WhoIsWorking cannot read such a file, so it may still use the script.
        #expect(run(["install"]).0 == 0)
        let commented = "{\n  // mine\n  \"whoisworking\": {}\n}\n"
        try Data(commented.utf8).write(to: defaultAntigravityHooks)
        #expect(run(["uninstall"]).0 == 0)
        #expect(FileManager.default.fileExists(atPath: script.path))
    }

    @Test func opencodeAgentWritesThePluginFile() throws {
        #expect(run(["status", "--agent", "opencode"]).1.hasSuffix(": notInstalled\n"))
        let (code, out) = run(["preview", "--agent", "opencode"])
        #expect(code == 0)
        #expect(out == OpenCodePlugin.contents)
        #expect(!FileManager.default.fileExists(atPath: defaultPlugin.path))
        #expect(run(["install", "--agent", "opencode"]).0 == 0)
        #expect(try String(contentsOf: defaultPlugin, encoding: .utf8) == OpenCodePlugin.contents)
        #expect(run(["status", "--agent", "opencode"]).1.hasSuffix(": installed\n"))
        // The plugin does not use the hook script.
        #expect(!FileManager.default.fileExists(atPath: script.path))
        #expect(run(["uninstall", "--agent", "opencode"]).0 == 0)
        #expect(!FileManager.default.fileExists(atPath: defaultPlugin.path))
    }

    @Test func unknownAgentIsRejected() {
        // This used `cursor` until Cursor became a known agent; any unknown name checks the same behaviour.
        #expect(run(["status", "--agent", "windsurf"]).0 == 2)
    }

    @Test func unknownSubcommandPrintsUsage() {
        let (code, out) = run(["frobnicate"])
        #expect(code == 2)
        #expect(out.hasPrefix("usage:"))
    }
}

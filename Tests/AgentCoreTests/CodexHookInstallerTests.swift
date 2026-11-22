import Foundation
import Testing
@testable import AgentCore

/// Shaped like a real ~/.codex/hooks.json with another tool's hooks on 9 events. Temporary copies only.
private let existingCodexHooks = #"""
{
  "hooks": {
    "PermissionRequest": [
      {
        "hooks": [
          {
            "type": "command",
            "command": ": other-tool-hook-form=1; other-tool codex permission"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": ": other-tool-hook-form=1; other-tool codex stop"
          }
        ]
      }
    ],
    "Interrupt": [
      {
        "hooks": [
          {
            "type": "command",
            "command": ": other-tool-hook-form=1; other-tool codex interrupt"
          }
        ]
      }
    ]
  }
}

"""#

@Suite("Codex hook installer")
struct CodexHookInstallerTests {
    let dir: URL
    let file: URL
    let command = PerchPaths.hookCommand(agent: "codex")

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("perch-codex-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        file = dir.appendingPathComponent("hooks.json")
        try Data(existingCodexHooks.utf8).write(to: file)
    }

    var installer: HookInstaller {
        HookInstaller(target: .codex, settingsURL: file, hookCommand: command, now: { Date(timeIntervalSince1970: 1_800_000_000) })
    }

    var text: String { (try? String(contentsOf: file, encoding: .utf8)) ?? "" }

    @Test func codexTargetCoversTheCodexEvents() {
        #expect(HookTarget.codex.events == [
            "SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse",
            "PermissionRequest", "Stop", "Interrupt", "SubagentStart", "SubagentStop",
        ])
        // Codex caps SessionEnd and Interrupt hooks at 3 seconds.
        #expect(HookTarget.codex.timeoutSeconds <= 3)
        #expect(HookTarget.codex.defaultSettingsPath == ".codex/hooks.json")
    }

    @Test func installAppendsAfterOtherToolsAndUninstallRestoresExactly() throws {
        let result = try installer.install()
        #expect(result.changed)
        let hooks = try #require(JSONValue.parse(text)["hooks"])
        #expect(Array(hooks.objectKeys.prefix(3)) == ["PermissionRequest", "Stop", "Interrupt"])
        for event in HookTarget.codex.events {
            let handlers = (hooks[event]?.arrayValue ?? []).flatMap { $0["hooks"]?.arrayValue ?? [] }
            #expect(handlers.last?["command"]?.stringValue == command, "\(event)")
            #expect(handlers.last?["timeout"] == .number("3"), "\(event)")
        }
        let stop = try #require(hooks["Stop"]?.arrayValue)
        #expect(stop.first?["hooks"]?.arrayValue?.first?["command"]?.stringValue == ": other-tool-hook-form=1; other-tool codex stop")
        #expect(try installer.status() == .installed)

        #expect(try !installer.install().changed)
        try installer.uninstall()
        #expect(text == existingCodexHooks)
    }

    @Test func refusesInvalidJSON() throws {
        try Data("{\"hooks\": ".utf8).write(to: file)
        #expect(throws: HookInstallerError.self) { try installer.install() }
        #expect(text == "{\"hooks\": ")
    }

    @Test func claudeAndCodexEntriesDoNotCountForEachOther() throws {
        // A Claude-only command in a Codex file is still "ours" by marker, but it is not the current Codex command.
        try installer.install()
        let claudeView = HookInstaller(target: .claudeCode, settingsURL: file, hookCommand: PerchPaths.hookCommand(agent: "claude-code"))
        #expect(try claudeView.status() == .partial)
    }

    /// Opt-in check against a real file without writing to it:
    /// `PERCH_ROUNDTRIP_FILE=~/.codex/hooks.json swift test --filter roundTripOfARealFile`
    @Test func codexHooksFileRoundTrips() throws {
        guard let path = ProcessInfo.processInfo.environment["PERCH_ROUNDTRIP_CODEX"] else { return }
        let text = try String(contentsOfFile: path, encoding: .utf8)
        #expect(try JSONValue.parse(text).formatted() + "\n" == text)
    }
}

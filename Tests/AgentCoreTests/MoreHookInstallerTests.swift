import Foundation
import Testing
@testable import AgentCore

// Installer formats for Cursor (INS-15) and Antigravity (INS-16). Temporary copies only.

private final class TempFile {
    let dir: URL
    let file: URL
    let clock = Date(timeIntervalSince1970: 1_800_000_000)

    init(_ contents: String?, name: String = "hooks.json") throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("whoisworking-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        file = dir.appendingPathComponent(name)
        if let contents { try Data(contents.utf8).write(to: file) }
    }

    deinit { try? FileManager.default.removeItem(at: dir) }

    func installer(_ target: HookTarget) -> HookInstaller {
        let fixed = clock
        return HookInstaller(
            target: target, settingsURL: file, hookCommand: AppPaths.hookCommand(agent: target.id), now: { fixed })
    }

    var text: String { (try? String(contentsOf: file, encoding: .utf8)) ?? "<missing>" }

    var backups: [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.contains(".whoisworking-backup-") }
    }
}

private func parse(_ text: String) throws -> JSONValue { try JSONValue.parse(text) }

// MARK: - Cursor

/// Shaped like a real ~/.cursor/hooks.json: another tool's entries, one without a timeout, `version` last.
private let existingCursorHooks = #"""
{
  "hooks": {
    "stop": [
      {
        "command": "/bin/sh -c 'other-tool cursor stop'",
        "timeout": 10
      }
    ],
    "sessionStart": [
      {
        "command": "bash '/Users/me/.cursor/other-state.sh' session"
      }
    ]
  },
  "version": 1
}

"""#

@Suite("Cursor hook installer")
struct CursorHookInstallerTests {
    private let command = AppPaths.hookCommand(agent: "cursor")

    @Test func installAppendsOneFlatEntryPerEventAfterOtherTools() throws {
        let temp = try TempFile(existingCursorHooks)
        #expect(try temp.installer(.cursor).install().changed)
        let root = try parse(temp.text)
        #expect(root.objectKeys == ["hooks", "version"])
        let hooks = try #require(root["hooks"])
        for event in HookTarget.cursor.events {
            let entries = try #require(hooks[event]?.arrayValue)
            #expect(entries.last == .object([
                JSONValue.Member("command", .string(command)),
                JSONValue.Member("timeout", .number("5")),
            ]))
        }
        // The other tool's entries come first and are unchanged.
        #expect(hooks["stop"]?.arrayValue?.first?["command"]?.stringValue == "/bin/sh -c 'other-tool cursor stop'")
        #expect(hooks["sessionStart"]?.arrayValue?.first == .object([
            JSONValue.Member("command", .string("bash '/Users/me/.cursor/other-state.sh' session")),
        ]))
        #expect(HookTarget.cursor.events == [
            "sessionStart", "sessionEnd", "postToolUse", "postToolUseFailure", "afterAgentThought", "stop",
        ])
        #expect(try temp.installer(.cursor).status() == .installed)
    }

    @Test func aNewFileStartsWithVersionOne() throws {
        let temp = try TempFile(nil)
        #expect(try temp.installer(.cursor).install().changed)
        let root = try parse(temp.text)
        #expect(root.objectKeys == ["version", "hooks"])
        #expect(root["version"] == .number("1"))
        #expect(try temp.installer(.cursor).uninstall().changed)
        #expect(try parse(temp.text) == .object([JSONValue.Member("version", .number("1"))]))
    }

    @Test func uninstallRestoresTheOriginalExactly() throws {
        let temp = try TempFile(existingCursorHooks)
        try temp.installer(.cursor).install()
        let second = try temp.installer(.cursor).install()
        #expect(!second.changed)
        #expect(temp.backups.count == 1)
        try temp.installer(.cursor).uninstall()
        #expect(temp.text == existingCursorHooks)
    }

    @Test func reinstallDoesNotReorderEvents() throws {
        // An empty event key before another tool's key: reinstall must leave the order alone.
        let original = #"{"version": 1, "hooks": {"stop": [], "afterFileEdit": [{"command": "other"}]}}"#
        let temp = try TempFile(original)
        try temp.installer(.cursor).install()
        let installed = temp.text
        #expect(try parse(installed)["hooks"]?.objectKeys.prefix(2) == ["stop", "afterFileEdit"])
        #expect(!(try temp.installer(.cursor).install().changed))
        #expect(temp.text == installed)
        #expect(temp.backups.count == 1)
    }

    @Test func refusesAFileWithHooksButNoVersion() throws {
        let original = #"{"hooks": {"stop": [{"command": "x"}]}}"#
        let temp = try TempFile(original)
        #expect(throws: HookInstallerError.self) { try temp.installer(.cursor).install() }
        #expect(temp.text == original)
        let nested = try TempFile(#"{"version": 1, "hooks": {"stop": [{"hooks": "x"}], "sessionEnd": {}}}"#)
        #expect(throws: HookInstallerError.self) { try nested.installer(.cursor).install() }
    }

    @Test func reportsAMissingEventAsPartial() throws {
        let temp = try TempFile(existingCursorHooks)
        try temp.installer(.cursor).install()
        var root = try parse(temp.text)
        guard case .object(var members) = root, let i = members.firstIndex(where: { $0.name == "hooks" }),
              case .object(var events) = members[i].value
        else { Issue.record("unexpected shape"); return }
        events.removeAll { $0.name == "afterAgentThought" }
        members[i].value = .object(events)
        root = .object(members)
        try Data(root.formatted().utf8).write(to: temp.file)
        #expect(try temp.installer(.cursor).status() == .partial)
    }
}

// MARK: - Antigravity

/// Another tool's named group, and the shapes Antigravity documents for plain and tool events.
private let existingAntigravityHooks = #"""
{
  "other-tool": {
    "Stop": [
      {
        "type": "command",
        "command": "./observe.sh"
      }
    ],
    "PostToolUse": [
      {
        "matcher": "run_command",
        "hooks": [
          {
            "type": "command",
            "command": "./after-tool.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}

"""#

@Suite("Antigravity hook installer")
struct AntigravityHookInstallerTests {
    private func handler(_ event: String) -> JSONValue {
        .object([
            JSONValue.Member("type", .string("command")),
            JSONValue.Member("command", .string(AppPaths.hookCommand(agent: "antigravity") + " " + event)),
            JSONValue.Member("timeout", .number("5")),
        ])
    }

    @Test func installAddsOneNamedGroupWithTheEventInEachCommand() throws {
        let temp = try TempFile(existingAntigravityHooks)
        #expect(try temp.installer(.antigravity).install().changed)
        let root = try parse(temp.text)
        #expect(root.objectKeys == ["other-tool", "whoisworking"])
        let group = try #require(root["whoisworking"])
        #expect(group.objectKeys == ["SessionStart", "PreInvocation", "PostToolUse", "Stop"])
        #expect(group["SessionStart"] == .array([handler("SessionStart")]))
        #expect(group["Stop"] == .array([handler("Stop")]))
        #expect(group["PostToolUse"] == .array([.object([
            JSONValue.Member("matcher", .string("")),
            JSONValue.Member("hooks", .array([handler("PostToolUse")])),
        ])]))
        #expect(try temp.installer(.antigravity).status() == .installed)
    }

    @Test func otherGroupsAreUntouchedAndUninstallRestoresExactly() throws {
        let temp = try TempFile(existingAntigravityHooks)
        try temp.installer(.antigravity).install()
        #expect(try parse(temp.text)["other-tool"] == parse(existingAntigravityHooks)["other-tool"])
        #expect(!(try temp.installer(.antigravity).install().changed))
        #expect(temp.backups.count == 1)
        try temp.installer(.antigravity).uninstall()
        #expect(temp.text == existingAntigravityHooks)
    }

    @Test func refusesAGroupWithEntriesItDidNotWrite() throws {
        let foreign = [
            // Someone else's command under our name.
            #"{"whoisworking": {"Stop": [{"type": "command", "command": "./mine.sh"}]}}"#,
            // Our script, registered for the wrong event.
            #"{"whoisworking": {"Stop": [{"type": "command", "command": "\"$HOME/Library/Application Support/WhoIsWorking/whoisworking-hook\" antigravity SessionStart"}]}}"#,
            // An event WhoIsWorking does not register.
            #"{"whoisworking": {"PreToolUse": []}}"#,
            // Not an object.
            #"{"whoisworking": true}"#,
            // Another tool wrapping our script: the command is not exactly ours.
            #"{"whoisworking": {"Stop": [{"type": "command", "command": "audit \"$HOME/Library/Application Support/WhoIsWorking/whoisworking-hook\" antigravity Stop"}]}}"#,
            // A matcher WhoIsWorking never writes.
            #"{"whoisworking": {"PostToolUse": [{"matcher": "run_command", "hooks": [{"type": "command", "command": "\"$HOME/Library/Application Support/WhoIsWorking/whoisworking-hook\" antigravity PostToolUse", "timeout": 5}]}]}}"#,
            // A duplicated key hides a second command.
            #"{"whoisworking": {"Stop": [{"type": "command", "command": "\"$HOME/Library/Application Support/WhoIsWorking/whoisworking-hook\" antigravity Stop", "command": "./mine.sh"}]}}"#,
        ]
        for original in foreign {
            let temp = try TempFile(original)
            #expect(throws: HookInstallerError.self) { try temp.installer(.antigravity).install() }
            #expect(throws: HookInstallerError.self) { try temp.installer(.antigravity).uninstall() }
            #expect(temp.text == original)
            #expect(temp.backups.isEmpty)
        }
    }

    @Test func keepsTheEnabledFlagAndReportsADisabledGroupAsPartial() throws {
        let temp = try TempFile(#"{"whoisworking": {"enabled": false}}"#)
        try temp.installer(.antigravity).install()
        let group = try #require(try parse(temp.text)["whoisworking"])
        #expect(group["enabled"] == .bool(false))
        #expect(group.objectKeys.first == "enabled")
        #expect(try temp.installer(.antigravity).status() == .partial)
    }

    @Test func installCreatesAMissingConfigFolder() throws {
        let temp = try TempFile(nil)
        let nested = temp.dir.appendingPathComponent("config/hooks.json")
        let installer = HookInstaller(
            target: .antigravity, settingsURL: nested, hookCommand: AppPaths.hookCommand(agent: "antigravity"))
        #expect(try installer.install().changed)
        #expect(try installer.status() == .installed)
    }

    @Test func refusesCommentsAndChangesNothing() throws {
        let original = "{\n  // my hooks\n  \"other-tool\": {},\n}\n"
        let temp = try TempFile(original)
        #expect(throws: HookInstallerError.self) { try temp.installer(.antigravity).install() }
        #expect(temp.text == original)
        #expect(temp.backups.isEmpty)
    }
}

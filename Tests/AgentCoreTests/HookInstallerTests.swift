import Foundation
import Testing
@testable import AgentCore

/// Every test works on a copy in a fresh temporary directory. Nothing here touches `~/.claude`.
private final class TempSettings {
    let dir: URL
    let file: URL
    var clock = Date(timeIntervalSince1970: 1_800_000_000)

    init(_ contents: String?) throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("whoisworking-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        file = dir.appendingPathComponent("settings.json")
        if let contents { try Data(contents.utf8).write(to: file) }
    }

    deinit { try? FileManager.default.removeItem(at: dir) }

    var installer: ClaudeHookInstaller {
        let fixed = clock
        return ClaudeHookInstaller(settingsURL: file, hookCommand: Self.command, now: { fixed })
    }

    var text: String { (try? String(contentsOf: file, encoding: .utf8)) ?? "<missing>" }

    var backups: [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("settings.json.whoisworking-backup-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static let command = #""$HOME/Library/Application Support/WhoIsWorking/whoisworking-hook" claude-code"#
}

/// Shaped like a real settings file: other tools' hooks with and without matchers, other keys, unicode.
private let existing = #"""
{
  "permissions": {
    "deny": [
      "Read(**/.env)"
    ]
  },
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/Users/me/.config/iterm2/cc-status"
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "startup|resume",
        "hooks": [
          {
            "type": "command",
            "command": "bash /Users/me/thermal-watch/session-hook.sh",
            "timeout": 15
          }
        ]
      }
    ],
    "TeammateIdle": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "other-tool idle"
          }
        ]
      }
    ]
  },
  "theme": "dark ✓"
}

"""#

@Suite("Claude hook installer")
struct HookInstallerTests {
    @Test func installAddsOneTaggedHandlerPerEvent() throws {
        let t = try TempSettings(existing)
        let result = try t.installer.install()
        #expect(result.changed)

        let root = try JSONValue.parse(t.text)
        let hooks = try #require(root["hooks"])
        for event in ClaudeHookInstaller.events {
            let commands = hooks[event]?.arrayValue?.flatMap { $0["hooks"]?.arrayValue ?? [] }
                .compactMap { $0["command"]?.stringValue } ?? []
            #expect(commands.filter { $0 == TempSettings.command }.count == 1, "\(event)")
        }
        #expect(try t.installer.status() == .installed)
    }

    @Test func installKeepsOtherToolsEntriesAndKeysInOrder() throws {
        let t = try TempSettings(existing)
        try t.installer.install()
        let root = try JSONValue.parse(t.text)
        #expect(root.objectKeys == ["permissions", "hooks", "theme"])
        #expect(root["theme"] == .string("dark ✓"))

        let hooks = try #require(root["hooks"])
        // Existing events keep their position; new ones are appended after them.
        #expect(Array(hooks.objectKeys.prefix(3)) == ["Stop", "SessionStart", "TeammateIdle"])
        // Other tools' groups are untouched and stay first.
        let original = try JSONValue.parse(existing)["hooks"]!
        for event in ["Stop", "SessionStart", "TeammateIdle"] {
            let before = original[event]!.arrayValue!
            let after = hooks[event]!.arrayValue!
            #expect(Array(after.prefix(before.count)) == before, "\(event)")
        }
        #expect(hooks["TeammateIdle"]!.arrayValue!.count == 1)
    }

    @Test func installWritesATimestampedBackupOfTheOriginalFirst() throws {
        let t = try TempSettings(existing)
        let result = try t.installer.install()
        #expect(t.backups.count == 1)
        // Compare resolved paths: the temp dir is reachable as both /var/… and /private/var/….
        #expect(result.backupURL?.resolvingSymlinksInPath().path == t.backups.first?.resolvingSymlinksInPath().path)
        #expect(t.backups.first?.lastPathComponent == "settings.json.whoisworking-backup-\(Self.stamp(t.clock))")
        #expect(try String(contentsOf: t.backups[0], encoding: .utf8) == existing)
    }

    @Test func installIsIdempotent() throws {
        let t = try TempSettings(existing)
        try t.installer.install()
        let once = t.text
        t.clock += 60
        let again = try t.installer.install()
        #expect(!again.changed)
        #expect(again.backupURL == nil)
        #expect(t.text == once)
        #expect(t.backups.count == 1)
    }

    @Test func uninstallRestoresThePriorContentExactly() throws {
        let t = try TempSettings(existing)
        try t.installer.install()
        t.clock += 60
        let result = try t.installer.uninstall()
        #expect(result.changed)
        #expect(t.text == existing)
        #expect(try t.installer.status() == .notInstalled)
        #expect(t.backups.count == 2)  // one before install, one before uninstall
    }

    @Test func uninstallRemovesOnlyTaggedHandlersEvenInsideSharedGroups() throws {
        let shared = #"""
        {
          "hooks": {
            "Stop": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "keep-me"
                  },
                  {
                    "type": "command",
                    "command": "\"$HOME/Library/Application Support/WhoIsWorking/whoisworking-hook\" claude-code"
                  }
                ]
              }
            ]
          }
        }

        """#
        let t = try TempSettings(shared)
        try t.installer.uninstall()
        let stop = try JSONValue.parse(t.text)["hooks"]?["Stop"]?.arrayValue
        #expect(stop?.count == 1)
        #expect(stop?.first?["hooks"]?.arrayValue?.compactMap { $0["command"]?.stringValue } == ["keep-me"])
    }

    @Test func uninstallWhenNotInstalledChangesNothing() throws {
        let t = try TempSettings(existing)
        let result = try t.installer.uninstall()
        #expect(!result.changed)
        #expect(t.text == existing)
        #expect(t.backups.isEmpty)
    }

    @Test func aLogicalNoOpWritesNothing() throws {
        // Compact JSON with no WhoIsWorking hooks: uninstall must not rewrite it in WhoIsWorking's formatting.
        let compact = #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"x"}]}]},"model":"opus"}"#
        let t = try TempSettings(compact)
        let preview = try t.installer.preview(.uninstall)
        #expect(!preview.changes)
        #expect(!(try t.installer.uninstall().changed))
        #expect(t.text == compact)
        #expect(t.backups.isEmpty)
        // Installed already, in compact form: reinstalling writes nothing either.
        try t.installer.install()
        let installed = t.installer
        let compactInstalled = withoutWhitespace(t.text)
        try Data(compactInstalled.utf8).write(to: t.file)
        #expect(!(try installed.install().changed))
        #expect(t.text == compactInstalled)
    }

    @Test func refusesToWriteWhenTheFileIsNotValidJSON() throws {
        let broken = "{ \"hooks\": { \"Stop\": [ } "
        let t = try TempSettings(broken)
        #expect(throws: HookInstallerError.self) { try t.installer.install() }
        #expect(throws: HookInstallerError.self) { try t.installer.uninstall() }
        #expect(t.text == broken)
        #expect(t.backups.isEmpty)
    }

    @Test func refusesUnexpectedShapes() throws {
        for weird in [#"[1]"#, #"{"hooks": []}"#, #"{"hooks": {"Stop": {}}}"#] {
            let t = try TempSettings(weird)
            #expect(throws: HookInstallerError.self, "\(weird)") { try t.installer.install() }
            #expect(t.text == weird)
        }
    }

    @Test func createsTheFileWhenMissingAndRemovesOurKeysOnUninstall() throws {
        let t = try TempSettings(nil)
        let result = try t.installer.install()
        #expect(result.changed)
        #expect(result.backupURL == nil)
        #expect(try t.installer.status() == .installed)
        try t.installer.uninstall()
        #expect(t.text == "{}\n")
    }

    @Test func reportsPartialInstalls() throws {
        let t = try TempSettings(#"""
        {
          "hooks": {
            "Stop": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "\"$HOME/Library/Application Support/WhoIsWorking/whoisworking-hook\" claude-code"
                  }
                ]
              }
            ]
          }
        }
        """#)
        #expect(try t.installer.status() == .partial)
        try t.installer.install()
        #expect(try t.installer.status() == .installed)
    }

    @Test func previewShowsTheChangeWithoutWriting() throws {
        let t = try TempSettings(existing)
        let preview = try t.installer.preview(.install)
        #expect(preview.before == existing)
        #expect(preview.after != existing)
        #expect(t.text == existing)
        #expect(t.backups.isEmpty)
    }

    @Test func keepsFilePermissions() throws {
        let t = try TempSettings(existing)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: t.file.path)
        try t.installer.install()
        let perms = try FileManager.default.attributesOfItem(atPath: t.file.path)[.posixPermissions] as? Int
        #expect(perms == 0o600)
    }

    @Test func writesThroughASymlinkInsteadOfReplacingIt() throws {
        let t = try TempSettings(nil)
        let real = t.dir.appendingPathComponent("real-settings.json")
        try Data(existing.utf8).write(to: real)
        try FileManager.default.createSymbolicLink(at: t.file, withDestinationURL: real)
        try t.installer.install()
        let type = try FileManager.default.attributesOfItem(atPath: t.file.path)[.type] as? FileAttributeType
        #expect(type == .typeSymbolicLink)
        #expect(try String(contentsOf: real, encoding: .utf8) != existing)
    }

    /// INS-18. A large backup takes long enough to write that a watcher sees the file while it
    /// is still being filled. Every mode the watcher sees must already be owner-only.
    @Test func aBackupIsNeverReadableByOthersWhileItIsWritten() throws {
        let t = try TempSettings("{}")
        let expected = t.file.path + ".whoisworking-backup-" + Self.stamp(t.clock)
        let watcher = ModeWatcher(path: expected)
        watcher.start()
        let url = try HookInstaller.writeBackup(of: Data(count: 96 * 1024 * 1024), beside: t.file, at: t.clock)
        let seen = watcher.stop()
        #expect(url.path == expected)
        #expect(seen == [0o600])
    }

    // INS-19. `beforeWrite` stands in for another tool that edits the file between
    // WhoIsWorking's read and its write.

    @Test func anEditMadeWhileInstallingIsKept() throws {
        let t = try TempSettings(existing)
        let file = t.file
        let theirs = #"{"model": "set by another tool"}"# + "\n"
        var installer = t.installer
        installer.beforeWrite = { try? Data(theirs.utf8).write(to: file) }
        #expect(throws: HookInstallerError.changedMeanwhile) { try installer.install() }
        #expect(t.text == theirs)
        #expect(t.backups.isEmpty)
        // The next try starts from the other tool's content and succeeds.
        try t.installer.install()
        #expect(t.text.contains("set by another tool"))
        #expect(try t.installer.status() == .installed)
    }

    @Test func aFileDeletedWhileInstallingStaysDeleted() throws {
        let t = try TempSettings(existing)
        let file = t.file
        var installer = t.installer
        installer.beforeWrite = { try? FileManager.default.removeItem(at: file) }
        #expect(throws: HookInstallerError.changedMeanwhile) { try installer.install() }
        #expect(t.text == "<missing>")
        #expect(t.backups.isEmpty)
    }

    @Test func aFileThatAppearsWhileInstallingIsKept() throws {
        let t = try TempSettings(nil)
        let file = t.file
        let theirs = #"{"model": "created by another tool"}"# + "\n"
        var installer = t.installer
        installer.beforeWrite = { try? Data(theirs.utf8).write(to: file) }
        #expect(throws: HookInstallerError.changedMeanwhile) { try installer.install() }
        #expect(t.text == theirs)
        #expect(t.backups.isEmpty)
    }

    static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: date)
    }
}

/// The same JSON without whitespace outside strings.
private func withoutWhitespace(_ text: String) -> String {
    var out = ""
    var inString = false, escaped = false
    for c in text {
        if inString {
            out.append(c)
            if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
        } else if c == "\"" {
            inString = true
            out.append(c)
        } else if !c.isWhitespace {
            out.append(c)
        }
    }
    return out
}

/// Polls a path's permission bits on another thread until stopped, and once more at the end.
private final class ModeWatcher: @unchecked Sendable {
    private let path: String
    private let lock = NSLock()
    private var modes: Set<Int> = []
    private var stopped = false
    private let finished = DispatchSemaphore(value: 0)

    init(path: String) { self.path = path }

    private func look() {
        var info = stat()
        guard stat(path, &info) == 0 else { return }
        lock.lock()
        modes.insert(Int(info.st_mode & 0o777))
        lock.unlock()
    }

    func start() {
        Thread.detachNewThread { [self] in
            while true {
                lock.lock()
                let done = stopped
                lock.unlock()
                if done { break }
                look()
            }
            look()
            finished.signal()
        }
    }

    func stop() -> Set<Int> {
        lock.lock()
        stopped = true
        lock.unlock()
        finished.wait()
        lock.lock()
        defer { lock.unlock() }
        return modes
    }
}

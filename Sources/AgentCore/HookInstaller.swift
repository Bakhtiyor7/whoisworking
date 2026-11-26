import Foundation

public enum HookInstallerError: Error, Equatable, CustomStringConvertible {
    case invalidJSON(String)
    case unexpectedShape(String)
    case io(String)
    /// Another tool changed the file between WhoIsWorking's read and its write (INS-19).
    case changedMeanwhile

    public var description: String {
        switch self {
        case .invalidJSON(let detail): "The settings file is not valid JSON (\(detail)). Nothing was changed."
        case .unexpectedShape(let detail): "The settings file has an unexpected shape: \(detail). Nothing was changed."
        case .io(let detail): "Could not read or write the settings file: \(detail)"
        case .changedMeanwhile: "The settings file changed while Who's Working was updating it. Nothing was changed. Try again."
        }
    }
}

public enum HookInstallStatus: Equatable, Sendable {
    case notInstalled
    /// Some events are missing or point at an old command.
    case partial
    case installed
}

/// Which agent's hook file an installer edits, and the shape of that file (`Format`).
public struct HookTarget: Equatable, Sendable {
    public enum Format: Equatable, Sendable {
        /// `{"hooks": {"<Event>": [{"matcher"?, "hooks": [handler]}]}}` (Claude Code, Codex).
        case groups
        /// `{"version": 1, "hooks": {"<event>": [{"command", "timeout"}]}}` (Cursor, INS-15).
        case flatList
        /// `{"<name>": {"<Event>": [handler] | [{"matcher", "hooks": [handler]}]}}`: one top-level
        /// group per tool, of which WhoIsWorking owns exactly one (Antigravity, INS-16).
        case namedGroup(String)
    }

    public var agent: AgentKind
    /// Name used in the hook command and on the command line (`claude-code`, `codex`, `cursor`, `antigravity`).
    public var id: String
    public var events: [String]
    public var timeoutSeconds: Int
    /// Relative to the home folder.
    public var defaultSettingsPath: String
    public var format: Format = .groups
    /// Events whose handlers sit in a `{"matcher", "hooks"}` group inside a named group.
    public var matcherEvents: [String] = []
    /// The event name goes to the hook script as a second argument, because the payload lacks it (ING-10).
    public var passesEventName = false

    public static let claudeCode = HookTarget(
        agent: .claudeCode, id: "claude-code",
        events: [
            "SessionStart", "SessionEnd", "UserPromptSubmit",
            "PreToolUse", "PostToolUse", "PostToolUseFailure",
            "PermissionRequest", "PermissionDenied", "Notification",
            "Stop", "StopFailure", "SubagentStart", "SubagentStop",
        ],
        timeoutSeconds: 5, defaultSettingsPath: ".claude/settings.json")

    /// https://learn.chatgpt.com/docs/hooks. Codex caps SessionEnd and Interrupt hooks at 3 s.
    public static let codex = HookTarget(
        agent: .codex, id: "codex",
        events: [
            "SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse",
            "PermissionRequest", "Stop", "Interrupt", "SubagentStart", "SubagentStop",
        ],
        timeoutSeconds: 3, defaultSettingsPath: ".codex/hooks.json")

    /// https://cursor.com/docs/hooks. Only events that never wait on a hook's answer: no permission
    /// hooks (`preToolUse`, `beforeShellExecution`, …) and no `beforeSubmitPrompt` gate (CUR-02).
    public static let cursor = HookTarget(
        agent: .cursor, id: "cursor",
        events: ["sessionStart", "sessionEnd", "postToolUse", "postToolUseFailure", "afterAgentThought", "stop"],
        timeoutSeconds: 5, defaultSettingsPath: ".cursor/hooks.json", format: .flatList)

    /// https://antigravity.google/docs/hooks. The payload has no event name, so each handler passes it.
    /// `PreToolUse` needs a decision in its output and is never registered (ANT-02).
    public static let antigravity = HookTarget(
        agent: .antigravity, id: "antigravity",
        events: ["SessionStart", "PreInvocation", "PostToolUse", "Stop"],
        timeoutSeconds: 5, defaultSettingsPath: ".gemini/config/hooks.json", format: .namedGroup("whoisworking"),
        matcherEvents: ["PostToolUse"], passesEventName: true)

    public static let all: [HookTarget] = [.claudeCode, .codex, .cursor, .antigravity]

    public static func named(_ id: String) -> HookTarget? { all.first { $0.id == id } }

    public var defaultSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(defaultSettingsPath)
    }
}

/// Earlier name, kept for the Claude Code call sites.
public typealias ClaudeHookInstaller = HookInstaller

/// Adds and removes WhoIsWorking's hook handlers in an agent's hook file.
///
/// - Merges into existing `hooks` without changing or reordering other tools' entries.
/// - Writes a timestamped backup beside the file before every change.
/// - Recognises its own handlers by the command (`…/WhoIsWorking/whoisworking-hook …`), so uninstall removes exactly those.
/// - Is idempotent, and refuses to write when the file is not valid JSON or has an unexpected shape.
public struct HookInstaller: Sendable {
    public enum Action: Sendable { case install, uninstall }

    public struct Result: Equatable, Sendable {
        public var changed: Bool
        public var backupURL: URL?
    }

    public struct Preview: Equatable, Sendable {
        /// Current file text ("" when the file does not exist).
        public var before: String
        /// Text the action would write.
        public var after: String
        public var changes: Bool { before != after }
    }

    /// Claude Code events (kept for existing callers).
    public static var events: [String] { HookTarget.claudeCode.events }

    /// Any handler whose command contains this is WhoIsWorking's.
    public static let marker = "/WhoIsWorking/whoisworking-hook"

    public let target: HookTarget
    public let settingsURL: URL
    public let hookCommand: String
    public let now: @Sendable () -> Date

    private var events: [String] { target.events }

    /// Runs between the read and the write. Tests use it to act as another tool that edits the file
    /// in that gap (INS-19); the app leaves it empty.
    var beforeWrite: @Sendable () -> Void = {}

    public init(target: HookTarget, settingsURL: URL, hookCommand: String, now: @escaping @Sendable () -> Date = Date.init) {
        self.target = target
        self.settingsURL = settingsURL
        self.hookCommand = hookCommand
        self.now = now
    }

    /// Claude Code installer.
    public init(settingsURL: URL, hookCommand: String, now: @escaping @Sendable () -> Date = Date.init) {
        self.init(target: .claudeCode, settingsURL: settingsURL, hookCommand: hookCommand, now: now)
    }

    // MARK: Public API

    public func status() throws -> HookInstallStatus {
        let (_, root) = try load()
        switch target.format {
        case .groups: return listStatus(root) { $0["hooks"]?.arrayValue ?? [] }
        case .flatList: return listStatus(root) { [$0] }
        case .namedGroup(let name):
            guard let group = root[name] else { return .notInstalled }
            guard group == ourNamedGroup(keeping: group) else { return .partial }
            return group["enabled"] == .bool(false) ? .partial : .installed
        }
    }

    public func preview(_ action: Action) throws -> Preview {
        let (text, root) = try load()
        let changed = try transform(root, action)
        // A logical no-op writes nothing, whatever the file's formatting (INS-17). This also leaves
        // a missing file missing when there is nothing to remove.
        if changed == root { return Preview(before: text, after: text) }
        let trailingNewline = text.isEmpty || text.hasSuffix("\n")
        return Preview(before: text, after: changed.formatted() + (trailingNewline ? "\n" : ""))
    }

    @discardableResult
    public func install() throws -> Result { try apply(.install) }

    @discardableResult
    public func uninstall() throws -> Result { try apply(.uninstall) }

    /// The command for one event: the base command, plus the event name for agents whose payload lacks it.
    public func command(for event: String) -> String {
        target.passesEventName ? "\(hookCommand) \(event)" : hookCommand
    }

    // MARK: Steps

    private func apply(_ action: Action) throws -> Result {
        let preview = try preview(action)
        guard preview.changes else { return Result(changed: false, backupURL: nil) }
        let target = settingsURL.resolvingSymlinksInPath()
        let fm = FileManager.default
        let exists = fm.fileExists(atPath: target.path)

        var backup: URL?
        var permissions: Int?
        if exists {
            permissions = (try? fm.attributesOfItem(atPath: target.path)[.posixPermissions]) as? Int
            backup = try writeBackup(of: Data(preview.before.utf8))
        }
        beforeWrite()
        // Another tool may have written the file since it was read. Look again right before the
        // write, and refuse instead of overwriting what it wrote (INS-19).
        let current = try? Data(contentsOf: target)
        let unchanged = current.map { $0 == Data(preview.before.utf8) } ?? preview.before.isEmpty
        guard unchanged else {
            if let backup { try? fm.removeItem(at: backup) }
            throw HookInstallerError.changedMeanwhile
        }
        do {
            // A first install may need the agent's config folder (for example ~/.gemini/config).
            if !exists {
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            }
            try Data(preview.after.utf8).write(to: target, options: .atomic)
            if let permissions { try fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: target.path) }
        } catch {
            throw HookInstallerError.io(error.localizedDescription)
        }
        return Result(changed: true, backupURL: backup)
    }

    private func load() throws -> (String, JSONValue) {
        let target = settingsURL.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: target.path) else { return ("", .object([])) }
        let data: Data
        do { data = try Data(contentsOf: target) } catch { throw HookInstallerError.io(error.localizedDescription) }
        guard let text = String(data: data, encoding: .utf8) else { throw HookInstallerError.invalidJSON("not UTF-8") }
        let root: JSONValue
        do { root = try JSONValue.parse(text) } catch { throw HookInstallerError.invalidJSON("\(error)") }
        guard root.isObject else { throw HookInstallerError.unexpectedShape("top level is not an object") }
        switch self.target.format {
        case .groups: try validateLists(root, entriesAreGroups: true)
        case .flatList:
            try validateLists(root, entriesAreGroups: false)
            if let version = root["version"], case .number = version {} else if root["version"] != nil {
                throw HookInstallerError.unexpectedShape("\"version\" is not a number")
            } else if root["hooks"] != nil {
                throw HookInstallerError.unexpectedShape("it has \"hooks\" but no \"version\"")
            }
        case .namedGroup(let name):
            if let group = root[name] { try validateNamedGroup(group, name: name) }
        }
        return (text, root)
    }

    /// `{"hooks": {"<event>": [entry]}}`, where an entry is a matcher group or (flat) a handler.
    private func validateLists(_ root: JSONValue, entriesAreGroups: Bool) throws {
        guard let hooks = root["hooks"] else { return }
        guard case .object(let events) = hooks else { throw HookInstallerError.unexpectedShape("\"hooks\" is not an object") }
        for event in events {
            guard case .array(let entries) = event.value else {
                throw HookInstallerError.unexpectedShape("hooks.\(event.name) is not an array")
            }
            for entry in entries {
                guard entry.isObject else { throw HookInstallerError.unexpectedShape("hooks.\(event.name) has a non-object entry") }
                if entriesAreGroups, let handlers = entry["hooks"], handlers.arrayValue == nil {
                    throw HookInstallerError.unexpectedShape("hooks.\(event.name)[].hooks is not an array")
                }
                if !entriesAreGroups, entry["hooks"] != nil {
                    throw HookInstallerError.unexpectedShape("hooks.\(event.name) has a nested \"hooks\" entry")
                }
            }
        }
    }

    /// WhoIsWorking's named group may hold only what WhoIsWorking writes; anything else is refused (INS-16).
    private func validateNamedGroup(_ group: JSONValue, name: String) throws {
        func refuse(_ why: String) -> HookInstallerError {
            .unexpectedShape("the \"\(name)\" hook group \(why), so WhoIsWorking did not write it")
        }
        guard case .object(let members) = group else { throw refuse("is not an object") }
        for member in members {
            if member.name == "enabled" {
                guard case .bool = member.value else { throw refuse("has a non-boolean \"enabled\"") }
                continue
            }
            guard events.contains(member.name), case .array(let entries) = member.value else {
                throw refuse("has \"\(member.name)\"")
            }
            for entry in entries {
                if target.matcherEvents.contains(member.name) {
                    guard case .object(let fields) = entry,
                          Set(fields.map(\.name)) == ["matcher", "hooks"], fields.count == 2,
                          entry["matcher"]?.stringValue == "",
                          let handlers = entry["hooks"]?.arrayValue,
                          handlers.allSatisfy({ isOurHandler($0, event: member.name) })
                    else { throw refuse("has an entry under \(member.name) it did not expect") }
                } else {
                    guard isOurHandler(entry, event: member.name) else {
                        throw refuse("has an entry under \(member.name) it did not expect")
                    }
                }
            }
        }
    }

    /// A handler exactly as WhoIsWorking writes it for `event`: each field once, `type` "command", our exact
    /// command with that event, and a numeric timeout. A wrapper around our script is someone else's.
    private func isOurHandler(_ handler: JSONValue, event: String) -> Bool {
        guard case .object(let fields) = handler else { return false }
        let names = fields.map(\.name)
        guard Set(names).count == names.count, Set(names).isSubset(of: ["type", "command", "timeout"]),
              handler["command"]?.stringValue == command(for: event)
        else { return false }
        if let type = handler["type"], type != .string("command") { return false }
        if let timeout = handler["timeout"], case .number = timeout {} else if handler["timeout"] != nil { return false }
        return true
    }

    private func transform(_ root: JSONValue, _ action: Action) throws -> JSONValue {
        switch target.format {
        case .groups: return transformLists(root, action, entriesAreGroups: true)
        case .flatList: return transformLists(root, action, entriesAreGroups: false)
        case .namedGroup(let name): return transformNamedGroup(root, action, name: name)
        }
    }

    private func transformLists(_ root: JSONValue, _ action: Action, entriesAreGroups: Bool) -> JSONValue {
        guard case .object(var members) = root else { return root }
        let hooksIndex = members.firstIndex { $0.name == "hooks" }
        var existingEvents: [JSONValue.Member] = []
        if let hooksIndex, case .object(let existing) = members[hooksIndex].value { existingEvents = existing }
        let hadHooks = hooksIndex != nil

        // 1. Remove every WhoIsWorking handler, dropping groups and events that only held WhoIsWorking's.
        var cleaned: [JSONValue.Member] = []
        for event in existingEvents {
            guard case .array(let entries) = event.value else { cleaned.append(event); continue }
            var kept: [JSONValue] = []
            var removedAny = false
            for entry in entries {
                if !entriesAreGroups {
                    if isOurs(entry) { removedAny = true } else { kept.append(entry) }
                    continue
                }
                guard case .object(var fields) = entry,
                      let i = fields.firstIndex(where: { $0.name == "hooks" }),
                      case .array(let handlers) = fields[i].value
                else { kept.append(entry); continue }
                let others = handlers.filter { !isOurs($0) }
                if others.count == handlers.count { kept.append(entry); continue }
                removedAny = true
                if others.isEmpty { continue }
                fields[i].value = .array(others)
                kept.append(.object(fields))
            }
            // Uninstall drops an event key it emptied. Install keeps it in place, so a reinstall puts
            // WhoIsWorking's entry back where it was instead of moving the key to the end.
            if removedAny, kept.isEmpty, action == .uninstall { continue }
            cleaned.append(JSONValue.Member(event.name, .array(kept)))
        }

        // 2. On install, append one WhoIsWorking entry to each of the target's events.
        if action == .install {
            for event in target.events {
                let entry = entriesAreGroups ? ourGroup(event) : ourFlatEntry(event)
                if let i = cleaned.firstIndex(where: { $0.name == event }), case .array(var entries) = cleaned[i].value {
                    entries.append(entry)
                    cleaned[i].value = .array(entries)
                } else {
                    cleaned.append(JSONValue.Member(event, .array([entry])))
                }
            }
        }

        if let hooksIndex {
            if cleaned.isEmpty, !existingEvents.isEmpty {
                members.remove(at: hooksIndex)
            } else {
                members[hooksIndex].value = .object(cleaned)
            }
        } else if !cleaned.isEmpty, !hadHooks {
            members.append(JSONValue.Member("hooks", .object(cleaned)))
        }
        // Cursor rejects a hooks file without a version; a file WhoIsWorking starts gets version 1 first.
        if target.format == .flatList, action == .install, !members.contains(where: { $0.name == "version" }) {
            members.insert(JSONValue.Member("version", .number("1")), at: 0)
        }
        return .object(members)
    }

    private func transformNamedGroup(_ root: JSONValue, _ action: Action, name: String) -> JSONValue {
        guard case .object(var members) = root else { return root }
        let index = members.firstIndex { $0.name == name }
        switch action {
        case .uninstall:
            if let index { members.remove(at: index) }
        case .install:
            let group = ourNamedGroup(keeping: index.map { members[$0].value })
            if let index { members[index].value = group } else { members.append(JSONValue.Member(name, group)) }
        }
        return .object(members)
    }

    private func handler(_ event: String) -> JSONValue {
        .object([
            JSONValue.Member("type", .string("command")),
            JSONValue.Member("command", .string(command(for: event))),
            JSONValue.Member("timeout", .number(String(target.timeoutSeconds))),
        ])
    }

    private func ourGroup(_ event: String) -> JSONValue {
        .object([JSONValue.Member("hooks", .array([handler(event)]))])
    }

    private func ourFlatEntry(_ event: String) -> JSONValue {
        .object([
            JSONValue.Member("command", .string(command(for: event))),
            JSONValue.Member("timeout", .number(String(target.timeoutSeconds))),
        ])
    }

    /// The named group as WhoIsWorking writes it, keeping an existing `enabled` flag first.
    private func ourNamedGroup(keeping existing: JSONValue?) -> JSONValue {
        var members: [JSONValue.Member] = []
        if let enabled = existing?["enabled"] { members.append(JSONValue.Member("enabled", enabled)) }
        for event in target.events {
            let value: JSONValue = target.matcherEvents.contains(event)
                ? .array([.object([
                    JSONValue.Member("matcher", .string("")),
                    JSONValue.Member("hooks", .array([handler(event)])),
                ])])
                : .array([handler(event)])
            members.append(JSONValue.Member(event, value))
        }
        return .object(members)
    }

    private func listStatus(_ root: JSONValue, handlers: (JSONValue) -> [JSONValue]) -> HookInstallStatus {
        guard let hooks = root["hooks"] else { return .notInstalled }
        func ours(_ event: String) -> [JSONValue] { (hooks[event]?.arrayValue ?? []).flatMap(handlers).filter(isOurs) }
        var current = 0
        var any = false
        for event in events {
            let mine = ours(event)
            if !mine.isEmpty { any = true }
            if mine.count == 1, mine[0]["command"]?.stringValue == command(for: event) { current += 1 }
        }
        // Handlers left on events we no longer use also count as "partial".
        let stray = hooks.objectKeys.filter { !events.contains($0) }.contains { !ours($0).isEmpty }
        if current == events.count, !stray { return .installed }
        return any || stray ? .partial : .notInstalled
    }

    private func isOurs(_ handler: JSONValue) -> Bool {
        guard let command = handler["command"]?.stringValue else { return false }
        return command.contains(Self.marker)
    }

    private func writeBackup(of data: Data) throws -> URL {
        try Self.writeBackup(of: data, beside: settingsURL, at: now())
    }

    /// Writes `<file>.whoisworking-backup-<yyyyMMdd-HHmmss>[-n]` (owner-only) and returns its URL.
    static func writeBackup(of data: Data, beside file: URL, at date: Date) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let base = file.path + ".whoisworking-backup-" + formatter.string(from: date)
        var path = base
        var n = 2
        // O_EXCL creates the file or fails, so an existing file is never overwritten, and the mode
        // is 0600 from the start: the backup is never readable by others, not even briefly (INS-18).
        var fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        while fd < 0, errno == EEXIST {
            path = "\(base)-\(n)"
            n += 1
            fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        }
        guard fd >= 0 else { throw HookInstallerError.io("backup failed: \(String(cString: strerror(errno)))") }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            try? FileManager.default.removeItem(atPath: path)
            throw HookInstallerError.io("backup failed: \(error.localizedDescription)")
        }
        return URL(fileURLWithPath: path)
    }
}

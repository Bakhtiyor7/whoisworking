import Foundation

public enum HookInstallerError: Error, Equatable, CustomStringConvertible {
    case invalidJSON(String)
    case unexpectedShape(String)
    case io(String)

    public var description: String {
        switch self {
        case .invalidJSON(let detail): "The settings file is not valid JSON (\(detail)). Nothing was changed."
        case .unexpectedShape(let detail): "The settings file has an unexpected shape: \(detail). Nothing was changed."
        case .io(let detail): "Could not read or write the settings file: \(detail)"
        }
    }
}

public enum HookInstallStatus: Equatable, Sendable {
    case notInstalled
    /// Some events are missing or point at an old command.
    case partial
    case installed
}

/// Adds and removes Perch's hook handlers in a Claude Code `settings.json`.
///
/// - Merges into existing `hooks` without changing or reordering other tools' entries.
/// - Writes a timestamped backup beside the file before every change.
/// - Recognises its own handlers by the command (`…/Perch/perch-hook …`), so uninstall removes exactly those.
/// - Is idempotent, and refuses to write when the file is not valid JSON or has an unexpected shape.
public struct ClaudeHookInstaller: Sendable {
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

    /// Claude Code hook events Perch listens to.
    public static let events = [
        "SessionStart", "SessionEnd", "UserPromptSubmit",
        "PreToolUse", "PostToolUse", "PostToolUseFailure",
        "PermissionRequest", "PermissionDenied", "Notification",
        "Stop", "StopFailure", "SubagentStart", "SubagentStop",
    ]

    /// Any handler whose command contains this is Perch's.
    public static let marker = "/Perch/perch-hook"
    public static let timeoutSeconds = 5

    public let settingsURL: URL
    public let hookCommand: String
    public let now: @Sendable () -> Date

    public init(settingsURL: URL, hookCommand: String, now: @escaping @Sendable () -> Date = Date.init) {
        self.settingsURL = settingsURL
        self.hookCommand = hookCommand
        self.now = now
    }

    // MARK: Public API

    public func status() throws -> HookInstallStatus {
        let (_, root) = try load()
        guard let hooks = root["hooks"] else { return .notInstalled }
        var current = 0
        var any = false
        for event in Self.events {
            let handlers = (hooks[event]?.arrayValue ?? []).flatMap { $0["hooks"]?.arrayValue ?? [] }
            let ours = handlers.filter(isOurs)
            if !ours.isEmpty { any = true }
            if ours.count == 1, ours[0]["command"]?.stringValue == hookCommand { current += 1 }
        }
        // Handlers left on events we no longer use also count as "partial".
        let stray = hooks.objectKeys.filter { !Self.events.contains($0) }.contains { event in
            (hooks[event]?.arrayValue ?? []).flatMap { $0["hooks"]?.arrayValue ?? [] }.contains(where: isOurs)
        }
        if current == Self.events.count, !stray { return .installed }
        return any || stray ? .partial : .notInstalled
    }

    public func preview(_ action: Action) throws -> Preview {
        let (text, root) = try load()
        let changed = try transform(root, action)
        let trailingNewline = text.isEmpty || text.hasSuffix("\n")
        var after = changed.formatted() + (trailingNewline ? "\n" : "")
        // Leave a missing file missing when there is nothing to remove.
        if text.isEmpty, action == .uninstall { after = "" }
        return Preview(before: text, after: after)
    }

    @discardableResult
    public func install() throws -> Result { try apply(.install) }

    @discardableResult
    public func uninstall() throws -> Result { try apply(.uninstall) }

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
        do {
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
        if let hooks = root["hooks"] {
            guard case .object(let events) = hooks else { throw HookInstallerError.unexpectedShape("\"hooks\" is not an object") }
            for event in events {
                guard case .array(let groups) = event.value else {
                    throw HookInstallerError.unexpectedShape("hooks.\(event.name) is not an array")
                }
                for group in groups {
                    guard group.isObject else { throw HookInstallerError.unexpectedShape("hooks.\(event.name) has a non-object entry") }
                    if let handlers = group["hooks"], handlers.arrayValue == nil {
                        throw HookInstallerError.unexpectedShape("hooks.\(event.name)[].hooks is not an array")
                    }
                }
            }
        }
        return (text, root)
    }

    private func transform(_ root: JSONValue, _ action: Action) throws -> JSONValue {
        guard case .object(var members) = root else { return root }
        let hooksIndex = members.firstIndex { $0.name == "hooks" }
        var events: [JSONValue.Member] = []
        if let hooksIndex, case .object(let existing) = members[hooksIndex].value { events = existing }
        let hadHooks = hooksIndex != nil

        // 1. Remove every Perch handler, dropping groups and events that only held Perch's.
        var cleaned: [JSONValue.Member] = []
        for event in events {
            guard case .array(let groups) = event.value else { cleaned.append(event); continue }
            var keptGroups: [JSONValue] = []
            var removedAny = false
            for group in groups {
                guard case .object(var fields) = group,
                      let i = fields.firstIndex(where: { $0.name == "hooks" }),
                      case .array(let handlers) = fields[i].value
                else { keptGroups.append(group); continue }
                let kept = handlers.filter { !isOurs($0) }
                if kept.count == handlers.count { keptGroups.append(group); continue }
                removedAny = true
                if kept.isEmpty { continue }
                fields[i].value = .array(kept)
                keptGroups.append(.object(fields))
            }
            if removedAny, keptGroups.isEmpty { continue }
            cleaned.append(JSONValue.Member(event.name, .array(keptGroups)))
        }

        // 2. On install, append one Perch group to each event.
        if action == .install {
            for event in Self.events {
                if let i = cleaned.firstIndex(where: { $0.name == event }), case .array(var groups) = cleaned[i].value {
                    groups.append(ourGroup)
                    cleaned[i].value = .array(groups)
                } else {
                    cleaned.append(JSONValue.Member(event, .array([ourGroup])))
                }
            }
        }

        if let hooksIndex {
            if cleaned.isEmpty, !events.isEmpty {
                members.remove(at: hooksIndex)
            } else {
                members[hooksIndex].value = .object(cleaned)
            }
        } else if !cleaned.isEmpty, !hadHooks {
            members.append(JSONValue.Member("hooks", .object(cleaned)))
        }
        return .object(members)
    }

    private var ourGroup: JSONValue {
        .object([
            JSONValue.Member("hooks", .array([
                .object([
                    JSONValue.Member("type", .string("command")),
                    JSONValue.Member("command", .string(hookCommand)),
                    JSONValue.Member("timeout", .number(String(Self.timeoutSeconds))),
                ]),
            ])),
        ])
    }

    private func isOurs(_ handler: JSONValue) -> Bool {
        guard let command = handler["command"]?.stringValue else { return false }
        return command.contains(Self.marker)
    }

    private func writeBackup(of data: Data) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let base = settingsURL.path + ".perch-backup-" + formatter.string(from: now())
        var path = base
        var n = 2
        while FileManager.default.fileExists(atPath: path) {
            path = "\(base)-\(n)"
            n += 1
        }
        let url = URL(fileURLWithPath: path)
        do {
            try data.write(to: url, options: .withoutOverwriting)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            throw HookInstallerError.io("backup failed: \(error.localizedDescription)")
        }
        return url
    }
}

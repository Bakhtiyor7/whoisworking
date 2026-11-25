import Foundation

/// What the notch offers a user whose agents are not connected yet: the setup hint beside the
/// notch (UI-16) and the setup card in the panel (UI-17). Pure; the app supplies what it read.
public struct SetupPrompt: Equatable, Sendable {
    public struct Row: Equatable, Sendable, Identifiable {
        public enum Action: Equatable, Sendable { case connect, repair }

        public var agent: AgentKind
        /// nil when the agent's file could not be read.
        public var status: HookInstallStatus?
        /// One line beside the name: the file that would change, or the state.
        public var detail: String
        public var action: Action?
        /// What is left for the user after an install made from the card.
        public var nextStep: String?

        /// "Skip" is offered on every row that is not installed.
        public var canSkip: Bool { status != .installed }

        public var id: AgentKind { agent }
    }

    /// The hint beside the notch: on while no agent is connected and the card still has one to offer.
    public var showsWings = false
    /// Empty when there is no card.
    public var rows: [Row] = []
    public var showsCard: Bool { !rows.isEmpty }
    /// Skipped agents that would otherwise be in the card, in the fixed order, so each can be undone.
    public var skipped: [AgentKind] = []
    /// The card's close button: "Done" once every row is installed. Either way it hides setup for a week.
    public var closeTitle = "Later"
    /// What the close button will do, for VoiceOver.
    public var closeHint = "Hides setup for a week"

    /// - Parameters:
    ///   - dismissal: when the user last put setup off; `now` decides whether it is still hidden.
    ///   - found: agents whose configuration folder exists on this Mac (`agentsFound`).
    ///   - statuses: install status per agent; an agent with no entry could not be read.
    ///   - installedNow: agents installed from the card since the app started.
    ///   - skipped: agents the user said never to offer.
    public init(
        ownsSocket: Bool, dismissal: SetupDismissal, now: Date, found: Set<AgentKind>,
        statuses: [AgentKind: HookInstallStatus], installedNow: Set<AgentKind> = [], skipped: Set<AgentKind> = []
    ) {
        // A second copy cannot receive events, so it offers nothing and saves nothing (UI-15).
        guard ownsSocket, !dismissal.isHidden(at: now) else { return }
        func connected(_ agent: AgentKind) -> Bool { statuses[agent] == .installed || statuses[agent] == .partial }
        // A skip holds until it is undone, or the hooks get installed anyway (from Settings).
        func isSkipped(_ agent: AgentKind) -> Bool {
            skipped.contains(agent) && statuses[agent] != .installed && !installedNow.contains(agent)
        }

        var candidates = AgentKind.allCases.filter { found.contains($0) || connected($0) || installedNow.contains($0) }
        if candidates.isEmpty { candidates = [.claudeCode, .codex] }
        let listed = candidates.filter { !isSkipped($0) }
        let offers = listed.contains { statuses[$0] != .installed }
        // Skipping every agent is a clear no, also when none is connected.
        showsWings = offers && !AgentKind.allCases.contains(where: connected)
        // Nothing to say when every listed agent was already installed before this launch.
        guard offers || !installedNow.isEmpty else { return }

        self.skipped = candidates.filter(isSkipped)
        rows = listed.map { agent in
            switch statuses[agent] {
            case .installed:
                Row(agent: agent, status: .installed, detail: agent == .openCode ? "Plugin installed" : "Hooks installed",
                    action: nil, nextStep: installedNow.contains(agent) ? Self.nextStep(for: agent) : nil)
            case .partial:
                Row(agent: agent, status: .partial, detail: "Partly installed", action: .repair, nextStep: nil)
            case .notInstalled:
                Row(agent: agent, status: .notInstalled, detail: Self.displayPath(for: agent), action: .connect, nextStep: nil)
            case nil:
                Row(agent: agent, status: nil, detail: "Could not read its file. See Settings.", action: nil, nextStep: nil)
            }
        }
        closeTitle = rows.allSatisfy { $0.status == .installed } ? "Done" : "Later"
    }

    /// File status cannot show that events arrive, so each agent gets the step that makes them arrive.
    static func nextStep(for agent: AgentKind) -> String? {
        switch agent {
        case .claudeCode, .antigravity: "Restart sessions that were already running."
        case .codex: "Next: trust the hooks in Codex. Use Review hooks in the app, or /hooks in the CLI."
        case .openCode: "Restart OpenCode to load the plugin."
        case .cursor: nil  // Cursor reloads its hooks file on save.
        }
    }

    /// The agent's hook file or plugin file, as shown to the user.
    public static func displayPath(for agent: AgentKind) -> String {
        if let target = HookTarget.all.first(where: { $0.agent == agent }) { return "~/" + target.defaultSettingsPath }
        return "~/.config/opencode/plugins/whoisworking.js"
    }

    /// The folder whose presence suggests the agent is used on this Mac, relative to the home folder.
    static func configFolder(for agent: AgentKind) -> String {
        switch agent {
        case .claudeCode: ".claude"
        case .codex: ".codex"
        case .cursor: ".cursor"
        case .openCode: ".config/opencode"
        case .antigravity: ".gemini"
        }
    }

    /// The text of the confirmation that opens inside a row before anything is written.
    public static func confirmation(for agent: AgentKind, fileExists: Bool) -> String {
        let path = displayPath(for: agent)
        guard let target = HookTarget.all.first(where: { $0.agent == agent }) else {
            // The plugin installer refuses a file it did not write, and backs up its own file only when edited.
            return fileExists
                ? "Replaces Who's Working's own plugin file, \(path). A copy you edited is backed up first. Other plugins stay as they are."
                : "Writes Who's Working's own plugin file, \(path). Other plugins stay as they are."
        }
        // A backup is made only when a file is there and is changed: a repair can find nothing to change.
        return fileExists
            ? "Adds a hook to \(target.events.count) events in \(path). The file is backed up before it is changed, and other tools' hooks stay as they are."
            : "Creates \(path) with a hook for \(target.events.count) events."
    }

    /// An install counts as made from the card only when it changed the file and left the hooks
    /// fully installed. No error is not enough: Antigravity keeps hooks the user turned off, so a
    /// repair there can succeed, change nothing and stay partly installed.
    public static func countsAsInstalledNow(changed: Bool, status: HookInstallStatus?) -> Bool {
        changed && status == .installed
    }

    /// Shown in the row when an install succeeded and the hooks are still not all on.
    public static func stillPartialNote(for agent: AgentKind) -> String {
        "Still partly installed. If the Who's Working hooks are turned off in \(agent.displayName), turn them on there."
    }

    /// Agents whose configuration folder exists under `home`. Only a suggestion of what to offer.
    public static func agentsFound(home: URL, exists: (URL) -> Bool = isFolder) -> Set<AgentKind> {
        Set(AgentKind.allCases.filter { exists(home.appendingPathComponent(configFolder(for: $0), isDirectory: true)) })
    }

    /// True for a directory; a regular file with a folder's name does not count.
    public static func isFolder(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

/// When the user last put setup off with "Later" (UI-16). It hides setup for a week, every time;
/// the permanent no is Skip, per agent.
public struct SetupDismissal: Equatable, Sendable {
    public static let snooze: TimeInterval = 7 * 24 * 3600

    public var lastAt: Date?

    public init(lastAt: Date? = nil) {
        self.lastAt = lastAt
    }

    public func isHidden(at now: Date) -> Bool {
        guard let lastAt else { return false }
        return now < lastAt.addingTimeInterval(Self.snooze)
    }

    public func closed(at now: Date) -> SetupDismissal {
        SetupDismissal(lastAt: now)
    }
}

/// What the collapsed notch draws, and so where the pointer opens the panel.
public enum CollapsedNotch: Equatable, Sendable {
    case hidden
    case needsYou(count: Int, longestWait: TimeInterval)
    case setup

    /// A session that needs the user takes the wings from the setup hint.
    public init(summary: NotchSummary, setup: SetupPrompt) {
        if summary.showsWings {
            self = .needsYou(count: summary.needsYouCount, longestWait: summary.longestWait ?? 0)
        } else {
            self = setup.showsWings ? .setup : .hidden
        }
    }

    public var showsWings: Bool { self != .hidden }
}

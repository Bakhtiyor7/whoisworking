import Foundation

/// Which coding agent a session belongs to. Only Claude Code in v1.
public enum AgentKind: String, Sendable, Codable, Equatable {
    case claudeCode
    case codex

    public var shortCode: String {
        switch self {
        case .claudeCode: "CC"
        case .codex: "CX"
        }
    }

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        }
    }
}

/// The six states a session can be in.
public enum SessionState: String, Sendable, CaseIterable, Equatable {
    case working
    case needsApproval
    case waitingForReply
    case doneUnseen
    case idle
    case error

    /// True for the states that make the wings appear.
    public var needsUser: Bool {
        switch self {
        case .needsApproval, .waitingForReply, .error: true
        default: false
        }
    }
}

/// One tool call, reduced to what the UI shows.
public struct ToolActivity: Equatable, Sendable {
    /// Tool name as the agent reports it, e.g. `Bash`, `Edit`, `mcp__github__create_issue`.
    public var name: String
    /// One short line for rows, e.g. "Running tests" or "Editing Header.tsx".
    public var summary: String
    /// The full command, file path or input, shown in the Needs you card.
    public var detail: String?

    public init(name: String, summary: String, detail: String? = nil) {
        self.name = name
        self.summary = summary
        self.detail = detail
    }
}

public struct Session: Equatable, Sendable, Identifiable {
    public let id: String
    public var agent: AgentKind
    public var state: SessionState
    /// When the session entered its current state. Drives elapsed and wait times.
    public var stateSince: Date
    /// The newest event applied. Older events are ignored for state changes.
    public var lastEventAt: Date
    public var cwd: String?
    /// Human title from the agent's session file, when it has one.
    public var name: String?
    public var pid: Int32?
    /// How the session was started, e.g. `claude-desktop` or `cli`.
    public var entrypoint: String?
    /// What it is doing now, one line.
    public var activity: String?
    /// The tool call waiting for approval.
    public var pendingTool: ToolActivity?
    /// Last notification text, assistant message or error text.
    public var message: String?
    /// False until a hook event arrives; until then the session file's status drives the state.
    public var hasHookEvents: Bool
    /// The agent's current turn id, when its hooks report one (Codex).
    public var turnId: String? = nil
    /// The agent's transcript file, when its hooks report one.
    public var transcriptPath: String? = nil

    public init(
        id: String,
        agent: AgentKind = .claudeCode,
        state: SessionState,
        stateSince: Date,
        lastEventAt: Date? = nil,
        cwd: String? = nil,
        name: String? = nil,
        pid: Int32? = nil,
        entrypoint: String? = nil,
        activity: String? = nil,
        pendingTool: ToolActivity? = nil,
        message: String? = nil,
        hasHookEvents: Bool = false
    ) {
        self.id = id
        self.agent = agent
        self.state = state
        self.stateSince = stateSince
        self.lastEventAt = lastEventAt ?? stateSince
        self.cwd = cwd
        self.name = name
        self.pid = pid
        self.entrypoint = entrypoint
        self.activity = activity
        self.pendingTool = pendingTool
        self.message = message
        self.hasHookEvents = hasHookEvents
    }

    /// Session name when present, else the last path component of `cwd`.
    public var displayName: String {
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty { return name }
        if let cwd, !cwd.isEmpty {
            let last = (cwd as NSString).lastPathComponent
            if !last.isEmpty, last != "/" { return last }
        }
        return "Session"
    }
}

/// Everything the app knows about sessions.
public struct SessionsState: Equatable, Sendable {
    public var sessions: [String: Session]
    /// Ids of sessions that ended. Late events for them are dropped instead of recreating the session.
    public var ended: Set<String>

    public init(sessions: [String: Session] = [:], ended: Set<String> = []) {
        self.sessions = sessions
        self.ended = ended
    }
}

/// A hook event from an agent, already mapped to common terms by an adapter.
public struct AgentEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case sessionStarted
        case sessionEnded
        case promptSubmitted
        /// About to run a tool. `subagent` is true when a subagent runs it.
        case toolStarted(ToolActivity, subagent: Bool)
        /// A tool finished (success or failure).
        case toolFinished(ToolActivity, subagent: Bool)
        case permissionRequested(ToolActivity)
        /// Auto mode denied a tool; the agent carries on.
        case permissionDenied
        /// The agent's own "needs your permission" notification.
        case permissionNotice(message: String?)
        /// The agent asked the user something (a question dialog) and waits for the answer.
        case waitingForReply(message: String?)
        /// The agent has been idle at its prompt for a while (Claude Code's `idle_prompt`, 60 s after Stop).
        case turnIdle(message: String?)
        /// The user answered a question dialog; the agent continues.
        case resumed
        /// The user interrupted the turn (Codex `Interrupt`).
        case interrupted
        case stopped(lastMessage: String?)
        case failed(error: String)
        /// A subagent started or stopped. Never creates a top-level session.
        case subagent(started: Bool, type: String?)
    }

    public var sessionId: String
    public var date: Date
    public var agent: AgentKind
    public var cwd: String?
    /// The agent process that ran the hook, when known (resolved from the hook's parent chain).
    public var pid: Int32?
    /// Turn id and transcript path, when the agent's hook payload has them.
    public var turnId: String? = nil
    public var transcriptPath: String? = nil
    public var kind: Kind

    public init(
        sessionId: String, date: Date, agent: AgentKind = .claudeCode, cwd: String? = nil, pid: Int32? = nil, kind: Kind
    ) {
        self.sessionId = sessionId
        self.date = date
        self.agent = agent
        self.cwd = cwd
        self.pid = pid
        self.kind = kind
    }
}

/// A session found on disk (e.g. `~/.claude/sessions/<pid>.json`).
public struct DiscoveredSession: Equatable, Sendable {
    public var sessionId: String
    public var agent: AgentKind
    public var pid: Int32
    public var cwd: String?
    public var name: String?
    /// The agent's own coarse status, e.g. `busy` or `idle`.
    public var status: String?
    public var entrypoint: String?
    public var startedAt: Date?
    public var statusUpdatedAt: Date?

    public init(
        sessionId: String, agent: AgentKind = .claudeCode, pid: Int32, cwd: String? = nil, name: String? = nil,
        status: String? = nil, entrypoint: String? = nil, startedAt: Date? = nil, statusUpdatedAt: Date? = nil
    ) {
        self.sessionId = sessionId
        self.agent = agent
        self.pid = pid
        self.cwd = cwd
        self.name = name
        self.status = status
        self.entrypoint = entrypoint
        self.startedAt = startedAt
        self.statusUpdatedAt = statusUpdatedAt
    }
}

/// A running agent process found without a session id (e.g. a Codex CLI started before Perch).
public struct DiscoveredProcess: Equatable, Sendable {
    public var agent: AgentKind
    public var pid: Int32
    public var cwd: String?
    public var startedAt: Date?

    public init(agent: AgentKind, pid: Int32, cwd: String?, startedAt: Date?) {
        self.agent = agent
        self.pid = pid
        self.cwd = cwd
        self.startedAt = startedAt
    }

    public static func placeholderId(pid: Int32) -> String { "process:\(pid)" }
}

/// Everything that can change the session list.
public enum StoreEvent: Equatable, Sendable {
    case agent(AgentEvent)
    case discovered(DiscoveredSession, at: Date)
    /// A running agent process with no session yet: shown as an idle placeholder until its first hook event.
    case discoveredProcess(DiscoveredProcess, at: Date)
    case processExited(pid: Int32)
    /// The user saw these sessions in the expanded panel.
    case viewed(ids: [String], at: Date)
    /// Drops sessions with no known process that have been silent for `Reducer.orphanTimeout`.
    case pruneOrphans(now: Date)
}

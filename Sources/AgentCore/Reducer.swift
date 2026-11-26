import Foundation

public enum Reducer {
    /// A session with no pid and no events for this long is assumed gone (its SessionEnd was missed).
    public static let orphanTimeout: TimeInterval = 15 * 60
    /// The same, for a session waiting for the user: agents send nothing while they wait (SES-08).
    public static let waitingOrphanTimeout: TimeInterval = 4 * 60 * 60

    /// How long a session with no pid may stay silent before it is assumed gone.
    public static func silenceLimit(for state: SessionState) -> TimeInterval {
        state == .needsApproval || state == .waitingForReply ? waitingOrphanTimeout : orphanTimeout
    }
    /// A session file's "idle" must be this much newer than the hook-derived state to override it.
    public static let fileStatusMargin: TimeInterval = 0.5
    /// How many ended session ids are remembered (RED-21).
    public static let maxEndedSessions = 1000
    /// An event with a longer session id is dropped (RED-22). Agents' ids are 36 characters.
    public static let maxSessionIdLength = 256
}

/// Pure state transition: (sessions, event) -> sessions.
///
/// Rules that keep it safe against real-world event streams:
/// - Events older than a session's newest applied event do not change its state (out-of-order delivery).
/// - Ended sessions are remembered so late events cannot recreate them; `sessionStarted` (resume) clears that.
/// - Subagent events never create top-level sessions.
/// - Events for unknown sessions create them, so sessions already running when the app launched still show.
public func reduce(_ state: SessionsState, _ event: StoreEvent) -> SessionsState {
    var next = state
    switch event {
    case .agent(let e):
        guard e.sessionId.count <= Reducer.maxSessionIdLength else { break }
        applyAgent(e, to: &next)
    case .discovered(let found, let date):
        guard found.sessionId.count <= Reducer.maxSessionIdLength else { break }
        applyDiscovered(found, at: date, to: &next)
    case .discoveredProcess(let proc, let date):
        // Only while no session is known for that process, and no live session of that agent shares its
        // folder (a CLI and the daemon running its conversation have different pids).
        guard !next.sessions.values.contains(where: { $0.pid == proc.pid }),
              !next.sessions.values.contains(where: {
                  !$0.isPlaceholder && $0.agent == proc.agent && proc.cwd != nil && $0.cwd == proc.cwd
              })
        else { break }
        let id = DiscoveredProcess.placeholderId(pid: proc.pid)
        next.sessions[id] = Session(
            id: id, agent: proc.agent, state: .idle, stateSince: proc.startedAt ?? date, lastEventAt: date,
            cwd: proc.cwd, pid: proc.pid, activity: nil)
    case .processExited(let pid):
        for (id, session) in next.sessions where session.pid == pid {
            next.sessions[id] = nil
            next.ended.insert(id)
        }
    case .pruneOrphans(let now):
        for (id, session) in next.sessions
        where session.pid == nil && now.timeIntervalSince(session.lastEventAt) > Reducer.silenceLimit(for: session.state) {
            next.sessions[id] = nil
        }
    case .viewed(let ids, _):
        for id in ids {
            guard var session = next.sessions[id], session.state == .doneUnseen else { continue }
            session.state = .idle
            next.sessions[id] = session
        }
    }
    return next
}

// MARK: - Agent events

private func applyAgent(_ e: AgentEvent, to state: inout SessionsState) {
    let id = e.sessionId

    switch e.kind {
    case .sessionEnded:
        state.sessions[id] = nil
        state.ended.insert(id)
        return
    case .sessionStarted:
        state.ended.remove(id)
    default:
        if state.ended.contains(id) { return }
    }

    var session: Session
    if let existing = state.sessions[id] {
        session = existing
        if e.date < session.lastEventAt { return }
    } else {
        guard createsSession(e.kind) else { return }
        session = Session(id: id, agent: e.agent, state: .idle, stateSince: e.date)
    }

    // Events that would change nothing leave the session as it is, clock included (RED-20).
    if isIgnored(e, by: session) { return }
    if case .renamed = e.kind {
        if let name = e.name, !name.trimmingCharacters(in: .whitespaces).isEmpty { session.name = name }
        state.sessions[id] = session
        return
    }

    session.hasHookEvents = true
    session.lastEventAt = e.date
    if let cwd = e.cwd, !cwd.isEmpty { session.cwd = cwd }
    if let name = e.name, !name.trimmingCharacters(in: .whitespaces).isEmpty { session.name = name }
    if let turnId = e.turnId { session.turnId = turnId }
    if let path = e.transcriptPath, !path.isEmpty { session.transcriptPath = path }
    if let pid = e.pid {
        session.pid = pid
        // The process now has a real session: drop its placeholder.
        let placeholder = DiscoveredProcess.placeholderId(pid: pid)
        if placeholder != id { state.sessions[placeholder] = nil }
    }
    // A live session replaces placeholders of the same agent in the same folder.
    if let cwd = session.cwd {
        for (otherId, other) in state.sessions
        where otherId != id && other.isPlaceholder && other.agent == session.agent && other.cwd == cwd {
            state.sessions[otherId] = nil
        }
    }

    func enter(_ newState: SessionState) {
        if session.state != newState {
            session.state = newState
            session.stateSince = e.date
        }
        if newState != .needsApproval {
            session.pendingTool = nil
            session.openRequests = []
        }
    }

    switch e.kind {
    case .sessionStarted, .sessionEnded:
        break

    case .interrupted:
        // The user stopped the turn themselves, so they have seen it.
        enter(.idle)
        session.activity = nil
        if let turn = e.turnId { session.endedTurnId = turn }

    case .promptSubmitted, .resumed:
        enter(.working)
        session.activity = nil
        session.message = nil

    case .toolStarted(let tool, let subagent):
        if subagent {
            if session.state == .working { session.activity = tool.summary }
        } else if session.state != .needsApproval {
            enter(.working)
            session.activity = tool.summary
        }

    case .toolFinished(let tool, let subagent):
        if subagent { break }
        if session.state == .needsApproval {
            // Only the tool that was waiting for approval resolves it; a parallel tool finishing does not.
            if let pending = session.pendingTool, pending.name != tool.name || pending.detail != tool.detail { break }
            enter(.working)
        } else if session.state != .working, state.sessions[id] == nil {
            enter(.working)
        }

    case .permissionRequested(let tool):
        enter(.needsApproval)
        session.pendingTool = tool
        session.activity = tool.summary
        if let requestId = tool.requestId {
            // The same request asked twice is still one request.
            if let i = session.openRequests.firstIndex(where: { $0.requestId == requestId }) {
                session.openRequests[i] = tool
            } else {
                session.openRequests.append(tool)
            }
        }

    case .permissionReplied(let requestId):
        // isIgnored let only a reply to a request that is still open through.
        guard let i = session.openRequests.firstIndex(where: { $0.requestId == requestId }) else { break }
        session.openRequests.remove(at: i)
        if let newest = session.openRequests.last {
            session.pendingTool = newest
        } else {
            enter(.working)
        }

    case .activity(let tool):
        let line = tool?.summary
        switch session.state {
        case .working, .needsApproval:
            if let line { session.activity = line }
        case .doneUnseen, .idle, .error, .waitingForReply:
            // isIgnored already dropped activity from the turn that ended; this is a new or unknown turn.
            enter(.working)
            session.activity = line
            session.message = nil
        }

    case .renamed:
        break

    case .permissionDenied:
        enter(.working)

    case .permissionNotice(let message):
        enter(.needsApproval)
        if let message { session.message = message }

    case .turnIdle:
        // A finished session stays in Done. Only a working session moves: its Stop was missed.
        if session.state == .working {
            enter(.doneUnseen)
            session.activity = nil
        }

    case .waitingForReply(let message):
        // Open approvals outrank a question: both need the user, and the approvals must not be lost (RED-17).
        if session.state == .needsApproval, !session.openRequests.isEmpty { break }
        enter(.waitingForReply)
        if let message { session.message = message }

    case .stopped(let lastMessage):
        enter(.doneUnseen)
        session.activity = nil
        session.message = lastMessage
        if let turn = e.turnId { session.endedTurnId = turn }

    case .failed(let error):
        enter(.error)
        session.activity = nil
        session.message = error
        if let turn = e.turnId { session.endedTurnId = turn }

    case .subagent(let started, let type):
        if started, session.state == .working {
            session.activity = type.map { "Running \($0) subagent" } ?? "Running a subagent"
        }
    }

    state.sessions[id] = session
}

/// An event that would change nothing: a reply to no open request, or activity from the turn that ended.
private func isIgnored(_ e: AgentEvent, by session: Session) -> Bool {
    switch e.kind {
    case .permissionReplied(let requestId):
        return session.state != .needsApproval || !session.openRequests.contains { $0.requestId == requestId }
    case .activity:
        guard let turn = e.turnId, turn == session.endedTurnId else { return false }
        return session.state != .working && session.state != .needsApproval
    default:
        return false
    }
}

private func createsSession(_ kind: AgentEvent.Kind) -> Bool {
    switch kind {
    case .sessionEnded, .subagent, .renamed, .permissionReplied: false
    case .toolStarted(_, let subagent), .toolFinished(_, let subagent): !subagent
    default: true
    }
}

// MARK: - Discovery

private func applyDiscovered(_ found: DiscoveredSession, at date: Date, to state: inout SessionsState) {
    let id = found.sessionId
    if state.ended.contains(id) { return }

    let fileState = stateFromFileStatus(found.status)

    if var session = state.sessions[id] {
        session.pid = found.pid
        if let cwd = found.cwd, !cwd.isEmpty { session.cwd = cwd }
        if let name = found.name, !name.isEmpty { session.name = name }
        if let entrypoint = found.entrypoint { session.entrypoint = entrypoint }
        if !session.hasHookEvents, let fileState, date >= session.lastEventAt {
            // No hooks for this session: the file's coarse status is all we have.
            let newState: SessionState = (fileState == .idle && session.state == .working) ? .doneUnseen : fileState
            if newState != session.state, !(newState == .doneUnseen && session.state == .idle) {
                session.state = newState
                session.stateSince = found.statusUpdatedAt ?? date
            }
            session.lastEventAt = date
        } else if session.hasHookEvents, let fileState, let changed = found.statusUpdatedAt,
                  changed > session.stateSince.addingTimeInterval(Reducer.fileStatusMargin)
        {
            if fileState == .idle, session.state == .needsApproval || session.state == .working {
                // The turn ended without a hook: a declined permission prompt or an Esc interrupt.
                session.state = .idle
                session.stateSince = changed
                session.pendingTool = nil
                session.activity = nil
            } else if fileState == .working, session.state == .needsApproval {
                // Answered, but the resolving hook did not match the request (e.g. its input changed).
                session.state = .working
                session.stateSince = changed
                session.pendingTool = nil
            }
        }
        state.sessions[id] = session
    } else {
        state.sessions[id] = Session(
            id: id,
            agent: found.agent,
            state: fileState ?? .idle,
            stateSince: found.statusUpdatedAt ?? found.startedAt ?? date,
            lastEventAt: date,
            cwd: found.cwd,
            name: found.name,
            pid: found.pid,
            entrypoint: found.entrypoint
        )
    }
}

private func stateFromFileStatus(_ status: String?) -> SessionState? {
    switch status {
    case "busy", "working", "running": .working
    case "idle": .idle
    // Claude Code's file says "waiting" while a permission prompt (or other dialog) is open.
    case "waiting": .needsApproval
    default: nil
    }
}

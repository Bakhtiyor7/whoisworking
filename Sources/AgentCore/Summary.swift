import Foundation

/// What the notch shows, derived from the session list.
public struct NotchSummary: Equatable, Sendable {
    /// Needs approval, waiting for reply, or error. Longest wait first.
    public var needsYou: [Session]
    /// Working sessions, by name.
    public var working: [Session]
    /// Done (unseen first), then idle; newest first within each.
    public var done: [Session]
    public var needsYouCount: Int { needsYou.count }
    /// Seconds the longest-waiting "needs you" session has waited.
    public var longestWait: TimeInterval?

    public init(sessions: some Collection<Session>, now: Date) {
        needsYou = sessions.filter(\.state.needsUser).sorted { ($0.stateSince, $0.id) < ($1.stateSince, $1.id) }
        working = sessions.filter { $0.state == .working }.sorted {
            ($0.displayName.localizedLowercase, $0.id) < ($1.displayName.localizedLowercase, $1.id)
        }
        let newestFirst: (Session, Session) -> Bool = { ($0.stateSince, $0.id) > ($1.stateSince, $1.id) }
        done = sessions.filter { $0.state == .doneUnseen }.sorted(by: newestFirst)
            + sessions.filter { $0.state == .idle }.sorted(by: newestFirst)
        longestWait = needsYou.first.map { max(0, now.timeIntervalSince($0.stateSince)) }
    }

    public var isEmpty: Bool { needsYou.isEmpty && working.isEmpty && done.isEmpty }
    /// The wings appear only when something needs the user.
    public var showsWings: Bool { !needsYou.isEmpty }
}

/// Compact elapsed time for wings and rows: `now`, `42s`, `4m`, `2h`, `3d`.
public func formatElapsed(_ seconds: TimeInterval) -> String {
    let s = Int(seconds.rounded(.down))
    switch s {
    case ..<5: return "now"
    case ..<60: return "\(s)s"
    case ..<3600: return "\(s / 60)m"
    case ..<86_400: return "\(s / 3600)h"
    default: return "\(s / 86_400)d"
    }
}

/// The same, as words for VoiceOver.
public func formatElapsedSpoken(_ seconds: TimeInterval) -> String {
    let s = max(0, Int(seconds.rounded(.down)))
    func unit(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
    switch s {
    case ..<60: return unit(s, "second")
    case ..<3600: return unit(s / 60, "minute")
    case ..<86_400: return unit(s / 3600, "hour")
    default: return unit(s / 86_400, "day")
    }
}

extension Session {
    /// A running agent process seen before any of its hook events.
    public var isPlaceholder: Bool { id.hasPrefix("process:") }

    /// One line for a 44 pt row: what the session is doing.
    public var rowDetail: String {
        func firstLine(_ text: String?) -> String? {
            guard let line = text?.split(separator: "\n", omittingEmptySubsequences: true).first else { return nil }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : trimmed
        }
        switch state {
        case .working: return activity ?? "Working"
        case .needsApproval: return pendingTool?.summary ?? firstLine(message) ?? "Needs approval"
        case .waitingForReply: return firstLine(message) ?? "Waiting for your reply"
        case .doneUnseen: return firstLine(message) ?? "Done"
        case .idle: return isPlaceholder ? "Running · no live status yet" : "Idle"
        case .error: return firstLine(message) ?? "Error"
        }
    }

    /// Headline of the Needs you card.
    public var requestTitle: String {
        switch state {
        case .needsApproval:
            guard let tool = pendingTool else { return message ?? "Needs your approval" }
            switch tool.name {
            case "Bash", "PowerShell": return "Wants permission to run a command"
            case "Edit", "MultiEdit", "Write", "NotebookEdit": return "Wants permission to edit a file"
            case "WebFetch": return "Wants permission to fetch a page"
            default: return "Wants permission: \(tool.summary)"
            }
        case .waitingForReply: return message ?? "Waiting for your reply"
        case .error: return "Stopped with an error"
        default: return rowDetail
        }
    }

    /// The full command, path or text shown in the card's code block.
    public var requestDetail: String? {
        switch state {
        case .needsApproval: pendingTool?.detail
        case .error: message
        default: nil
        }
    }
}

import Foundation

/// Reads a Codex rollout (its session log, `transcript_path` in hook payloads) to find how a turn ended.
///
/// Codex CLI 0.163 fires no hook when a turn fails (for example an API error), so a session would stay
/// "working" forever. The rollout records `event_msg` / `task_complete` (with `error` when it failed).
/// Codex calls the rollout format unstable, so this is a best-effort fallback: unknown shapes are ignored.
public enum CodexRollout {
    public enum TurnEnd: Equatable, Sendable {
        case completed(lastMessage: String?)
        case failed(message: String)
    }

    /// How long a working session must be silent before its rollout is read.
    public static let quietInterval: TimeInterval = 10

    /// How the turn `turnId` ended, or nil while it is still running (or not in the text).
    public static func turnEnd(in text: String, turnId: String) -> TurnEnd? {
        var end: TurnEnd?
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard line.contains("task_"),
                  let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  json["type"] as? String == "event_msg",
                  let payload = json["payload"] as? [String: Any],
                  payload["turn_id"] as? String == turnId
            else { continue }
            switch payload["type"] as? String {
            case "task_started":
                end = nil
            case "task_complete":
                if let error = payload["error"] as? [String: Any] {
                    end = .failed(message: readableError(error["message"] as? String))
                } else {
                    end = .completed(lastMessage: payload["last_agent_message"] as? String)
                }
            default:
                break
            }
        }
        return end
    }

    /// For a Codex session that says "working" but has been silent for `quietInterval`, reads its rollout
    /// and returns the event that ends the turn, if the turn has ended.
    public static func endOfQuietTurn(_ session: Session, now: Date, read: (String) -> String?) -> StoreEvent? {
        guard session.agent == .codex, session.state == .working, session.hasHookEvents,
              now.timeIntervalSince(session.lastEventAt) >= quietInterval,
              let turnId = session.turnId, let path = session.transcriptPath,
              let text = read(path), let end = turnEnd(in: text, turnId: turnId)
        else { return nil }
        let kind: AgentEvent.Kind = switch end {
        case .failed(let message): .failed(error: message)
        case .completed(let lastMessage): .stopped(lastMessage: lastMessage)
        }
        return .agent(AgentEvent(sessionId: session.id, date: now, agent: .codex, cwd: session.cwd, kind: kind))
    }

    /// Codex stores API errors as a JSON string; pull out the human message when it is one.
    private static func readableError(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "The turn failed" }
        if let json = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any] {
            if let inner = json["error"] as? [String: Any], let message = inner["message"] as? String { return message }
            if let message = json["message"] as? String { return message }
        }
        return raw
    }

    /// The last `bytes` of a file: rollouts grow large, and only the end matters.
    public static func readTail(of path: String, bytes: Int = 256 * 1024) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let start = size > UInt64(bytes) ? size - UInt64(bytes) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd() else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

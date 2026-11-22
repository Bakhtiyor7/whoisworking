import Foundation

/// Maps raw Cursor hook JSON (app and `cursor-agent`) to common events.
/// Event and field names: https://cursor.com/docs/hooks and the cursor-agent hook runner (2026.04.17).
///
/// Cursor has no pre-tool event WhoIsWorking may register (they are permission hooks), so finished tools
/// and thoughts are observed activity, scoped to `generation_id` (RED-18). No event means "needs approval".
public enum CursorAdapter {
    public static func event(from data: Data, receivedAt date: Date) -> AgentEvent? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let sessionId = nonEmpty(json["conversation_id"]) ?? nonEmpty(json["session_id"]),
            let name = json["hook_event_name"] as? String,
            let kind = kind(for: name, json)
        else { return nil }
        let folder = (json["workspace_roots"] as? [String])?.first { !$0.isEmpty }
        var event = AgentEvent(sessionId: sessionId, date: date, agent: .cursor, cwd: folder, kind: kind)
        event.turnId = nonEmpty(json["generation_id"])
        event.transcriptPath = nonEmpty(json["transcript_path"])
        return event
    }

    /// True for a payload Cursor wrote, whatever header it arrived under (CUR-03).
    public static func isCursorPayload(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return json["cursor_version"] != nil
    }

    private static func kind(for name: String, _ json: [String: Any]) -> AgentEvent.Kind? {
        switch name {
        case "sessionStart": return .sessionStarted
        case "sessionEnd": return .sessionEnded
        case "beforeSubmitPrompt": return .promptSubmitted
        case "preToolUse": return .toolStarted(tool(json), subagent: false)
        case "postToolUse", "postToolUseFailure": return .activity(tool(json))
        case "afterAgentThought": return .activity(ToolActivity(name: "thought", summary: "Thinking"))
        case "stop":
            switch json["status"] as? String {
            case "aborted": return .interrupted
            case "error": return .failed(error: "Cursor stopped with an error")
            default: return .stopped(lastMessage: nil)
            }
        default: return nil
        }
    }

    /// Cursor's tool names map onto Claude Code's for the activity line (Shell is Bash, Write covers edits).
    static func tool(_ json: [String: Any]) -> ToolActivity {
        let name = json["tool_name"] as? String ?? "tool"
        let claudeName: String = switch name {
        case "Shell": "Bash"
        case "Delete", "StrReplace", "MultiEdit", "Edit": "Edit"
        default: name
        }
        var mapped = json
        mapped["tool_name"] = claudeName
        if let input = json["tool_input"] as? String {
            // MCP tool input arrives as a JSON string.
            mapped["tool_input"] = (try? JSONSerialization.jsonObject(with: Data(input.utf8))) as? [String: Any] ?? [:]
        }
        var activity = ClaudeCodeAdapter.tool(mapped)
        activity.name = name
        return activity
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let s = value as? String, !s.isEmpty else { return nil }
        return s
    }
}

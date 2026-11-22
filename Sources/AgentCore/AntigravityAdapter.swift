import Foundation

/// Maps Google Antigravity hook JSON to common events (spec 14).
/// Field names: https://antigravity.google/docs/hooks. The payload has no event name: each handler is
/// registered as `whoisworking-hook antigravity <Event>`, and the header's `event=` carries it (ING-10).
public enum AntigravityAdapter {
    public static func event(from data: Data, eventName: String?, receivedAt date: Date) -> AgentEvent? {
        guard
            let eventName,
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let sessionId = nonEmpty(json["conversationId"]),
            let kind = kind(for: eventName, json)
        else { return nil }
        let folder = (json["workspacePaths"] as? [String])?.first { !$0.isEmpty }
        var event = AgentEvent(sessionId: sessionId, date: date, agent: .antigravity, cwd: folder, kind: kind)
        event.transcriptPath = nonEmpty(json["transcriptPath"])
        return event
    }

    private static func kind(for name: String, _ json: [String: Any]) -> AgentEvent.Kind? {
        switch name {
        case "SessionStart": return .sessionStarted
        // Before each model call; with no turn id it also marks the start of a new turn (RED-18).
        case "PreInvocation": return .activity(ToolActivity(name: "model", summary: "Thinking"))
        // A failed tool stays a line; only Stop reports errors (ANT-04).
        case "PostToolUse": return .activity(tool(json["toolCall"] as? [String: Any] ?? [:]))
        case "Stop": return stop(json)
        default: return nil
        }
    }

    /// Error, then the step limit, then cancellation, then background work, then done (ANT-03).
    private static func stop(_ json: [String: Any]) -> AgentEvent.Kind {
        let reason = (json["terminationReason"] as? String ?? "").lowercased()
        if reason == "error" { return .failed(error: nonEmpty(json["error"]) ?? "Antigravity stopped with an error") }
        if reason == "max_steps_exceeded" { return .failed(error: "Stopped at the step limit") }
        if reason.contains("cancel") || reason.contains("interrupt") { return .interrupted }
        if json["fullyIdle"] as? Bool == false {
            return .activity(ToolActivity(name: "background", summary: "Background tasks running"))
        }
        return .stopped(lastMessage: nil)
    }

    /// Antigravity's tool names and argument keys map onto Claude Code's for the activity line.
    static func tool(_ call: [String: Any]) -> ToolActivity {
        let name = nonEmpty(call["name"]) ?? "tool"
        let args = call["args"] as? [String: Any] ?? [:]
        func first(_ keys: String...) -> String? { keys.lazy.compactMap { nonEmpty(args[$0]) }.first }
        let (claudeName, input): (String, [String: Any]) = switch name {
        case "run_command": ("Bash", ["command": first("CommandLine", "command") ?? ""])
        case "view_file", "view_file_outline": ("Read", ["file_path": first("AbsolutePath", "path", "file_path") ?? ""])
        case "write_to_file", "replace_file_content", "multi_replace_file_content":
            ("Edit", ["file_path": first("TargetFile", "path", "file_path") ?? ""])
        case "grep_search": ("Grep", ["pattern": first("Query", "pattern") ?? ""])
        default: (name, args)
        }
        var activity = ClaudeCodeAdapter.tool(["tool_name": claudeName, "tool_input": input])
        activity.name = name
        return activity
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let s = value as? String, !s.isEmpty else { return nil }
        return s
    }
}

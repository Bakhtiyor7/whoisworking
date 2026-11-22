import Foundation

/// Maps raw Codex hook JSON to common events.
/// Event and field names: https://learn.chatgpt.com/docs/hooks (Codex CLI 0.163).
///
/// Codex has no Notification event, so "needs approval" comes only from `PermissionRequest`,
/// and there is no "waiting for your reply" signal. `Interrupt` means the user stopped the turn.
public enum CodexAdapter {
    public static func event(from data: Data, receivedAt date: Date) -> AgentEvent? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let sessionId = json["session_id"] as? String, !sessionId.isEmpty,
            let name = json["hook_event_name"] as? String,
            let kind = kind(for: name, json)
        else { return nil }
        var event = AgentEvent(sessionId: sessionId, date: date, agent: .codex, cwd: json["cwd"] as? String, kind: kind)
        event.turnId = json["turn_id"] as? String
        event.transcriptPath = json["transcript_path"] as? String
        return event
    }

    private static func kind(for name: String, _ json: [String: Any]) -> AgentEvent.Kind? {
        let inSubagent = json["agent_id"] != nil
        switch name {
        case "SessionStart": return .sessionStarted
        case "SessionEnd": return .sessionEnded
        case "UserPromptSubmit": return .promptSubmitted
        case "PreToolUse": return .toolStarted(tool(json), subagent: inSubagent)
        case "PostToolUse": return .toolFinished(tool(json), subagent: inSubagent)
        case "PermissionRequest": return .permissionRequested(tool(json))
        case "Stop": return .stopped(lastMessage: json["last_assistant_message"] as? String)
        case "Interrupt": return .interrupted
        case "SubagentStart": return .subagent(started: true, type: json["agent_type"] as? String)
        case "SubagentStop": return .subagent(started: false, type: json["agent_type"] as? String)
        default: return nil  // PreCompact, PostCompact, Pre/PostModelRequest: diagnostic only.
        }
    }

    static func tool(_ json: [String: Any]) -> ToolActivity {
        let name = json["tool_name"] as? String ?? "tool"
        let input = json["tool_input"] as? [String: Any] ?? [:]
        switch name {
        case "apply_patch":
            let patch = (input["command"] ?? input["input"] ?? input["patch"]).flatMap(commandText) ?? ""
            return patchActivity(patch)
        case "Bash":
            let command = input["command"].flatMap(commandText) ?? ""
            let description = (input["description"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let firstLine = command.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? command
            return ToolActivity(name: name, summary: ClaudeCodeAdapter.shorten(description ?? firstLine), detail: command)
        default:
            return ClaudeCodeAdapter.tool(json)
        }
    }

    /// Codex may send a command as a string or as an argv array.
    private static func commandText(_ value: Any) -> String? {
        if let s = value as? String { return s }
        if let parts = value as? [String] { return parts.map(shellQuote).joined(separator: " ") }
        return nil
    }

    private static func shellQuote(_ s: String) -> String {
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_./=:@%+,")
        if !s.isEmpty, s.unicodeScalars.allSatisfy(safe.contains) { return s }
        return "'" + s.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    private static func patchActivity(_ patch: String) -> ToolActivity {
        let prefixes = ["*** Update File: ", "*** Add File: ", "*** Delete File: "]
        var lines: [String] = []
        var paths: [String] = []
        for line in patch.split(separator: "\n") {
            for prefix in prefixes where line.hasPrefix(prefix) {
                let path = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                paths.append(path)
                lines.append(String(prefix.dropFirst(4)) + path)
            }
        }
        guard let first = paths.first else {
            return ToolActivity(name: "apply_patch", summary: "Editing files", detail: patch.isEmpty ? nil : patch)
        }
        let base = (first as NSString).lastPathComponent
        let summary = paths.count > 1 ? "Editing \(base) and \(paths.count - 1) more" : "Editing \(base)"
        return ToolActivity(name: "apply_patch", summary: ClaudeCodeAdapter.shorten(summary), detail: lines.joined(separator: "\n"))
    }
}

/// Finding Codex CLI processes.
public enum CodexProcesses {
    /// Process name of the native Codex binary (CLI, and the app-server inside ChatGPT.app).
    public static let processName = "codex"

    /// Subcommands that are not an interactive session.
    static let nonInteractive: Set<String> = [
        "exec", "e", "review", "login", "logout", "mcp", "mcp-server", "app-server", "app", "completion",
        "sandbox", "debug", "apply", "a", "cloud", "responses-api-proxy", "stdio-to-uds", "features", "help",
        "exec-server",
    ]

    /// Options that take a separate value.
    static let optionsWithValue: Set<String> = [
        "-c", "--config", "-a", "--ask-for-approval", "-s", "--sandbox", "-m", "--model", "-p", "--profile",
        "-C", "--cd", "-i", "--image", "--add-dir", "--enable", "--disable", "--local-provider",
    ]

    /// Interactive Codex CLIs that are running now. The reducer shows them as idle placeholders until
    /// their first hook event, so sessions started before Perch are visible (state unknown until then).
    public static func discoveryEvents(probe: ProcessProbe, now: Date) -> [StoreEvent] {
        probe.allPids().sorted().compactMap { pid in
            guard probe.name(of: pid) == processName, probe.hasTerminal(pid),
                  let args = probe.arguments(of: pid), isInteractive(arguments: args)
            else { return nil }
            let proc = DiscoveredProcess(agent: .codex, pid: pid, cwd: probe.cwd(of: pid), startedAt: probe.startTime(of: pid))
            return .discoveredProcess(proc, at: now)
        }
    }

    /// True for `codex`, `codex "prompt"`, `codex resume …`: an interactive terminal session.
    public static func isInteractive(arguments: [String]) -> Bool {
        var i = 1
        while i < arguments.count {
            let arg = arguments[i]
            if arg.hasPrefix("-") {
                if optionsWithValue.contains(arg) { i += 1 }
                i += 1
                continue
            }
            return !nonInteractive.contains(arg)
        }
        return true
    }
}

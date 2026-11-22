import Foundation

/// Maps raw Claude Code hook JSON (stdin of a command hook) to common events.
/// Event and field names: https://code.claude.com/docs/en/hooks
public enum ClaudeCodeAdapter {
    public static func event(from data: Data, receivedAt date: Date) -> AgentEvent? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let sessionId = json["session_id"] as? String, !sessionId.isEmpty,
            let name = json["hook_event_name"] as? String,
            let kind = kind(for: name, json)
        else { return nil }
        return AgentEvent(sessionId: sessionId, date: date, agent: .claudeCode, cwd: json["cwd"] as? String, kind: kind)
    }

    private static func kind(for name: String, _ json: [String: Any]) -> AgentEvent.Kind? {
        let inSubagent = json["agent_id"] != nil
        // AskUserQuestion is routed through the permission flow but is a question to the user.
        if json["tool_name"] as? String == "AskUserQuestion" {
            switch name {
            case "PermissionRequest": return .waitingForReply(message: firstQuestion(json))
            case "PostToolUse", "PostToolUseFailure": return .resumed
            default: break
            }
        }
        switch name {
        case "SessionStart": return .sessionStarted
        case "SessionEnd": return .sessionEnded
        case "UserPromptSubmit": return .promptSubmitted
        case "PreToolUse": return .toolStarted(tool(json), subagent: inSubagent)
        case "PostToolUse", "PostToolUseFailure": return .toolFinished(tool(json), subagent: inSubagent)
        case "PermissionRequest": return .permissionRequested(tool(json))
        case "PermissionDenied": return .permissionDenied
        case "Stop": return .stopped(lastMessage: json["last_assistant_message"] as? String)
        case "StopFailure": return .failed(error: failure(json))
        case "SubagentStart": return .subagent(started: true, type: json["agent_type"] as? String)
        case "SubagentStop": return .subagent(started: false, type: json["agent_type"] as? String)
        case "Notification": return notification(json)
        default: return nil
        }
    }

    private static func notification(_ json: [String: Any]) -> AgentEvent.Kind? {
        let message = json["message"] as? String
        switch json["notification_type"] as? String {
        case "permission_prompt": return .permissionNotice(message: message)
        case "idle_prompt": return .turnIdle(message: message)
        case "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input":
            return .waitingForReply(message: message)
        case "elicitation_complete", "elicitation_response": return .resumed
        default: return nil
        }
    }

    private static func firstQuestion(_ json: [String: Any]) -> String? {
        let input = json["tool_input"] as? [String: Any]
        let questions = input?["questions"] as? [[String: Any]]
        return questions?.first?["question"] as? String
    }

    private static func failure(_ json: [String: Any]) -> String {
        let code = json["error"] as? String ?? "unknown"
        let readable: String = switch code {
        case "rate_limit": "Rate limit"
        case "authentication_failed": "Authentication failed"
        case "billing_error": "Billing error"
        case "server_error": "Server error"
        case "max_output_tokens": "Output limit reached"
        case "model_not_found": "Model not found"
        case "invalid_request": "Invalid request"
        default: code.replacingOccurrences(of: "_", with: " ").capitalizedFirst
        }
        if let details = json["error_details"] as? String, !details.isEmpty { return "\(readable) (\(details))" }
        return readable
    }

    // MARK: Tools

    static func tool(_ json: [String: Any]) -> ToolActivity {
        let name = json["tool_name"] as? String ?? "tool"
        let input = json["tool_input"] as? [String: Any] ?? [:]
        let filePath = (input["file_path"] ?? input["notebook_path"] ?? input["path"]) as? String
        let fileName = filePath.map { ($0 as NSString).lastPathComponent }

        switch name {
        case "Bash", "PowerShell":
            let command = input["command"] as? String ?? ""
            let description = (input["description"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let firstLine = command.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? command
            return ToolActivity(name: name, summary: shorten(description ?? firstLine), detail: command)
        case "Edit", "MultiEdit", "Write", "NotebookEdit":
            return ToolActivity(name: name, summary: "Editing \(fileName ?? "a file")", detail: filePath)
        case "Read":
            return ToolActivity(name: name, summary: "Reading \(fileName ?? "a file")", detail: filePath)
        case "Grep":
            let pattern = input["pattern"] as? String
            return ToolActivity(name: name, summary: shorten("Searching for \(pattern ?? "text")"), detail: pattern)
        case "Glob":
            return ToolActivity(name: name, summary: "Finding files", detail: input["pattern"] as? String)
        case "WebFetch":
            let url = input["url"] as? String
            let host = url.flatMap { URL(string: $0)?.host() }
            return ToolActivity(name: name, summary: "Fetching \(host ?? "a page")", detail: url)
        case "WebSearch":
            let query = input["query"] as? String
            return ToolActivity(name: name, summary: shorten("Searching the web for \(query ?? "…")"), detail: query)
        case "Task", "Agent":
            let description = input["description"] as? String
            return ToolActivity(
                name: name, summary: shorten(description.map { "Subagent: \($0)" } ?? "Running a subagent"),
                detail: input["prompt"] as? String)
        default:
            if name.hasPrefix("mcp__") {
                let parts = name.split(separator: "__", omittingEmptySubsequences: true).map(String.init)
                let server = parts.count > 1 ? parts[1] : "mcp"
                let toolName = parts.count > 2 ? parts[2...].joined(separator: "__") : name
                return ToolActivity(name: name, summary: shorten("Using \(toolName) (\(server))"), detail: compactJSON(input))
            }
            return ToolActivity(name: name, summary: shorten("Using \(name)"), detail: compactJSON(input))
        }
    }

    static func shorten(_ text: String, max: Int = 60) -> String {
        let oneLine = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        guard oneLine.count > max else { return oneLine }
        return String(oneLine.prefix(max - 1)) + "…"
    }

    private static func compactJSON(_ value: [String: Any]) -> String? {
        guard !value.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        return text.count > 2000 ? String(text.prefix(1999)) + "…" : text
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// One message on the WhoIsWorking socket: an optional `whoisworking1 <agent>` header line, then the hook JSON.
/// The header lets later agents (Codex, Cursor, OpenCode) share the same socket and hook script.
public struct HookMessage: Equatable, Sendable {
    public static let headerPrefix = "whoisworking1 "

    public var agent: String
    public var payload: Data
    /// Parent pid of the hook script (`ppid=` in the header), used to find the agent process.
    public var parentPid: Int32?
    /// The hook event, for agents whose payload has no event name (`event=` in the header, ING-10).
    public var eventName: String?

    public init(agent: String, payload: Data, parentPid: Int32? = nil, eventName: String? = nil) {
        self.agent = agent
        self.payload = payload
        self.parentPid = parentPid
        self.eventName = eventName
    }

    public static func parse(_ data: Data) -> HookMessage? {
        let prefix = Data(headerPrefix.utf8)
        if data.starts(with: prefix) {
            guard let newline = data.firstIndex(of: UInt8(ascii: "\n")) else { return nil }
            let headerBytes = data[data.startIndex + prefix.count ..< newline]
            // "<agent> [key=value ...]"
            guard let header = String(data: headerBytes, encoding: .utf8) else { return nil }
            let words = header.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard let agent = words.first, !agent.contains("=") else { return nil }
            var parentPid: Int32?
            for word in words.dropFirst() where word.hasPrefix("ppid=") {
                parentPid = Int32(word.dropFirst(5)).flatMap { $0 > 1 ? $0 : nil }
            }
            // Letters only, exactly once; anything else is ambiguous and gives no event name.
            let events = words.dropFirst().filter { $0.hasPrefix("event=") }.map { String($0.dropFirst(6)) }
            let eventName = events.count == 1 && !events[0].isEmpty && events[0].allSatisfy { $0.isASCII && $0.isLetter }
                ? events[0] : nil
            return HookMessage(
                agent: agent, payload: Data(data[(newline + 1)...]), parentPid: parentPid, eventName: eventName)
        }
        // No header: a bare JSON object is treated as Claude Code.
        let firstByte = data.first { !($0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09) }
        guard firstByte == UInt8(ascii: "{") else { return nil }
        return HookMessage(agent: "claude-code", payload: data)
    }

    public func event(receivedAt date: Date) -> AgentEvent? {
        switch agent {
        case "claude-code":
            // cursor-agent also runs Claude Code hooks; its JSON is never a Claude Code session (CUR-03).
            CursorAdapter.isCursorPayload(payload)
                ? CursorAdapter.event(from: payload, receivedAt: date)
                : ClaudeCodeAdapter.event(from: payload, receivedAt: date)
        case "codex": CodexAdapter.event(from: payload, receivedAt: date)
        case "cursor": CursorAdapter.event(from: payload, receivedAt: date)
        case "opencode": OpenCodeAdapter.event(from: payload, receivedAt: date)
        case "antigravity": AntigravityAdapter.event(from: payload, eventName: eventName, receivedAt: date)
        default: nil
        }
    }
}

/// `~/.claude/sessions/<pid>.json`, written by Claude Code for CLI and desktop sessions.
public enum ClaudeSessionFile {
    public static func parse(_ data: Data) -> DiscoveredSession? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let pid = (json["pid"] as? NSNumber)?.int32Value,
            let sessionId = json["sessionId"] as? String, !sessionId.isEmpty
        else { return nil }
        func date(_ key: String) -> Date? {
            (json[key] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        }
        return DiscoveredSession(
            sessionId: sessionId,
            agent: .claudeCode,
            pid: pid,
            cwd: json["cwd"] as? String,
            name: json["name"] as? String,
            status: json["status"] as? String,
            entrypoint: json["entrypoint"] as? String,
            startedAt: date("startedAt"),
            statusUpdatedAt: date("statusUpdatedAt") ?? date("updatedAt")
        )
    }
}

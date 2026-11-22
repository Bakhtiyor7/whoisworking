import Foundation
import Testing
@testable import AgentCore

// Cursor hook payloads (CUR-01…06). Fixtures are CONSTRUCTED from cursor.com/docs/hooks and the
// cursor-agent hook runner; see Tests/Fixtures/README.md.

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private let conversation = "c0ffee00-0000-4000-8000-000000000001"

private func cursor(_ name: String, at date: Date = now) throws -> AgentEvent? {
    CursorAdapter.event(from: try fixture("cursor/\(name).json"), receivedAt: date)
}

private func json(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: object)
}

@Suite("Cursor adapter")
struct CursorAdapterTests {
    @Test func lifecycleMapsToSessionEvents() throws {
        #expect(try cursor("sessionStart")?.kind == .sessionStarted)
        #expect(try cursor("sessionEnd")?.kind == .sessionEnded)
        let prompt = try json(["conversation_id": "c1", "hook_event_name": "beforeSubmitPrompt", "prompt": "hi"])
        #expect(CursorAdapter.event(from: prompt, receivedAt: now)?.kind == .promptSubmitted)
    }

    @Test func stopStatusesMapToDoneInterruptedAndError() throws {
        #expect(try cursor("stop-completed")?.kind == .stopped(lastMessage: nil))
        #expect(try cursor("stop-aborted")?.kind == .interrupted)
        #expect(try cursor("stop-error")?.kind == .failed(error: "Cursor stopped with an error"))
        let odd = try json(["conversation_id": "c1", "hook_event_name": "stop", "status": "paused"])
        #expect(CursorAdapter.event(from: odd, receivedAt: now)?.kind == .stopped(lastMessage: nil))
    }

    @Test func toolsAndThoughtsAreObservedActivity() throws {
        guard case .activity(let shell)? = try cursor("postToolUse-Shell")?.kind else {
            Issue.record("postToolUse is not activity"); return
        }
        #expect(shell?.summary == "swift test")
        #expect(shell?.detail == "swift test")
        guard case .activity(let write)? = try cursor("postToolUse-Write")?.kind else {
            Issue.record("postToolUse is not activity"); return
        }
        #expect(write?.summary == "Editing App.swift")
        guard case .activity(let failed)? = try cursor("postToolUseFailure-Shell")?.kind else {
            Issue.record("postToolUseFailure is not activity"); return
        }
        #expect(failed?.summary == "swift build")
        #expect(try cursor("afterAgentThought")?.kind == .activity(ToolActivity(name: "thought", summary: "Thinking")))
        let pre = try json([
            "conversation_id": "c1", "hook_event_name": "preToolUse", "tool_name": "Shell",
            "tool_input": ["command": "ls"],
        ])
        #expect(CursorAdapter.event(from: pre, receivedAt: now)?.kind
            == .toolStarted(ToolActivity(name: "Shell", summary: "ls", detail: "ls"), subagent: false))
    }

    @Test func commonFieldsGiveIdFolderAndTurn() throws {
        let event = try #require(try cursor("stop-aborted"))
        #expect(event.sessionId == conversation)
        #expect(event.agent == .cursor)
        #expect(event.cwd == "/Users/me/dev/demo")
        #expect(event.turnId == "gen-0002")
        #expect(event.pid == nil)
        // sessionStart may carry only session_id.
        let start = try json(["session_id": "c9", "hook_event_name": "sessionStart", "workspace_roots": []])
        #expect(CursorAdapter.event(from: start, receivedAt: now)?.sessionId == "c9")
    }

    @Test func unknownOrBrokenInputIsDropped() throws {
        #expect(CursorAdapter.event(from: Data("{".utf8), receivedAt: now) == nil)
        #expect(CursorAdapter.event(from: try json(["hook_event_name": "stop"]), receivedAt: now) == nil)
        let unknown = try json(["conversation_id": "c1", "hook_event_name": "workspaceOpen"])
        #expect(CursorAdapter.event(from: unknown, receivedAt: now) == nil)
        let permission = try json(["conversation_id": "c1", "hook_event_name": "beforeShellExecution", "command": "ls"])
        #expect(CursorAdapter.event(from: permission, receivedAt: now) == nil)
    }

    @Test func noCursorEventMeansNeedsApproval() throws {
        let files = try FileManager.default.contentsOfDirectory(atPath: fixturesDir.appendingPathComponent("cursor").path)
        let state = try files.sorted().compactMap { try cursor(($0 as NSString).deletingPathExtension) }
            .reduce(SessionsState()) { reduce($0, .agent($1)) }
        for session in state.sessions.values { #expect(session.state != .needsApproval) }
        for name in ["beforeShellExecution", "beforeMCPExecution", "beforeReadFile", "subagentStart"] {
            let event = try json(["conversation_id": "c1", "hook_event_name": name])
            #expect(CursorAdapter.event(from: event, receivedAt: now) == nil)
        }
    }

    @Test func sessionsEndOnSessionEndOrAfterLongSilence() throws {
        let start = try #require(try cursor("sessionStart"))
        var state = reduce(SessionsState(), .agent(start))
        #expect(state.sessions[conversation]?.pid == nil)
        state = reduce(state, .pruneOrphans(now: now.addingTimeInterval(14 * 60)))
        #expect(state.sessions[conversation] != nil)
        state = reduce(state, .pruneOrphans(now: now.addingTimeInterval(16 * 60)))
        #expect(state.sessions[conversation] == nil)

        // After the silence rule a later event recreates the session.
        state = reduce(state, .agent(try #require(try cursor("stop-completed", at: now.addingTimeInterval(17 * 60)))))
        #expect(state.sessions[conversation]?.state == .doneUnseen)

        // After sessionEnd only a new sessionStart brings it back.
        state = reduce(SessionsState(), .agent(start))
        state = reduce(state, .agent(try #require(try cursor("sessionEnd"))))
        #expect(state.sessions[conversation] == nil)
        state = reduce(state, .agent(try #require(try cursor("stop-completed", at: now.addingTimeInterval(60)))))
        #expect(state.sessions[conversation] == nil)
        state = reduce(state, .agent(try #require(try cursor("sessionStart", at: now.addingTimeInterval(120)))))
        #expect(state.sessions[conversation] != nil)
    }

    @Test func mapsEveryFixture() throws {
        let files = try FileManager.default.contentsOfDirectory(atPath: fixturesDir.appendingPathComponent("cursor").path)
        #expect(files.count >= 9)
        for file in files where file.hasSuffix(".json") {
            #expect(try cursor((file as NSString).deletingPathExtension) != nil, "\(file) did not map")
        }
    }
}

@Suite("Cursor routing")
struct CursorRoutingTests {
    @Test func routesCursorMessagesToTheAdapter() throws {
        var data = Data("whoisworking1 cursor ppid=42\n".utf8)
        data.append(try fixture("cursor/stop-completed.json"))
        let event = HookMessage.parse(data).flatMap { $0.event(receivedAt: now) }
        #expect(event?.agent == .cursor)
        #expect(event?.sessionId == conversation)
    }

    @Test func cursorPayloadsUnderTheClaudeHeaderNeverBecomeClaudeSessions() throws {
        // cursor-agent runs Claude Code hooks too; its JSON then arrives under the claude-code header.
        var data = Data("whoisworking1 claude-code ppid=42\n".utf8)
        data.append(try fixture("cursor/sessionStart.json"))
        let event = HookMessage.parse(data).flatMap { $0.event(receivedAt: now) }
        #expect(event?.agent == .cursor)
        // Cursor uses Claude-style names for some converted hooks; those still never become Claude sessions.
        let claudeNamed = try json([
            "conversation_id": "c1", "session_id": "c1", "hook_event_name": "Stop", "cursor_version": "3.25.9",
        ])
        var named = Data("whoisworking1 claude-code\n".utf8)
        named.append(claudeNamed)
        #expect(HookMessage.parse(named).flatMap { $0.event(receivedAt: now) }?.agent != .claudeCode)
    }
}

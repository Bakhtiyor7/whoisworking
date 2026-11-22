import Foundation
import Testing
@testable import AgentCore

// Antigravity hook payloads (ANT-02…06). Fixtures are CONSTRUCTED from antigravity.google/docs/hooks;
// the payload has no event name, so the header's `event=` carries it (ING-10).

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private let conversation = "5a1e0000-0000-4000-8000-000000000001"

/// The fixture as it arrives on the socket: the event name comes from the file name's first word.
private func message(_ name: String) throws -> HookMessage {
    let event = String(name.split(separator: "-").first!)
    var data = Data("whoisworking1 antigravity ppid=42 event=\(event)\n".utf8)
    data.append(try fixture("antigravity/\(name).json"))
    return try #require(HookMessage.parse(data))
}

private func antigravity(_ name: String, at date: Date = now) throws -> AgentEvent? {
    try message(name).event(receivedAt: date)
}

@Suite("Antigravity adapter")
struct AntigravityAdapterTests {
    @Test func routesAntigravityMessagesWithTheirEventName() throws {
        let start = try #require(try antigravity("SessionStart"))
        #expect(start.agent == .antigravity)
        #expect(start.kind == .sessionStarted)
    }

    @Test func aMessageWithoutAnEventNameIsDropped() throws {
        var data = Data("whoisworking1 antigravity ppid=42\n".utf8)
        data.append(try fixture("antigravity/SessionStart.json"))
        #expect(HookMessage.parse(data)?.event(receivedAt: now) == nil)
        var unknown = Data("whoisworking1 antigravity event=PreToolUse\n".utf8)
        unknown.append(try fixture("antigravity/SessionStart.json"))
        #expect(HookMessage.parse(unknown)?.event(receivedAt: now) == nil)
        #expect(AntigravityAdapter.event(from: Data("{".utf8), eventName: "Stop", receivedAt: now) == nil)
        #expect(AntigravityAdapter.event(from: Data(#"{"workspacePaths":[]}"#.utf8), eventName: "Stop", receivedAt: now) == nil)
    }

    @Test func lifecycleMapsToSessionEvents() throws {
        #expect(try antigravity("SessionStart")?.kind == .sessionStarted)
        #expect(try antigravity("PreInvocation")?.kind == .activity(ToolActivity(name: "model", summary: "Thinking")))
        guard case .activity(let tool)? = try antigravity("PostToolUse-run_command")?.kind else {
            Issue.record("PostToolUse is not activity"); return
        }
        #expect(tool?.name == "run_command")
        #expect(tool?.summary == "swift test")
        #expect(tool?.detail == "swift test")
        #expect(try antigravity("Stop-model_stop")?.kind == .stopped(lastMessage: nil))
    }

    @Test func stopPrecedence() throws {
        #expect(try antigravity("Stop-error")?.kind == .failed(error: "Model overloaded"))
        #expect(try antigravity("Stop-max_steps_exceeded")?.kind == .failed(error: "Stopped at the step limit"))
        #expect(try antigravity("Stop-background")?.kind
            == .activity(ToolActivity(name: "background", summary: "Background tasks running")))
        func stop(_ fields: [String: Any]) throws -> AgentEvent.Kind? {
            var json: [String: Any] = ["conversationId": "c1", "fullyIdle": true]
            json.merge(fields) { $1 }
            return AntigravityAdapter.event(
                from: try JSONSerialization.data(withJSONObject: json), eventName: "Stop", receivedAt: now)?.kind
        }
        #expect(try stop(["terminationReason": "user_cancelled"]) == .interrupted)
        #expect(try stop(["terminationReason": "error"]) == .failed(error: "Antigravity stopped with an error"))
        // An error wins over background work still running.
        #expect(try stop(["terminationReason": "error", "error": "boom", "fullyIdle": false]) == .failed(error: "boom"))
        #expect(try stop(["terminationReason": "something_new"]) == .stopped(lastMessage: nil))
    }

    @Test func commonFieldsGiveIdAndFolder() throws {
        let event = try #require(try antigravity("Stop-model_stop"))
        #expect(event.sessionId == conversation)
        #expect(event.cwd == "/Users/me/dev/demo")
        #expect(event.transcriptPath?.hasSuffix("transcript.jsonl") == true)
        #expect(event.turnId == nil)
        #expect(event.pid == nil)
    }

    @Test func repeatedTurnsReuseTheSession() throws {
        let turn: [(String, TimeInterval)] = [
            ("SessionStart", 0), ("PreInvocation", 1), ("PostToolUse-run_command", 2), ("Stop-model_stop", 3),
            ("PreInvocation", 10), ("Stop-model_stop", 11), ("PreInvocation", 20),
        ]
        var state = SessionsState()
        for (name, s) in turn {
            state = reduce(state, .agent(try #require(try antigravity(name, at: now.addingTimeInterval(s)))))
        }
        #expect(state.sessions.count == 1)
        #expect(state.sessions[conversation]?.state == .working)
        #expect(state.sessions[conversation]?.stateSince == now.addingTimeInterval(20))
    }

    @Test func failedToolsStayActivityLines() throws {
        guard case .activity(let tool)? = try antigravity("PostToolUse-view_file-error")?.kind else {
            Issue.record("a failed tool is not activity"); return
        }
        #expect(tool?.summary == "Reading App.swift")
        let files = try FileManager.default.contentsOfDirectory(atPath: fixturesDir.appendingPathComponent("antigravity").path)
        for file in files {
            let kind = try antigravity((file as NSString).deletingPathExtension)?.kind
            if case .permissionRequested = kind { Issue.record("\(file) means needs approval") }
        }
    }

    @Test func quietConversationsGoAfterLongSilence() throws {
        var state = reduce(SessionsState(), .agent(try #require(try antigravity("Stop-model_stop"))))
        state = reduce(state, .pruneOrphans(now: now.addingTimeInterval(14 * 60)))
        #expect(state.sessions[conversation] != nil)
        state = reduce(state, .pruneOrphans(now: now.addingTimeInterval(16 * 60)))
        #expect(state.sessions[conversation] == nil)
    }

    @Test func mapsEveryFixture() throws {
        let files = try FileManager.default.contentsOfDirectory(atPath: fixturesDir.appendingPathComponent("antigravity").path)
        #expect(files.count >= 8)
        for file in files where file.hasSuffix(".json") {
            #expect(try antigravity((file as NSString).deletingPathExtension) != nil, "\(file) did not map")
        }
    }
}

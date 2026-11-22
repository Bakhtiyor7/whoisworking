import Foundation
import Testing
@testable import AgentCore

/// `Tests/Fixtures`, found relative to this file so no resource bundle is needed.
let fixturesDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Fixtures")

func fixture(_ path: String) throws -> Data {
    try Data(contentsOf: fixturesDir.appendingPathComponent(path))
}

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private let sid = "8f2b6c1e-1111-4a5b-9c3d-000000000001"

private func kind(_ name: String) throws -> AgentEvent.Kind? {
    try ClaudeCodeAdapter.event(from: fixture("claude-code/\(name).json"), receivedAt: now)?.kind
}

@Suite("Claude Code adapter")
struct ClaudeCodeAdapterTests {
    @Test func commonFieldsAreMapped() throws {
        let event = try #require(ClaudeCodeAdapter.event(from: fixture("claude-code/SessionStart.json"), receivedAt: now))
        #expect(event.sessionId == sid)
        #expect(event.cwd == "/Users/me/api-server")
        #expect(event.date == now)
        #expect(event.agent == .claudeCode)
        #expect(event.kind == .sessionStarted)
    }

    @Test func lifecycleEvents() throws {
        #expect(try kind("SessionEnd") == .sessionEnded)
        #expect(try kind("UserPromptSubmit") == .promptSubmitted)
        #expect(try kind("Stop") == .stopped(lastMessage: "All 42 tests pass. I fixed the missing express import."))
        #expect(try kind("StopFailure") == .failed(error: "Rate limit (429 Too Many Requests)"))
    }

    @Test func bashToolUsesDescriptionForTheRowAndCommandForTheCard() throws {
        let tool = ToolActivity(name: "Bash", summary: "Run test suite with coverage", detail: "npm test -- --coverage")
        #expect(try kind("PreToolUse-Bash") == .toolStarted(tool, subagent: false))
        #expect(try kind("PermissionRequest-Bash") == .permissionRequested(tool))
        #expect(try kind("PostToolUse-Bash") == .toolFinished(tool, subagent: false))
        #expect(try kind("PostToolUseFailure-Bash") == .toolFinished(tool, subagent: false))
    }

    @Test func editToolShowsTheFileName() throws {
        let tool = ToolActivity(name: "Edit", summary: "Editing Header.tsx", detail: "/Users/me/api-server/src/Header.tsx")
        #expect(try kind("PreToolUse-Edit") == .toolStarted(tool, subagent: false))
    }

    @Test func mcpToolShowsToolAndServer() throws {
        guard case .toolStarted(let tool, false)? = try kind("PreToolUse-mcp") else {
            Issue.record("expected toolStarted")
            return
        }
        #expect(tool.summary == "Using create_issue (github)")
        #expect(tool.detail == #"{"title":"Bug"}"#)
    }

    @Test func toolCallsInsideASubagentAreMarked() throws {
        let tool = ToolActivity(name: "Read", summary: "Reading README.md", detail: "/Users/me/api-server/README.md")
        #expect(try kind("PreToolUse-subagent") == .toolStarted(tool, subagent: true))
    }

    @Test func subagentLifecycle() throws {
        #expect(try kind("SubagentStart") == .subagent(started: true, type: "Explore"))
        #expect(try kind("SubagentStop") == .subagent(started: false, type: "Explore"))
    }

    @Test func autoModeDenial() throws {
        #expect(try kind("PermissionDenied") == .permissionDenied)
    }

    @Test func notifications() throws {
        #expect(try kind("Notification-permission_prompt") == .permissionNotice(message: "Claude needs your permission to use Bash"))
        #expect(try kind("Notification-idle_prompt")
            == .waitingForReply(message: "Claude is waiting for your input", onlyIfActive: true))
        #expect(try kind("Notification-elicitation_dialog")
            == .waitingForReply(message: "Claude has a question for you", onlyIfActive: false))
        #expect(try kind("Notification-elicitation_response") == .resumed)
        #expect(try kind("Notification-auth_success") == nil)
    }

    @Test func unknownOrBrokenInputIsDropped() {
        #expect(ClaudeCodeAdapter.event(from: Data("not json".utf8), receivedAt: now) == nil)
        #expect(ClaudeCodeAdapter.event(from: Data(#"{"hook_event_name":"Stop"}"#.utf8), receivedAt: now) == nil)
        #expect(ClaudeCodeAdapter.event(
            from: Data(#"{"session_id":"x","hook_event_name":"FutureEvent"}"#.utf8), receivedAt: now) == nil)
        #expect(ClaudeCodeAdapter.event(from: Data("[1,2]".utf8), receivedAt: now) == nil)
    }

    @Test func longBashCommandsWithoutDescriptionAreShortenedForTheRow() {
        let long = String(repeating: "x", count: 200)
        let json = #"{"session_id":"x","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"\#(long)\nsecond line"}}"#
        guard case .toolStarted(let tool, _)? = ClaudeCodeAdapter.event(from: Data(json.utf8), receivedAt: now)?.kind else {
            Issue.record("expected toolStarted")
            return
        }
        #expect(tool.summary.count <= 60)
        #expect(tool.summary.hasSuffix("…"))
        #expect(tool.detail == long + "\nsecond line")
    }
}

@Suite("Wire message")
struct HookMessageTests {
    @Test func headerNamesTheAgent() {
        let msg = HookMessage.parse(Data("perch1 claude-code\n{\"a\":1}".utf8))
        #expect(msg?.agent == "claude-code")
        #expect(msg?.payload == Data(#"{"a":1}"#.utf8))
    }

    @Test func bareJSONIsTreatedAsClaudeCode() {
        let msg = HookMessage.parse(Data(#"  {"a":1}"#.utf8))
        #expect(msg?.agent == "claude-code")
    }

    @Test func emptyOrGarbageIsRejected() {
        #expect(HookMessage.parse(Data()) == nil)
        #expect(HookMessage.parse(Data("hello".utf8)) == nil)
    }

    @Test func routesClaudeCodeMessagesToTheAdapter() throws {
        var data = Data("perch1 claude-code\n".utf8)
        data.append(try fixture("claude-code/Stop.json"))
        let event = HookMessage.parse(data).flatMap { $0.event(receivedAt: now) }
        #expect(event?.sessionId == sid)
    }

    @Test func unknownAgentsAreIgnored() {
        let event = HookMessage.parse(Data("perch1 someday-agent\n{\"session_id\":\"x\"}".utf8))?.event(receivedAt: now)
        #expect(event == nil)
    }
}

@Suite("Claude session files")
struct ClaudeSessionFileTests {
    @Test func parsesTheRealShape() throws {
        let found = try #require(ClaudeSessionFile.parse(fixture("claude-sessions/53992.json")))
        #expect(found.pid == 53992)
        #expect(found.sessionId == "00000000-0000-4000-8000-000000000003")
        #expect(found.cwd == "/Users/me/dev/api-server")
        #expect(found.name == "Example session")
        #expect(found.status == "busy")
        #expect(found.entrypoint == "claude-desktop")
        #expect(found.startedAt == Date(timeIntervalSince1970: 1_795_339_800.123))
        #expect(found.statusUpdatedAt == Date(timeIntervalSince1970: 1_795_341_400.456))
    }

    @Test func missingPidOrSessionIdIsRejected() {
        #expect(ClaudeSessionFile.parse(Data(#"{"pid":1}"#.utf8)) == nil)
        #expect(ClaudeSessionFile.parse(Data(#"{"sessionId":"x"}"#.utf8)) == nil)
        #expect(ClaudeSessionFile.parse(Data("{".utf8)) == nil)
    }
}

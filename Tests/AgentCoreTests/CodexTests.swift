import Foundation
import Testing
@testable import AgentCore

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private let sid = "019a7c1e-2222-7b5b-9c3d-000000000001"

private func codexKind(_ name: String) throws -> AgentEvent.Kind? {
    try CodexAdapter.event(from: fixture("codex/\(name).json"), receivedAt: now)?.kind
}

@Suite("Codex adapter")
struct CodexAdapterTests {
    @Test func commonFieldsAreMapped() throws {
        let event = try #require(CodexAdapter.event(from: fixture("codex/SessionStart.json"), receivedAt: now))
        #expect(event.sessionId == sid)
        #expect(event.agent == .codex)
        #expect(event.cwd == "/Users/me/api-server")
        #expect(event.date == now)
        #expect(event.kind == .sessionStarted)
    }

    @Test func lifecycleEvents() throws {
        #expect(try codexKind("SessionEnd") == .sessionEnded)
        #expect(try codexKind("UserPromptSubmit") == .promptSubmitted)
        #expect(try codexKind("Stop") == .stopped(lastMessage: "All tests pass."))
        #expect(try codexKind("Interrupt") == .interrupted)
        #expect(try codexKind("SubagentStart") == .subagent(started: true, type: "explorer"))
        #expect(try codexKind("SubagentStop") == .subagent(started: false, type: "explorer"))
    }

    @Test func diagnosticEventsAreIgnored() throws {
        #expect(try codexKind("PostModelRequest") == nil)
    }

    @Test func shellToolUsesTheDescriptionWhenThereIsOne() throws {
        let plain = ToolActivity(name: "Bash", summary: "npm test", detail: "npm test")
        #expect(try codexKind("PreToolUse-Bash") == .toolStarted(plain, subagent: false))
        #expect(try codexKind("PostToolUse-Bash") == .toolFinished(plain, subagent: false))
        let described = ToolActivity(name: "Bash", summary: "Run the test suite", detail: "npm test")
        #expect(try codexKind("PermissionRequest-Bash") == .permissionRequested(described))
    }

    @Test func approvalResolvesWhenTheSameCommandFinishes() throws {
        // PermissionRequest carries a description that PostToolUse lacks; matching must still work.
        let events = try ["UserPromptSubmit", "PreToolUse-Bash", "PermissionRequest-Bash", "PostToolUse-Bash"]
            .enumerated()
            .compactMap { i, name in
                try CodexAdapter.event(from: fixture("codex/\(name).json"), receivedAt: now.addingTimeInterval(Double(i)))
            }
        let afterRequest = events.prefix(3).map(StoreEvent.agent).reduce(SessionsState(), reduce)
        #expect(afterRequest.sessions[sid]?.state == .needsApproval)
        let afterRun = events.map(StoreEvent.agent).reduce(SessionsState(), reduce)
        #expect(afterRun.sessions[sid]?.state == .working)
    }

    @Test func applyPatchNamesTheFiles() throws {
        guard case .toolStarted(let tool, false)? = try codexKind("PreToolUse-apply_patch") else {
            Issue.record("expected toolStarted")
            return
        }
        #expect(tool.name == "apply_patch")
        #expect(tool.summary == "Editing Header.tsx and 1 more")
        #expect(tool.detail == "Update File: src/Header.tsx\nAdd File: src/Footer.tsx")
    }

    @Test func mcpToolShowsToolAndServer() throws {
        guard case .toolStarted(let tool, _)? = try codexKind("PreToolUse-mcp") else {
            Issue.record("expected toolStarted")
            return
        }
        #expect(tool.summary == "Using create_issue (github)")
    }

    @Test func commandArraysAreJoined() {
        let json = #"{"session_id":"x","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":["bash","-lc","ls -la"]}}"#
        guard case .toolStarted(let tool, _)? = CodexAdapter.event(from: Data(json.utf8), receivedAt: now)?.kind else {
            Issue.record("expected toolStarted")
            return
        }
        #expect(tool.detail == "bash -lc 'ls -la'")
    }

    @Test func brokenInputIsDropped() {
        #expect(CodexAdapter.event(from: Data("nope".utf8), receivedAt: now) == nil)
        #expect(CodexAdapter.event(from: Data(#"{"hook_event_name":"Stop"}"#.utf8), receivedAt: now) == nil)
    }
}

@Suite("Wire header with parent pid")
struct WireHeaderTests {
    @Test func headerCarriesTheHookParentPid() {
        let msg = HookMessage.parse(Data("perch1 codex ppid=4242\n{}".utf8))
        #expect(msg?.agent == "codex")
        #expect(msg?.parentPid == 4242)
        #expect(msg?.payload == Data("{}".utf8))
    }

    @Test func oldHeaderWithoutPidStillParses() {
        let msg = HookMessage.parse(Data("perch1 claude-code\n{}".utf8))
        #expect(msg?.agent == "claude-code")
        #expect(msg?.parentPid == nil)
    }

    @Test func codexMessagesRouteToTheCodexAdapter() throws {
        var data = Data("perch1 codex ppid=1\n".utf8)
        data.append(try fixture("codex/Stop.json"))
        #expect(HookMessage.parse(data)?.event(receivedAt: now)?.agent == .codex)
    }
}

@Suite("Codex sessions in the reducer")
struct CodexReducerTests {
    private func ev(_ kind: AgentEvent.Kind, _ s: TimeInterval, id: String = "c1", pid: Int32? = nil) -> StoreEvent {
        .agent(AgentEvent(sessionId: id, date: now.addingTimeInterval(s), agent: .codex, cwd: "/Users/me/web", pid: pid, kind: kind))
    }

    @Test func interruptMeansIdle() {
        let bash = ToolActivity(name: "Bash", summary: "npm test", detail: "npm test")
        let s = [ev(.promptSubmitted, 0), ev(.permissionRequested(bash), 1), ev(.interrupted, 2)].reduce(SessionsState(), reduce)
        #expect(s.sessions["c1"]?.state == .idle)
        #expect(s.sessions["c1"]?.pendingTool == nil)
    }

    @Test func hookPidIsRecordedSoTheSessionIsCleanedUpWhenCodexExits() {
        var s = [ev(.promptSubmitted, 0, pid: 700)].reduce(SessionsState(), reduce)
        #expect(s.sessions["c1"]?.pid == 700)
        #expect(s.sessions["c1"]?.agent == .codex)
        s = reduce(s, .processExited(pid: 700))
        #expect(s.sessions.isEmpty)
    }

    @Test func aRunningCodexCliWithoutEventsShowsAsAnIdlePlaceholder() {
        let proc = DiscoveredProcess(agent: .codex, pid: 900, cwd: "/Users/me/web", startedAt: now)
        let s = reduce(SessionsState(), .discoveredProcess(proc, at: now))
        let placeholder = s.sessions[DiscoveredProcess.placeholderId(pid: 900)]
        #expect(placeholder?.state == .idle)
        #expect(placeholder?.agent == .codex)
        #expect(placeholder?.displayName == "web")
        #expect(placeholder?.pid == 900)
    }

    @Test func theFirstHookEventFromThatProcessReplacesThePlaceholder() {
        let proc = DiscoveredProcess(agent: .codex, pid: 900, cwd: "/Users/me/web", startedAt: now)
        var s = reduce(SessionsState(), .discoveredProcess(proc, at: now))
        s = reduce(s, ev(.promptSubmitted, 5, pid: 900))
        #expect(Set(s.sessions.keys) == ["c1"])
        // Seeing the process again does not bring the placeholder back.
        s = reduce(s, .discoveredProcess(proc, at: now.addingTimeInterval(9)))
        #expect(Set(s.sessions.keys) == ["c1"])
    }

    @Test func placeholdersGoWhenTheProcessExits() {
        let proc = DiscoveredProcess(agent: .codex, pid: 900, cwd: nil, startedAt: now)
        var s = reduce(SessionsState(), .discoveredProcess(proc, at: now))
        s = reduce(s, .processExited(pid: 900))
        #expect(s.sessions.isEmpty)
    }

    @Test func codexAndClaudeSessionsSitSideBySide() {
        let claude = AgentEvent(sessionId: "cc", date: now, agent: .claudeCode, cwd: "/p/a", kind: .promptSubmitted)
        let s = [.agent(claude), ev(.promptSubmitted, 0)].reduce(SessionsState(), reduce)
        #expect(Set(s.sessions.values.map(\.agent)) == [.claudeCode, .codex])
    }
}

@Suite("Codex processes")
struct CodexProcessTests {
    @Test func interactiveCodexIsRecognisedByItsArguments() {
        #expect(CodexProcesses.isInteractive(arguments: ["codex"]))
        #expect(CodexProcesses.isInteractive(arguments: ["/x/codex", "-a", "untrusted", "fix the bug"]))
        #expect(CodexProcesses.isInteractive(arguments: ["codex", "resume", "--last"]))
        #expect(!CodexProcesses.isInteractive(arguments: ["codex", "app-server", "--listen", "stdio://"]))
        #expect(!CodexProcesses.isInteractive(arguments: ["codex", "sandbox", "-c", "x=1"]))
        #expect(!CodexProcesses.isInteractive(arguments: ["codex", "exec", "do it"]))
        #expect(!CodexProcesses.isInteractive(arguments: ["codex", "mcp-server"]))
        #expect(!CodexProcesses.isInteractive(arguments: ["codex", "-c", "a=b", "app-server"]))
    }

    @Test func theHookParentChainLeadsToTheCodexProcess() {
        // hook script (300) <- sh (200) <- codex (100) <- zsh (50)
        let parents: [Int32: Int32] = [300: 200, 200: 100, 100: 50, 50: 1]
        let names: [Int32: String] = [300: "sh", 200: "sh", 100: "codex", 50: "zsh"]
        let probe = ProcessProbe(startTime: { _ in now }, parent: { parents[$0] }, name: { names[$0] })
        #expect(probe.ancestor(of: 300, named: "codex") == 100)
        #expect(probe.ancestor(of: 100, named: "codex") == 100)
        #expect(probe.ancestor(of: 50, named: "codex") == nil)
    }

    @Test func theRealProbeKnowsThisProcessName() {
        let name = ProcessProbe.system.name(of: getpid())
        #expect(name != nil && !(name ?? "").isEmpty)
        #expect(ProcessProbe.system.arguments(of: getpid())?.isEmpty == false)
    }
}

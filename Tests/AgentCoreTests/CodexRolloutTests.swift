import Foundation
import Testing
@testable import AgentCore

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private let failedTurn = "01a00000-0000-7000-8000-000000000001"

private func rollout(_ name: String) throws -> String {
    String(decoding: try fixture("codex-rollout/\(name).jsonl"), as: UTF8.self)
}

/// Codex 0.163 fires no hook when a turn fails; its rollout file records `task_complete` with an error.
@Suite("Codex rollout")
struct CodexRolloutTests {
    @Test func aFailedTurnReportsTheApiErrorMessage() throws {
        let end = CodexRollout.turnEnd(in: try rollout("failed-turn"), turnId: failedTurn)
        #expect(end == .failed(message: "The 'gpt-6.2-sol' model is not supported when using Codex with a ChatGPT account."))
    }

    @Test func aCompletedTurnReportsItsLastMessage() throws {
        #expect(CodexRollout.turnEnd(in: try rollout("completed-turn"), turnId: "turn_a") == .completed(lastMessage: "Done."))
    }

    @Test func aTurnStillRunningHasNoEnd() throws {
        #expect(CodexRollout.turnEnd(in: try rollout("running-turn"), turnId: "turn_b") == nil)
    }

    @Test func theEndOfAnotherTurnDoesNotCount() throws {
        #expect(CodexRollout.turnEnd(in: try rollout("completed-turn"), turnId: "turn_z") == nil)
    }

    @Test func plainTextErrorsAndBrokenLinesAreHandled() {
        let text = """
        not json
        {"type":"event_msg","payload":{"type":"task_complete","turn_id":"t","error":{"message":"stream disconnected"}}}
        {"truncated
        """
        #expect(CodexRollout.turnEnd(in: text, turnId: "t") == .failed(message: "stream disconnected"))
    }

    @Test func codexHookEventsCarryTheTurnAndTranscript() throws {
        let event = try #require(CodexAdapter.event(from: fixture("codex/UserPromptSubmit.json"), receivedAt: now))
        #expect(event.turnId == "turn_1")
        #expect(event.transcriptPath?.hasSuffix("rollout-2026-11-22T20-00-00-019a7c1e-2222-7b5b-9c3d-000000000001.jsonl") == true)
        let s = reduce(SessionsState(), .agent(event))
        #expect(s.sessions[event.sessionId]?.turnId == "turn_1")
        #expect(s.sessions[event.sessionId]?.transcriptPath == event.transcriptPath)
    }

    // MARK: Stuck-session check

    private func workingCodex(lastEvent: TimeInterval) -> Session {
        var s = Session(id: "c1", agent: .codex, state: .working, stateSince: now.addingTimeInterval(lastEvent),
                        lastEventAt: now.addingTimeInterval(lastEvent), cwd: "/p/x", hasHookEvents: true)
        s.turnId = failedTurn
        s.transcriptPath = "/rollout.jsonl"
        return s
    }

    @Test func aQuietWorkingCodexSessionWhoseTurnFailedBecomesAnError() throws {
        let text = try rollout("failed-turn")
        let event = CodexRollout.endOfQuietTurn(workingCodex(lastEvent: -30), now: now) { _ in text }
        guard case .agent(let e)? = event, case .failed(let message) = e.kind else {
            Issue.record("expected a failed event, got \(String(describing: event))")
            return
        }
        #expect(message.contains("not supported"))
        #expect(e.sessionId == "c1")
        #expect(e.agent == .codex)
        #expect(e.date == now)
    }

    @Test func recentlyActiveSessionsAreNotChecked() throws {
        let text = try rollout("failed-turn")
        var read = false
        let event = CodexRollout.endOfQuietTurn(workingCodex(lastEvent: -2), now: now) { _ in read = true; return text }
        #expect(event == nil)
        #expect(!read)
    }

    @Test func onlyWorkingCodexSessionsAreChecked() throws {
        let text = try rollout("failed-turn")
        var claude = workingCodex(lastEvent: -30)
        claude.agent = .claudeCode
        #expect(CodexRollout.endOfQuietTurn(claude, now: now) { _ in text } == nil)
        var asking = workingCodex(lastEvent: -30)
        asking.state = .needsApproval
        #expect(CodexRollout.endOfQuietTurn(asking, now: now) { _ in text } == nil)
    }

    @Test func aMissingRolloutChangesNothing() {
        #expect(CodexRollout.endOfQuietTurn(workingCodex(lastEvent: -30), now: now) { _ in nil } == nil)
    }
}

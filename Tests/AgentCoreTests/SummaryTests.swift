import Foundation
import Testing
@testable import AgentCore

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private func ago(_ s: TimeInterval) -> Date { now.addingTimeInterval(-s) }
private func session(_ id: String, _ state: SessionState, since: TimeInterval, name: String? = nil) -> Session {
    Session(id: id, state: state, stateSince: ago(since), cwd: "/p/\(id)", name: name)
}

@Suite("Notch summary")
struct SummaryTests {
    @Test func emptyWhenThereAreNoSessions() {
        let s = NotchSummary(sessions: [], now: now)
        #expect(s.isEmpty)
        #expect(s.needsYouCount == 0)
        #expect(s.longestWait == nil)
        #expect(!s.showsWings)
    }

    @Test func workingAndIdleSessionsDrawNothing() {
        let s = NotchSummary(sessions: [session("a", .working, since: 5), session("b", .idle, since: 50)], now: now)
        #expect(!s.showsWings)
        #expect(!s.isEmpty)
    }

    @Test func doneSessionsAloneDoNotShowWings() {
        let s = NotchSummary(sessions: [session("a", .doneUnseen, since: 5)], now: now)
        #expect(!s.showsWings)
    }

    @Test func wingsCountSessionsThatNeedYouAndShowTheLongestWait() {
        let s = NotchSummary(sessions: [
            session("a", .needsApproval, since: 120),
            session("b", .waitingForReply, since: 300),
            session("c", .working, since: 999),
            session("d", .error, since: 30),
        ], now: now)
        #expect(s.showsWings)
        #expect(s.needsYouCount == 3)
        #expect(s.longestWait == 300)
    }

    @Test func sectionsAreGroupedAndOrdered() {
        let s = NotchSummary(sessions: [
            session("w2", .working, since: 10, name: "beta"),
            session("n1", .needsApproval, since: 60),
            session("d1", .idle, since: 5),
            session("w1", .working, since: 20, name: "alpha"),
            session("n2", .waitingForReply, since: 600),
            session("d2", .doneUnseen, since: 100),
            session("d3", .doneUnseen, since: 10),
        ], now: now)
        #expect(s.needsYou.map(\.id) == ["n2", "n1"])  // longest wait first
        #expect(s.working.map(\.id) == ["w1", "w2"])  // by name
        #expect(s.done.map(\.id) == ["d3", "d2", "d1"])  // unseen first, newest first
    }
}

@Suite("Formatting")
struct FormattingTests {
    @Test func elapsed() {
        #expect(formatElapsed(0) == "now")
        #expect(formatElapsed(4.9) == "now")
        #expect(formatElapsed(42) == "42s")
        #expect(formatElapsed(60) == "1m")
        #expect(formatElapsed(3599) == "59m")
        #expect(formatElapsed(3600) == "1h")
        #expect(formatElapsed(86_399) == "23h")
        #expect(formatElapsed(86_400 * 3) == "3d")
        #expect(formatElapsed(-10) == "now")
    }

    @Test func spokenElapsed() {
        #expect(formatElapsedSpoken(42) == "42 seconds")
        #expect(formatElapsedSpoken(60) == "1 minute")
        #expect(formatElapsedSpoken(7200) == "2 hours")
    }

    @Test func rowDetailDescribesWhatTheSessionIsDoing() {
        var s = Session(id: "x", state: .working, stateSince: now, activity: "Editing Header.tsx")
        #expect(s.rowDetail == "Editing Header.tsx")
        s.activity = nil
        #expect(s.rowDetail == "Working")
        s.state = .idle
        #expect(s.rowDetail == "Idle")
        s.state = .doneUnseen
        s.message = "All tests pass.\nDetails follow."
        #expect(s.rowDetail == "All tests pass.")
        s.message = nil
        #expect(s.rowDetail == "Done")
        s.state = .error
        s.message = "Rate limit"
        #expect(s.rowDetail == "Rate limit")
        s.state = .waitingForReply
        s.message = nil
        #expect(s.rowDetail == "Waiting for your reply")
    }

    @Test func placeholderRowsSayThereIsNoLiveStatusYet() {
        let proc = DiscoveredProcess(agent: .codex, pid: 5, cwd: "/p/web", startedAt: now)
        let s = reduce(SessionsState(), .discoveredProcess(proc, at: now))
        #expect(s.sessions.values.first?.rowDetail == "Running · no live status yet")
    }

    @Test func approvalRequestTitleNamesTheKindOfTool() {
        var s = Session(id: "x", state: .needsApproval, stateSince: now)
        s.pendingTool = ToolActivity(name: "Bash", summary: "Run", detail: "npm test")
        #expect(s.requestTitle == "Wants permission to run a command")
        #expect(s.requestDetail == "npm test")
        s.pendingTool = ToolActivity(name: "Edit", summary: "Editing a.swift", detail: "/p/a.swift")
        #expect(s.requestTitle == "Wants permission to edit a file")
        s.pendingTool = ToolActivity(name: "mcp__github__create_issue", summary: "Using create_issue (github)", detail: nil)
        #expect(s.requestTitle == "Wants permission: Using create_issue (github)")
        s.pendingTool = nil
        s.message = "Claude needs your permission to use Bash"
        #expect(s.requestTitle == "Claude needs your permission to use Bash")
        #expect(s.requestDetail == nil)
    }
}

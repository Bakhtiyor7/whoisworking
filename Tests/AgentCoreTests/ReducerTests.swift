import Foundation
import Testing
@testable import AgentCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

private let bash = ToolActivity(name: "Bash", summary: "Run tests", detail: "npm test")
private let read = ToolActivity(name: "Read", summary: "Reading App.swift", detail: "/p/App.swift")

private func ev(_ kind: AgentEvent.Kind, _ s: TimeInterval, id: String = "s1", cwd: String? = "/Users/me/api-server")
    -> StoreEvent
{
    .agent(AgentEvent(sessionId: id, date: at(s), cwd: cwd, kind: kind))
}

/// Applies events in order from an empty state.
private func run(_ events: [StoreEvent], from start: SessionsState = SessionsState()) -> SessionsState {
    events.reduce(start, reduce)
}

@Suite("Reducer")
struct ReducerTests {
    @Test func sessionStartCreatesIdleSession() {
        let s = run([ev(.sessionStarted, 0)])
        let session = s.sessions["s1"]
        #expect(session?.state == .idle)
        #expect(session?.cwd == "/Users/me/api-server")
        #expect(session?.displayName == "api-server")
        #expect(session?.hasHookEvents == true)
    }

    @Test func promptSubmittedMeansWorking() {
        let s = run([ev(.sessionStarted, 0), ev(.promptSubmitted, 1)])
        #expect(s.sessions["s1"]?.state == .working)
        #expect(s.sessions["s1"]?.stateSince == at(1))
    }

    @Test func toolUseKeepsWorkingAndUpdatesActivityWithoutResettingTheClock() {
        let s = run([
            ev(.promptSubmitted, 0),
            ev(.toolStarted(bash, subagent: false), 5),
            ev(.toolFinished(bash, subagent: false), 9),
            ev(.toolStarted(read, subagent: false), 10),
        ])
        #expect(s.sessions["s1"]?.state == .working)
        #expect(s.sessions["s1"]?.activity == "Reading App.swift")
        #expect(s.sessions["s1"]?.stateSince == at(0))
    }

    @Test func permissionRequestMeansNeedsApproval() {
        let s = run([
            ev(.promptSubmitted, 0),
            ev(.toolStarted(bash, subagent: false), 1),
            ev(.permissionRequested(bash), 2),
        ])
        #expect(s.sessions["s1"]?.state == .needsApproval)
        #expect(s.sessions["s1"]?.pendingTool == bash)
        #expect(s.sessions["s1"]?.stateSince == at(2))
    }

    @Test func approvedToolFinishingMeansWorkingAgain() {
        let s = run([
            ev(.promptSubmitted, 0),
            ev(.permissionRequested(bash), 2),
            ev(.toolFinished(bash, subagent: false), 30),
        ])
        #expect(s.sessions["s1"]?.state == .working)
        #expect(s.sessions["s1"]?.pendingTool == nil)
        #expect(s.sessions["s1"]?.stateSince == at(30))
    }

    @Test func aParallelToolFinishingDoesNotClearAPendingApproval() {
        let s = run([
            ev(.promptSubmitted, 0),
            ev(.toolStarted(read, subagent: false), 1),
            ev(.toolStarted(bash, subagent: false), 1),
            ev(.permissionRequested(bash), 2),
            ev(.toolFinished(read, subagent: false), 3),
        ])
        #expect(s.sessions["s1"]?.state == .needsApproval)
        #expect(s.sessions["s1"]?.stateSince == at(2))
    }

    @Test func permissionNotificationAfterRequestKeepsTheOriginalWaitTime() {
        let s = run([
            ev(.permissionRequested(bash), 2),
            ev(.permissionNotice(message: "Claude needs your permission to use Bash"), 8),
        ])
        #expect(s.sessions["s1"]?.state == .needsApproval)
        #expect(s.sessions["s1"]?.stateSince == at(2))
        #expect(s.sessions["s1"]?.pendingTool == bash)
    }

    @Test func permissionNotificationAloneMeansNeedsApproval() {
        let s = run([ev(.promptSubmitted, 0), ev(.permissionNotice(message: "Claude needs your permission"), 8)])
        #expect(s.sessions["s1"]?.state == .needsApproval)
        #expect(s.sessions["s1"]?.message == "Claude needs your permission")
    }

    @Test func autoModeDenialMeansWorkingAgain() {
        let s = run([ev(.permissionRequested(bash), 2), ev(.permissionDenied, 3)])
        #expect(s.sessions["s1"]?.state == .working)
    }

    @Test func idleNotificationAfterStopMeansWaitingForReply() {
        let s = run([
            ev(.promptSubmitted, 0),
            ev(.stopped(lastMessage: "Which option?"), 10),
            ev(.waitingForReply(message: "Claude is waiting for your input", onlyIfActive: true), 70),
        ])
        #expect(s.sessions["s1"]?.state == .waitingForReply)
    }

    @Test func idleNotificationIsIgnoredOnceTheUserHasSeenTheSession() {
        let s = run([
            ev(.promptSubmitted, 0),
            ev(.stopped(lastMessage: nil), 10),
            .viewed(ids: ["s1"], at: at(20)),
            ev(.waitingForReply(message: "Claude is waiting for your input", onlyIfActive: true), 70),
        ])
        #expect(s.sessions["s1"]?.state == .idle)
    }

    @Test func questionDialogMeansWaitingForReplyEvenWhenIdle() {
        let s = run([
            ev(.sessionStarted, 0),
            ev(.waitingForReply(message: "Pick one", onlyIfActive: false), 5),
        ])
        #expect(s.sessions["s1"]?.state == .waitingForReply)
        #expect(s.sessions["s1"]?.message == "Pick one")
    }

    @Test func answeringAQuestionMeansWorkingAgain() {
        let s = run([
            ev(.promptSubmitted, 0),
            ev(.waitingForReply(message: "Pick one", onlyIfActive: false), 5),
            ev(.resumed, 9),
        ])
        #expect(s.sessions["s1"]?.state == .working)
    }

    @Test func stopMeansDoneUnseen() {
        let s = run([ev(.promptSubmitted, 0), ev(.stopped(lastMessage: "All tests pass."), 10)])
        #expect(s.sessions["s1"]?.state == .doneUnseen)
        #expect(s.sessions["s1"]?.message == "All tests pass.")
        #expect(s.sessions["s1"]?.activity == nil)
    }

    @Test func stopFailureMeansError() {
        let s = run([ev(.promptSubmitted, 0), ev(.failed(error: "rate_limit"), 10)])
        #expect(s.sessions["s1"]?.state == .error)
        #expect(s.sessions["s1"]?.message == "rate_limit")
    }

    @Test func viewingADoneSessionMakesItIdle() {
        let s = run([ev(.promptSubmitted, 0), ev(.stopped(lastMessage: nil), 10), .viewed(ids: ["s1"], at: at(20))])
        #expect(s.sessions["s1"]?.state == .idle)
    }

    @Test func viewingDoesNotClearSessionsThatNeedTheUser() {
        let s = run([ev(.permissionRequested(bash), 0), .viewed(ids: ["s1"], at: at(20))])
        #expect(s.sessions["s1"]?.state == .needsApproval)
    }

    @Test func sessionEndRemovesTheSession() {
        let s = run([ev(.promptSubmitted, 0), ev(.sessionEnded, 10)])
        #expect(s.sessions["s1"] == nil)
    }

    @Test func lateEventsAfterSessionEndDoNotBringItBack() {
        let s = run([ev(.promptSubmitted, 0), ev(.sessionEnded, 10), ev(.stopped(lastMessage: nil), 11)])
        #expect(s.sessions.isEmpty)
    }

    @Test func resumingAnEndedSessionBringsItBack() {
        let s = run([ev(.promptSubmitted, 0), ev(.sessionEnded, 10), ev(.sessionStarted, 20)])
        #expect(s.sessions["s1"]?.state == .idle)
    }

    @Test func pidDeathRemovesTheSession() {
        let found = DiscoveredSession(sessionId: "s1", pid: 4242, cwd: "/Users/me/api-server", status: "busy")
        let s = run([
            .discovered(found, at: at(0)),
            ev(.promptSubmitted, 1),
            .processExited(pid: 4242),
            ev(.toolStarted(bash, subagent: false), 2),
        ])
        #expect(s.sessions.isEmpty)
    }

    @Test func pidDeathLeavesOtherSessionsAlone() {
        let a = DiscoveredSession(sessionId: "a", pid: 1, status: "busy")
        let b = DiscoveredSession(sessionId: "b", pid: 2, status: "busy")
        let s = run([.discovered(a, at: at(0)), .discovered(b, at: at(0)), .processExited(pid: 1)])
        #expect(Set(s.sessions.keys) == ["b"])
    }

    @Test func subagentEventsDoNotCreateTopLevelSessions() {
        let s = run([
            ev(.subagent(started: true, type: "Explore"), 0, id: "unknown"),
            ev(.toolStarted(read, subagent: true), 1, id: "unknown"),
            ev(.toolFinished(read, subagent: true), 2, id: "unknown"),
            ev(.subagent(started: false, type: "Explore"), 3, id: "unknown"),
        ])
        #expect(s.sessions.isEmpty)
    }

    @Test func subagentToolsDoNotWakeAFinishedParent() {
        let s = run([
            ev(.promptSubmitted, 0),
            ev(.stopped(lastMessage: nil), 10),
            ev(.toolStarted(read, subagent: true), 11),
            ev(.subagent(started: false, type: "Explore"), 12),
        ])
        #expect(s.sessions["s1"]?.state == .doneUnseen)
    }

    @Test func subagentPermissionRequestStillNeedsTheUser() {
        let s = run([ev(.promptSubmitted, 0), ev(.permissionRequested(bash), 3)])
        #expect(s.sessions["s1"]?.state == .needsApproval)
    }

    @Test func duplicateEventsAreHarmless() {
        let once = run([ev(.promptSubmitted, 0), ev(.permissionRequested(bash), 2)])
        let twice = run([
            ev(.promptSubmitted, 0), ev(.promptSubmitted, 0),
            ev(.permissionRequested(bash), 2), ev(.permissionRequested(bash), 2),
        ])
        #expect(once == twice)
    }

    @Test func olderEventsArrivingLateDoNotChangeState() {
        let s = run([ev(.promptSubmitted, 0), ev(.stopped(lastMessage: nil), 10), ev(.toolStarted(read, subagent: false), 5)])
        #expect(s.sessions["s1"]?.state == .doneUnseen)
    }

    @Test func eventsForUnknownSessionsCreateThemSoMidRunLaunchesWork() {
        let s = run([ev(.toolStarted(bash, subagent: false), 5)])
        #expect(s.sessions["s1"]?.state == .working)
        #expect(s.sessions["s1"]?.activity == "Run tests")
    }

    @Test func sessionEndForUnknownSessionIsHarmless() {
        let s = run([ev(.sessionEnded, 5)])
        #expect(s.sessions.isEmpty)
    }

    // MARK: Discovery

    @Test func discoveredSessionAppearsWithItsFileStatus() {
        let found = DiscoveredSession(
            sessionId: "s1", pid: 99, cwd: "/Users/me/web", name: "Fix header", status: "busy",
            entrypoint: "claude-desktop", startedAt: at(-60))
        let s = run([.discovered(found, at: at(0))])
        let session = s.sessions["s1"]
        #expect(session?.state == .working)
        #expect(session?.pid == 99)
        #expect(session?.displayName == "Fix header")
        #expect(session?.entrypoint == "claude-desktop")
        #expect(session?.hasHookEvents == false)
    }

    @Test func discoveredIdleSessionIsIdle() {
        let found = DiscoveredSession(sessionId: "s1", pid: 99, status: "idle")
        #expect(run([.discovered(found, at: at(0))]).sessions["s1"]?.state == .idle)
    }

    @Test func discoveryFillsMetadataButDoesNotOverrideHookState() {
        let found = DiscoveredSession(sessionId: "s1", pid: 99, name: "Named", status: "idle")
        let s = run([ev(.permissionRequested(bash), 0), .discovered(found, at: at(5))])
        #expect(s.sessions["s1"]?.state == .needsApproval)
        #expect(s.sessions["s1"]?.pid == 99)
        #expect(s.sessions["s1"]?.name == "Named")
    }

    @Test func fileStatusDrivesStateUntilHooksArrive() {
        let busy = DiscoveredSession(sessionId: "s1", pid: 99, status: "busy")
        var idle = busy
        idle.status = "idle"
        let s = run([.discovered(busy, at: at(0)), .discovered(idle, at: at(5))])
        #expect(s.sessions["s1"]?.state == .doneUnseen)
    }

    @Test func discoveryDoesNotReviveEndedSessions() {
        let found = DiscoveredSession(sessionId: "s1", pid: 99, status: "busy")
        let s = run([ev(.promptSubmitted, 0), ev(.sessionEnded, 1), .discovered(found, at: at(2))])
        #expect(s.sessions.isEmpty)
    }
}

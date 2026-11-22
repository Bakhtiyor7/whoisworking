import Foundation
import Testing
@testable import AgentCore

// Reducer rules added for Cursor, OpenCode and Antigravity: request-keyed approvals (RED-17),
// observed activity (RED-18) and names from hook events (RED-19). Fixed dates, no clock.

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

private func ev(
    _ kind: AgentEvent.Kind, _ s: TimeInterval, id: String = "s1", agent: AgentKind = .openCode,
    turn: String? = nil, name: String? = nil
) -> StoreEvent {
    var event = AgentEvent(sessionId: id, date: at(s), agent: agent, cwd: "/Users/me/demo", kind: kind)
    event.turnId = turn
    event.name = name
    return .agent(event)
}

private func run(_ events: [StoreEvent]) -> SessionsState { events.reduce(SessionsState(), reduce) }

private func ask(_ id: String, _ resource: String) -> ToolActivity {
    ToolActivity(name: "external_directory", summary: "Access \(resource)", detail: resource, requestId: id)
}

@Suite("Agent kinds")
struct AgentKindTests {
    @Test func everyAgentHasANameAndACode() {
        let expected: [(AgentKind, String, String)] = [
            (.claudeCode, "Claude Code", "CC"), (.codex, "Codex", "CX"), (.cursor, "Cursor", "CU"),
            (.openCode, "OpenCode", "OC"), (.antigravity, "Antigravity", "AG"),
        ]
        for (agent, name, code) in expected {
            #expect(agent.displayName == name)
            #expect(agent.shortCode == code)
        }
        #expect(AgentKind.allCases.count == expected.count)
    }

    @Test func fiveAgentsSitSideBySide() {
        var s = SessionsState()
        for (i, agent) in AgentKind.allCases.enumerated() {
            s = reduce(s, ev(.promptSubmitted, Double(i), id: "s-\(agent.rawValue)", agent: agent))
        }
        #expect(s.sessions.count == 5)
        s = reduce(s, ev(.sessionEnded, 10, id: "s-cursor", agent: .cursor))
        #expect(s.sessions.count == 4)
        for agent in AgentKind.allCases where agent != .cursor {
            #expect(s.sessions["s-\(agent.rawValue)"]?.agent == agent)
            #expect(s.sessions["s-\(agent.rawValue)"]?.state == .working)
        }
    }
}

@Suite("Approvals keyed by request id")
struct RequestReplyTests {
    @Test func aReplyClosesOnlyItsOwnRequest() {
        let first = ask("per_1", "/etc/*"), second = ask("per_2", "/var/*")
        var s = run([
            ev(.promptSubmitted, 0),
            ev(.permissionRequested(first), 1),
            ev(.permissionRequested(second), 2),
            ev(.permissionReplied(requestId: "per_2"), 3),
        ])
        #expect(s.sessions["s1"]?.state == .needsApproval)
        #expect(s.sessions["s1"]?.pendingTool == first)
        s = reduce(s, ev(.permissionReplied(requestId: "per_1"), 4))
        #expect(s.sessions["s1"]?.state == .working)
        #expect(s.sessions["s1"]?.pendingTool == nil)
        #expect(s.sessions["s1"]?.openRequests.isEmpty == true)
    }

    @Test func aRepeatedRequestIsOpenOnce() {
        let s = run([
            ev(.promptSubmitted, 0),
            ev(.permissionRequested(ask("per_1", "/etc/*")), 1),
            ev(.permissionRequested(ask("per_1", "/etc/*")), 2),
            ev(.permissionReplied(requestId: "per_1"), 3),
        ])
        #expect(s.sessions["s1"]?.state == .working)
    }

    @Test func aQuestionDoesNotHideOpenApprovals() {
        let s = run([
            ev(.promptSubmitted, 0),
            ev(.permissionRequested(ask("per_1", "/etc/*")), 1),
            ev(.waitingForReply(message: "Which database?"), 2),
        ])
        #expect(s.sessions["s1"]?.state == .needsApproval)
        #expect(s.sessions["s1"]?.openRequests.count == 1)
    }

    @Test func aReplyForAnUnknownRequestChangesNothing() {
        let s = run([
            ev(.promptSubmitted, 0),
            ev(.permissionRequested(ask("per_1", "/etc/*")), 1),
            ev(.permissionReplied(requestId: "per_9"), 2),
        ])
        #expect(s.sessions["s1"]?.state == .needsApproval)
        #expect(s.sessions["s1"]?.stateSince == at(1))
    }

    @Test func aLateReplyAfterTheTurnEndedChangesNothing() {
        let s = run([
            ev(.promptSubmitted, 0),
            ev(.permissionRequested(ask("per_1", "/etc/*")), 1),
            ev(.stopped(lastMessage: nil), 2),
            ev(.permissionReplied(requestId: "per_1"), 3),
        ])
        #expect(s.sessions["s1"]?.state == .doneUnseen)
        #expect(s.sessions["s1"]?.openRequests.isEmpty == true)
    }
}

@Suite("Observed activity")
struct ObservedActivityTests {
    private let edit = ToolActivity(name: "Write", summary: "Editing App.swift", detail: "/p/App.swift")

    @Test func firstActivityOfANewTurnMeansWorking() {
        let s = run([
            ev(.sessionStarted, 0, agent: .cursor),
            ev(.activity(edit), 1, agent: .cursor, turn: "g1"),
            ev(.stopped(lastMessage: nil), 2, agent: .cursor, turn: "g1"),
            ev(.activity(edit), 10, agent: .cursor, turn: "g2"),
        ])
        #expect(s.sessions["s1"]?.state == .working)
        #expect(s.sessions["s1"]?.activity == "Editing App.swift")
        #expect(s.sessions["s1"]?.stateSince == at(10))
    }

    @Test func lateActivityFromTheEndedTurnChangesNothing() {
        let s = run([
            ev(.activity(edit), 1, agent: .cursor, turn: "g1"),
            ev(.stopped(lastMessage: nil), 2, agent: .cursor, turn: "g1"),
            ev(.activity(edit), 3, agent: .cursor, turn: "g1"),
        ])
        #expect(s.sessions["s1"]?.state == .doneUnseen)
        #expect(s.sessions["s1"]?.activity == nil)
    }

    @Test func activityWithoutTurnIdsMeansWorking() {
        let s = run([
            ev(.sessionStarted, 0, agent: .antigravity),
            ev(.stopped(lastMessage: nil), 1, agent: .antigravity),
            ev(.activity(edit), 5, agent: .antigravity),
        ])
        #expect(s.sessions["s1"]?.state == .working)
        #expect(s.sessions["s1"]?.activity == "Editing App.swift")
    }

    @Test func activityInTheTurnTheSessionStartedInIsWork() {
        // Cursor's sessionStart can carry the same generation id as the first tool of the turn.
        let s = run([
            ev(.sessionStarted, 0, agent: .cursor, turn: "g1"),
            ev(.activity(edit), 1, agent: .cursor, turn: "g1"),
        ])
        #expect(s.sessions["s1"]?.state == .working)
    }

    @Test func activityWakesIdleErrorAndWaitingSessions() {
        let ends: [AgentEvent.Kind] = [.interrupted, .failed(error: "boom"), .waitingForReply(message: "Which one?")]
        for end in ends {
            let s = run([ev(.promptSubmitted, 0), ev(end, 1), ev(.activity(nil), 2)])
            #expect(s.sessions["s1"]?.state == .working, "after \(end)")
            #expect(s.sessions["s1"]?.message == nil)
        }
    }

    @Test func activityDuringApprovalOnlyUpdatesTheLine() {
        let s = run([
            ev(.promptSubmitted, 0),
            ev(.permissionRequested(ask("per_1", "/etc/*")), 1),
            ev(.activity(edit), 2),
        ])
        #expect(s.sessions["s1"]?.state == .needsApproval)
        #expect(s.sessions["s1"]?.activity == "Editing App.swift")
        #expect(s.sessions["s1"]?.pendingTool?.requestId == "per_1")
    }
}

@Suite("Names from hook events")
struct SessionNameTests {
    @Test func anEventNameBecomesTheSessionName() {
        let s = run([ev(.sessionStarted, 0, name: "Fix the login bug")])
        #expect(s.sessions["s1"]?.displayName == "Fix the login bug")
    }

    @Test func aRenameChangesOnlyTheName() {
        var s = run([ev(.promptSubmitted, 0)])
        s = reduce(s, ev(.renamed, 5, name: "Pong test"))
        #expect(s.sessions["s1"]?.name == "Pong test")
        #expect(s.sessions["s1"]?.state == .working)
        #expect(s.sessions["s1"]?.stateSince == at(0))
        #expect(s.sessions["s1"]?.lastEventAt == at(0))
        // A rename alone never creates a session.
        let none = run([ev(.renamed, 0, id: "other", name: "Ghost")])
        #expect(none.sessions["other"] == nil)
    }
}

@Suite("Ignored events")
struct IgnoredEventTests {
    @Test func anIgnoredEventDoesNotMoveTheClock() {
        let request = ask("per_1", "/etc/*")
        let edit = ToolActivity(name: "Write", summary: "Editing App.swift")
        // Each ignored event arrives at 5 s; a real stop dated 3 s must still apply afterwards.
        let ignored: [StoreEvent] = [
            ev(.permissionReplied(requestId: "per_9"), 5),
            ev(.activity(edit), 5, turn: "g1"),
            ev(.renamed, 5, name: "Late title"),
        ]
        for event in ignored {
            var s = run([ev(.promptSubmitted, 0, turn: "g1"), ev(.permissionRequested(request), 1, turn: "g1")])
            if case .agent(let e) = event, case .activity = e.kind {
                s = reduce(s, ev(.stopped(lastMessage: nil), 2, turn: "g1"))  // the ended turn
            }
            s = reduce(s, event)
            #expect(s.sessions["s1"]?.lastEventAt != at(5), "\(event)")
            s = reduce(s, ev(.failed(error: "boom"), 3))
            #expect(s.sessions["s1"]?.state == .error, "\(event)")
        }
    }
}

@Suite("Silence rule")
struct SilenceRuleTests {
    @Test func waitingSessionsStayUpToFourHours() {
        let minute: TimeInterval = 60
        let waiting: [AgentEvent.Kind] = [
            .permissionRequested(ask("per_1", "/etc/*")), .waitingForReply(message: "Which database?"),
        ]
        for kind in waiting {
            var s = run([ev(.promptSubmitted, 0), ev(kind, 1)])
            s = reduce(s, .pruneOrphans(now: at(16 * minute)))
            #expect(s.sessions["s1"] != nil, "\(kind) gone after 16 minutes")
            s = reduce(s, .pruneOrphans(now: at(239 * minute)))
            #expect(s.sessions["s1"] != nil, "\(kind) gone before 4 hours")
            s = reduce(s, .pruneOrphans(now: at(241 * minute)))
            #expect(s.sessions["s1"] == nil, "\(kind) still there after 4 hours")
        }
        // Working, done and error sessions keep the 15-minute rule.
        for kind: AgentEvent.Kind in [.promptSubmitted, .stopped(lastMessage: nil), .failed(error: "boom")] {
            let s = reduce(run([ev(kind, 0)]), .pruneOrphans(now: at(16 * minute)))
            #expect(s.sessions["s1"] == nil, "\(kind) kept past 15 minutes")
        }
    }
}

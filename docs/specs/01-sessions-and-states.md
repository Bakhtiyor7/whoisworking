# 01 Sessions and states

Status: implemented
Code: `Sources/AgentCore/Session.swift`, `Sources/AgentCore/Reducer.swift`

## Purpose

One model for every agent session on this Mac, whatever agent it belongs to. The UI reads only this model.

## Terms

- **Session:** one conversation of one agent, identified by the agent's session id. It carries the agent (`claudeCode` shown as CC, `codex` shown as CX), state, the time it entered that state, folder, name, owning pid, current activity line, pending tool and last message.
- **Needs you:** the states `needsApproval`, `waitingForReply` and `error`. Only these make the wings appear.
- **Placeholder:** a running agent process seen before any hook event. Its id is `process:<pid>`.

## Requirements

### SES-01 Six states

A session is in exactly one of: `working`, `needsApproval`, `waitingForReply`, `doneUnseen`, `idle`, `error`.

Tests: `ReducerTests/sessionStartCreatesIdleSession`, `ReducerTests/promptSubmittedMeansWorking`, `ReducerTests/permissionRequestMeansNeedsApproval`, `ReducerTests/questionDialogMeansWaitingForReplyEvenWhenIdle`, `ReducerTests/stopMeansDoneUnseen`, `ReducerTests/stopFailureMeansError`

### SES-02 Session start

Given no session with that id, when a session-start event arrives, then an `idle` session exists.

Tests: `ReducerTests/sessionStartCreatesIdleSession`

### SES-03 Sessions already running are picked up

Given Perch started after the agent, when any top-level event arrives for an unknown session id, then the session is created and the event applied.

Tests: `ReducerTests/eventsForUnknownSessionsCreateThemSoMidRunLaunchesWork`

### SES-04 Seeing a finished session

Given a session in `doneUnseen`, when the user sees it in the expanded panel, then it becomes `idle`. Sessions that need the user are not changed by being seen.

Tests: `ReducerTests/viewingADoneSessionMakesItIdle`, `ReducerTests/viewingDoesNotClearSessionsThatNeedTheUser`

### SES-05 Session end

When a session-end event arrives, the session is removed. An end event for an unknown session changes nothing.

Tests: `ReducerTests/sessionEndRemovesTheSession`, `ReducerTests/sessionEndForUnknownSessionIsHarmless`

### SES-06 Ended sessions stay ended

Given an ended session, when later events or a session file for the same id arrive, then the session is not recreated. Only a new session-start (a resume) brings it back.

Tests: `ReducerTests/lateEventsAfterSessionEndDoNotBringItBack`, `ReducerTests/resumingAnEndedSessionBringsItBack`, `ReducerTests/discoveryDoesNotReviveEndedSessions`

### SES-07 Removal when the process exits

Given sessions with a known pid, when that process exits, then exactly the sessions owned by that pid are removed and remembered as ended.

Tests: `ReducerTests/pidDeathRemovesTheSession`, `ReducerTests/pidDeathLeavesOtherSessionsAlone`

### SES-08 Removal after long silence

Given a session with no known pid, when it has had no event for more than 15 minutes, then it is removed. Sessions with a pid are never removed by silence.

Tests: `ReducerTests/sessionsWithoutAProcessAreDroppedAfterLongSilence`

### SES-09 Agents side by side

Claude Code and Codex sessions live in the same list and do not affect each other.

Tests: `CodexReducerTests/codexAndClaudeSessionsSitSideBySide`

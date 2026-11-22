# 02 Reducer

Status: implemented
Code: `Sources/AgentCore/Reducer.swift` (`reduce`)

## Purpose

`reduce` is the only place session state changes: a pure function `(SessionsState, StoreEvent) -> SessionsState`. It must give the right state for real event streams, which arrive late, twice, out of order and with gaps.

## Requirements

### RED-01 Prompt and tools

When a prompt is submitted the session is `working`. A tool start keeps it `working` and replaces the activity line, without restarting the state clock.

Tests: `ReducerTests/promptSubmittedMeansWorking`, `ReducerTests/toolUseKeepsWorkingAndUpdatesActivityWithoutResettingTheClock`

### RED-02 Permission request

When a permission request arrives the session is `needsApproval` and remembers the tool (name and detail) that is waiting.

Tests: `ReducerTests/permissionRequestMeansNeedsApproval`

### RED-03 Only the same tool resolves an approval

Given a session in `needsApproval`, when a tool finishes, then the session returns to `working` only if the finished tool has the same name and detail as the pending one. A parallel tool finishing changes nothing.

Tests: `ReducerTests/approvedToolFinishingMeansWorkingAgain`, `ReducerTests/aParallelToolFinishingDoesNotClearAPendingApproval`

### RED-04 Permission notice

The agent's own "needs your permission" notification means `needsApproval`. If a permission request already put the session there, the original wait time is kept.

Tests: `ReducerTests/permissionNotificationAloneMeansNeedsApproval`, `ReducerTests/permissionNotificationAfterRequestKeepsTheOriginalWaitTime`

### RED-05 Auto mode denial

When auto mode denies a tool, the agent carries on, so the session is `working`.

Tests: `ReducerTests/autoModeDenialMeansWorkingAgain`

### RED-06 Questions

A question dialog means `waitingForReply`, also when the session was idle. When the user answers, the session is `working`.

Tests: `ReducerTests/questionDialogMeansWaitingForReplyEvenWhenIdle`, `ReducerTests/answeringAQuestionMeansWorkingAgain`

### RED-07 Stop and failure

Stop means `doneUnseen` with the last message. A stop failure means `error` with the error text.

Tests: `ReducerTests/stopMeansDoneUnseen`, `ReducerTests/stopFailureMeansError`

### RED-08 Idle notification

The agent's idle notification moves only a `working` session, to `doneUnseen` (its Stop was missed). It leaves `doneUnseen`, `idle`, `needsApproval` and `waitingForReply` as they are.

Tests: `ReducerTests/idleNotificationWhileWorkingMeansDoneUnseen`, `ReducerTests/idleNotificationAfterStopKeepsTheSessionInDone`, `ReducerTests/idleNotificationAfterTheUserSawTheSessionKeepsItIdle`, `ReducerTests/idleNotificationDoesNotClearAnApprovalOrAQuestion`

### RED-09 Subagents

Subagent start/stop and subagent tool events never create a top-level session and never change its state. While the parent is `working` they may update its activity line. A permission request raised inside a subagent still moves the session to `needsApproval`.

Tests: `ReducerTests/subagentEventsDoNotCreateTopLevelSessions`, `ReducerTests/subagentToolsDoNotWakeAFinishedParent`, `ReducerTests/subagentPermissionRequestStillNeedsTheUser`

### RED-10 Order and duplicates

An event older than the session's newest applied event is ignored. Applying the same event twice gives the same state as applying it once.

Tests: `ReducerTests/olderEventsArrivingLateDoNotChangeState`, `ReducerTests/duplicateEventsAreHarmless`

### RED-11 Session file before hooks

Given a session with no hook events yet, the session file's status drives the state: `busy` is `working`, `waiting` is `needsApproval`, `idle` is `idle`. A file going idle while the session was `working` means `doneUnseen`.

Tests: `ReducerTests/discoveredSessionAppearsWithItsFileStatus`, `ReducerTests/discoveredIdleSessionIsIdle`, `ReducerTests/fileStatusDrivesStateUntilHooksArrive`, `ReducerTests/waitingFileStatusWithoutHooksMeansNeedsApproval`

### RED-12 Hooks win over the session file

Given a session that has had hook events, the file still fills in pid, folder, name and entrypoint, but does not override the hook-derived state.

Tests: `ReducerTests/discoveryFillsMetadataButDoesNotOverrideHookState`

### RED-13 The file fills the gaps hooks leave

Given a session with hook events, when the file's status changed more than 0.5 s after the session entered its state, then:

- file `idle` moves `needsApproval` or `working` to `idle` (a declined permission prompt and an Esc interrupt fire no hook);
- file `busy` moves `needsApproval` to `working` (answered, but the resolving hook did not match).

A file status that is older than the state changes nothing, and file `idle` never touches `doneUnseen` or `waitingForReply`.

Tests: `ReducerTests/fileGoingIdleAfterADeclinedPermissionMakesTheSessionIdle`, `ReducerTests/fileGoingIdleAfterAnInterruptMakesAWorkingSessionIdle`, `ReducerTests/fileGoingBusyAfterAnApprovalMeansWorkingAgain`, `ReducerTests/busyFileStatusFromBeforeTheRequestKeepsNeedsApproval`, `ReducerTests/staleIdleFileStatusDoesNotOverrideNewerHookState`, `ReducerTests/idleFileStatusDoesNotTouchDoneOrWaitingSessions`

### RED-14 Interrupt

When the user interrupts a turn (Codex `Interrupt`), the session is `idle`: the user stopped it, so they have seen it.

Tests: `CodexReducerTests/interruptMeansIdle`

### RED-15 Hook pid ownership

When a hook event carries the owning process id, the session records it, so the session is removed when that process exits.

Tests: `CodexReducerTests/hookPidIsRecordedSoTheSessionIsCleanedUpWhenCodexExits`

### RED-16 Placeholders

A running agent process with no session shows as an `idle` placeholder (`process:<pid>`). It is removed when a real session with the same pid appears, when a live session of the same agent exists in the same folder, or when the process exits. No placeholder is created next to a live session of that agent in the same folder.

Tests: `CodexReducerTests/aRunningCodexCliWithoutEventsShowsAsAnIdlePlaceholder`, `CodexReducerTests/theFirstHookEventFromThatProcessReplacesThePlaceholder`, `CodexReducerTests/noPlaceholderNextToALiveCodexSessionInTheSameFolder`, `CodexReducerTests/aLiveSessionReplacesThePlaceholderForItsFolder`, `CodexReducerTests/placeholdersGoWhenTheProcessExits`

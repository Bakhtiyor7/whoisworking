# 04 Codex

Status: implemented
Code: `Sources/AgentCore/CodexAdapter.swift` (`CodexAdapter`, `CodexProcesses`), `Sources/AgentCore/CodexRollout.swift`

## Purpose

Show Codex sessions with the same states as Claude Code, although Codex has no session files, often runs the conversation in a shared `codex app-server` daemon, and fires no hook when a turn fails.

Verified live with Codex CLI 0.163.0 and 0.171.0. Known gap: Codex has no notification event for questions, so there is no `waitingForReply` for Codex.

## Requirements

### CDX-01 Common fields and lifecycle

Codex events carry session id, folder and time. `SessionStart`, `SessionEnd`, `UserPromptSubmit`, `Stop` and `Interrupt` map to the shared lifecycle events. Diagnostic events are ignored. Broken input is dropped.

Tests: `CodexAdapterTests/commonFieldsAreMapped`, `CodexAdapterTests/lifecycleEvents`, `CodexAdapterTests/diagnosticEventsAreIgnored`, `CodexAdapterTests/brokenInputIsDropped`

### CDX-02 Tool lines

- Shell: the row shows the description when there is one; a command given as an array is joined into one line.
- `apply_patch`: the row names the files.
- MCP tools: the row names the tool and its server.

Tests: `CodexAdapterTests/shellToolUsesTheDescriptionWhenThereIsOne`, `CodexAdapterTests/commandArraysAreJoined`, `CodexAdapterTests/applyPatchNamesTheFiles`, `CodexAdapterTests/mcpToolShowsToolAndServer`

### CDX-03 Approval resolves on the same command

A Codex permission request and the later finish of the same command produce matching tool name and detail, so the approval resolves (see RED-03).

Tests: `CodexAdapterTests/approvalResolvesWhenTheSameCommandFinishes`

### CDX-04 Wire header with parent pid

The header carries the hook's parent pid (`ppid=`). A header without it still parses. Messages with agent `codex` go to the Codex adapter.

Tests: `WireHeaderTests/headerCarriesTheHookParentPid`, `WireHeaderTests/oldHeaderWithoutPidStillParses`, `WireHeaderTests/codexMessagesRouteToTheCodexAdapter`

### CDX-05 Which process owns a session

The owning process is the nearest process named `codex` above the hook's parent: the `codex app-server` daemon when it runs the hooks, the ChatGPT app's app-server for sessions inside the app, and the CLI itself for in-process hooks. The session is removed when that process exits.

Tests: `CodexProcessTests/theHookParentChainLeadsToTheCodexProcess`, `CodexProcessTests/hooksRunByTheAppServerDaemonBelongToTheDaemon`, `CodexProcessTests/hooksInTheChatGPTAppBelongToItsAppServer`, `CodexProcessTests/hooksRunDirectlyByTheCliBelongToIt`

### CDX-06 Codex CLIs started before WhoIsWorking

A running process named `codex` that has a terminal and whose arguments are an interactive invocation (not `exec`, `app-server`, `mcp` and similar subcommands) becomes a placeholder event with its pid, folder and start time (see RED-16).

Tests: `CodexProcessTests/interactiveCodexIsRecognisedByItsArguments`, `CodexProcessTests/runningInteractiveCodexProcessesBecomePlaceholderEvents`

### CDX-07 The system process probe

The real probe lists processes and reports a process's name, folder and whether it has a terminal.

Tests: `CodexProcessTests/theRealProbeKnowsWhetherAProcessHasATerminal`, `CodexProcessTests/theRealProbeListsProcessesAndFindsThisOnesFolder`, `CodexProcessTests/theRealProbeKnowsThisProcessName`

### CDX-08 Hook events carry turn and transcript

Codex hook events carry the turn id and the transcript (rollout) path, and the session keeps them.

Tests: `CodexRolloutTests/codexHookEventsCarryTheTurnAndTranscript`

### CDX-09 Reading how a turn ended

From rollout text and a turn id: a `task_complete` with an error means failed with the readable API error message; a `task_complete` without one means completed with the last agent message; a turn that only started has no end. The end of another turn does not count. Plain-text errors and broken lines are handled without failing.

Tests: `CodexRolloutTests/aFailedTurnReportsTheApiErrorMessage`, `CodexRolloutTests/aCompletedTurnReportsItsLastMessage`, `CodexRolloutTests/aTurnStillRunningHasNoEnd`, `CodexRolloutTests/theEndOfAnotherTurnDoesNotCount`, `CodexRolloutTests/plainTextErrorsAndBrokenLinesAreHandled`

### CDX-10 Quiet working sessions are checked

Given a Codex session that has been `working` with no events for 10 s, when its rollout shows the turn failed, then the session becomes `error` with that message. Sessions with recent events, sessions in other states and non-Codex sessions are not checked. A missing rollout changes nothing.

The rollout format is documented by Codex as unstable: unknown shapes are ignored, never treated as errors.

Tests: `CodexRolloutTests/aQuietWorkingCodexSessionWhoseTurnFailedBecomesAnError`, `CodexRolloutTests/recentlyActiveSessionsAreNotChecked`, `CodexRolloutTests/onlyWorkingCodexSessionsAreChecked`, `CodexRolloutTests/aMissingRolloutChangesNothing`

### CDX-11 The rollout is read safely

The rollout path comes from hook payloads, which any local process can send. Only a regular file is read, and at most its last 256 KB: a pipe, a device such as `/dev/zero`, a directory or a missing path gives nothing, without blocking or reading without end.

Tests: `CodexRolloutTests/theTailOfARegularFileIsRead`, `CodexRolloutTests/specialFilesAreNotRead`

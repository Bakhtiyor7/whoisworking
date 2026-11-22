# 03 Claude Code

Status: implemented
Code: `Sources/AgentCore/ClaudeCodeAdapter.swift` (`ClaudeCodeAdapter`, `HookMessage`), `Sources/AgentCore/Ingest.swift` (`ClaudeSessionFile`, `ClaudeSessionScanner`, `ProcessProbe`)

## Purpose

Turn Claude Code's hook JSON and its session files into the shared events the reducer understands.

## Requirements

### CCA-01 Common fields

Every mapped event carries the session id, the folder and the time it was received.

Tests: `ClaudeCodeAdapterTests/commonFieldsAreMapped`

### CCA-02 Lifecycle events

`SessionStart`, `SessionEnd`, `UserPromptSubmit`, `Stop` and `StopFailure` map to session started, session ended, prompt submitted, stopped (with the last message) and failed (with the error).

Tests: `ClaudeCodeAdapterTests/lifecycleEvents`

### CCA-03 Tool lines

Each tool call becomes one short row line plus an optional full detail for the Needs you card:

- Bash: the row shows the description, the card shows the command. Without a description, a long command is shortened for the row.
- Edit and similar: the row names the file.
- MCP tools: the row names the tool and its server.

Tests: `ClaudeCodeAdapterTests/bashToolUsesDescriptionForTheRowAndCommandForTheCard`, `ClaudeCodeAdapterTests/longBashCommandsWithoutDescriptionAreShortenedForTheRow`, `ClaudeCodeAdapterTests/editToolShowsTheFileName`, `ClaudeCodeAdapterTests/mcpToolShowsToolAndServer`

### CCA-04 Subagents

Tool calls made inside a subagent are marked as such. `SubagentStart` and `SubagentStop` map to subagent events with the subagent type.

Tests: `ClaudeCodeAdapterTests/toolCallsInsideASubagentAreMarked`, `ClaudeCodeAdapterTests/subagentLifecycle`

### CCA-05 Questions are not approvals

A permission request for the `AskUserQuestion` tool is a question (`waitingForReply`), not an approval.

Tests: `ClaudeCodeAdapterTests/askUserQuestionIsAQuestionNotAnApproval`

### CCA-06 Auto mode denial

`PermissionDenied` maps to permission denied.

Tests: `ClaudeCodeAdapterTests/autoModeDenial`

### CCA-07 Notifications

`Notification` maps by type: a permission prompt is a permission notice, an idle prompt is turn idle, an elicitation dialog or "agent needs input" is waiting for reply.

Tests: `ClaudeCodeAdapterTests/notifications`

### CCA-08 Unknown input is dropped

Unknown event names, missing fields and broken JSON produce no event and no error.

Tests: `ClaudeCodeAdapterTests/unknownOrBrokenInputIsDropped`

### CCA-09 Real payloads

Every payload captured from a real Claude Code session maps to an event, and a real captured sequence ends in `needsApproval`.

Tests: `ClaudeCodeRealPayloadTests/mapsEveryCapturedEvent`, `ClaudeCodeRealPayloadTests/realSequenceEndsInNeedsApproval`

### CCA-10 Wire format

One message per socket connection: a header line `whoisworking1 <agent> ppid=<pid>` followed by the agent's raw hook JSON. A bare JSON object with no header is treated as Claude Code. Empty input and garbage are rejected. Messages go to the adapter of the agent named in the header; unknown agents are ignored. One exception: a `claude-code` message whose JSON has `cursor_version` was sent by Cursor running Claude Code hooks, and goes to the Cursor adapter (CUR-03).

Tests: `HookMessageTests/headerNamesTheAgent`, `HookMessageTests/bareJSONIsTreatedAsClaudeCode`, `HookMessageTests/emptyOrGarbageIsRejected`, `HookMessageTests/routesClaudeCodeMessagesToTheAdapter`, `HookMessageTests/unknownAgentsAreIgnored`, `CursorRoutingTests/cursorPayloadsUnderTheClaudeHeaderNeverBecomeClaudeSessions`

### CCA-11 Session files

`~/.claude/sessions/<pid>.json` is parsed for pid, session id, folder, name, status and entrypoint. A file with no pid or no session id is rejected.

Tests: `ClaudeSessionFileTests/parsesTheRealShape`, `ClaudeSessionFileTests/missingPidOrSessionIdIsRejected`

### CCA-12 Discovery scan

The scanner reads every session file in the folder and skips broken ones. A missing folder scans as empty. Live files become discovered sessions; a known pid that has died becomes a process-exited event.

Tests: `DiscoveryTests/scansSessionFilesAndSkipsBrokenOnes`, `DiscoveryTests/missingDirectoryScansAsEmpty`, `DiscoveryTests/liveSessionsAreReportedAndDeadPidsRemoved`

### CCA-13 Reused pids

A pid counts as alive only when a process with that pid exists and it started no later than the session did (5 s tolerance), so a reused pid does not keep a dead session alive.

Tests: `DiscoveryTests/aReusedPidDoesNotCountAsAlive`, `DiscoveryTests/theRealProbeSeesThisProcess`

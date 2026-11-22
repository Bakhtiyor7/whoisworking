# 11 Cursor adapter

Status: draft
Depends on: `02-reducer.md`, `05-ingest-and-hook-script.md`, `06-hook-installer.md`
Code: `Sources/AgentCore/CursorAdapter.swift`, `HookTarget.cursor` in `Sources/AgentCore/HookInstaller.swift`

## Purpose

Show local Cursor agent sessions (the Cursor app and `cursor-agent`) in WhoIsWorking with the [Cursor badge](../../Sources/WhoIsWorking/AgentIcons/cursor.png).

Sources, checked on 2026-11-22: the [Cursor hook reference](https://cursor.com/docs/hooks), and the hook runner inside `cursor-agent` 2026.04.17-787b533 (Cursor app 3.25.9 is installed alongside). The CLI and the app share the hook runner, event names and file. It runs each hook as a shell command with the JSON on stdin, so `$HOME` in the command expands.

The fixtures are CONSTRUCTED from those sources. A live capture is still open (CUR-08), so this spec stays a draft, and Settings and the README call Cursor support experimental until then.

## Requirements

### CUR-01 Adapter

`CursorAdapter` maps Cursor hook JSON to `AgentEvent.Kind`. The session id is `conversation_id`, falling back to `session_id` (equal to it on `sessionStart` and `sessionEnd`). The folder is the first of `workspace_roots`. The turn id is `generation_id`. The mapping:

- `sessionStart` → session started. `sessionEnd` → session ended.
- `postToolUse` and `postToolUseFailure` → observed activity with the tool's line (RED-18). A failed tool stays a line, not an error.
- `afterAgentThought` → observed activity, "Thinking".
- `stop` with `status` `completed` → done. `aborted` → interrupted (idle, the user stopped it). `error` → error, "Cursor stopped with an error". Any other status → done.
- `beforeSubmitPrompt` → prompt submitted, and `preToolUse` → tool started. WhoIsWorking never registers these two (CUR-02), but maps them when another source sends them (CUR-03).

Unknown events, broken JSON and events without a conversation are dropped.

Tests: `CursorAdapterTests/lifecycleMapsToSessionEvents`, `CursorAdapterTests/stopStatusesMapToDoneInterruptedAndError`, `CursorAdapterTests/toolsAndThoughtsAreObservedActivity`, `CursorAdapterTests/commonFieldsGiveIdFolderAndTurn`, `CursorAdapterTests/unknownOrBrokenInputIsDropped`

### CUR-02 Hook target

`HookTarget.cursor` edits `~/.cursor/hooks.json` in Cursor's flat shape (INS-15) with agent id `cursor` and a 5 s timeout. It registers only `sessionStart`, `sessionEnd`, `postToolUse`, `postToolUseFailure`, `afterAgentThought` and `stop`. These never wait on a hook's answer. Never registered: the permission hooks (`preToolUse`, `subagentStart`, `beforeShellExecution`, `beforeMCPExecution`, `beforeReadFile`, `beforeTabFileRead`), where an empty or invalid answer may block the agent, and the `beforeSubmitPrompt` gate.

Tests: `CursorHookInstallerTests/installAppendsOneFlatEntryPerEventAfterOtherTools`, `CursorHookInstallerTests/aNewFileStartsWithVersionOne`, `CursorHookInstallerTests/uninstallRestoresTheOriginalExactly`

### CUR-03 Routing

`HookMessage.event` routes header agent `cursor` to the adapter. `cursor-agent` also runs Claude Code hooks from `~/.claude/settings.json` (its hook sources include `claude-user`), so a Cursor payload can arrive under the `claude-code` header. A `claude-code` message whose JSON has `cursor_version` goes to the Cursor adapter, so it never becomes a Claude Code session.

Tests: `CursorRoutingTests/routesCursorMessagesToTheAdapter`, `CursorRoutingTests/cursorPayloadsUnderTheClaudeHeaderNeverBecomeClaudeSessions`

### CUR-04 Approval status

Cursor sessions never show "needs approval". A missing follow-up event cannot tell a pending approval from a slow, failed or cancelled tool, and the hooks that see approvals are permission hooks (CUR-02).

Tests: `CursorAdapterTests/noCursorEventMeansNeedsApproval`

### CUR-05 Lifetime

Cursor events carry no owning pid, so a session is removed on `sessionEnd`, or after 15 minutes of silence (SES-08), or 4 hours if it is waiting for the user. After the silence rule a later event recreates it. After `sessionEnd` only a new `sessionStart` does (SES-06), so if Cursor fired `sessionEnd` after every turn, later turns would stay hidden until the next `sessionStart`: CUR-08 checks this.

Tests: `CursorAdapterTests/sessionsEndOnSessionEndOrAfterLongSilence`

### CUR-06 Fixtures

Constructed payloads live in `Tests/Fixtures/cursor/`, recorded in `Tests/Fixtures/README.md`. A test maps every one.

Tests: `CursorAdapterTests/mapsEveryFixture`

### CUR-07 Docs

`README.md` has an install section for Cursor, marks the support experimental, and says what is covered and what is not.

Verified by: README review

### CUR-08 Live capture

Capture `cursor-agent` and Cursor app payloads (needs `cursor-agent login`) and replace or confirm the constructed fixtures. Check four things. Does `sessionEnd` fire per turn or only when the conversation closes? Do `generation_id` values match between tool events and `stop`? Is an empty answer accepted on every registered event? Do WhoIsWorking's Claude Code hooks also run inside Cursor (CUR-03), and if so, does Cursor treat their empty answer on `preToolUse` as allow? Then drop the experimental label.

## Open questions

1. Which process owns a Cursor session, and can the hook's parent chain find it, for "Open session" and cleanup on exit?

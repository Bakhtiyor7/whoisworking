# 12 OpenCode adapter

Status: implemented
Depends on: `02-reducer.md`, `05-ingest-and-hook-script.md`
Code: `Sources/AgentCore/OpenCode.swift` (plugin source, installer, adapter)

## Purpose

Show local OpenCode v2 sessions in WhoIsWorking with the [OpenCode badge](../../Sources/WhoIsWorking/AgentIcons/opencode.png).

OpenCode has no hooks file. It loads plugins, and v2 runs only v2 plugins: `export default { id, setup(ctx) }`, where `setup` subscribes to `ctx.event.subscribe()` and returns a cleanup function ([server plugins](https://opencode.ai/docs/build/plugins/server)). V1 plugins, such as the `orca` one on this machine, do not run on v2, and v1 is not supported.

Captured on 2026-11-22 from OpenCode CLI 2.0.14 (`opencode run --standalone`, free model) with a capture plugin in a scratch project. Four runs: a plain reply, a shell tool, a permission request that was rejected, and a subagent. What the captures showed:

- Every event is `{id, created (ms), type, durable?: {aggregateID, seq}, location?: {directory}, data}`, with the session id at `data.sessionID`.
- A root session started by `opencode run` emits no `session.created`. A subagent's child session does, with `parentID`.
- `ctx.session.get({sessionID})` returns `location.directory`, plus `parentID` and `title` when set.
- A rejected permission runs `permission.asked` → `permission.replied` (`reject`) → `session.tool.failed` → `session.execution.interrupted` (`reason: user`).
- The tool name arrives on `session.tool.input.started`. `session.tool.called` carries the input.

Captured: `session.created` (child), `session.execution.started|succeeded|interrupted`, `session.step.started`, `session.tool.input.started`, `session.tool.called`, `permission.asked` and `permission.replied`. Taken from the 2.0.14 binary's event schemas, not captured: `session.execution.failed`, `session.renamed`, `session.deleted` and `form.created`.

The shipped plugin was also run inside OpenCode 2.0.14 itself (a permission request that OpenCode rejected), with a socket listener standing in for WhoIsWorking. What it sent is `Tests/Fixtures/opencode-real/e2e-permission.forwarded.jsonl`.

## Requirements

### OPC-01 Plugin file

WhoIsWorking installs one plugin file it owns, `~/.config/opencode/plugins/whoisworking.js`. Its first line is the marker `// WhoIsWorking OpenCode plugin.`. Install writes it, creating the folder if needed, and is idempotent. A `XDG_CONFIG_HOME` or OpenCode config folder elsewhere is not followed yet; use `--settings <path>` on the command line. A file at that path without the marker is refused on install and on uninstall. Replacing or removing a marked copy that differs from the current version writes a timestamped backup first (`whoisworking.js.whoisworking-backup-…`, which OpenCode does not load). Uninstall deletes only that file; if it is a link, the link goes and its target stays. Status is installed when the file matches, partial when a marked copy is outdated, and not installed when there is no file. Other plugins are never touched.

Tests: `OpenCodePluginInstallerTests/installWritesThePluginAndIsIdempotent`, `OpenCodePluginInstallerTests/refusesAFileItDidNotWrite`, `OpenCodePluginInstallerTests/replacingAnEditedCopyKeepsABackup`, `OpenCodePluginInstallerTests/uninstallRemovesOnlyItsOwnFile`, `OpenCodePluginInstallerTests/statusFollowsTheFile`, `OpenCodePluginInstallerTests/uninstallRemovesALinkNotItsTarget`, `OpenCodePluginInstallerTests/removingAnEditedCopyKeepsABackup`

### OPC-02 The plugin cannot slow or change OpenCode

The plugin only observes. It never answers a permission or a form, never changes input or output, and imports only Node built-ins (`node:net`, `node:fs`, `node:os`, `node:path`). It forwards these types: `session.created`, `session.renamed`, `session.deleted`, `session.execution.started|succeeded|failed|interrupted`, `session.step.started`, `session.tool.called`, `permission.asked`, `permission.replied` and `form.created`. Each `data` is trimmed to the fields WhoIsWorking reads. Tool input keeps only `command`, `path`, `filePath`, `pattern`, `url`, `description` and `agent`, so no prompt, file content or tool output is sent. A shell command is sent as typed (up to 1,000 characters), as for Claude Code and Codex, because the Needs you card shows it. Events are trimmed before they are queued, so the queue never holds more than that.

Messages go one connection at a time, in order, from a queue of at most 256. On overflow the oldest is dropped. A send gives up after 1 s. Each message uses the wire format `whoisworking1 opencode ppid=<OpenCode's pid>` followed by the JSON. When the socket is missing, nothing is sent, no session is looked up, and nothing fails. A failed or slow session lookup (1 s) is not remembered, so the next event for that session asks again. Cleanup stops the subscription, empties the queue and ends a send in flight, and the plugin's timers never keep OpenCode from exiting.

Tests: `OpenCodePluginTests/forwardsTrimmedEventsInOrder`, `OpenCodePluginTests/childSessionsCarryTheirRoot`, `OpenCodePluginTests/doesNothingWhenTheAppIsNotRunning`, `OpenCodePluginTests/aStalledAppCostsOneSecondAndTheQueueKeepsTheNewest`, `OpenCodePluginTests/cleanupStopsSending`, `OpenCodePluginTests/aFailedLookupIsTriedAgain`, `OpenCodePluginSourceTests/onlyObservesAndUsesOnlyBuiltIns`. The plugin tests run the JavaScript under Node; on a machine without Node they are skipped, except in CI, where they fail.

### OPC-03 Adapter

`OpenCodeAdapter` maps forwarded messages to `AgentEvent.Kind`, keyed by `data.sessionID`, dated by the event's own `created` time so a late message is dropped by the reducer's ordering rule (RED-10).

- `session.created` → session started. `session.deleted` → session ended. `session.renamed` → renamed (RED-19).
- `session.execution.started` → prompt submitted. `.succeeded` → done. `.failed` → error with the error's message. `.interrupted` → interrupted, except reason `superseded`, which is dropped because the next execution starts right after it.
- `session.step.started` → observed activity without a turn id (RED-18), which returns a session waiting for a reply to working when the model continues.
- `session.tool.called` → tool started, with the tool name the plugin attached.
- `form.created` → waiting for reply, with the form's title.

Unknown types and broken input are dropped.

Tests: `OpenCodeAdapterTests/lifecycleAndExecutionMapToSessionEvents`, `OpenCodeAdapterTests/supersededInterruptionsAreDropped`, `OpenCodeAdapterTests/toolsStepsAndFormsMap`, `OpenCodeAdapterTests/theEventTimeIsTheEventDate`, `OpenCodeAdapterTests/unknownOrBrokenInputIsDropped`

### OPC-04 Folder and name

The folder is the event's `location.directory`, else the directory the plugin found for the session. The name is the session title when there is one. When neither is known, the folder stays unknown.

Tests: `OpenCodeAdapterTests/folderAndNameComeFromTheEventOrTheLookup`

### OPC-05 Needs you

`permission.asked` → needs approval, with the action, the resources and the request id. `permission.replied` → closes that request only (RED-17). A child session's requests, replies and questions count against its root session, the one the user sees. A child's tool call only updates the root's activity line, and a child's model step counts as activity on the root (so the root is working again after the user answered the child's question). Everything else from a child session is dropped, so subagents never become rows.

Tests: `OpenCodeAdapterTests/permissionsCarryTheirRequestId`, `OpenCodeAdapterTests/childSessionsActOnTheirRoot`

### OPC-06 Lifetime

`session.deleted` removes the session. OpenCode sessions have no owning pid in WhoIsWorking yet, because the server may be a shared background service. Quiet sessions go after 15 minutes (SES-08). OpenCode sends nothing while it waits, so a session waiting for approval or an answer stays up to 4 hours.

Tests: `OpenCodeAdapterTests/deletedSessionsAreRemoved`

### OPC-07 Real payloads

The captured events, anonymized, live in `Tests/Fixtures/opencode-real/` and are recorded in `Tests/Fixtures/README.md`. Every message the plugin forwards for a top-level session maps, a subagent's own execution and step messages map to nothing, and each captured run ends in the state the user saw: done, done, idle after the rejection, and done with the subagent never shown as a row.

Tests: `OpenCodeRealPayloadTests/mapsEveryCapturedEvent`, `OpenCodeRealPayloadTests/capturedRunsEndInTheRightState`, `OpenCodeRealPayloadTests/thePluginInsideOpenCodeEndsTheRejectedRunIdle`

### OPC-08 Routing and command line

`HookMessage.event` routes header agent `opencode` to the adapter. `WhoIsWorking hooks … --agent opencode [--settings <plugin path>]` reports, previews, installs and removes the plugin file.

Tests: `OpenCodeAdapterTests/routesOpenCodeMessagesToTheAdapter`, `HooksCommandTests/opencodeAgentWritesThePluginFile`

### OPC-09 Kept current

At launch only, an installed plugin that differs from this version is replaced, with a backup, as the hook script is (UI-14). A missing file stays missing, an unmarked file is refused, and a link is left alone. Opening Settings writes nothing. A failed update shows in Settings.

Tests: `OpenCodePluginInstallerTests/updateReplacesOnlyAnOutdatedOwnedFile`

### OPC-10 Docs

`README.md` has install steps for OpenCode and says what is covered and what is not.

Verified by: README review

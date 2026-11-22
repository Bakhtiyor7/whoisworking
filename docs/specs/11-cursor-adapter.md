# 11 Cursor adapter

Status: draft
Depends on: `02-reducer.md`, `06-hook-installer.md`

## Purpose

Show Cursor agent sessions (the Cursor app and `cursor-agent`) in Perch, marked CU.

**Unverified:** the event and field names below come from `docs/plan.md` §2, which notes they were read from truncated doc pages. Before any code, read https://cursor.com/docs/agent/hooks, capture real payloads with `PERCH_LOG_EVENTS=1`, and correct this spec.

## Requirements

### CUR-01 Adapter

A `CursorAdapter` maps Cursor hook JSON to the shared `AgentEvent.Kind`. Sessions are identified by `conversation_id`; the folder is the first of `workspace_roots`. Unknown events and broken input are dropped.

### CUR-02 Hook target

A `HookTarget` for `~/.cursor/hooks.json` with the agent id `cursor`. All guarantees of `06-hook-installer.md` apply unchanged. If Cursor's file shape differs from the `{"hooks": {"<Event>": [...]}}` shape the installer knows, the installer is extended behind tests first; it never falls back to rewriting the file.

### CUR-03 Routing

`HookMessage.event` routes header agent `cursor` to the adapter.

### CUR-04 Inferred "needs you"

Cursor has no permission event. A `beforeShellExecution` or `beforeMCPExecution` with no follow-up event within a set time means `needsApproval`; the follow-up for the same command resolves it. The delay is chosen from captured payloads and stated here before coding.

### CUR-05 Lifetime

A session is removed when the owning Cursor process exits, or after 15 minutes of silence with no known pid (SES-08).

### CUR-06 Fixtures

Captured, anonymized payloads live in `Tests/Fixtures/cursor/`, recorded in `Tests/Fixtures/README.md`. A test maps every captured event, as for Claude Code (CCA-09).

### CUR-07 Docs

`README.md` gets an install section and a "what is covered and what is not" section for Cursor.

## Open questions

1. Is the inferred approval reliable enough to show wings, or should Cursor sessions only show working and done?
2. Does `cursor-agent` (CLI) fire the same hooks as the app?
3. Which process owns a Cursor session, and can it be found from the hook's parent chain?

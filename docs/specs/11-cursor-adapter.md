# 11 Cursor adapter

Status: draft
Depends on: `02-reducer.md`, `06-hook-installer.md`

## Purpose

Show local Cursor agent sessions in WhoIsWorking using the [Cursor badge](../../Resources/AgentIcons/cursor.png). Verify the macOS app first and assess the CLI with separate captures.

The [Cursor hook reference](https://cursor.com/docs/hooks) documents the configuration, fields, and lifecycle events below. Captures from the installed app and CLI are pending.

## Requirements

### CUR-01 Adapter

A `CursorAdapter` maps agent hooks to the shared `AgentEvent.Kind`. Use `conversation_id` as the session ID, with the documented `session_id` as a fallback on `sessionStart`. Use the first workspace root as the folder when available. Drop unknown events, invalid payloads, and events outside a conversation.

Map `sessionStart` to a new session and `sessionEnd` to removal. Use a verified prompt or activity event for working. For `stop`, map `completed`, `aborted`, and `error` to completed, interrupted, and failed turns respectively. Check repeated turns in a single conversation and reserve session removal for an actual end.

### CUR-02 Hook target

Add a `HookTarget` for the user-level `~/.cursor/hooks.json` with the agent ID `cursor`. Cursor documents a root `version` and a `hooks` object containing ordered arrays of command definitions. Apply the guarantees in `06-hook-installer.md` and check both a new file and a file with unrelated hooks.

Only register events that accept the existing silent, exit-zero forwarding contract. Confirm behavior with a missing or stale WhoIsWorking socket as well as a listening one.

### CUR-03 Routing

`HookMessage.event` routes header agent `cursor` to the adapter.

### CUR-04 Approval status

Initial coverage reports lifecycle and confirmed errors. A missing follow-up event cannot distinguish a pending approval from a slow, failed, or canceled tool. The documented permission hooks can block execution on invalid responses. Leave them outside the status-only integration until an observation path for an actual pending approval is verified and approved.

### CUR-05 Lifetime

A session is removed when the owning Cursor process exits, or after 15 minutes of silence with no known pid (SES-08).

### CUR-06 Fixtures

Captured, anonymized payloads live in `Tests/Fixtures/cursor/`, recorded in `Tests/Fixtures/README.md`. A test maps every captured event, as for Claude Code (CCA-09).

### CUR-07 Docs

`README.md` gets an install section and a "what is covered and what is not" section for Cursor.

## Open questions

1. Which prompt and lifecycle events accept a silent, exit-zero handler in the app? Does `sessionEnd` fire when the conversation closes?
2. Does the installed CLI fire the same hooks as the app, with the same conversation IDs and event order?
3. Which process owns a session, and does the hook parent chain identify it reliably?

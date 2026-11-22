# 14 Antigravity adapter

Status: draft
Depends on: `02-reducer.md`, `05-ingest-and-hook-script.md`, `06-hook-installer.md`

## Purpose

Show local Google Antigravity sessions in WhoIsWorking using the [Antigravity badge](../../Resources/AgentIcons/antigravity.png). Verify the installed macOS client first. Evaluate the CLI and other clients separately.

The [Google Antigravity hook reference](https://antigravity.google/docs/hooks?tab=ide) documents lifecycle events, the global configuration path, and the handler schema. Captures from the installed client are pending.

## Requirements

### ANT-01 Hook configuration

The documented global file is `~/.gemini/config/hooks.json`. It groups events under named hooks with a schema distinct from WhoIsWorking's current targets. Verify the path and shape on the supported client before enabling installation. Install and uninstall affect only WhoIsWorking's named hook group and meet the backup, idempotency, and ordering guarantees in `06-hook-installer.md`.

### ANT-02 Forwarding and routing

Forward supported events through the local WhoIsWorking socket under the agent ID `antigravity`. Antigravity's documented common payload lacks an event-name field, so the handler registration supplies the event name unless captures establish a reliable field. Include only the data required by the adapter and reject unknown or invalid envelopes.

Use the existing silent hook only where the client accepts no output and exit zero. Google documents a response for `Stop`. Until the installed client is verified to accept a passive observer for an event, leave that event unregistered. Verify that WhoIsWorking being unavailable leaves normal agent execution and stopping intact.

### ANT-03 Session identity and lifecycle

Use `conversationId` as the session ID and the first workspace path as the folder when present. Use `SessionStart` for discovery. A verified `PreInvocation` can mark a session working. `PostInvocation` marks an individual model call and leaves the turn active. A verified `Stop` with `fullyIdle: true` can mark execution ended. Check that repeated turns reuse the same session and that a stop with background work outstanding does not mark it done.

### ANT-04 Approval and error states

Initial coverage uses verified lifecycle events. The documented hooks do not expose an explicit pending approval event. Use only verified signals for needs approval and errors.

### ANT-05 Lifetime

When a reliable local process owner exits, remove its sessions. Keep the conversation available between turns and use the 15-minute orphan rule (SES-08) when there is no known owner.

### ANT-06 Verification and docs

Capture and anonymize the installed client's payloads before implementation. Cover new conversations, repeated turns, normal stop, interruption, background tasks, unknown events, and an unavailable WhoIsWorking socket. Record the fixtures and publish the supported client versions and installation steps with the integration.

## Open questions

1. Does the installed macOS client load the documented global hook file and emit the same payloads as newer releases?
2. Which lifecycle hooks accept the existing silent observer? Does `Stop` distinguish completion, interruption, and failure in practice?
3. Can the hook parent chain identify an owning process and separate top-level conversations from subagents?
4. Should the first release cover only the macOS client or also the Antigravity CLI?

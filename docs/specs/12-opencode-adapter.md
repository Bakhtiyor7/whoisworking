# 12 OpenCode adapter

Status: draft
Depends on: `02-reducer.md`, `05-ingest-and-hook-script.md`

## Purpose

Show local OpenCode v2 sessions in WhoIsWorking using the [OpenCode badge](../../Resources/AgentIcons/opencode.png). The installed CLI reported v2.0.14 when checked with isolated data and configuration paths.

The [plugin guide](https://opencode.ai/docs/plugins/) documents global plugin discovery. The [server plugin reference](https://opencode.ai/docs/build/plugins/server) documents `ctx.event.subscribe()` and the [API reference](https://opencode.ai/docs/api) lists the event types. Captures from the installed version are pending.

## Requirements

### OPC-01 Plugin, not hook entries

WhoIsWorking installs one v2 server plugin file it owns in the global OpenCode plugin directory, normally `~/.config/opencode/plugins/whoisworking.js`. Respect the configured location, refuse an unrelated file at the same path, and leave existing plugins intact. Install is idempotent and uninstall removes only the owned file.

### OPC-02 The plugin cannot slow or change OpenCode

Subscribe to relevant public events and stop the subscription when the plugin unloads. Forward only the fields WhoIsWorking needs using the WhoIsWorking socket format. Sending is best effort and takes place outside the agent's blocking path. A missing socket leaves OpenCode running normally. The plugin never evaluates permissions, changes agent input, or modifies tool results.

### OPC-03 Adapter

An `OpenCodeAdapter` maps forwarded events to `AgentEvent.Kind` using the session ID verified in each event. Start with `session.created`, `session.execution.started`, the documented succeeded, failed, and interrupted execution events, and `session.deleted`. Keep a session available between runs and use documented parent information to keep subagents out of the top-level session list. Drop unknown events and invalid input.

### OPC-04 Folder

Use the directory for the individual session when available. A server can host more than one workspace, so leave the folder unknown if the event or a session lookup cannot establish it.

### OPC-05 Needs you

Use `permission.asked` to show a pending owner action and `permission.replied` to clear the corresponding request. Match the session and permission request IDs. Confirm the state after approval, denial, and an execution ending while permission is pending.

### OPC-06 Lifetime

Remove deleted sessions immediately. If captured events establish a reliable local process owner, remove its sessions on process exit. Otherwise use the 15-minute orphan rule (SES-08).

### OPC-07 Fixtures and docs

Captured, anonymized events live in `Tests/Fixtures/opencode/`, recorded in `Tests/Fixtures/README.md`. `README.md` gets install and coverage sections.

## Open questions

1. On v2.0.14, what fields and order does the server plugin see for session creation, execution, and permission requests and replies?
2. Can a plugin resolve a session's directory and distinguish subagent sessions in both the terminal and desktop clients?
3. Does plugin reload cleanly stop event forwarding? Does the existing `orca` plugin coexist with the observer across start, reload, and uninstall?
4. Does the server provide a reliable process lifetime for its sessions? Is OpenCode v1 compatibility needed?

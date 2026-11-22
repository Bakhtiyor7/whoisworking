# 12 OpenCode adapter

Status: draft
Depends on: `02-reducer.md`, `05-ingest-and-hook-script.md`

## Purpose

Show OpenCode sessions in Perch, marked OC.

**Unverified:** OpenCode has no hooks file. It loads JavaScript plugins from `~/.config/opencode/plugins/`. The plugin event names in `docs/plan.md` §2 are unconfirmed. Before any code, read https://opencode.ai/docs/plugins/, capture real events, and correct this spec.

## Requirements

### OPC-01 Plugin, not hook entries

Perch installs one plugin file it owns, `~/.config/opencode/plugins/perch.js`. It never edits another tool's plugin. Install is idempotent; uninstall deletes exactly that file.

### OPC-02 The plugin cannot slow or change OpenCode

The plugin only forwards events to Perch's socket with the same wire format (`perch1 opencode ppid=<pid>` then JSON). It returns nothing that changes OpenCode's behaviour, swallows every error, and does nothing when the socket is missing. This is the plugin equivalent of ING-07 and ING-09.

### OPC-03 Adapter

An `OpenCodeAdapter` maps the forwarded events to the shared `AgentEvent.Kind`, keyed by `sessionID`. Unknown events and broken input are dropped.

### OPC-04 Folder

The folder comes from the event when present, otherwise from the owning process's working directory.

### OPC-05 Needs you

The permission event maps to `needsApproval`; the reply resolves it.

### OPC-06 Lifetime

A session is removed when the owning `opencode` process exits, or after 15 minutes of silence with no known pid (SES-08).

### OPC-07 Fixtures and docs

Captured, anonymized events live in `Tests/Fixtures/opencode/`, recorded in `Tests/Fixtures/README.md`. `README.md` gets install and coverage sections.

## Open questions

1. What are the real plugin event names for prompt, tool start/finish, permission and session end?
2. Does a plugin see the session's folder?
3. An existing `orca` plugin is installed on this machine: does plugin order matter?

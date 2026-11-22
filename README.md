# Perch

A macOS app that lives in the MacBook notch and shows the status of Claude Code and Codex sessions on this Mac: which are working, which need you, which finished. Nothing is drawn while sessions are idle or working. When a session needs you, small amber "wings" appear beside the notch. Hover the notch for the full list.

Status only (v1): Perch never approves or denies anything.

## Requirements

- macOS 15 or later (built and tested on macOS 27.2, MacBook Pro M4)
- Xcode 16+ command-line tools (Swift 6)

## Build and test

```bash
swift test
```

```bash
scripts/bundle.sh
```

`bundle.sh` builds the release binary and assembles `build/Perch.app` (agent app with no Dock icon via `LSUIElement`, ad-hoc signed, not notarized). Use `scripts/bundle.sh debug` for a debug build.

## Run

```bash
open build/Perch.app
```

Hover the notch to open the panel. With no notch (external display), Perch shows a small pill at the top centre when something needs you. Opening `Perch.app` again while it runs shows Settings, which also has the Quit button.

Claude Code sessions that were already running appear within a few seconds (Perch reads `~/.claude/sessions/*.json`). Codex has no session files: running Codex CLIs show as "Running · no live status yet" until their first hook event. Live states (needs approval, waiting for reply, done) need the hooks below. Rows are marked CC (Claude Code) or CX (Codex).

## Install the Claude Code hooks

In Settings choose **Install hooks…**, or from a terminal:

```bash
build/Perch.app/Contents/MacOS/Perch hooks preview > /tmp/perch-preview.json && diff -u ~/.claude/settings.json /tmp/perch-preview.json
```

```bash
build/Perch.app/Contents/MacOS/Perch hooks install
```

What install does:

1. Writes the hook script to `~/Library/Application Support/Perch/perch-hook`. It uses only `/bin/sh` and `/usr/bin/nc`, forwards the hook JSON to Perch's socket and always exits 0, so it never blocks Claude Code, even when Perch is not running.
2. Saves a backup beside the settings file: `~/.claude/settings.json.perch-backup-YYYYMMDD-HHMMSS`.
3. Appends one Perch entry to 13 hook events in `~/.claude/settings.json`. Other tools' entries are not changed or reordered. Running install again changes nothing. If the file is not valid JSON, Perch refuses to write.

New Claude Code sessions pick up the hooks. Sessions that were already running may need a restart.

## Install the Codex hooks

In Settings, Codex section, choose **Install hooks…**, or:

```bash
build/Perch.app/Contents/MacOS/Perch hooks preview --agent codex > /tmp/perch-codex-preview.json && diff -u ~/.codex/hooks.json /tmp/perch-codex-preview.json
```

```bash
build/Perch.app/Contents/MacOS/Perch hooks install --agent codex
```

This appends one Perch entry (timeout 3 s, Codex's limit for SessionEnd and Interrupt) to 10 events in `~/.codex/hooks.json`, with the same guarantees as for Claude Code: backup first, other tools' entries untouched, idempotent, refuses invalid JSON.

Codex then asks you to trust the new hooks before it runs them. In the Codex CLI type `/hooks` and trust the Perch entries; in the ChatGPT/Codex app use **Review hooks** (or Settings › Hooks). Until then Codex skips them and Perch sees nothing from Codex. If Codex has never opened a folder before, it also asks whether to trust that folder.

## Uninstall the hooks

In Settings choose **Uninstall hooks…** in the agent's section, or:

```bash
build/Perch.app/Contents/MacOS/Perch hooks uninstall
```

```bash
build/Perch.app/Contents/MacOS/Perch hooks uninstall --agent codex
```

This removes exactly the entries whose command contains `/Perch/perch-hook`. If Perch was the only thing on an event, the event key is removed too, so the file returns to its earlier content. A backup is written first. The shared hook script is deleted once no agent's hooks use it.

## How it works

- `Sources/AgentCore` has no UI and is fully unit-tested: the session model and its six states, a pure reducer `(sessions, event) -> sessions`, the Claude Code and Codex hook adapters, the order-preserving JSON reader/writer used by the installer, the Unix socket server, the hook script, and session discovery.
- `Sources/Perch` is the app: a borderless non-activating `NSPanel` above the menu bar, sized from `NSScreen.safeAreaInsets` and the auxiliary top areas, with SwiftUI inside. It is click-through while collapsed, opens after a 150 ms hover dwell and closes 250 ms after the cursor leaves.
- Two cases fire no hook: declining a permission prompt, and pressing Esc to interrupt. Perch covers them with the session file: when its `status` turns `idle` after the last hook event, a session stuck in "needs approval" or "working" becomes idle. Without hooks, the file's `busy`, `waiting` and `idle` map to working, needs approval and idle.
- The hook script sends its parent pid. For Codex, Perch walks up from it to the nearest `codex` process and ties the session to it, so the session is removed when that process exits.

## Codex: what is covered and what is not

Tested with Codex CLI 0.163.0; the ChatGPT app's own Codex is a newer build.

- Covered: working, needs approval (with the full command), done, interrupted, and turns that fail. Codex 0.163 fires no hook when a turn fails (for example an API error), so for a Codex session that has said "working" for 10 s without events, Perch reads the end of its rollout (`transcript_path`) and shows the error or marks it done. Codex calls that file format unstable, so this is best effort.
- No "waiting for your reply" for Codex: Codex has no notification event for questions.
- Codex 0.163 runs the conversation in a shared `codex app-server` daemon that outlives the terminal ("Any running work continues"). Perch ties those sessions to the daemon, so closing the CLI window does not remove them; Codex's `SessionEnd` (normal close, or 30 minutes idle with no client) does.
- Sessions started before Perch: running Codex CLIs appear as placeholders until their next hook event. Sessions in the ChatGPT app appear only after their next hook event.
- One row per folder: a placeholder for a Codex CLI is hidden while a live Codex session exists in the same folder, so two CLIs in one folder show as one until the second sends an event.
- Names: Codex sessions are named after their folder. ChatGPT app projects can live in folders with generated names.
- "Open session" reaches the terminal only when the hook process still has the terminal app as an ancestor; daemon-hosted sessions usually do not, and Perch beeps.

- Hook events arrive on `~/Library/Application Support/Perch/events.sock` (directory 0700, socket 0600), one JSON object per connection. Perch also rescans session files when they change, every 3 seconds and after wake. Sessions whose process exited are removed.

"Open session" and row clicks bring the owning app to the front by walking the session process's parent chain to the first regular app (Terminal, iTerm2, VS Code, Cursor, Claude.app). They cannot select a specific terminal tab or a specific conversation inside Claude.app. Sessions inside tmux or screen have no app parent, so Perch beeps instead.

## Debug switches (environment variables)

| Variable | Effect |
|---|---|
| `PERCH_DEBUG_STATE=/path/state.txt` | Writes a readable snapshot of all sessions on every change |
| `PERCH_LOG_EVENTS=1` | Saves every raw hook payload to `~/Library/Application Support/Perch/event-log/` (useful for test fixtures) |
| `PERCH_SNAPSHOT=/dir` | Renders the collapsed and expanded panel to PNGs (no screen-recording permission needed) |
| `PERCH_FORCE=expanded` | Keeps the panel open |
| `PERCH_NO_NOTCH=1` | Uses the no-notch pill layout on a notched screen |
| `PERCH_OPEN_SETTINGS=1` | Opens Settings at launch |

## Project docs

- `docs/plan.md`: research, plan and settled design
- `docs/spike/main.swift`: the throwaway spike the window behaviour came from

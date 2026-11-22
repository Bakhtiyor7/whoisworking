# Perch

A macOS app that lives in the MacBook notch and shows the status of Claude Code sessions on this Mac: which are working, which need you, which finished. Nothing is drawn while sessions are idle or working. When a session needs you, small amber "wings" appear beside the notch. Hover the notch for the full list.

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

Sessions that were already running appear within a few seconds (Perch reads `~/.claude/sessions/*.json`). Live states (needs approval, waiting for reply, done) need the hooks below.

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

## Uninstall the hooks

In Settings choose **Uninstall hooks…**, or:

```bash
build/Perch.app/Contents/MacOS/Perch hooks uninstall
```

This removes exactly the entries whose command contains `/Perch/perch-hook` and deletes the hook script. If Perch was the only thing on an event, the event key is removed too, so the file returns to its earlier content. A backup is written first.

## How it works

- `Sources/AgentCore` has no UI and is fully unit-tested: the session model and its six states, a pure reducer `(sessions, event) -> sessions`, the Claude Code hook adapter, the order-preserving JSON reader/writer used by the installer, the Unix socket server, the hook script, and session discovery.
- `Sources/Perch` is the app: a borderless non-activating `NSPanel` above the menu bar, sized from `NSScreen.safeAreaInsets` and the auxiliary top areas, with SwiftUI inside. It is click-through while collapsed, opens after a 150 ms hover dwell and closes 250 ms after the cursor leaves.
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

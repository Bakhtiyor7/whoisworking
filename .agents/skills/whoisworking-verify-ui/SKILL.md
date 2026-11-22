---
name: whoisworking-verify-ui
description: Check WhoIsWorking's notch panel, wings, empty state, no-notch pill or Settings window without looking at the screen, by rendering snapshots and reading the debug state file. Use after any change under Sources/WhoIsWorking, when a UI requirement in docs/specs/08-notch-ui.md needs proof, or when asked to run, screenshot or show the app.
---

# Verify the WhoIsWorking UI

The `WhoIsWorking` target has no unit tests. Prove UI changes with snapshots and the state file, and say in your report which check you ran.

## Rules

- Run the debug binary from `.build/debug/WhoIsWorking`. Do not run `scripts/bundle.sh` for a check: it deletes and rebuilds `build/WhoIsWorking.app`, which may be the copy the user has running.
- A second WhoIsWorking may run next to the user's copy. It cannot own the socket, so it gets no hook events and its panel shows "Another copy of WhoIsWorking is already running." Session files and running Codex processes still appear. This is enough for layout checks. For a check that needs live hook events, ask the user before quitting their copy.
- Never run `WhoIsWorking hooks install` or `uninstall` without `--settings <copy>`.
- Snapshot mode does not exit. Start it in the background, wait, then stop that pid only.

## Steps

1. Build:

```bash
swift build
```

2. Render into an empty folder outside the repo (your scratch or temp folder), then stop the process:

```bash
OUT="$(mktemp -d)"; WHOISWORKING_SNAPSHOT="$OUT" WHOISWORKING_DEBUG_STATE="$OUT/state.txt" .build/debug/WhoIsWorking >/dev/null 2>&1 & PID=$!; sleep 6; kill "$PID"; ls "$OUT"
```

3. Read `collapsed.png` and `expanded.png` as images, and `state.txt` as text. Compare with the requirement you are proving.

## Variants

Add these variables to the command in step 2:

| Goal | Variable |
|---|---|
| Keep the panel open | `WHOISWORKING_FORCE=expanded` |
| Empty state | `WHOISWORKING_CLAUDE_SESSIONS="$OUT/none"` after `mkdir "$OUT/none"` (running Codex CLIs still show as placeholders) |
| No-notch pill | `WHOISWORKING_NO_NOTCH=1` |
| Settings window, saved as `settings.png` | `WHOISWORKING_OPEN_SETTINGS=1` |

To show a given state, write session files into a folder and point `WHOISWORKING_CLAUDE_SESSIONS` at it. Copy the shape from `Tests/Fixtures/claude-sessions/`, set `pid` to a live process (for example `$$`), and set `status` to `busy`, `waiting` or `idle`. Without hook events, `waiting` renders as needs approval, which shows the wings and the Needs you card.

## What snapshots cannot prove

Hover timing (UI-06), window level and click-through (UI-07), "Open session" (UI-10) and motion (UI-11) need a person at the notch. Say so in the report and name them as not verified.

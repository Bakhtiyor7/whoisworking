# WhoIsWorking

A macOS app that lives in the MacBook notch and shows the status of Claude Code, Codex, Cursor, OpenCode and Antigravity sessions on this Mac: which are working, which need you, which finished. Nothing is drawn while sessions are idle or working. When a session needs you, small amber "wings" appear beside the notch. Hover the notch for the full list.

Status only (v1): WhoIsWorking never approves or denies anything.

The app shows its name as "Who's Working". It was called Perch until 2026-11-22; see [Switching from Perch](#switching-from-perch).

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

```bash
scripts/check-specs.sh
```

`check-specs.sh` checks that the specs in `docs/specs/` and the tests name each other.

`bundle.sh` builds the release binary and assembles `build/WhoIsWorking.app` (agent app with no Dock icon via `LSUIElement`, ad-hoc signed, not notarized). Use `scripts/bundle.sh debug` for a debug build.

## Run

```bash
open build/WhoIsWorking.app
```

Hover the notch to open the panel. With no notch (external display), WhoIsWorking shows a small pill at the top centre when something needs you. Opening `WhoIsWorking.app` again while it runs shows Settings, which also has the Quit button.

## Update to the latest changes

```bash
scripts/update.sh
```

This runs the tests and the spec check, builds the release binary, stops the running WhoIsWorking, rebuilds `build/WhoIsWorking.app` and opens it. Tests and the build run before anything is stopped, so a failure leaves the running copy alone. `--skip-tests` skips the first step. Installed hooks keep working across updates: the hook script path stays the same and WhoIsWorking rewrites the script at launch when it changed.

Claude Code sessions that were already running appear within a few seconds (WhoIsWorking reads `~/.claude/sessions/*.json`). Codex has no session files: running Codex CLIs show as "Running · no live status yet" until their first hook event. Live states (needs approval, waiting for reply, done) need the hooks below. Cursor, OpenCode and Antigravity sessions appear after their first event once their hooks or plugin are installed. Session rows and Needs you cards show each agent's icon.

WhoIsWorking bundles the full-color [Claude Code](https://github.com/lobehub/lobe-icons/blob/7e81f85708ada35e054c96173a14b1bfbe9b74e3/packages/static-png/dark/claudecode-color.png) and [Codex](https://github.com/lobehub/lobe-icons/blob/7e81f85708ada35e054c96173a14b1bfbe9b74e3/packages/static-png/dark/codex-color.png) artwork and the [Cursor, OpenCode and Antigravity marks](Resources/AgentIcons/README.md) from Lobe Icons. The [Lobe Icons MIT license](Sources/WhoIsWorking/AgentIcons/LobeIcons-LICENSE.txt) ships with the app. The marks identify the agents and belong to their respective owners.

## Releases

Builds for other people are published in the public [whoisworking-releases](https://github.com/Bakhtiyor7/whoisworking-releases) repo as a DMG; this repo stays private. Bump the version in `Resources/Info.plist` and write `docs/release-notes/X.Y.Z.md` in a commit, then:

```bash
scripts/release.sh 0.1.0 --dry-run
```

```bash
scripts/release.sh 0.1.0
```

The dry run tests, builds into `build/release/0.1.0/` and checks the DMG without publishing anything. The real run shows what it will publish and asks for "yes", then creates the release, pushes `master` and the tag to this repo, and checks the public download. The app's Check for Updates button reads the latest release of that repo. Details: [spec 13](docs/specs/13-distribution.md).

## Switching from Perch

The rename changed the hook path, so WhoIsWorking does not recognise hooks that Perch installed. With the old build still in `build/Perch.app`, remove them first (or use Uninstall hooks in Perch's Settings), then quit Perch:

```bash
build/Perch.app/Contents/MacOS/Perch hooks uninstall
```

```bash
build/Perch.app/Contents/MacOS/Perch hooks uninstall --agent codex
```

```bash
pkill -x Perch
```

Then run `scripts/update.sh`, install the hooks again from WhoIsWorking (below) and delete `build/Perch.app`. If "Launch at login" was on in Perch, turn it on again in WhoIsWorking.

## Install the Claude Code hooks

In Settings choose **Install hooks…**, or from a terminal:

```bash
build/WhoIsWorking.app/Contents/MacOS/WhoIsWorking hooks preview > /tmp/whoisworking-preview.json && diff -u ~/.claude/settings.json /tmp/whoisworking-preview.json
```

```bash
build/WhoIsWorking.app/Contents/MacOS/WhoIsWorking hooks install
```

What install does:

1. Writes the hook script to `~/Library/Application Support/WhoIsWorking/whoisworking-hook`. It uses only `/bin/sh` and `/usr/bin/nc`, forwards the hook JSON to WhoIsWorking's socket and always exits 0, so it never blocks Claude Code, even when WhoIsWorking is not running.
2. Saves a backup beside the settings file: `~/.claude/settings.json.whoisworking-backup-YYYYMMDD-HHMMSS`.
3. Appends one WhoIsWorking entry to 13 hook events in `~/.claude/settings.json`. Other tools' entries are not changed or reordered. Running install again changes nothing. If the file is not valid JSON, WhoIsWorking refuses to write.

New Claude Code sessions pick up the hooks. Sessions that were already running may need a restart.

## Install the Codex hooks

In Settings, Codex section, choose **Install hooks…**, or:

```bash
build/WhoIsWorking.app/Contents/MacOS/WhoIsWorking hooks preview --agent codex > /tmp/whoisworking-codex-preview.json && diff -u ~/.codex/hooks.json /tmp/whoisworking-codex-preview.json
```

```bash
build/WhoIsWorking.app/Contents/MacOS/WhoIsWorking hooks install --agent codex
```

This appends one WhoIsWorking entry (timeout 3 s, Codex's limit for SessionEnd and Interrupt) to 10 events in `~/.codex/hooks.json`, with the same guarantees as for Claude Code: backup first, other tools' entries untouched, idempotent, refuses invalid JSON.

Codex then asks you to trust the new hooks before it runs them. In the Codex CLI type `/hooks` and trust the WhoIsWorking entries; in the ChatGPT/Codex app use **Review hooks** (or Settings › Hooks). Until then Codex skips them and WhoIsWorking sees nothing from Codex. If Codex has never opened a folder before, it also asks whether to trust that folder.

## Install the Cursor hooks (experimental)

In Settings, Cursor section, choose **Install hooks…**, or:

```bash
build/WhoIsWorking.app/Contents/MacOS/WhoIsWorking hooks preview --agent cursor > /tmp/whoisworking-cursor-preview.json && diff -u ~/.cursor/hooks.json /tmp/whoisworking-cursor-preview.json
```

```bash
build/WhoIsWorking.app/Contents/MacOS/WhoIsWorking hooks install --agent cursor
```

This appends one entry (timeout 5 s) to 6 events in `~/.cursor/hooks.json`: `sessionStart`, `sessionEnd`, `postToolUse`, `postToolUseFailure`, `afterAgentThought` and `stop`. The guarantees are the same as for Claude Code. A new file starts with `"version": 1`. A file with hooks but no `version` is refused, because Cursor rejects it too. The Cursor app and `cursor-agent` read the same file, and Cursor reloads it on save.

## Install the OpenCode plugin

OpenCode 2 has no hooks file; it loads plugins. In Settings, OpenCode section, choose **Install plugin…**, or:

```bash
build/WhoIsWorking.app/Contents/MacOS/WhoIsWorking hooks install --agent opencode
```

This writes WhoIsWorking's own file, `~/.config/opencode/plugins/whoisworking.js`. Other plugins are not touched. If a file at that path was not written by WhoIsWorking, install refuses. The plugin uses only Node built-ins. It forwards session status to WhoIsWorking's socket and never answers a permission or changes anything. Restart running OpenCode sessions to load it. WhoIsWorking updates its plugin at launch when it changed.

## Install the Antigravity hooks (experimental)

In Settings, Antigravity section, choose **Install hooks…**, or:

```bash
build/WhoIsWorking.app/Contents/MacOS/WhoIsWorking hooks install --agent antigravity
```

This adds a hook group named `whoisworking` to `~/.gemini/config/hooks.json` for `SessionStart`, `PreInvocation`, `PostToolUse` and `Stop`. Other hook groups are not touched, and uninstall removes only that group. Antigravity allows comments in this file. WhoIsWorking cannot read a file with comments, so it refuses and changes nothing. The support is experimental: it follows Google's hook reference and has not yet been checked against a live Antigravity session.

## Uninstall the hooks

In Settings choose **Uninstall hooks…** in the agent's section, or:

```bash
build/WhoIsWorking.app/Contents/MacOS/WhoIsWorking hooks uninstall
```

```bash
build/WhoIsWorking.app/Contents/MacOS/WhoIsWorking hooks uninstall --agent codex
```

`--agent cursor`, `--agent antigravity` and `--agent opencode` work the same way. For OpenCode, uninstall deletes the plugin file.

This removes exactly the entries whose command contains `/WhoIsWorking/whoisworking-hook`. If WhoIsWorking was the only thing on an event, the event key is removed too, so the file returns to its earlier content. A backup is written first. For Antigravity the whole `whoisworking` hook group goes, and for OpenCode the plugin file is deleted (with a backup only if it was edited). The shared hook script is deleted once no agent's hooks use it.

## How it works

- `Sources/AgentCore` has no UI and is fully unit-tested: the session model and its six states, a pure reducer `(sessions, event) -> sessions`, the Claude Code, Codex, Cursor, OpenCode and Antigravity adapters, the OpenCode plugin source, the order-preserving JSON reader/writer used by the installer, the Unix socket server, the hook script, and session discovery.
- `Sources/WhoIsWorking` is the app: a borderless non-activating `NSPanel` above the menu bar, sized from `NSScreen.safeAreaInsets` and the auxiliary top areas, with SwiftUI inside. It is click-through while collapsed, opens after a 150 ms hover dwell and closes 250 ms after the cursor leaves.
- Two cases fire no hook: declining a permission prompt, and pressing Esc to interrupt. WhoIsWorking covers them with the session file: when its `status` turns `idle` after the last hook event, a session stuck in "needs approval" or "working" becomes idle. Without hooks, the file's `busy`, `waiting` and `idle` map to working, needs approval and idle.
- The hook script sends its parent pid. For Codex, WhoIsWorking walks up from it to the nearest `codex` process and ties the session to it, so the session is removed when that process exits.

## Codex: what is covered and what is not

Tested live with Codex CLI 0.163.0 and 0.171.0 (needs approval, approve, done; a failed turn; a daemon restart during an open approval, which Codex resumes with `SessionStart` source `resume`). Neither build has a hook event for failed model requests.

- Covered: working, needs approval (with the full command), done, interrupted, and turns that fail. Codex 0.163 fires no hook when a turn fails (for example an API error), so for a Codex session that has said "working" for 10 s without events, WhoIsWorking reads the end of its rollout (`transcript_path`) and shows the error or marks it done. Codex calls that file format unstable, so this is best effort.
- No "waiting for your reply" for Codex: Codex has no notification event for questions.
- Codex 0.163 runs the conversation in a shared `codex app-server` daemon that outlives the terminal ("Any running work continues"). WhoIsWorking ties those sessions to the daemon, so closing the CLI window does not remove them; Codex's `SessionEnd` (normal close, or 30 minutes idle with no client) does.
- Sessions started before WhoIsWorking: running Codex CLIs appear as placeholders until their next hook event. Sessions in the ChatGPT app appear only after their next hook event.
- One row per folder: a placeholder for a Codex CLI is hidden while a live Codex session exists in the same folder, so two CLIs in one folder show as one until the second sends an event.
- Names: Codex sessions are named after their folder. ChatGPT app projects can live in folders with generated names.
- "Open session" reaches the terminal only when the hook process still has the terminal app as an ancestor; daemon-hosted sessions usually do not, and WhoIsWorking beeps.

## Cursor, OpenCode and Antigravity: what is covered and what is not

- **Cursor** (app and `cursor-agent`, experimental): working, done, interrupted and errors. Cursor's events that see approvals are permission hooks, where an empty answer could block Cursor, so WhoIsWorking never registers them. Cursor sessions therefore never show "needs approval". Cursor reports tools only after they run, so a turn that only writes text shows nothing until it ends. Not yet checked against live Cursor payloads.
- **OpenCode 2**: working, needs approval (with the request), waiting for your answer to a question, done, interrupted and errors. Subagents never become rows of their own; their permission requests show on the session you started. Checked against OpenCode 2.0.14 with captured runs (reply, shell command, rejected permission, subagent) and with the plugin itself running inside OpenCode. Questions, failed runs, renames and deleted sessions follow OpenCode's event schemas and were not captured. OpenCode 1 plugins are not supported.
- **Antigravity** (experimental): working, done, background tasks still running, and errors. Antigravity's hooks have no approval event, so no "needs approval".
- None of the three gives WhoIsWorking an owning process yet. Their sessions go when the agent ends them, or after 15 minutes without events, and "Open session" cannot find their window. A session waiting for you (approval or an answer) stays up to 4 hours, because agents send nothing while they wait.

## How events arrive

- Hook events arrive on `~/Library/Application Support/WhoIsWorking/events.sock` (directory 0700, socket 0600), one JSON object per connection. WhoIsWorking also rescans session files when they change, every 3 seconds and after wake. Sessions whose process exited are removed.

"Open session" and row clicks bring the owning app to the front by walking the session process's parent chain to the first regular app (Terminal, iTerm2, VS Code, Cursor, Claude.app). They cannot select a specific terminal tab or a specific conversation inside Claude.app. Sessions inside tmux or screen have no app parent, so WhoIsWorking beeps instead.

## Debug switches (environment variables)

| Variable | Effect |
|---|---|
| `WHOISWORKING_DEBUG_STATE=/path/state.txt` | Writes a readable snapshot of all sessions on every change |
| `WHOISWORKING_LOG_EVENTS=1` | Saves every raw hook payload to `~/Library/Application Support/WhoIsWorking/event-log/` (useful for test fixtures) |
| `WHOISWORKING_SNAPSHOT=/dir` | Renders the collapsed and expanded panel to PNGs (no screen-recording permission needed) |
| `WHOISWORKING_FORCE=expanded` | Keeps the panel open |
| `WHOISWORKING_NO_NOTCH=1` | Uses the no-notch pill layout on a notched screen |
| `WHOISWORKING_OPEN_SETTINGS=1` | Opens Settings at launch |

## Project docs

- `docs/specs/`: what WhoIsWorking does as numbered requirements, each linked to its tests, plus draft specs for the next work
- `docs/plan.md`: research, plan and settled design
- `docs/spike/main.swift`: the throwaway spike the window behaviour came from
- `AGENTS.md`: guidance for coding agents, including the project skills, hooks and allowlists

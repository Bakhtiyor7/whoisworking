# Developing Who's Working

This page is for people who want to build, test or change Who's Working. At the end you will have a build from source running on your Mac and know where each part of the code lives. Start with [CONTRIBUTING.md](../CONTRIBUTING.md) for how changes are made and reviewed. Coding agents read [AGENTS.md](../AGENTS.md), which has the same facts in more detail.

## What you need

- macOS 15 or later on Apple silicon. The app is built and tested on macOS 27.2 on a MacBook Pro M4.
- Xcode 16 or later, or its command-line tools (Swift 6).

There are no third-party dependencies.

## Build and test

Run the tests:

```bash
swift test
```

Check that the specs and the tests name each other:

```bash
scripts/check-specs.sh
```

Check that no tracked file holds anything private and that every workflow action is pinned:

```bash
scripts/check-public.sh --tree-only
```

Check the Markdown links, the install command and the wording rules:

```bash
scripts/check-docs.sh
```

Build the app bundle into `build/WhoIsWorking.app`. It has no Dock icon (`LSUIElement`), is ad-hoc signed and is not notarized. Add `debug` for a debug build.

```bash
scripts/bundle.sh
```

## Run

```bash
open build/WhoIsWorking.app
```

Only one Who's Working can run at a time. A second copy finds the socket in use and says "Another copy of WhoIsWorking is already running."

## Update your own copy

```bash
scripts/update.sh
```

This runs the tests and the spec check, builds the release binary, stops the running Who's Working, rebuilds `build/WhoIsWorking.app` and opens it. Tests and the build run before anything is stopped, so a failure leaves the running copy alone. `--skip-tests` skips the first step.

To keep Who's Working in Applications, add `--install`. It copies the new build to `/Applications/WhoIsWorking.app` and opens that copy. Once it is there, every later `scripts/update.sh` updates it too. Open at login needs the copy in Applications.

```bash
scripts/update.sh --install
```

Connected agents keep working across updates: the hook script's path stays the same, and Who's Working rewrites the script at launch when it changed.

## Work on a copy of a hook file

The app's binary is also the command line for the hook installer. Pass `--settings` to work on a copy instead of your real file:

```bash
build/WhoIsWorking.app/Contents/MacOS/WhoIsWorking hooks preview --agent codex --settings /tmp/hooks-copy.json
```

The subcommands are `status`, `preview`, `install` and `uninstall`, and `--agent` takes `claude-code`, `codex`, `cursor`, `antigravity` or `opencode`.

## How it works

- `Sources/AgentCore` has no UI and holds all the logic. It is the only tested target: the session model and its six states, a pure reducer `(sessions, event) -> sessions`, the adapters for each agent, the OpenCode plugin source, the order-preserving JSON reader and writer the installer uses, the Unix socket server, the hook script, and session discovery.
- `Sources/WhoIsWorking` is the app: a borderless panel that does not take focus, above the menu bar, sized from the screen's safe area, with SwiftUI inside. It lets clicks through while collapsed, opens after the pointer rests on the notch for 150 ms, and closes 250 ms after it leaves.
- Two things fire no hook in Claude Code: declining a permission prompt, and pressing Esc to stop a turn. Who's Working covers them with the session file: when its `status` turns `idle` after the last hook event, a session stuck in "needs approval" or "working" becomes idle. Without hooks, the file's `busy`, `waiting` and `idle` map to working, needs approval and idle.
- The hook script sends its parent's process id. For Codex, Who's Working walks up from it to the nearest `codex` process and ties the session to it, so the session goes when that process exits.

### How events arrive

Hook events arrive on `~/Library/Application Support/WhoIsWorking/events.sock` (folder mode 0700, socket 0600), one message per connection. Who's Working also rescans Claude Code's session files when they change, every 3 seconds and after the Mac wakes. Sessions whose process exited are removed.

Clicking a session brings its app to the front by walking up the session process's parents to the first regular app (Terminal, iTerm2, VS Code, Cursor, Claude). It cannot select a terminal tab or a conversation inside the Claude app. Sessions inside tmux or screen have no app above them, so Who's Working beeps.

## Debug switches

These environment variables change what the app does, for checks without looking at the screen. Set them on the binary inside the bundle. [What Who's Working does on your Mac](trust.md#diagnostics) lists what each one writes.

| Variable | Effect |
|---|---|
| `WHOISWORKING_DEBUG_STATE=/path/state.txt` | Rewrites a readable snapshot of all sessions on every change |
| `WHOISWORKING_LOG_EVENTS=1` | Saves every raw hook payload to `~/Library/Application Support/WhoIsWorking/event-log/`, for test fixtures |
| `WHOISWORKING_SNAPSHOT=/dir` | Renders the collapsed and expanded panel to PNGs, with no screen-recording permission |
| `WHOISWORKING_FORCE=expanded` | Keeps the panel open |
| `WHOISWORKING_NO_NOTCH=1` | Uses the no-notch pill layout on a notched screen |
| `WHOISWORKING_OPEN_SETTINGS=1` | Opens Settings at launch |
| `WHOISWORKING_SETUP_PREVIEW=confirm:codex` | Shows the setup card with that agent's confirmation open (`installed:codex`: as if just installed from the card; `skipped:cursor`: with that agent skipped). Agents are `claudeCode`, `codex`, `cursor`, `openCode`, `antigravity` |
| `WHOISWORKING_CLAUDE_SESSIONS=/dir` | Reads Claude Code session files from another folder |
| `WHOISWORKING_FAKE_LATEST=/path.json` | Answers Check for Updates from a file (`WHOISWORKING_FAKE_STATUS`, default 200; 0 means no response) |
| `WHOISWORKING_SOCKET=/path` | Read by the hook script and the plugin only: sends events to another socket |

## Releases

Bump the version in `Resources/Info.plist` and write `docs/release-notes/X.Y.Z.md` in a commit. Then rehearse the release. The dry run tests, builds into `build/release/X.Y.Z-dry-run/`, checks the DMG, renders the install script and runs it against that DMG, and publishes nothing.

```bash
scripts/release.sh X.Y.Z --dry-run
```

How a release is built and published is in [spec 13](specs/13-distribution.md), [spec 16](specs/16-signing-and-ci.md) and [spec 20](specs/20-install-command.md).

## Switching from Perch

Who's Working was called Perch until 2026-11-22, before its first release. The rename changed the hook path, so Who's Working does not recognise hooks that a Perch build installed. With the old build still in `build/Perch.app`, remove them first (or use Uninstall hooks in Perch's Settings), then quit Perch:

```bash
build/Perch.app/Contents/MacOS/Perch hooks uninstall
```

```bash
build/Perch.app/Contents/MacOS/Perch hooks uninstall --agent codex
```

```bash
pkill -x Perch
```

Then run `scripts/update.sh`, connect the agents again from Who's Working and delete `build/Perch.app`. If launch at login was on in Perch, turn on Open at login in Who's Working.

## Project docs

- [`docs/specs/`](specs/README.md): what Who's Working does, as numbered requirements, each linked to its tests, and draft specs for the next work.
- [`docs/plan.md`](plan.md): the research and the settled design (sizes, hover timings, colours).
- [`docs/spike/main.swift`](spike/main.swift): the throwaway spike the window behaviour came from.
- [`AGENTS.md`](../AGENTS.md): guidance for coding agents, including the project skills, hooks and allowed commands.

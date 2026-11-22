# AGENTS.md

Guidance for coding agents (Codex, Claude Code and others) working in this repository. `CLAUDE.md` imports this file, so edit this one.

## What this is

WhoIsWorking (shown to users as "Who's Working"; called Perch until 2026-11-22, and the repo folder is still `perch`) is a macOS notch app that shows the status of Claude Code and Codex sessions on this Mac. v1 is status only: it never approves or denies anything, and the hook script never makes a decision. `README.md` is the user-facing description of behaviour (install steps, Codex coverage and gaps); update it when behaviour changes. `docs/plan.md` holds the research and the settled design (sizes, hover timings, colours). `docs/specs/` holds the requirements; see Specs below.

## Commands

Swift Package (tools 6.0, macOS 15+), no third-party dependencies, no linter or formatter config.

```bash
swift test                                                         # all tests (~1 s after build)
swift test --filter ReducerTests                                   # one suite, by struct name
swift test --filter ReducerTests/permissionRequestMeansNeedsApproval   # one test
swift build                                                        # debug build of both targets
scripts/check-specs.sh                                             # specs and tests name each other
scripts/bundle.sh                                                  # release build -> build/WhoIsWorking.app (ad-hoc signed)
scripts/bundle.sh debug                                            # same, debug configuration
scripts/update.sh [--skip-tests]                                   # test, build, stop the running WhoIsWorking, rebundle, reopen
open build/WhoIsWorking.app
```

`--filter` matches on the Swift type and function names, not the `@Suite("…")` display names. It is a substring match, so `ReducerTests` also runs `CodexReducerTests`.

The same binary is a CLI for the hook installer. Use `--settings <path>` to work on a copy instead of the real `~/.claude/settings.json` or `~/.codex/hooks.json`:

```bash
build/WhoIsWorking.app/Contents/MacOS/WhoIsWorking hooks status|preview|install|uninstall [--agent claude-code|codex] [--settings <path>]
```

Only one WhoIsWorking can run at a time: a second copy finds the socket live and reports "Another copy of WhoIsWorking is already running."

### Checking the app without looking at the screen

The `WhoIsWorking` target has no tests. Verify UI and end-to-end changes with these environment variables (set them on the binary inside the bundle):

| Variable | Effect |
|---|---|
| `WHOISWORKING_DEBUG_STATE=/path/state.txt` | Rewrites a readable snapshot of all sessions on every state change |
| `WHOISWORKING_SNAPSHOT=/dir` | Renders the collapsed and expanded panel to PNGs |
| `WHOISWORKING_FORCE=expanded` | Keeps the panel open |
| `WHOISWORKING_NO_NOTCH=1` | Uses the no-notch pill layout |
| `WHOISWORKING_OPEN_SETTINGS=1` | Opens Settings at launch |
| `WHOISWORKING_LOG_EVENTS=1` | Saves every raw hook payload to `~/Library/Application Support/WhoIsWorking/event-log/` |
| `WHOISWORKING_CLAUDE_SESSIONS=/dir` | Reads Claude session files from another folder (an empty one shows the empty state) |
| `WHOISWORKING_SOCKET=/path` | Read by the hook script only: sends events to another socket |

## Architecture

Two targets. `AgentCore` has no UI and holds all logic; it is the only tested target. `WhoIsWorking` is the AppKit/SwiftUI shell and should stay thin: new behaviour goes into `AgentCore` behind a pure function or an injectable dependency, then gets wired in `SessionStore`.

### Event flow

```
agent hook -> whoisworking-hook (sh + nc) -> events.sock -> HookMessage.parse -> adapter -> AgentEvent ┐
~/.claude/sessions/*.json -> ClaudeSessionScanner -> discoveryEvents() ------------------------┤
process table -> CodexProcesses.discoveryEvents() (placeholders) ------------------------------┼-> StoreEvent -> reduce() -> SessionsState -> NotchSummary -> views
Codex rollout tail -> CodexRollout.endOfQuietTurn() --------------------------------------------┤
3 s timer / directory watcher / wake -> pruneOrphans ------------------------------------------┘
```

- **Wire format** (`HookMessage`, in `ClaudeCodeAdapter.swift`): one message per socket connection, a header line `whoisworking1 <agent> ppid=<pid>` followed by the agent's raw hook JSON. A bare JSON object with no header is treated as Claude Code. The socket handler runs before the connection is closed, on purpose: the hook process is still alive then, so its parent chain can be walked.
- **Adapters** (`ClaudeCodeAdapter`, `CodexAdapter`) map agent-specific hook JSON to the shared `AgentEvent.Kind`. Unknown events return nil and are dropped. Adding an agent means a new adapter, a `HookTarget`, and a case in `HookMessage.event`.
- **Reducer** (`reduce` in `Reducer.swift`) is the single place session state changes: a pure `(SessionsState, StoreEvent) -> SessionsState`. `SessionStore` (app target) only collects inputs and calls it. The rules it enforces, each covered by tests:
  - Events older than a session's newest applied event are ignored.
  - Ended session ids are remembered so late events cannot recreate them; only `sessionStarted` clears that.
  - Subagent start/stop and subagent tool events never create a top-level session and never change its state, only the activity line. A permission request raised inside a subagent still moves the session to `needsApproval`.
  - While a session is in `needsApproval`, only the finish of the same tool (name and detail) resolves it.
  - Hook events win over the session file once `hasHookEvents` is true. The file then only fills gaps the hooks leave, and only when its status is newer than the state by `fileStatusMargin`: `idle` moves `needsApproval`/`working` to `idle` (a declined permission prompt and an Esc interrupt fire no hook), and `busy` moves `needsApproval` back to `working`.
- **Six states** (`SessionState`): `needsApproval`, `waitingForReply` and `error` are the "needs you" states that make the wings appear. `doneUnseen` becomes `idle` when the user sees it in the expanded panel (`.viewed`).

### Session lifetime and process ownership

Sessions are removed when their owning process dies (`processExited`), on `SessionEnd`, or after 15 minutes of silence with no known pid.

- Claude Code: the pid comes from `~/.claude/sessions/<pid>.json`. `ProcessProbe.isAlive` compares start times to reject reused pids.
- Codex has no session files. The hook's `ppid` is walked up to the nearest process named `codex` (often the shared `codex app-server` daemon, which outlives the terminal). Interactive Codex CLIs found in the process table before any hook event become placeholder sessions with id `process:<pid>`; a real session with the same pid, or the same agent and folder, replaces the placeholder.
- Codex 0.163 fires no hook when a turn fails, so a Codex session that has been `working` and silent for 10 s gets the tail of its rollout file read (`CodexRollout`). The format is documented by Codex as unstable: unknown shapes must be ignored, not treated as errors.

`ProcessProbe` is a struct of closures; tests build one with fake lookups, the app uses `ProcessProbe.system`.

### Hook installer

`HookInstaller` edits files it does not own (`~/.claude/settings.json`, `~/.codex/hooks.json`), which other tools also write hooks into. Its guarantees are the contract, and `HookInstallerTests` / `CodexHookInstallerTests` pin them:

- Other tools' entries are never changed or reordered. This is why the installer uses `OrderedJSON.swift` (`JSONValue`, keeps key order and number spelling, writes like `JSON.stringify(v, null, 2)`) instead of `JSONSerialization`.
- A timestamped backup is written beside the file before every change.
- Install is idempotent; uninstall removes exactly the entries whose command contains `/WhoIsWorking/whoisworking-hook` and drops event keys it leaves empty.
- Invalid JSON or an unexpected shape means refuse and change nothing.

The hook script lives in `HookScript.contents` (`Ingest.swift`) and is written to `~/Library/Application Support/WhoIsWorking/whoisworking-hook`. It must use only `/bin/sh` and `/usr/bin/nc`, print nothing and always exit 0, so it can never block or slow an agent, also when WhoIsWorking is not running. The app rewrites the installed copy at launch when it differs from `contents`.

## Tests

Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`), not XCTest. Reducer tests build event lists with small helpers and fold them through `reduce` from fixed dates; nothing reads the clock.

Fixtures are plain files under `Tests/Fixtures`, located through `#filePath` (`fixturesDir` in `ClaudeCodeAdapterTests.swift`), so there is no resource bundle. `Tests/Fixtures/README.md` records which fixtures were captured from real sessions and which were constructed from docs; keep it accurate when adding any. To capture real payloads, run WhoIsWorking with `WHOISWORKING_LOG_EVENTS=1` and anonymize the files from the event log.

## Specs

`docs/specs/` states what WhoIsWorking does as numbered requirements (`RED-03`), each naming the tests that prove it. `docs/specs/README.md` has the index and the format. Specs 01–08 describe what is built; 10–13 are drafts for the next work (design for Settings, empty state and pill; Cursor; OpenCode; distribution).

The order of work is spec, then failing test, then code:

1. Add or edit the requirement in the spec. For a draft spec, settle its open questions with the user first.
2. Write the failing test and name it on the requirement's `Tests:` line (`Type/function`).
3. Write the code, then run `swift test` and `scripts/check-specs.sh`.

`scripts/check-specs.sh` fails when an id repeats, a `Tests:` line names a missing test, an implemented requirement has no `Tests:` or `Verified by:` line, or a test is named by no spec. The hook installer and hook script requirements (`06`, `05`) are contracts: a change that would weaken one stops and goes to the user.

## Design

Visual and interaction work follows the `whoisworking-design` skill: Mobbin for references, a Claude Design canvas for two or three directions the user picks from, then the Apple HIG and Liquid Glass skills to review the chosen one before building. Rules that hold for every screen:

- The panel body is pure black with the notch's corner curve. Glass is only for controls inside the expanded panel.
- One colour per state, always with an icon or shape: amber needs you, green done, red error, neutral working.
- The package supports macOS 15, so Liquid Glass APIs sit behind `#available(macOS 26, *)` with a plain fallback.

Mobbin, Liquid Glass (`liquid-glass`) and Apple HIG (`apple-hig-designer`) come from the user's plugins and personal skills, not from this repo. If one is missing in a session, say so and carry on; never invent a reference or a link.

To check the UI, run the debug binary directly (`.build/debug/WhoIsWorking` with the `WHOISWORKING_*` variables); the `whoisworking-verify-ui` skill has the steps. Do not run `scripts/bundle.sh` just to check something: it replaces `build/WhoIsWorking.app`, which may be the copy that is running. `scripts/update.sh` also stops the running WhoIsWorking, so run it only when the user asks.

## Agent setup

| What | Where | Read by |
|---|---|---|
| Instructions | `AGENTS.md` (`CLAUDE.md` imports it) | Claude Code, Codex, Cursor, OpenCode |
| Skills: `whoisworking-spec`, `whoisworking-verify-ui`, `whoisworking-design`, `whoisworking-fixtures` | `.agents/skills/` (`.claude/skills` is a symlink to it) | all four |
| Subagents: `spec-reviewer`, `design-reviewer` | `.claude/agents/` | Claude Code |
| Allowed commands, plugins, hooks | `.claude/settings.json` | Claude Code |
| Allowed commands | `.codex/rules/whoisworking.rules` (trusted projects only), `.cursor/cli.json`, `opencode.json` | Codex, cursor-agent, OpenCode |
| CI | `.github/workflows/ci.yml` | GitHub Actions |

Claude Code hooks, in `scripts/agent/`:

- `check-swift.sh` (Stop): when sources, tests or specs changed since the last passing run, it runs `swift build`, `swift test` and `scripts/check-specs.sh`, and sends failures back to the agent.
- `guard-hooks-cli.sh` (PreToolUse, Bash): blocks `WhoIsWorking hooks install|uninstall` without `--settings`, so the user's real hook files are never edited from an agent session.

Other agents have no such hooks here: run the same three commands before reporting work as done, and always pass `--settings <copy>` to the hooks CLI.

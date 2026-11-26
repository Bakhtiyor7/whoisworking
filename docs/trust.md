# What Who's Working does on your Mac

This page is for anyone deciding whether to install Who's Working, or checking it after they did. It lists every file the app reads and writes, its one network request, and what it never does. Each row says how to see it on your own Mac, or which test pins it.

A test here is a tripwire: it fails when the code changes, so the change shows up in review. A test cannot prove that something never happens. Neither can a list like this one. What it gives you is a short list of things to check, and the source to check them against.

The commands below assume the app is in `/Applications`. Each one only reads.

## Three checks that take under a minute

1. Read the hook script, which Claude Code, Codex, Cursor and Antigravity run because of Who's Working. (OpenCode runs a plugin instead; see [What the hook script and the plugin do](#what-the-hook-script-and-the-plugin-do).) It is under 20 lines of `/bin/sh` and sends the event to a socket on this Mac with `/usr/bin/nc`. The file exists once you have connected an agent.

```bash
cat ~/Library/Application\ Support/WhoIsWorking/whoisworking-hook
```

2. Before you connect an agent, see exactly what would change in its hook file. This prints a diff and writes nothing. If the agent has no hook file yet, `diff` says the file does not exist; Who's Working would then create it with only its own entries. For another agent, replace `codex` with `cursor` or `antigravity`, or drop `--agent codex` for Claude Code, and use that agent's file from [Files it changes](#files-it-changes).

```bash
diff -u ~/.codex/hooks.json <(/Applications/WhoIsWorking.app/Contents/MacOS/WhoIsWorking hooks preview --agent codex)
```

3. See that the app claims no entitlements and declares no use of protected data. The first command prints only the app's path. The second prints nothing: the app names no use of the camera, microphone, contacts, location or similar data, which macOS requires before it asks you. These two show what the app declares. That it uses no Accessibility or Screen Recording API is pinned by a test instead, because an app outside the sandbox needs no entitlement for those; see [What it never does](#what-it-never-does).

```bash
codesign -d --entitlements - /Applications/WhoIsWorking.app
```

```bash
plutil -p /Applications/WhoIsWorking.app/Contents/Info.plist | grep UsageDescription
```

## Files it reads

| What | Why | How to check |
|---|---|---|
| `~/.claude/sessions/*.json` | Claude Code writes one file per running session. Who's Working reads the process id, folder, name and status, so sessions show up before their first hook event. | `ls ~/.claude/sessions` |
| Each agent's hook file (see [Files it changes](#files-it-changes)) | To show in Settings and in the setup card whether that agent is connected. | The Settings window shows the status of each one. |
| The folders `~/.claude`, `~/.codex`, `~/.cursor`, `~/.config/opencode`, `~/.gemini` | Only whether each exists, to offer that agent in the setup card. Nothing inside is read for this. | `SetupPromptTests` |
| The end of a Codex session log (at most 256 KB, the path Codex sends as `transcript_path`) | Codex sends no hook event when a turn fails. When a Codex session has said "working" for 10 seconds without an event, Who's Working reads the end of its log to see whether the turn ended. Only a regular file is read. | `CodexRolloutTests` |
| The process list | To tie a session to the program that runs it, remove the session when that program quits, and bring its app to the front when you click it. Who's Working reads process ids, names, parents, start times, working folders and, for Codex, the command-line arguments of your own processes. | `ProcessProbe` in [`Sources/AgentCore/Ingest.swift`](../Sources/AgentCore/Ingest.swift) |
| Its own preferences | See [Files it creates](#files-it-creates). | |

## Files it creates

| File | When | How to check |
|---|---|---|
| `~/Library/Application Support/WhoIsWorking/` | At launch, or when the hook script is first written. At launch the app makes it readable only by you (mode 0700). | `ls -la ~/Library/Application\ Support/WhoIsWorking` |
| `~/Library/Application Support/WhoIsWorking/events.sock` | At launch; removed when the app quits. Only your own processes can connect (mode 0600). Any program running as you can send it an event, and Who's Working only shows what it receives. | The same command. Test: `IngestTests` |
| `~/Library/Application Support/WhoIsWorking/whoisworking-hook` | When you connect Claude Code, Codex, Cursor or Antigravity. Rewritten at launch if it differs from the app's copy. Deleted when no agent's hook file uses it any more. | The first quick check. Test: `HooksCommandTests` |
| `~/.config/opencode/plugins/whoisworking.js` | When you connect OpenCode. Replaced at launch, with a backup, if it differs from the app's copy. Deleted when you disconnect OpenCode. | `cat ~/.config/opencode/plugins/whoisworking.js`. Test: `OpenCodePluginInstallerTests` |
| `~/Library/Preferences/io.github.bakhtiyor7.WhoIsWorking.plist` | When you skip an agent or click Later on the setup card. Who's Working saves `setupSkippedAgents` and `setupDismissedAt`, and reads `logEvents` (see [Diagnostics](#diagnostics)). | `defaults read io.github.bakhtiyor7.WhoIsWorking` |
| A login item | Only when you turn on Open at login in Settings. Turning it off removes it. | It appears among the login items in System Settings. |

Who's Working never deletes a backup it keeps. The one exception: if another tool changed the file between Who's Working reading and writing it, Who's Working writes nothing and deletes the backup it had just made. Backups hold your file as it was, so you can delete them yourself once you no longer need them.

## Files it changes

Who's Working changes an agent's file only when you click Connect, Install or Uninstall for that agent, or run `WhoIsWorking hooks install` or `uninstall` yourself. The OpenCode plugin is the one other case: at launch, an outdated copy is replaced with this version's, after a backup. Before it changes a file that already exists, it writes a backup beside it, readable only by you (mode 0600). Other tools' entries are never changed or reordered. If the file is not valid JSON, or not in the shape the agent documents, nothing is written.

| Agent | File | Backup |
|---|---|---|
| Claude Code | `~/.claude/settings.json` | `~/.claude/settings.json.whoisworking-backup-YYYYMMDD-HHMMSS` |
| Codex | `~/.codex/hooks.json` | `~/.codex/hooks.json.whoisworking-backup-YYYYMMDD-HHMMSS` |
| Cursor | `~/.cursor/hooks.json` | `~/.cursor/hooks.json.whoisworking-backup-YYYYMMDD-HHMMSS` |
| Antigravity | `~/.gemini/config/hooks.json` | `~/.gemini/config/hooks.json.whoisworking-backup-YYYYMMDD-HHMMSS` |
| OpenCode | `~/.config/opencode/plugins/whoisworking.js` (its own file) | `~/.config/opencode/plugins/whoisworking.js.whoisworking-backup-YYYYMMDD-HHMMSS`, only when the file had been edited or an older version is replaced |

Connecting adds one entry per event, each running the hook script. Disconnecting removes exactly the entries whose command contains `/WhoIsWorking/whoisworking-hook`, and drops an event key that it leaves empty. Your own later edits to the file stay.

To see the change before you make it, use the second quick check. To see what is installed now:

```bash
/Applications/WhoIsWorking.app/Contents/MacOS/WhoIsWorking hooks status --agent codex
```

Tests: `HookInstallerTests`, `CodexHookInstallerTests`, `CursorHookInstallerTests`, `AntigravityHookInstallerTests`, `OpenCodePluginInstallerTests`. `TrustPageTests/everyFileInstallAndUninstallTouchIsListed` connects and disconnects every agent in a temporary home folder and fails if a file it touched is missing from this page.

## What the hook script and the plugin do

When an agent runs the hook script, the script reads the event the agent passes it, writes it to `events.sock` with `/usr/bin/nc`, and exits. It prints nothing, makes no decision and always exits with success, so it cannot block or slow the agent. When Who's Working is not running, the script reads the event and drops it. The OpenCode plugin does the same from inside OpenCode, with Node's built-in `node:net`.

An event can hold your prompts, file paths and the commands the agent runs. Who's Working keeps what it needs to show the session (its state and a short activity line) in memory only. All of it is gone when the app quits. Nothing is written to disk unless you turn on a diagnostic below.

Neither the script nor the plugin names a host or a web address, and the script runs no program but `cat` and `/usr/bin/nc`.

Tests: `IngestTests`, `SourcePolicyTests/theHookScriptAndPluginNameNoHost`. Source: `HookScript` in [`Sources/AgentCore/Ingest.swift`](../Sources/AgentCore/Ingest.swift) and `OpenCodePlugin` in [`Sources/AgentCore/OpenCode.swift`](../Sources/AgentCore/OpenCode.swift).

## The one network request

Who's Working makes one network request, and only when you click Check for Updates in Settings. Nothing runs in the background.

| | |
|---|---|
| Address | `https://api.github.com/repos/Bakhtiyor7/whoisworking-releases/releases/latest` |
| What it reads | Only the version number of the latest release. Any link in the answer is ignored. |
| What GitHub sees | Your IP address, the time, and `WhoIsWorking/<version>` as the user agent. No cookies, no sign-in, no saved credentials. If GitHub answers with a redirect, macOS follows it. |
| Download | Clicking Download opens `https://github.com/Bakhtiyor7/whoisworking-releases/releases/tag/vX.Y.Z` in your browser. The app downloads nothing itself. |

Tests: `SourcePolicyTests/onlyTheUpdateCheckUsesTheNetwork` fails if networking code appears in any other file. `TrustPageTests/theNetworkHostIsTheOneTheUpdateCheckUses` fails if the address changes and this page does not. Source: [`Sources/WhoIsWorking/Updates.swift`](../Sources/WhoIsWorking/Updates.swift).

A list of open connections at one moment would not prove that nothing else is ever sent, so this page does not offer one. An outgoing firewall that logs every connection over days is a real check, if you use one.

## What else it asks macOS to do

- Open the release page in your browser when you click Download.
- Bring a session's app to the front when you click that session.

No source file starts another program, and only [`Updates.swift`](../Sources/WhoIsWorking/Updates.swift) and [`AppFocuser.swift`](../Sources/WhoIsWorking/AppFocuser.swift) ask macOS to open something. Test: `SourcePolicyTests/onlyTwoFilesAskMacOSToOpenSomething`.

## What it never does

| Never | How to check |
|---|---|
| Sends usage data or crash reports | The network section above, and `SourcePolicyTests/onlyTheUpdateCheckUsesTheNetwork` |
| Asks you for an account or a sign-in | There is none in the app. |
| Uses the network in the background | The network section above |
| Approves, denies or answers anything on an agent's behalf | The hook script exits without output. Cursor and Antigravity events that wait for an answer are never connected. Tests: `IngestTests`, `CursorHookInstallerTests`, `AntigravityHookInstallerTests` |
| Asks for Accessibility, Screen Recording or Full Disk Access | No source file uses the APIs behind Accessibility, Screen Recording or Input Monitoring. Test: `SourcePolicyTests/noSourceAsksForAccessibilityOrScreenRecording`. An app cannot ask for Full Disk Access; you would add it yourself in System Settings, and Who's Working reads nothing that needs it. |
| Uses a third-party library | `Package.swift` has no dependency. Test: `SourcePolicyTests/thePackageHasNoDependenciesOrPlugins` |

## Diagnostics

These are off unless you turn them on. They exist for building and testing Who's Working. Each one that writes a file writes it where you say, except the event log.

| Switch | What it does |
|---|---|
| `logEvents` preference, or `WHOISWORKING_LOG_EVENTS=1` | Saves every event Who's Working receives, prompts and commands included, as a file in `~/Library/Application Support/WhoIsWorking/event-log/`. Who's Working never deletes them; delete the folder when you are done. |
| `WHOISWORKING_DEBUG_STATE=/path/state.txt` | Rewrites a text file with every session's state, title and activity line on each change. |
| `WHOISWORKING_SNAPSHOT=/folder` | Saves pictures of the notch panel to that folder. |
| `WHOISWORKING_FORCE=expanded` | Keeps the panel open. |
| `WHOISWORKING_NO_NOTCH=1` | Uses the layout for screens without a notch. |
| `WHOISWORKING_OPEN_SETTINGS=1` | Opens Settings at launch. |
| `WHOISWORKING_SETUP_PREVIEW=confirm:codex` | Shows a state of the setup card. Its buttons write nothing. |
| `WHOISWORKING_CLAUDE_SESSIONS=/folder` | Reads Claude Code session files from another folder. |
| `WHOISWORKING_FAKE_LATEST=/path.json`, `WHOISWORKING_FAKE_STATUS=200` | Answers Check for Updates from a file instead of the network. |
| `WHOISWORKING_SOCKET=/path` | Read by the hook script and the plugin: sends events to another socket. |

These switches also work in the released app. A program that can set them already runs as you and could do the same harm without them. [`SECURITY.md`](../SECURITY.md) lists this under Known limits.

Test: `TrustPageTests/everyDebugVariableInTheSourceIsListed` fails if the code reads a `WHOISWORKING_` variable this table does not list.

## Remove everything

1. In Settings, click Uninstall for each connected agent. This removes Who's Working's entries and the hook script.
2. Quit Who's Working from Settings and move `/Applications/WhoIsWorking.app` to the Trash.
3. Delete its folder and preferences. The backups beside your agents' files stay until you delete them.

```bash
rm -rf ~/Library/Application\ Support/WhoIsWorking
```

```bash
defaults delete io.github.bakhtiyor7.WhoIsWorking
```

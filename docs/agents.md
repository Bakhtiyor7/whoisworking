# Agents: what Who's Working shows for each

This page is for people who use Who's Working with one or more coding agents. For each agent it says what you will see in the notch, what you will not, and how to connect and disconnect it. At the end you will know which states to expect and how to undo a connection.

Who's Working learns about a session through hooks: commands an agent runs when something happens, such as a tool call or the end of a turn. Connecting an agent adds Who's Working's hook to that agent's hook file. OpenCode has no hook file, so Who's Working adds a plugin file instead. [What Who's Working does on your Mac](trust.md) lists every file involved.

## At a glance

| Agent | Working | Needs approval | Waiting for your reply | Done | Error | Status |
|---|---|---|---|---|---|---|
| Claude Code | Yes | Yes | Yes | Yes | Yes | Tested live |
| Codex | Yes | Yes | No | Yes | Yes | Tested live with Codex CLI 0.163.0 and 0.171.0 |
| OpenCode 2 | Yes | Yes | Yes | Yes | Yes | Checked against OpenCode 2.0.14 |
| Cursor | Yes | No | No | Yes | Yes | Experimental, not yet checked against live Cursor events |
| Antigravity | Yes | No | No | Yes | Yes | Experimental, not yet checked against a live Antigravity session |

## Connect an agent

The easiest way is the notch. Until an agent is connected, a plug and "Set up" appear beside the notch. Hover there and the "Finish setup" card lists the agents found on this Mac (Claude Code and Codex if it finds none).

1. Click **Connect** beside an agent. The card shows which file will change.
2. Click **Install**. Who's Working backs up the file, if there is one, then adds its hook.
3. Do what the row says is left, such as restarting running sessions or, for Codex, trusting the hooks.

You can also connect each agent in Settings, in that agent's section, with **Install hooks…** (**Install plugin…** for OpenCode). Opening Who's Working again while it runs shows Settings.

To see the change before you make it, run the preview for that agent. It prints the diff and writes nothing. If the agent has no hook file yet, `diff` says the file does not exist; Who's Working would then create it with only its own entries.

```bash
diff -u ~/.claude/settings.json <(/Applications/WhoIsWorking.app/Contents/MacOS/WhoIsWorking hooks preview)
```

Each agent's section below has its own preview command.

## Disconnect an agent

In Settings, click **Uninstall hooks…** (**Uninstall plugin…** for OpenCode) in that agent's section. Who's Working backs up the file, then removes exactly its own entries: those whose command contains `/WhoIsWorking/whoisworking-hook`. If Who's Working was the only hook on an event, that event's key goes too, so the file returns to how it was. Your own later edits stay. The hook script is deleted once no agent uses it.

From a terminal, the same thing for Claude Code:

```bash
/Applications/WhoIsWorking.app/Contents/MacOS/WhoIsWorking hooks uninstall
```

For another agent, add `--agent codex`, `--agent cursor`, `--agent antigravity` or `--agent opencode`.

## Claude Code

Who's Working adds one entry to 13 hook events in `~/.claude/settings.json`. New Claude Code sessions pick up the hooks. Sessions that were already running may need a restart.

```bash
diff -u ~/.claude/settings.json <(/Applications/WhoIsWorking.app/Contents/MacOS/WhoIsWorking hooks preview)
```

What you see:

- Sessions that were already running appear within a few seconds, before any hook event, because Claude Code writes a file per session in `~/.claude/sessions/`.
- Working, needs approval, waiting for your reply, done and errors.
- Declining a permission prompt and pressing Esc to stop a turn fire no hook. Who's Working sees them in the session file instead, so the session moves on within a few seconds.

## Codex

Who's Working adds one entry to 10 events in `~/.codex/hooks.json`, with a 3-second timeout, the most Codex allows for some of them.

```bash
diff -u ~/.codex/hooks.json <(/Applications/WhoIsWorking.app/Contents/MacOS/WhoIsWorking hooks preview --agent codex)
```

Codex needs one more step: it asks you to trust new hooks before it runs them. In the Codex CLI, type `/hooks` and trust the Who's Working entries. In the Codex app, use **Review hooks**, or Settings › Hooks. Until then Codex skips the hooks and Who's Working sees nothing from Codex. If Codex has never opened a folder before, it also asks whether to trust that folder.

What you see:

- Working, needs approval (with the full command), done, stopped, and turns that fail.
- Codex fires no hook when a turn fails, for example on an API error. When a Codex session has said "working" for 10 seconds without an event, Who's Working reads the end of its session log and shows the error or marks the turn done. Codex calls that log format unstable, so this is best effort.
- Running Codex CLIs appear as "Running · no live status yet" until their first hook event. Sessions in the Codex app appear only after their next hook event.

What you do not see:

- "Waiting for your reply": Codex has no event for a question.
- Two Codex CLIs in the same folder show as one row until the second sends an event.

Good to know:

- Codex runs conversations in a shared `codex app-server` process that outlives the terminal. Who's Working ties those sessions to it, so closing the terminal window does not remove them. Codex's own session end does: a normal close, or 30 minutes idle with no client.
- Codex sessions are named after their folder. Codex app projects can live in folders with generated names.
- Clicking a session reaches the terminal only when that terminal started the Codex process. Sessions hosted by `codex app-server` usually were not, and Who's Working beeps.

## OpenCode

OpenCode 2 has no hook file; it loads plugins. Who's Working writes its own plugin file, `~/.config/opencode/plugins/whoisworking.js`, and touches no other plugin. If a file at that path was not written by Who's Working, it refuses. The plugin uses only Node's built-in modules, forwards session status to Who's Working, and never answers a permission or changes anything. Restart running OpenCode sessions to load it. Who's Working updates its plugin at launch when it changed.

To read the plugin Who's Working would write, without writing it:

```bash
/Applications/WhoIsWorking.app/Contents/MacOS/WhoIsWorking hooks preview --agent opencode
```

What you see:

- Working, needs approval (with the request), waiting for your answer to a question, done, stopped and errors.
- Subagents never become rows of their own. Their permission requests show on the session you started.

Checked against OpenCode 2.0.14 with captured runs (a reply, a shell command, a rejected permission, a subagent) and with the plugin running inside OpenCode. Questions, failed runs, renames and deleted sessions follow OpenCode's event schemas and were not captured. OpenCode 1 plugins are not supported.

## Cursor (experimental)

Who's Working adds one entry, with a 5-second timeout, to 6 events in `~/.cursor/hooks.json`: `sessionStart`, `sessionEnd`, `postToolUse`, `postToolUseFailure`, `afterAgentThought` and `stop`. A new file starts with `"version": 1`. A file with hooks but no `version` is refused, because Cursor rejects it too. The Cursor app and `cursor-agent` read the same file, and Cursor reloads it when it changes.

```bash
diff -u ~/.cursor/hooks.json <(/Applications/WhoIsWorking.app/Contents/MacOS/WhoIsWorking hooks preview --agent cursor)
```

What you see: working, done, stopped and errors.

What you do not see:

- "Needs approval". Cursor's events that see approvals are permission hooks, where an empty answer could block Cursor, so Who's Working never connects them.
- Anything during a turn that only writes text. Cursor reports tools only after they run, so such a turn shows nothing until it ends.

## Antigravity (experimental)

Who's Working adds a hook group named `whoisworking` to `~/.gemini/config/hooks.json`, for `SessionStart`, `PreInvocation`, `PostToolUse` and `Stop`. Other hook groups are not touched, and disconnecting removes only that group. Antigravity allows comments in this file. Who's Working cannot read a file with comments, so it refuses and changes nothing.

```bash
diff -u ~/.gemini/config/hooks.json <(/Applications/WhoIsWorking.app/Contents/MacOS/WhoIsWorking hooks preview --agent antigravity)
```

What you see: working, done, background tasks still running, and errors.

What you do not see: "needs approval". Antigravity's hooks have no approval event.

The support follows Google's hook reference and has not yet been checked against a live Antigravity session.

## Cursor, OpenCode and Antigravity: when sessions go away

None of the three tells Who's Working which process runs a session. Their sessions go when the agent ends them, or after 15 minutes without events. A session waiting for you (an approval or an answer) stays up to 4 hours, because agents send nothing while they wait. Clicking one of these sessions cannot find its window.

## Clicking a session

Clicking a session brings its app to the front: Terminal, iTerm2, VS Code, Cursor or Claude. Who's Working finds the app by walking up from the session's process to the first regular app. It cannot pick a terminal tab or a conversation inside the Claude app. Sessions inside tmux or screen have no app above them, so Who's Working beeps instead.

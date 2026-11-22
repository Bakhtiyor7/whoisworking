# 08 Notch UI

Status: implemented
Code: `Sources/WhoIsWorking/` (`NotchPanel.swift`, `NotchViews.swift`, `SessionStore.swift`, `AppFocuser.swift`, `Settings.swift`, `main.swift`)

## Purpose

The visible app. The `WhoIsWorking` target has no unit tests and stays thin: it lays out what `AgentCore` computes. These requirements are checked by rendering snapshots (`WHOISWORKING_SNAPSHOT`) and reading the debug state file (`WHOISWORKING_DEBUG_STATE`); the `whoisworking-verify-ui` skill has the steps. Design source: `docs/plan.md` §5 and §5a.

## Requirements

### UI-01 Hidden by default

While every session is idle or working, nothing is drawn.

Verified by: snapshot (collapsed, sessions idle or working)

### UI-02 Wings

When a session needs the user, wings appear 70 pt each side of the notch: an amber dot and the count on the left, the longest wait on the right.

Verified by: snapshot (collapsed, one session in needs approval)

### UI-03 Expanded panel

The expanded panel is 560 pt wide with sections Needs you, Working, Done. A Needs you card shows the session name, the request title, the full command or text and an "Open session" button. Other sessions are 44 pt rows with a state icon, name, one-line detail and elapsed time.

When a session appears as a row or a Needs you card, its 24 pt badge shows the matching Claude Code, Codex, Cursor, OpenCode or Antigravity icon in its original colors. The icons are bundled for offline use. VoiceOver identifies each agent by its full name.

Verified by: color snapshot of Claude Code and Codex in both session rows and Needs you cards; snapshot on 2026-11-22 with an OpenCode Needs you card, a Cursor row and an Antigravity row (synthetic events)

### UI-04 Panel body

The body is pure black with the notch's corner curve, so it reads as the notch growing. Glass is allowed only on controls inside the expanded panel, never on the body.

Verified by: snapshot (`WHOISWORKING_FORCE=expanded`)

### UI-05 State colours and shapes

Amber for needs you, green for done, red for error, neutral for working. Every colour is paired with an icon or shape, so the state reads without colour.

Verified by: snapshot (`WHOISWORKING_FORCE=expanded`, one session per state)

### UI-06 Hover

The panel opens after the cursor has rested 150 ms on the notch or wings, and closes 250 ms after the cursor leaves the panel.

Verified by: manual check on the notch

### UI-07 Window

A borderless, non-activating panel three levels above the main menu, sized from the screen's safe area and auxiliary top areas, present on all Spaces and over full-screen apps. It is click-through while collapsed.

Verified by: manual check on the notch

### UI-08 No notch

On a screen without a notch, nothing is drawn until something needs the user; then a pill appears at the top centre with the same content as the wings.

Verified by: snapshot (`WHOISWORKING_NO_NOTCH=1`)

### UI-09 Empty state

With no sessions, the expanded panel says "No agent sessions" and, when hooks are not installed, shows an "Open Settings" button.

Verified by: snapshot (`WHOISWORKING_FORCE=expanded`, `WHOISWORKING_CLAUDE_SESSIONS` pointing at an empty folder)

### UI-10 Open session

"Open session" and a row click bring the owning app to the front by walking the session process's parent chain to the first regular app. When there is none (tmux, screen, daemon-hosted Codex), WhoIsWorking beeps. It cannot select a specific tab or conversation.

Verified by: manual check with a terminal session

### UI-11 Motion

Expanding uses a spring. With Reduce Motion on, it uses a short ease instead.

Verified by: manual check with Reduce Motion on

### UI-12 Settings

Opening WhoIsWorking.app while it runs shows Settings. Settings has one section per agent (Claude Code, Codex, Cursor and Antigravity marked experimental, OpenCode) with the hook or plugin status (installed, partial, not installed), install and uninstall buttons, and Quit. The window is 640 pt tall and scrolls.

Verified by: snapshot of the window (`WHOISWORKING_OPEN_SETTINGS=1`)

### UI-13 Refresh

Session files are rescanned when their folder changes, every 3 seconds, and after wake from sleep.

Verified by: `WHOISWORKING_DEBUG_STATE` file after starting and ending a session

### UI-14 Hook script kept current

At launch, the installed hook script is rewritten when it differs from the built-in contents.

Verified by: manual check (edit the installed script, relaunch, compare)

### UI-15 App shell

WhoIsWorking is an agent app with no Dock icon. Its user-visible name (bundle display name, Settings title, version line, Quit button, messages) is "Who's Working". A second copy reports that another copy is already running.

Verified by: manual check

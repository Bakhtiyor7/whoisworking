# Who's Working

A macOS app that lives in the MacBook notch and shows the status of your coding agent sessions: which are working, which need you, which finished. When a session needs you, small amber "wings" appear beside the notch. Hover the notch for the full list.

Supported agents:
- Claude Code (CLI and desktop app)
- Codex (CLI and app)
- OpenCode 2
- Cursor and Antigravity (experimental)

Status only: Who's Working never approves or denies anything.

This repository holds releases only; the source code is not public.

## Requirements

- macOS 15 or later
- A Mac with Apple silicon (M1 or later)

## Install

1. Download the `.dmg` from the [latest release](https://github.com/Bakhtiyor7/whoisworking-releases/releases/latest) and open it.
2. Drag **Who's Working** into **Applications**, then eject the disk image. Don't run it from the disk image.
3. Open Who's Working from Applications.

### First launch: "Open Anyway"

Releases are not yet notarized by Apple, so macOS blocks the first launch. On macOS 15 and later, Control-click › Open no longer gets past this. Instead:

1. Click **Done** in the dialog that says Apple could not verify the app.
2. Open **System Settings › Privacy & Security** and scroll to the bottom.
3. Click **Open Anyway** next to "Who's Working", then confirm with your password.

Or, in Terminal:

```bash
xattr -dr com.apple.quarantine "/Applications/WhoIsWorking.app"
```

Expect this step again after each update until releases are notarized.

## Set up

Open Who's Working again while it runs to show Settings. For each agent you use, click **Install hooks…** (OpenCode: **Install plugin…**). Before each change, Who's Working backs up the agent's settings file and touches only its own entries. Codex asks you to trust new hooks: type `/hooks` in the Codex CLI, or use Review hooks in the Codex app.

## Update

In Settings, click **Check for Updates**. If a newer version exists, **Download** opens its release page. Quit Who's Working (Settings › Quit), replace the app in Applications with the new one, and open it. Installed hooks keep working.

## Uninstall

1. In Settings, click **Uninstall hooks…** (or **Uninstall plugin…**) for every agent you set up.
2. Quit Who's Working and move it from Applications to the Trash.

If you delete the app first, the hooks stay in your agents' settings but do nothing.

## Privacy

Who's Working runs entirely on your Mac. It reads your agents' local session files and receives their hook events over a local socket in `~/Library/Application Support/WhoIsWorking/`. Its only network request is **Check for Updates**, made only when you click it: GitHub sees your IP address and the app's version.

## Bug reports

Open an [issue](https://github.com/Bakhtiyor7/whoisworking-releases/issues). Please leave out private file paths, prompts and session content.

## Source code archives

GitHub attaches "Source code (zip)" and "Source code (tar.gz)" to every release. In this repository they contain only this README. The app is the `.dmg`.

The Claude Code and Codex marks inside the app come from [Lobe Icons](https://github.com/lobehub/lobe-icons) (MIT). They identify the agents and belong to their owners.

# Who's Working

Who's Working shows your coding agent sessions in the MacBook notch: which are working, which need you, and which are done. It works with Claude Code, Codex, OpenCode, Cursor and Antigravity.

It needs macOS 15 or later on a Mac with Apple silicon. **Free, on this Mac only, status only:** it never approves or denies anything for an agent.

<!-- A short recording of the notch goes here before launch (OSS-14). -->

## Quick start

1. Paste this into Terminal. It installs Who's Working into Applications and opens it.

```bash
curl --proto '=https' --tlsv1.2 -fsSL -o whoisworking-install.sh https://github.com/Bakhtiyor7/whoisworking-releases/releases/latest/download/install.sh && sh whoisworking-install.sh
```

2. Hover the plug beside the notch, click **Connect** beside an agent, then **Install**.
3. Send a prompt in that agent. Hover the notch to see the session.

**Until the next release:** the command installs Who's Working 0.1.1, which has no plug and no setup card. In place of step 2, open Who's Working again while it runs to show Settings, and click **Install hooks…** in an agent's section (for OpenCode, **Install plugin…**). The card comes with the next release.

Read [what the command does](#install) before you run it. The app is not notarized, and this route skips the macOS first-launch check.

## Is it safe?

Who's Working changes your agents' hook files and receives their events, so it is fair to ask.

- It writes only the files listed in [What Who's Working does on your Mac](docs/trust.md), and backs up an agent's file before changing it.
- The hook it adds runs a short shell script that passes the event to the app and exits. It never answers for the agent.
- Its only network request is **Check for Updates**, and only when you click it. GitHub sees your IP address.
- It asks macOS for no special access: no Accessibility, Screen Recording or Full Disk Access.

Three checks that take under a minute let you see some of this on your own Mac. [What Who's Working does on your Mac](docs/trust.md#three-checks-that-take-under-a-minute) says what each one shows.

<details>
<summary>Run the three checks</summary>

1. Read the hook script that agents run. It exists once you have connected an agent.

```bash
cat ~/Library/Application\ Support/WhoIsWorking/whoisworking-hook
```

2. Before you connect Codex, see what would change in its hook file. This writes nothing. If Codex has no hook file yet, `diff` says the file does not exist; Who's Working would then create it with only its own entries.

```bash
diff -u ~/.codex/hooks.json <(/Applications/WhoIsWorking.app/Contents/MacOS/WhoIsWorking hooks preview --agent codex)
```

3. See that the app claims no entitlements. This prints only the app's path.

```bash
codesign -d --entitlements - /Applications/WhoIsWorking.app
```

</details>

Who's Working is built with coding agents under the maintainer's review; the specs, the tests and the commit trailers are the record.

## Install

The command saves an install script as `whoisworking-install.sh` in the current folder and runs it. The script downloads the disk image of the latest release, checks it against the SHA-256 written in the script, copies Who's Working to Applications and opens it. It never uses `sudo` and never asks for a password.

Before you run it:

- Who's Working is not notarized, because there is no paid Apple Developer ID yet. macOS cannot check who made it.
- An app installed this way skips the check macOS runs when you first open a download. If you want macOS to check it, use the [disk image](#install-from-the-disk-image) instead.
- If Terminal warns you about pasting, or you use a standard account, use the disk image.

<details>
<summary>Install in three steps, reading the script first</summary>

To pause before anything runs, do it in three steps.

1. Download the script. Nothing runs yet.

```bash
curl --proto '=https' --tlsv1.2 -fsSL -o whoisworking-install.sh https://github.com/Bakhtiyor7/whoisworking-releases/releases/latest/download/install.sh
```

2. Read it. It is plain `/bin/sh`, and its first lines say what it does.

```bash
less whoisworking-install.sh
```

3. Run it.

```bash
sh whoisworking-install.sh
```

</details>

### Install from the disk image

1. Download the `.dmg` from the [latest release](https://github.com/Bakhtiyor7/whoisworking-releases/releases/latest) and open it.
2. Drag **Who's Working** into **Applications**, then eject the disk image.
3. Open Who's Working from Applications. macOS blocks the first launch, because the app is not notarized:
   - Click **Done** in the dialog.
   - Open **System Settings › Privacy & Security** and scroll down.
   - Click **Open Anyway** next to "Who's Working", then confirm with your password.

Expect this step again after each update, until releases are notarized.

### Build it from source

<details>
<summary>Build and install from source</summary>

You need Xcode or its command-line tools (Swift 6). A copy you build on your own Mac is not checked by Gatekeeper, so there is no Open Anyway step.

1. Get the source of the latest release.

```bash
git clone https://github.com/Bakhtiyor7/whoisworking.git
```

```bash
cd whoisworking
```

```bash
git checkout "$(git describe --tags --abbrev=0)"
```

2. Build, test and install it into Applications. This takes a few minutes.

```bash
scripts/update.sh --install
```

</details>

## Connect your agents

Who's Working has to be connected to each agent you use. Until one is, a plug and **Set up** appear beside the notch.

Who's Working 0.1.1, which the command installs today, has no plug or card: use **Install hooks…** in Settings, as in [Quick start](#quick-start). Steps 3 and 4 below still apply.

1. Hover the plug. The **Finish setup** card lists the agents found on this Mac.
2. Click **Connect** beside an agent. The card says which file will change.
3. Click **Install**. Who's Working backs up that file, then adds a hook: a command the agent runs when something happens.
4. Do what the row says is left. Codex asks you to trust new hooks: type `/hooks` in the Codex CLI, or use **Review hooks** in the Codex app. Restart sessions that were already running.

To check that it works, send a prompt in a session you connected. The session appears when you hover the notch.

The hook passes the agent's events to Who's Working on this Mac, and those events include your prompts, file paths and commands. The panel shows each session's state and a short activity line. The events never leave your Mac.

To undo it, open Settings (open Who's Working again while it runs) and click **Uninstall hooks…** in that agent's section. Who's Working removes only its own entries and keeps your later edits.

<details>
<summary>Notes for each agent</summary>

- **Claude Code:** sessions that were already running appear within a few seconds, before any hook event.
- **Codex:** until you trust the hooks, Codex skips them and Who's Working sees nothing from Codex. A running Codex CLI shows "Running · no live status yet" until its first event.
- **OpenCode 2:** Who's Working adds a plugin file instead of a hook. Restart running OpenCode sessions to load it.
- **Cursor and Antigravity:** experimental. Their sessions go away after 15 minutes without events.

[What Who's Working shows for each agent](docs/agents.md) has the details.

</details>

## Which agents it supports

| Agent | Shows | Does not show |
|---|---|---|
| Claude Code | working, needs approval, waiting for your reply, done, errors | |
| Codex | working, needs approval, done, errors | waiting for your reply |
| OpenCode 2 | working, needs approval, waiting for your reply, done, errors | |
| Cursor (experimental) | working, done, errors | needs approval |
| Antigravity (experimental) | working, done, errors | needs approval |

[What Who's Working shows for each agent](docs/agents.md) says why, and how to connect and disconnect each one.

## Update and uninstall

Click **Check for Updates** in Settings. If a newer version exists, **Download** opens its release page. Running the install command again also installs the newest release. Connected agents keep working after an update.

### Uninstall

1. In Settings, click **Uninstall hooks…** (OpenCode: **Uninstall plugin…**) for each connected agent. This removes Who's Working's entries and its hook script.
2. Quit Who's Working from Settings, and move `/Applications/WhoIsWorking.app` to the Trash.
3. Delete its folder and its preferences:

```bash
rm -rf ~/Library/Application\ Support/WhoIsWorking
```

```bash
defaults delete io.github.bakhtiyor7.WhoIsWorking
```

The backups beside your agents' files, named `….whoisworking-backup-YYYYMMDD-HHMMSS`, stay until you delete them. If you delete the app first, the hooks stay in your agents' files and do nothing.

## Common problems

<details>
<summary>Nothing appears in the notch. Is it running?</summary>

Who's Working draws nothing while sessions are working or idle. Amber wings appear beside the notch when a session needs you, and hovering the notch shows every session. If no agent is connected yet, a plug and **Set up** appear instead.

</details>

<details>
<summary>Why do my Codex sessions show no live status?</summary>

Codex runs new hooks only after you trust them. Type `/hooks` in the Codex CLI, or use **Review hooks** in the Codex app, and trust the Who's Working entries.

</details>

<details>
<summary>My Mac has no notch. Does it work?</summary>

Yes. On a screen without a notch, Who's Working shows a small pill at the top centre when a session needs you.

</details>

<details>
<summary>macOS says it cannot verify Who's Working. What do I do?</summary>

That is the check for apps that are not notarized. Follow the Open Anyway steps under [the disk image](#install-from-the-disk-image). If macOS says the app is damaged or is malware, do not open it, and [report it](SECURITY.md).

</details>

<details>
<summary>Terminal warned me when I pasted the command. Should I paste anyway?</summary>

Use the [disk image](#install-from-the-disk-image) instead. It goes through macOS's own check.

</details>

<details>
<summary>Does Who's Working slow down my agent?</summary>

The hook script passes the event to the app and exits. When Who's Working is not running, the script reads the event and exits without sending it.

</details>

## Report a bug or contribute

- **Found a bug?** [Open an issue](https://github.com/Bakhtiyor7/whoisworking/issues/new/choose). Please leave out private paths, prompts and session text.
- **Found a security problem?** Report it privately, as [SECURITY.md](SECURITY.md) says.
- **A question?** Ask in [Discussions](https://github.com/Bakhtiyor7/whoisworking/discussions).
- **Want to help?** Start with [CONTRIBUTING.md](CONTRIBUTING.md). [docs/development.md](docs/development.md) says how to build and test.

## Licence

Who's Working is free software under the [GNU General Public License, version 3 only](LICENSE) (`GPL-3.0-only`). You may use, change and share it; a copy you share must come with its source under the same licence. The name and the icon are not part of that: see [TRADEMARK.md](TRADEMARK.md).

The agent marks come from [Lobe Icons](https://github.com/lobehub/lobe-icons) under its [MIT licence](Sources/WhoIsWorking/AgentIcons/LobeIcons-LICENSE.txt), which ships with the app; [Resources/AgentIcons/README.md](Resources/AgentIcons/README.md) lists them. They identify the agents and belong to their owners.

Copyright (C) 2026 Bakhtiyor7.

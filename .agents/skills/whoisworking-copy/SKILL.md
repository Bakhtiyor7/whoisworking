---
name: whoisworking-copy
description: Use when writing or changing any text a Who's Working user reads - setup card, Settings notes, confirmations, alerts, errors, install.sh output, the public README, release notes - or when a text about hooks, files, permissions, macOS security prompts or privacy feels unclear, suspicious or too technical.
---

# Writing Who's Working's words

Who's Working changes other tools' files and is not notarized. Every text has to earn trust: say what happens, prove it with specifics, and give the way back. Rules for releases and channels are in `docs/distribution-rules.md`; the review behind both is `docs/install-and-setup-review.md`.

## Every text starts from the code

Before writing a claim, find the code or spec that makes it true, and write only that. Examples: "a backup is made" only where `HookInstaller` writes one (not on refusal, not for a new file); "does nothing when Who's Working is not running" because the hook script's `nc` fails and it exits 0 (ING-07). A claim you cannot point to is cut, however reassuring it sounds ("the app is not damaged", "sessions show up once trusted").

macOS and agent wording (dialog titles, button names, menu paths) is copied from Apple's or the agent's docs or from a capture, never written from memory. If you cannot confirm it, describe the step without quoting it and note it as unconfirmed in the spec.

## Asking before a change (consent)

Any text before a write to another tool's file has these parts, in this order:

1. **What you get**, in the user's terms: "To show Codex sessions in the notch, …"
2. **What changes**: the file path, and "one entry per event" or the plugin file. Event names and counts go behind a Details disclosure or in Settings, never in the headline.
3. **What the hook sends and does not do**: it passes the agent's events, which include prompts, file paths and commands, to Who's Working on this Mac; the panel shows status and a short activity line; these events stay on the Mac; it never approves, blocks or changes anything; it does nothing when the app is not running. Never shorten this to "status only": that understates what the app receives. Never write "nothing leaves your Mac" about the app as a whole: Check for Updates asks GitHub.
4. **The way back**: a backup before any change to an existing file (never promise one for a new file, or for a repair that may change nothing), and Uninstall in Settings removes only Who's Working's entries and keeps the user's later edits. A file Who's Working created and the backups stay.
5. **What is left to do**, if anything: restart running sessions; for Codex, trust the hooks.

The confirm button names the action ("Add hook", "Add plugin"), never "OK", "Allow" or "Continue". "Cancel" sits beside it.

Fit the space. In the notch card (a 44 pt row that opens a short confirmation) the visible text is at most about 40 words (a test holds it to 42): parts 1 and 2 in one sentence, parts 3 and 4 in one sentence, part 5 after the install. Everything else goes behind Details or into Settings. Settings and the README have room for all five in full. Event counts and event names never appear in visible text, only behind Details.

Example for the card (file exists):

> To show Codex sessions here, Who's Working adds a hook to ~/.codex/hooks.json, backing it up before any change. Codex then passes its events, prompts, commands and paths included, to Who's Working on this Mac. Uninstall in Settings removes it.
>
> [Add hook] [Cancel] · Details

## Security prompts

- Say why: not notarized because there is no paid Apple Developer ID yet. Say what it means in Apple's terms: macOS cannot check who made the app.
- Give Apple's own route for the "could not verify" dialog: Privacy & Security, Open Anyway. Never put `xattr`, `spctl` or "Paste Anyway" on a main route, and never promise the warning is wrong.
- Other warnings get other answers: Terminal's paste confirmation, "use the disk image instead"; a malware or "damaged" alert or an XProtect block, "stop and report it".
- Say what a route skips: the install command does not go through the first-launch check. Offer the disk image to anyone who wants macOS to check it.
- Offer a way to check instead of a reassurance: the source, the tag, the SHA-256.

## Errors and status

- Cause, then what was left alone, then the fix: "Couldn't add the hook: ~/.claude/settings.json isn't valid JSON. Who's Working left it unchanged. Fix the file, then try again." Raw detail goes on a second line or behind Copy details. Say exactly what is unchanged: adding a hook writes the hook script before the agent's file is read. `InstallerProblem` (ONB-06) holds these texts.
- No "Error" titles, no codes, no blame, no apology.
- Status says what Who's Working knows, not what it hopes: "Hook added" after a write; "Last event 2 min ago" once one arrived. No event yet is not an error (an idle agent sends nothing), and Who's Working cannot see whether Codex trusts the hooks, so it reminds instead of claiming (spec 22).

## Words

| Use | Not |
|---|---|
| Who's Working (UI and docs); `WhoIsWorking` only for paths and the binary | Perch, the app, WIW |
| hook: on first use in a screen, "a hook (a command Codex runs when something happens)" | integration, injection, payload, instrumenting |
| add / remove a hook | install into, patch, inject |
| Connect (the row action) | Setup, Configure |
| this Mac, your Mac | locally, client-side |
| needs you, working, done | blocked, idle (in UI) |

Agent names exactly: Claude Code, Codex, Cursor, OpenCode, Antigravity. Menu paths with `›`. File paths in code style in docs.

## Sentences

- Under 25 words; one idea each. Active voice, with "Who's Working" or "you" as the subject.
- No em or en dashes in prose. Straight quotes in code and paths; the app's name keeps its apostrophe.
- No filler or sales words: simply, just, seamless, easily, powerful, secure (unless you say against what).
- Optional steps use "can", required ones say so plainly: "Codex needs one more step."
- One next step at the end of a flow, not a list of everything possible.

## Before you finish

- [ ] Every claim points at code or a spec id; macOS and agent wording is confirmed.
- [ ] Consent texts have all five parts; the button names the action.
- [ ] No text tells people to bypass a macOS prompt.
- [ ] Read it aloud as a first-time user who has never heard of hooks. Would they know what happens and what to do next?
- [ ] If a string lives in `AgentCore` (`SetupPrompt`, `Summary`), its test still pins it; change the test in the same edit.

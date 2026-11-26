# 22 Setup and first use

Status: draft
Source: user request 2026-11-26: the install, set-up steps and texts can feel suspicious, and a new user may not know what to do to make the app work. Review, research and plan in a working review kept on the maintainer's Mac and not published (OSS-02), reviewed by Codex GPT-6.2-Astra (high) the same day; release rules in [`../distribution-rules.md`](../distribution-rules.md); writing rules in the `whoisworking-copy` skill.
Code: `Sources/AgentCore/SetupPrompt.swift` (ONB-01, ONB-02), `Sources/AgentCore/InstallerProblem.swift` (ONB-06), `Sources/WhoIsWorking/Setup.swift`, `Settings.swift`. Planned: a new `Sources/AgentCore/ConnectionStatus.swift` (ONB-03), `NotchViews.swift`, `SessionStore.swift`.

## Purpose

Make the step from "installed" to "working" clear and believable. A new user should know, at each moment, what Who's Working is about to change, what it will receive, how to undo it, what is left to do, and whether it works.

This spec covers what the app shows. Spec 21 (open source) owns the README layout, the trust page and release provenance; spec 20 owns the install script; specs 05 and 06 stay the contracts for the hook script and the installer, and nothing here weakens them.

Not in this spec: a welcome window at first launch (tried and removed, UI-16), a test event sent by Who's Working itself (dropped: the hook script exits 0 with no listener, so it proves nothing about the agent, and spec 21 forbids starting programs, OSS-13), any change to when or how hooks are written.

## Requirements

### ONB-01 Consent says what is sent and how to undo it

The confirmation inside a setup card row (UI-17) and the install confirmation in Settings say, in this order: what the user gets, which file changes, what the hook passes to Who's Working and that it stays on this Mac, and how to undo it. They name the agent's events as including prompts, file paths and commands, and never call them "status only". In the card the visible text is about 35 words or fewer; event names and counts are not in it. The card's confirm button names the action ("Add hook", "Add plugin"); Settings' install alert shows the same text, says "in the notch" for "here", adds the event names, and keeps "Install" to match its "Install hooks…" buttons, which the README names (renaming them waits for the README rewrite, OSS-14). A backup is promised only before a change. The card text is at most 42 words for every agent and file state.

What the events hold comes from each agent's payloads in `Tests/Fixtures`: Claude Code, Codex and Antigravity send the prompt and commands; Cursor sends commands and the agent's thinking; the OpenCode plugin trims prompt text and sends status, commands and file paths.

Tests: `SetupPromptTests/theConfirmationNamesTheFileAndPromisesABackupOnlyForAnExistingFile`, `SetupPromptTests/theConfirmationSaysWhatEachAgentsEventsHold`, `SetupPromptTests/theConfirmButtonNamesWhatItAdds`
Verified by: snapshots of the card with the Codex confirmation open (`WHOISWORKING_SETUP_PREVIEW=confirm:codex`) on 2026-11-26

### ONB-02 Settings notes are short and complete

Each agent's section in Settings states the same four facts as ONB-01 in full, plus that nothing leaves the Mac and that the hook never approves, blocks or changes anything (ING-07), and the agent-specific step (restart running sessions; Codex: trust the hooks; OpenCode: restart OpenCode). The backup is stated as conditional, because the section shows before the file exists. No sentence of the explanation is longer than 25 words. Only the events are said to stay on the Mac, not the app as a whole (Check for Updates asks GitHub, DST-03). The Codex note is split into the reason and the two routes (Codex CLI, Codex app). The install alert lists the event names; the status line has no dash.

Tests: `SetupPromptTests/settingsExplainsTheChangeWhatIsSentAndTheWayBackInFull`
Verified by: Settings snapshot (`WHOISWORKING_OPEN_SETTINGS=1`) on 2026-11-26, read against the `whoisworking-copy` checklist

### ONB-03 Last event per agent

Who's Working keeps, per agent, the time of the last hook event it received from that agent over the socket and parsed with that agent's adapter. Session files, the process table and rollout reads do not count. The time is kept in memory and is gone when the app quits. Uninstalling an agent's hooks clears it.

A pure function turns install status and that time into one line, separate from the install status, never replacing it:

| Install status | Last event | Line |
|---|---|---|
| not installed | any | none |
| installed or partly installed | none since launch | "No event yet. Start a new session to check." |
| installed or partly installed | at time t | "Last event 2 min ago" (relative, like the session rows) |
| could not be read | any | none |

It never says "connected", "working" or "trusted": an idle agent sends nothing, and one event does not prove every hook runs. Where the line is shown is open question 1.

Planned tests: `ConnectionStatusTests/noEventYetAsksForANewSession`, `ConnectionStatusTests/aReceivedEventShowsHowLongAgo`, `ConnectionStatusTests/notInstalledShowsNothing`, `ConnectionStatusTests/discoveredSessionsDoNotCountAsEvents`, `ConnectionStatusTests/uninstallClearsTheLastEvent`

### ONB-04 Codex trust reminder

After Codex hooks are installed, and until a Codex hook event arrives in this run of the app, the Codex row (card and Settings) shows: "If you haven't yet, trust the hooks in Codex: type /hooks in the Codex CLI, or use Review hooks in the Codex app." The reminder never says the hooks are trusted or untrusted; Who's Working cannot read Codex's trust. It goes when a Codex hook event arrives (ONB-03), and comes back after a restart of the app until the next one.

Planned tests: `SetupPromptTests/codexRemindsAboutTrustUntilACodexEventArrives`, `SetupPromptTests/aCodexProcessWithoutAHookEventKeepsTheReminder`

### ONB-05 The empty state names the user's agents

With no sessions, the panel's empty state names the agents whose hooks or plugin are installed ("Start a Claude Code or OpenCode session and it shows up here."). With none installed it says that sessions show up once an agent is connected, and offers Settings, as today. The text is built in `AgentCore` so it can be tested.

Planned tests: `SummaryTests/theEmptyStateNamesTheInstalledAgents`, `SummaryTests/theEmptyStateWithNothingInstalledPointsToSetup`

### ONB-06 Installer errors say the cause and the fix

Every installer refusal or failure shown in the card or in Settings names the agent's file, what was left alone, and what to do: for example "Couldn't add the hook: ~/.claude/settings.json isn't valid JSON. Who's Working left it unchanged. Fix the file, then try again." In Settings the raw detail is on a second, dimmer line; the card shows only the text. Errors never start with "Error" and never show only a Swift error description. Only the agent's file is said to be unchanged, and only for refusals the installer makes before it writes (invalid JSON, unexpected shape): adding a hook writes the shared hook script first, and a failed read or write may come after the backup. An unexpected shape is described as entries Who's Working does not recognise, since the file may be valid for the agent. A read refusal also says what to do. Any other error while adding a hook comes from writing the hook script, and says so. Each `HookInstallerError` case has its text for adding, removing, reading and (plugin) updating; Antigravity's invalid file names comments as the likely cause; the plugin's shape refusal says the file is not Who's Working's. A file another tool changed between Who's Working's read and its write (INS-19) is named as changed meanwhile: Who's Working kept that change, and the user tries again; there is no raw detail.

Tests: `InstallerProblemTests/invalidJSONNamesTheFileAndTheFix`, `InstallerProblemTests/anUnexpectedShapeNamesTheFileAndTheFix`, `InstallerProblemTests/aForeignPluginFileNamesTheFileAndTheFix`, `InstallerProblemTests/antigravityCommentsAreNamedAsTheLikelyCause`, `InstallerProblemTests/aFailedReadOrWriteNamesTheFileWithoutClaimingNothingChanged`, `InstallerProblemTests/aFileThatCannotBeReadIsLeftAlone`, `InstallerProblemTests/aPluginUpdateFailureNamesThePluginFile`, `InstallerProblemTests/aHookScriptFailureNamesTheScriptAndLeavesTheAgentFileAlone`, `InstallerProblemTests/noTextStartsWithErrorOrHasADash`, `InstallerProblemTests/aFileChangedMeanwhileSaysTheChangeWasKept`

### ONB-07 What to do when nothing shows up

One set of steps, in this order, is shown in the README's common problems section (OSS-14) and reachable from Settings with a link:

1. Is Who's Working running? Open it from Applications; a second open shows Settings.
2. Is the agent's hook added? Settings shows it per agent.
3. Codex only: are the hooks trusted? Type /hooks in the Codex CLI.
4. Was the session started after the hook was added? Start a new one.
5. Did an event arrive? Settings shows the last event (ONB-03).
6. Still nothing: open an issue with the app version, macOS version, agent and its version, and no prompts or private paths.

Verified by (planned): the README section and the Settings link, read against this list.

## Follow-ups from the code review

Found by Codex GPT-6.2-Astra (high) in the ONB-01, ONB-02 and ONB-06 change on 2026-11-26 and left for later, because they are behaviour of the untested app target or outside the installer texts:

- In `HookManager`, a launch-time plugin update error is cleared when Settings opens and refreshes, and the card keeps an old refusal after the file was fixed elsewhere. Read errors and operation errors should be kept apart and cleared on recovery or retry. This was so before this change.
- Raw errors remain outside the installer texts: "Open at login" shows `localizedDescription`, the socket banner shows a Swift error, and `WhoIsWorking hooks install|uninstall` prints `error: <error>` without the target file (or its `--settings` override).
- `README.md` still tells card users to click Install, and says nothing shows from Codex until the hooks are trusted (running Codex CLIs show as placeholders). Spec 21's README rewrite (OSS-14) takes both.

## Requirements in other specs that change

Edited in their own specs when this one is started, not here:

- UI-17 (spec 08): the confirmation text and button label (ONB-01), the Codex reminder (ONB-04), the last-event line if it goes in the card (open question 1).
- DST-21 and DST-22 (spec 20): README and release-note wording follows `docs/distribution-rules.md` rules 1 to 3 (no `xattr` or "Paste Anyway" on the main route; three warnings, three answers). The script's endings stay release-specific: 0.1.1 has no setup hint.
- ING-06 (spec 05): the script also runs `cat`, found through `PATH`. A wording fix to a contract spec, so the user decides (open question 5).
- OSS-12 and OSS-14 (spec 21, another session's draft): the trust page and README take their privacy wording and the removal details (what stays after uninstall) from rules 5 and 13 of [`../distribution-rules.md`](../distribution-rules.md).

## Open questions

1. Where does the last-event line show: in the setup card rows, in Settings, or both? A design choice, shown as visual options first.
2. Does the setup card get a Details disclosure for the event list and the backup, or do those stay in Settings only?
3. Should there be a persistent way to open Settings besides the panel's gear and opening the app again (a right-click on the notch, an optional menu-bar item)?
4. Should the last event survive a restart of the app? Kept in memory today, so nothing about sessions is written to disk.
5. Fix ING-06's wording to name `cat`, or change the script to call `/bin/cat`? The second changes the hook script, which every installed copy would pick up at launch (UI-14); the command line in the agents' files stays the same.
6. Ship the text changes (ONB-01, ONB-02, ONB-06) before the open-source launch, or together with it?

# 08 Notch UI

Status: implemented
Code: `Sources/WhoIsWorking/` (`NotchPanel.swift`, `NotchViews.swift`, `SessionStore.swift`, `AppFocuser.swift`, `Settings.swift`, `main.swift`); `Sources/AgentCore/SetupPrompt.swift` (UI-16, UI-17)

## Purpose

The visible app. The `WhoIsWorking` target has no unit tests and stays thin: it lays out what `AgentCore` computes. These requirements are checked by rendering snapshots (`WHOISWORKING_SNAPSHOT`) and reading the debug state file (`WHOISWORKING_DEBUG_STATE`); the `whoisworking-verify-ui` skill has the steps. Design source: `docs/plan.md` §5 and §5a.

## Requirements

### UI-01 Hidden by default

While every session is idle or working, nothing is drawn. The one exception is the setup hint (UI-16), which shows until an agent is connected or the user dismisses it.

Verified by: snapshot (collapsed, sessions idle or working)

### UI-02 Wings

When a session needs the user, wings appear 70 pt each side of the notch: an amber dot and the count on the left, the longest wait on the right.

The setup hint (UI-16) uses the same wings with other content: a white plug glyph on the left and "Set up" on the right. A session that needs the user takes the wings from it.

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

On a screen without a notch, nothing is drawn until something needs the user or the setup hint is on (UI-16); then a pill appears at the top centre with the same content as the wings.

Verified by: snapshot (`WHOISWORKING_NO_NOTCH=1`)

### UI-09 Empty state

With no sessions, the expanded panel says "No agent sessions" and, when hooks are not installed, shows an "Open Settings" button. While the setup card is shown (UI-17) the card stands in for the empty state.

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

### UI-16 Setup hint in the notch

Source: 2026-11-25. A new user who had installed no hooks saw nothing at all: no Dock icon, nothing drawn, no sessions. The first answer, opening the Settings window once on the first launch, was built and failed the same day in a real install: opened by the install script with `open` while another app's window filled the screen, the app did not become active, the window sat behind that window, and the one-time check was used up. A copy started straight from a shell did come to the front, which is why the checks before the install missed it. That behaviour and its `firstRunChecked` preference are removed. The hint now lives in the notch, which needs no focus and is not a single try.

Given this copy owns the session socket and the user has not dismissed setup, when no agent's hooks or plugin are installed or partly installed, then the collapsed notch shows the setup wings (UI-02), or the pill on a screen without a notch (UI-08), and hovering opens the panel with the setup card (UI-17). The wings go when an agent is connected, and come back if every agent is disconnected again. A session that needs the user takes the wings. Closing the card hides the hint and the card for seven days the first time. After that they come back once, and the close button then reads "Don't show again"; closing a second time hides them for good (preferences `setupDismissCount` and `setupDismissedAt`). Settings still has everything, and opening Who's Working again while it runs still shows Settings. A copy without the socket (UI-15) shows no hint and no card, and writes no preference. VoiceOver reads the wings as "Who's Working needs setup".

Tests: `SetupPromptTests/noConnectedAgentShowsTheSetupWings`, `SetupPromptTests/aSessionThatNeedsYouTakesTheWingsFromSetup`, `SetupPromptTests/aConnectedAgentHidesTheSetupWings`, `SetupPromptTests/notNowHidesSetupForAWeekAndTheSecondTimeForGood`, `SetupPromptTests/hiddenSetupStaysHiddenWhateverElseChanges`, `SetupPromptTests/aCopyWithoutTheSocketOffersNoSetup`
Verified by: snapshots of the debug binary on 2026-11-25, each in a throwaway home (`CFFIXED_USER_HOME`, so the copy has its own socket and no hooks): collapsed, the wings show the white plug and "Set up"; with `WHOISWORKING_NO_NOTCH=1`, the pill shows the same; with one session waiting for approval, the wings show the amber dot and count instead. A second copy beside the installed app showed the socket error and the empty state, and no hint or card. With the preferences saying setup was closed once fifteen days earlier, the card was back with "Don't show again"; closed once a minute earlier, there was no hint and the panel showed the empty state. Still open, for a person at the notch: that hovering the setup wings opens the panel, clicking the close button, VoiceOver, and the installed app after a real install

### UI-17 Setup card

While the user has not dismissed setup and this copy owns the socket, the expanded panel shows a "Finish setup" card below Needs you and above Working, when an agent found on this Mac is not fully connected, or hooks were installed from the card since the app started. With nothing to say it is absent: every listed agent was installed before this launch.

- **Rows.** One 44 pt row per agent found on this Mac, in the order Claude Code, Codex, Cursor, OpenCode, Antigravity. An agent counts as found when its configuration folder exists (`~/.claude`, `~/.codex`, `~/.cursor`, `~/.config/opencode`, `~/.gemini`) or its hooks are installed or partly installed. When none is found, Claude Code and Codex are listed. The folders are only a suggestion of what to offer; Settings always lists all five.
- **Status.** A row shows the agent's icon and name and one of: the file that would change with a "Connect" button; "Partly installed" with a "Repair" button; "Hooks installed" or "Plugin installed" with a green check; or "Could not read its file. See Settings." with no button. File status cannot show that events really arrive, so the card never says "connected".
- **Installing.** "Connect" and "Repair" do not write. They open a confirmation inside the row that names the file and what is added, promises a backup only for a file that already exists and is changed, and has "Install" and "Cancel". "Install" makes the same call as Settings' install button, so the hook installer's contract ([06](06-hook-installer.md)) holds unchanged. It acts only for the row whose confirmation is open, and the confirmation closes when the panel closes, so a click on a later visit cannot install. After a refusal or an error the reason is shown in red in the row and the status is read again. An install that succeeds but leaves the hooks partly installed (Antigravity keeps hooks the user turned off) says so and does not count as installed.
- **Next step.** After an install from the card, the row says what is left: for Codex, to trust the hooks in Codex (Review hooks in the app, `/hooks` in the CLI); for Claude Code and Antigravity, to restart sessions that were already running; for OpenCode, to restart OpenCode. The card stays, with these lines, until the app quits or the user closes the card, so the last install does not take its own next step away.
- **Closing.** The button at the top right reads "Done" once every row is installed, "Don't show again" when setup was closed once before, and "Not now" otherwise. Each of them closes setup by the rule in UI-16: a week the first time, for good the second.
- Statuses and the socket are read again each time the panel opens and every 15 seconds, without writing anything, so hooks installed or removed elsewhere, and a socket won after wake, change the hint and the card within that time.

Tests: `SetupPromptTests/onlyAnInstallThatChangedTheFileAndLeftItInstalledCountsAsMadeNow`, `SetupPromptTests/aFileWithAnAgentFoldersNameIsNotAFolder`, `SetupPromptTests/theCardListsTheAgentsFoundOnThisMacInAFixedOrder`, `SetupPromptTests/withNoAgentFoundClaudeCodeAndCodexAreOffered`, `SetupPromptTests/theCardStaysForAgentsStillToConnect`, `SetupPromptTests/anInstallMadeNowKeepsTheCardAndSaysWhatToDoNext`, `SetupPromptTests/everythingInstalledEarlierShowsNoCard`, `SetupPromptTests/partlyInstalledAndUnreadableFilesAreShownAsTheyAre`, `SetupPromptTests/theConfirmationNamesTheFileAndPromisesABackupOnlyForAnExistingFile`, `SetupPromptTests/agentsAreFoundByTheirConfigFolders`
Verified by: snapshots of the debug binary on 2026-11-25 in throwaway homes holding `.claude`, `.codex` and `.cursor`: the card with three rows and Connect buttons; the confirmation open in the Claude Code row (`WHOISWORKING_SETUP_PREVIEW=confirm:claudeCode`), reading "Creates ~/.claude/settings.json with a hook for 13 events."; Codex hooks installed in that home and marked as installed from the card (`installed:codex`), with the green check, "Hooks installed" and the trust line; with a session waiting for approval, the Needs you card above the setup card. Still open, for a person at the notch: clicking Connect, Install, Cancel and the close button in the live panel, the row after a refused install, and the card's height with five agents on a small screen

## Design notes for UI-16 and UI-17

References (Mobbin), and what was taken from each:

- [Apple Fitness](https://mobbin.com/screens/b6cbddbe-a2f1-4050-8ee5-10fe30ccf937?utm_source=claude-code&utm_medium=ai-assistant&utm_source_platform=mcp) and [Tide Guide](https://mobbin.com/screens/1a430478-613f-4122-89fc-4ad78a03593d?utm_source=claude-code&utm_medium=ai-assistant&utm_source_platform=mcp) in the Dynamic Island: one glyph on the left, one short label on the right. The setup wings.
- [Rocket Money](https://mobbin.com/screens/94e3c7a6-fac7-4f42-a73b-b54d3e8fe2a4?utm_source=claude-code&utm_medium=ai-assistant&utm_source_platform=mcp) and [Shopify](https://mobbin.com/screens/32ac5921-43be-435c-88cc-9e29bd8eb23e?utm_source=claude-code&utm_medium=ai-assistant&utm_source_platform=mcp): a short setup list pinned above the normal content, with items that tick off from real state.
- [Google Health](https://mobbin.com/screens/fe7208b2-ff98-4e64-be36-31f8c23435a3?utm_source=claude-code&utm_medium=ai-assistant&utm_source_platform=mcp): setup is offered with a way to dismiss it, never forced.
- [Mintlify](https://mobbin.com/screens/e700ca68-4482-467d-abe8-c66cbbd663fa?utm_source=claude-code&utm_medium=ai-assistant&utm_source_platform=mcp): one row per integration with an icon, a name, one line and a "Connect" button.

The owner asked for a hint in the notch. The agent built a first version after a Codex review without showing directions first, which the owner had not wanted: important design decisions are the owner's to make from options. The four decisions were then put to the owner on 2026-11-25, with the built version as one option each time. Chosen: a static marker beside the notch (over the notch opening by itself on first launch, and over a pulsing marker); white (over amber); installing inside the notch card (over a card that only opens Settings, and over one "Connect all" button); and "Not now" that asks again after a week (over hiding for good, which was what had been built, and over coming back at every launch).

Codex GPT-6.2-Astra (high) reviewed the design before it was built. Checked here before adopting: the panel accepts the first click over another app (`FirstMouseHostingView`), `HookManager.refresh()` can rewrite the hook script, and `firstRunChecked` was already set for users who never saw the Settings window.

- **Fixed blockers:** the card went away on the last install, exactly when the Codex trust step had to be shown, so it now stays until the app quits or the user closes it, and says "Hooks installed", not "Connected"; a copy without the socket could have offered installs and saved "Not now", so the hint, the card and the preference all need the socket.
- **Changed:** installing from the panel goes through a confirmation inside the row, because the panel takes the first click over another app; the wings are white, so amber keeps meaning that a session waits; Needs you stays above the card; partial and unreadable files are shown as they are; statuses are read again when the panel opens with a call that writes nothing; one value decides what the collapsed notch draws and where the pointer opens it.
- **Not built:** the notch opening by itself for a few seconds on the first launch. The wings stay until setup is done, so they survive a missed login or a full-screen launch, and a one-time animation would again depend on being seen once.
- **After the review of the code:** an open confirmation closed nothing when the panel closed, so a click on the next visit could have installed, and it now closes with the panel and Install acts only for the open row; a failed install reads the status again and keeps its own message; an install only counts when it changed the file and left the hooks installed; the hint follows a socket won later and hooks removed elsewhere; a file named like an agent's folder is not a folder; the installer says to open the new copy after another one is quit, and sends people to Settings when the card or an agent is missing.
- **Kept on Codex's advice:** a route without the pointer. Opening Who's Working again from Applications shows Settings, also after "Not now".

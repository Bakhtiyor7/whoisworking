# 06 Hook installer

Status: implemented
Code: `Sources/AgentCore/HookInstaller.swift`, `Sources/AgentCore/OrderedJSON.swift`, `Sources/AgentCore/HooksCommand.swift`

## Purpose

Add and remove WhoIsWorking's hooks in files WhoIsWorking does not own (`~/.claude/settings.json`, `~/.codex/hooks.json`, `~/.cursor/hooks.json`, `~/.gemini/config/hooks.json`), which other tools also write hooks into. These requirements are a contract: a change that breaks one is a bug, whatever else it achieves.

The app was called Perch until 2026-11-22, and its entries used `/Perch/perch-hook`. The installer does not recognise those: remove them with the old Perch build before installing WhoIsWorking's hooks.

## Requirements

### INS-01 Install adds one entry per event

Install appends one handler, recognisable by `/WhoIsWorking/whoisworking-hook` in its command, to each of the agent's events: 13 for Claude Code (timeout 5 s), 10 for Codex (timeout 3 s), 6 for Cursor (timeout 5 s). For Antigravity it writes one named group with a handler for each of 4 events (timeout 5 s, INS-16).

Tests: `HookInstallerTests/installAddsOneTaggedHandlerPerEvent`, `CodexHookInstallerTests/codexTargetCoversTheCodexEvents`, `CursorHookInstallerTests/installAppendsOneFlatEntryPerEventAfterOtherTools`, `AntigravityHookInstallerTests/installAddsOneNamedGroupWithTheEventInEachCommand`

### INS-02 Other tools' entries are untouched

Install never changes or reorders other tools' entries or keys. WhoIsWorking's entry goes after them.

Tests: `HookInstallerTests/installKeepsOtherToolsEntriesAndKeysInOrder`, `CodexHookInstallerTests/installAppendsAfterOtherToolsAndUninstallRestoresExactly`

### INS-03 Backup first

Before every change, a timestamped backup of the original is written beside the file.

Tests: `HookInstallerTests/installWritesATimestampedBackupOfTheOriginalFirst`

### INS-04 Idempotent

Running install again changes nothing.

Reinstalling puts WhoIsWorking's entry back where it was: an event key emptied while reinstalling keeps its place instead of moving to the end.

Tests: `HookInstallerTests/installIsIdempotent`, `CursorHookInstallerTests/reinstallDoesNotReorderEvents`

### INS-05 Uninstall removes exactly WhoIsWorking's entries

Uninstall removes only handlers whose command contains `/WhoIsWorking/whoisworking-hook`, also inside groups shared with other tools, and drops event keys it leaves empty, so the file returns to its earlier content byte for byte. Uninstall when nothing is installed changes nothing.

Tests: `HookInstallerTests/uninstallRestoresThePriorContentExactly`, `HookInstallerTests/uninstallRemovesOnlyTaggedHandlersEvenInsideSharedGroups`, `HookInstallerTests/uninstallWhenNotInstalledChangesNothing`, `CodexHookInstallerTests/installAppendsAfterOtherToolsAndUninstallRestoresExactly`

### INS-06 Refuse what it does not understand

Invalid JSON or an unexpected shape means refuse and change nothing.

Tests: `HookInstallerTests/refusesToWriteWhenTheFileIsNotValidJSON`, `HookInstallerTests/refusesUnexpectedShapes`, `CodexHookInstallerTests/refusesInvalidJSON`

### INS-07 Missing file

Given no settings file, install creates it; uninstall then removes WhoIsWorking's keys again.

Install creates a missing parent folder too (for example `~/.gemini/config`).

Tests: `HookInstallerTests/createsTheFileWhenMissingAndRemovesOurKeysOnUninstall`, `AntigravityHookInstallerTests/installCreatesAMissingConfigFolder`

### INS-08 Status

Status reports installed, not installed, or partial (some events missing).

Tests: `HookInstallerTests/reportsPartialInstalls`

### INS-09 Preview

Preview returns the file as install would write it, and writes nothing.

Tests: `HookInstallerTests/previewShowsTheChangeWithoutWriting`, `HooksCommandTests/previewChangesNothing`

### INS-10 File permissions and symlinks

The file keeps its permissions. When the settings path is a symlink, WhoIsWorking writes through it and does not replace the link with a file.

Tests: `HookInstallerTests/keepsFilePermissions`, `HookInstallerTests/writesThroughASymlinkInsteadOfReplacingIt`

### INS-11 Agents are separate

Claude Code entries and Codex entries do not count for each other. The Codex hooks file round-trips unchanged.

Tests: `CodexHookInstallerTests/claudeAndCodexEntriesDoNotCountForEachOther`, `CodexHookInstallerTests/codexHooksFileRoundTrips`

### INS-12 Order-preserving JSON

The JSON reader and writer keep key order and number spelling. Reading and writing a file formatted like `JSON.stringify(v, null, 2)` gives identical bytes, including a real settings file. Compact input is pretty-printed. Invalid JSON is rejected. Surrogate pairs decode.

Tests: `OrderedJSONTests/roundTripIsByteIdentical`, `OrderedJSONTests/keyOrderIsPreserved`, `OrderedJSONTests/compactInputIsPrettyPrinted`, `OrderedJSONTests/invalidJSONIsRejected`, `OrderedJSONTests/surrogatePairsDecode`, `OrderedJSONTests/roundTripOfARealFile`

### INS-13 Command line

`WhoIsWorking hooks status|preview|install|uninstall [--agent claude-code|codex|cursor|antigravity|opencode] [--settings <path>]`:

- install writes the exact hook script;
- `--agent codex`, `--agent cursor` and `--agent antigravity` work on that agent's hook file, and `--agent opencode` on the OpenCode plugin file (OPC-01);
- an unknown agent is rejected; an unknown subcommand prints usage.

Tests: `HooksCommandTests/installWritesTheExactScript`, `HooksCommandTests/codexAgentWritesTheCodexHooksFile`, `HooksCommandTests/cursorAndAntigravityAgentsWriteTheirOwnFiles`, `HooksCommandTests/unknownAgentIsRejected`, `HooksCommandTests/unknownSubcommandPrintsUsage`

### INS-14 Hook script lifetime

Uninstall on the default settings removes the hook script, unless another agent's default hook file still uses it. A default hook file that WhoIsWorking cannot read (for example Antigravity's, which may contain comments) counts as still using it. Uninstall on another settings file (`--settings`) always leaves the script alone. The OpenCode plugin does not use the script and plays no part here.

Tests: `HooksCommandTests/uninstallOnTheDefaultSettingsRemovesTheHookScript`, `HooksCommandTests/theScriptStaysWhileAnotherAgentStillUsesIt`, `HooksCommandTests/uninstallOnAnotherSettingsFileLeavesTheHookScriptAlone`, `HooksCommandTests/uninstallOnAnotherFileKeepsTheScriptEvenWhenNothingElseUsesIt`, `HooksCommandTests/theScriptStaysWhenAHookFileCannotBeRead`

### INS-15 Cursor's file shape

`~/.cursor/hooks.json` is `{"version": 1, "hooks": {"<event>": [{"command", "timeout", …}]}}`: a flat list of entries per event, with no matcher groups. Install appends one `{"command", "timeout"}` entry to each event, after other tools' entries. A missing file is created with `"version": 1` first. An existing file with hooks but no numeric `version` is refused, because Cursor rejects it too. Uninstall removes only WhoIsWorking's entries and the event keys it leaves empty, and keeps `version`.

Tests: `CursorHookInstallerTests/installAppendsOneFlatEntryPerEventAfterOtherTools`, `CursorHookInstallerTests/aNewFileStartsWithVersionOne`, `CursorHookInstallerTests/uninstallRestoresTheOriginalExactly`, `CursorHookInstallerTests/refusesAFileWithHooksButNoVersion`, `CursorHookInstallerTests/reportsAMissingEventAsPartial`

### INS-16 Antigravity's named group

`~/.gemini/config/hooks.json` maps hook names to their events. WhoIsWorking owns the top-level `"whoisworking"` key and nothing else. Its value holds one handler per event, `{"type": "command", "command": "<script> antigravity <Event>", "timeout": 5}`, directly under `SessionStart`, `PreInvocation` and `Stop`, and inside a `{"matcher": "", "hooks": […]}` group under `PostToolUse`. Install sets the key and keeps an existing `"enabled"` value. A disabled group reports as partial, and install leaves it disabled. A `"whoisworking"` key that holds anything else is refused on install and on uninstall: a command that is not exactly WhoIsWorking's (including one that wraps the script), a handler for the wrong event, another matcher, unknown or repeated fields. Uninstall deletes the key. Comments or trailing commas, which Antigravity allows, make the file unreadable for WhoIsWorking: it refuses and changes nothing.

Tests: `AntigravityHookInstallerTests/installAddsOneNamedGroupWithTheEventInEachCommand`, `AntigravityHookInstallerTests/otherGroupsAreUntouchedAndUninstallRestoresExactly`, `AntigravityHookInstallerTests/refusesAGroupWithEntriesItDidNotWrite`, `AntigravityHookInstallerTests/keepsTheEnabledFlagAndReportsADisabledGroupAsPartial`, `AntigravityHookInstallerTests/refusesCommentsAndChangesNothing`

### INS-17 A no-op writes nothing

When install or uninstall would leave the parsed content unchanged, the file is not written and no backup is made, even if its formatting differs from WhoIsWorking's.

Tests: `HookInstallerTests/aLogicalNoOpWritesNothing` (uninstall on a compact file without WhoIsWorking's hooks, and reinstall on a compact file that has them)

### INS-18 A backup is private from its first byte

A backup is created with mode 0600. It is never readable by other users, also not between its creation and a later permission change. A file that already exists at the backup's path is never overwritten.

Tests: `HookInstallerTests/aBackupIsNeverReadableByOthersWhileItIsWritten`

### INS-19 An edit made meanwhile is never overwritten

Given another tool changes, creates or deletes the file after WhoIsWorking read it, when WhoIsWorking is about to write, then it reads the file again and, finding it different from what it read, refuses: the file stays as the other tool left it, the backup WhoIsWorking had just made is removed, and the message says the file changed and to try again.

The check runs immediately before the write. The instant between the check and the write cannot be closed, because other tools take no lock on the file.

Tests: `HookInstallerTests/anEditMadeWhileInstallingIsKept`, `HookInstallerTests/aFileDeletedWhileInstallingStaysDeleted`, `HookInstallerTests/aFileThatAppearsWhileInstallingIsKept`

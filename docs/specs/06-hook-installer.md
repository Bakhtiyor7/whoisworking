# 06 Hook installer

Status: implemented
Code: `Sources/AgentCore/HookInstaller.swift`, `Sources/AgentCore/OrderedJSON.swift`, `Sources/AgentCore/HooksCommand.swift`

## Purpose

Add and remove Perch's hooks in files Perch does not own (`~/.claude/settings.json`, `~/.codex/hooks.json`), which other tools also write hooks into. These requirements are a contract: a change that breaks one is a bug, whatever else it achieves.

## Requirements

### INS-01 Install adds one entry per event

Install appends one handler, recognisable by `/Perch/perch-hook` in its command, to each of the agent's events: 13 for Claude Code (timeout 5 s), 10 for Codex (timeout 3 s).

Tests: `HookInstallerTests/installAddsOneTaggedHandlerPerEvent`, `CodexHookInstallerTests/codexTargetCoversTheCodexEvents`

### INS-02 Other tools' entries are untouched

Install never changes or reorders other tools' entries or keys. Perch's entry goes after them.

Tests: `HookInstallerTests/installKeepsOtherToolsEntriesAndKeysInOrder`, `CodexHookInstallerTests/installAppendsAfterOtherToolsAndUninstallRestoresExactly`

### INS-03 Backup first

Before every change, a timestamped backup of the original is written beside the file.

Tests: `HookInstallerTests/installWritesATimestampedBackupOfTheOriginalFirst`

### INS-04 Idempotent

Running install again changes nothing.

Tests: `HookInstallerTests/installIsIdempotent`

### INS-05 Uninstall removes exactly Perch's entries

Uninstall removes only handlers whose command contains `/Perch/perch-hook`, also inside groups shared with other tools, and drops event keys it leaves empty, so the file returns to its earlier content byte for byte. Uninstall when nothing is installed changes nothing.

Tests: `HookInstallerTests/uninstallRestoresThePriorContentExactly`, `HookInstallerTests/uninstallRemovesOnlyTaggedHandlersEvenInsideSharedGroups`, `HookInstallerTests/uninstallWhenNotInstalledChangesNothing`, `CodexHookInstallerTests/installAppendsAfterOtherToolsAndUninstallRestoresExactly`

### INS-06 Refuse what it does not understand

Invalid JSON or an unexpected shape means refuse and change nothing.

Tests: `HookInstallerTests/refusesToWriteWhenTheFileIsNotValidJSON`, `HookInstallerTests/refusesUnexpectedShapes`, `CodexHookInstallerTests/refusesInvalidJSON`

### INS-07 Missing file

Given no settings file, install creates it; uninstall then removes Perch's keys again.

Tests: `HookInstallerTests/createsTheFileWhenMissingAndRemovesOurKeysOnUninstall`

### INS-08 Status

Status reports installed, not installed, or partial (some events missing).

Tests: `HookInstallerTests/reportsPartialInstalls`

### INS-09 Preview

Preview returns the file as install would write it, and writes nothing.

Tests: `HookInstallerTests/previewShowsTheChangeWithoutWriting`, `HooksCommandTests/previewChangesNothing`

### INS-10 File permissions and symlinks

The file keeps its permissions. When the settings path is a symlink, Perch writes through it and does not replace the link with a file.

Tests: `HookInstallerTests/keepsFilePermissions`, `HookInstallerTests/writesThroughASymlinkInsteadOfReplacingIt`

### INS-11 Agents are separate

Claude Code entries and Codex entries do not count for each other. The Codex hooks file round-trips unchanged.

Tests: `CodexHookInstallerTests/claudeAndCodexEntriesDoNotCountForEachOther`, `CodexHookInstallerTests/codexHooksFileRoundTrips`

### INS-12 Order-preserving JSON

The JSON reader and writer keep key order and number spelling. Reading and writing a file formatted like `JSON.stringify(v, null, 2)` gives identical bytes, including a real settings file. Compact input is pretty-printed. Invalid JSON is rejected. Surrogate pairs decode.

Tests: `OrderedJSONTests/roundTripIsByteIdentical`, `OrderedJSONTests/keyOrderIsPreserved`, `OrderedJSONTests/compactInputIsPrettyPrinted`, `OrderedJSONTests/invalidJSONIsRejected`, `OrderedJSONTests/surrogatePairsDecode`, `OrderedJSONTests/roundTripOfARealFile`

### INS-13 Command line

`Perch hooks status|preview|install|uninstall [--agent claude-code|codex] [--settings <path>]`:

- install writes the exact hook script;
- `--agent codex` works on the Codex hooks file;
- an unknown agent is rejected; an unknown subcommand prints usage.

Tests: `HooksCommandTests/installWritesTheExactScript`, `HooksCommandTests/codexAgentWritesTheCodexHooksFile`, `HooksCommandTests/unknownAgentIsRejected`, `HooksCommandTests/unknownSubcommandPrintsUsage`

### INS-14 Hook script lifetime

Uninstall on the default settings removes the hook script, unless another agent's default hook file still uses it. Uninstall on another settings file (`--settings`) leaves the script alone.

Tests: `HooksCommandTests/uninstallOnTheDefaultSettingsRemovesTheHookScript`, `HooksCommandTests/theScriptStaysWhileAnotherAgentStillUsesIt`, `HooksCommandTests/uninstallOnAnotherSettingsFileLeavesTheHookScriptAlone`

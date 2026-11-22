# WhoIsWorking specs

What WhoIsWorking does, written as numbered requirements. Tests prove them; `scripts/check-specs.sh` keeps the two in step. Research and the reasons behind the design are in [`../plan.md`](../plan.md).

## Index

| Spec | Ids | Status |
|---|---|---|
| [01 Sessions and states](01-sessions-and-states.md) | SES | implemented |
| [02 Reducer](02-reducer.md) | RED | implemented |
| [03 Claude Code](03-claude-code.md) | CCA | implemented |
| [04 Codex](04-codex.md) | CDX | implemented |
| [05 Ingest and hook script](05-ingest-and-hook-script.md) | ING | implemented |
| [06 Hook installer](06-hook-installer.md) | INS | implemented |
| [07 Summary and formatting](07-summary.md) | SUM | implemented |
| [08 Notch UI](08-notch-ui.md) | UI | implemented |
| [10 Design for Settings, empty state, pill](10-settings-empty-pill-design.md) | DSN | draft |
| [11 Cursor adapter](11-cursor-adapter.md) | CUR | draft |
| [12 OpenCode adapter](12-opencode-adapter.md) | OPC | implemented |
| [13 Distribution](13-distribution.md) | DST | draft |
| [14 Antigravity adapter](14-antigravity-adapter.md) | ANT | draft |
| [15 Click to session](15-click-to-session.md) | NAV | draft |

## Not in v1

- Approving or denying from the notch. WhoIsWorking is status only, and the hook script never makes a decision.
- Usage limits and remote machines.

## Format

```markdown
# NN Title

Status: implemented | draft
Code: where it lives

## Purpose

## Requirements

### RED-03 Short name

Given … when … then …

Tests: `ReducerTests/approvedToolFinishingMeansWorkingAgain`
```

- An id is a prefix and a number. Ids are never reused or renumbered; a removed requirement keeps its number retired.
- `Tests:` names Swift test functions as `Type/function`, the same form `swift test --filter` takes.
- Requirements on the untested `WhoIsWorking` target use `Verified by:` with the snapshot or manual check that proves them.
- Draft specs need no `Tests:` lines and end with open questions. A draft becomes `implemented` when every requirement has its line.

## Working with specs

1. Change the spec first: add or edit the requirement. For new work, answer the draft's open questions with the user before coding.
2. Write the failing test and name it on the requirement's `Tests:` line.
3. Write the code, then run the checks:

```bash
swift test
```

```bash
scripts/check-specs.sh
```

`check-specs.sh` fails when an id is used twice, a `Tests:` line names a test that does not exist, an implemented requirement has no proof line, or a test is not named by any spec.

The `whoisworking-spec` skill has the same steps for agents.

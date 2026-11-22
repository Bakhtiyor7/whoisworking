# 07 Summary and formatting

Status: implemented
Code: `Sources/AgentCore/Summary.swift` (`NotchSummary`, `formatElapsed`, `formatElapsedSpoken`, `Session.rowDetail`, `Session.requestTitle`)

## Purpose

Decide what the notch shows from the session list, and the exact words on rows and cards. Views only lay these out.

## Requirements

### SUM-01 Nothing to show

With no sessions the summary is empty. Working and idle sessions alone draw nothing while collapsed.

Tests: `SummaryTests/emptyWhenThereAreNoSessions`, `SummaryTests/workingAndIdleSessionsDrawNothing`

### SUM-02 Wings only when something needs you

The wings show only when at least one session is in `needsApproval`, `waitingForReply` or `error`. Finished sessions alone do not show them.

Tests: `SummaryTests/doneSessionsAloneDoNotShowWings`

### SUM-03 Wing content

The wings show the number of sessions that need you and the wait of the one that has waited longest.

Tests: `SummaryTests/wingsCountSessionsThatNeedYouAndShowTheLongestWait`

### SUM-04 Sections

The expanded panel has three groups in this order: Needs you (longest wait first), Working (by name), Done (unseen first, then idle; newest first within each).

Tests: `SummaryTests/sectionsAreGroupedAndOrdered`

### SUM-05 Elapsed time

Compact form: `now` under 5 s, then `42s`, `4m`, `2h`, `3d`. Spoken form for VoiceOver: "1 second", "4 minutes", "2 hours", "3 days".

Tests: `FormattingTests/elapsed`, `FormattingTests/spokenElapsed`

### SUM-06 Row line

Each row has one line saying what the session is doing: the activity while working, the pending tool or first line of the message when it needs approval, the first line of the message for questions, done and errors, with a fixed fallback per state. Placeholders say "Running · no live status yet".

Tests: `FormattingTests/rowDetailDescribesWhatTheSessionIsDoing`, `FormattingTests/placeholderRowsSayThereIsNoLiveStatusYet`

### SUM-07 Approval title

The Needs you card's headline names the kind of tool: run a command, edit a file, fetch a page, or the tool's own summary.

Tests: `FormattingTests/approvalRequestTitleNamesTheKindOfTool`

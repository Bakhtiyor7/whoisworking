# 14 Antigravity adapter

Status: draft
Depends on: `02-reducer.md`, `05-ingest-and-hook-script.md`, `06-hook-installer.md`
Code: `Sources/AgentCore/AntigravityAdapter.swift`, `HookTarget.antigravity` in `Sources/AgentCore/HookInstaller.swift`

## Purpose

Show local Google Antigravity sessions in WhoIsWorking with the [Antigravity badge](../../Sources/WhoIsWorking/AgentIcons/antigravity.png). The first release covers the macOS app. No Antigravity CLI is installed here, so the CLI is not checked.

Sources, checked on 2026-11-22: the [Antigravity hook reference](https://antigravity.google/docs/hooks?tab=ide) (app, CLI and IDE tabs), and the language server inside the installed app 1.23.2. The language server reads `hooks.json` with a parser that allows comments, and it has pre- and post-invocation hooks. The payload has no event name. The fixtures are CONSTRUCTED from the reference. Until a live capture (ANT-08), Settings and the README call Antigravity support experimental. You decided on 2026-11-22 to register `Stop` before that capture, because without it no turn ever ends.

## Requirements

### ANT-01 Hook configuration

`HookTarget.antigravity` edits the global `~/.gemini/config/hooks.json`. WhoIsWorking owns the top-level `whoisworking` hook group and nothing else (INS-16). It registers `SessionStart`, `PreInvocation`, `PostToolUse` (matcher `""`) and `Stop`, timeout 5 s. `PreToolUse` is never registered, because Antigravity requires a decision in its answer.

Tests: `AntigravityHookInstallerTests/installAddsOneNamedGroupWithTheEventInEachCommand`, `AntigravityHookInstallerTests/otherGroupsAreUntouchedAndUninstallRestoresExactly`, `AntigravityHookInstallerTests/refusesAGroupWithEntriesItDidNotWrite`

### ANT-02 Forwarding and routing

Each handler is `whoisworking-hook antigravity <Event>`, so the header carries the event name (ING-10). `HookMessage.event` routes header agent `antigravity` to the adapter with that name. A message without a valid event name is dropped. The silent hook script answers nothing. The reference documents that any `Stop` decision other than `"continue"` lets the stop happen, and that the other three events take optional answers.

Tests: `HookScriptTests/forwardsTheEventNameWhenGiven`, `AntigravityAdapterTests/routesAntigravityMessagesWithTheirEventName`, `AntigravityAdapterTests/aMessageWithoutAnEventNameIsDropped`

### ANT-03 Session identity and lifecycle

The session id is `conversationId`. The folder is the first of `workspacePaths`. The mapping:

- `SessionStart` → session started.
- `PreInvocation` → observed activity, "Thinking". `PostToolUse` → observed activity with the tool's line. Both have no turn id, so they also mark the start of a new turn (RED-18).
- `Stop` → done, with these exceptions in this order. `terminationReason` `error` → error, with the payload's `error` text. `max_steps_exceeded` → error, "Stopped at the step limit". A reason that names a cancel or interrupt → interrupted. `fullyIdle: false` → still working, "Background tasks running".

Tests: `AntigravityAdapterTests/lifecycleMapsToSessionEvents`, `AntigravityAdapterTests/stopPrecedence`, `AntigravityAdapterTests/commonFieldsGiveIdAndFolder`, `AntigravityAdapterTests/repeatedTurnsReuseTheSession`

### ANT-04 Approval and error states

No Antigravity event means "needs approval": the hooks expose no pending approval. Errors come only from `Stop` (ANT-03). A tool that failed stays an activity line.

Tests: `AntigravityAdapterTests/failedToolsStayActivityLines`

### ANT-05 Lifetime

Events carry no owning pid. Conversations stay between turns and go after 15 minutes of silence, or 4 hours while waiting for the user (SES-08).

Tests: `AntigravityAdapterTests/quietConversationsGoAfterLongSilence`

### ANT-06 Fixtures

Constructed payloads live in `Tests/Fixtures/antigravity/`, one per event and stop case, recorded in `Tests/Fixtures/README.md`. A test maps every one.

Tests: `AntigravityAdapterTests/mapsEveryFixture`

### ANT-07 Docs

`README.md` has install steps for Antigravity, marks the support experimental, and says what is covered.

Verified by: README review

### ANT-08 Live capture

Capture the app's payloads for a new conversation, repeated turns, a normal stop, an interruption, background tasks and an unknown event, with WhoIsWorking running and not running. Confirm that an empty answer passes every registered event. Confirm that the app runs the command through a shell, so `$HOME` in it expands. Record the supported app version. Then drop the experimental label.

## Open questions

1. Can the hook's parent chain identify an owning process (the language server) for cleanup and "Open session"?
2. Does `ANTIGRAVITY_CONVERSATION_ID` in the hook environment match `conversationId` in the payload?

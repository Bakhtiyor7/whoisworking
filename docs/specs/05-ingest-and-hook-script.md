# 05 Ingest and hook script

Status: implemented
Code: `Sources/AgentCore/Ingest.swift` (`EventSocketServer`, `HookScript`, `AppPaths`)

## Purpose

Get hook events from agents into WhoIsWorking without ever slowing or blocking an agent, also when WhoIsWorking is not running.

## Requirements

### ING-01 Socket

WhoIsWorking listens on a Unix socket at `~/Library/Application Support/WhoIsWorking/events.sock`. The folder is owner-only (0700) and the socket is owner-only (0600). Each connection delivers one message.

Tests: `EventSocketTests/receivesOneMessagePerConnectionWithOwnerOnlyPermissions`

### ING-02 Stale socket file

Given a socket file left behind by a WhoIsWorking that is no longer running, when WhoIsWorking starts, then it replaces the file and listens.

Tests: `EventSocketTests/replacesAStaleSocketFile`

### ING-03 One WhoIsWorking at a time

Given another server already listening on the socket, when a second WhoIsWorking starts, then it refuses to start.

Tests: `EventSocketTests/refusesToStartWhenAnotherServerIsListening`

### ING-04 Handler runs before the connection closes

The message handler runs while the connection is still open, so the hook process is still alive and its parent chain can be walked.

Tests: `EventSocketTests/theHandlerRunsBeforeTheConnectionCloses`

### ING-05 Stop

When the server stops, the socket file is removed.

Tests: `EventSocketTests/stopRemovesTheSocket`

### ING-06 Hook script uses only system tools

The hook script is executable and uses only `/bin/sh` and `/usr/bin/nc`.

Tests: `HookScriptTests/isExecutableAndOnlyUsesSystemTools`

### ING-07 Hook script never blocks an agent

The script prints nothing and always exits 0. When WhoIsWorking is not running, or the socket file is stale, it still exits 0 quickly.

Tests: `HookScriptTests/exitsZeroQuicklyAndSilentlyWhenTheAppIsNotRunning`, `HookScriptTests/exitsZeroWhenTheSocketFileIsStale`

### ING-08 Hook script forwards stdin

The script sends a header naming the agent and its parent pid, followed by the hook JSON from stdin, to the socket (`WHOISWORKING_SOCKET` overrides the path).

Tests: `HookScriptTests/forwardsStdinWithAnAgentHeader`

### ING-09 The script makes no decision

The script never approves, denies or changes anything: v1 is status only. This follows from ING-07 (no output, exit 0).

Tests: `HookScriptTests/exitsZeroQuicklyAndSilentlyWhenTheAppIsNotRunning`

### ING-10 Event name in the header

Given an agent whose payload has no event name (Antigravity), its handlers are registered with the event as a second argument: `whoisworking-hook antigravity Stop`. The script then adds `event=<name>` to the header (`whoisworking1 antigravity ppid=<pid> event=Stop`) and forwards stdin unchanged. Without a second argument the header is exactly as before. The script sends `event=` only for a name of letters and leaves anything else out. The parser also accepts only a name of letters; an empty, malformed or repeated `event=` gives no event name. The script still prints nothing and exits 0 (ING-07).

Tests: `HookScriptTests/forwardsTheEventNameWhenGiven`, `HookScriptTests/exitsZeroSilentlyWithAnEventNameAndNoApp`, `HookScriptTests/malformedEventArgumentsAreLeftOut`, `HookMessageTests/headerCarriesTheEventName`, `HookMessageTests/malformedEventNamesAreIgnored`

### ING-11 A connection has 5 seconds

A connection is closed 5 s after it was accepted, however slowly its sender writes. Until then the rules already in force apply: it is also closed after 2 s without data, and at 1 MB. What was read by then is handed on like any other message; a hook sends its whole message in milliseconds.

Tests: `EventSocketTests/aConnectionIsClosedAtItsDeadlineHoweverSlowlyItSends`, `EventSocketTests/theStandardLimitsAreTheOnesStatedHere`

### ING-12 At most 32 connections at once

At most 32 connections are read at the same time. One that arrives while 32 are open is closed at once and its message is not read. The hook script still exits 0 (ING-07); that event is lost. When a connection ends, its place is free again.

Tests: `EventSocketTests/connectionsBeyondTheCapAreClosedAtOnce`, `EventSocketTests/theStandardLimitsAreTheOnesStatedHere`

### ING-13 A connection is read at once, however busy the process is

An accepted connection is read on a thread of its own, started when it is accepted, never on a thread borrowed from a pool the whole process shares. ING-12's cap of 32 bounds these threads. So a message is read, and the deadline of ING-11 kept, while the rest of the app (or, in tests, the other suites) keeps every pooled thread busy. Found on 2026-11-26: on a loaded CI runner, reads queued behind GCD's limited pool, so a message arrived after 3 s, a connection outlived its deadline and the hook script waited out `nc`'s 1 s timeout.

Tests: `EventSocketTests/aConnectionIsReadWhileTheSharedThreadPoolIsBusy`

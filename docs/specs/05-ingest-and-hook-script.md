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

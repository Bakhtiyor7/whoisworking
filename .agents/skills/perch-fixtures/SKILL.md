---
name: perch-fixtures
description: Capture real agent hook payloads for Perch tests, anonymize them and record them in Tests/Fixtures/README.md. Use when adding or correcting an adapter, when a new agent version changes its hook JSON, or when a fixture is marked CONSTRUCTED and a real one is wanted.
---

# Capture test fixtures

Adapter tests should run on payloads from real sessions. `Tests/Fixtures/README.md` says which fixtures are captured and which were built by hand; keep it true.

## Steps

1. Capturing needs the Perch that owns the socket. If the user's Perch is running, ask them to restart it with logging on, or to quit it so you can start one:

```bash
PERCH_LOG_EVENTS=1 .build/debug/Perch
```

2. Have the agent do the thing you need a payload for: a prompt, a tool call, a permission prompt, a failed turn, an interrupt.
3. Raw payloads appear in `~/Library/Application Support/Perch/event-log/`, one file per hook event, named `<timestamp>-<EventName>.json`. Each holds the agent's JSON without the `perch1` header line.
4. Copy the ones you need into `Tests/Fixtures/<agent>-real/` and anonymize every file:
   - home paths become `/Users/me`;
   - session, prompt and turn ids become fixed placeholders, the same placeholder wherever the same id repeats;
   - remove prompt text, command output, file contents, tokens, emails and repository names that are not needed for the test.
5. Read each file once more before saving. Nothing private may enter the repo.
6. Add a section to `Tests/Fixtures/README.md`: CAPTURED or CONSTRUCTED, date, agent and version, what was changed.
7. Add a test that maps every captured file (see `ClaudeCodeRealPayloadTests/mapsEveryCapturedEvent`) and name it in the spec with the `perch-spec` skill.
8. Delete the files you copied from the event log folder when done, and turn logging off.

Fixtures are located through `#filePath` (`fixturesDir` in `Tests/AgentCoreTests/ClaudeCodeAdapterTests.swift`); there is no resource bundle to update.

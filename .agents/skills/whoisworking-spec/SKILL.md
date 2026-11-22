---
name: whoisworking-spec
description: Write or change a WhoIsWorking spec in docs/specs before touching code. Use when adding behaviour, fixing a bug, starting one of the draft specs (Cursor, OpenCode, distribution, design), or when scripts/check-specs.sh fails.
---

# Spec first, then test, then code

`docs/specs/README.md` has the format and the index. Read it and the spec for the area you are changing before anything else.

## Changing behaviour

1. Find the requirement. If the change fits an existing one, edit its wording. If not, add a new one with the next free number for that prefix. Never renumber or reuse an id.
2. Write it as Given/When/Then in plain words. State numbers (timeouts, sizes) exactly; take them from the code or the user, do not guess.
3. Write the failing test in `Tests/AgentCoreTests`, named after the behaviour, and add it to the requirement's `Tests:` line as `Type/function`. Run it and confirm it fails for the right reason:

```bash
swift test --filter ReducerTests/theNewTestName
```

4. Write the minimal code in `AgentCore`. Wire it in `SessionStore` only if needed.
5. Run both checks and report their output:

```bash
swift test
```

```bash
scripts/check-specs.sh
```

## Fixing a bug

A bug means a requirement is missing or a test is. Add or correct the requirement, reproduce the bug with a failing test, then fix it.

## UI requirements

The `WhoIsWorking` target has no tests. Use `Verified by:` and name the snapshot or manual check. Run it with the `whoisworking-verify-ui` skill.

## Starting a draft spec

1. Put the spec's open questions to the user and write the answers into the spec.
2. Check every item marked unverified against the tool's official docs and real captured payloads (`whoisworking-fixtures` skill). Correct the spec.
3. Work one requirement at a time with the loop above.
4. When every requirement has a `Tests:` or `Verified by:` line, set `Status: implemented`, update the index in `docs/specs/README.md`, and update `README.md` if users see a difference.

## Contracts that do not bend

- `06-hook-installer.md`: other tools' entries untouched, backup first, idempotent, refuse invalid input.
- `05-ingest-and-hook-script.md`: the hook script prints nothing, decides nothing and exits 0.

A change that needs to break one of these stops and goes to the user.

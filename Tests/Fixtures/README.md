# Test fixtures

## `claude-code/*.json` (CONSTRUCTED)

Hook payloads built by hand on 2026-11-22 from the documented shapes at
https://code.claude.com/docs/en/hooks (Claude Code 2.1.329/2.1.330 era). They are
**not** captured from a live session. Replace or extend them with captured payloads
when available (run Perch with `PERCH_LOG_EVENTS=1` and copy files from
`~/Library/Application Support/Perch/event-log/`).

## `claude-sessions/*.json` (REAL SHAPE, values changed)

Copied from a real `~/.claude/sessions/<pid>.json` on this machine. Field names and
types are real; paths and a few fields were replaced or removed.

## `claude-code-real/*.json` (CAPTURED, anonymized)

Captured on 2026-11-22 from real Claude Code 2.1.329 CLI sessions with
`PERCH_LOG_EVENTS=1`. Home paths are replaced with `/Users/me`, session and prompt ids
with fixed placeholders. They confirm the constructed fixtures above: real payloads
carry the same fields plus `effort`, `prompt_id` and `scratchpad_dir`, which Perch ignores.

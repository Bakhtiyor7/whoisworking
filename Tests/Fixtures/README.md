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

## `codex/*.json` (CONSTRUCTED)

Codex hook payloads built by hand on 2026-11-22 from https://learn.chatgpt.com/docs/hooks
(redirected from developers.openai.com/codex/hooks), for Codex CLI 0.163. Not captured.

## `codex-rollout/*.jsonl`

`failed-turn.jsonl`: the `task_started` / `task_complete` lines are CAPTURED from a real
Codex CLI 0.163 rollout (a turn that failed with a 400 model error); the `response_item`
line between them is constructed. `completed-turn.jsonl` and `running-turn.jsonl` are
CONSTRUCTED in the same shape. Codex documents the rollout format as unstable.

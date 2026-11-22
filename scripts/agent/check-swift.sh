#!/bin/sh
# Claude Code Stop hook: when Swift sources, tests or specs changed since the last passing run,
# build, test and check the specs. On failure, exit 2 so the agent sees the output and keeps working.
# Silent and fast when nothing changed. Can also be run by hand: scripts/agent/check-swift.sh </dev/null
set -u
INPUT="$(cat 2>/dev/null || true)"
# Already continuing because of this hook: let the agent stop, so it cannot loop.
case "$INPUT" in
  *'"stop_hook_active":true'* | *'"stop_hook_active": true'*) exit 0 ;;
esac
cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/../..}" || exit 0

HASH="$(
  git ls-files -z -co --exclude-standard -- Sources Tests Package.swift docs/specs scripts/check-specs.sh 2>/dev/null |
    LC_ALL=C sort -z | xargs -0 shasum 2>/dev/null | shasum | cut -d' ' -f1
)"
STAMP=".build/agent-check.ok"
if [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$HASH" ]; then exit 0; fi

if OUT="$(swift build 2>&1 && swift test 2>&1 && scripts/check-specs.sh 2>&1)"; then
  mkdir -p .build && printf '%s\n' "$HASH" >"$STAMP"
  exit 0
fi
{
  echo "Perch checks failed (swift build, swift test, scripts/check-specs.sh). Fix this before finishing:"
  # Failure lines first (failed tests, compiler errors, spec problems), then the end of the output.
  printf '%s\n' "$OUT" | grep -E '✘|error:|docs/specs/|no spec names|check-specs:' | head -n 30
  printf '%s\n' "$OUT" | tail -n 8
} >&2
exit 2

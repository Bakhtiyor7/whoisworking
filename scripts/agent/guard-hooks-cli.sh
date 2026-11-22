#!/bin/sh
# Claude Code PreToolUse hook for Bash: blocks `Perch hooks install|uninstall` without --settings,
# so an agent working on Perch cannot edit the real ~/.claude/settings.json or ~/.codex/hooks.json.
# Reads the hook JSON on stdin. Exit 2 = blocked (stderr goes to the agent), 0 = allowed.
INPUT="$(cat 2>/dev/null || true)"
if printf '%s' "$INPUT" | grep -Eq "Perch[\\\\\"']*[[:space:]]+hooks[[:space:]]+(install|uninstall)"; then
  case "$INPUT" in
    *--settings*) exit 0 ;;
  esac
  echo "Blocked: 'Perch hooks install|uninstall' without --settings edits the user's real hook files. Work on a copy: add --settings <path to a copy>. To change the real files, ask the user to run the command." >&2
  exit 2
fi
exit 0

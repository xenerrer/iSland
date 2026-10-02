#!/usr/bin/env bash
# Plays two fake agent sessions through the real hook, so you can watch the island react.
# iSland must be running and the hooks installed (iSland --install-hooks).
#
#   scripts/demo.sh
set -euo pipefail

HOOK="${HOOK:-$HOME/.island/bin/island-hook}"
[ -x "$HOOK" ] || { echo "hook helper not found at $HOOK: run 'iSland --install-hooks' first" >&2; exit 1; }

# ev <session> <project> <event> [extra json fields]
ev() {
  printf '{"session_id":"%s","cwd":"/demo/%s","hook_event_name":"%s"%s}' "$1" "$2" "$3" "${4:+,$4}" | "$HOOK"
  echo "  $2: $3"
  sleep "${STEP:-1.6}"
}

echo "Two sessions start (green dots)"
ev demo-a landing-page SessionStart
ev demo-b api-server SessionStart

echo "landing-page starts working (orange, pulsing)"
ev demo-a landing-page UserPromptSubmit
ev demo-a landing-page PreToolUse '"tool_name":"Edit"'

echo "api-server needs you (red, pulsing, moves to the top)"
ev demo-b api-server UserPromptSubmit
ev demo-b api-server Notification '"message":"Claude needs your permission to use Bash"'

echo "landing-page finishes (green)"
ev demo-a landing-page Stop

echo "api-server resumes, then finishes"
ev demo-b api-server PostToolUse '"tool_name":"Bash"'
ev demo-b api-server Stop

echo "Sessions end (they leave the island)"
ev demo-a landing-page SessionEnd
ev demo-b api-server SessionEnd
echo "Done."

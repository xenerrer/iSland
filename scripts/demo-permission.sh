#!/usr/bin/env bash
# Sends a fake permission request to the running iSland and prints what it would tell Claude Code.
# A card opens in the notch. Click Allow / Deny / Always / Terminal (or press Option-Command-Y / -N / -T),
# or do nothing and watch it hand the question back to the terminal when the countdown ends.
#
#   scripts/demo-permission.sh
set -euo pipefail

HOOK="${HOOK:-$HOME/.island/bin/island-hook}"
[ -x "$HOOK" ] || { echo "hook helper not found at $HOOK: install the hooks from the iSland menu (the ✻ in the menu bar)" >&2; exit 1; }

PAYLOAD='{"session_id":"demo-permission","transcript_path":"/tmp/t.jsonl","cwd":"/demo/api","permission_mode":"default","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"npm test","description":"Run the test suite"},"permission_suggestions":[{"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"npm test:*"}],"behavior":"allow","destination":"localSettings"},{"type":"addDirectories","directories":["/demo/api"],"destination":"session"},{"type":"setMode","mode":"acceptEdits","destination":"session"}]}'

echo "A card is waiting in the notch (${ISLAND_WAIT:-20}s). Answer it there..."
answer="$(printf '%s' "$PAYLOAD" | "$HOOK")"
if [ -z "$answer" ]; then
  echo "No decision: Claude Code would ask in its own terminal prompt."
else
  echo "Claude Code would receive:"
  echo "$answer"
fi

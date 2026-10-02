#!/usr/bin/env bash
# End-to-end test of the permission flow with the real binaries:
#   Claude Code payload -> island-hook -> socket -> iSland -> socket -> island-hook -> stdout (what Claude Code reads)
#
# Isolated on purpose: ISLAND_HOME points everything at a temporary folder and iSland runs --headless, so this
# never touches a running instance, never shows a window and never answers a real session.
#
#   scripts/e2e-permission.sh                      # the debug build
#   APP_BIN=dist/iSland.app/Contents/MacOS/iSland HOOK_BIN=dist/iSland.app/Contents/Helpers/island-hook \
#     scripts/e2e-permission.sh                    # the shipped, signed artifacts
set -euo pipefail
cd "$(dirname "$0")/.."

swift build > /dev/null
BIN="$(swift build --show-bin-path)"
APP_BIN="${APP_BIN:-$BIN/iSland}"
HOOK_BIN="${HOOK_BIN:-$BIN/island-hook}"
export ISLAND_HOME
ISLAND_HOME="$(mktemp -d "${TMPDIR:-/tmp}/isl.XXXXXX")"
APP_PID=""
cleanup() { [ -n "$APP_PID" ] && kill "$APP_PID" 2>/dev/null || true; rm -rf "$ISLAND_HOME"; }
trap cleanup EXIT

# Same shape a real Claude Code 2.1.x sends (captured from a live session): no tool_use_id, a description, three suggestions.
PAYLOAD='{"session_id":"e2e-1","transcript_path":"/tmp/t.jsonl","cwd":"/demo/api","permission_mode":"default","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"npm test","description":"Run the test suite"},"permission_suggestions":[{"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"npm test:*"}],"behavior":"allow","destination":"localSettings"},{"type":"addDirectories","directories":["/demo/api"],"destination":"session"},{"type":"setMode","mode":"acceptEdits","destination":"session"}]}'
ASK='{"session_id":"e2e-1","hook_event_name":"PermissionRequest","tool_name":"AskUserQuestion","tool_input":{}}'

failures=0
pass() { echo "  ok   $1"; }
fail() { echo "  FAIL $1"; failures=$((failures + 1)); }

start_app() {
  "$APP_BIN" --headless --verbose "$@" > "$ISLAND_HOME/app.log" 2>&1 &
  APP_PID=$!
  for _ in $(seq 1 50); do [ -S "$ISLAND_HOME/island.sock" ] && return; sleep 0.1; done
  echo "iSland did not start"; cat "$ISLAND_HOME/app.log"; exit 1
}
stop_app() { kill "$APP_PID" 2>/dev/null || true; wait "$APP_PID" 2>/dev/null || true; APP_PID=""; rm -f "$ISLAND_HOME/island.sock"; }

# json <field path> reads a value from the hook's stdout, e.g. hookSpecificOutput.decision.behavior
json() { python3 -c "
import json, sys
try:
    node = json.loads(sys.argv[1])
    for key in sys.argv[2].split('.'):
        node = node[int(key)] if isinstance(node, list) else node[key]
    print(node)
except Exception:
    print('')
" "$1" "$2"; }

echo "decisions, through the real hook and a real socket"
for mode in allow allowAlways deny terminal; do
  start_app --auto-decide "$mode"
  out="$(printf '%s' "$PAYLOAD" | "$HOOK_BIN")"
  stop_app
  case "$mode" in
    allow)
      [ "$(json "$out" hookSpecificOutput.decision.behavior)" = allow ] && [ -z "$(json "$out" hookSpecificOutput.decision.updatedPermissions)" ] \
        && pass "allow -> {behavior: allow}" || fail "allow: $out" ;;
    allowAlways)
      [ "$(json "$out" hookSpecificOutput.decision.updatedPermissions.0.rules.0.ruleContent)" = "npm test:*" ] \
        && [ "$(json "$out" hookSpecificOutput.decision.updatedPermissions.0.type)" = addRules ] \
        && [ -z "$(json "$out" hookSpecificOutput.decision.updatedPermissions.1)" ] \
        && pass "allowAlways -> applies only the first addRules suggestion (not addDirectories or setMode)" || fail "allowAlways: $out" ;;
    deny)
      [ "$(json "$out" hookSpecificOutput.decision.behavior)" = deny ] && [ -n "$(json "$out" hookSpecificOutput.decision.message)" ] \
        && pass "deny -> {behavior: deny, message}" || fail "deny: $out" ;;
    terminal)
      [ -z "$out" ] && pass "terminal -> prints nothing, Claude asks in its own prompt" || fail "terminal: $out" ;;
  esac
done

echo "failure modes: the agent must never be left hanging"
start=$SECONDS
out="$(printf '%s' "$PAYLOAD" | "$HOOK_BIN")"
[ -z "$out" ] && [ $((SECONDS - start)) -le 1 ] && pass "no app running -> instant, silent" || fail "no app: '$out' after $((SECONDS - start))s"

start_app
start=$SECONDS
out="$(printf '%s' "$PAYLOAD" | ISLAND_WAIT=1 "$HOOK_BIN")"
elapsed=$((SECONDS - start))
[ -z "$out" ] && [ "$elapsed" -le 3 ] && pass "nobody answers -> gives up after the wait (${elapsed}s), prints nothing" || fail "unanswered: '$out' after ${elapsed}s"
sleep 0.3
grep -q "hook left without an answer" "$ISLAND_HOME/app.log" && pass "the island notices that the hook left" || fail "the island did not notice the hook leaving"

: > "$ISLAND_HOME/app.log"
out="$(printf '%s' "$ASK" | "$HOOK_BIN")"
sleep 0.2
if [ -z "$out" ] && ! grep -q "waiting for an answer" "$ISLAND_HOME/app.log"; then
  pass "AskUserQuestion -> never offered to the island"
else
  fail "AskUserQuestion was treated as a yes/no question: '$out'"
fi
stop_app

echo
[ "$failures" -eq 0 ] && echo "all good" || { echo "$failures failure(s)"; exit 1; }

#!/usr/bin/env bash
# Stress test of the real app and hook: a burst of events, garbage on the socket, hung connections and many
# simultaneous permission requests. Isolated (ISLAND_HOME in a temp folder, no window), so it never touches a
# running iSland or a real session. Fails if the app dies, leaks memory badly, or loses events.
#
#   scripts/soak.sh [events]      # default 1500
set -euo pipefail
cd "$(dirname "$0")/.."

EVENTS="${1:-1500}"
swift build > /dev/null
BIN="$(swift build --show-bin-path)"
APP_BIN="${APP_BIN:-$BIN/iSland}"
HOOK_BIN="${HOOK_BIN:-$BIN/island-hook}"

export ISLAND_HOME
ISLAND_HOME="$(mktemp -d "${TMPDIR:-/tmp}/isl.XXXXXX")"
APP_PID=""
cleanup() { [ -n "$APP_PID" ] && kill "$APP_PID" 2>/dev/null || true; rm -rf "$ISLAND_HOME"; }
trap cleanup EXIT

"$APP_BIN" --headless > "$ISLAND_HOME/app.log" 2>&1 &
APP_PID=$!
for _ in $(seq 1 50); do [ -S "$ISLAND_HOME/island.sock" ] && break; sleep 0.1; done
rss() { ps -o rss= -p "$APP_PID" | tr -d ' '; }
failures=0
check() { if [ "$2" = ok ]; then echo "  ok   $1"; else echo "  FAIL $1 ($2)"; failures=$((failures + 1)); fi; }
alive() { kill -0 "$APP_PID" 2>/dev/null && echo ok || echo "the app died"; }

echo "soak: $EVENTS events + abuse + 60 simultaneous questions"
START_RSS=$(rss)

# 1) a burst of real hook invocations, 16 at a time, across 40 sessions
start=$SECONDS
seq 1 "$EVENTS" | xargs -P 16 -I{} sh -c '
  n=$(( {} % 40 ))
  case $(( {} % 3 )) in 0) e=PreToolUse;; 1) e=PostToolUse;; 2) e=Stop;; esac
  printf "{\"session_id\":\"soak-$n\",\"cwd\":\"/soak/p$n\",\"hook_event_name\":\"$e\",\"tool_name\":\"Bash\"}" | "$0"
' "$HOOK_BIN" 2>/dev/null
sleep 1.5
delivered=$(grep -c "iSland: " "$ISLAND_HOME/app.log" || true)
check "burst: $delivered of $EVENTS events delivered in $((SECONDS - start))s" "$([ "$delivered" -ge "$EVENTS" ] && echo ok || echo "lost $((EVENTS - delivered))")"
check "app alive after the burst" "$(alive)"

# 2) garbage on the socket
python3 - "$ISLAND_HOME/island.sock" <<'PY'
import os, socket, sys, time
path = sys.argv[1]
def conn():
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.connect(path); return s
cases = [
    os.urandom(4096),                          # binary junk
    b"{" * 5000,                               # deeply nested, never closed
    b'{"agent":"x","sessionId":"y"',           # truncated JSON, no newline
    b"A" * (2 * 1024 * 1024),                  # 2 MB with no newline
    b'{"agent":"claude","sessionId":"fuzz","event":"Stop","timestamp":0}',  # valid, no newline, then close
    b"\n\n\n",                                 # empty lines
]
for blob in cases:
    try:
        s = conn()
        try: s.sendall(blob)
        except (BrokenPipeError, ConnectionResetError): pass
        s.close()
    except OSError as e:
        print("connect failed:", e); sys.exit(1)
held, refused = [], 0
for _ in range(200):                           # connections that never speak
    try:
        held.append(conn())
    except OSError:                            # macOS queues at most 128 pending connections: the rest are refused, which is fine
        refused += 1
        time.sleep(0.01)
print("  silent connections held: %d, refused: %d" % (len(held), refused))
time.sleep(1.5)
for s in held: s.close()
PY
sleep 0.5
check "app alive after garbage and 200 hung connections" "$(alive)"

# 3) sixty simultaneous permission requests nobody answers: every hook must give up on its own, silently
start=$SECONDS
outputs=$(seq 1 60 | xargs -P 60 -I{} sh -c '
  printf "{\"session_id\":\"q-{}\",\"cwd\":\"/soak/q\",\"hook_event_name\":\"PermissionRequest\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"},\"tool_use_id\":\"tu-{}\"}" | ISLAND_WAIT=3 "$0"
' "$HOOK_BIN" 2>/dev/null | wc -c | tr -d ' ')
elapsed=$((SECONDS - start))
check "60 unanswered questions: all gave up in ${elapsed}s with no output" "$([ "$outputs" = 0 ] && [ "$elapsed" -le 8 ] && echo ok || echo "output=$outputs elapsed=$elapsed")"
sleep 0.5
noticed=$(grep -c "hook left without an answer" "$ISLAND_HOME/app.log" || true)
check "the app noticed all $noticed/60 hooks leaving" "$([ "$noticed" -ge 60 ] && echo ok || echo "only $noticed")"
check "app alive after the questions" "$(alive)"

# 4) still serving after all that
printf '{"session_id":"after","cwd":"/soak/after","hook_event_name":"SessionStart"}' | "$HOOK_BIN"
sleep 0.4
check "still delivers a normal event afterwards" "$(grep -q 'SessionStart session=after' "$ISLAND_HOME/app.log" && echo ok || echo "event missing")"

END_RSS=$(rss)
growth=$(( (END_RSS - START_RSS) / 1024 ))
check "memory: ${START_RSS} KB -> ${END_RSS} KB (+${growth} MB)" "$([ "$growth" -le 80 ] && echo ok || echo "grew ${growth} MB")"

echo
[ "$failures" -eq 0 ] && echo "all good" || { echo "$failures failure(s)"; exit 1; }

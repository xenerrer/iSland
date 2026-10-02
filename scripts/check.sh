#!/usr/bin/env bash
# Everything that can be verified without a human: build, unit tests, end-to-end and stress tests.
#
#   scripts/check.sh              # build + unit tests + end-to-end on the debug build
#   scripts/check.sh --package    # also builds the DMG and runs the end-to-end on the signed, packaged app
#
# Takes about a minute (three with --package). Exits non-zero if anything fails.
set -uo pipefail
cd "$(dirname "$0")/.."

LOG="$(mktemp -d "${TMPDIR:-/tmp}/island-check.XXXXXX")"
failures=0

step() { # step <title> <command...>
  local title="$1"; shift
  printf '  %-58s' "$title"
  if "$@" > "$LOG/step.log" 2>&1; then echo "ok"; else echo "FAILED"; sed 's/^/      /' "$LOG/step.log" | tail -25; failures=$((failures + 1)); fi
}

tests_summary() {
  swift test > "$LOG/tests.raw" 2>&1
  local status=$?
  sed 's/\x1b\[[0-9;]*m//g' "$LOG/tests.raw" > "$LOG/tests.log"
  cat "$LOG/tests.log"
  [ "$status" -eq 0 ] && ! grep -q "✘" "$LOG/tests.log"
}

# The packaged app carries what the music and calendar cards need: the adapter, which must really run from inside the
# bundle after re-signing, and the text macOS shows when it asks for calendar access.
packaged_widgets_ready() {
  local app="$PWD/dist/iSland.app"
  [ -f "$app/Contents/Resources/mediaremote-adapter.pl" ] || { echo "adapter script missing"; return 1; }
  [ -d "$app/Contents/Frameworks/MediaRemoteAdapter.framework" ] || { echo "adapter framework missing"; return 1; }
  plutil -extract NSCalendarsFullAccessUsageDescription raw "$app/Contents/Info.plist" > /dev/null || { echo "calendar usage text missing"; return 1; }
  plutil -extract NSCameraUsageDescription raw "$app/Contents/Info.plist" > /dev/null || { echo "camera usage text missing"; return 1; }
  [ -f "$app/Contents/Resources/pt.lproj/InfoPlist.strings" ] || { echo "pt-BR usage text missing"; return 1; }
  perl -e 'alarm shift; exec @ARGV' 15 /usr/bin/perl "$app/Contents/Resources/mediaremote-adapter.pl" \
    "$app/Contents/Frameworks/MediaRemoteAdapter.framework" get > /dev/null || { echo "adapter does not run from the bundle"; return 1; }
}

# A duplicate key in the Portuguese table is a fatal error the first time the app runs in Portuguese.
l10n_has_no_duplicate_keys() {
  python3 - <<'PY'
import re, sys, collections
keys = re.findall(r'^\s+"((?:[^"\\]|\\.)*)":', open("Sources/iSland/L10n.swift", encoding="utf-8").read().split("private static let portuguese")[1], re.M)
dupes = [k for k, n in collections.Counter(keys).items() if n > 1]
print("duplicate keys:", dupes) if dupes else None
sys.exit(1 if dupes else 0)
PY
}

# The music adapter is third-party code that runs inside Apple's perl: it must be exactly the bytes that were reviewed.
vendored_adapter_unchanged() {
  (cd ThirdParty/mediaremote-adapter && shasum -a 256 -c CHECKSUMS.txt > /dev/null)
}

echo "iSland check"
step "Portuguese strings: no duplicate keys" l10n_has_no_duplicate_keys
step "third-party adapter matches its pinned checksums" vendored_adapter_unchanged
step "swift build" swift build
step "unit tests (core + app)" tests_summary
grep -E "Test run with" "$LOG/tests.log" 2>/dev/null | sed 's/^/      /'
step "end-to-end: hook <-> island, debug build" ./scripts/e2e-permission.sh
step "stress: 1500 events, garbage, 60 simultaneous questions" ./scripts/soak.sh

if [ "${1:-}" = "--package" ]; then
  step "package: .app + .dmg (release, ad-hoc signed)" ./scripts/package.sh
  step "package: signature is valid" codesign --verify --deep --strict dist/iSland.app
  step "package: music adapter and calendar text are inside" packaged_widgets_ready
  step "end-to-end: hook <-> island, packaged artifacts" env \
    APP_BIN="$PWD/dist/iSland.app/Contents/MacOS/iSland" \
    HOOK_BIN="$PWD/dist/iSland.app/Contents/Helpers/island-hook" ./scripts/e2e-permission.sh
fi

echo
if [ "$failures" -eq 0 ]; then echo "all good"; else echo "$failures step(s) failed"; fi
rm -rf "$LOG"
[ "$failures" -eq 0 ]

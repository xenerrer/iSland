#!/usr/bin/env bash
# Photographs the island the way the compositor really draws it: every style over every synthetic wallpaper.
# Needs no permission (the app captures its own windows). Stops a running iSland for a few seconds, then restarts it
# (the .app if that is what was running). Needs the screen awake and unlocked: a locked screen captures as transparent.
#
#   scripts/shots.sh <output-dir> [extra iSland arguments, e.g. -glassTint 0.6]
#   STYLES="glass solid" BACKDROPS="busy" scripts/shots.sh /tmp/shots
#   VARIANT=list scripts/shots.sh /tmp/shots     # list (default: sessions only) | request (with an approval card) | closed

# Heads up: capturing the screen, even only our own windows, makes macOS ask whether the app that launched this
# (Terminal, Claude...) may record the screen. Declining is fine: the capture of our own windows still works.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:?usage: shots.sh <output-dir> [extra iSland arguments]}"
shift
STYLES="${STYLES:-glass clear solid}"
BACKDROPS="${BACKDROPS:-light dark busy}"
VARIANT="${VARIANT:-list}"
case "$VARIANT" in request) VARIANT_FLAG="--request" ;; closed) VARIANT_FLAG="--closed" ;; *) VARIANT_FLAG="" ;; esac

swift build > /dev/null
BIN="$(swift build --show-bin-path)/iSland"
mkdir -p "$OUT"

# Whatever is running now (the .app from run-bundle.sh, or the plain binary) is stopped for the shots and brought back after.
was_bundle=false
was_plain=false
pgrep -f "bundle/iSland.app/Contents/MacOS/iSland" > /dev/null && was_bundle=true
pgrep -f "Products/Debug/iSland" > /dev/null && was_plain=true
if $was_bundle; then pkill -f "bundle/iSland.app/Contents/MacOS/iSland" || true; fi
if $was_plain; then pkill -f "Products/Debug/iSland" || true; fi
if $was_bundle || $was_plain; then sleep 0.5; fi

for style in $STYLES; do
  for backdrop in $BACKDROPS; do
    "$BIN" --selfshot "$OUT/$style-$backdrop-$VARIANT.png" --backdrop "$backdrop" $VARIANT_FLAG -style "$style" "$@" 2>&1 \
      | grep -E "failed" || true
  done
done

if $was_bundle; then
  open -n .build/bundle/iSland.app --stdout "$HOME/.island/app.log" --stderr "$HOME/.island/app.log" --args --verbose
elif $was_plain; then
  ( "$BIN" --verbose > "$OUT/live.log" 2>&1 & )
fi
ls "$OUT"/*.png

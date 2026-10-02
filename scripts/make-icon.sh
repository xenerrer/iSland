#!/usr/bin/env bash
# Builds Resources/AppIcon.icns from the icon the app draws for itself (Sources/iSland/AppIcon.swift).
#
#   scripts/make-icon.sh
set -euo pipefail
cd "$(dirname "$0")/.."

swift build > /dev/null
BIN="$(swift build --show-bin-path)/iSland"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/island-icon.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
MASTER="$WORK/master.png"
SET="$WORK/AppIcon.iconset"
mkdir -p "$SET" Resources

"$BIN" --icon "$MASTER" 2>&1 | grep -q "icon written" || { echo "the app could not draw its icon" >&2; exit 1; }

# name:pixels, the sizes iconutil expects
for entry in icon_16x16:16 icon_16x16@2x:32 icon_32x32:32 icon_32x32@2x:64 icon_128x128:128 icon_128x128@2x:256 \
             icon_256x256:256 icon_256x256@2x:512 icon_512x512:512 icon_512x512@2x:1024; do
  name="${entry%%:*}"; pixels="${entry##*:}"
  sips -z "$pixels" "$pixels" "$MASTER" --out "$SET/$name.png" > /dev/null
done

iconutil -c icns "$SET" -o Resources/AppIcon.icns
cp "$MASTER" Resources/AppIcon-1024.png
echo "OK: Resources/AppIcon.icns"

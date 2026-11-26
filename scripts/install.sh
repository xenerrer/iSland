#!/usr/bin/env bash
# Builds iSland from source and installs it in ~/Applications. Needs only the Command Line Tools (no Xcode, no Apple
# Developer account). An app you build yourself is not quarantined, so macOS opens it without the
# "cannot verify the developer" warning that a downloaded app gets.
#
#   scripts/install.sh              build, install, open
#   INSTALL_DIR=/Applications scripts/install.sh
#   NO_OPEN=1 scripts/install.sh    do not open it afterwards
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v swift > /dev/null 2>&1; then
  echo "The Command Line Tools are missing. Install them with:  xcode-select --install   and run this again." >&2
  exit 1
fi
[ "$(uname -m)" = arm64 ] || echo "Note: iSland is built and tested on Apple silicon only." >&2

DEST="${INSTALL_DIR:-$HOME/Applications}"
mkdir -p "$DEST"

echo "Building iSland $(tr -d '[:space:]' < VERSION) (the first build takes a couple of minutes)..."
APP="$(./scripts/bundle.sh release .build/install | tail -1)"

pkill -f "iSland.app/Contents/MacOS/iSland" 2> /dev/null || true
sleep 1
rm -rf "$DEST/iSland.app"
cp -R "$APP" "$DEST/iSland.app"
echo "Installed: $DEST/iSland.app"

if [ -z "${NO_OPEN:-}" ]; then
  open "$DEST/iSland.app"
  echo "Opened. Point the pointer at the notch, open the island and click the gear to connect your agents."
fi

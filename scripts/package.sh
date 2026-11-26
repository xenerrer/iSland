#!/usr/bin/env bash
# Builds iSland.app and a drag-to-Applications iSland-<version>.dmg into ./dist.
# Needs no Apple Developer account: the app is ad-hoc signed by default.
# Without notarization, users must approve the first launch in System Settings -> Privacy & Security
# (the DMG carries a READ ME FIRST.txt that says how; see also PRD.md, "Distribuição").
#
# The app itself is assembled by bundle.sh, which also documents BUNDLE_ID, VERSION and SIGN_IDENTITY.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="iSland"
VERSION="${VERSION:-$(tr -d '[:space:]' < VERSION)}" # the single source of the version: the VERSION file
export VERSION

DIST="dist"
rm -rf "$DIST"
mkdir -p "$DIST"
APP="$(./scripts/bundle.sh release "$DIST" | tail -1)"

STAGE="$DIST/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp packaging/READ-ME-FIRST.txt "$STAGE/READ ME FIRST.txt"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format ULMO "$DIST/$APP_NAME-$VERSION.dmg" > /dev/null
rm -rf "$STAGE"

echo "OK: $DIST/$APP_NAME-$VERSION.dmg"

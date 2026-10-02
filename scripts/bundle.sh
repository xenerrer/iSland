#!/usr/bin/env bash
# Assembles iSland.app from a build: app binary, hook helper, media adapter, icon and Info.plist, then signs it.
# Shared by package.sh (release, for the DMG) and run-bundle.sh (debug, for trying the app as a real app).
#
#   scripts/bundle.sh <debug|release> <output-dir>
#
#   BUNDLE_ID=...       reverse-DNS id (changing it later resets users' permissions)
#   VERSION=...         shown in the app and in the DMG name
#   SIGN_IDENTITY=...   "-" (ad-hoc, default) or e.g. "Developer ID Application: Name (TEAMID)" once you have one.
#                       With a real identity, also sign with `--options runtime` and the entitlement
#                       com.apple.security.personal-information.calendars, or the hardened runtime will refuse calendar access.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:?usage: bundle.sh <debug|release> <output-dir>}"
OUT="${2:?usage: bundle.sh <debug|release> <output-dir>}"
APP_NAME="iSland"
BUNDLE_ID="${BUNDLE_ID:-com.lucasschoenherr.island}"
VERSION="${VERSION:-0.4.0}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
ADAPTER="ThirdParty/mediaremote-adapter"

[ -f Resources/AppIcon.icns ] || ./scripts/make-icon.sh

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

APP="$OUT/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp "$BIN/iSland" "$APP/Contents/MacOS/$APP_NAME"
cp "$BIN/island-hook" "$APP/Contents/Helpers/island-hook"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# What is playing comes from a Perl script that loads this framework (see ThirdParty/mediaremote-adapter/README.md).
cp -R "$ADAPTER/MediaRemoteAdapter.framework" "$APP/Contents/Frameworks/"
cp "$ADAPTER/mediaremote-adapter.pl" "$APP/Contents/Resources/"
cp "$ADAPTER/LICENSE" "$APP/Contents/Resources/MediaRemoteAdapter-LICENSE.txt"

# The text macOS shows when it asks for calendar access.
CALENDAR_EN="iSland shows your next meeting in the notch. It only reads event titles and times on this Mac, and nothing leaves your computer."
CALENDAR_PT="O iSland mostra sua próxima reunião no notch. Ele só lê títulos e horários dos eventos neste Mac, e nada sai do seu computador."

CAMERA_EN="iSland turns your camera on only while you use the mirror in the notch. The picture is never recorded or sent anywhere."
CAMERA_PT="O iSland só liga a câmera enquanto você usa o espelho no notch. A imagem nunca é gravada nem enviada para lugar nenhum."

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>pt</string></array>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSCalendarsFullAccessUsageDescription</key><string>$CALENDAR_EN</string>
  <key>NSCalendarsUsageDescription</key><string>$CALENDAR_EN</string>
  <key>NSCameraUsageDescription</key><string>$CAMERA_EN</string>
  <key>NSHumanReadableCopyright</key><string>Copyright © 2026. All rights reserved.</string>
</dict>
</plist>
PLIST

mkdir -p "$APP/Contents/Resources/en.lproj" "$APP/Contents/Resources/pt.lproj"
cat > "$APP/Contents/Resources/en.lproj/InfoPlist.strings" <<STRINGS
"NSCalendarsFullAccessUsageDescription" = "$CALENDAR_EN";
"NSCalendarsUsageDescription" = "$CALENDAR_EN";
"NSCameraUsageDescription" = "$CAMERA_EN";
STRINGS
cat > "$APP/Contents/Resources/pt.lproj/InfoPlist.strings" <<STRINGS
"NSCalendarsFullAccessUsageDescription" = "$CALENDAR_PT";
"NSCalendarsUsageDescription" = "$CALENDAR_PT";
"NSCameraUsageDescription" = "$CAMERA_PT";
STRINGS

# A development build (STABLE_REQUIREMENT=1, set by run-bundle.sh) is signed with a requirement that names the app instead
# of the hash of its code. macOS then keeps the permissions you grant it (calendar) across rebuilds; an ad-hoc signature's
# identity is that hash, which changes every time. Releases skip this: there, any ad-hoc app with the same id would
# inherit the permissions.
requirement=()
if [ -n "${STABLE_REQUIREMENT:-}" ]; then requirement=(-r "=designated => identifier \"$BUNDLE_ID\""); fi

# Sign inner code first, then the bundle.
codesign --force --sign "$SIGN_IDENTITY" "$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
codesign --force --sign "$SIGN_IDENTITY" "$APP/Contents/Helpers/island-hook"
codesign --force --sign "$SIGN_IDENTITY" ${requirement[@]+"${requirement[@]}"} "$APP"
codesign --verify --deep --strict "$APP"

echo "$APP"

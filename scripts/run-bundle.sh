#!/usr/bin/env bash
# Builds a debug iSland.app and (re)launches it as a real app, in place of the plain binary.
#
# Why: macOS asks calendar access for the app that is running. A plain binary runs under whatever launched it
# (Terminal, Claude...), so only a real .app can ask for its own. The log goes to ~/.island/app.log.
#
# The build is signed with a requirement that names the app rather than its code (see bundle.sh), so the calendar access
# you grant should survive rebuilds. Watch ~/.island/app.log: "calendar access is authorized" at start means it did.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="$(STABLE_REQUIREMENT=1 ./scripts/bundle.sh debug .build/bundle | tail -1)"

pkill -f "Products/Debug/iSland" 2> /dev/null || true # the plain debug binary
pkill -f "bundle/iSland.app/Contents/MacOS/iSland" 2> /dev/null || true
sleep 0.5

mkdir -p "$HOME/.island"
touch "$HOME/.island/app.log" && chmod 600 "$HOME/.island/app.log" # it records tool names and messages: yours alone
open "$APP" --stdout "$HOME/.island/app.log" --stderr "$HOME/.island/app.log" --args --verbose
sleep 1
pgrep -f "bundle/iSland.app/Contents/MacOS/iSland" > /dev/null && echo "running: $APP" || { echo "did not start; see ~/.island/app.log" >&2; exit 1; }

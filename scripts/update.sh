#!/usr/bin/env bash
# Brings an installed copy up to date: pulls the latest source and installs it again.
# Settings, favorites and history live in ~/.island and the app's preferences, so they are kept.
set -euo pipefail
cd "$(dirname "$0")/.."
git pull --ff-only
exec ./scripts/install.sh

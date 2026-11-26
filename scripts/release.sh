#!/usr/bin/env bash
# Publishes a release on GitHub from this Mac: checks, builds the DMG, tags, uploads the DMG and its checksum.
# It runs here and not in CI on purpose: the DMG must be built with the macOS 26 SDK to include Liquid Glass (the CI
# runners have an older one and would ship the black fallback).
#
#   scripts/release.sh            release the version in the VERSION file
#   scripts/release.sh --dry-run  do everything except tag and upload
set -euo pipefail
cd "$(dirname "$0")/.."

DRY=""; [ "${1:-}" = "--dry-run" ] && DRY=1
VERSION="$(tr -d '[:space:]' < VERSION)"
TAG="v$VERSION"

[ -z "$(git status --porcelain)" ] || { echo "Commit your changes first (the working tree is not clean)." >&2; exit 1; }
[ "$(git rev-parse --abbrev-ref HEAD)" = main ] || { echo "Release from the main branch." >&2; exit 1; }
git rev-parse "$TAG" > /dev/null 2>&1 && { echo "$TAG already exists: bump the VERSION file." >&2; exit 1; }
grep -q "^## \[$VERSION\]" CHANGELOG.md || { echo "CHANGELOG.md has no '## [$VERSION]' section: write the notes first." >&2; exit 1; }

./scripts/check.sh --package
DMG="dist/iSland-$VERSION.dmg"
( cd dist && shasum -a 256 "iSland-$VERSION.dmg" > "iSland-$VERSION.dmg.sha256" )

NOTES="$(mktemp)"
awk -v v="$VERSION" '$0 ~ "^## \\[" v "\\]" {on=1; next} /^## \[/ {on=0} on' CHANGELOG.md > "$NOTES"
cat >> "$NOTES" <<TEXT

---
**Install:** open the DMG, drag iSland to Applications. The first time, macOS says it cannot verify the developer
(this build is not notarized): System Settings > Privacy & Security > "Open Anyway". Or build it yourself with
\`scripts/install.sh\`, which needs no approval. SHA-256 is in the \`.sha256\` file.
TEXT

if [ -n "$DRY" ]; then
  echo "Dry run: built $DMG, would tag $TAG and publish with these notes:"; cat "$NOTES"; rm -f "$NOTES"; exit 0
fi

git tag -a "$TAG" -m "iSland $VERSION"
git push origin "$TAG"
gh release create "$TAG" "$DMG" "$DMG.sha256" --title "iSland $VERSION" --notes-file "$NOTES"
rm -f "$NOTES"
echo "Released $TAG"

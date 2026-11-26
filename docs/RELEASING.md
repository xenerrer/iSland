# Releasing

Everything runs on the maintainer's Mac, with the macOS 26 SDK, so the DMG has Liquid Glass. (CI only builds and tests, on an older SDK where the glass falls back to black: never ship a CI build.)

1. Put the new number in `VERSION` (SemVer) and write the notes under `## [x.y.z]` in `CHANGELOG.md`.
2. Commit to `main`.
3. `scripts/release.sh --dry-run` builds, runs every check, makes the DMG and prints the release notes, and stops there.
4. `scripts/release.sh` does the same, then tags `vX.Y.Z`, pushes the tag and publishes the GitHub Release with the DMG and its `.sha256`.

People who built from source update with `scripts/update.sh`; people with the DMG take the new one from Releases.

## Not done yet (needs money or a decision)

- **Notarization** needs a paid Apple Developer account. Until then the DMG needs the one-time "Open Anyway".
- **Automatic updates for DMG users** (Sparkle): needs a signing key kept by the maintainer and an `appcast.xml` on a public host. Not implemented; source builds update with `scripts/update.sh`.
- **Public repository and license.** The repository is private and `LICENSE` is "all rights reserved". Before making it public (or before anyone can build from source) choose a license on purpose: that is a legal decision, not a technical one.

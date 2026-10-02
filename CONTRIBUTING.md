# Contributing

## Setup
Requirements: macOS 15+, Apple silicon, Command Line Tools (no Xcode needed).

```bash
swift build
scripts/check.sh            # everything: build, tests, end-to-end, stress
scripts/check.sh --package  # also builds the .app and .dmg and verifies the signature
scripts/run-bundle.sh       # build and relaunch a debug .app (needed to try calendar/camera)
```

## Rules of the house
- `scripts/check.sh` must pass before every commit/PR. It also guards duplicate keys in the Portuguese table (`L10n.swift`) and the pinned checksums of `ThirdParty/`.
- Only Apple frameworks; **no network access**, no telemetry. Anything touching the socket, hooks or files must keep the least-privilege posture described in `docs/SECURITY.md`.
- Everything the user sees goes through `L10n` (English key → Portuguese value).
- Add a test with each behaviour change (`Tests/IslandCoreTests` for pure logic, `Tests/iSlandTests` for app state/layout).
- Never read or print credentials; never commit secrets.
- Visual changes: attach a screenshot (`scripts/shots.sh`, or the `--selfshot` dev flag).

## Commits and PRs
Small, focused commits with imperative messages ("Add display picker"). Open a PR against `main`; CI must be green.

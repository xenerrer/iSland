# Changelog
Format: [Keep a Changelog](https://keepachangelog.com/). Versions follow SemVer.

## [Unreleased]
### Added
- Multi-display support: island on the main display by default; all displays or one specific display from Settings → Displays.
- Codex CLI and Gemini CLI support with each agent's own spinner; guided first run; Macs without a notch.
- Mirror, photo, pomodoro, agenda scrolling, new-chat shortcut, hide in full-screen video.
### Changed
- Closing animation sequenced (content leaves, then the container closes).
### Security
- Hardened local socket, display-text sanitization, review gate for long approvals, pinned adapter checksums. See docs/SECURITY.md.

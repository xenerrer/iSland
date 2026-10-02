# iSland

Your MacBook's notch, as a control surface for AI coding agents: **Claude Code**, **Codex CLI** and **Gemini CLI**. Works on Macs without a notch too.

- See at a glance what each session is doing. While Claude works you get the same **✻ spinner** Claude Code shows in the terminal; a session that needs you turns red.
- **The collapsed notch only reports what matters**: the ✻ while something works, red when something needs you, and a green dot for about 8 seconds when the last job finishes. Then it is just the notch again; nothing stays on while everything is at rest.
- **Approve permissions from the notch**: Allow, Deny, "Always allow" (the rule Claude suggests) or hand it back to the terminal. Or press **⌥⌘Y / ⌥⌘N / ⌥⌘T**; the shortcuts exist only while a question is waiting.
- **Every row is a chat, by name**: the title the Claude app shows in its sidebar, with the folder it works in underneath, small. **Click a row to open that exact chat** in the Claude app (a session that runs in a terminal or VS Code brings that app forward instead). The approval card names the chat too, and its hand-back button says "In chat" instead of "Terminal" for chats that live in the Claude app.
- Each row shows how long the turn has been running ("Edit · 1m 20s") or took ("Done · 3m 12s"). A small grey icon marks a chat that does not ask before acting (Claude's *bypass permissions* mode, where commands run without asking, so no Allow/Deny card will ever appear for it), auto-accepts edits, or only plans. Hover the icon for the explanation.
- **A mirror in the notch**: the mirror icon beside the gear turns the camera on and shows you in a circle hanging from the notch; the round button takes a photo (saved as a JPEG in `Pictures/iSland`, after asking you once inside the mirror itself; the picture is not mirrored), and a note offers to show it in Finder. **Back** returns to the usual island and turns the camera off (it is on only while the mirror shows, never recorded). macOS asks for camera access the first time, from the installed app only.
- **New chat in one click**: the pencil icon in the header lists the folders you worked in most recently; a click starts a new chat there, in the Claude app.
- **Your agenda**: a card with the event in progress or the next one (**Google Calendar included**, see below) and a **Join** button on meetings with a Meet, Zoom or Teams link, with a mirror icon beside it to check yourself first. **Scroll up or down inside the card** to move through the rest of the day, one event at a time; "3/5" tells you where you are.
- **Pomodoro**: the timer icon in the header opens its setup (focus, short break, long break, and how many focus periods before the long one; remembered) and starts it; while it runs, the same button pauses and resumes. Beside the collapsed notch there is only a small ring of thirty dots (always thirty, whatever the length) that go out clockwise as the phase runs down (white for focus, green for a break); the exact time and pause / skip / stop are on the card in the open island. Breaks start by themselves; after one it waits for you to start the next focus. A sound plays at each end.
- **The collapsed pill stays balanced**: whatever it shows (count, equalizer, tomato and time, ring, status) is split over the two sides of the notch with the same number on each, so it stays centred.
- **Tidy up**: the × at the right edge of a row takes that chat off the list. It comes back by itself when that chat starts something new, not from idle chatter.
- **Motion**: the default (*Smooth*) follows Apple's own: a soft spring that opens with barely a hint of bounce and closes with none, and content that clears out of a light blur once the island has begun to grow. *Bouncy*, the livelier motion of the original boring.notch, is in the settings menu (Animation). **Time to open** (instant to 1.2 s) is in the settings menu; the default is 120 ms.
- **Steps aside for video**: while another app shows a video in full screen (YouTube, Netflix, any player) the collapsed notch hides its icons, and they return when you leave full screen. A permission question still opens the island. It can be turned off in the settings menu.
- **Settings are behind the gear** in the open island. The ✻ in the menu bar is optional (off by default; "Show icon in menu bar" turns it on). Opening the app a second time shows the island for a few seconds, so the gear is always reachable.
- Optional: soft sounds when a question arrives or a long turn finishes, and hiding the island from screen sharing (both in the ✻ menu, both off by default).
- Liquid Glass body on macOS 26+, pure black pill that fuses with the hardware notch when collapsed. Honors *Reduce Transparency* and *Reduce Motion*.
- If iSland is not running, Claude Code behaves exactly as it always did.

English and Brazilian Portuguese, chosen from the system language.

## Requirements

macOS 15 or later (Liquid Glass needs 26+; it falls back to solid black below that), Apple silicon. Building needs only the Command Line Tools: no Xcode.

## Build and run

```bash
swift build
.build/out/Products/Debug/iSland          # shows in the notch; the ✻ in the menu bar is its menu
.build/out/Products/Debug/iSland --install-hooks --dry-run   # see exactly what would change in ~/.claude/settings.json
.build/out/Products/Debug/iSland --install-hooks             # do it (backs the file up first)
```

To try it as a real app (needed for the calendar, see below), build a debug `.app` and relaunch it in place of the plain binary:

```bash
scripts/run-bundle.sh      # .build/bundle/iSland.app, log in ~/.island/app.log
```

Or from the menu: **✻ → Install Claude Code hooks…**, which explains what changes before doing anything. On a first launch with no hooks installed, iSland offers this once by itself.
`--uninstall-hooks` (or the menu) removes only what iSland added and gives the file back unchanged.

## Install from a DMG

```bash
scripts/package.sh        # dist/iSland.app and dist/iSland-<version>.dmg
```

Open the DMG, drag iSland to Applications. The build is ad-hoc signed (no paid Apple account needed), so macOS asks you to approve the first launch in *System Settings → Privacy & Security → Open Anyway*. The DMG carries a bilingual `READ ME FIRST.txt` that says how.

## How it works

```
Claude Code ──hook──▶ island-hook ──socket ~/.island/island.sock──▶ iSland ──▶ notch
                         ◀──────────── allow / deny / terminal ◀──────────────┘
```

`island-hook` is registered for `SessionStart`, `SessionEnd`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Notification`, `PermissionRequest` and `Stop`. Everything is fire-and-forget (`async`) except `PermissionRequest`, which waits up to 20 s for your answer and otherwise prints nothing, so Claude Code asks in the terminal as usual. It never fails the agent: every error path exits 0 silently.

Everything iSland keeps lives in `~/.island` (socket `0600` in a `0700` folder, plus the helper binary). `ISLAND_HOME` relocates it, which is how the tests stay isolated.

## More than one agent

Each agent tells iSland what it is doing through its own hooks, always through the same small helper (`island-hook --agent codex|gemini`; no argument means Claude Code). Each one shows its own sign of working in the notch, taken from the agent's own terminal: Claude Code's blooming star ✻, Gemini CLI's braille dots in its blue, and Codex CLI's pulsing bullet •.

| Agent | Where the hooks go | What iSland does |
|---|---|---|
| Claude Code | `~/.claude/settings.json` | status, approve or deny permissions, chat names, open the chat |
| Codex CLI | `~/.codex/hooks.json` | status, approve or deny permissions (same protocol as Claude Code). Codex asks you to trust new hooks once: run `/hooks` in Codex |
| Gemini CLI | `~/.gemini/settings.json` | status only (Gemini's hooks run inside its loop and have no approval protocol iSland can rely on); a permission prompt turns the row red |

Connect them from the first-run guide or the settings menu; both save a backup of the file first and touch nothing else. Codex and Gemini are only offered when they seem to be installed. **The Codex and Gemini support was written from their documentation and tested with payloads shaped like it, not against the real programs.**

On a Mac without a notch, iSland draws a virtual one the height of the menu bar; collapsed and with nothing to report it is invisible, and resting the pointer at the top centre still opens it.

## Chat names and "open this chat"

The Claude app keeps one small JSON file per chat in `~/Library/Application Support/Claude/claude-code-sessions/<account>/<organization>/local_<id>.json`. Each has the id Claude Code uses for the conversation (`cliSessionId`, the `session_id` of every hook payload), the name in the app's sidebar (`title`) and the app's own id (`local_…`). iSland matches them up, read-only, off the main thread: a file is asked only for its ids (the first bytes) until its chat is on screen, because a record can weigh 500 KB, and it is read in full again only when it changes. A session with no record there (started in a terminal) gets its name from the end of its transcript, where Claude Code appends a `custom-title` entry, and otherwise shows the folder name.

Clicking a row hands `claude://code/continue?session=local_…` to the Claude app, addressed to it by bundle id. That link is the app's own "continue this chat" entry point, found in its code; the id must have exactly the shape the app accepts or no link is built. None of this is a documented interface: if a new version of the Claude app changes it, rows go back to showing the folder and a click brings the app forward, and nothing else is affected. Chat names are shown on screen, so *Hide from screen sharing* covers them too. `iSland --chat-of <session id>` prints what is found for a session, for debugging.

## Music and calendar

**Music.** macOS 15.4 closed the system's MediaRemote framework to ordinary apps, but not to Apple's own `/usr/bin/perl`. So iSland runs a small Perl script as a child process; the script loads [MediaRemoteAdapter](ThirdParty/mediaremote-adapter/README.md) (BSD-3-Clause, vendored unmodified) and prints one JSON line per change. iSland reads those lines, and the controls send commands back the same way. If Apple ever closes that door, the music card simply stops appearing; nothing else is affected. This is the one place iSland relies on a private interface. The child is stopped when iSland quits (including on `kill`), and leftovers of a crashed run are cleaned up at the next start.

**Calendar.** iSland reads events with EventKit, from whatever calendars macOS has: iCloud, Exchange and **Google**. To get Google Calendar in the island, add the Google account in *System Settings → Internet Accounts* and keep *Calendars* switched on (the ✻ menu has a shortcut). The first time, the card shows **Connect**; clicking it makes macOS ask for calendar access. Nothing is requested before that click, and only a real `.app` can ask (a plain binary would be asking on behalf of Terminal). iSland reads titles, times, the calendar name and meeting links, keeps nothing on disk and sends nothing anywhere. Declined events and all-day events are left out.

Music and agenda can be turned off in the settings menu; both step aside while a permission question is waiting.

## Scripts

| Script | What it does |
|---|---|
| `scripts/check.sh [--package]` | Build, unit tests, end-to-end and stress tests (also on the packaged app with `--package`) |
| `scripts/soak.sh [events]` | Stress test: a burst of events, garbage and hung connections on the socket, 60 simultaneous unanswered questions |
| `scripts/e2e-permission.sh` | Real hook ↔ real socket ↔ real island, isolated and headless; decisions and failure modes |
| `scripts/package.sh` | `.app` + `.dmg` |
| `scripts/bundle.sh <debug\|release> <dir>` | Assembles `iSland.app` (binary, hook helper, music adapter, Info.plist with the calendar permission text, icon) and signs it; used by the two scripts around it |
| `scripts/run-bundle.sh` | Debug `.app` relaunched in place of the plain binary, so calendar access can be asked. Signed with a requirement that names the app instead of its code hash, so the permission you grant should survive rebuilds |
| `scripts/make-icon.sh` | Draws the app icon in code → `Resources/AppIcon.icns` |
| `scripts/demo.sh` | Plays two fake sessions through the real hook so you can watch the island react |
| `scripts/demo-permission.sh` | Sends a fake permission request; answer it in the notch and see what Claude Code would receive |
| `scripts/shots.sh <dir>` | Photographs the island over synthetic wallpapers, as the compositor really draws it (see below) |

## Development flags

`--chat-of <session id>` which Claude app chat a session belongs to · `--newchat`, `--focus` previews · `--demo [--request] [--no-agents] [--paused] [--finished] [--mirror]` pinned-open demo (made-up sessions, track and events; `--no-agents` shows only music and calendar, `--paused` pauses the track, `--finished` shows a job that has just finished) · `--snapshot <png> [--closed] [--request]` render without touching the screen · `--selfshot <png> [--backdrop light|dark|busy]` draw the real island over a synthetic wallpaper and capture it · `--headless` socket + store only · `--auto-decide allow|allowAlways|deny|terminal` answers sessions named `e2e-*` only · `--verbose` · `--whois <pid>` · `-style solid|glass|clear` · `-glassTint 0..1`, `-clearTint`, `-scrim` tuning knobs · `defaults write com.lucasschoenherr.island doneGlance 0` turns the green "finished" dot off (the default is 8 seconds).

`--selfshot` captures the app's own windows with `CGWindowListCreateImage` (marked unavailable in the SDK but present at runtime). macOS does not ask for Screen Recording for your own windows, but it may show a prompt asking whether the launching app may record the screen; declining is fine.

## Learning what an agent really sends

`touch ~/.island/capture-schema` makes the hook record the *shape* of every payload in `~/.island/schema.jsonl`: field names, nesting, types and a few enum-like values (`hook_event_name`, `notification_type`, `tool_name`...). Every other string becomes `"<string>"`, so prompts, commands and paths never reach the disk. Identical shapes are stored once. `rm ~/.island/capture-schema` turns it off. For raw payloads, opt in per run with `ISLAND_DUMP=/path/file.jsonl`.

## Tests

`swift test` runs 174 tests: JSON round trip, hook installer (including "install then uninstall gives back the identical file"), wire protocol over real sockets, the Claude Code adapter, payload redaction, the session store's ordering rules, the Now Playing decoder, the agenda rules (which events show, "in 12 min", meeting links), the island's size math, when the collapsed notch reports something (and when it stays plain), and the chat names (finding a chat by session id, titles that sit after a big block, a record caught mid-write, the transcript fallback, the `claude://` link).

Notes for contributors on the Command Line Tools alone:

- SwiftUI's `@State` is a macro in the macOS 27 SDK and its plugin ships only with Xcode, so the code uses `ObservableObject` and `phaseAnimator`.
- With only the Command Line Tools the build system intermittently fails to hand Swift Testing's macro plugin to the compiler (`plugin for module 'TestingMacros' not found`, on test files that have nothing wrong). `Package.swift` passes the plugin directory explicitly when it exists, which made test builds deterministic.

## Glass without a black band

In the glass styles the top of the island is no longer black: the glass shows the wallpaper all the way up, with only the light tint and scrim that keep text readable (`-glassTint`, `-clearTint`, `-scrim`). Collapsed, the pill is still black so it fuses with the hardware notch.

## Vários monitores
Por padrão a ilha aparece só na tela principal do sistema. Em Ajustes → Telas: Tela principal, Todas as telas ou uma tela específica. Em vídeo em tela cheia os ícones somem (por tela); desligável no menu.

Segurança e QA: `docs/SECURITY.md`, `docs/QA.md`.

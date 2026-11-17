# Boterm 0.3.4 — local build 25, 2026-11-17

- Project dashboard (▦ in the top bar): session time, terminals and agents with live state, code changes from git since the project opened (Boterm's own `.boterm/` excluded), tests that caught failures, fixes and improvements, team actions, MCP time per server and the project history. Clicking an agent opens its terminal.
- Activity pulse: the colored dot of a terminal producing output pulses in the sidebar, pane titles and dashboard; typing echo does not count. Reduced motion shows a static ring.
- `boterm event KIND TEXT` / `events` (MCP `event`, `events`): agents record test-fail, test-pass, fix, improvement, decision and blocker facts; role prompts ask for them.
- Claude agents start with Boterm hooks (`--settings`, added to the user's settings, never replacing them) that report each tool call's `duration_ms`; MCP time is measured for Claude only.
- Opening a project folder with history shows a one-line notice with the last entry and a shortcut to the dashboard.

# Boterm 0.3.3 — local build 24, 2026-11-17

- Project history: `.boterm/HISTORY.md` in the project folder, at most 8 KB, read by the Orquestrador before planning. Only the Orquestrador records entries (`boterm history TITLE SUMMARY`); older entries roll into `HISTORY-archive.md`, which is never loaded automatically.
- Context compaction: `boterm compact SESSION [FOCUS]` sends the agent CLI's own command (`/compact` for Claude and Codex, `/compress` for Gemini CLI) once the terminal has been quiet for 5 s and untouched by typing for 30 s. The Orquestrador records and compacts after each activity finished end to end, never mid-activity.

# Boterm 0.3.2 — local build 23, 2026-11-17

- Sidebar and project tabs update in place: one click selects and shows a terminal even while agents retitle their sessions many times per second.
- Free mosaic: each terminal spans cells of a half-column grid. Drag the corner to change width and height (arrow keys on the focused corner, double click to reset); drag the title to move. Dense packing, no overlap.
- Layout profiles: save mode, order, mosaic sizes, split proportions and sidebar width under a name; reapply them to the current project's terminals by name. Kept across restarts.
- Mensageiro, eighth Development role: the team's only channel to the owner over Telegram (verified chat, token in the Keychain), WhatsApp (self chat, screenshots) and email. Permanent permissions are global, listed and revocable in Settings; only a session launched as Mensageiro can notify, ask or grant.

# Boterm 0.3.1 — local build 22, 2026-11-13

- Build 22: match the native title bar to the dark workspace header and use only Boterm as the window title. Project paths no longer replace the title; the version remains in Settings → About.

- Build 21: show shared conversation history inside both participating terminal panes, colored by speaker. Keep the bottom area for sending messages, without a duplicate transcript. Broadcasts stay within their project; messages remain plain text and never become terminal input.
- Pulse the session's existing color dot and show an attention label for recognized confirmation, selection, login and input prompts. Clear it when the prompt/composer changes or the process ends. Reduced motion uses a static indicator; permissions are never answered automatically.

- Build 20: Gemini (Antigravity) launches the installed `agy` terminal with its existing account, without configuring API credentials. Available in the agent selector and all seven development roles; interactive prompts, local Boterm CLI coordination and the client's permissions are preserved. Gemini CLI remains available as a separate option.

- Build 19: Mosaic beside Split shows the active project's open terminals in a grid that adapts to the available width and height. Selecting a terminal preserves the grid; toggling Mosaic off returns to the selected terminal. Small windows scroll when needed to keep terminal rows usable.

- Build 18: bind Claude's per-session MCP JSON to `--mcp-config=` so initial role prompts cannot be interpreted as configuration file paths. Preserve client options, authentication and permissions; Gemini continues to use its interactive prompt option.

- Ask to save local terminal history before closing a session, window or the app, including ended sessions. Save failures keep the session open; Cancel leaves processes running.
- Save available scrollback and team messages as private UTF-8 archives. Shell → Save History saves without closing; Shell → Saved History opens the archive folder. Archives do not resume agent processes.
- Identify the new window as Boterm 0.3.1 while older running versions remain open.

# Boterm 0.3.0 — local build, 2026-11-13

- Build 16: native project folder picker, four recent folder shortcuts in Development and ten persistent recent projects in the Dock menu. Dock projects open a new named workspace with terminals in the chosen folder; the objective field is preserved.

- Renamed the native application to Boterm with the connected-terminal icon; GitHub URL, extension IDs and bundle identifier retained.
- Project tabs, session sidebar, split terminals, rename/close actions, independent PTYs and visible team messages.
- Agent launcher, symbols, process status and recent task messages; existing voice waveform preserved.
- Per-session MCP integration for Codex/Claude, with no global client config edits.
- Bundled native `boterm` CLI for workspace-scoped session inspection and communication over a private Unix socket.
- Bind control requests to kernel-reported process ancestry to reject forged session identities.
- Copy/paste buttons, native menu and Mac/Control shortcuts; Ctrl+C without selection keeps interrupt behavior.
- Import the installed VS Code theme at launch; preserve original ANSI colors and accent default-colour URLs, paths and shell variables.
- Stable session colour dots; draggable session order; adjustable sidebar, split rows/columns and team area, with keyboard controls.
- Rename project tabs with the pencil; new projects appear before + and the final Private Project tab.
- Dictation stays pinned to its original session and never submits a prompt.
- No restart persistence or automatic model activation; peers must check their inbox.

# Changelog

## Public preview v0.2.9 — 2026-10-27

Terminal 0.2.9; the VS Code extension remains 0.1.3.

- Several terminals at once: Shell → New Window (⌘N) or right-click the Dock icon → New Window. Each window runs its own login shell and opens slightly offset from the previous one.
- New Window menu listing the open terminals.
- Closing a window ends only its session; VozTTY quits with the last window. Quitting with several sessions running asks once.
- A command passed after `--` still runs only in the first window; later windows start a login shell in your home folder.

## Public preview v0.2.8 — 2026-10-26

Terminal 0.2.8; the VS Code extension remains 0.1.3.

- The whole sent prompt is blue, including the indented rows Claude Code and Codex create when they break a long prompt.
- The draft still being written is amber; paths and files are mint; links are lilac.
- New VozTTY → Allow Computer Control… menu item: requests Accessibility and Screen Recording so agent CLIs in the terminal can use the mouse, keyboard and screen; AppleScript automation now has a usage description.
- Signed with a Developer ID so macOS privacy grants survive updates. Not notarized yet.

## Public preview v0.2.7 — 2026-10-26

Terminal 0.2.7; the VS Code extension remains 0.1.3.

- Drag images, audio, PDFs or any file from Finder into the terminal to insert their escaped paths, so assistant CLIs can attach them. No Enter is sent; names with control characters are skipped.
- While dictating, the top-bar language picker and Dictate button hide; Pause, Stop & insert and Cancel appear only once, in the voice strip.
- The interface follows the dictation language: Portuguese labels for pt-BR/pt-PT, English for en-US.

## Public preview v0.2.6 — 2026-10-23

Terminal 0.2.6 and VS Code 0.1.3.

- Full-width 42 px voice history with transparent styling, pause markers and compact controls.
- Updated English README, generated social cover and clearly labeled synthetic-file demo.

### Shared vocabulary

- Shared local vocabulary with preferred spellings and explicit alternatives after transcription.
- Native Edit Vocabulary menu and VS Code Command Palette action; no additional terminal UI.
- Whole-word, case-insensitive, longest-first, single-pass correction; bounded UTF-8 configuration validated before microphone capture.
- Existing no-Enter and no-clipboard behavior preserved. Included in both preview downloads.

## Public preview v0.2.1 — 2026-10-23

Native terminal update; the VS Code extension remains 0.1.2.

- Remove duplicate minimize/maximize/close buttons from the content header; keep the standard macOS title-bar controls.
- Show readable language names while preserving the recognition language IDs and saved preferences.
- Make Dictate easier to find, shorten the keyboard hints and clarify recording, cancellation and review guidance.

## Public preview v0.2.0 — 2026-10-23

This release includes two separate downloads: **VozTTY Terminal 0.2.0** and the **VS Code extension 0.1.2**.

### Native Mac terminal

- AppKit window, local WebKit/xterm.js renderer and real macOS PTY.
- Dictate/Stop & insert, cancellation and transcript recovery.
- Black conversation layout with blue prompt accents and light output.
- Persistent minimize, maximize/restore and close controls.
- Corrected terminal sizing during window resize and restored the app icon glyph.

### VS Code extension

- Microphone control in the integrated terminal, local Apple speech recognition and direct insertion without Enter.
- Original terminal targeting, cancellation on terminal switch/close and recovery on delivery failure.
- Closed-pipe shutdown fix from 0.1.1.
- English command names, status messages, error messages and permission descriptions in 0.1.2. Command IDs remain unchanged.

### Validation and limits

- Twelve JavaScript unit checks and native PTY/resize checks passed locally.
- Maintainer confirmed short voice use in Codex, Claude Code and Antigravity in the native terminal.
- Long controlled acoustic and CLI insertion checks are documented in the README.
- Apple Silicon/macOS 26+ only. Packages are ad hoc signed, not notarized. This remains a preview.

### Native build 14

- Compact hover/click session actions, contextual project pencils and quiet top-bar icons.
- Settings/About with author credit and project information; seven-role development preset with per-role Codex/Claude/Gemini selection and working directory.
- Command/status/diff terminal accents, preserving ANSI; refined black-and-mint macOS icon.

### Native build 15

- Correct About credit to Ricardo Danyalgil Junior; add open source/MIT notice and GitHub link.
- Keep icon exports pointed at the new professional source.

# Boterm 0.3.0 — local build, 2026-11-13

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

# Boterm — native macOS terminal

Project tabs, a session sidebar, split terminals, visible agent messaging and local voice dictation. AppKit + bundled xterm.js + real PTYs; no Node.js runtime or CDN. Apple Silicon and macOS 26+.

Use the agent selector to start Codex, Claude, Gemini or OpenCode with a visible symbol and state. Codex/Claude receive per-session MCP tools; other clients retain their own integration setup. The existing animated microphone history and pause/continue strip are preserved.

See [the agent guide](../docs/AGENT_GUIDE.md) for `boterm list/read/message/inbox/new/send`. Messages never type into another shell. Model CLIs keep their own authentication and permissions. All sessions within a project are shared with its team; other projects are isolated. Maximum 32 terminals per window; messages retain the latest 200 in memory. Closing the application ends its processes.

⌘T adds a terminal. The top bar adds projects, the sidebar switches sessions, and Dividir displays sessions together (stacked in narrow windows). Renomear names a terminal; × closes it after confirmation. New Window remains ⌘N.

Copy/paste works through buttons, native Edit menu, ⌘C/⌘V and Ctrl+C/Ctrl+V. Ctrl+C without selection still interrupts a process. Dictation and dropped files never append Enter. The active VS Code theme is read from the user's local settings and installed extension on launch; third-party themes are not redistributed. CLI ANSI output is preserved without prompt/token recoloring. Without an installed theme, the renderer uses a neutral dark fallback.

## Build and open

From the repository root, with Apple's development tools installed:

```sh
./terminal/build.sh
open terminal/Boterm.app
```

The renderer is vendored with its upstream licenses. There is no Node.js runtime, package installation or CDN dependency in the app. `-- /absolute/executable [arguments...]` starts an executable directly; otherwise the app starts `/bin/zsh -l`. The working directory is inherited, or the home directory when started from `/`.

Current source builds (0.2.4) show a compact, transparent voice activity line inside the terminal while dictation is active. The line is 40 px high, with small text controls and a 28 px waveform, without a card, border or background. The waveform retains the last 20 seconds of real microphone intensity, moves smoothly, and marks paused intervals along the same timeline. The timer counts recorded audio, excluding pauses. This is a short level history held only in memory, not audio playback or a saved recording history; it clears when dictation finishes or is cancelled. Reduced-motion mode updates from microphone events without continuous scrolling. **Pause** stops capturing without discarding earlier audio; **Continue** resumes the same recording. You can **Stop & insert** while recording or paused, or **Cancel** to discard it. Paused speech is excluded. The panel reserves its own space so it does not cover CLI output.

Click **Dictate**, wait for **Listening**, speak, then **Stop & insert**. The shortcut is **Control + Option + V** while the terminal is focused. **Esc** cancels. Select a language from the toolbar. Dictation is passed through xterm.js's paste path, including bracketed paste when the child application requests that mode. It never appends Return.

Window controls live only in the standard macOS title bar. The content header holds the language picker and **Dictate**; both hide while dictating, so the voice strip inside the terminal is the only place with Pause, Stop & insert and Cancel. Labels follow the selected dictation language (Portuguese for pt-BR/pt-PT, English for en-US). The language names map to the same pt-BR, pt-PT and en-US engine identifiers and preserve existing preferences. Closing an active session still asks for confirmation.

No process restoration or notarization yet. Closing a running shell asks for confirmation. Closing the app loses unsent terminal text and unsaved recovery windows.

## Windows

Shell → New Window (⌘N) or right-click the Dock icon → New Window opens another terminal with its own login shell in your home folder. Each window dictates on its own. The Window menu lists open terminals; closing one ends only that session, and Boterm quits with the last window. A command given after `--` runs only in the first window.

## Attaching files

Drag images, audio, PDFs or any other files from Finder onto the terminal. Like Terminal.app, Boterm inserts their shell-escaped paths followed by a space, without Enter; Claude Code and Codex attach images and documents from those paths. Names containing control characters are skipped instead of pasted. Promised files (for example, an image dragged straight from a browser) are not supported yet: save the file first. `VOZ_TEST_MODE=drop` checks the native drop path end to end.

## Allowing computer control

Boterm → **Allow Computer Control…** asks macOS for Accessibility (mouse and keyboard) and Screen Recording. Programs started in the terminal inherit these grants, so an agent CLI can operate other apps. AppleScript automation is requested the first time a program uses it. Anything you run in this terminal gets the same access: allow it only if you trust what runs there.

Ad hoc builds lose every macOS privacy grant (including the microphone) when rebuilt. Release builds are signed with a Developer ID; set `VOZTTY_SIGN` to your identity to keep grants across local rebuilds.

## Unit checks

From the repository root:

```sh
xcrun swiftc -parse-as-library -swift-version 6 \
  test/terminal.unit.swift terminal/PTY.swift terminal/Dictation.swift terminal/TerminalTheme.swift \
  -o /tmp/voztty-terminal-unit
/tmp/voztty-terminal-unit
```

`npm test` also checks prompt recognition, wrapping, Unicode and reused rows.

Checks terminal control removal, preserved Unicode/punctuation, a real child PTY, resize and the difference between a draft and explicitly submitted input.

## Integration harness

`test/terminal.integration.swift` is compiled only with `-D VOZ_TEST` and is excluded from the normal app. Compile it with Main, App, PTY, Dictation, LocalControl, ControlActions, TerminalTheme and `native/Vocabulary.swift` (exclude CLI.swift), place that executable in a temporary copy of the built app, and ad hoc sign the copy before running it. Do not replace the installed application with the test executable.

The harness requires `VOZ_TEST_RESULT`. Modes:

- `VOZ_TEST_MODE=agent-launch`: launches the installed Codex through the native selector and checks its visible process badge without submitting a model prompt.
- `VOZ_TEST_MODE=workspace`: checks independent PTYs, workspace isolation, peer messages, native clipboard, draft paste and the real CLI/socket transport.

With `VOZ_TEST_KEEP_OPEN=1`, `VOZ_TEST_CONTROL_COMMAND` can run a follow-up command in a fresh test terminal. Use it to launch `python3 test/control.integration.py RESULT_JSON /absolute/path/to/boterm`; the control test must run inside that Boterm instance because requests are bound to the calling session's process ancestry. It also rejects an attempted session impersonation.

- `VOZ_TEST_MODE=layout`: resizes the native window through 1120, 620, 800 and 1440 px widths, checks completed grid fitting and ensures no right/bottom overflow. Requires no model login or microphone.
- `VOZ_TEST_MODE=voice-controls`: exercises real microphone metering and continuous history, the panel's Pause/Continue controls, exclusion of paused speech, preserved audio on both sides of a pause, stopping while paused, and PTY insertion without Return. Uses synthetic speech through the speakers; not a recognition benchmark.
- `VOZ_TEST_MODE=inspect`: records startup metadata and optional local `VOZ_TEST_SCREEN`; does not insert a prompt.
- `VOZ_TEST_MODE=cli`: requires `VOZ_TEST_READY` (an input-composer regex) and `VOZ_TEST_TRANSCRIPT` (a test transcript path). Inserts an existing prefix and a long transcript, then verifies the PTY bytes and the visible draft without Enter.
- `VOZ_TEST_MODE=long-microphone`: additionally requires `VOZ_TEST_PHRASE` pointing to `test/fixtures/long-dictation.txt` and `VOZ_TEST_TRANSCRIPT` as the output path. Opens the real microphone and plays synthetic Portuguese speech through the current speakers. Checks opening/closing coverage, capture/file duration, draft insertion and no Return.

`VOZ_TEST_KEEP_OPEN=1` leaves the test window open for visual inspection. Other runs close their own test window when complete. Tests never submit a prompt to a model. Text/screen evidence stays local unless deliberately selected for the documentation; do not commit personal dictations or account details.

The Claude setup helper can confirm trust only when `VOZ_TEST_TRUST_DISPOSABLE=1` and the working directory is empty and named `/tmp/voztty-workspace.*`. Gemini setup remains untrusted. Authentication is never bypassed or supplied by the harness.

## VS Code CLI checks

`test/cli.integration.js` runs through the Extension Development Host, with the actual installed extension, actual CLI processes and a test PTY. It requires `VOZ_TEST_AUDIO`, `VOZ_TEST_RESULT`, `VOZ_TEST_HEADLESS` (an isolated `@xterm/headless` 6.0.0 package path), and `VOZ_TEST_CODEX` / `VOZ_TEST_CLAUDE` executable paths. The speech input is a local synthetic audio file; this test does not open the microphone. The headless renderer is test-only and is not a production dependency.

Read [the validation record](../VALIDACAO.md) before interpreting any test as compatibility or recognition-accuracy evidence.

## App icon

The source concept is `assets/boterm/icon-concept.png`. Run `./terminal/build-icon.sh` to export `terminal/Boterm.icns`, then rebuild. Bundle identifier and helper identifiers remain stable to preserve existing settings and macOS permission identity.

## Vocabulary checks

From the repository root:

```sh
xcrun swiftc native/Vocabulary.swift test/vocabulary.unit.swift -o /tmp/voztty-vocabulary-test
/tmp/voztty-vocabulary-test
```

The shared helper loads the local vocabulary before recording. Both native and VS Code clients receive the corrected final event through the existing protocol. Vocabulary tests cover canonical spelling, explicit aliases, Unicode/word boundaries, longest matches, literal regex characters, single-pass replacement, empty files and invalid entries. The packaged `vocabulary.txt` starter must match the Swift defaults.

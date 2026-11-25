# Boterm — native macOS terminal

Project tabs, a session sidebar, split terminals, visible agent messaging and local voice dictation. AppKit + bundled xterm.js + real PTYs; no Node.js runtime or CDN. Apple Silicon and macOS 26+.

Use the agent selector to start Codex, Claude, Gemini (Antigravity), Gemini CLI or OpenCode with a visible symbol and state. Gemini (Antigravity) starts the installed `agy` terminal with its existing Google account login; Boterm does not configure an API key. The client's model and permissions remain under its own control. Codex/Claude receive per-session MCP tools; other clients retain their own integration setup. The existing animated microphone history and pause/continue strip are preserved.

See [the agent guide](../docs/AGENT_GUIDE.md) for `boterm list/read/message/inbox/new/send`. Messages never type into another shell. Model CLIs keep their own authentication and permissions. All sessions within a project are shared with its team; other projects are isolated. Maximum 32 terminals per window; messages retain the latest 200 in memory. Closing the application ends its processes.

⌘T adds a terminal. The top bar adds projects, the sidebar switches sessions, and Dividir displays sessions together (stacked in narrow windows). Renomear names a terminal; × closes it after confirmation. New Window remains ⌘N.

Mosaico, beside Dividir, arranges all open terminals in the active project using as many columns as the available space allows. Click a pane to work in it, or click Mosaico again to return to the active terminal. Layout changes preserve processes and drafts. Small windows scroll vertically when needed.

Each terminal has a compact, collapsible Conversa history. A direct message and its reply appear in both participants' panes, with names, time and the speaker's terminal color. Broadcasts appear in the project's panes. Enviar mensagem à equipe at the bottom contains only the composer, avoiding a second transcript. Messages never alter the CLI output or send terminal input.

Recognized permission, trust, login and input prompts pulse the session's color dot and show a text attention label. Reduced motion keeps a static marker. Detection uses common CLI prompt patterns, so a client with a different format may need a pattern update. Boterm never selects a menu option or accepts a permission automatically.

Copy/paste works through buttons, native Edit menu, ⌘C/⌘V and Ctrl+C/Ctrl+V. Ctrl+C without selection still interrupts a process. Dictation and dropped files never append Enter. The active VS Code theme is read from the user's local settings and installed extension on launch; third-party themes are not redistributed. CLI ANSI output is preserved. Default-colour links, paths/files and shell variables receive accents in the normal buffer; full-screen programs retain their own styling. Without an installed theme, the renderer uses the VS Code dark terminal palette.

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

No process restoration or notarization yet. Closing a session, window or app asks whether to save its history, close without saving or cancel. A save failure keeps the terminal open. Unsent terminal text and unsaved recovery windows can still be lost.

Build 17 (0.3.1) saves the available terminal scrollback (up to 5,000 retained lines per terminal), project/session labels, project paths and retained team messages as UTF-8 text under `~/Library/Application Support/Boterm/History`. Files are local, with owner-only directory/file permissions. Shell → Save History (⌘S) saves without closing; Shell → Saved History opens the folder in Finder. Archives are for reading, not resuming provider processes. They contain terminal output, including any sensitive text printed there, only when you choose to save.

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

After building, `python3 test/agent-launch.integration.py terminal/Boterm.app/Contents/Resources/bin/boterm` checks all five launchers with a temporary socket and client substitutes, including long literal prompts and Claude's bounded MCP argument. It does not contact model providers.

Checks terminal control removal, preserved Unicode/punctuation, a real child PTY, resize and the difference between a draft and explicitly submitted input.

## Integration harness

`test/terminal.integration.swift` is compiled only with `-D VOZ_TEST` and is excluded from the normal app. Compile it with Main, App, PTY, Dictation, LocalControl, ControlActions, Messenger, TerminalTheme and `native/Vocabulary.swift` (exclude CLI.swift), place that executable in a temporary copy of the built app, and ad hoc sign the copy before running it. Do not replace the installed application with the test executable.

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

The icon source is `assets/boterm/icon-professional.png`. Run `./terminal/build-icon.sh` to export `terminal/Boterm.icns`, then rebuild. Bundle identifier and helper identifiers remain stable to preserve existing settings and macOS permission identity.

## Vocabulary checks

From the repository root:

```sh
xcrun swiftc native/Vocabulary.swift test/vocabulary.unit.swift -o /tmp/voztty-vocabulary-test
/tmp/voztty-vocabulary-test
```

The shared helper loads the local vocabulary before recording. Both native and VS Code clients receive the corrected final event through the existing protocol. Vocabulary tests cover canonical spelling, explicit aliases, Unicode/word boundaries, longest matches, literal regex characters, single-pass replacement, empty files and invalid entries. The packaged `vocabulary.txt` starter must match the Swift defaults.

### Adjustable workspace (local build 13)

Each session has a stable coloured dot in the sidebar and pane heading. Drag a heading or sidebar entry onto another terminal to reorder it within the project; Option-Up/Down does the same from the keyboard. Drag the visible grips to resize the sidebar, split columns/rows, or team message area. Focus a grip and use arrow keys for keyboard resizing. Split panes share column widths and row heights.

Click the pencil beside a project name to edit it; Enter saves, Escape cancels, and leaving the field saves a nonempty name. The + button creates a numbered project before the final Private Project tab. That tab starts its shell only when opened. Projects remain isolated by the existing workspace rules; the label does not add an OS sandbox. Names and layout last for the current window, with no restart restoration.

`VOZ_TEST_MODE=customize VOZ_TEST_UI_SCRIPT=/absolute/path/test/terminal-customize.js` exercises these controls through the native integration harness and can write a screenshot with `VOZ_TEST_SNAPSHOT`.

## Compact controls and development preset (build 14)

The top-right ⋯ menu reveals session actions on mouse hover, click or keyboard activation; Escape closes it. Project pencils appear on hover/focus, while + remains visible. The top bar uses muted icons with colour on interaction. Settings (⚙) contains About, author credit, collaboration, privacy, colour and session-lifetime information.

The ⌘ button opens the Development preset: use “Selecionar pasta…” to browse for the project directory (or type its absolute path), keep an optional objective, and choose Codex/Claude/Gemini (Antigravity)/Gemini CLI for each of seven roles. Selecting or cancelling the folder picker preserves the objective and does not launch the team. Creating the team launches six specialists, then the Orchestrator, in the chosen directory. Each receives its role prompt as an argument, never as interpolated shell code. Antigravity and Gemini CLI use `--prompt-interactive`. Existing sessions stay intact; a project with a live preset team rejects duplicate creation. There must be seven free session slots.

Build 16 keeps ten recent project folders in local preferences, with four quick choices beneath the folder selector. Missing folders are filtered out. The Dock menu lists recent folders above New Window; selecting one opens a named project in a new window with its shell and subsequent terminals in that directory. macOS lists open windows in its standard Dock section. Recent folders survive restarting the app; terminal conversations do not.

The Orchestrator is instructed to maintain `BOTERM_PLAN.md`, assign file ownership, dispatch to ready peer CLI prompts and iterate through implementation, tests, integrations, UX/design, loop review and final evidence. This is model-driven coordination through the existing Boterm tools, not a background job scheduler. Login, trust and tool approvals can require user action. A message alone does not wake a stopped model; the coordinator must check readiness and explicitly submit the next task. Closing the app ends the team. Full autonomous completion across real provider accounts has not been validated.

Terminal accents now include commands, Kotlin/Java/Go/Rust/config files, status words and recognizable diff rows. Only default-colour cells are decorated; ANSI colours, Unicode alignment and full-screen applications retain their own rendering.

## Sidebar selection and free mosaic

Sidebar rows and project tabs are updated in place. Agents retitle their terminals many times per second, and rebuilding the list swallowed clicks; one click on a sidebar row now selects and shows that terminal.

In Mosaico, each terminal occupies cells of a half-column grid. Drag the corner (bottom right) to change width and height, use the arrow keys on the focused corner, or double-click it to restore the default size. Drag the pane title to move a terminal; dense packing fills the gaps. Sizes last for the current window. `test/terminal-mosaic.js` covers resizing, overlap, moving and sidebar selection during title updates.

## Layout profiles

Below Dividir/Mosaico, **Salvar** stores the current arrangement under a name you choose: mode (single, split or mosaic), terminal order, mosaic sizes, split proportions and sidebar width. Choosing a profile rearranges the terminals of the current project that have the same names; it never starts or closes processes. Profiles live in the app preferences and survive restarts. × deletes the selected profile after confirmation. `test/terminal-mosaic.js` covers capture, a broken stored profile and reapplying.

## Mensageiro

The Development preset has an eighth role, Mensageiro (Claude by default, because it must read screenshots). It is the team's only channel to the owner: updates, access, permission and decision requests, waiting for the reply on the same channel.

- **Telegram (verified).** Settings → Configurar Telegram. Copy the BotFather token, click Ler token: it goes from the clipboard straight to the Keychain (`com.danyalgil.boterm.telegram`), is never displayed, and the clipboard is cleared. Send the six-digit code to the bot; only that private chat can answer or grant from then on. `ask` sends Yes once / Yes always / No buttons; free-text and replies to the question also count. Yes always with a scope is recorded by the app itself.
- **WhatsApp and email** are driven by the agent through computer control, following its role prompt: WhatsApp in the owner's chat with himself, every message prefixed `🤖 Boterm:`, replies read by screenshot, no `cmd+↑`. A permanent permission given there is recorded with `grant SCOPE whatsapp|email 'exact reply'`.
- **Permissions** are global (`~/Library/Application Support/Boterm/permissions.json`, 0600). Every agent can read them (`permissions`); only a session launched as Mensageiro by the preset can `notify`, `ask`, `answer` or `grant`. A terminal merely named Mensageiro is refused. Settings lists grants with Revogar.
- Messages to anyone other than the owner need the scope `destinatario:<canal>:<contato>` first.

Not covered: the agents' own CLI approval prompts (Claude/Codex keep those in their own settings), and an idle Mensageiro is not woken automatically by a Telegram answer; it polls `answer`. `test/messenger.unit.swift` covers the store, reply parsing and notify reaching the paired phone app; `test/terminal-messenger.js` runs the CLI on the real socket for the role gate.

## Project history and compaction

`.boterm/HISTORY.md` in the project folder is the team's memory across sessions. The Orquestrador reads it before planning and, after each activity finished end to end, records a short entry with `boterm history 'Title' 'Summary'` (≤2000 characters: outcome, decisions, files, tests, failures, open items). The file stays under 8 KB; older entries move to `.boterm/HISTORY-archive.md`, read only when needed. Only a session launched as Orquestrador by the preset can write; every session reads its own project folder's history. Commit `.boterm/` or ignore it as you prefer.

`boterm compact SESSION [FOCUS]` (MCP `compact`) compacts an agent's context with its own CLI command: `/compact [focus]` for Claude, `/compact` for Codex, `/compress` for Gemini CLI. Antigravity, OpenCode and plain shells are refused rather than guessed. Boterm waits until the terminal has produced no output for 5 s and received no typing for 30 s, then submits it, so the Orquestrador can compact itself at the end of its turn. One pending compaction per terminal; it gives up after 30 minutes.

## Project dashboard

▦ in the top bar replaces the terminals with the project dashboard (the terminals keep running; clicking a terminal or agent returns to it). Cards: session time and live state; code changes since the project opened (`git status`/`diff --numstat HEAD`, read-only with optional locks off, `.boterm/` excluded, 5 s timeout); tests that caught failures, fixes, improvements and blockers reported with `boterm event`; team actions from the message history; MCP time per server; project history. It refreshes every 5 s while open and never replaces nodes under a pressed mouse button.

A terminal is shown as working when it produced output in the last 2.5 s that is not the echo of typing; its dot pulses everywhere it appears. This is an activity signal, not proof that a model is generating.

Claude agents are launched with `--settings` hooks (PreToolUse/PostToolUse for MCP, edit and Bash tools) running `boterm tool`, which reads the hook JSON, sends the tool name and `duration_ms` to the app, prints nothing and always exits 0. Codex, Gemini and other CLIs show no MCP time.

## Visual worlds (build 26)

Two worlds share one structure, chosen in Settings → Aparência and kept in preferences (`world`). **Grelha construída** (default): near-black ground, hairline rules, a blue construction grid visible in empty mosaic cells and while arranging, square identity chips that pulse while a terminal produces output, one orange plane on the active terminal's header, Saira for the count, headings and figures. **Set de rodagem**: tally lamps (red rolling, amber needs you, hollow standby, no halos), camera-tape identity bars, Barlow Condensed headings. Product context lives in `PRODUCT.md`; the direction contract in `.impeccable/surfaces/`; design tokens in `DESIGN.md`. Fonts are bundled under `web/fonts` (OFL, see README there).

Clicking the large count (e.g. 8/32) cycles single view → mosaic → dashboard. "Salvar layout" appears only after an arrangement action in the current project; the profile selector appears once a profile exists.

## Qualidade and learned role rules (build 27)

The Development preset has ten roles (Cibersegurança, after Testes, since 2026-11-25); Qualidade comes just before Mensageiro. After the Orquestrador records an activity in the history, it asks Qualidade to review the cycle. Qualidade keeps `.boterm/ROLES.md`, for example:

```markdown
## Todos
Rode npm test antes de reportar.
## Testes
Anexe o comando exato e a saída da falha.
```

On team launch the app reads the first 8 KB of that file. The page appends `## Todos` and the role's own section (1200 characters each at most) to that role's prompt, labelled as repository data. Other headings are ignored. The dashboard's history line shows how many sections were learned.

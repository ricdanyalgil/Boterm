# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

The interface is HTML/CSS/JS inside a native macOS app (Swift/AppKit + WKWebView, `terminal/web`). Treat it as web for design language, while respecting macOS desktop expectations: a dark title bar, native menus, keyboard shortcuts, a minimum window of 620×380 px.

## Users

Two audiences, weighted equally (confirmed 2026-11-17):

- **Ricardo, daily.** He uses it for hours, with teams of AI coding agents (Codex, Claude, Gemini/Antigravity) working on several projects at once, often eight terminals per project. He talks to it by voice dictation as much as he types.
- **Developers discovering it as open source.** They need to understand on first open what a project, a terminal, an agent and the team are, without reading docs.

## Product Purpose

Boterm is a local terminal for running and coordinating teams of AI coding agents. Each project tab holds real terminals; agents in the same project talk to each other through a local socket/MCP (list, read, message, send). The Development preset launches a role-based team (Orquestrador, Desenvolvimento, Testes, Integrações, UX e design, Engenharia de loop, Resposta e entrega, Mensageiro). Success means one person can supervise eight agents without reading every terminal.

## Positioning

A terminal that is also the agents' shared workspace: agents see and message their peers, with project isolation enforced by process ancestry. It also has local voice dictation that never presses Enter, a Mensageiro role that reaches the owner on Telegram/WhatsApp and records permanent permissions, project history that survives sessions, and idle-gated context compaction.

## Operating Context

- It runs on a Mac, often all day, beside VS Code and a browser. Sessions are long, and the user switches between supervision (who needs me?) and focus (one terminal).
- Agents' CLIs keep their own logins, approvals and permission prompts. Boterm shows attention markers but never answers prompts automatically.
- Per-project memory lives in `.boterm/HISTORY.md` in the project folder. Global permissions are in `~/Library/Application Support/Boterm/permissions.json`.

## Capabilities and Constraints

- Project tabs (top), the project's terminals (left sidebar), terminal stage with single / Dividir (split) / Mosaico (free grid, corner resize, drag to move), layout profiles, team message composer, project dashboard, settings and the Development preset dialog.
- The dark native title bar and the bottom native dictation strip (language, Ditar) are AppKit, outside the web view.
- CSP: `default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; font-src 'self'`. There are no remote fonts, scripts or images; every asset ships in the bundle.
- The terminal renderer is xterm.js; terminal text colours come from the user's VS Code theme.
- Interface language: Portuguese (pt-BR) labels; the dictation strip follows the chosen dictation language.
- "Working" means recent output in a terminal, not proof that a model is generating. Attention detection covers common prompts, not all.

## Brand Commitments

- The name is Boterm. Its icon is a `>_` built cell by cell on a blue construction grid, chalk on near-black, with one orange cursor cell, matching the Grelha construída world (`assets/boterm/icon-grid.svg`, `terminal/Boterm.icns`; since 2026-11-17, replacing the mint `>_`).
- Terminal text colours follow the user's VS Code theme (confirmed binding).
- Structure is binding (confirmed): project tabs on top, terminal list on the left, dictation strip at the bottom.
- Each session keeps a stable identity colour across sidebar, pane and messages.

## Evidence on Hand

Real UI and test captures come from the native harness (`test/terminal-*.js` with `VOZ_TEST_SNAPSHOT`). There are no testimonials, user counts or benchmarks; do not invent any.

## Product Principles

1. Supervision at a glance. The state of every agent (working, waiting, needs you, ended) must be readable without opening its terminal.
2. Terminals own the space. Chrome earns its pixels; secondary controls appear when they become relevant.
3. Progress is visible. Code changes, failures caught, fixes and history are one click away, never in the way.
4. Nothing acts on the user's behalf silently. No automatic Enter, no auto-approved prompts, and outward messages only through the Mensageiro under recorded permissions.
5. First open teaches itself. A newcomer can tell projects, terminals, agents and the team apart.

## Accessibility & Inclusion

Keyboard operation for every control (existing: arrow-key resizing, ⌥↑/↓ reordering, Escape closes menus). `prefers-reduced-motion` replaces pulses with static indicators. Screen-reader mode is on in xterm. Voice dictation is a first-class input.

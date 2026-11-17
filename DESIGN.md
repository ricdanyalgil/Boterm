---
name: Boterm
description: A local terminal where one person supervises a team of AI coding agents; the workspace is a construction grid.
colors:
  ground: "#0c0d10"
  panel: "#101217"
  raise: "#161921"
  rule: "#1f2330"
  rule-strong: "#2c3244"
  construction: "#2e54c4"
  grid-line: "rgb(46 84 196 / .2)"
  grid-strong: "rgb(70 110 230 / .55)"
  text: "#e8e9ec"
  text-2: "#a7acb8"
  text-3: "#8a90a0"
  accent: "#ff4d2e"
  on-accent: "#0c0d10"
  attention: "#ffc53d"
  focus: "#6f8cff"
  add: "#c3e88d"
  del: "#f07178"
  set-ground: "#101012"
  set-panel: "#151518"
  set-raise: "#1c1c20"
  set-rule: "#24252a"
  set-rule-strong: "#34363d"
  set-construction: "#8a8f98"
  set-text: "#ecebe6"
  set-text-2: "#aaaeb5"
  set-text-3: "#8d929b"
  set-attention: "#f2b33d"
  set-tally: "#e5322d"
typography:
  display:
    fontFamily: "Saira, -apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "64px"
    fontWeight: 300
    lineHeight: 0.92
    letterSpacing: "-.02em"
  headline:
    fontFamily: "Saira, -apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "40px"
    fontWeight: 300
    lineHeight: 1
    letterSpacing: "-.01em"
  title:
    fontFamily: "Saira, -apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "18px"
    fontWeight: 500
    lineHeight: 1.2
  body:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Helvetica Neue', sans-serif"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1.4
  label:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Helvetica Neue', sans-serif"
    fontSize: "11px"
    fontWeight: 400
    lineHeight: 1.4
  mono:
    fontFamily: "ui-monospace, 'SF Mono', Menlo, monospace"
    fontSize: "12px"
    fontWeight: 400
    lineHeight: 1.7
  set-display:
    fontFamily: "'Barlow Condensed', -apple-system, sans-serif"
    fontSize: "40px"
    fontWeight: 600
    lineHeight: 1
    letterSpacing: ".02em"
rounded:
  grid: "0px"
  set: "3px"
spacing:
  cell: "8px"
  row-pad: "20px"
  section: "32px"
  bar: "44px"
  pane-header: "30px"
components:
  project-tab:
    textColor: "{colors.text-2}"
    height: "{spacing.bar}"
    padding: "0 6px 0 20px"
  project-tab-selected:
    textColor: "{colors.text}"
  pane-header:
    backgroundColor: "{colors.panel}"
    textColor: "{colors.text-2}"
    height: "{spacing.pane-header}"
    padding: "0 12px"
  pane-header-active:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.on-accent}"
  session-row:
    textColor: "{colors.text-2}"
    padding: "9px 16px 9px 20px"
  session-row-selected:
    backgroundColor: "{colors.raise}"
  identity-chip:
    size: "8px"
    rounded: "{rounded.grid}"
  button-quiet:
    textColor: "{colors.text-2}"
    rounded: "{rounded.grid}"
    padding: "6px 10px"
  button-quiet-hover:
    backgroundColor: "{colors.raise}"
    textColor: "{colors.text}"
  button-primary:
    backgroundColor: "{colors.text}"
    textColor: "{colors.ground}"
    rounded: "{rounded.grid}"
    padding: "6px 10px"
  input:
    backgroundColor: "{colors.panel}"
    rounded: "{rounded.grid}"
    padding: "6px 8px"
  dialog:
    backgroundColor: "{colors.panel}"
    textColor: "{colors.text-2}"
    rounded: "{rounded.grid}"
    padding: "28px"
---

# Design System: Boterm

## Overview

**Creative North Star: "The Construction Grid"**

The workspace is a construction grid. Terminals snap to whole cells, panes are framed on the construction module, and the grid shows itself where work is being arranged: faint in empty mosaic cells, stronger while a pane is resized or moved. Everything else is near-black ground, hairline rules and chalk text, so the terminals (which keep the user's VS Code theme) own the space.

Two worlds share one structure. **Grelha construída** ("grid", the default) is a Crouwel-style grid specimen: square corners, deep-blue construction lines, one earned orange plane. **Set de rodagem** ("set", chosen in Settings → Aparência, persisted natively as the `world` user default and injected as `data-world` at document start) re-skins the same structure as a film set: tally lamps, camera-tape identity bars, condensed call-sheet headers, 3px corners and 10px gutters. The structure is binding in both: project tabs on top, terminals on the left, dictation strip at the bottom.

Density is operational. The large team count (8/32) heads the sidebar, and clicking it cycles single → mosaic → dashboard. Every agent's state is readable from its row without opening it.

**Key Characteristics:**
- Flat, square and ruled: 1px hairlines divide every region, with no cards and no rounded shell in the grid world.
- One orange plane per screen, and only when more than one terminal is visible.
- Identity colour per session, stable across sidebar, pane header and messages.
- Activity is an opacity pulse. Attention is amber. Nothing glows.
- Magnitudes are drawn as rows of 8px cells, the same module as the grid.

## Colors

A near-black, blue-ruled ground with chalk text, one hot orange, and amber reserved for "needs you".

### Primary
- **Signal Orange** (accent): the background of the active terminal's header in split or mosaic view. No other use. In the set world the accent becomes chalk and the active pane is marked by a session-tinted border and a raised header instead.

### Secondary
- **Construction Blue** (construction, grid-line, grid-strong): the mosaic's construction grid, the pane frame (`--frame`, construction at 42%), the slash in the team count, MCP usage cells and voice-level cells. In the set world construction turns neutral grey and the grid is not drawn.
- **Focus Blue** (focus): focus outlines, resize-handle hover, drop targets, links, text selection.

### Tertiary
- **Attention Amber** (attention; set-attention in the set world): the "precisa de você" state. It is used for the state word, a 1px outline around the chip, a 7% row tint and a 1px pane frame.
- **Tally Red** (set-tally, set world only): the lit tally lamp of a working session.
- **Diff Green / Diff Red** (add, del): added and removed code cells, passing and failing test events, and destructive hover (close terminal, delete profile).

### Neutral
- **Ground** (ground): the app background, sidebar, top bar and dashboard.
- **Panel** (panel): pane headers, menus, dialogs, the voice panel and inputs.
- **Raise** (raise): hover and the selected session row.
- **Rule / Rule Strong** (rule, rule-strong): all hairlines. The strong variant is for input, menu and dialog borders and scrollbar thumbs.
- **Chalk / Chalk 2 / Chalk 3** (text, text-2, text-3): names and values, secondary labels, and metadata and times. text-3 is the quietest tone allowed for readable text.
- **Session identity colours**: eight colours assigned in order (#82aaff, #c3e88d, #ffcb6b, #c792ea, #89ddff, #f78c6c, #f071a2, #80cbc4). They are data, set per session as `--session-color`, and are never used as chrome.

### Named Rules
**The One Plane Rule.** Signal Orange fills exactly one surface, the active pane header, and only when split or mosaic puts more than one terminal on screen. A single-terminal view has no orange at all.

**The Amber Means You Rule.** Amber marks only a session waiting on the user. It is never decoration, warning chrome or emphasis.

**The Borrowed Text Rule.** Terminal text colours and the pane body background (`--terminal-bg`) come from the user's VS Code theme. These tokens style everything around the terminal, never inside it.

## Typography

**Display Font:** Saira variable, bundled (falls back to the system UI font). The set world uses Barlow Condensed 500/600, also bundled.
**Body Font:** the system UI stack (-apple-system, SF Pro Text).
**Mono Font:** ui-monospace / SF Mono, for paths, code rows and commits.

**Character:** a light, wide technical grotesk for the numbers that matter, over the native Mac UI face for everything operational. The set world swaps in a condensed, uppercase, call-sheet face for headers.

### Hierarchy
- **Display** (Saira 300, 64px, 0.92): the team count only. It drops to 38px in small windows, and becomes Barlow Condensed 600 at 40px in the set world.
- **Headline** (Saira 300, 40px): the dashboard project name, 28px when small. Dialog titles use Saira 400 at 24px.
- **Title** (Saira 500, 18px): dashboard section titles.
- **Body** (system 13px/1.4): UI default. Session names and pane names are 500.
- **Label** (system 11–12px): provider, state word, times and table headers. In the grid world, row times and pane meta use Saira 12px.
- **Mono** (12px): paths, file rows and the commit list.

### Named Rules
**The Tabular Rule.** Every number that updates (counts, times, pane w×h, dashboard facts) uses tabular numerals.

**The Set Uppercase Rule.** Uppercase condensed headers (pane names, section titles, dialog titles) belong to the set world's call-sheet language only. The grid world keeps its headers in sentence case.

## Layout

There is a fixed frame: a 44px top bar, a resizable sidebar (240px default, 168px min, 50vw max, joined by a 1px handle), and the stage. The brand wordmark sits above the sidebar column. Project tabs are hairline-separated cells, and the view modes (Dividir / Mosaico) and 44px square tool buttons sit at the right.

The stage has three views. In single view, one terminal fills it. In split view, panes share a grid with 6px resize handles. In mosaic view, panes live on a free grid of whole cells: the cell size is exposed as `--cell-w`/`--cell-h`, panes are moved by dragging the header and resized from an 18px corner, and the header shows the live size in cells (w×h). The grid world has zero gutter and panes sit flush on 1px rules. The set world has a 10px gutter.

The dashboard is a 12-column grid divided by rules. The team table spans all 12 columns. Code and MCP take 7 columns with a right rule, and quality and history take the remaining 5. Sections are padded 22px/32px. Below 1000px every section spans the full width.

Small windows (max-width 760px or max-height 520px) shrink the count, drop the state word and task line from rows (the chip still carries state), and hide narrow table columns. Below 750px the view modes are hidden and the sidebar is 180px. Narrow panes drop the provider first (300px), then the meta (200px), and always keep the name.

**The Progressive Controls Rule.** Secondary controls appear when they become relevant. The layout-profile selector exists only when profiles exist, Delete only when one is selected, and Save only after an arrangement action in this project.

## Elevation & Depth

Flat. Depth comes from tonal steps (ground → panel → raise) and 1px rules, never from shadows. Panes draw their top and left frame as an inset 1px rule, and the stage closes the right and bottom edges, so the mosaic reads as one ruled sheet. The single exception is floating overlays: the action menu drops an ambient shadow so it can be read over terminals, and dialogs sit on a 60% black backdrop.

### Shadow Vocabulary
- **Overlay** (`box-shadow: 0 14px 36px rgb(0 0 0 / .5)`): the action menu only.

### Named Rules
**The No Glow Rule.** State is never shown as a halo, glow or coloured shadow. Activity is an opacity pulse of the identity mark (1.2s grid, 1.4s set). Under reduced motion it becomes a static 1px outline in the session colour.

## Shapes

The grid world is entirely square (`--radius: 0`): buttons, inputs, menus, dialogs, panes and chips. The set world softens corners to 3px, turns the chip into a 9px round tally lamp, and rounds dashboard cells by 1px. Icons are drawn on a 16px square, as a 1.4 stroke with square caps and mitred joins. They come from one inline SVG sprite, and the shapes are cells and rules, not glyphs.

**The Straight Bar Rule.** A selected project tab or view mode is marked by a straight 2px bar under its label only. The bar is inset to the label's padding, never runs to the cell edges, and is never curved, pill-shaped or filled.

## Components

### Project tabs and view modes
Text cells 44px high, separated by right rules. Unselected tabs use text-2 and the selected tab uses text plus the 2px bar (`--tab-bar`). An edit pencil appears on hover or focus (always on touch). Private projects use text-3. View-mode buttons use the same bar when pressed.

### Team count
A button heading the sidebar: "now / max" in the display face. The slash is in Construction Blue and turns Focus Blue on hover, and the max is in text-3. Below it is a two-line meta (view name, session duration). Clicking it cycles single → mosaic → dashboard.

### Session row
A three-column grid: an 8px identity chip, the name over the provider and task line, and the state word over a tabular time. The row is at least 54px high and divided by rules. The selected row is raised, and an attention row gets a 7% amber tint. State words come from one function and are used everywhere: **trabalhando**, **precisa de você**, **em espera** (agent idle), **parado** (no agent), **encerrado**.

### Identity mark (signature)
- **Grid:** an 8px square chip in the session colour. Working: opacity pulse. Needs you: 1px amber outline offset 2px. Ended: hollow 1px text-3 square.
- **Set:** a 9px round tally lamp, unlit (hollow ring) by default, lit Tally Red while working, amber when it needs you, plus a 3px camera-tape bar in the session colour at the left of the row and pane header.

### Terminal pane
A 30px header on panel showing the chip, name, provider and meta (w×h · time, right-aligned). The header is the drag handle. In split or mosaic view the active header takes the One Plane, with all text in on-accent. An attention pane takes a 1px amber frame. While arranging (`.arranging`), the grid strengthens to grid-strong and panes dim to 92%.

### Buttons
Quiet by default: transparent, text-2, 6px/10px, at least 28px high, square, and raised on hover with a 150ms ease-out. The primary action (dialogs) is a full-width chalk fill with ground text. The only destructive cue is Diff Red text on hover.

### Inputs / Fields
Panel fill, 1px rule-strong border, square, caret in Focus Blue. Focus is a 1px Focus Blue outline inset by 1px, the same as every focusable element.

### Dashboard
The header is the project name, its path in mono and one facts sentence (session time · n/32 terminais · n trabalhando · n precisam de você). Below it come the team table (40px rows, rules only, state colours as in the sidebar), then code and MCP magnitudes drawn as wrapping rows of 8px cells with 2px gaps (add green, del red, MCP in Construction Blue), then a quality timeline (time, kind, event) and the history list. Each section has a title and one plain sentence.

### Voice panel
Recent microphone level drawn as cells, like the mosaic: 80 columns of up to 7 whole cells over 20 seconds, with pauses as faint bands. The panel sits on panel above the native dictation strip.

## Do's and Don'ts

### Do:
- **Do** keep the orange plane for the active pane header in split or mosaic view only.
- **Do** draw magnitudes and levels as whole cells on the 8px module, never as smooth bars or charts.
- **Do** derive every state word and state colour from the one session-state function. Do not paraphrase it.
- **Do** mark selection with the straight 2px under-label bar or a raise step.
- **Do** let new controls appear only when they become relevant.
- **Do** ship every font, icon and image in the bundle. The CSP allows no remote assets.

### Don't:
- **Don't** put a glow, halo or coloured shadow on lamps, chips or panes.
- **Don't** build hero-metric cards, stat tiles or small uppercase kicker labels over headings on the dashboard. Facts go in a sentence, and magnitudes go in cell rows or the table.
- **Don't** colour terminal text or the pane body from these tokens. That belongs to the user's VS Code theme.
- **Don't** round corners in the grid world, and don't use curved, pill or edge-to-edge selection indicators in either world.
- **Don't** use session identity colours as chrome, or Signal Orange or amber as decoration.
- **Don't** move the binding structure: tabs on top, terminals left, dictation strip at the bottom.

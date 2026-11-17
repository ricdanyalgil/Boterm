---
version: 1
slug: "terminal-web-index-html"
primary_target: "terminal/web/index.html"
related_targets: ["terminal/web/terminal.css","terminal/web/dashboard.js"]
---

# Boterm app shell

Scope: the whole web UI of the macOS app (`terminal/web`): project bar, sidebar, terminal stage (single / split / mosaic), project dashboard, voice panel, dialogs. Mode: Operate.

Audience and job: Ricardo daily, supervising up to eight agents per project, and developers opening it for the first time. They need to see at a glance who works, who waits and who needs them, then focus one terminal. Constraints: tabs on top, terminals on the left, dictation strip at the bottom, terminal text in the user's VS Code theme, CSP without remote assets.

Chosen direction: Grelha construída (fused Crouwel grid specimen), chosen by the user on 2026-11-17 over the assigned Set de rodagem. The Set de rodagem ships as a switchable alternate world (Settings → Aparência). The user's binding notes: no coloured halo on lamps; the selected project tab is marked by a straight bar under its label only, never to the edges, never curved.

## Direction contract

THESIS: The workspace is a construction grid; terminals snap to whole cells and the grid shows itself where work is being arranged. Refuses the rounded-card, single-accent dev-tool shell.

OWN-WORLD: Near-black ground #0c0d10, hairline rules, deep-blue construction lines #1d3b8f, chalk text #e8e9ec, one earned orange plane #ff4d2e on the active terminal's header only. Square corners, small neutral grotesk, tabular numerals, identity colours as small square chips.

STORY: The user reads team size and state from the sidebar's large count (8/32), sees which agent needs them, opens it, rearranges the mosaic by cells, and switches to the dashboard to read the code, quality and history.

FIRST VIEWPORT: The top bar holds the BOTERM wordmark above the sidebar column, project tabs as hairline-separated cells, and Dividir/Mosaico and icons at the right. In the sidebar, a large "8/32" heads the column (clicking it cycles single → mosaic → dashboard), then the terminal rows: chip, role and provider, state and time. The stage holds the terminal mosaic flush on 1px rules, with the active header in orange. The dictation strip sits at the bottom.

FORM: Crouwel grid specimen, dealt challenger, adopted over the assigned direction (candidate 6 of the grounded list). seed:c0474387272a5791

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

Signature interaction: while a mosaic pane is resized or moved, the construction grid strengthens and the pane's live size in cells (w×h) shows in its header; empty cells always show the faint grid. Motion grammar: 150–200 ms ease-out state changes, activity as an opacity pulse of the identity chip (no glow), reduced motion becomes static.

Open decisions: none.

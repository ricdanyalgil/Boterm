'use strict';
// Add colour only to default-colour cells; applications retain their ANSI styling.
function terminalAccents(terminal) {
  let decorations = [], markers = [];
  function clear() {
    for (const decoration of decorations) decoration.dispose();
    for (const marker of markers) marker.dispose();
    decorations = []; markers = [];
  }
  function refresh() {
    clear();
    const buffer = terminal.buffer.active;
    // shortcut: markers belong to the normal buffer; full-screen apps keep their own colours.
    if (buffer.type !== 'normal') return;
    const palette = terminal.options.theme;
    const colors = {url: palette.brightMagenta, path: palette.brightCyan, file: palette.brightCyan, variable: palette.brightYellow, command: palette.brightBlue, error: palette.brightRed, success: palette.brightGreen, warning: palette.brightYellow, added: palette.brightGreen, removed: palette.brightRed};
    for (let row = buffer.viewportY; row < Math.min(buffer.length, buffer.viewportY + terminal.rows); row++) {
      const line = buffer.getLine(row);
      if (!line) continue;
      let text = '', cells = [];
      for (let x = 0; x < line.length; x++) {
        const cell = line.getCell(x);
        if (!cell || cell.getWidth() === 0) continue;
        const chars = cell.getChars() || ' ';
        cells.push({x, start: text.length, end: text.length + chars.length, width: cell.getWidth(), plain: cell.isFgDefault() && cell.isBgDefault() && !cell.isInverse()});
        text += chars;
      }
      const tokens = textTokens(text);
      if (!tokens.length) continue;
      const marker = terminal.registerMarker(row - buffer.baseY - buffer.cursorY);
      if (!marker) continue;
      markers.push(marker);
      for (const token of tokens) {
        // Group adjacent cells so long URLs need one decoration, not one per character.
        let start, end;
        const flush = () => {
          if (start !== undefined) {
            const decoration = terminal.registerDecoration({marker, x: start, width: end - start, foregroundColor: colors[token.kind]?.slice(0, 7), layer: 'bottom'});
            if (decoration) decorations.push(decoration);
          }
          start = end = undefined;
        };
        for (const cell of cells) {
          if (cell.start >= token.start && cell.end <= token.end && cell.plain) {
            start ??= cell.x; end = cell.x + cell.width;
          } else flush();
        }
        flush();
      }
    }
  }
  // Each decoration change makes xterm repaint the whole viewport, and onScroll fires once per scrolled line, so
  // refreshing on every event doubled the cost of nine streaming panes. Colour once output settles (300 ms),
  // and at most once a second while it keeps streaming.
  let quiet, since = 0;
  const schedule = () => {
    const now = Date.now(); since ||= now; clearTimeout(quiet);
    quiet = setTimeout(() => { since = 0; refresh(); }, Math.max(0, Math.min(300, since + 1000 - now)));
  };
  const listeners = [terminal.onWriteParsed(schedule), terminal.onScroll(schedule), terminal.onResize(schedule)];
  return {refresh, dispose() { clearTimeout(quiet); for (const listener of listeners) listener.dispose(); clear(); }};
}
if (typeof module !== 'undefined') module.exports = terminalAccents;

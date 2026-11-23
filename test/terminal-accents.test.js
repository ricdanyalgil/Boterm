const test = require('node:test');
const assert = require('node:assert/strict');
global.textTokens = require('../terminal/web/text-tokens');
const terminalAccents = require('../terminal/web/terminal-accents');
test('decorates Unicode cell positions, preserves ANSI and cleans up listeners/markers', () => {
  const events = {}, drawn = [], markers = [];
  let disposedListeners = 0;
  const cells = [
    ['界', 2], ['', 0], ['😀', 2], ['', 0], [' ', 1],
    ...[...'$HOME $ANSI'].map(c => [c, 1])
  ];
  const line = {length: cells.length, getCell(x) { return {
    getChars: () => cells[x][0], getWidth: () => cells[x][1],
    isFgDefault: () => x < 11, isBgDefault: () => true, isInverse: () => false
  }; }};
  const terminal = {
    rows: 1, buffer: {active: {type: 'normal', viewportY: 0, baseY: 0, cursorY: 0, length: 1, getLine: () => line}},
    options: {theme: {brightYellow: '#ffcc00'}},
    registerMarker(offset) { assert.equal(offset, 0); const m = {dispose() { this.disposed = true; }}; markers.push(m); return m; },
    registerDecoration(options) { drawn.push(options); return {dispose() { options.disposed = true; }}; }
  };
  for (const event of ['onWriteParsed', 'onScroll', 'onResize']) terminal[event] = callback => { events[event] = callback; return {dispose() { disposedListeners++; }}; };
  const accents = terminalAccents(terminal); accents.refresh();
  assert.deepEqual(drawn.map(d => [d.x, d.width, d.foregroundColor]), [[5, 5, '#ffcc00']]);
  terminal.buffer.active.type = 'alternate'; accents.refresh();
  assert.equal(drawn[0].disposed, true); assert.equal(markers[0].disposed, true);
  assert.equal(drawn.length, 1);
  accents.dispose(); assert.equal(disposedListeners, 3);
});

test('accents wait for output to settle and refresh at least once a second while it streams', t => {
  t.mock.timers.enable({apis: ['setTimeout', 'Date']});
  const events = {}; let refreshes = 0;
  const terminal = {rows: 0, buffer: {active: {type: 'alternate'}}, options: {theme: {}}};
  for (const event of ['onWriteParsed', 'onScroll', 'onResize']) terminal[event] = callback => { events[event] = callback; return {dispose() {}}; };
  terminal.buffer.active = {get type() { refreshes++; return 'alternate'; }};
  const accents = terminalAccents(terminal);
  for (let i = 0; i < 100; i++) events.onScroll();
  assert.equal(refreshes, 0, 'no synchronous refresh per scrolled line');
  t.mock.timers.tick(300); assert.equal(refreshes, 1, 'one refresh after output settles');
  for (let ms = 0; ms < 1000; ms += 50) { events.onWriteParsed(); t.mock.timers.tick(50); }
  assert.ok(refreshes >= 2, 'a continuous stream still refreshes within a second');
  accents.dispose();
});

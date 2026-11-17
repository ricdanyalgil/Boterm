const test = require('node:test');
const assert = require('node:assert/strict');
const {plural, formatDuration, sessionBusy, toolTotals} = require('../terminal/web/dashboard');
test('dashboard formats durations and separates output from typing echo', () => {
  assert.equal(plural(1, 'falha apanhada', 'falhas apanhadas'), '1 falha apanhada');
  assert.equal(plural(0, 'falha apanhada', 'falhas apanhadas'), '0 falhas apanhadas');
  assert.equal(formatDuration(42), '42 s');
  assert.equal(formatDuration(600), '10 min');
  assert.equal(formatDuration(3900), '1 h 05 min');
  const now = 100000;
  assert.equal(sessionBusy({lastOutput: now - 1000, lastInput: now - 9000}, now), true);
  assert.equal(sessionBusy({lastOutput: now - 1000, lastInput: now - 1100}, now), false, 'echo of typing is not work');
  assert.equal(sessionBusy({lastOutput: now - 5000, lastInput: 0}, now), false, 'quiet terminal is idle');
  assert.equal(sessionBusy({lastOutput: now - 100, lastInput: 0, ended: true}, now), false);
  assert.equal(sessionBusy({lastOutput: now - 1000, lastInput: 0, lastResize: now - 1500}, now), false, 'redraw after resize is not work');
  assert.equal(sessionBusy({lastOutput: now - 100, lastInput: 0, lastResize: now - 3000}, now), true);
});
test('tool totals split edits, shell commands and MCP time', () => {
  assert.deepEqual(toolTotals({Edit: {calls: 3, seconds: 1}, Write: {calls: 1, seconds: 0}, Bash: {calls: 4, seconds: 9}, 'mcp:github': {calls: 2, seconds: 12.5}, 'mcp:boterm': {calls: 1, seconds: .5}}),
    {edits: 4, shell: 4, mcp: 13, mcpCalls: 3});
});

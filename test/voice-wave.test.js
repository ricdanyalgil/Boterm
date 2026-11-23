'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const voiceWave = require('../terminal/web/voice-wave');

const peak = (d, x) => Math.max(...d.match(/-?[\d.]+,-?[\d.]+/g).map(p => p.split(',').map(Number)).filter(([px]) => Math.abs(px - x) < 0.01).map(([, y]) => Math.abs(y - 32)));

test('draws three ribbons that keep earlier voice at its real place in the 20 s window', () => {
  const {paths} = voiceWave([{at: 1000, level: 0.2}, {at: 11000, level: 1}, {at: 21000, level: 0}], [], 21000);
  assert.equal(paths.length, 3);
  for (const d of paths) assert.ok(d.startsWith('M0,32') && d.endsWith('Z'));
  // The loud sample sits in the middle (x=500), taller than the quiet one and than "now".
  assert.ok(peak(paths[0], 500) > 10, peak(paths[0], 500));
  assert.ok(peak(paths[0], 500) > peak(paths[0], 1000));
  // Twenty seconds later it has scrolled out.
  assert.ok(voiceWave([{at: 1000, level: 1}], [], 22000).paths.every(d => !d.includes(',5.')));
});

test('marks completed and ongoing pauses by wall time, then expires them', () => {
  const pauses = [{start: 5000, end: 9000}, {start: 10000}];
  assert.deepEqual(voiceWave([], pauses, 12000).bands, [{x: 650, width: 200}, {x: 900, width: 100}]);
  assert.deepEqual(voiceWave([], [{start: 5000, end: 9000}], 30000).bands, []);
});

test('falls to the baseline when the meter stops and rejects invalid geometry', () => {
  const {paths, bands} = voiceWave([{at: 1000, level: 1}, {at: NaN, level: 1}, {at: 2000, level: Infinity}], [{start: NaN}, {start: 1, end: NaN}], 2000);
  assert.ok(paths[0].includes('970.0,'));
  for (const d of paths) assert.ok(!/NaN|Infinity/.test(d));
  assert.deepEqual(bands, []);
});

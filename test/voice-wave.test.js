'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const voiceWave = require('../terminal/web/voice-wave');

const heights = d => d.match(/-?[\d.]+,-?[\d.]+/g).map(p => Math.abs(Number(p.split(',')[1]) - 32));

test('draws three closed ribbons that taper to the baseline at both ends', () => {
  const ribbons = voiceWave(1, 500);
  assert.equal(ribbons.length, 3);
  for (const d of ribbons) {
    assert.ok(d.startsWith('M0.0,32.00') && d.endsWith('Z'));
    assert.ok(d.includes('1000.0,32.00'));
  }
});

test('speech lifts the ribbons; silence leaves a thin living line', () => {
  const loud = Math.max(...voiceWave(1, 500).flatMap(heights));
  const quiet = Math.max(...voiceWave(0, 500).flatMap(heights));
  assert.ok(loud > 20 && loud <= 29.3, loud);
  assert.ok(quiet > 0 && quiet < 1.3, quiet);
});

test('rejects invalid input instead of drawing NaN geometry', () => {
  for (const d of [...voiceWave(NaN, NaN), ...voiceWave(Infinity, 0), ...voiceWave(-1, 0)]) assert.ok(!/NaN|Infinity/.test(d));
  assert.deepEqual(voiceWave(5, 0), voiceWave(1, 0));
});

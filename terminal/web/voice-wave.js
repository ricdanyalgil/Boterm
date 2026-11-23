'use strict';
// Live spectral ribbons for the voice panel: three lobed sine ribbons whose height follows the
// current microphone level. No audio or transcript is stored here; only one level and a clock.
const VOICE_RIBBONS = [
  {weight: 1, frequency: 2.6, speed: 0.0021, offset: 0},
  {weight: 0.78, frequency: 3.4, speed: -0.0027, offset: 1.7},
  {weight: 0.6, frequency: 4.3, speed: 0.0034, offset: 3.1}
];
function voiceWave(level, time, steps = 96) {
  const value = Number.isFinite(level) ? Math.max(0, Math.min(1, level)) : 0;
  const clock = Number.isFinite(time) ? time : 0;
  // A thin living line while listening in silence; speech lifts the ribbons toward the strip's edge.
  const height = 1.2 + value * 28;
  return VOICE_RIBBONS.map(ribbon => {
    const phase = ribbon.offset + clock * ribbon.speed * (1 + value * 1.5);
    const upper = [], lower = [];
    for (let i = 0; i <= steps; i++) {
      const t = i / steps * 2 - 1;
      // Taper to the baseline at both ends, so the ribbons read as one voice in the middle of the line.
      const taper = Math.pow(1 - t * t, 1.6);
      const h = height * ribbon.weight * taper * Math.abs(Math.sin(t * ribbon.frequency * Math.PI + phase));
      const x = (i / steps * 1000).toFixed(1);
      upper.push(`${x},${(32 - h).toFixed(2)}`);
      lower.push(`${x},${(32 + h).toFixed(2)}`);
    }
    return `M${upper.join(' L')} L${lower.reverse().join(' L')} Z`;
  });
}
if (typeof module !== 'undefined') module.exports = voiceWave;

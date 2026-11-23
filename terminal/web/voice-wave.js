'use strict';
// Voice panel wave: the last 20 seconds of microphone level, drawn as three spectral ribbons
// (Siri-like lobes) that scroll left with time, plus the pauses as bands.
// Only levels and local timestamps live here; no audio or transcript.
const VOICE_RIBBONS = [
  {weight: 1, period: 900, offset: 0},
  {weight: 0.8, period: 640, offset: 1.7},
  {weight: 0.62, period: 470, offset: 3.1}
];
function voiceWave(samples, pauses, now) {
  const x = time => Math.max(0, Math.min(1000, (time - now + 20000) / 20));
  const recent = samples.filter(s => Number.isFinite(s.at) && Number.isFinite(s.level) && s.at >= now - 20000 && s.at <= now);
  const points = recent.map(s => ({at: s.at, x: x(s.at), level: Math.max(0, Math.min(1, s.level))}));
  const last = recent.at(-1);
  // Meter silence is not voice: when readings stop, the ribbons fall back to the baseline.
  if (last && now - last.at > 400) points.push({at: last.at + 400, x: x(last.at + 400), level: 0});
  const first = points[0]?.x ?? 1000;
  const paths = VOICE_RIBBONS.map(r => {
    const shape = points.map(p => {
      // Lobes are anchored to each sample's time, so they travel left with the history.
      const lobe = 0.15 + 0.85 * Math.abs(Math.sin(p.at / r.period * Math.PI + r.offset));
      // The oldest seconds fade into the left edge.
      const fade = Math.min(1, p.x / 120);
      return {x: p.x.toFixed(1), h: (0.6 + p.level * 27) * r.weight * lobe * fade};
    });
    const upper = [`0,32`, `${first.toFixed(1)},32`, ...shape.map(p => `${p.x},${(32 - p.h).toFixed(2)}`), '1000,32'];
    const lower = shape.reverse().map(p => `${p.x},${(32 + p.h).toFixed(2)}`);
    return `M${upper.join(' L')} L${lower.length ? lower.join(' L') : '1000,32'} L${first.toFixed(1)},32 Z`;
  });
  const bands = pauses.filter(p => Number.isFinite(p.start) && Number.isFinite(p.end ?? now) && (p.end ?? now) >= p.start && (p.end ?? now) >= now - 20000 && p.start <= now)
    .map(p => ({x: x(p.start), width: x(p.end ?? now) - x(p.start)}));
  return {paths, bands};
}
if (typeof module !== 'undefined') module.exports = voiceWave;

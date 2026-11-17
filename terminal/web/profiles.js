'use strict';
// Layout profiles: named arrangements kept by the app across launches. A profile arranges the
// terminals that exist (matched by name); it never starts processes.
let layoutProfiles = {};
function currentLayout() {
  const panes = [...sessions.values()].filter(s => s.workspace === activeWorkspace)
    .map(s => ({name: s.name, w: Number(s.host.dataset.w) || 0, h: Number(s.host.dataset.h) || 0}));
  return {mode: mosaic ? 'mosaic' : split ? 'split' : 'single', sidebar: document.getElementById('sidebar').clientWidth, splitColumns, splitRows, panes};
}
function applyLayout(layout) {
  if (!layout || !Array.isArray(layout.panes)) return;
  mosaic = layout.mode === 'mosaic'; split = layout.mode === 'split';
  if (Number.isFinite(layout.sidebar)) document.getElementById('sidebar').style.width = `${clamp(layout.sidebar, 110, innerWidth * .5)}px`;
  if (Number.isFinite(layout.splitColumns)) splitColumns = clamp(layout.splitColumns, 15, 85);
  if (Array.isArray(layout.splitRows) && layout.splitRows.every(Number.isFinite)) splitRows = layout.splitRows.slice(0, 16);
  const peers = [...sessions.values()].filter(s => s.workspace === activeWorkspace), used = new Set();
  const ordered = [];
  for (const pane of layout.panes) {
    const s = peers.find(p => p.name === pane.name && !used.has(p)); if (!s) continue;
    used.add(s); ordered.push(s);
    for (const key of ['w', 'h']) { if (pane[key] > 0) s.host.dataset[key] = Math.min(32, Math.round(pane[key])); else delete s.host.dataset[key]; }
  }
  const rest = peers.filter(s => !used.has(s)), order = [...ordered, ...rest];
  const others = [...sessions.values()].filter(s => s.workspace !== activeWorkspace);
  sessions.clear(); for (const s of [...order, ...others]) sessions.set(s.id, s);
  const grid = document.getElementById('terminal'); for (const s of sessions.values()) grid.append(s.host);
  renderNavigation(); fitVisible();
}
function renderLayoutProfiles(selected = document.getElementById('layout-profile').value) {
  const select = document.getElementById('layout-profile');
  select.replaceChildren(new Option('Perfil de layout…', ''), ...Object.keys(layoutProfiles).sort().map(name => new Option(name, name)));
  select.value = layoutProfiles[selected] ? selected : '';
  document.getElementById('layout-delete').disabled = !select.value;
}
if (typeof document !== 'undefined') document.addEventListener('DOMContentLoaded', () => {
  const select = document.getElementById('layout-profile');
  select.onchange = () => { applyLayout(layoutProfiles[select.value]); renderLayoutProfiles(select.value); };
  document.getElementById('layout-save').onclick = () => send({type: 'saveLayout', name: select.value, layout: JSON.stringify(currentLayout())});
  document.getElementById('layout-delete').onclick = () => { if (select.value) send({type: 'deleteLayout', name: select.value}); };
  send({type: 'layoutProfiles'});
});

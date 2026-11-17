'use strict';
let draggedSession, splitColumns = 50, splitRows = [];
const clamp = (value, min, max) => Math.max(min, Math.min(max, value));
function resizeHandle(label, orientation, adjust) {
  const handle = document.createElement('div');
  handle.className = `resize-handle resize-${orientation}`;
  handle.tabIndex = 0; handle.setAttribute('role', 'separator');
  handle.setAttribute('aria-label', label); handle.setAttribute('aria-valuenow', '50'); handle.setAttribute('aria-valuemin', '0'); handle.setAttribute('aria-valuemax', '100'); handle.setAttribute('aria-orientation', orientation);
  handle.title = `${label} · arraste ou use as setas`;
  const apply = delta => {
    const value = adjust(delta);
    if (Number.isFinite(value)) handle.setAttribute('aria-valuenow', String(Math.round(value)));
    fitVisible();
  };
  handle.addEventListener('pointerdown', event => {
    if (event.button !== 0) return;
    event.preventDefault(); event.stopPropagation(); handle.setPointerCapture(event.pointerId);
    let last = orientation === 'vertical' ? event.clientX : event.clientY;
    handle.onpointermove = move => {
      const position = orientation === 'vertical' ? move.clientX : move.clientY;
      apply(position - last); last = position;
    };
    handle.onpointerup = handle.onlostpointercapture = () => { handle.onpointermove = null; };
  });
  handle.addEventListener('keydown', event => {
    const directions = orientation === 'vertical' ? {ArrowLeft: -16, ArrowRight: 16} : {ArrowUp: -16, ArrowDown: 16};
    if (directions[event.key]) { event.preventDefault(); apply(directions[event.key]); }
  });
  return handle;
}
function updateSplitLayout(count) {
  const grid = document.getElementById('terminal');
  const panes = [...grid.children].filter(pane => !pane.hidden);
  grid.style.gridAutoFlow = grid.style.gridAutoRows = '';
  for (const pane of panes) pane.style.gridColumn = pane.style.gridRow = '';
  if (mosaic) {
    const balanced = Math.ceil(Math.sqrt(count * grid.clientWidth / Math.max(1, grid.clientHeight) / 1.8));
    const columns = Math.max(1, Math.min(count, balanced, Math.floor(grid.clientWidth / 320)));
    // Each terminal spans cells of a half-column grid; dense packing refills gaps after a resize or move.
    const tracks = columns * MOSAIC_CELLS;
    grid.dataset.tracks = tracks;
    grid.style.gridTemplateColumns = `repeat(${tracks}, minmax(0, 1fr))`;
    grid.style.gridTemplateRows = '';
    grid.style.gridAutoRows = 'minmax(36px, 1fr)'; grid.style.gridAutoFlow = 'row dense';
    for (const pane of panes) {
      pane.style.gridColumn = `span ${Math.min(Number(pane.dataset.w) || MOSAIC_CELLS, tracks)}`;
      pane.style.gridRow = `span ${Number(pane.dataset.h) || MOSAIC_CELLS}`;
    }
    return;
  }
  const columns = matchMedia('(max-width: 750px)').matches ? 1 : 2;
  const rows = Math.ceil(count / columns);
  if (splitRows.length !== rows) splitRows = Array(rows).fill(1);
  grid.style.gridTemplateColumns = split && columns === 2 ? `minmax(100px, ${splitColumns}fr) minmax(100px, ${100 - splitColumns}fr)` : 'minmax(0, 1fr)';
  [...grid.children].filter(pane => !pane.hidden).forEach((pane, index) => {
    pane.querySelector('.resize-vertical').hidden = columns === 1 || index % columns !== 0 || count < 2;
    pane.querySelector('.resize-horizontal').hidden = Math.floor(index / columns) >= rows - 1;
  });
  grid.style.gridTemplateRows = split ? splitRows.map(size => `minmax(80px, ${size}fr)`).join(' ') : 'minmax(0, 1fr)';
}
const MOSAIC_CELLS = 2;
function mosaicResizer(host) {
  const corner = document.createElement('div');
  corner.className = 'mosaic-resize'; corner.tabIndex = 0; corner.setAttribute('role', 'button');
  corner.setAttribute('aria-label', 'Tamanho no mosaico'); corner.title = 'Arraste para mudar largura e altura · setas no teclado · duplo clique repõe';
  const span = (w, h) => {
    const tracks = Number(document.getElementById('terminal').dataset.tracks) || MOSAIC_CELLS;
    w = clamp(w, 1, tracks); h = clamp(h, 1, 16);
    if (String(w) === host.dataset.w && String(h) === host.dataset.h) return;
    host.dataset.w = w; host.dataset.h = h; fitVisible();
  };
  const current = () => [Number(host.dataset.w) || MOSAIC_CELLS, Number(host.dataset.h) || MOSAIC_CELLS];
  corner.addEventListener('pointerdown', event => {
    if (event.button !== 0) return;
    event.preventDefault(); event.stopPropagation(); corner.setPointerCapture(event.pointerId);
    const grid = document.getElementById('terminal'), gap = parseFloat(getComputedStyle(grid).columnGap) || 0;
    const [, h] = current(), cellHeight = (host.getBoundingClientRect().height + gap) / h;
    corner.onpointermove = move => {
      const rect = host.getBoundingClientRect(), cellWidth = (grid.clientWidth + gap) / (Number(grid.dataset.tracks) || 1);
      span(Math.round((move.clientX - rect.left + gap) / cellWidth), Math.round((move.clientY - rect.top + gap) / cellHeight));
    };
    corner.onpointerup = corner.onlostpointercapture = () => { corner.onpointermove = null; };
  });
  corner.addEventListener('dblclick', () => { delete host.dataset.w; delete host.dataset.h; fitVisible(); });
  corner.addEventListener('keydown', event => {
    const step = {ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1]}[event.key];
    if (!step) return;
    event.preventDefault(); const [w, h] = current(); span(w + step[0], h + step[1]);
  });
  host.append(corner);
}
function paneResizers(host) {
  mosaicResizer(host);
  host.append(resizeHandle('Largura dos terminais', 'vertical', delta => {
    const width = document.getElementById('terminal').clientWidth;
    splitColumns = clamp(splitColumns + delta / width * 100, 15, 85);
    return splitColumns;
  }));
  host.append(resizeHandle('Altura dos terminais', 'horizontal', delta => {
    const grid = document.getElementById('terminal');
    const visible = [...grid.children].filter(pane => !pane.hidden);
    const columns = matchMedia('(max-width: 750px)').matches ? 1 : 2;
    const row = Math.floor(visible.indexOf(host) / columns);
    if (row >= splitRows.length - 1) return;
    const sum = splitRows[row] + splitRows[row + 1];
    const change = delta / Math.max(1, host.clientHeight) * splitRows[row];
    splitRows[row] = clamp(splitRows[row] + change, sum * .15, sum * .85);
    splitRows[row + 1] = sum - splitRows[row];
    return splitRows[row] / sum * 100;
  }));
}
function moveSessionBefore(sourceID, targetID, after = false) {
  const source = sessions.get(sourceID), target = sessions.get(targetID);
  if (!source || !target || source === target || source.workspace !== target.workspace) return;
  const ordered = [...sessions.values()].filter(s => s !== source);
  ordered.splice(ordered.indexOf(target) + Number(after), 0, source);
  sessions.clear(); for (const session of ordered) sessions.set(session.id, session);
  const grid = document.getElementById('terminal');
  for (const session of ordered) grid.append(session.host);
  renderNavigation(); fitVisible();
}
function movableSession(session, handle) {
  handle.draggable = true;
  handle.title = `${session.title || session.name} · arraste para mover; ⌥↑/↓ para reordenar`;
  handle.addEventListener('dragstart', event => {
    draggedSession = session.id; event.dataTransfer.effectAllowed = 'move';
    event.dataTransfer.setData('text/x-boterm-session', session.id);
  });
  handle.addEventListener('dragend', () => { draggedSession = undefined; document.querySelectorAll('.drop-target').forEach(el => el.classList.remove('drop-target')); });
  const target = handle.classList.contains('pane-title') ? session.host : handle;
  target.addEventListener('dragover', event => {
    if (!draggedSession || draggedSession === session.id) return;
    event.preventDefault(); event.dataTransfer.dropEffect = 'move'; target.classList.add('drop-target');
  });
  target.addEventListener('dragleave', () => target.classList.remove('drop-target'));
  target.addEventListener('drop', event => {
    if (!draggedSession) return;
    event.preventDefault(); event.stopPropagation(); target.classList.remove('drop-target');
    const ids = [...sessions.keys()];
    moveSessionBefore(draggedSession, session.id, ids.indexOf(draggedSession) < ids.indexOf(session.id)); draggedSession = undefined;
  });
  handle.tabIndex = 0;
  handle.addEventListener('keydown', event => {
    if (!event.altKey || !['ArrowUp', 'ArrowDown'].includes(event.key)) return;
    event.preventDefault();
    const peers = [...sessions.values()].filter(s => s.workspace === session.workspace);
    const index = peers.indexOf(session), next = peers[index + (event.key === 'ArrowUp' ? -1 : 1)];
    if (!next) return;
    if (event.key === 'ArrowUp') moveSessionBefore(session.id, next.id); else moveSessionBefore(next.id, session.id);
    (document.getElementById('sessions').children[[...sessions.values()].filter(s => s.workspace === session.workspace).indexOf(session)])?.focus();
  });
}
document.addEventListener('DOMContentLoaded', () => {
  const sidebar = document.getElementById('sidebar');
  sidebar.after(resizeHandle('Largura da lateral', 'vertical', delta => {
    sidebar.style.width = `${clamp(sidebar.clientWidth + delta, 110, innerWidth * .5)}px`;
    return sidebar.clientWidth / innerWidth * 100;
  }));
});

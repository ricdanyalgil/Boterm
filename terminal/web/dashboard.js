'use strict';
// Project dashboard and live state. Live facts come from the page (sessions, messages);
// code, history and tool timing come from the app. Numbers sit inside sentences and tables,
// not as hero metrics; magnitudes are drawn as rows of grid cells.
const dashboardData = new Map(), historyNoticed = new Set();
let dashboardOpen = false, dashboardTick = 0;
const eventLabels = {'test-fail': 'Falha apanhada', 'test-pass': 'Teste aprovado', fix: 'Correção', improvement: 'Melhoria', decision: 'Decisão', blocker: 'Bloqueio'};
/** Portuguese count with the right number: plural(1, 'falha apanhada', 'falhas apanhadas'). */
const plural = (n, one, many) => `${n} ${n === 1 ? one : many}`;
function formatDuration(seconds) {
  seconds = Math.max(0, Math.round(seconds));
  if (seconds < 60) return `${seconds} s`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes} min`;
  return `${Math.floor(minutes / 60)} h ${String(minutes % 60).padStart(2, '0')} min`;
}
/** Compact clock for rows and pane headers: 0:07, 1:12 (hours:minutes). */
function formatClock(seconds) {
  const minutes = Math.floor(Math.max(0, seconds) / 60);
  return `${Math.floor(minutes / 60)}:${String(minutes % 60).padStart(2, '0')}`;
}
/** Window resizes and view switches make every shell redraw its prompt; that redraw is not work. */
function resizeGrace() { const now = Date.now(); for (const s of sessions.values()) s.lastResize = Math.max(s.lastResize || 0, now); }
/** Busy means fresh output that is neither the echo of typing nor the redraw that follows a resize. */
function sessionBusy(s, now = Date.now()) {
  const output = s.lastOutput || 0;
  return !s.ended && now - output < 2500 && output - (s.lastInput || 0) > 400 && output - (s.lastResize || 0) > 1000;
}
function sessionState(s, now = Date.now()) {
  if (s.ended) return ['ended', 'encerrado'];
  if (s.attention) return ['attention', 'precisa de você'];
  if (sessionBusy(s, now)) return ['busy', 'trabalhando'];
  return ['idle', s.agent ? 'em espera' : 'parado'];
}
function element(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}
function section(title, sentence, className) {
  const box = element('section', `dash-section ${className}`);
  box.append(element('h2', '', title));
  if (sentence) box.append(element('p', 'dash-sentence', sentence));
  return box;
}
/** A magnitude as a row of grid cells: each kind fills whole cells, scaled to the largest row. */
function cellBar(parts, max, cells = 24) {
  const bar = element('span', 'cell-bar'); bar.setAttribute('aria-hidden', 'true');
  for (const [kind, value] of parts) {
    const count = value > 0 ? Math.max(1, Math.round(value / Math.max(1, max) * cells)) : 0;
    for (let i = 0; i < count; i++) bar.append(element('i', kind));
  }
  return bar;
}
function requestDashboard(workspace = activeWorkspace) {
  if (!workspaces.has(workspace)) return;
  const since = (workspaceStarted.get(workspace) || new Date()).toISOString();
  send({type: 'dashboard', workspace, directory: workspaceDirectories.get(workspace) || '', since});
}
function workspaceSummary(workspace) {
  const peers = [...sessions.values()].filter(s => s.workspace === workspace);
  const messages = messageHistory.filter(m => m.workspace === workspace);
  const count = test => messages.filter(m => test(String(m.text))).length;
  return {
    peers, agents: peers.filter(s => s.agent),
    busy: peers.filter(s => sessionState(s)[0] === 'busy').length,
    attention: peers.filter(s => s.attention && !s.ended).length,
    messages: count(t => !t.startsWith('[')), submits: count(t => t.startsWith('[Terminal: submitted input]')),
    drafts: count(t => t.startsWith('[Terminal: inserted draft]')), compactions: count(t => t.startsWith('[Boterm] Compactação')),
    owner: messages.filter(m => String(m.fromName).includes('Telegram')).length
  };
}
function toolTotals(tools = {}) {
  let edits = 0, shell = 0, mcp = 0, mcpCalls = 0;
  for (const [name, usage] of Object.entries(tools)) {
    if (name.startsWith('mcp:')) { mcp += usage.seconds; mcpCalls += usage.calls; }
    else if (name === 'Bash') shell += usage.calls;
    else edits += usage.calls;
  }
  return {edits, shell, mcp, mcpCalls};
}
function teamTable(summary, data) {
  const table = element('table', 'dash-table'), head = element('tr');
  for (const [label, cls] of [['Terminal', ''], ['Estado', ''], ['Aberto', 'num'], ['Edições', 'num'], ['Comandos', 'num narrow-hide'], ['MCP', 'num narrow-hide'], ['Última ação', 'wide narrow-hide']]) head.append(element('th', cls, label));
  const thead = element('thead'); thead.append(head);
  const body = element('tbody');
  for (const s of summary.peers) {
    const [state, label] = sessionState(s), tools = toolTotals(data?.sessions?.[s.id]);
    const row = element('tr', `dash-agent state-${state}`); row.style.setProperty('--session-color', s.color);
    const name = element('td', 'dash-name'), open = button('', () => { closeDashboard(); activateSession(s.id); }, `Abrir ${s.name}`);
    open.append(element('span', 'chip'), element('strong', '', s.name), element('small', '', providerNames[s.agent] || 'Shell'));
    name.append(open);
    row.append(name, element('td', 'dash-state', label), element('td', 'num', formatClock((Date.now() - s.startedAt) / 1000)),
      element('td', 'num col-edits', String(tools.edits)), element('td', 'num narrow-hide', String(tools.shell)),
      element('td', 'num narrow-hide', tools.mcpCalls ? formatDuration(tools.mcp) : '—'), element('td', 'wide narrow-hide', s.attention ? `Pede: ${s.attention}` : s.lastMessage || ''));
    body.append(row);
  }
  table.append(thead, body); return table;
}
function renderDashboard(force = false) {
  const panel = document.getElementById('dashboard');
  if (!dashboardOpen) return;
  // Never swap nodes under a pressed mouse button; that swallows the click.
  if (!force && panel.matches(':active')) return;
  const workspace = activeWorkspace, data = dashboardData.get(workspace) || {}, summary = workspaceSummary(workspace);
  const started = workspaceStarted.get(workspace) || new Date();

  const header = element('header', 'dash-head'), title = element('div', 'dash-title');
  title.append(element('h1', '', workspaces.get(workspace) || 'Projeto'), element('p', 'dash-path', data.directory || workspaceDirectories.get(workspace) || 'Sem pasta de projeto'));
  const facts = element('p', 'dash-facts');
  facts.textContent = `${formatDuration((Date.now() - started) / 1000)} de sessão · ${summary.peers.length}/32 terminais · ${summary.busy} trabalhando${summary.attention ? ` · ${summary.attention} ${summary.attention === 1 ? 'precisa' : 'precisam'} de você` : ''}`;
  header.append(title, facts, button('', closeDashboard, 'Fechar painel'));
  header.lastChild.classList.add('dash-close'); header.lastChild.append(icon('close'));

  const grid = element('div', 'dash-grid');
  const team = section('Equipa', `${plural(summary.messages, 'mensagem', 'mensagens')} · ${plural(summary.submits, 'tarefa enviada', 'tarefas enviadas')} · ${plural(summary.drafts, 'rascunho', 'rascunhos')} · ${plural(summary.compactions, 'compactação', 'compactações')}${summary.owner ? ` · ${plural(summary.owner, 'resposta sua', 'respostas suas')}` : ''}`, 'dash-team');
  team.append(teamTable(summary, data)); grid.append(team);

  const code = data.code;
  const codeBox = section('Código', code?.repo ? `+${code.added} −${code.removed} em ${plural(code.changed, 'arquivo alterado', 'arquivos alterados')}${code.untracked ? ` (${plural(code.untracked, 'novo', 'novos')})` : ''} · ${plural(code.commits.length, 'commit', 'commits')} nesta sessão · ${code.branch || 'sem branch'}` : code ? 'A pasta não é um repositório git.' : 'A ler o repositório…', 'dash-code');
  if (code?.files?.length) {
    const max = Math.max(...code.files.map(f => f.added + f.removed)), list = element('ul', 'dash-rows');
    for (const f of code.files) { const row = element('li'); row.append(element('code', '', f.file), cellBar([['add', f.added], ['del', f.removed]], max), element('span', 'num', `+${f.added} −${f.removed}`)); list.append(row); }
    codeBox.append(list);
  }
  if (code?.commits?.length) { const list = element('ul', 'dash-commits'); for (const c of code.commits.slice(0, 4)) list.append(element('li', '', c)); codeBox.append(list); }
  grid.append(codeBox);

  const events = data.events || [], byKind = kind => events.filter(e => e.kind === kind).length;
  const quality = section('Qualidade', `${plural(byKind('test-fail'), 'falha apanhada', 'falhas apanhadas')} · ${plural(byKind('test-pass'), 'aprovado', 'aprovados')} · ${plural(byKind('fix'), 'correção', 'correções')} · ${plural(byKind('improvement'), 'melhoria', 'melhorias')}${byKind('blocker') ? ` · ${plural(byKind('blocker'), 'bloqueio', 'bloqueios')}` : ''}`, 'dash-quality');
  if (events.length) {
    const list = element('ol', 'dash-timeline');
    for (const e of events.slice(-10).reverse()) {
      const row = element('li', `event-${e.kind}`);
      row.append(element('time', 'num', new Date(e.time).toLocaleTimeString('pt-BR', {hour: '2-digit', minute: '2-digit'})), element('span', 'dash-kind', eventLabels[e.kind] || e.kind), element('span', 'dash-event', `${e.name}: ${e.text}`));
      list.append(row);
    }
    quality.append(list);
  } else quality.append(element('p', 'dash-empty', 'Os agentes registam aqui falhas apanhadas, correções e melhorias com boterm event.'));
  grid.append(quality);

  const usage = data.usage || {}, servers = Object.entries(usage).filter(([name]) => name.startsWith('mcp:')).sort((a, b) => b[1].seconds - a[1].seconds);
  const total = servers.reduce((sum, [, u]) => sum + u.seconds, 0), calls = servers.reduce((sum, [, u]) => sum + u.calls, 0);
  const mcp = section('MCP', servers.length ? `${formatDuration(total)} em ${plural(calls, 'chamada', 'chamadas')} · medido nos agentes Claude` : 'Medido nos agentes Claude; Codex e Gemini não expõem esse tempo.', 'dash-mcp');
  if (servers.length) {
    const max = servers[0][1].seconds, list = element('ul', 'dash-rows');
    for (const [name, u] of servers.slice(0, 6)) { const row = element('li'); row.append(element('code', '', name.slice(4)), cellBar([['use', u.seconds]], max), element('span', 'num', `${u.calls} · ${formatDuration(u.seconds)}`)); list.append(row); }
    mcp.append(list);
  }
  grid.append(mcp);

  const history = data.history;
  const historyBox = section('Histórico do projeto', history ? (history.entries ? `${plural(history.entries, 'entrada', 'entradas')} em .boterm/HISTORY.md${history.archive ? ' · arquivo antigo disponível' : ''}` : 'Ainda sem entradas. O Orquestrador regista cada atividade concluída.') + (history.roles ? ` · ${plural(history.roles, 'secção aprendida', 'secções aprendidas')} pela Qualidade em .boterm/ROLES.md` : '') : 'Sem pasta de projeto.', 'dash-history');
  if (history?.recent?.length) { const list = element('ol', 'dash-commits'); for (const t of history.recent) list.append(element('li', '', t)); historyBox.append(list); }
  grid.append(historyBox);

  const key = header.textContent + grid.textContent + [...grid.querySelectorAll('.dash-agent')].map(n => n.className).join();
  if (!force && panel.dataset.key === key) return;
  panel.dataset.key = key; panel.replaceChildren(header, grid);
}
function openDashboard() {
  resizeGrace(); dashboardOpen = true; document.body.dataset.view = 'dashboard';
  document.getElementById('dashboard').hidden = false;
  document.getElementById('dashboard-toggle').setAttribute('aria-pressed', 'true');
  document.getElementById('history-notice').hidden = true;
  renderDashboard(true); requestDashboard(); updateLiveState();
}
function closeDashboard() {
  if (!dashboardOpen) return;
  resizeGrace(); dashboardOpen = false; delete document.body.dataset.view;
  document.getElementById('dashboard').hidden = true;
  document.getElementById('dashboard-toggle').setAttribute('aria-pressed', 'false');
  fitVisible(); updateLiveState();
}
/** The 8/32 counter cycles the views: single → mosaic → dashboard → single. */
function cycleView() {
  if (dashboardOpen) { closeDashboard(); mosaic = false; split = false; fitVisible(); }
  else if (mosaic) openDashboard();
  else { mosaic = true; split = false; fitVisible(); }
  markLayoutChanged(); updateLiveState();
}
function receiveDashboard(data, extra) {
  const merged = {...data, ...(extra || {})};
  dashboardData.set(data.workspace, merged);
  if (dashboardOpen && data.workspace === activeWorkspace) renderDashboard();
  // Opening a project with history: say so once, without taking over the screen.
  if (merged.history?.entries && !historyNoticed.has(data.workspace) && !dashboardOpen) {
    historyNoticed.add(data.workspace);
    const notice = document.getElementById('history-notice');
    notice.querySelector('span').textContent = `Histórico do projeto: ${plural(merged.history.entries, 'entrada', 'entradas')} · última: ${merged.history.recent[0] || ''}`;
    notice.hidden = data.workspace !== activeWorkspace;
  }
}
function receiveEvent(event) {
  const data = dashboardData.get(event.workspace) || {workspace: event.workspace};
  data.events = [...(data.events || []), event].slice(-60); dashboardData.set(event.workspace, data);
  const s = sessions.get(event.session); if (s) { s.lastMessage = `${eventLabels[event.kind]}: ${event.text}`; renderNavigation(); }
  if (dashboardOpen) renderDashboard();
}
/** Once a second: activity, state words, clocks and the team caption, updated in place. */
function updateLiveState() {
  const now = Date.now(), set = (node, value) => { if (node && node.textContent !== value) node.textContent = value; };
  for (const s of sessions.values()) {
    const [state, label] = sessionState(s, now), clock = formatClock((now - s.startedAt) / 1000);
    for (const node of [s.host, s.row]) {
      if (!node) continue;
      node.classList.toggle('busy', state === 'busy');
      for (const name of ['busy', 'attention', 'idle', 'ended']) node.classList.toggle(`state-${name}`, state === name);
    }
    if (s.row) { set(s.row.querySelector('.row-word'), label); set(s.row.querySelector('.row-time'), clock); }
    set(s.host.querySelector('.pane-meta'), `${mosaic ? `${Number(s.host.dataset.w) || MOSAIC_CELLS}×${Number(s.host.dataset.h) || MOSAIC_CELLS} · ` : ''}${clock}`);
  }
  const active = sessions.get(activeID);
  document.getElementById('session-label')?.classList.toggle('busy', Boolean(active && sessionBusy(active, now)));
  const started = workspaceStarted.get(activeWorkspace);
  if (dashboardOpen) renderDashboard();
  set(document.getElementById('team-meta'), `Terminais · ${dashboardOpen ? 'painel' : mosaic ? 'mosaico' : split ? 'dividido' : 'vista única'}\n${started ? formatDuration((now - started) / 1000) : '0 s'} de sessão`);
}
if (typeof document !== 'undefined') setInterval(() => {
  updateLiveState();
  if (dashboardOpen && ++dashboardTick % 5 === 0) requestDashboard();
}, 1000);
if (typeof document !== 'undefined') document.addEventListener('DOMContentLoaded', () => {
  document.getElementById('dashboard-toggle').onclick = () => dashboardOpen ? closeDashboard() : openDashboard();
  document.getElementById('team-count').onclick = cycleView;
  document.getElementById('sessions').addEventListener('click', closeDashboard, true);
  const notice = document.getElementById('history-notice');
  notice.querySelector('.notice-open').onclick = openDashboard;
  notice.querySelector('.notice-close').onclick = () => { notice.hidden = true; };
  for (const radio of document.querySelectorAll('#world-choice input')) radio.onchange = () => { if (radio.checked) setWorld(radio.value, true); };
  setWorld(document.documentElement.dataset.world || 'grid');
});
/** Two visual worlds share one structure; the choice is kept by the app across launches. */
function setWorld(world, persist = false) {
  if (!['grid', 'set'].includes(world)) return;
  document.documentElement.dataset.world = world;
  for (const radio of document.querySelectorAll('#world-choice input')) radio.checked = radio.value === world;
  if (persist) send({type: 'setWorld', world});
}
if (typeof module !== 'undefined') module.exports = {plural, formatDuration, formatClock, sessionBusy, toolTotals};

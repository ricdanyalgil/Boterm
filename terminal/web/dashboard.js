'use strict';
// Project dashboard: what the team is doing now and what it has done since the project opened.
// Live facts come from the page (sessions, messages); code, history and tool timing come from the app.
const dashboardData = new Map(), historyNoticed = new Set();
let dashboardOpen = false, dashboardTick = 0;
const eventLabels = {'test-fail': 'Teste apanhou falha', 'test-pass': 'Teste aprovado', fix: 'Correção', improvement: 'Melhoria', decision: 'Decisão', blocker: 'Bloqueio'};
const agentMarks = {codex: '◇', claude: '✳', agy: '✦', gemini: '✦', opencode: '⌘'};

/** Portuguese count with the right number: plural(1, 'falha apanhada', 'falhas apanhadas'). */
const plural = (n, one, many) => `${n} ${n === 1 ? one : many}`;
function formatDuration(seconds) {
  seconds = Math.max(0, Math.round(seconds));
  if (seconds < 60) return `${seconds} s`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes} min`;
  return `${Math.floor(minutes / 60)} h ${String(minutes % 60).padStart(2, '0')} min`;
}
/** Busy means fresh output that is not just the echo of someone typing. */
function sessionBusy(s, now = Date.now()) {
  return !s.ended && now - (s.lastOutput || 0) < 2500 && (s.lastOutput || 0) - (s.lastInput || 0) > 400;
}
function sessionState(s) {
  if (s.ended) return ['ended', 'Encerrado'];
  if (s.attention) return ['attention', `Atenção: ${s.attention}`];
  if (sessionBusy(s)) return ['busy', 'A trabalhar'];
  return ['idle', s.agent ? 'À espera' : 'Shell parada'];
}
function element(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}
function card(title, value, detail) {
  const box = element('section', 'dash-card'), head = element('h3', '', title);
  box.append(head);
  if (value !== undefined) box.append(element('p', 'dash-value', value));
  if (detail) box.append(element('p', 'dash-detail', detail));
  return box;
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
function agentList(summary, data) {
  const list = element('ul', 'dash-agents');
  for (const s of summary.peers) {
    const [state, label] = sessionState(s), tools = toolTotals(data?.sessions?.[s.id]);
    const item = element('li', `dash-agent state-${state}`); item.style.setProperty('--session-color', s.color);
    const open = button('', () => { closeDashboard(); activateSession(s.id); }, `Abrir ${s.name}`);
    open.append(element('span', 'dash-dot'), element('strong', '', `${agentMarks[s.agent] || '›_'} ${s.name}`), element('span', 'dash-state', label));
    const facts = [`aberto há ${formatDuration((Date.now() - s.startedAt) / 1000)}`];
    if (tools.edits) facts.push(plural(tools.edits, 'edição', 'edições'));
    if (tools.shell) facts.push(plural(tools.shell, 'comando', 'comandos'));
    if (tools.mcpCalls) facts.push(`MCP ${formatDuration(tools.mcp)}`);
    if (s.lastMessage) facts.push(s.lastMessage);
    open.append(element('small', '', facts.join(' · ')));
    item.append(open); list.append(item);
  }
  return list;
}
function renderDashboard(force = false) {
  const panel = document.getElementById('dashboard');
  if (!dashboardOpen) return;
  // Never swap nodes under a pressed mouse button; that swallows the click.
  if (!force && panel.matches(':active')) return;
  const workspace = activeWorkspace, data = dashboardData.get(workspace) || {}, summary = workspaceSummary(workspace);
  const started = workspaceStarted.get(workspace) || new Date();
  const header = element('header', 'dash-header');
  const title = element('div');
  title.append(element('h2', '', workspaces.get(workspace) || 'Projeto'), element('p', 'dash-detail', data.directory || workspaceDirectories.get(workspace) || 'Sem pasta de projeto'));
  header.append(title, button('×', closeDashboard, 'Fechar painel'));

  const grid = element('div', 'dash-grid');
  grid.append(card('Sessão', formatDuration((Date.now() - started) / 1000), `${plural(summary.peers.length, 'terminal', 'terminais')} · ${plural(summary.agents.length, 'agente', 'agentes')} · ${summary.busy} a trabalhar${summary.attention ? ` · ${plural(summary.attention, 'pede', 'pedem')} atenção` : ''}`));

  const code = data.code, codeCard = card('Código', code?.repo ? `+${code.added} −${code.removed}` : '—',
    code?.repo ? `${plural(code.changed, 'arquivo alterado', 'arquivos alterados')}${code.untracked ? ` (${plural(code.untracked, 'novo', 'novos')})` : ''} · ${plural(code.commits.length, 'commit', 'commits')} nesta sessão · ${code.branch || 'sem branch'}` : code ? 'A pasta não é um repositório git.' : 'A ler o repositório…');
  if (code?.files?.length) {
    const files = element('ul', 'dash-files');
    for (const f of code.files) { const row = element('li'); row.append(element('code', '', f.file), element('span', '', `+${f.added} −${f.removed}`)); files.append(row); }
    codeCard.append(files);
  }
  grid.append(codeCard);

  const events = data.events || [], byKind = kind => events.filter(e => e.kind === kind).length;
  const quality = card('Testes e melhorias', plural(byKind('test-fail'), 'falha apanhada', 'falhas apanhadas'), `${plural(byKind('test-pass'), 'aprovado', 'aprovados')} · ${plural(byKind('fix'), 'correção', 'correções')} · ${plural(byKind('improvement'), 'melhoria', 'melhorias')}${byKind('blocker') ? ` · ${plural(byKind('blocker'), 'bloqueio', 'bloqueios')}` : ''}`);
  if (events.length) {
    const list = element('ul', 'dash-events');
    for (const e of events.slice(-8).reverse()) {
      const row = element('li', `event-${e.kind}`);
      row.append(element('span', 'dash-kind', eventLabels[e.kind] || e.kind), element('span', '', `${e.name}: ${e.text}`));
      list.append(row);
    }
    quality.append(list);
  } else quality.append(element('p', 'dash-detail', 'Os agentes registam falhas, correções e melhorias com boterm event.'));
  grid.append(quality);

  grid.append(card('Ações', String(summary.messages + summary.submits + summary.drafts), `${plural(summary.messages, 'mensagem', 'mensagens')} · ${plural(summary.submits, 'tarefa enviada', 'tarefas enviadas')} · ${plural(summary.drafts, 'rascunho', 'rascunhos')} · ${plural(summary.compactions, 'compactação', 'compactações')}${summary.owner ? ` · ${plural(summary.owner, 'resposta sua', 'respostas suas')}` : ''}`));

  const usage = data.usage || {}, servers = Object.entries(usage).filter(([name]) => name.startsWith('mcp:')).sort((a, b) => b[1].seconds - a[1].seconds);
  const mcpCard = card('MCP', formatDuration(servers.reduce((sum, [, u]) => sum + u.seconds, 0)), servers.length ? `${plural(servers.reduce((sum, [, u]) => sum + u.calls, 0), 'chamada', 'chamadas')} · medido nos agentes Claude` : 'Medido nos agentes Claude; Codex e Gemini não expõem esse tempo.');
  if (servers.length) {
    const list = element('ul', 'dash-files');
    for (const [name, u] of servers.slice(0, 6)) { const row = element('li'); row.append(element('code', '', name.slice(4)), element('span', '', `${u.calls} · ${formatDuration(u.seconds)}`)); list.append(row); }
    mcpCard.append(list);
  }
  grid.append(mcpCard);

  const history = data.history, historyCard = card('Histórico do projeto', history ? String(history.entries) : '—', history ? (history.entries ? `${history.entries === 1 ? 'entrada' : 'entradas'} em .boterm/HISTORY.md${history.archive ? ' · arquivo antigo disponível' : ''}` : 'Ainda sem entradas. O Orquestrador regista cada atividade concluída.') : 'Sem pasta de projeto.');
  if (history?.recent?.length) { const list = element('ul', 'dash-events'); for (const t of history.recent) list.append(element('li', '', t)); historyCard.append(list); }
  grid.append(historyCard);

  const agents = element('section', 'dash-card dash-wide'); agents.append(element('h3', '', 'Terminais e agentes'), agentList(summary, data));
  grid.append(agents);
  const key = header.textContent + grid.textContent + [...grid.querySelectorAll('.dash-agent')].map(n => n.className).join();
  if (!force && panel.dataset.key === key) return;
  panel.dataset.key = key; panel.replaceChildren(header, grid);
}
function openDashboard() {
  dashboardOpen = true; document.body.dataset.view = 'dashboard';
  document.getElementById('dashboard').hidden = false;
  document.getElementById('dashboard-toggle').setAttribute('aria-pressed', 'true');
  document.getElementById('history-notice').hidden = true;
  renderDashboard(true); requestDashboard();
}
function closeDashboard() {
  if (!dashboardOpen) return;
  dashboardOpen = false; delete document.body.dataset.view;
  document.getElementById('dashboard').hidden = true;
  document.getElementById('dashboard-toggle').setAttribute('aria-pressed', 'false');
  fitVisible();
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
// Pulse the colored dot of every terminal that is producing output.
if (typeof document !== 'undefined') setInterval(() => {
  const now = Date.now();
  for (const s of sessions.values()) {
    const busy = sessionBusy(s, now);
    s.host.classList.toggle('busy', busy); s.row?.classList.toggle('busy', busy);
  }
  document.getElementById('session-label')?.classList.toggle('busy', Boolean(sessions.get(activeID) && sessionBusy(sessions.get(activeID), now)));
  if (dashboardOpen) { renderDashboard(); if (++dashboardTick % 5 === 0) requestDashboard(); }
}, 1000);
if (typeof document !== 'undefined') document.addEventListener('DOMContentLoaded', () => {
  document.getElementById('dashboard-toggle').onclick = () => dashboardOpen ? closeDashboard() : openDashboard();
  document.getElementById('sessions').addEventListener('click', closeDashboard, true);
  const notice = document.getElementById('history-notice');
  notice.querySelector('.notice-open').onclick = openDashboard;
  notice.querySelector('.notice-close').onclick = () => { notice.hidden = true; };
});
if (typeof module !== 'undefined') module.exports = {plural, formatDuration, sessionBusy, toolTotals};

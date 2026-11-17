'use strict';
const sessions = new Map(), workspaces = new Map();
const workspaceDirectories = new Map(), workspaceStarted = new Map();
let activeID, activeWorkspace, split = false, mosaic = false;
let nextSessionColor = 0, nextProjectNumber = 2;
const privateWorkspace = crypto.randomUUID();
const sessionColors = ['#82aaff', '#c3e88d', '#ffcb6b', '#c792ea', '#89ddff', '#f78c6c', '#f071a2', '#80cbc4'];
const messageHistory = [];
function button(text, action, label = text) {
  const b = document.createElement('button');
  b.type = 'button'; b.textContent = text; b.title = label; b.setAttribute('aria-label', label);
  b.addEventListener('click', action); return b;
}
function screenText(terminal, limit = 262144) {
  if (!terminal) throw new Error('Session not found');
  const b = terminal.buffer.active;
  return Array.from({length: b.length}, (_, i) => b.getLine(i)?.translateToString(true) ?? '').join('\n').slice(limit === null ? 0 : -limit);
}
function createSession(name = 'Terminal', workspace = activeWorkspace, agent = '', launch = {}) {
  if (sessions.size >= 32) throw new Error('Maximum 32 terminals per window');
  if (!workspaces.has(workspace)) throw new Error('Workspace not found');
  const id = crypto.randomUUID(), host = document.createElement('section');
  const color = sessionColors.find(c => ![...sessions.values()].some(s => s.color === c)) || `hsl(${nextSessionColor++ * 137.508 % 360} 70% 72%)`;
  host.style.setProperty('--session-color', color);
  host.className = 'terminal-pane'; host.setAttribute('aria-label', name);
  document.getElementById('terminal').append(host);
  const heading = document.createElement('div'), output = document.createElement('div');
  heading.className = 'pane-title'; heading.textContent = name; output.className = 'terminal-content'; host.append(heading, output);
  const terminal = new Terminal({fontFamily: 'Menlo, Monaco, monospace', fontSize: 14, lineHeight: 1.25,
    allowProposedApi: true, cursorBlink: true, scrollback: 5000, screenReaderMode: true, theme: BOTERM_THEME});
  const addon = new FitAddon.FitAddon(); terminal.loadAddon(addon); terminal.open(output);
  const accents = terminalAccents(terminal);
  if (!workspaceStarted.has(workspace)) workspaceStarted.set(workspace, new Date());
  const session = {startedAt: Date.now(), lastOutput: 0, lastInput: 0, id, color, accents, workspace, name: name.slice(0, 80), term: terminal, fit: addon, host, ended: false, agent, agentState: 'idle'};
  sessions.set(id, session);
  const conversation = document.createElement('details'), summary = document.createElement('summary'), log = document.createElement('div');
  conversation.className = 'session-conversation'; conversation.hidden = true;
  log.className = 'session-conversation-log'; log.setAttribute('role', 'log'); log.setAttribute('aria-live', 'polite');
  conversation.append(summary, log); host.append(conversation);
  conversation.addEventListener('toggle', fitVisible);
  terminal.onWriteParsed(() => updateAttention(session));
  movableSession(session, heading);
  paneResizers(host);
  terminal.onData(data => { session.lastInput = Date.now(); send({type: 'input', session: id, data}); });
  terminal.onResize(({cols, rows}) => send({type: 'resize', session: id, columns: cols, rows}));
  terminal.onTitleChange(title => { session.title = title.slice(0, 100); renderNavigation(); });
  host.addEventListener('mousedown', () => { if (activeID !== id) activateSession(id, false); });
  terminal.attachCustomKeyEventHandler(event => {
    const action = terminalShortcut(event, terminal.hasSelection());
    if (action) {
      event.preventDefault();
      if (action === 'newSession') createSession();
      else if (action === 'selectAll') terminal.selectAll();
      else send({type: action, text: action === 'copy' ? terminal.getSelection() : undefined});
      return false;
    }
    if (event.type === 'keydown' && event.key === 'Escape' && document.body.dataset.dictating === 'true') {
      send({type: 'cancelVoice'}); return false;
    }
    return true;
  });
  activateSession(id);
  renderConversations();
  send({type: 'ready', session: id, workspace, name: session.name, agent, directory: launch.directory ?? workspaceDirectories.get(workspace), prompt: launch.prompt, role: launch.role, columns: terminal.cols, rows: terminal.rows});
  return id;
}
function newWorkspace(name, directory) {
  if (sessions.size >= 32) throw new Error('Maximum 32 terminals per window');
  const id = crypto.randomUUID(); workspaces.set(id, name || `Projeto ${nextProjectNumber++}`);
  if (directory) workspaceDirectories.set(id, directory);
  activeWorkspace = id; createSession('Terminal 1', id);
  if (directory) setTimeout(() => requestDashboard(id), 800);
  return id;
}
function activateSession(id, focus = true) {
  const s = sessions.get(id); if (!s) return;
  activeID = id; activeWorkspace = s.workspace; term = s.term; fit = s.fit;
  send({type: 'activate', session: id});
  renderNavigation(); fitVisible(); if (focus) term.focus();
  s.host.scrollIntoView?.({block: 'nearest', inline: 'nearest'});
}
function fitVisible() {
  const visible = [...sessions.values()].filter(s => s.workspace === activeWorkspace && (split || mosaic || s.id === activeID));
  document.getElementById('terminal').classList.toggle('split', split || mosaic);
  document.getElementById('terminal').classList.toggle('mosaic', mosaic);
  document.getElementById('split').setAttribute('aria-pressed', String(split));
  document.getElementById('mosaic').setAttribute('aria-pressed', String(mosaic));
  for (const s of sessions.values()) {
    s.host.hidden = !visible.includes(s);
    s.host.classList.toggle('active', s.id === activeID);
    s.host.querySelector('.session-conversation-log').setAttribute('aria-live', s.id === activeID ? 'polite' : 'off');
  }
  updateSplitLayout(visible.length);
  requestAnimationFrame(() => { for (const s of visible) { if (s.host.clientWidth > 30 && s.host.clientHeight > 30) s.fit.fit(); } });
}
function updateAttention(session) {
  const buffer = session.term.buffer.active;
  const text = Array.from({length: buffer.length - buffer.baseY}, (_, i) => buffer.getLine(buffer.baseY + i)?.translateToString(true) ?? '').join('\n');
  const attention = session.ended ? '' : terminalAttention(text);
  if (session.attention === attention) return;
  session.attention = attention; session.host.classList.toggle('needs-attention', Boolean(attention)); renderNavigation();
}
// Agents retitle their terminals many times per second; replacing a node between mousedown and
// mouseup swallows the click, so navigation updates existing nodes and rebuilds only on real changes.
const setIfChanged = (node, key, value) => { if (node[key] !== value) node[key] = value; };
function sessionRow(s) {
  if (s.row) return s.row;
  const row = button('', () => activateSession(s.id));
  row.classList.add('session-entry'); row.style.setProperty('--session-color', s.color);
  const task = document.createElement('small'); task.className = 'session-task';
  row.append(document.createElement('span'), document.createElement('small'), task);
  movableSession(s, row);
  return s.row = row;
}
function renderNavigation(forceProjects = false) {
  const tabs = document.getElementById('workspaces');
  const tabsKey = JSON.stringify([...workspaces, activeWorkspace]);
  if (forceProjects || (!tabs.querySelector('input') && tabs.dataset.key !== tabsKey)) {
  tabs.dataset.key = tabsKey;
  tabs.replaceChildren();
  const add = button('＋', () => newWorkspace(), 'Novo projeto');
  for (const [id, name] of [...workspaces].sort(([a], [b]) => Number(a === privateWorkspace) - Number(b === privateWorkspace))) {
    if (id === privateWorkspace) tabs.append(add);
    const group = document.createElement('div'); group.className = 'project-tab';
    const tab = button(name, () => {
      const session = [...sessions.values()].find(s => s.workspace === id);
      if (session) activateSession(session.id);
      else { activeWorkspace = id; createSession('Terminal 1', id); }
    });
    const edit = () => {
      const field = document.createElement('input'); field.value = workspaces.get(id);
      field.maxLength = 80; field.setAttribute('aria-label', 'Nome do projeto');
      group.replaceChildren(field); field.focus(); field.select();
      let done = false;
      const finish = save => {
        if (done) return; done = true;
        if (save) renameWorkspace(id, field.value);
        renderNavigation(true);
      };
      field.addEventListener('keydown', event => {
        if (event.key === 'Enter' || event.key === 'Escape') { event.preventDefault(); finish(event.key === 'Enter'); }
      });
      field.addEventListener('blur', () => finish(true));
    };
    tab.classList.toggle('selected', id === activeWorkspace); tab.setAttribute('aria-current', String(id === activeWorkspace));
    const pencil = button('✎', edit, `Renomear projeto ${name}`); pencil.className = 'project-edit'; pencil.setAttribute('aria-label', pencil.title);
    group.append(tab, pencil); tabs.append(group);
  }
  if (!workspaces.has(privateWorkspace)) tabs.append(add);
  }
  const list = document.getElementById('sessions'), select = document.getElementById('recipient');
  const peers = [...sessions.values()].filter(s => s.workspace === activeWorkspace), rows = peers.map(sessionRow);
  if (rows.length !== list.children.length || rows.some((row, i) => list.children[i] !== row)) list.replaceChildren(...rows);
  const marks = {codex: '◇', claude: '✳', agy: '✦', gemini: '✦', opencode: '⌘'};
  for (const s of peers) {
    const [label, state, task] = s.row.children;
    setIfChanged(label, 'textContent', `${marks[s.agent] || '›_'} ${s.name}`);
    setIfChanged(state, 'textContent', s.ended ? 'Encerrado' : s.attention ? `! ${s.attention}` : s.agent ? (s.agentState === 'running' ? '● Em execução' : '○ Pronto') : 'Shell');
    setIfChanged(state, 'className', s.attention ? 'agent-attention' : s.agentState === 'running' ? 'agent-running' : '');
    setIfChanged(task, 'textContent', s.lastMessage || ''); setIfChanged(task, 'title', s.lastMessage || ''); task.hidden = !s.lastMessage;
    setIfChanged(s.row, 'title', `${s.title || s.name} · arraste para mover; ⌥↑/↓ para reordenar${s.attention ? ` · Atenção: ${s.attention}` : ''}`);
    s.row.setAttribute('aria-label', s.attention ? `${s.name} · Atenção: ${s.attention}` : s.title || s.name);
    s.row.classList.toggle('needs-attention', Boolean(s.attention));
    s.row.classList.toggle('selected', s.id === activeID);
  }
  const recipients = peers.filter(s => s.id !== activeID), recipientsKey = JSON.stringify(recipients.map(s => [s.id, s.name]));
  if (select.dataset.key !== recipientsKey) {
    const recipient = select.value; select.dataset.key = recipientsKey;
    select.replaceChildren(new Option('Toda a equipe', '*'), ...recipients.map(s => new Option(s.name, s.id)));
    if ([...select.options].some(o => o.value === recipient)) select.value = recipient;
  }
  const label = document.getElementById('session-label');
  label.textContent = sessions.get(activeID)?.name ?? '';
  label.style.setProperty('--session-color', sessions.get(activeID)?.color ?? sessionColors[0]);
  label.classList.toggle('needs-attention', Boolean(sessions.get(activeID)?.attention));
}
function renameWorkspace(id, name) {
  if (!workspaces.has(id) || !name.trim()) return;
  workspaces.set(id, name.trim().slice(0, 80));
}
function renameSession(id, name) {
  const s = sessions.get(id); if (!s || !name.trim()) return;
  s.name = name.trim().slice(0, 80); s.host.querySelector('.pane-title').textContent = s.name; s.host.setAttribute('aria-label', s.name); renderNavigation(); renderConversations();
}
function removeSession(id) {
  const s = sessions.get(id); if (!s) return;
  s.accents.dispose(); s.term.dispose(); s.host.remove(); sessions.delete(id);
  const next = [...sessions.values()].find(other => other.workspace === s.workspace);
  if (!next && s.workspace !== privateWorkspace) { workspaces.delete(s.workspace); workspaceDirectories.delete(s.workspace); }
  if (id === activeID) {
    const target = next || sessions.values().next().value;
    if (target) activateSession(target.id); else newWorkspace();
  } else { renderNavigation(); fitVisible(); }
}
function showMessage(message) {
  const sender = sessions.get(message.from), recipient = sessions.get(message.to);
  messageHistory.push({...message, color: sender?.color ?? sessionColors[0]}); if (messageHistory.length > 200) messageHistory.shift();
  if (sender) sender.lastMessage = 'Enviou: ' + message.text;
  if (recipient) recipient.lastMessage = 'Recebeu: ' + message.text;
  renderNavigation(); renderConversations(); fitVisible();
}
function messageRow(message) {
  const row = document.createElement('p'), label = document.createElement('strong'), text = document.createElement('span');
  row.dataset.messageId = message.id;
  row.className = 'conversation-message'; row.style.color = message.color;
  label.textContent = `${message.fromName} → ${message.toName} · ${new Date(message.time).toLocaleTimeString()} `;
  text.textContent = message.text; row.append(label, text); return row;
}
function updateMessageLog(log, messages) {
  const ids = new Set(messages.map(m => m.id));
  let changed = false;
  for (const row of [...log.children]) if (!ids.has(row.dataset.messageId)) { row.remove(); changed = true; }
  const displayed = new Set([...log.children].map(row => row.dataset.messageId));
  for (const message of messages) if (!displayed.has(message.id)) { log.append(messageRow(message)); changed = true; }
  return changed;
}
function renderConversations() {
  for (const session of sessions.values()) {
    const conversation = session.host.querySelector('.session-conversation'), log = conversation.querySelector('[role="log"]');
    const messages = messageHistory.filter(m => m.workspace === session.workspace && (m.from === session.id || m.to === session.id || m.to === '*'));
    const firstMessage = conversation.hidden && messages.length > 0;
    conversation.hidden = !messages.length;
    conversation.querySelector('summary').textContent = `Conversa · ${messages.length}`;
    log.setAttribute('aria-label', `Conversa de ${session.name}`);
    const changed = updateMessageLog(log, messages);
    if (firstMessage) conversation.open = true;
    if (changed) conversation.scrollTop = conversation.scrollHeight;
  }
}
document.addEventListener('DOMContentLoaded', () => {
  document.getElementById('launch-agent').onclick = () => { const kind = document.getElementById('agent-kind').value; createSession({codex: 'Codex', claude: 'Claude', agy: 'Gemini (Antigravity)', gemini: 'Gemini CLI', opencode: 'OpenCode'}[kind], activeWorkspace, kind); };
  document.getElementById('new-session').onclick = () => createSession(`Terminal ${sessions.size + 1}`);
  document.getElementById('split').onclick = () => {
    split = !split; mosaic = false;
    if (split && [...sessions.values()].filter(s => s.workspace === activeWorkspace).length === 1) createSession('Terminal 2');
    fitVisible();
  };
  document.getElementById('mosaic').onclick = () => { mosaic = !mosaic; split = false; fitVisible(); };
  document.getElementById('copy-text').onclick = () => window.voz.copy();
  document.getElementById('paste-text').onclick = () => send({type: 'paste'});
  document.getElementById('rename-session').onclick = () => send({type: 'rename', session: activeID});
  document.getElementById('close-session').onclick = () => send({type: 'closeSession', session: activeID});
  document.getElementById('team-form').onsubmit = event => {
    event.preventDefault(); const input = document.getElementById('team-text');
    if (input.value.trim()) send({type: 'message', session: activeID, to: document.getElementById('recipient').value, text: input.value});
    input.value = '';
  };
  document.getElementById('team').ontoggle = fitVisible;
});

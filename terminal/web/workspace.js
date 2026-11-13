'use strict';
const sessions = new Map(), workspaces = new Map();
let activeID, activeWorkspace, split = false;
const messageHistory = [];
function button(text, action, label = text) {
  const b = document.createElement('button');
  b.type = 'button'; b.textContent = text; b.title = label;
  b.addEventListener('click', action); return b;
}
function screenText(terminal) {
  if (!terminal) throw new Error('Session not found');
  const b = terminal.buffer.active;
  return Array.from({length: b.length}, (_, i) => b.getLine(i)?.translateToString(true) ?? '').join('\n').slice(-262144);
}
function createSession(name = 'Terminal', workspace = activeWorkspace, agent = '') {
  if (sessions.size >= 32) throw new Error('Maximum 32 terminals per window');
  if (!workspaces.has(workspace)) throw new Error('Workspace not found');
  const id = crypto.randomUUID(), host = document.createElement('section');
  host.className = 'terminal-pane'; host.setAttribute('aria-label', name);
  document.getElementById('terminal').append(host);
  const heading = document.createElement('div'), output = document.createElement('div');
  heading.className = 'pane-title'; heading.textContent = name; output.className = 'terminal-content'; host.append(heading, output);
  const terminal = new Terminal({fontFamily: 'Menlo, Monaco, monospace', fontSize: 14, lineHeight: 1.25,
    cursorBlink: true, scrollback: 5000, screenReaderMode: true, theme: BOTERM_THEME});
  const addon = new FitAddon.FitAddon(); terminal.loadAddon(addon); terminal.open(output);
  const session = {id, workspace, name: name.slice(0, 80), term: terminal, fit: addon, host, ended: false, agent, agentState: 'idle'};
  sessions.set(id, session);
  terminal.onData(data => send({type: 'input', session: id, data}));
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
  send({type: 'ready', session: id, workspace, name: session.name, agent, columns: terminal.cols, rows: terminal.rows});
  return id;
}
function newWorkspace(name) {
  if (sessions.size >= 32) throw new Error('Maximum 32 terminals per window');
  const id = crypto.randomUUID(); workspaces.set(id, name || `Projeto ${workspaces.size + 1}`);
  activeWorkspace = id; createSession('Terminal 1', id); return id;
}
function activateSession(id, focus = true) {
  const s = sessions.get(id); if (!s) return;
  activeID = id; activeWorkspace = s.workspace; term = s.term; fit = s.fit;
  send({type: 'activate', session: id});
  renderNavigation(); fitVisible(); if (focus) term.focus();
}
function fitVisible() {
  const visible = [...sessions.values()].filter(s => s.workspace === activeWorkspace && (split || s.id === activeID));
  document.getElementById('terminal').classList.toggle('split', split);
  for (const s of sessions.values()) {
    s.host.hidden = !visible.includes(s);
    s.host.classList.toggle('active', s.id === activeID);
  }
  requestAnimationFrame(() => { for (const s of visible) { if (s.host.clientWidth > 30 && s.host.clientHeight > 30) s.fit.fit(); } });
}
function renderNavigation() {
  const tabs = document.getElementById('workspaces'); tabs.replaceChildren();
  for (const [id, name] of workspaces) {
    const tab = button(name, () => activateSession([...sessions.values()].find(s => s.workspace === id).id));
    tab.classList.toggle('selected', id === activeWorkspace); tab.setAttribute('aria-current', String(id === activeWorkspace));
    tabs.append(tab);
  }
  tabs.append(button('＋', () => newWorkspace(), 'Novo projeto'));
  const list = document.getElementById('sessions'), select = document.getElementById('recipient');
  const recipient = select.value; list.replaceChildren(); select.replaceChildren(new Option('Toda a equipe', '*'));
  for (const s of sessions.values()) {
    if (s.workspace !== activeWorkspace) continue;
    const marks = {codex: '◇', claude: '✳', gemini: '✦', opencode: '⌘'};
    const row = button(`${marks[s.agent] || '›_'} ${s.name}`, () => activateSession(s.id), s.title || s.name);
    const state = document.createElement('small');
    state.textContent = s.ended ? 'Encerrado' : s.agent ? (s.agentState === 'running' ? '● Em execução' : '○ Pronto') : 'Shell';
    state.className = s.agentState === 'running' ? 'agent-running' : ''; row.append(state);
    if (s.lastMessage) { const task = document.createElement('small'); task.className = 'session-task'; task.textContent = s.lastMessage; task.title = s.lastMessage; row.append(task); }
    row.classList.toggle('selected', s.id === activeID); list.append(row);
    if (s.id !== activeID) select.add(new Option(s.name, s.id));
  }
  if ([...select.options].some(o => o.value === recipient)) select.value = recipient;
  document.getElementById('session-label').textContent = sessions.get(activeID)?.name ?? '';
  renderMessages();
}
function renameSession(id, name) {
  const s = sessions.get(id); if (!s || !name.trim()) return;
  s.name = name.trim().slice(0, 80); s.host.querySelector('.pane-title').textContent = s.name; s.host.setAttribute('aria-label', s.name); renderNavigation();
}
function removeSession(id) {
  const s = sessions.get(id); if (!s) return;
  s.term.dispose(); s.host.remove(); sessions.delete(id);
  const next = [...sessions.values()].find(other => other.workspace === s.workspace);
  if (!next) workspaces.delete(s.workspace);
  if (id === activeID) {
    const target = next || sessions.values().next().value;
    if (target) activateSession(target.id); else newWorkspace();
  } else { renderNavigation(); fitVisible(); }
}
function showMessage(message) {
  messageHistory.push(message); if (messageHistory.length > 200) messageHistory.shift();
  const sender = sessions.get(message.from), recipient = sessions.get(message.to);
  if (sender) sender.lastMessage = 'Enviou: ' + message.text;
  if (recipient) recipient.lastMessage = 'Recebeu: ' + message.text;
  if (message.workspace === activeWorkspace) document.getElementById('team').open = true;
  renderNavigation();
}
function renderMessages() {
  const log = document.getElementById('team-log'); log.replaceChildren();
  const messages = messageHistory.filter(m => m.workspace === activeWorkspace);
  for (const m of messages) {
    const row = document.createElement('p'), label = document.createElement('strong'), text = document.createElement('span');
    label.textContent = `${m.fromName} → ${m.toName} · ${new Date(m.time).toLocaleTimeString()} `;
    text.textContent = m.text; row.append(label, text); log.append(row);
  }
  document.getElementById('message-count').textContent = String(messages.length); log.scrollTop = log.scrollHeight;
}
document.addEventListener('DOMContentLoaded', () => {
  document.getElementById('launch-agent').onclick = () => { const kind = document.getElementById('agent-kind').value; createSession({codex: 'Codex', claude: 'Claude', gemini: 'Gemini', opencode: 'OpenCode'}[kind], activeWorkspace, kind); };
  document.getElementById('new-session').onclick = () => createSession(`Terminal ${sessions.size + 1}`);
  document.getElementById('split').onclick = event => {
    split = !split; event.currentTarget.setAttribute('aria-pressed', String(split));
    if (split && [...sessions.values()].filter(s => s.workspace === activeWorkspace).length === 1) createSession('Terminal 2');
    fitVisible();
  };
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

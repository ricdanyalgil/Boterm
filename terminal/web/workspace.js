'use strict';
const sessions = new Map(), workspaces = new Map();
const workspaceDirectories = new Map();
let activeID, activeWorkspace, split = false;
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
  const session = {id, color, accents, workspace, name: name.slice(0, 80), term: terminal, fit: addon, host, ended: false, agent, agentState: 'idle'};
  sessions.set(id, session);
  movableSession(session, heading);
  paneResizers(host);
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
  send({type: 'ready', session: id, workspace, name: session.name, agent, directory: launch.directory ?? workspaceDirectories.get(workspace), prompt: launch.prompt, columns: terminal.cols, rows: terminal.rows});
  return id;
}
function newWorkspace(name, directory) {
  if (sessions.size >= 32) throw new Error('Maximum 32 terminals per window');
  const id = crypto.randomUUID(); workspaces.set(id, name || `Projeto ${nextProjectNumber++}`);
  if (directory) workspaceDirectories.set(id, directory);
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
  updateSplitLayout(visible.length);
  requestAnimationFrame(() => { for (const s of visible) { if (s.host.clientWidth > 30 && s.host.clientHeight > 30) s.fit.fit(); } });
}
function renderNavigation(forceProjects = false) {
  const tabs = document.getElementById('workspaces');
  if (forceProjects || !tabs.querySelector('input')) {
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
  const recipient = select.value; list.replaceChildren(); select.replaceChildren(new Option('Toda a equipe', '*'));
  for (const s of sessions.values()) {
    if (s.workspace !== activeWorkspace) continue;
    const marks = {codex: '◇', claude: '✳', gemini: '✦', opencode: '⌘'};
    const row = button(`${marks[s.agent] || '›_'} ${s.name}`, () => activateSession(s.id), s.title || s.name);
    row.classList.add('session-entry'); row.style.setProperty('--session-color', s.color);
    movableSession(s, row);
    const state = document.createElement('small');
    state.textContent = s.ended ? 'Encerrado' : s.agent ? (s.agentState === 'running' ? '● Em execução' : '○ Pronto') : 'Shell';
    state.className = s.agentState === 'running' ? 'agent-running' : ''; row.append(state);
    if (s.lastMessage) { const task = document.createElement('small'); task.className = 'session-task'; task.textContent = s.lastMessage; task.title = s.lastMessage; row.append(task); }
    row.classList.toggle('selected', s.id === activeID); list.append(row);
    if (s.id !== activeID) select.add(new Option(s.name, s.id));
  }
  if ([...select.options].some(o => o.value === recipient)) select.value = recipient;
  const label = document.getElementById('session-label');
  label.textContent = sessions.get(activeID)?.name ?? '';
  label.style.setProperty('--session-color', sessions.get(activeID)?.color ?? sessionColors[0]);
  renderMessages();
}
function renameWorkspace(id, name) {
  if (!workspaces.has(id) || !name.trim()) return;
  workspaces.set(id, name.trim().slice(0, 80));
}
function renameSession(id, name) {
  const s = sessions.get(id); if (!s || !name.trim()) return;
  s.name = name.trim().slice(0, 80); s.host.querySelector('.pane-title').textContent = s.name; s.host.setAttribute('aria-label', s.name); renderNavigation();
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

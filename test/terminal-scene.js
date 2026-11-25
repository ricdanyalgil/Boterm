// Design capture fixture: a realistic eight-agent team. Set SCENE ('mosaic' | 'dashboard') and WORLD before this file.
const now = Date.now(), first = activeID;
setWorld(typeof WORLD === 'undefined' ? 'grid' : WORLD);
renameWorkspace(activeWorkspace, 'boterm'); workspaces.set(crypto.randomUUID(), 'site'); workspaces.set(crypto.randomUUID(), 'docs'); renderNavigation(true);
const team = [['Orquestrador', 'claude', 'busy', 72], ['Desenvolvimento', 'codex', 'busy', 48], ['Testes', 'claude', 'attention', 31], ['Integrações', 'gemini', 'idle', 7],
  ['UX e design', 'claude', 'busy', 22], ['Engenharia de loop', 'codex', 'idle', 3], ['Resposta e entrega', 'claude', 'idle', 15], ['Mensageiro', 'claude', 'idle', 41]];
const text = {
  Orquestrador: '\x1b[32m●\x1b[0m Plano: dividir a tarefa em 3 frentes\r\n\x1b[2m────────────────────────────\x1b[0m\r\n\x1b[34m❯\x1b[0m delegar src/auth/session.ts → Desenvolvimento\r\n\x1b[34m❯\x1b[0m pedir suíte de testes → Testes\r\n\x1b[34m❯\x1b[0m rever layout do painel → UX e design\r\n\x1b[32m✓\x1b[0m 3 mensagens enviadas aos agentes\r\n\x1b[2m  aguardando relatórios…\x1b[0m\r\n\x1b[33m!\x1b[0m Testes aguarda a sua permissão\r\n',
  Desenvolvimento: '\x1b[34m$\x1b[0m git diff --stat\r\n src/auth/session.ts | 42 \x1b[32m+++++++++\x1b[31m--\x1b[0m\r\n src/auth/token.ts   | 18 \x1b[32m++++\x1b[0m\r\n src/ui/Login.tsx    | 31 \x1b[32m+++++++\x1b[31m-\x1b[0m\r\n\x1b[2m 3 files changed\x1b[0m\r\n\x1b[32m●\x1b[0m A editar src/auth/refresh.ts\r\n\x1b[32m+\x1b[0m export async function refresh(t) {\r\n\x1b[32m+\x1b[0m   return rotate(t)\r\n\x1b[32m+\x1b[0m }\r\n',
  Testes: '\x1b[34m●\x1b[0m Bash(npm test)\r\n  \x1b[2m⎿ a aguardar permissão\x1b[0m\r\n\r\n\x1b[33m╭──────────────────────────────╮\x1b[0m\r\n\x1b[33m│\x1b[0m Do you want to run npm test?  \x1b[33m│\x1b[0m\r\n\x1b[33m│\x1b[0m \x1b[36m❯ 1. Yes\x1b[0m   2. No             \x1b[33m│\x1b[0m\r\n\x1b[33m╰──────────────────────────────╯\x1b[0m\r\n',
  'UX e design': '\x1b[32m●\x1b[0m A rever tokens de espaçamento\r\n\x1b[34m$\x1b[0m grep -r "gap:" src/ui\r\n\x1b[2msrc/ui/Sidebar.css:8\x1b[0m   gap: 12px\r\n\x1b[2msrc/ui/Tabs.css:3\x1b[0m      gap: 24px\r\n\x1b[32m✓\x1b[0m módulo de 24 px confirmado\r\n'
};
const ids = [];
team.forEach(([name, agent, state, minutes], i) => {
  // Plain shells labelled as agents: a fixture must never start a real agent CLI.
  const id = i === 0 ? first : createSession(name, activeWorkspace);
  if (i === 0) renameSession(id, name);
  const s = sessions.get(id); s.agent = agent; s.startedAt = now - minutes * 60000;
  if (state === 'busy') { s.lastOutput = now + 1e9; s.lastInput = 0; }
  if (state === 'attention') { s.attention = 'Permissão'; s.host.classList.add('needs-attention'); }
  s.term.reset(); if (text[name]) s.term.write(text[name]);
  ids.push(id);
});
workspaceStarted.set(activeWorkspace, new Date(now - 72 * 60000));
sessions.get(ids[7]).lastMessage = 'Aguarda resposta no Telegram';
sessions.get(ids[2]).lastMessage = 'Pede: permitir npm test';
const h = (id, w, ht) => { const s = sessions.get(id).host; s.dataset.w = w; s.dataset.h = ht; };
h(ids[0], 4, 4); h(ids[1], 2, 4); h(ids[2], 3, 4); h(ids[4], 3, 4);
for (const i of [3, 5, 6, 7]) { const s = sessions.get(ids[i]).host; s.dataset.w = 1; s.dataset.h = 2; }
activateSession(ids[0]); mosaic = true; split = false; fitVisible(); renderNavigation();
const ev = (session, kind, text, ago) => receiveEvent({id: crypto.randomUUID(), workspace: activeWorkspace, session: ids[session], name: team[session][0], kind, text, time: new Date(now - ago * 60000).toISOString()});
ev(2, 'test-fail', 'login.test.ts: token expirava antes da renovação', 38); ev(1, 'fix', 'renova o token 60 s antes de expirar', 30); ev(2, 'test-pass', 'login.test.ts e session.test.ts', 26); ev(4, 'improvement', 'espaçamento da lateral no módulo de 24 px', 12); ev(2, 'test-fail', 'api/session.test.ts: 401 sem cabeçalho', 4);
requestDashboard = () => {}; // the fixture's data stands in for the app's
receiveDashboard({workspace: activeWorkspace, directory: '/Users/dev/projetos/boterm', usage: {'mcp:github': {calls: 21, seconds: 160}, 'mcp:boterm': {calls: 14, seconds: 52}, 'mcp:playwright': {calls: 3, seconds: 38}},
  events: dashboardData.get(activeWorkspace)?.events, sessions: {[ids[0]]: {Edit: {calls: 2, seconds: 1}, 'mcp:boterm': {calls: 9, seconds: 30}}, [ids[1]]: {Edit: {calls: 14, seconds: 6}, Bash: {calls: 9, seconds: 40}}, [ids[2]]: {Bash: {calls: 6, seconds: 90}}, [ids[4]]: {Edit: {calls: 5, seconds: 2}, 'mcp:github': {calls: 21, seconds: 160}}}},
  {code: {repo: true, branch: 'main', changed: 14, untracked: 2, added: 412, removed: 96, commits: ['a1c9e02 Renova token antes de expirar', '7f3b2d1 Testes de sessão', 'c04e9aa Espaçamento da lateral'],
    files: [{file: 'src/auth/login.ts', added: 120, removed: 30}, {file: 'src/api/session.ts', added: 88, removed: 12}, {file: 'test/login.test.ts', added: 64, removed: 0}, {file: 'src/ui/Sidebar.css', added: 22, removed: 31}, {file: 'src/auth/token.ts', added: 18, removed: 4}]},
   history: {entries: 6, archive: false, recent: ['2026-11-17 10:13 · Login com renovação de token', '2026-11-16 18:40 · Painel do projeto', '2026-11-16 15:02 · Mensageiro no Telegram']}});
for (let i = 0; i < 5; i++) messageHistory.push({id: crypto.randomUUID(), workspace: activeWorkspace, from: ids[0], to: ids[1], text: i < 3 ? 'tarefa' : '[Terminal: submitted input] faça x', time: new Date().toISOString()});
if (typeof SCENE !== 'undefined' && SCENE === 'dashboard') openDashboard();
updateLiveState();
// Let the shells finish printing their first prompt, so idle reads as idle.
await new Promise(r => setTimeout(r, 3500));
// Then replace whatever the real shells printed: their prompt carries the user and Mac name, which must never be captured.
const prompt = '\x1b[2m(base)\x1b[0m dev@boterm boterm % ';
team.forEach(([name], i) => { const t = sessions.get(ids[i]).term; t.reset(); t.write((text[name] || '') + prompt); });
const waiting = sessions.get(ids[2]); waiting.attention = 'Confirmação solicitada'; waiting.host.classList.add('needs-attention'); renderNavigation();
return {scene: typeof SCENE === 'undefined' ? 'mosaic' : SCENE, world: document.documentElement.dataset.world};

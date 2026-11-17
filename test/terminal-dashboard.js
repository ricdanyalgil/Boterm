// Project dashboard against the real app: git, events, Claude hook timing, history, live activity and clicks.
const check = (condition, message) => { if (!condition) throw new Error(message); };
const wait = async (test, label, limit = 300) => { for (let i = 0; i < limit; i++) { if (test()) return; await new Promise(r => setTimeout(r, 100)); } throw new Error('Timed out: ' + label); };
const flat = id => { const b = sessions.get(id).term.buffer.active; let text = ''; for (let i = 0; i < b.length; i++) { const line = b.getLine(i); text += (i && !line.isWrapped ? '\n' : '') + line.translateToString(true); } return text; };
const run = async (id, command, marker) => {
  window.voz.insert(`${command}; echo ${marker}-done`, id, true);
  await wait(() => flat(id).split(`${marker}-done`).length > 2, marker);
  return flat(id);
};
const ready = async id => wait(() => /[%$#] ?$/m.test(screenText(sessions.get(id).term)), 'prompt');
const cli = '"$BOTERM_CLI"', dir = `/tmp/boterm-dashboard-${crypto.randomUUID()}`;
const setup = activeID; await ready(setup);
await run(setup, `mkdir -p ${dir} && cd ${dir} && git init -q && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m inicio && sleep 2`, 'd0');

const project = newWorkspace('Painel', dir), shell = activeID; await ready(shell);
await run(shell, `sleep 1 && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m durante && printf 'a\\nb\\n' > app.js && git add app.js`, 'd00');
const orchestrator = createSession('Orquestrador', project, '', {role: 'Orquestrador', directory: dir}); await ready(orchestrator);
await run(orchestrator, `${cli} event test-fail 'npm test: login quebrado' && ${cli} event fix 'login corrigido' && ${cli} history 'Login' 'Falha apanhada e corrigida.'`, 'd1');
check(sessions.get(orchestrator).lastMessage === 'Correção: login corrigido', 'Event did not reach the sidebar');
const hook = (event, name, id, ms) => `echo '{"hook_event_name":"${event}","tool_name":"${name}","tool_use_id":"${id}"${ms ? `,"duration_ms":${ms}` : ''}}' | ${cli} tool`;
const silent = await run(orchestrator, `${hook('PreToolUse', 'mcp__github__search', 't1')} && ${hook('PostToolUse', 'mcp__github__search', 't1', 1500)} && ${hook('PostToolUse', 'mcp__github__search', 't2', 1600)} && ${hook('PostToolUse', 'Edit', 't3', 20)} && echo hooks-ok`, 'd2');
check(silent.includes('hooks-ok') && !silent.split('d2-done')[1].includes('boterm:'), 'Hook command printed or failed');

document.getElementById('dashboard-toggle').click();
check(document.body.dataset.view === 'dashboard' && getComputedStyle(document.getElementById('terminal')).display === 'none', 'Dashboard did not replace the terminals');
const panel = document.getElementById('dashboard');
await wait(() => panel.textContent.includes('+2 −0') && panel.textContent.includes('2 chamadas'), 'fresh dashboard data');
const text = panel.textContent;
check(text.includes('1 falha apanhada') && text.includes('1 correção'), 'Quality events missing');
check(text.includes('3 s') && text.includes('2 chamadas') && text.includes('github'), 'MCP time missing');
check(text.includes('1 arquivo alterado') && text.includes('1 commit nesta sessão'), 'Code changes missing');
check(text.includes('1 entrada em .boterm/HISTORY.md') && text.includes('Login'), 'History missing');
check(panel.querySelectorAll('.dash-agent').length === 2 && [...panel.querySelectorAll('.dash-agent')].find(r => r.textContent.includes('Orquestrador')).querySelector('.col-edits').textContent === '1', 'Agents or tool counts missing');

// Live activity: output pulses the dot; typing echo does not.
window.voz.insert('for i in $(seq 1 40); do echo tick; sleep 0.1; done', shell, true);
await wait(() => sessions.get(shell).row.classList.contains('busy') && panel.querySelector('.state-busy'), 'busy pulse');
await wait(() => !sessions.get(shell).row.classList.contains('busy'), 'busy cleared', 120);

// A click during constant re-rendering still opens the chosen terminal.
const target = [...panel.querySelectorAll('.dash-agent button')].find(b => b.textContent.includes('Orquestrador'));
target.dispatchEvent(new MouseEvent('mousedown', {bubbles: true})); renderDashboard(); target.click();
check(!document.body.dataset.view && activeID === orchestrator, 'Agent click did not open its terminal');

// Reopening the project folder finds its history once.
newWorkspace('Reaberto', dir);
await wait(() => !document.getElementById('history-notice').hidden, 'history notice');
check(document.getElementById('history-notice').textContent.includes('1 entrada · última:') && document.getElementById('history-notice').textContent.includes('Login'), 'History notice text');
activateSession(orchestrator); document.getElementById('dashboard-toggle').click();
await wait(() => panel.textContent.includes('+2 −0'), 'dashboard for snapshot');
return {dashboard: true, gitChanges: true, qualityEvents: true, mcpTiming: true, historyCard: true, busyPulse: true, clickDuringRender: true, historyNotice: true};

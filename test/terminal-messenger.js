// Role gate on the real socket: only a session launched as Mensageiro may contact the owner or record permissions.
const check = (condition, message) => { if (!condition) throw new Error(message); };
const wait = async (test, label, limit = 300) => { for (let i = 0; i < limit; i++) { if (test()) return; await new Promise(r => setTimeout(r, 100)); } throw new Error('Timed out: ' + label); };
const shell = async (name, role) => {
  const id = createSession(name, activeWorkspace, '', role ? {role} : {});
  await wait(() => /[%$#] ?$/m.test(screenText(sessions.get(id).term)), `${name} prompt`);
  return id;
};
// Rejoin soft-wrapped rows so checks do not depend on the terminal width.
const flat = id => { const b = sessions.get(id).term.buffer.active; let text = ''; for (let i = 0; i < b.length; i++) { const line = b.getLine(i); text += (i && !line.isWrapped ? '\n' : '') + line.translateToString(true); } return text; };
const run = async (id, command, marker) => {
  window.voz.insert(`${command}; echo ${marker}-done`, id, true);
  await wait(() => flat(id).split(`${marker}-done`).length > 2, marker);
  return flat(id);
};
const plain = await shell('Testes'), impostor = await shell('Mensageiro'), messenger = await shell('Mensageiro', 'Mensageiro');
const cli = '"$BOTERM_CLI"';
let out = await run(plain, `${cli} notify oi`, 'm1');
check(out.includes('Only the Mensageiro session'), 'Plain session reached notify');
out = await run(impostor, `${cli} grant deploy:x whatsapp 'Sim, sempre'`, 'm2');
check(out.includes('Only the Mensageiro session'), 'Session renamed Mensageiro without the role could grant');
out = await run(plain, `${cli} permissions`, 'm3');
const listed = out.split('m3-done').at(-2);
check(listed.trimStart().startsWith('[') && !listed.includes('boterm:'), 'permissions must be readable by every agent');
out = await run(messenger, `${cli} answer naoexiste`, 'm4');
check(out.includes('Unknown request ID'), 'Unknown ask accepted');
out = await run(messenger, `${cli} grant deploy:x telegram 'Sim'`, 'm5');
check(out.includes('grant needs via whatsapp|email'), 'grant accepted an unverifiable channel');
out = await run(messenger, `${cli} notify 'teste'`, 'm6');
check(/Telegram (não está emparelhado|não configurado)|"sent"/.test(out), 'notify gave no clear Telegram state');
// Project history and idle-gated compaction.
const dir = `/tmp/boterm-history-${crypto.randomUUID()}`;
await run(plain, `mkdir -p ${dir}`, 'h0');
const orchestrator = createSession('Orquestrador', activeWorkspace, '', {role: 'Orquestrador', directory: dir});
await wait(() => /[%$#] ?$/m.test(screenText(sessions.get(orchestrator).term)), 'orchestrator prompt');
out = await run(plain, `${cli} history 'Falso' 'Nao devia gravar'`, 'h1');
check(out.includes('Only the Orquestrador records project history'), 'Non-orchestrator wrote history');
out = await run(orchestrator, `${cli} history 'Mosaico livre' 'Feito, testado e revisto.'; cat ${dir}/.boterm/HISTORY.md`, 'h2');
check(out.includes('· Mosaico livre') && out.includes('Feito, testado e revisto.'), 'History entry not written to the project');
out = await run(orchestrator, `${cli} history`, 'h3');
check(out.includes('# Histórico Boterm'), 'history read failed');
out = await run(plain, `${cli} compact ${plain}`, 'h4');
check(out.includes('No known compaction command'), 'Compaction guessed a command for a plain shell');
const identity = `python3 -c 'import socket,json,os;s=socket.socket(socket.AF_UNIX);s.connect(os.environ["BOTERM_SOCKET"]);s.sendall((json.dumps(dict(command="agentState",**{"from":os.environ["BOTERM_SESSION"]},workspace=os.environ["BOTERM_WORKSPACE"],agent="claude",state="idle"))+"\\n").encode());print(s.recv(999))'`;
await run(orchestrator, identity, 'h5');
out = await run(orchestrator, `${cli} compact ${orchestrator} 'manter o plano'`, 'h6');
check(out.includes('"scheduled"') && out.includes('/compact manter o plano'), 'Compaction not scheduled');
const before = Date.now();
check(!/no such file or directory: \/compact|command not found: \/compact/.test(flat(orchestrator)), 'Compaction sent before the terminal was idle');
await wait(() => /no such file or directory: \/compact|command not found: \/compact/.test(flat(orchestrator)), 'compaction delivery', 900);
check(Date.now() - before > 20000, 'Compaction ignored recent input');
return {projectHistory: true, historyRoleGate: true, compactionUnknownAgent: true, compactionWaitsForIdle: true, roleGate: true, impostorRejected: true, permissionsReadable: true, grantChannelChecked: true, telegramStateReported: true};

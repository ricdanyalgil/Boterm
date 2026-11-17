// Role gate on the real socket: only a session launched as Mensageiro may contact the owner or record permissions.
const check = (condition, message) => { if (!condition) throw new Error(message); };
const wait = async (test, label) => { for (let i = 0; i < 300; i++) { if (test()) return; await new Promise(r => setTimeout(r, 100)); } throw new Error('Timed out: ' + label); };
const shell = async (name, role) => {
  const id = createSession(name, activeWorkspace, '', role ? {role} : {});
  await wait(() => /[%$#] ?$/m.test(screenText(sessions.get(id).term)), `${name} prompt`);
  return id;
};
const run = async (id, command, marker) => {
  window.voz.insert(`${command}; echo ${marker}-done`, id, true);
  await wait(() => screenText(sessions.get(id).term).includes(`${marker}-done\n`) || screenText(sessions.get(id).term).split(`${marker}-done`).length > 2, marker);
  return screenText(sessions.get(id).term);
};
const plain = await shell('Testes'), impostor = await shell('Mensageiro'), messenger = await shell('Mensageiro', 'Mensageiro');
const cli = '"$BOTERM_CLI"';
let out = await run(plain, `${cli} notify oi`, 'm1');
check(out.includes('Only the Mensageiro session'), 'Plain session reached notify');
out = await run(impostor, `${cli} grant deploy:x whatsapp 'Sim, sempre'`, 'm2');
check(out.includes('Only the Mensageiro session'), 'Session renamed Mensageiro without the role could grant');
out = await run(plain, `${cli} permissions`, 'm3');
const listed = out.slice(out.lastIndexOf('permissions; echo m3-done') + 25);
check(listed.trimStart().startsWith('[') && !listed.includes('boterm:'), 'permissions must be readable by every agent');
out = await run(messenger, `${cli} answer naoexiste`, 'm4');
check(out.includes('Unknown request ID'), 'Unknown ask accepted');
out = await run(messenger, `${cli} grant deploy:x telegram 'Sim'`, 'm5');
check(out.includes('grant needs via whatsapp|email'), 'grant accepted an unverifiable channel');
out = await run(messenger, `${cli} notify 'teste'`, 'm6');
check(/Telegram (não está emparelhado|não configurado)|"sent"/.test(out), 'notify gave no clear Telegram state');
return {roleGate: true, impostorRejected: true, permissionsReadable: true, grantChannelChecked: true, telegramStateReported: true};

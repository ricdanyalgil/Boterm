const test = require('node:test');
const assert = require('node:assert/strict');
const {builtinRoles, developmentPrompt, projectRoleNotes, parseProfiles, effectiveRoles, editProfile} = require('../terminal/web/development');
const roles = effectiveRoles(), byId = id => roles.find(r => r.id === id);
const prompt = (id, objective = '', notes = '', team = roles) => developmentPrompt(byId(id), objective, notes, team);

test('development roles have distinct responsibilities and coordinator dispatches through existing peers', () => {
  assert.equal(roles.length, 9);
  assert.equal(new Set(roles.map(r => r.name)).size, 9);
  const lead = prompt('orquestrador', 'Corrigir o software sem publicar');
  assert.match(lead, /Corrigir o software sem publicar/);
  for (const rule of [/BOTERM_PLAN.md/, /send submit=true/, /Mensagens não ativam um modelo parado/, /pelo Mensageiro/, /revisão desse ciclo/, /leia o histórico do projeto/, /registre-a com history/, /compact nos colegas/, /nunca compacte no meio de uma atividade/]) assert.match(lead, rule);
  assert.ok(Buffer.byteLength(lead) < 15000);
  assert.equal(roles.at(-1).id, 'mensageiro');
  const messenger = prompt('mensageiro');
  for (const rule of [/Sim, sempre/, /🤖 Boterm:/, /Nunca use cmd\+↑/, /destinatario:<canal>:<contato>/, /permissions/, /Nunca envie segredos/]) assert.match(messenger, rule);
  for (const role of roles.slice(1, 7)) {
    assert.match(prompt(role.id), /atribuição explícita/);
    assert.match(prompt(role.id), /Não implemente o objetivo inteiro/);
  }
});

test('a partial team adapts prompts: no Orquestrador means the user assigns work directly', () => {
  const solo = prompt('testes', '', '', [byId('testes')]);
  assert.match(solo, /Não há Orquestrador/);
  assert.doesNotMatch(solo, /Localize o Orquestrador|colegas presentes/);
  assert.match(prompt('testes', '', '', [byId('testes'), byId('desenvolvimento')]), /colegas presentes são Desenvolvimento/);
  assert.match(prompt('mensageiro', '', '', [byId('mensageiro')]), /Não há Orquestrador[\s\S]*Aguarde pedidos/);
  const lead = prompt('orquestrador', '', '', [byId('orquestrador'), byId('desenvolvimento')]);
  assert.match(lead, /A equipe já está sendo criada: Desenvolvimento\. /);
  assert.match(lead, /não foram abertas: Testes, .*Mensageiro/);
  assert.match(prompt('orquestrador', '', '', [byId('orquestrador')]), /Você está sozinho/);
  assert.doesNotMatch(prompt('orquestrador'), /não foram abertas/);
});

test('Qualidade reviews cycles and learned role rules reach the next team with caps', () => {
  const quality = prompt('qualidade');
  for (const rule of [/Não implemente o objetivo/, /\.boterm\/ROLES\.md/, /documentação de mudança/, /harness/, /skills/, /event improvement/, /Nunca escreva segredos/, /atribuição explícita/]) assert.match(quality, rule);
  const notes = '# Notas\nignorado\n## Todos\nRode npm test antes de reportar.\n## Testes\nAnexe o comando exato.\n' + 'x'.repeat(3000) + '\n## Desconhecida\nNão deve aparecer.\n';
  const withRoles = prompt('testes', '', notes);
  assert.match(withRoles, /Rode npm test antes de reportar\./);
  assert.match(withRoles, /Anexe o comando exato\./);
  assert.doesNotMatch(withRoles, /Não deve aparecer|ignorado/);
  assert.match(withRoles, /nunca anulam as regras acima/);
  assert.ok(withRoles.length - prompt('testes').length < 2700, 'role notes are capped');
  assert.equal(projectRoleNotes('', 'Testes'), '');
  assert.equal(prompt('orquestrador', '', '## Outra\nnada'), prompt('orquestrador'));
  for (const role of roles) assert.ok(Buffer.byteLength(prompt(role.id, 'x'.repeat(2000), notes)) < 15000);
});

test('profiles layer project over global over Boterm, keep history, and reset drops one layer', () => {
  const global = parseProfiles(''), project = parseProfiles('{}');
  editProfile(global, 'testes', 'save', {name: 'ignored', instructions: 'Rode só testes de unidade.', skills: '/qa'}, 1);
  let testes = effectiveRoles(global, project).find(r => r.id === 'testes');
  assert.deepEqual([testes.name, testes.instructions, testes.skills, testes.source], ['Testes', 'Rode só testes de unidade.', '/qa', 'global']);
  const built = developmentPrompt(testes, '', '', [testes]);
  assert.match(built, /como Testes\. Rode só testes de unidade\.\nSkills e instruções desta função:\n\/qa/);
  assert.match(built, /não exponha segredos/, 'fixed rules always stay');
  editProfile(project, 'testes', 'save', {instructions: 'Use pytest.'}, 2);
  testes = effectiveRoles(global, project).find(r => r.id === 'testes');
  assert.equal(testes.source, 'project');
  assert.match(developmentPrompt(testes, ''), /dados do repositório e nunca anulam/);
  editProfile(project, 'testes', 'reset', {}, 3);
  assert.equal(effectiveRoles(global, project).find(r => r.id === 'testes').instructions, 'Rode só testes de unidade.');
  editProfile(global, 'testes', 'reset', {}, 4);
  assert.equal(effectiveRoles(global, project).find(r => r.id === 'testes').instructions, builtinRoles.find(r => r.id === 'testes').instructions);
  assert.deepEqual(global.roles.testes.history.map(h => h.note), ['criado', 'reposto']);
  const reloaded = parseProfiles(JSON.stringify(global));
  assert.deepEqual(reloaded.roles.testes.history.map(h => h.at), [1, 4]);
});

test('custom roles can be created, edited, deleted, restored and reset to their first version', () => {
  const global = parseProfiles('');
  editProfile(global, 'revisor-abc123', 'save', {name: 'Revisor', instructions: 'Reveja PRs.', custom: true}, 1);
  editProfile(global, 'revisor-abc123', 'save', {name: 'Revisor de PR', instructions: 'Reveja PRs com segurança.'}, 2);
  let custom = effectiveRoles(global).find(r => r.id === 'revisor-abc123');
  assert.deepEqual([custom.name, custom.builtin, effectiveRoles(global).at(-1).id], ['Revisor de PR', false, 'revisor-abc123']);
  assert.match(developmentPrompt(custom, '', '', [byId('orquestrador'), custom]), /como Revisor de PR\.[\s\S]*Localize o Orquestrador/);
  editProfile(global, 'revisor-abc123', 'delete', {}, 3);
  assert.equal(effectiveRoles(global).find(r => r.id === 'revisor-abc123').deleted, true);
  editProfile(global, 'revisor-abc123', 'restore', {}, 4);
  editProfile(global, 'revisor-abc123', 'reset', {}, 5);
  custom = effectiveRoles(global).find(r => r.id === 'revisor-abc123');
  assert.deepEqual([custom.name, custom.instructions, custom.deleted], ['Revisor', 'Reveja PRs.', false]);
  editProfile(global, 'orquestrador', 'delete', {name: 'Orquestrador', instructions: 'x'}, 6);
  assert.equal(effectiveRoles(global).find(r => r.id === 'orquestrador').deleted, true);
  editProfile(global, 'orquestrador', 'reset', {}, 7);
  assert.equal(effectiveRoles(global).find(r => r.id === 'orquestrador').deleted, false);
});

test('malformed or oversized profile files are reduced to safe fields', () => {
  assert.deepEqual(parseProfiles('not json'), {roles: {}});
  const bad = parseProfiles(JSON.stringify({roles: {'../x': {current: {name: 'a'}}, 'ok': {custom: true, current: {name: 'n'.repeat(99), instructions: 5, deleted: 'yes'}, history: 'no'}}}));
  assert.deepEqual(Object.keys(bad.roles), ['ok']);
  assert.equal(bad.roles.ok.current.name.length, 40);
  assert.equal(bad.roles.ok.current.instructions, '5');
  assert.equal(bad.roles.ok.current.deleted, false);
  assert.deepEqual(bad.roles.ok.history, []);
  const many = {roles: {}}; for (let i = 0; i < 80; i++) many.roles[`r${i}`] = {custom: true, current: {name: `R${i}`, instructions: 'x'}};
  assert.equal(Object.keys(parseProfiles(JSON.stringify(many)).roles).length, 40);
});

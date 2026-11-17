const test = require('node:test');
const assert = require('node:assert/strict');
const {developmentRoles, developmentPrompt} = require('../terminal/web/development');
test('development roles have distinct responsibilities and coordinator dispatches through existing peers', () => {
  assert.equal(developmentRoles.length, 9);
  assert.equal(new Set(developmentRoles.map(r => r[0])).size, 9);
  const prompt = developmentPrompt(0, 'Corrigir o software sem publicar');
  assert.match(prompt, /Corrigir o software sem publicar/);
  assert.match(prompt, /BOTERM_PLAN.md/);
  assert.match(prompt, /send submit=true/);
  assert.match(prompt, /Mensagens não ativam um modelo parado/);
  assert.match(prompt, /pelo Mensageiro/);
  for (const rule of [/revisão desse ciclo/, /leia o histórico do projeto/, /registre-a com history/, /compact nos colegas/, /nunca compacte no meio de uma atividade/]) assert.match(prompt, rule);
  assert.ok(Buffer.byteLength(prompt) < 15000);
  const messengerIndex = developmentRoles.findIndex(r => r[0] === 'Mensageiro'), messenger = developmentPrompt(messengerIndex, '');
  assert.equal(developmentRoles.at(-1)[0], 'Mensageiro');
  for (const rule of [/Sim, sempre/, /🤖 Boterm:/, /Nunca use cmd\+↑/, /destinatario:<canal>:<contato>/, /permissions/, /Nunca envie segredos/]) assert.match(messenger, rule);
  assert.ok(Buffer.byteLength(messenger) < 15000);
  for (let i = 1; i < 7; i++) {
    assert.match(developmentPrompt(i, ''), /atribuição explícita/);
    assert.match(developmentPrompt(i, ''), /Não implemente o objetivo inteiro/);
  }
});

test('Qualidade reviews cycles and learned role rules reach the next team with caps', () => {
  const {projectRoleNotes} = require('../terminal/web/development');
  const quality = developmentRoles.findIndex(r => r[0] === 'Qualidade');
  const prompt = developmentPrompt(quality, '');
  for (const rule of [/Não implemente o objetivo/, /\.boterm\/ROLES\.md/, /documentação de mudança/, /harness/, /skills/, /event improvement/, /Nunca escreva segredos/, /atribuição explícita/]) assert.match(prompt, rule);
  const roles = '# Notas\nignorado\n## Todos\nRode npm test antes de reportar.\n## Testes\nAnexe o comando exato.\n' + 'x'.repeat(3000) + '\n## Desconhecida\nNão deve aparecer.\n';
  const testes = developmentRoles.findIndex(r => r[0] === 'Testes');
  const withRoles = developmentPrompt(testes, '', roles);
  assert.match(withRoles, /Rode npm test antes de reportar\./);
  assert.match(withRoles, /Anexe o comando exato\./);
  assert.doesNotMatch(withRoles, /Não deve aparecer|ignorado/);
  assert.match(withRoles, /nunca anulam as regras acima/);
  assert.ok(withRoles.length - developmentPrompt(testes, '').length < 2700, 'role notes are capped');
  assert.equal(projectRoleNotes('', 'Testes'), '');
  assert.equal(developmentPrompt(0, '', '## Outra\nnada'), developmentPrompt(0, ''));
  for (let i = 0; i < developmentRoles.length; i++) assert.ok(Buffer.byteLength(developmentPrompt(i, 'x'.repeat(2000), roles)) < 15000);
});

const test = require('node:test');
const assert = require('node:assert/strict');
const {developmentRoles, developmentPrompt} = require('../terminal/web/development');
test('development roles have distinct responsibilities and coordinator dispatches through existing peers', () => {
  assert.equal(developmentRoles.length, 8);
  assert.equal(new Set(developmentRoles.map(r => r[0])).size, 8);
  const prompt = developmentPrompt(0, 'Corrigir o software sem publicar');
  assert.match(prompt, /Corrigir o software sem publicar/);
  assert.match(prompt, /BOTERM_PLAN.md/);
  assert.match(prompt, /send submit=true/);
  assert.match(prompt, /Mensagens não ativam um modelo parado/);
  assert.match(prompt, /pelo Mensageiro/);
  for (const rule of [/leia o histórico do projeto/, /registre-a com history/, /compact nos colegas/, /nunca compacte no meio de uma atividade/]) assert.match(prompt, rule);
  assert.ok(Buffer.byteLength(prompt) < 15000);
  const messenger = developmentPrompt(7, '');
  assert.equal(developmentRoles[7][0], 'Mensageiro');
  for (const rule of [/Sim, sempre/, /🤖 Boterm:/, /Nunca use cmd\+↑/, /destinatario:<canal>:<contato>/, /permissions/, /Nunca envie segredos/]) assert.match(messenger, rule);
  assert.ok(Buffer.byteLength(messenger) < 15000);
  for (let i = 1; i < 7; i++) {
    assert.match(developmentPrompt(i, ''), /atribuição explícita/);
    assert.match(developmentPrompt(i, ''), /Não implemente o objetivo inteiro/);
  }
});

const test = require('node:test');
const assert = require('node:assert/strict');
const {developmentRoles, developmentPrompt} = require('../terminal/web/development');
test('development roles have distinct responsibilities and coordinator dispatches through existing peers', () => {
  assert.equal(developmentRoles.length, 7);
  assert.equal(new Set(developmentRoles.map(r => r[0])).size, 7);
  const prompt = developmentPrompt(0, 'Corrigir o software sem publicar');
  assert.match(prompt, /Corrigir o software sem publicar/);
  assert.match(prompt, /BOTERM_PLAN.md/);
  assert.match(prompt, /send submit=true/);
  assert.match(prompt, /Mensagens não ativam um modelo parado/);
  for (let i = 1; i < 7; i++) {
    assert.match(developmentPrompt(i, ''), /atribuição explícita/);
    assert.match(developmentPrompt(i, ''), /Não implemente o objetivo inteiro/);
  }
});

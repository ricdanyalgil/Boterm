const test = require('node:test');
const assert = require('node:assert/strict');
const {terminalAttention} = require('../terminal/web/attention');
test('recognizes explicit permission, trust, login and input requests', () => {
  for (const prompt of [
    'Allow access to this file?\n> 1. Yes, allow access\n  2. No, deny access\nEsc to cancel',
    'Run this command?\n> 1. Yes, run command\n  4. No, cancel',
    'Trust this folder?\n› 1. Trust and continue\n  2. Back to Agent Command Center',
    'Do you trust the contents of this project?\n> Yes, I trust this folder\nNo, exit',
    'Would you like to run the following command?\n› 1. Yes, proceed (y)\n  2. No (n)'
  ]) assert.equal(terminalAttention(prompt), 'Confirmação solicitada');
  assert.equal(terminalAttention('How would you like to authenticate?\n● 1. Sign in with Google\n2. Use API key'), 'Login solicitado');
  assert.equal(terminalAttention('Password:'), 'Login solicitado');
  assert.equal(terminalAttention('Digite o nome do projeto:'), 'Entrada solicitada');
});
test('does not flag ordinary composers, prose, completed work or old scrollback', () => {
  for (const text of ['› Ask Codex to do anything', 'Thinking...\nTool call running', 'Tests: 19 passed\n❯', 'The documentation describes how to trust this folder.', 'Run this command?\nYes\nNo\n' + 'Working...\n'.repeat(25)]) assert.equal(terminalAttention(text), '');
});
test('clears a previous request when a composer returns and detects the next request', () => {
  const previous = 'Run this command?\n> 1. Yes, run command\n  4. No, cancel\n';
  for (const idle of ['❯', '› Ask Codex to do anything', '> Auto mode: edits & safe commands auto-approved', '(base) user@host ~/project %']) assert.equal(terminalAttention(previous + idle), '');
  assert.equal(terminalAttention(previous + '❯\nPassword:'), 'Login solicitado');
});

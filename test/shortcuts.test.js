const test = require('node:test');
const assert = require('node:assert/strict');
const {terminalShortcut} = require('../terminal/web/shortcuts');
const key = (code, extra = {}) => ({type: 'keydown', code, ...extra});
test('Ctrl+C copies a selection and otherwise remains SIGINT', () => {
  assert.equal(terminalShortcut(key('KeyC', {ctrlKey: true}), true), 'copy');
  assert.equal(terminalShortcut(key('KeyC', {ctrlKey: true}), false), null);
  assert.equal(terminalShortcut(key('KeyC', {metaKey: true}), true), 'copy');
});
test('paste shortcuts do not submit and dictation keeps its chord', () => {
  assert.equal(terminalShortcut(key('KeyV', {ctrlKey: true}), false), 'paste');
  assert.equal(terminalShortcut(key('KeyV', {metaKey: true}), false), 'paste');
  assert.equal(terminalShortcut(key('KeyV', {ctrlKey: true, altKey: true}), false), 'voice');
  assert.equal(terminalShortcut(key('KeyV', {altKey: true}), false), null);
  assert.equal(terminalShortcut({...key('KeyC', {ctrlKey: true}), type: 'keyup'}, true), null);
});

'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const textTokens = require('../terminal/web/text-tokens');
const pick = text => textTokens(text).map(t => [t.kind, text.slice(t.start, t.end)]);
test('colours links, paths and document names without swallowing punctuation', () => {
  assert.deepEqual(pick('Veja https://github.com/ricdanyalgil/VozTTY/releases/tag/v0.2.7.'), [['url', 'https://github.com/ricdanyalgil/VozTTY/releases/tag/v0.2.7']]);
  assert.deepEqual(pick('em ~/Softwares/maskid/api/app, e (./build.sh)'), [['path', '~/Softwares/maskid/api/app'], ['path', './build.sh']]);
  assert.deepEqual(pick('/Users/r/Downloads/Datasheet\\ -\\ VIP\\ 7200.pdf aberto'), [['path', '/Users/r/Downloads/Datasheet\\ -\\ VIP\\ 7200.pdf']]);
  assert.deepEqual(pick('O relatório.pdf e a Câmera_térmica.docx estão prontos.'), [['file', 'relatório.pdf'], ['file', 'Câmera_térmica.docx']]);
  assert.deepEqual(pick('com o teste em test/drop-paths.test.js.'), [['file', 'test/drop-paths.test.js']]);
});
test('leaves prose, versions, fractions and shell prompts alone', () => {
  assert.deepEqual(pick('São 3/4 das câmeras, versão 0.2.7, e/ou depois. user@Mac % ls'), []);
  assert.deepEqual(pick(''), []);
});
test('recognises shell variables and assignments while preserving URLs and paths', () => {
  assert.deepEqual(pick('export PROJECT=boterm echo $HOME ${USER}'), [['variable', 'PROJECT'], ['variable', '$HOME'], ['variable', '${USER}']]);
  assert.deepEqual(pick('https://example.com/?name=value /tmp/$HOME/file.txt'), [['url', 'https://example.com/?name=value'], ['path', '/tmp/$HOME/file.txt']]);
});
test('colours commands, code files, failures, success and unified diffs', () => {
  assert.deepEqual(pick('npm test'), [['command', 'npm']]);
  assert.deepEqual(pick('Read VerifierContext.kt application.properties'), [['command', 'Read'], ['file', 'VerifierContext.kt'], ['file', 'application.properties']]);
  assert.deepEqual(pick('BUILD FAILED · tests PASSED · WARNING'), [['error', 'FAILED'], ['success', 'PASSED'], ['warning', 'WARNING']]);
  assert.deepEqual(pick('+const value = 1;'), [['added', '+const value = 1;']]);
  assert.deepEqual(pick('  16 - old value'), [['removed', '  16 - old value']]);
  assert.deepEqual(pick('- regular prose'), []);
  assert.deepEqual(pick('+ Show details'), []);
});

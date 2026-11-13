'use strict';
function terminalShortcut(event, selected) {
  if (event.type !== 'keydown') return null;
  if (event.ctrlKey && event.altKey && event.code === 'KeyV') return 'voice';
  if (event.altKey) return null;
  if ((event.metaKey || event.ctrlKey) && event.code === 'KeyC' && selected) return 'copy';
  if ((event.metaKey || event.ctrlKey) && event.code === 'KeyV') return 'paste';
  if (event.metaKey && event.code === 'KeyA') return 'selectAll';
  if (event.metaKey && event.code === 'KeyT') return 'newSession';
  return null;
}
if (typeof module !== 'undefined') module.exports = {terminalShortcut};

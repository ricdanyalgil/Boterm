'use strict';
function terminalAttention(text) {
  let lines = text.trimEnd().split('\n');
  const idle = lines.findLastIndex(line => /^\s*(?:❯\s*|›\s*Ask Codex to do anything|>\s*Auto mode:.*|(?:\([^)]*\)\s*)?\S+@\S+.*[$%#]\s*|[$%#]\s*)$/i.test(line));
  if (idle >= 0) lines = lines.slice(idle + 1);
  const recent = lines.slice(-24).join('\n');
  const choices = lines.slice(-14).join('\n');
  // shortcut: recognizes explicit CLI prompts only, extend patterns when a client changes its menus.
  if (/(?:^|\n)\s*(?:enter |type |digite |informe |introduza )?[^\n]{0,60}(?:password|senha)\s*:\s*$/i.test(recent)) return 'Login solicitado';
  const menu = /^[ \t]*[>❯›●]?\s*(?:\d+[.)]\s*)?(?:yes\b|no\b|trust\b|sign in\b|sim\b|não\b|allow\b)/im.test(choices);
  if (menu && /how would you like to authenticate|sign in|como deseja (?:entrar|autenticar)/i.test(recent)) return 'Login solicitado';
  if (menu && /allow access|run this command|trust (?:this|the|these)|do you trust|do you want to proceed|would you like to run|enter to confirm|permitir acesso|deseja (?:continuar|executar)/i.test(recent)) return 'Confirmação solicitada';
  if (/(?:^|\n)\s*(?:enter|type|digite|informe|introduza|select|choose|selecione)\b[^\n]{0,120}[:?]\s*$/i.test(recent)) return 'Entrada solicitada';
  return '';
}
if (typeof module !== 'undefined') module.exports = {terminalAttention};

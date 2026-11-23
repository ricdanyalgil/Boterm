'use strict';
let term, fit;
const send = body => window.webkit.messageHandlers.terminal.postMessage(body);
const voicePanel = document.getElementById('voice-panel');
const voiceStatus = document.getElementById('voice-status');
const voiceHint = document.getElementById('voice-hint');
const voiceTime = document.getElementById('voice-time');
const pauseButton = document.getElementById('voice-pause');
const stopButton = document.getElementById('voice-stop');
const voiceRibbons = [...document.querySelectorAll('.voice-ribbon')];
// The meter arrives at 10 Hz; the drawn level rises fast and falls slowly, like a voice meter.
let voiceTarget = 0, voiceLevel = 0, lastMeter = 0, waveFrame;
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
function drawVoiceWave(now = performance.now()) {
  // Meter silence is not voice: without a fresh reading the ribbons settle to the baseline.
  const target = now - lastMeter < 400 ? voiceTarget : 0;
  voiceLevel += (target - voiceLevel) * (target > voiceLevel ? 0.45 : 0.12);
  // Reduced motion keeps the height feedback but holds the ribbons still.
  voiceWave(voiceLevel, reducedMotion.matches ? 0 : now).forEach((d, i) => voiceRibbons[i]?.setAttribute('d', d));
}
function animateVoiceWave(now) {
  drawVoiceWave(now);
  // A pause settles to a still line, then the loop sleeps until recording resumes.
  if (voicePanel.dataset.state === 'paused' && voiceLevel < 0.002) { waveFrame = undefined; return; }
  waveFrame = requestAnimationFrame(animateVoiceWave);
}
const cancelButton = document.getElementById('voice-cancel');
cancelButton.addEventListener('click', () => send({type: 'cancelVoice'}));
pauseButton.addEventListener('click', () => send({type: 'pauseVoice'}));
stopButton.addEventListener('click', () => send({type: 'voice'}));
window.voz = {
  async historySnapshot(sessionID) {
    const selected = [...sessions.values()].filter(s => !sessionID || s.id === sessionID);
    if (!selected.length) throw new Error('Session not found');
    await Promise.all(selected.map(s => new Promise(resolve => s.term.write('', resolve))));
    const projects = new Set(selected.map(s => s.workspace));
    const output = selected.map(s => `=== ${workspaces.get(s.workspace)} · ${s.name} · ${s.agent || 'Shell'} ===\nPasta: ${workspaceDirectories.get(s.workspace) || 'Diretório inicial do terminal'}\n\n${screenText(s.term, null)}`);
    const messages = messageHistory.filter(m => projects.has(m.workspace)).map(m => `${m.time} · ${m.fromName} → ${m.toName}: ${m.text}`);
    return output.join('\n\n') + '\n\n=== Mensagens da equipe ===\n' + messages.join('\n');
  },
  theme(colors) {
    const {name, ...palette} = colors;
    Object.assign(BOTERM_THEME, palette);
    for (const s of sessions.values()) { s.term.options.theme = {...BOTERM_THEME}; s.accents.refresh(); }
    document.documentElement.style.setProperty('--terminal-bg', BOTERM_THEME.background);
    document.documentElement.style.setProperty('--terminal-fg', BOTERM_THEME.foreground);
  },
  agent(id, name, state) {
    const s = sessions.get(id); if (!s) return;
    s.agent = name; s.agentState = state; renderNavigation();
  },
  create: createSession,
  world: setWorld,
  dashboard: receiveDashboard,
  event: receiveEvent,
  startDevelopment,
  recentProjects(paths) {
    const list = document.getElementById('development-recents');
    list.replaceChildren(); list.hidden = !paths.length;
    if (paths.length) {
      const label = document.createElement('p'); label.textContent = 'Projetos recentes'; list.append(label);
      for (const path of paths.slice(0, 4)) {
        const entry = button(path.split('/').pop() || path, () => window.voz.developmentDirectory(path), path);
        entry.title = path; list.append(entry);
      }
    }
  },
  developmentDirectory(path) {
    document.getElementById('development-directory').value = path;
    document.getElementById('development-error').textContent = '';
    document.getElementById('development-choose-directory').focus();
  },
  layoutProfiles(profiles, selected) {
    layoutProfiles = {};
    for (const [name, json] of Object.entries(profiles || {})) { try { layoutProfiles[name] = JSON.parse(json); } catch {} }
    renderLayoutProfiles(selected);
    if (selected) markLayoutSaved();
  },
  messengerState(state) {
    const labels = {paired: 'Telegram conectado.', pairing: `Telegram: envie ao seu bot a mensagem ${state.code || ''} para concluir.`, token: 'Telegram: token gravado, falta emparelhar.', off: 'Telegram não configurado.'};
    document.getElementById('telegram-state').textContent = labels[state.telegram] || labels.off;
    document.getElementById('telegram-setup').textContent = state.telegram === 'paired' ? 'Reconfigurar Telegram…' : 'Configurar Telegram…';
    const list = document.getElementById('permission-list'), grants = state.grants || [];
    document.getElementById('permissions-empty').hidden = grants.length > 0;
    list.replaceChildren(...grants.map(g => {
      const item = document.createElement('li'), text = document.createElement('span'), scope = document.createElement('code'), note = document.createElement('small');
      scope.textContent = g.scope; note.textContent = ` · ${g.via} · ${new Date(g.time).toLocaleString()}${g.note ? ' · ' + g.note : ''}`;
      text.append(scope, note); item.append(text, button('Revogar', () => send({type: 'revokePermission', id: g.id}), `Revogar ${g.scope}`)); return item;
    }));
  },
  developmentError(message) { document.getElementById('development-error').textContent = message; },
  newWorkspace,
  activate: activateSession,
  remove: removeSession,
  rename: renameSession,
  message: showMessage,
  copy() {
    const element = document.activeElement;
    const text = element?.matches('input') ? element.value.slice(element.selectionStart, element.selectionEnd) : (getSelection()?.toString() || term.getSelection());
    send({type: 'copy', text});
  },
  paste(text) {
    const element = document.activeElement;
    if (element?.matches('input')) element.setRangeText(text, element.selectionStart, element.selectionEnd, 'end');
    else { term.paste(text); term.focus(); }
  },
  selectAll() {
    const element = document.activeElement;
    if (element?.matches('input')) element.select(); else term.selectAll();
  },
  fit() { resizeGrace(); fitVisible(); },
  snapshot(id) { return screenText(sessions.get(id)?.term); },
  ended(id) { const s = sessions.get(id); if (s) { s.ended = true; updateAttention(s); renderNavigation(); } },
  write(base64, id = activeID) { const s = sessions.get(id); if (s) s.lastOutput = Date.now(); s?.term.write(Uint8Array.from(atob(base64), c => c.charCodeAt(0))); },
  insert(text, id = activeID, submit = false) {
    const target = sessions.get(id); if (!target) throw new Error("Session closed");
    if (/[\r\n]/.test(text) && !target.term.modes.bracketedPasteMode) throw new Error("Multiline agent input requires bracketed paste");
    target.term.paste(text); if (submit) target.term.input('\r', true);
    if (id === activeID) target.term.focus();
  },
  drop(paths, x, y) {
    if (Number.isFinite(x) && Number.isFinite(y)) {
      const pane = document.elementFromPoint(x, y)?.closest('.terminal-pane');
      const target = [...sessions.values()].find(s => s.host === pane);
      if (target) activateSession(target.id);
    }
    const text = dropPaths(paths); if (text) term.paste(text + ' '); term.focus();
  },
  focus() { term.focus(); },
  state(state, lang = 'en-US') {
    const now = performance.now();
    if (state !== 'recording') voiceTarget = 0;
    if (state === 'preparing' || state === 'idle') voiceLevel = 0;
    if (waveFrame !== undefined) cancelAnimationFrame(waveFrame);
    waveFrame = undefined;
    if (['recording', 'pausing', 'paused', 'resuming', 'stopping'].includes(state)) waveFrame = requestAnimationFrame(animateVoiceWave);
    document.body.dataset.dictating = String(state !== 'idle');
    voicePanel.hidden = state === 'idle';
    voicePanel.dataset.state = state;
    // The panel speaks the language chosen for dictation.
    const pt = lang.startsWith('pt');
    const t = (en, ptText) => pt ? ptText : en;
    document.documentElement.lang = pt ? 'pt' : 'en';
    const labels = pt ? {
      idle: '', preparing: 'Preparando o microfone…', recording: 'Gravando voz',
      pausing: 'Pausando…', paused: 'Gravação pausada', resuming: 'Retomando…', stopping: 'Transcrevendo no seu Mac…'
    } : {
      idle: '', preparing: 'Preparing microphone…', recording: 'Voice recording',
      pausing: 'Pausing…', paused: 'Recording paused', resuming: 'Resuming…', stopping: 'Transcribing on your Mac…'
    };
    voiceStatus.textContent = labels[state] ?? '';
    voiceHint.textContent = state === 'paused' ? t('Audio preserved. Continue when you are ready.', 'Áudio preservado. Continue quando quiser.')
      : state === 'stopping' ? t('Your text will appear in the prompt. Nothing is sent.', 'O texto vai aparecer no prompt. Nada é enviado.')
      : state === 'preparing' ? t('Wait for Listening before speaking.', 'Espere a gravação começar antes de falar.')
      : t('Speak freely. Text appears after Stop & insert.', 'Fale à vontade. O texto aparece depois de Parar e inserir.');
    pauseButton.textContent = state === 'paused' ? t('Continue', 'Continuar') : t('Pause', 'Pausar');
    stopButton.textContent = t('Stop & insert', 'Parar e inserir');
    cancelButton.textContent = t('Cancel', 'Cancelar');
    pauseButton.disabled = !['recording', 'paused'].includes(state);
    pauseButton.setAttribute('aria-pressed', String(state === 'paused'));
    stopButton.disabled = !['recording', 'paused'].includes(state);
    drawVoiceWave(now);
    if (state === 'preparing' || state === 'idle') voiceTime.textContent = '0:00';
  },
  meter(level, seconds) {
    if (voicePanel.dataset.state !== 'recording' || !Number.isFinite(level) || !Number.isFinite(seconds)) return;
    const value = Math.max(0, Math.min(1, level));
    voiceTarget = value; lastMeter = performance.now();
    const total = Math.max(0, Math.floor(seconds));
    voiceTime.textContent = `${Math.floor(total / 60)}:${String(total % 60).padStart(2, '0')}`;
  },
  screen() { return screenText(term); }
};
new ResizeObserver(() => { resizeGrace(); fitVisible(); }).observe(document.getElementById('stage'));
newWorkspace(window.botermInitialDirectory?.split('/').pop() || 'Projeto 1', window.botermInitialDirectory);
workspaces.set(privateWorkspace, 'Private Project');
renderNavigation();

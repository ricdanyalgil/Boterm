'use strict';
let term, fit;
const send = body => window.webkit.messageHandlers.terminal.postMessage(body);
const voicePanel = document.getElementById('voice-panel');
const voiceStatus = document.getElementById('voice-status');
const voiceHint = document.getElementById('voice-hint');
const voiceTime = document.getElementById('voice-time');
const pauseButton = document.getElementById('voice-pause');
const stopButton = document.getElementById('voice-stop');
const voiceEnvelope = document.getElementById('voice-envelope');
const pauseMarks = document.getElementById('voice-pauses');
let voiceSamples = [], voicePauses = [], waveFrame, lastWaveDraw = 0;
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
function drawVoiceWave(now = performance.now()) {
  voiceSamples = voiceSamples.filter(sample => sample.at >= now - 20000).slice(-220);
  voicePauses = voicePauses.filter(pause => (pause.end ?? now) >= now - 20000);
  const {path, bands} = voiceWave(voiceSamples, voicePauses, now);
  voiceEnvelope.setAttribute('d', path);
  // Geometry comes only from finite local timestamps, never transcript or CLI text.
  pauseMarks.innerHTML = bands.map(band => `<rect x="${band.x}" y="0" width="${Math.max(2, band.width)}" height="64"/><line x1="${band.x}" y1="0" x2="${band.x}" y2="64"/>${band.width > 48 ? `<text x="${band.x + 8}" y="14">PAUSE</text>` : ''}`).join('');
}
function animateVoiceWave(now) {
  if (now - lastWaveDraw >= 33) { drawVoiceWave(now); lastWaveDraw = now; }
  waveFrame = requestAnimationFrame(animateVoiceWave);
}
const cancelButton = document.getElementById('voice-cancel');
cancelButton.addEventListener('click', () => send({type: 'cancelVoice'}));
pauseButton.addEventListener('click', () => send({type: 'pauseVoice'}));
stopButton.addEventListener('click', () => send({type: 'voice'}));
window.voz = {
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
  startDevelopment,
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
  fit() { fitVisible(); },
  snapshot(id) { return screenText(sessions.get(id)?.term); },
  ended(id) { const s = sessions.get(id); if (s) { s.ended = true; renderNavigation(); } },
  write(base64, id = activeID) { sessions.get(id)?.term.write(Uint8Array.from(atob(base64), c => c.charCodeAt(0))); },
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
    if (state === 'preparing' || state === 'idle') { voiceSamples = []; voicePauses = []; }
    if (state === 'paused') {
      voiceSamples.push({at: now, level: 0});
      voicePauses.push({start: now});
    }
    if (state === 'recording' && voicePauses.at(-1)?.end === undefined && voicePauses.length) {
      voicePauses.at(-1).end = now;
      voiceSamples.push({at: now, level: 0});
    }
    if (waveFrame !== undefined) cancelAnimationFrame(waveFrame);
    waveFrame = undefined;
    if (['recording', 'pausing', 'paused', 'resuming'].includes(state) && !reducedMotion.matches) waveFrame = requestAnimationFrame(animateVoiceWave);
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
    voiceSamples.push({at: performance.now(), level: value});
    drawVoiceWave();
    const total = Math.max(0, Math.floor(seconds));
    voiceTime.textContent = `${Math.floor(total / 60)}:${String(total % 60).padStart(2, '0')}`;
  },
  screen() { return screenText(term); }
};
new ResizeObserver(fitVisible).observe(document.getElementById('terminal'));
newWorkspace('Projeto 1');
workspaces.set(privateWorkspace, 'Private Project');
renderNavigation();

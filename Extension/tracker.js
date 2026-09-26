// Sayfanın kendi dünyasında çalışır: medya öğelerini (DOM'a eklenmemiş olanlar dahil) takip eder.
(() => {
  if (window.__tabMixer) return;
  window.__tabMixer = true;

  const media = new Set();
  const audible = new WeakSet(); // kullanıcının sesli dinlediği öğeler
  const lastPlayed = new WeakMap();
  let wasPlaying = false;
  let lastActive = 0;

  // Sessiz önizlemeleri ve çok kısa sesleri sayma. Bir kez sesli çalan öğe,
  // sesi sonradan kısılsa da listede kalır.
  const real = (m) => audible.has(m) && (m.duration > 5 || m.duration === Infinity);
  const isPlaying = (m) => !m.paused && !m.ended && real(m);

  function track(m) {
    if (media.has(m)) return;
    media.add(m);
    for (const e of ['playing', 'pause', 'ended', 'volumechange', 'emptied']) m.addEventListener(e, report);
  }

  function current() {
    return [...media].filter(real).sort((a, b) => (lastPlayed.get(b) || 0) - (lastPlayed.get(a) || 0))[0];
  }

  function report() {
    let playing = false;
    for (const m of media) {
      if (!m.paused && !m.muted && m.volume > 0) audible.add(m);
      if (isPlaying(m)) {
        playing = true;
        lastPlayed.set(m, Date.now());
      }
    }
    if (playing || wasPlaying) lastActive = Date.now();
    wasPlaying = playing;
    if (!lastActive) return;
    const m = current();
    const volume = m ? (m.muted ? 0 : m.volume) : 1;
    window.dispatchEvent(new CustomEvent('__tabmixer_state2', { detail: JSON.stringify({ playing, lastActive, volume }) }));
  }

  const origPlay = HTMLMediaElement.prototype.play;
  HTMLMediaElement.prototype.play = function (...args) {
    track(this);
    return origPlay.apply(this, args);
  };
  document.addEventListener('play', (e) => e.target instanceof HTMLMediaElement && track(e.target), true);
  document.addEventListener('playing', (e) => e.target instanceof HTMLMediaElement && (track(e.target), report()), true);
  document.querySelectorAll('video,audio').forEach(track);
  report();

  window.addEventListener('__tabmixer_ping2', report);

  window.addEventListener('__tabmixer_cmd2', (e) => {
    const cmd = JSON.parse(e.detail);
    const list = [...media].filter(real);
    if (cmd.type === 'volume') {
      for (const m of list) {
        m.volume = Math.min(1, Math.max(0, cmd.value));
        if (cmd.value > 0 && m.muted) m.muted = false;
      }
      return;
    }
    const playing = list.filter(isPlaying);
    if (playing.length) {
      playing.forEach((m) => m.pause());
      return;
    }
    const last = current();
    if (last) last.play().catch(() => {});
  });
})();

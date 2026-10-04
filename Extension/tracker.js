// Sayfanın kendi dünyasında çalışır: medya öğelerini (DOM'a eklenmemiş olanlar dahil) takip eder.
// Eklenti güncellenince açık sekmelere yeni sürüm enjekte edilir ama eskisi sayfada çalışmaya
// devam eder. Yeni sürüm kendini duyurur, eskiler de susar. v2 bu duyuruyu bilmediği için
// olay adları 3'e çekildi; eski izleyici artık komut almaz.
(() => {
  let retired = false;
  window.dispatchEvent(new CustomEvent('__tabmixer_retire'));
  window.addEventListener('__tabmixer_retire', () => (retired = true), { once: true });

  // Öğeleri zayıf referansla tut: sayfadan atılan öğeler bellekten silinebilsin. Çalan öğeyi
  // tarayıcı zaten canlı tutar, DOM'a eklenmemiş olsa bile kaybolmaz.
  const media = new Set(); // WeakRef<HTMLMediaElement>
  const tracked = new WeakSet();
  const audible = new WeakSet(); // kullanıcının sesli dinlediği öğeler
  const lastPlayed = new WeakMap();
  let wasPlaying = false;
  let lastActive = 0;

  // Sessiz önizlemeleri ve çok kısa sesleri sayma. Bir kez sesli çalan öğe,
  // sesi sonradan kısılsa da listede kalır.
  const real = (m) => audible.has(m) && (m.duration > 5 || m.duration === Infinity);
  const isPlaying = (m) => !m.paused && !m.ended && real(m);

  // Canlı öğeler; silinmiş olanların referanslarını da temizler.
  function live() {
    const list = [];
    for (const ref of media) {
      const m = ref.deref();
      if (m) list.push(m);
      else media.delete(ref);
    }
    return list;
  }

  function track(m) {
    if (tracked.has(m)) return;
    tracked.add(m);
    media.add(new WeakRef(m));
    for (const e of ['playing', 'pause', 'ended', 'volumechange', 'emptied']) m.addEventListener(e, report);
  }

  // YouTube oynatıcısı sesi kendi hafızasında tutar ve öğeye normalizasyonla uygular.
  // Öğeye doğrudan yazılan ses bir sonraki videoda/reklamda eskiye döner, bu yüzden
  // YouTube'da sesi oynatıcının kendi API'siyle okuyup yazıyoruz.
  function ytPlayer(m) {
    const p = m.closest?.('.html5-video-player');
    return p && typeof p.setVolume === 'function' && typeof p.getVolume === 'function' ? p : null;
  }

  // setVolume sesi YouTube'un kayıtlarına yazmıyor; oynatıcı ara sıra (format değişimi,
  // reklam vb.) sesi bu kayıtlardan geri yüklüyor ve eski değer dönüyor. Kendi ayarı gibi kaydet.
  function saveYtVolume(volume, muted) {
    const now = Date.now();
    const data = JSON.stringify({ volume, muted });
    try {
      localStorage.setItem('yt-player-volume', JSON.stringify({ data, expiration: now + 30 * 86400000, creation: now }));
      sessionStorage.setItem('yt-player-volume', JSON.stringify({ data, creation: now }));
    } catch {}
  }

  function volumeOf(m) {
    const p = ytPlayer(m);
    if (p) return p.isMuted?.() ? 0 : p.getVolume() / 100;
    return m.muted ? 0 : m.volume;
  }

  function current() {
    return live().filter(real).sort((a, b) => (lastPlayed.get(b) || 0) - (lastPlayed.get(a) || 0))[0];
  }

  function report() {
    if (retired) return;
    let playing = false;
    for (const m of live()) {
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
    const volume = m ? volumeOf(m) : 1;
    window.dispatchEvent(new CustomEvent('__tabmixer_state3', { detail: JSON.stringify({ playing, lastActive, volume }) }));
  }

  // Sayfa play'in değiştirildiğini kolayca anlamasın: adı, uzunluğu ve toString'i aslı gibi.
  const origPlay = HTMLMediaElement.prototype.play;
  const play = {
    play() {
      track(this);
      return origPlay.apply(this, arguments);
    },
  }.play;
  Object.defineProperty(play, 'toString', { value: origPlay.toString.bind(origPlay), writable: true, configurable: true });
  HTMLMediaElement.prototype.play = play;
  document.addEventListener('play', (e) => e.target instanceof HTMLMediaElement && track(e.target), true);
  document.addEventListener('playing', (e) => e.target instanceof HTMLMediaElement && (track(e.target), report()), true);
  document.querySelectorAll('video,audio').forEach(track);
  report();

  window.addEventListener('__tabmixer_ping3', report);

  window.addEventListener('__tabmixer_cmd3', (e) => {
    if (retired) return;
    // Sayfa bu olayı da taklit edebilir; bozuk ya da beklenmeyen komutu yok say.
    let cmd;
    try {
      cmd = JSON.parse(typeof e.detail === 'string' ? e.detail : '');
    } catch {
      return;
    }
    if (cmd?.type !== 'toggle' && !(cmd?.type === 'volume' && Number.isFinite(cmd.value))) return;
    const list = live().filter(real);
    if (cmd.type === 'volume') {
      const value = Math.min(1, Math.max(0, cmd.value));
      const players = new Set();
      for (const m of list) {
        const p = ytPlayer(m);
        if (p) {
          players.add(p);
          continue;
        }
        m.volume = value;
        if (value > 0 && m.muted) m.muted = false;
      }
      for (const p of players) {
        p.setVolume(Math.round(value * 100));
        if (value > 0 && p.isMuted?.()) p.unMute?.();
      }
      if (players.size) saveYtVolume(Math.round(value * 100), value === 0);
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

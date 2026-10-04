// Sayfa dünyası ile eklenti arasındaki köprü.
(() => {
  const send = (msg) => {
    try {
      chrome.runtime.sendMessage(msg);
    } catch {}
  };

  // Sayfa durum olayını saniyede binlerce kez atabilir; her biri arka planda sekme taraması ve
  // uygulamada dosya yazımı demek. En fazla 100 ms'de bir gönder (sonuncusu her zaman gider),
  // aynı durumu da kısa süre içinde tekrar gönderme. Ses çubuğu sürüklenirken akıcı kalsın diye
  // bekletme değil, seyreltme.
  const INTERVAL = 100;
  let pending = null;
  let timer = 0;
  let lastSent = 0;
  let lastKey = '';

  function flush() {
    timer = 0;
    const msg = pending;
    pending = null;
    if (!msg) return;
    const key = `${msg.playing}|${msg.lastActive}|${msg.volume}`;
    const now = Date.now();
    if (key === lastKey && now - lastSent < 1000) return;
    lastKey = key;
    lastSent = now;
    send(msg);
  }

  function sendState(msg) {
    pending = msg;
    if (timer) return;
    const wait = lastSent + INTERVAL - Date.now();
    if (wait <= 0) flush();
    else timer = setTimeout(flush, wait);
  }

  // Sayfa bu olayı taklit edebilir; sadece beklenen alanları, doğru türde al.
  window.addEventListener('__tabmixer_state3', (e) => {
    let data;
    try {
      data = JSON.parse(typeof e.detail === 'string' ? e.detail : '');
    } catch {
      return;
    }
    const volume = Number(data?.volume);
    const lastActive = Number(data?.lastActive);
    sendState({
      type: 'state',
      playing: data?.playing === true,
      lastActive: Number.isFinite(lastActive) ? Math.min(Math.max(lastActive, 0), Date.now()) : 0,
      volume: Number.isFinite(volume) ? Math.min(Math.max(volume, 0), 1) : 1,
    });
  });
  window.addEventListener('pagehide', () => {
    clearTimeout(timer);
    timer = 0;
    pending = null;
    lastKey = '';
    send({ type: 'gone' });
  });
  // Geri/ileri önbelleğinden dönen sayfa yeniden yüklenmez; izleyiciden durumu tekrar iste.
  window.addEventListener('pageshow', (e) => {
    if (e.persisted) window.dispatchEvent(new CustomEvent('__tabmixer_ping3'));
  });
  chrome.runtime.onMessage.addListener((msg) => {
    if (msg.type === 'toggle' || msg.type === 'volume') {
      window.dispatchEvent(new CustomEvent('__tabmixer_cmd3', { detail: JSON.stringify(msg) }));
    }
  });
  window.dispatchEvent(new CustomEvent('__tabmixer_ping3'));
})();

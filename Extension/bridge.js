// Sayfa dünyası ile eklenti arasındaki köprü.
(() => {
  const send = (msg) => {
    try {
      chrome.runtime.sendMessage(msg);
    } catch {}
  };

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
    send({
      type: 'state',
      playing: data?.playing === true,
      lastActive: Number.isFinite(lastActive) ? Math.min(Math.max(lastActive, 0), Date.now()) : 0,
      volume: Number.isFinite(volume) ? Math.min(Math.max(volume, 0), 1) : 1,
    });
  });
  window.addEventListener('pagehide', () => send({ type: 'gone' }));
  chrome.runtime.onMessage.addListener((msg) => {
    if (msg.type === 'toggle' || msg.type === 'volume') {
      window.dispatchEvent(new CustomEvent('__tabmixer_cmd3', { detail: JSON.stringify(msg) }));
    }
  });
  window.dispatchEvent(new CustomEvent('__tabmixer_ping3'));
})();

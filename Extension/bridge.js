// Sayfa dünyası ile eklenti arasındaki köprü.
(() => {
  const send = (msg) => {
    try {
      chrome.runtime.sendMessage(msg);
    } catch {}
  };

  window.addEventListener('__tabmixer_state2', (e) => send({ type: 'state', ...JSON.parse(e.detail) }));
  window.addEventListener('pagehide', () => send({ type: 'gone' }));
  chrome.runtime.onMessage.addListener((msg) => {
    if (msg.type === 'toggle' || msg.type === 'volume') {
      window.dispatchEvent(new CustomEvent('__tabmixer_cmd2', { detail: JSON.stringify(msg) }));
    }
  });
  window.dispatchEvent(new CustomEvent('__tabmixer_ping2'));
})();

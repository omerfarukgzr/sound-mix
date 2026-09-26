const HOST = 'io.github.omerfarukgzr.tabmixer';
const frames = new Map(); // "tabId:frameId" -> { tabId, frameId, playing, lastActive, volume }
let port = null;
const icons = new Map(); // tabId -> { host, data }

// Sekmenin site ikonunu Chrome'un kendi önbelleğinden al (base64 PNG)
async function favicon(tab) {
  let host;
  try {
    host = new URL(tab.url).host;
  } catch {
    return null;
  }
  const cached = icons.get(tab.id);
  if (cached?.host === host) return cached.data;
  try {
    const url = chrome.runtime.getURL(`/_favicon/?pageUrl=${encodeURIComponent(tab.url)}&size=32`);
    const buf = new Uint8Array(await (await fetch(url)).arrayBuffer());
    let bin = '';
    for (const byte of buf) bin += String.fromCharCode(byte);
    const data = btoa(bin);
    icons.set(tab.id, { host, data });
    return data;
  } catch {
    return null;
  }
}

let retryDelay = 1000;

// Tab Mixer uygulaması kapanır, güncellenir ya da hiç kurulu değilse bağlantı kopar.
// Hatayı okuyup (Chrome'un "işlenmemiş hata" uyarısı çıkmasın) artan aralıklarla yeniden dene.
function connect() {
  port = chrome.runtime.connectNative(HOST);
  port.onMessage.addListener((msg) => {
    retryDelay = 1000;
    onCommand(msg);
  });
  port.onDisconnect.addListener(() => {
    void chrome.runtime.lastError;
    port = null;
    setTimeout(connect, retryDelay);
    retryDelay = Math.min(retryDelay * 2, 60000);
  });
  push();
}

function tabFrames(tabId) {
  return [...frames.values()].filter((f) => f.tabId === tabId);
}

function dropFrame(tabId, frameId) {
  frames.delete(`${tabId}:${frameId}`);
}

// Artık var olmayan iframe'lerin kayıtlarını temizle
async function prune() {
  const tabIds = new Set([...frames.values()].map((f) => f.tabId));
  for (const tabId of tabIds) {
    const alive = await chrome.webNavigation.getAllFrames({ tabId }).catch(() => null);
    const ids = new Set((alive ?? []).map((f) => f.frameId));
    for (const f of tabFrames(tabId)) if (!ids.has(f.frameId)) dropFrame(f.tabId, f.frameId);
  }
}

async function push() {
  if (!port) return;
  await prune();
  const byTab = new Map();
  for (const f of frames.values()) {
    const t = byTab.get(f.tabId) ?? { tabId: f.tabId, playing: false, lastActive: 0, volume: 1 };
    t.playing ||= f.playing;
    if (f.lastActive >= t.lastActive) t.volume = f.volume ?? 1;
    t.lastActive = Math.max(t.lastActive, f.lastActive);
    byTab.set(f.tabId, t);
  }
  const tabs = [];
  for (const t of byTab.values()) {
    try {
      const tab = await chrome.tabs.get(t.tabId);
      tabs.push({ ...t, title: tab.title, windowId: tab.windowId, icon: await favicon(tab) });
    } catch {
      for (const f of tabFrames(t.tabId)) frames.delete(`${f.tabId}:${f.frameId}`);
    }
  }
  try {
    port?.postMessage({ type: 'state', tabs });
  } catch {}
}

function onCommand(msg) {
  if (!msg || typeof msg !== 'object') return;
  if (msg.cmd !== 'reload' && !Number.isInteger(msg.tabId)) return;
  if (msg.cmd === 'volume' && !(typeof msg.value === 'number' && msg.value >= 0 && msg.value <= 1)) return;
  if (msg.cmd === 'toggle') {
    const fs = tabFrames(msg.tabId);
    const playing = fs.filter((f) => f.playing);
    const targets = playing.length ? playing : fs.sort((a, b) => b.lastActive - a.lastActive).slice(0, 1);
    for (const f of targets) chrome.tabs.sendMessage(f.tabId, { type: 'toggle' }, { frameId: f.frameId }).catch(() => {});
  } else if (msg.cmd === 'volume') {
    for (const f of tabFrames(msg.tabId)) {
      f.volume = msg.value;
      chrome.tabs.sendMessage(f.tabId, { type: 'volume', value: msg.value }, { frameId: f.frameId }).catch(() => {});
    }
  } else if (msg.cmd === 'reload') {
    chrome.runtime.reload();
  } else if (msg.cmd === 'focus') {
    chrome.tabs.get(msg.tabId).then((tab) => {
      chrome.tabs.update(tab.id, { active: true });
      chrome.windows.update(tab.windowId, { focused: true });
    }).catch(() => {});
  }
}

chrome.runtime.onMessage.addListener((msg, sender) => {
  // Sadece kendi içerik betiklerimizden gelen mesajlar
  if (!sender.tab || sender.id !== chrome.runtime.id) return;
  if (msg.type === 'gone') {
    dropFrame(sender.tab.id, sender.frameId);
    push();
    return;
  }
  if (msg.type !== 'state') return;
  const key = `${sender.tab.id}:${sender.frameId}`;
  frames.set(key, { tabId: sender.tab.id, frameId: sender.frameId, playing: msg.playing, lastActive: msg.lastActive, volume: msg.volume });
  push();
});

chrome.tabs.onRemoved.addListener((tabId) => {
  icons.delete(tabId);
  for (const f of tabFrames(tabId)) frames.delete(`${f.tabId}:${f.frameId}`);
  push();
});

chrome.webNavigation.onCommitted.addListener(({ tabId, frameId }) => {
  if (frameId === 0) {
    for (const f of tabFrames(tabId)) dropFrame(f.tabId, f.frameId);
  } else {
    dropFrame(tabId, frameId);
  }
  push();
});

chrome.tabs.onUpdated.addListener((tabId, info) => {
  if (info.status === 'loading' && info.url) {
    for (const f of tabFrames(tabId)) frames.delete(`${f.tabId}:${f.frameId}`);
  }
  if (info.title || info.status) push();
});

// Kurulumda zaten açık olan sekmelere de yerleş
chrome.runtime.onInstalled.addListener(async () => {
  for (const tab of await chrome.tabs.query({})) {
    if (!/^https?:/.test(tab.url ?? '') || tab.discarded) continue;
    const target = { tabId: tab.id, allFrames: true };
    chrome.scripting.executeScript({ target, files: ['bridge.js'] })
      .then(() => chrome.scripting.executeScript({ target, files: ['tracker.js'], world: 'MAIN' }))
      .catch(() => {});
  }
});

connect();

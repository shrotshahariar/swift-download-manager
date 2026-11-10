// Swift DM — background service worker
// 1. Catches Chrome downloads and hands them to the Swift DM app (aria2 JSON-RPC on localhost).
// 2. Records video/audio files each tab loads, so the popup can offer them for download.

const DEFAULTS = { enabled: true, secret: '', port: 16888, minSizeMB: 0, exclude: '', sniff: true };

async function cfg() {
  return { ...DEFAULTS, ...(await chrome.storage.local.get(Object.keys(DEFAULTS))) };
}

async function rpc(method, params = [], c) {
  c = c || (await cfg());
  const res = await fetch(`http://127.0.0.1:${c.port}/jsonrpc`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ jsonrpc: '2.0', id: 'ext', method, params: [`token:${c.secret}`, ...params] }),
    signal: AbortSignal.timeout(2500),
  });
  const j = await res.json();
  if (j.error) throw new Error(j.error.message);
  return j.result;
}

function isExcluded(url, list) {
  let host;
  try { host = new URL(url).hostname; } catch { return false; }
  return list.split(/[\s,]+/).filter(Boolean).some((d) => host === d || host.endsWith('.' + d));
}

async function sendToApp(url, { referrer, filename } = {}, c) {
  const opts = {};
  if (/^(https?|ftp):/i.test(url)) {
    const header = [`User-Agent: ${navigator.userAgent}`];
    try {
      const cookies = await chrome.cookies.getAll({ url });
      if (cookies.length) header.push('Cookie: ' + cookies.map((k) => `${k.name}=${k.value}`).join('; '));
    } catch {}
    if (referrer) header.push(`Referer: ${referrer}`);
    opts.header = header;
  }
  if (filename) opts.out = filename;
  const gid = await rpc('aria2.addUri', [[url], opts], c);
  flashBadge('↓', '#2563eb');
  return gid;
}

function flashBadge(text, color) {
  chrome.action.setBadgeBackgroundColor({ color });
  chrome.action.setBadgeText({ text });
  setTimeout(() => chrome.action.setBadgeText({ text: '' }), 2500);
}

// ---------------------------------------------------------------------------
// Download takeover
// ---------------------------------------------------------------------------

chrome.downloads.onDeterminingFilename.addListener((item, suggest) => {
  (async () => {
    const c = await cfg();
    const url = item.finalUrl || item.url;
    const skip =
      !c.enabled || !c.secret ||
      item.byExtensionId === chrome.runtime.id ||
      item.state !== 'in_progress' ||
      !/^(https?|ftp):/i.test(url) ||
      isExcluded(url, c.exclude) ||
      (c.minSizeMB > 0 && item.totalBytes > 0 && item.totalBytes < c.minSizeMB * 1048576);
    if (skip) return suggest();

    try {
      await rpc('aria2.getVersion', [], c);
    } catch {
      return suggest(); // app not running → Chrome keeps it
    }

    const filename = (item.filename || '').split(/[\\/]/).pop();
    try {
      await chrome.downloads.cancel(item.id);
      chrome.downloads.erase({ id: item.id });
      await sendToApp(url, { referrer: item.referrer, filename }, c);
    } catch (e) {
      console.warn('Swift DM: hand-off failed, falling back to Chrome', e);
      chrome.downloads.download({ url, filename: filename || undefined });
    }
    suggest();
  })();
  return true;
});

// ---------------------------------------------------------------------------
// Media sniffing: remember media responses per tab
// ---------------------------------------------------------------------------

const MEDIA_EXT = /\.(mp4|m4v|webm|mkv|mov|avi|flv|wmv|ts|m3u8|mpd|mp3|m4a|aac|ogg|oga|opus|flac|wav)(\?|#|$)/i;
const SEGMENT = /(\.m4s|\/seg[-_]?\d+|[-_]\d+\.ts)(\?|$)|init\.mp4/i;
const media = new Map(); // tabId -> Map(url -> item)

function kindOf(type, url) {
  if (/mpegurl|\.m3u8/i.test(type + url)) return 'stream';
  if (/dash\+xml|\.mpd/i.test(type + url)) return 'stream';
  if (/^video\//.test(type) || /\.(mp4|m4v|webm|mkv|mov|avi|flv|wmv|ts)(\?|#|$)/i.test(url)) return 'video';
  if (/^audio\//.test(type) || /\.(mp3|m4a|aac|ogg|oga|opus|flac|wav)(\?|#|$)/i.test(url)) return 'audio';
  return null;
}

async function saveTab(tabId) {
  const list = [...(media.get(tabId)?.values() || [])];
  try { await chrome.storage.session.set({ ['media:' + tabId]: list }); } catch {}
  chrome.action.setBadgeBackgroundColor({ tabId, color: '#6b7280' });
  chrome.action.setBadgeText({ tabId, text: list.length ? String(list.length) : '' });
}

async function loadTab(tabId) {
  if (media.has(tabId)) return media.get(tabId);
  const saved = (await chrome.storage.session.get('media:' + tabId))['media:' + tabId] || [];
  const m = new Map(saved.map((i) => [i.url, i]));
  media.set(tabId, m);
  return m;
}

chrome.webRequest.onHeadersReceived.addListener(
  (d) => {
    if (d.tabId < 0 || d.statusCode >= 400 || !/^https?:/.test(d.url)) return;
    const h = Object.fromEntries((d.responseHeaders || []).map((x) => [x.name.toLowerCase(), x.value || '']));
    const type = (h['content-type'] || '').split(';')[0].trim().toLowerCase();
    const kind = kindOf(type, d.url);
    if (!kind || (SEGMENT.test(d.url) && kind !== 'stream')) return;

    // Content-Range gives the real size of a partially requested file
    let size = Number(h['content-length']) || 0;
    const range = /\/(\d+)\s*$/.exec(h['content-range'] || '');
    if (range) size = Number(range[1]);
    if (kind !== 'stream' && size > 0 && size < 100 * 1024) return; // skip tiny clips and pings

    (async () => {
      const { sniff } = await cfg();
      if (!sniff) return;
      const m = await loadTab(d.tabId);
      if (m.has(d.url)) return;
      m.set(d.url, { url: d.url, kind, type, size, source: 'network', time: Date.now() });
      if (m.size > 200) m.delete(m.keys().next().value);
      saveTab(d.tabId);
    })();
  },
  { urls: ['<all_urls>'], types: ['media', 'xmlhttprequest', 'other', 'object'] },
  ['responseHeaders']
);

// Forget a tab's media when it navigates to a new page or closes
chrome.tabs.onUpdated.addListener((tabId, info) => {
  if (info.status === 'loading' && info.url) {
    media.set(tabId, new Map());
    saveTab(tabId);
  }
});
chrome.tabs.onRemoved.addListener((tabId) => {
  media.delete(tabId);
  chrome.storage.session.remove('media:' + tabId).catch(() => {});
});

// ---------------------------------------------------------------------------
// Context menu + messages from the popup
// ---------------------------------------------------------------------------

chrome.runtime.onInstalled.addListener(async () => {
  chrome.contextMenus.create({
    id: 'sdm',
    title: 'Download with Swift DM',
    contexts: ['link', 'image', 'video', 'audio'],
  });
  chrome.contextMenus.create({
    id: 'sdm-page',
    title: 'Download all media on this page with Swift DM…',
    contexts: ['page'],
  });
  const { secret } = await cfg();
  if (!secret) chrome.action.setBadgeText({ text: '!' });
});

chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  if (info.menuItemId === 'sdm-page') {
    chrome.action.openPopup?.().catch(() => {});
    return;
  }
  const url = info.linkUrl || info.srcUrl;
  if (!url) return;
  try {
    await sendToApp(url, { referrer: info.pageUrl || tab?.url });
  } catch {
    flashBadge('×', '#dc2626');
    chrome.downloads.download({ url });
  }
});

chrome.runtime.onMessage.addListener((msg, _sender, reply) => {
  if (msg?.type === 'add') {
    Promise.all((msg.urls || [msg.url]).map((u) => sendToApp(u, { referrer: msg.referrer })))
      .then((gids) => reply({ ok: true, gids }), (e) => reply({ ok: false, error: e.message }));
    return true;
  }
  if (msg?.type === 'media') {
    loadTab(msg.tabId).then((m) => reply([...m.values()]));
    return true;
  }
});

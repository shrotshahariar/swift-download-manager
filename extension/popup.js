const DEFAULTS = { enabled: true, secret: '', port: 16888, minSizeMB: 0, exclude: '', sniff: true };
const KEYS = ['gid', 'status', 'totalLength', 'completedLength', 'downloadSpeed', 'uploadSpeed', 'files', 'bittorrent', 'errorMessage', 'seeder'];
const $ = (id) => document.getElementById(id);
let c = { ...DEFAULTS };
let tab = null;
let view = 'tasks';
let pageItems = [];
const chosen = new Set();

// ---------- helpers ----------

function fmt(n) {
  n = Number(n) || 0;
  const u = ['B', 'KB', 'MB', 'GB', 'TB'];
  let i = 0;
  while (n >= 1024 && i < u.length - 1) { n /= 1024; i++; }
  return (i ? n.toFixed(n < 10 ? 1 : 0) : n) + ' ' + u[i];
}

function fmtTime(s) {
  if (!isFinite(s) || s <= 0) return '';
  s = Math.round(s);
  if (s < 60) return s + 's';
  if (s < 3600) return `${Math.floor(s / 60)}m ${s % 60}s`;
  return `${Math.floor(s / 3600)}h ${Math.floor((s % 3600) / 60)}m`;
}

function el(tag, cls, text) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text != null) e.textContent = text;
  return e;
}

function iconBtn(symbol, title, onClick) {
  const b = el('button', 'icon-btn', symbol);
  b.title = title;
  b.onclick = (e) => { e.stopPropagation(); onClick(); };
  return b;
}

function nameFromUrl(u) {
  try {
    if (u.startsWith('magnet:')) {
      const dn = new URL(u).searchParams.get('dn');
      return dn || 'Magnet link';
    }
    const url = new URL(u);
    const last = decodeURIComponent(url.pathname.split('/').filter(Boolean).pop() || '');
    return last || url.hostname;
  } catch { return u; }
}

// File-type badge colours, matching the app
const KINDS = [
  [/\.(mp4|m4v|mkv|webm|mov|avi|flv|wmv|ts|mpe?g)$/i, '#9e57ff'],
  [/\.(mp3|m4a|aac|flac|wav|ogg|opus|aiff)$/i, '#ff5590'],
  [/\.(jpe?g|png|gif|webp|heic|svg|bmp|tiff|avif)$/i, '#26bf80'],
  [/\.(zip|rar|7z|tar|gz|bz2|xz|tgz)$/i, '#ff9926'],
  [/\.(pdf|docx?|xlsx?|pptx?|txt|epub|csv|md)$/i, '#338cff'],
  [/\.(dmg|pkg|app|exe|msi|apk|deb|rpm|iso|img)$/i, '#6b788f'],
  [/\.(js|json|py|swift|html|css|xml|ya?ml|sh)$/i, '#f2664d'],
];

function kindBadge(name, isTorrent) {
  const b = el('div', 'kind');
  let color = '#808ca6', label = (/\.([a-z0-9]{1,4})$/i.exec(name)?.[1] || 'file');
  if (isTorrent) { color = '#1ab3bf'; label = 'BT'; }
  else for (const [re, c] of KINDS) if (re.test(name)) { color = c; break; }
  b.style.background = `linear-gradient(135deg, ${color}, ${color}b8)`;
  b.textContent = label;
  return b;
}

const STATUS = {
  active: ['Downloading', '#4085ff'], seeding: ['Seeding', '#21c47a'], waiting: ['Queued', '#ff9f1c'],
  paused: ['Paused', '#ff9f1c'], complete: ['Done', '#21c47a'], removed: ['Stopped', '#8b93a1'], error: ['Failed', '#ef4444'],
};
const BAR = {
  active: 'linear-gradient(90deg,#4085ff,#945cff)', seeding: 'linear-gradient(90deg,#21c47a,#14b8a6)',
  waiting: 'linear-gradient(90deg,#ff9f1c,#ffc733)', paused: 'linear-gradient(90deg,#ff9f1c,#ffc733)',
  error: 'linear-gradient(90deg,#ef4444,#ec4899)', removed: 'linear-gradient(90deg,#ef4444,#ec4899)',
};

function pill(key) {
  const [text, color] = STATUS[key] || [key, '#8b93a1'];
  const p = el('span', 'pill', text);
  p.style.color = color;
  p.style.background = color + '22';
  return p;
}

// Speed graph (last 60 samples)
const history = Array(60).fill(0);
function drawGraph(speed) {
  history.push(speed);
  history.shift();
  const peak = Math.max(...history, 64 * 1024);
  const pts = history.map((v, i) => [(i / (history.length - 1)) * 100, 38 - (v / peak) * 34]);
  let d = `M${pts[0][0]},${pts[0][1]}`;
  for (let i = 1; i < pts.length; i++) {
    const [ax, ay] = pts[i - 1], [bx, by] = pts[i];
    d += ` Q${ax},${ay} ${(ax + bx) / 2},${(ay + by) / 2}`;
  }
  d += ` L${pts[pts.length - 1][0]},${pts[pts.length - 1][1]}`;
  $('graphLine').setAttribute('d', d);
  $('graphFill').setAttribute('d', d + ' L100,40 L0,40 Z');
}

async function rpc(method, params = []) {
  const res = await fetch(`http://127.0.0.1:${c.port}/jsonrpc`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ jsonrpc: '2.0', id: 'p', method, params: [`token:${c.secret}`, ...params] }),
    signal: AbortSignal.timeout(2000),
  });
  const j = await res.json();
  if (j.error) throw new Error(j.error.message);
  return j.result;
}

/** Opens a swiftdm:// link, which the app handles (reveal in Finder, open, show window). */
function appLink(path) {
  const url = `swiftdm://${path}`;
  if (tab?.id && /^https?:/.test(tab.url || '')) chrome.tabs.update(tab.id, { url });
  else chrome.tabs.create({ url });
}

function setStatus(kind, text) {
  $('status').querySelector('.dot').className = 'dot ' + kind;
  $('statusText').textContent = text;
}

// ---------- Downloads view ----------

function taskName(t) {
  const bt = t.bittorrent?.info?.name;
  if (bt) return bt;
  const p = t.files?.[0]?.path || '';
  if (p.startsWith('[METADATA]')) return 'Fetching torrent info…';
  if (p) return p.split('/').pop();
  return nameFromUrl(t.files?.[0]?.uris?.[0]?.uri || '') || 'Starting…';
}

function taskMeta(t) {
  const total = Number(t.totalLength), done = Number(t.completedLength), speed = Number(t.downloadSpeed);
  const pct = total ? Math.floor((done / total) * 100) + '%' : '';
  const size = total ? `${fmt(done)} of ${fmt(total)}` : fmt(done);
  // Returns [left, right] text for the card's bottom line
  switch (t.status) {
    case 'active':
      if (t.seeder === 'true') return [fmt(total), `↑ ${fmt(t.uploadSpeed)}/s`];
      return [size, [`↓ ${fmt(speed)}/s`, total && speed ? fmtTime((total - done) / speed) + ' left' : ''].filter(Boolean).join(' · ')];
    case 'waiting': case 'paused': case 'removed': return [size, pct];
    case 'error': return [t.errorMessage || 'Failed', ''];
    default: return [fmt(total), ''];
  }
}

async function act(fn) {
  try { await fn(); } catch (e) { $('addMsg').className = 'msg err'; $('addMsg').textContent = e.message; }
  refreshTasks();
}

function taskRow(t) {
  const row = el('div', 'card ' + t.status);
  const total = Number(t.totalLength), done = Number(t.completedLength);
  const name = taskName(t);
  const key = t.status === 'active' && t.seeder === 'true' ? 'seeding' : t.status;
  row.append(kindBadge(name, !!t.bittorrent));

  const body = el('div', 'body');
  const line1 = el('div', 'line1');
  const n = el('div', 'n', name);
  n.title = name;
  line1.append(n, pill(key));
  body.append(line1);
  if (t.status !== 'complete') {
    const bar = el('div', 'bar');
    const fill = el('div');
    fill.style.width = (total ? (done / total) * 100 : 0).toFixed(1) + '%';
    fill.style.background = BAR[key] || BAR.active;
    bar.append(fill);
    body.append(bar);
  }
  const [left, right] = taskMeta(t);
  const meta = el('div', 'm');
  meta.append(el('span', '', left), el('span', '', right));
  meta.title = `${left}  ${right}`;
  body.append(meta);
  row.append(body);

  const acts = el('div', 'acts');
  const live = ['active', 'waiting', 'paused'].includes(t.status);
  if (t.status === 'active' || t.status === 'waiting') acts.append(iconBtn('⏸', 'Pause', () => act(() => rpc('aria2.forcePause', [t.gid]))));
  if (t.status === 'paused') acts.append(iconBtn('▶', 'Resume', () => act(() => rpc('aria2.unpause', [t.gid]))));
  if (t.status === 'complete') {
    acts.append(iconBtn('↗', 'Open file', () => appLink(`open?gid=${t.gid}`)));
    acts.append(iconBtn('🔍', 'Show in Finder', () => appLink(`reveal?gid=${t.gid}`)));
  }
  acts.append(iconBtn('✕', live ? 'Cancel' : 'Remove from list', () => act(async () => {
    if (live) { await rpc('aria2.forceRemove', [t.gid]); await new Promise((r) => setTimeout(r, 300)); }
    await rpc('aria2.removeDownloadResult', [t.gid]).catch(() => {});
  })));
  row.append(acts);
  return row;
}

async function refreshTasks() {
  $('setup').hidden = !!c.secret;
  if (!c.secret) { setStatus('err', 'Not connected'); $('tasks').replaceChildren(); return; }
  try {
    const [active, waiting, stopped, stat] = await Promise.all([
      rpc('aria2.tellActive', [KEYS]),
      rpc('aria2.tellWaiting', [0, 50, KEYS]),
      rpc('aria2.tellStopped', [0, 8, KEYS]),
      rpc('aria2.getGlobalStat'),
    ]);
    const speed = Number(stat.downloadSpeed);
    setStatus('ok', 'Connected');
    $('speed').textContent = `${fmt(speed)}/s`;
    $('speedSub').textContent = `↑ ${fmt(stat.uploadSpeed)}/s`;
    $('nActive').textContent = stat.numActive;
    $('nQueued').textContent = stat.numWaiting;
    $('nDone').textContent = stopped.filter((t) => t.status === 'complete').length;
    drawGraph(speed);
    if (view !== 'tasks') return;

    const box = $('tasks');
    const live = [...active, ...waiting];
    const recent = [...stopped].reverse();
    const parts = [];
    if (live.length) parts.push(el('div', 'section-title', `In progress (${live.length})`), ...live.map(taskRow));
    if (recent.length) {
      const title = el('div', 'section-title', 'Recent');
      const clear = el('button', 'link', 'Clear');
      clear.onclick = () => act(() => rpc('aria2.purgeDownloadResult'));
      title.append(clear);
      parts.push(title, ...recent.map(taskRow));
    }
    if (!parts.length) {
      const e = el('div', 'empty');
      e.append(el('span', 'big', '⬇'), 'No downloads yet. Paste a link above or download something in Chrome.');
      parts.push(e);
    }
    box.replaceChildren(...parts);
  } catch (e) {
    setStatus('err', /unauthorized/i.test(e.message) ? 'Wrong key' : 'App not running');
    if (view === 'tasks') $('tasks').replaceChildren(el('div', 'empty', /unauthorized/i.test(e.message)
      ? 'The key doesn’t match. Copy it again from Swift DM → Settings → Browser.'
      : 'Swift DM isn’t running. Open it and this will connect automatically.'));
  }
}

// ---------- This page view ----------

/** Runs inside the web page: collects media elements and downloadable links. */
function scanPage() {
  const out = [];
  const seen = new Set();
  const FILE = /\.(zip|rar|7z|tar|gz|bz2|xz|dmg|pkg|iso|exe|msi|apk|pdf|epub|mobi|docx?|xlsx?|pptx?|csv|mp4|m4v|mkv|webm|mov|avi|mp3|m4a|flac|wav|ogg|torrent|img|bin|deb|rpm|appimage)(\?|#|$)/i;
  const add = (url, kind, extra = {}) => {
    if (!url || seen.has(url) || url.startsWith('blob:') || url.startsWith('data:')) return;
    if (!/^(https?|ftp|magnet):/i.test(url)) return;
    seen.add(url);
    out.push({ url, kind, ...extra });
  };
  document.querySelectorAll('video, audio').forEach((m) => {
    const kind = m.tagName === 'VIDEO' ? 'video' : 'audio';
    add(m.currentSrc || m.src, kind);
    m.querySelectorAll('source').forEach((s) => add(s.src, kind));
  });
  document.querySelectorAll('img').forEach((img) => {
    if (img.naturalWidth >= 160 && img.naturalHeight >= 160) {
      add(img.currentSrc || img.src, 'image', { w: img.naturalWidth, h: img.naturalHeight });
    }
  });
  document.querySelectorAll('a[href]').forEach((a) => {
    const href = a.href;
    if (href.startsWith('magnet:')) add(href, 'magnet', { label: a.textContent.trim().slice(0, 80) });
    else if (FILE.test(href) || a.hasAttribute('download')) add(href, 'file', { label: a.textContent.trim().slice(0, 80) });
  });
  return out;
}

const GROUPS = [
  ['video', 'Videos'], ['audio', 'Audio'], ['file', 'Files'], ['magnet', 'Magnet links'], ['image', 'Images'], ['stream', 'Streams'],
];

async function loadPage() {
  pageItems = [];
  if (!tab?.id || !/^https?:/.test(tab.url || '')) {
    $('pageList').replaceChildren(el('div', 'empty', 'Open a web page to find its videos, audio, images and files.'));
    updateSelection();
    return;
  }
  const [sniffed, scanned] = await Promise.all([
    chrome.runtime.sendMessage({ type: 'media', tabId: tab.id }).catch(() => []),
    chrome.scripting.executeScript({ target: { tabId: tab.id, allFrames: true }, func: scanPage })
      .then((res) => res.flatMap((r) => r.result || []))
      .catch(() => []),
  ]);
  const byUrl = new Map();
  for (const i of [...(sniffed || []), ...scanned]) {
    const prev = byUrl.get(i.url);
    byUrl.set(i.url, { ...i, ...prev, size: prev?.size || i.size });
  }
  pageItems = [...byUrl.values()];
  renderPage();
}

function renderPage() {
  const n = pageItems.filter((i) => i.kind !== 'image').length;
  $('pageCount').textContent = pageItems.length ? `(${n || pageItems.length})` : '';
  if (view !== 'page') return;
  if (!pageItems.length) {
    $('pageList').replaceChildren(el('div', 'empty', 'Nothing found yet. Start playing a video, then open this again.'));
    updateSelection();
    return;
  }
  const parts = [];
  for (const [kind, title] of GROUPS) {
    const items = pageItems.filter((i) => i.kind === kind);
    if (!items.length) continue;
    const head = el('div', 'section-title', `${title} (${items.length})`);
    if (kind !== 'stream') {
      const all = el('button', 'link', 'Select all');
      all.onclick = () => {
        const every = items.every((i) => chosen.has(i.url));
        items.forEach((i) => (every ? chosen.delete(i.url) : chosen.add(i.url)));
        renderPage();
      };
      head.append(all);
    }
    parts.push(head);
    for (const i of items) parts.push(mediaRow(i));
    if (kind === 'stream') {
      parts.push(el('div', 'hint', 'Streaming playlists (HLS/DASH) are made of many small pieces. Swift DM can’t join them into one video yet.'));
    }
  }
  $('pageList').replaceChildren(...parts);
  updateSelection();
}

function mediaRow(i) {
  const disabled = i.kind === 'stream';
  const row = el('label', 'media' + (disabled ? ' disabled' : ''));
  if (i.kind === 'image') {
    const img = el('img', 'thumb');
    img.src = i.url;
    img.loading = 'lazy';
    row.append(img);
  } else {
    const box = el('input');
    box.type = 'checkbox';
    box.disabled = disabled;
    box.checked = chosen.has(i.url);
    box.onchange = () => { box.checked ? chosen.add(i.url) : chosen.delete(i.url); updateSelection(); };
    row.append(box);
  }
  const info = el('div');
  const name = el('div', 'n', i.label || nameFromUrl(i.url));
  name.title = i.url;
  const details = [i.size ? fmt(i.size) : '', i.w ? `${i.w}×${i.h}` : '', (i.type || '').replace(/^(video|audio)\//, ''), new URL(i.url).hostname]
    .filter(Boolean).join(' · ');
  info.append(name, el('div', 's', details));
  row.append(info);
  if (i.kind === 'image') {
    const pick = el('input');
    pick.type = 'checkbox';
    pick.checked = chosen.has(i.url);
    pick.onchange = () => { pick.checked ? chosen.add(i.url) : chosen.delete(i.url); updateSelection(); };
    row.append(pick);
  } else if (!disabled) {
    row.append(iconBtn('↓', 'Download now', () => send([i.url])));
  } else {
    row.append(iconBtn('⧉', 'Copy link', () => navigator.clipboard.writeText(i.url)));
  }
  return row;
}

function updateSelection() {
  const count = [...chosen].filter((u) => pageItems.some((i) => i.url === u)).length;
  $('downloadSelected').disabled = !count;
  $('downloadSelected').textContent = count ? `Download ${count}` : 'Download';
}

async function send(urls) {
  const r = await chrome.runtime.sendMessage({ type: 'add', urls, referrer: tab?.url });
  const msg = view === 'page' ? $('pageMsg') : $('addMsg');
  msg.className = 'msg' + (r?.ok ? '' : ' err');
  msg.textContent = r?.ok ? `Sent ${urls.length} to Swift DM ✓` : `Couldn’t send: ${r?.error || 'app not running'}`;
  return r?.ok;
}

// ---------- settings ----------

async function save(patch) {
  Object.assign(c, patch);
  await chrome.storage.local.set(patch);
  if ('secret' in patch) chrome.action.setBadgeText({ text: patch.secret ? '' : '!' });
  refreshTasks();
}

// ---------- startup ----------

(async () => {
  c = { ...DEFAULTS, ...(await chrome.storage.local.get(Object.keys(DEFAULTS))) };
  [tab] = await chrome.tabs.query({ active: true, currentWindow: true });

  for (const k of ['enabled', 'sniff']) {
    $(k).checked = c[k];
    $(k).onchange = (e) => save({ [k]: e.target.checked });
  }
  $('secret').value = c.secret;
  $('port').value = c.port;
  $('minSizeMB').value = c.minSizeMB;
  $('exclude').value = c.exclude;
  $('secret').oninput = (e) => save({ secret: e.target.value.trim() });
  $('keyQuick').oninput = (e) => { $('secret').value = e.target.value.trim(); save({ secret: e.target.value.trim() }); };
  $('port').onchange = (e) => save({ port: Number(e.target.value) || DEFAULTS.port });
  $('minSizeMB').onchange = (e) => save({ minSizeMB: Math.max(0, Number(e.target.value) || 0) });
  $('exclude').onchange = (e) => save({ exclude: e.target.value });

  document.querySelectorAll('nav button').forEach((b) => (b.onclick = () => {
    view = b.dataset.view;
    document.querySelectorAll('nav button').forEach((x) => x.classList.toggle('active', x === b));
    document.querySelectorAll('.view').forEach((v) => (v.hidden = v.id !== 'view-' + view));
    if (view === 'page') loadPage();
    if (view === 'tasks') refreshTasks();
  }));

  $('openApp').onclick = () => appLink('show');

  $('addForm').onsubmit = async (e) => {
    e.preventDefault();
    const urls = $('url').value.split(/\s+/).filter(Boolean);
    const bad = urls.filter((u) => !/^(https?|ftp|magnet):/i.test(u));
    if (!urls.length || bad.length) {
      $('addMsg').className = 'msg err';
      $('addMsg').textContent = 'Enter http(s), ftp or magnet links.';
      return;
    }
    if (await send(urls)) $('url').value = '';
    refreshTasks();
  };

  $('downloadSelected').onclick = async () => {
    const urls = [...chosen].filter((u) => pageItems.some((i) => i.url === u));
    if (await send(urls)) { chosen.clear(); renderPage(); }
  };

  refreshTasks();
  loadPage();  // fills the "This page" count in the background
  setInterval(refreshTasks, 1000);
})();

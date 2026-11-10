// ==UserScript==
// @name         Video Downloader - YouTube button
// @namespace    local.ytdl
// @version      4.6.1
// @homepageURL  https://github.com/sleeeeeeeeeeeeeep-cmyl/VideoDownloader
// @supportURL   https://github.com/sleeeeeeeeeeeeeep-cmyl/VideoDownloader/issues
// @updateURL    https://raw.githubusercontent.com/sleeeeeeeeeeeeeep-cmyl/VideoDownloader/main/VideoDownloader.user.js
// @downloadURL  https://raw.githubusercontent.com/sleeeeeeeeeeeeeep-cmyl/VideoDownloader/main/VideoDownloader.user.js
// @description  Adds a Download button under YouTube videos (also Shorts, Live and YouTube Music) that sends the video to the Video Downloader app on this computer (Windows or Linux). Video, phone, best quality, editor-friendly, audio and clips.
// @match        https://www.youtube.com/*
// @match        https://music.youtube.com/*
// @grant        none
// @run-at       document-idle
// @noframes
// ==/UserScript==
(function () {
  'use strict';

  // ---------- settings ----------
  const SHORTCUT_KEY = 'D';          // Shift+D = download with your ✓ option
  const CLIP_KEY = 'C';              // Shift+C = open the clip panel
  const DEFAULT_CLIP_SECONDS = 30;
  const MODES = [                    // keys must match VideoDownloader.ps1 and video-downloader.py
    { key: 'video', label: 'Video',            hint: 'small file · for this PC' },
    { key: 'phone', label: 'Phone',            hint: 'H.264 · plays on any phone' },
    { key: 'best',  label: 'Best quality',     hint: 'highest quality · big file' },
    { key: 'edit',  label: 'Editor-friendly',  hint: '1080p H.264 · opens anywhere' },
    { key: 'audio', label: 'Audio only',       hint: 'with cover art' },
  ];

  const ID = 'ytdl-local';
  const MENU = ID + '-menu';     // the dropdown lives directly in <body> so YouTube's layout can't clip or hide it
  const STORE_KEY = 'ytdl-last-mode';
  let lastSent = 0;

  // ---------- helpers ----------
  const $ = (sel, root = document) => root.querySelector(sel);
  const modeInfo = (k) => MODES.find((m) => m.key === k) || MODES[0];

  function getMode() {
    try { const m = localStorage.getItem(STORE_KEY); return MODES.some((x) => x.key === m) ? m : 'video'; }
    catch { return 'video'; }
  }
  function setMode(m) { try { localStorage.setItem(STORE_KEY, m); } catch { /* storage blocked */ } }

  function videoId() {
    const u = new URL(location.href);
    let id = null;
    if (u.pathname === '/watch') id = u.searchParams.get('v');
    else {
      const m = u.pathname.match(/^\/(?:shorts|live)\/([A-Za-z0-9_-]{11})/);
      if (m) id = m[1];
    }
    return id && /^[A-Za-z0-9_-]{11}$/.test(id) ? id : null;
  }

  function player() {
    return $('#movie_player video') || $('ytd-reel-video-renderer[is-active] video') || $('video');
  }

  // "1:05" / "1:02:03" / "75" -> seconds (null if invalid)
  function toSeconds(t) {
    t = String(t).trim();
    if (/^\d+(\.\d+)?$/.test(t)) return Math.floor(+t);
    const m = t.match(/^(?:(\d+):)?(\d{1,2}):(\d{1,2})$/);
    if (!m) return null;
    return (+(m[1] || 0)) * 3600 + (+m[2]) * 60 + (+m[3]);
  }
  function clock(s) {
    s = Math.max(0, Math.floor(s));
    const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60;
    const pad = (n) => String(n).padStart(2, '0');
    return h ? `${h}:${pad(m)}:${pad(sec)}` : `${m}:${pad(sec)}`;
  }

  // DOM without innerHTML (YouTube enforces Trusted Types)
  function el(tag, props = {}, children = []) {
    const n = document.createElement(tag);
    for (const [k, v] of Object.entries(props)) {
      if (k === 'class') n.className = v;
      else if (k.startsWith('on')) n.addEventListener(k.slice(2), v);
      else if (k in n) n[k] = v;
      else n.setAttribute(k, v);
    }
    for (const c of children) n.append(c);
    return n;
  }
  function downloadIcon() {
    const ns = 'http://www.w3.org/2000/svg';
    const svg = document.createElementNS(ns, 'svg');
    svg.setAttribute('viewBox', '0 0 24 24'); svg.setAttribute('width', '20'); svg.setAttribute('height', '20');
    svg.setAttribute('aria-hidden', 'true');
    const p = document.createElementNS(ns, 'path');
    p.setAttribute('d', 'M12 3v10.17l3.59-3.58L17 11l-5 5-5-5 1.41-1.41L11 13.17V3h1zM5 18h14v2H5z');
    p.setAttribute('fill', 'currentColor');
    svg.append(p);
    return svg;
  }

  // ---------- styles ----------
  function ensureStyle() {
    if (document.getElementById(ID + '-style')) return;
    const css = `
      #${ID}{display:inline-flex;position:relative;margin-left:8px;flex-shrink:0;z-index:2000;font-family:Roboto,Arial,sans-serif;white-space:nowrap;align-self:center}
      #${ID}.float{position:fixed;right:20px;bottom:20px;margin:0;z-index:9999}
      #${ID}.hidden{display:none}
      #${ID} .b{display:inline-flex;align-items:center;gap:6px;height:36px;padding:0 14px;border:0;cursor:pointer;
        font:500 14px Roboto,Arial,sans-serif;color:var(--yt-spec-text-primary,#fff);
        background:var(--yt-spec-badge-chip-background,rgba(255,255,255,.1));transition:background .15s}
      #${ID} .b:hover{background:var(--yt-spec-button-chip-background-hover,rgba(255,255,255,.2))}
      #${ID} .b:focus-visible,#${MENU} .item:focus-visible,#${MENU} input:focus-visible{outline:2px solid #3ea6ff;outline-offset:2px}
      #${ID} .main{border-radius:18px 0 0 18px}
      #${ID} .main.sent{background:#2e7d32;color:#fff}
      #${ID} .more{border-radius:0 18px 18px 0;padding:0 10px;border-left:1px solid var(--yt-spec-10-percent-layer,rgba(255,255,255,.2))}
      #${ID}.float .b{background:#cc0000;color:#fff;box-shadow:0 2px 8px rgba(0,0,0,.4)}
      #${ID}.float .b:hover{background:#e60000}
      #${ID}.float .more{border-left-color:rgba(255,255,255,.35)}
      #${MENU}{position:fixed;z-index:10001;min-width:330px;max-width:calc(100vw - 16px);max-height:calc(100vh - 16px);overflow-y:auto;
        padding:8px 0;border-radius:12px;display:none;box-sizing:border-box;font-family:Roboto,Arial,sans-serif;
        background:var(--yt-spec-menu-background,#282828);box-shadow:0 4px 32px rgba(0,0,0,.4);color:var(--yt-spec-text-primary,#fff)}
      #${MENU}.open{display:block}
      #${MENU} .item{display:flex;width:100%;align-items:center;justify-content:space-between;gap:16px;padding:10px 16px;
        border:0;background:none;cursor:pointer;text-align:left;font:400 14px Roboto,Arial,sans-serif;color:inherit}
      #${MENU} .item:hover{background:var(--yt-spec-10-percent-layer,rgba(255,255,255,.1))}
      #${MENU} .label{white-space:nowrap}
      #${MENU} .hint{color:var(--yt-spec-text-secondary,#aaa);font-size:12px;white-space:nowrap}
      #${MENU} .sep{height:1px;margin:6px 0;background:var(--yt-spec-10-percent-layer,rgba(255,255,255,.1))}
      #${MENU} .clip{display:none;padding:6px 16px 10px}
      #${MENU} .clip.open{display:block}
      #${MENU} .row{display:flex;align-items:center;gap:8px;margin:6px 0;font-size:13px}
      #${MENU} .row span{width:38px;color:var(--yt-spec-text-secondary,#aaa)}
      #${MENU} input{width:84px;height:28px;padding:0 8px;border-radius:6px;border:1px solid rgba(255,255,255,.25);
        background:rgba(0,0,0,.25);color:inherit;font:400 13px Roboto,Arial,sans-serif}
      #${MENU} input.bad{border-color:#ff4e45}
      #${MENU} .small{height:28px;padding:0 10px;border-radius:14px;border:0;cursor:pointer;font:500 12px Roboto,Arial,sans-serif;
        background:var(--yt-spec-badge-chip-background,rgba(255,255,255,.1));color:inherit}
      #${MENU} .go{width:100%;margin-top:6px;height:32px;border-radius:16px;border:0;cursor:pointer;background:#3ea6ff;color:#0f0f0f;font:500 13px Roboto,Arial,sans-serif}
      #${MENU} .len{font-size:12px;color:var(--yt-spec-text-secondary,#aaa)}
      #${MENU} .tip{padding:8px 16px 4px;font-size:12px;color:var(--yt-spec-text-secondary,#aaa)}
      #${ID}-toast{position:fixed;left:50%;bottom:32px;transform:translateX(-50%);z-index:10000;padding:10px 16px;border-radius:8px;
        background:#323232;color:#fff;font:400 14px Roboto,Arial,sans-serif;box-shadow:0 2px 8px rgba(0,0,0,.4);
        opacity:0;transition:opacity .2s;pointer-events:none;max-width:80vw}
      #${ID}-toast.show{opacity:1}`;
    document.head.append(el('style', { id: ID + '-style', textContent: css }));
  }

  // ---------- toast ----------
  let toastTimer;
  function toast(msg, ms = 3500) {
    let t = document.getElementById(ID + '-toast');
    if (!t) { t = el('div', { id: ID + '-toast', role: 'status' }); document.body.append(t); }
    t.textContent = msg;
    t.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => t.classList.remove('show'), ms);
  }

  // ---------- sending ----------
  function launch(uri, what) {
    const now = Date.now();
    if (now - lastSent < 1500) return false;           // ignore accidental double-clicks
    lastSent = now;
    location.href = uri;                               // handled by the Video Downloader app on this computer
    toast(`Sent to Video Downloader: ${what}. If your browser asks, allow it to open Video Downloader.`);
    const main = $(`#${ID} .main`);
    if (main) { main.classList.add('sent'); setTimeout(() => main.classList.remove('sent'), 1500); }
    return true;
  }

  function send(mode) {
    const id = videoId();
    if (!id) { toast('No video found on this page'); return; }
    setMode(mode);
    refresh();
    launch(`ytdl://${mode}/${id}`, modeInfo(mode).label);
  }

  function sendClip() {
    const id = videoId();
    const w = document.getElementById(ID);
    if (!id || !w) return;
    const m = menuEl();
    if (!m) return;
    const sIn = $('.cs', m), eIn = $('.ce', m);
    const s = toSeconds(sIn.value), e = toSeconds(eIn.value);
    sIn.classList.toggle('bad', s === null);
    eIn.classList.toggle('bad', e === null || (s !== null && e <= s));
    if (s === null || e === null || e <= s) { toast('Clip times: use m:ss, and the end must be after the start'); return; }
    if (e > 999999) { toast('Clips can end at most 277 hours into a video'); return; }   // the app accepts up to 6 digits
    if (launch(`ytdl://clip/${id}/${s}-${e}`, `Clip ${clock(s)} – ${clock(e)}`)) closeMenu();
  }

  // ---------- widget ----------
  const menuEl = () => document.getElementById(MENU);
  const isOpen = () => { const m = menuEl(); return !!m && m.classList.contains('open'); };

  function closeMenu() {
    const m = menuEl();
    if (!m) return;
    m.classList.remove('open');
    $('.clip', m).classList.remove('open');
  }

  // put the dropdown right under (or above) the button, kept fully on screen
  function placeMenu() {
    const m = menuEl(), w = document.getElementById(ID);
    if (!m || !w || !m.classList.contains('open')) return;
    const r = w.getBoundingClientRect();
    if (!r.width) { closeMenu(); return; }                       // button scrolled away / hidden
    const mw = m.offsetWidth, mh = m.offsetHeight, gap = 6, pad = 8;
    const left = Math.min(Math.max(pad, r.right - mw), window.innerWidth - mw - pad);
    let top = r.bottom + gap;
    if (top + mh > window.innerHeight - pad && r.top - gap - mh >= pad) top = r.top - gap - mh;   // not enough room below
    top = Math.max(pad, Math.min(top, window.innerHeight - pad - mh));                              // always fully on screen
    m.style.left = `${Math.round(left)}px`;
    m.style.top = `${Math.round(top)}px`;
  }

  function openMenu() {
    const m = menuEl();
    if (!m) return;
    refresh();
    m.classList.add('open');
    placeMenu();
  }

  function updateClipLength() {
    const m = menuEl();
    if (!m) return;
    const s = toSeconds($('.cs', m).value), e = toSeconds($('.ce', m).value);
    $('.len', m).textContent = (s !== null && e !== null && e > s) ? `Length ${clock(e - s)}` : '';
  }

  function openClip() {
    const w = menuEl();
    if (!w) return;
    const v = player();
    const t = v ? Math.floor(v.currentTime) : 0;
    const dur = v && isFinite(v.duration) ? Math.floor(v.duration) : t + DEFAULT_CLIP_SECONDS;
    $('.cs', w).value = clock(t);
    $('.ce', w).value = clock(Math.min(dur, t + DEFAULT_CLIP_SECONDS));
    for (const i of w.querySelectorAll('input')) i.classList.remove('bad');
    updateClipLength();
    $('.clip', w).classList.add('open');
    openMenu();
    $('.cs', w).focus();
  }

  function timeRow(labelText, cls) {
    const input = el('input', {
      class: cls, type: 'text', inputMode: 'numeric', placeholder: 'm:ss', spellcheck: false,
      onkeydown: (e) => { e.stopPropagation(); if (e.key === 'Enter') sendClip(); if (e.key === 'Escape') closeMenu(); },
      oninput: updateClipLength,
    });
    const now = el('button', {
      class: 'small', type: 'button', textContent: 'Now', title: 'Use the current playback time',
      onclick: () => { const v = player(); if (v) { input.value = clock(v.currentTime); updateClipLength(); } },
    });
    return el('div', { class: 'row' }, [el('span', { textContent: labelText }), input, now]);
  }

  function buildMenu() {
    const menu = el('div', { id: MENU, role: 'menu' });
    for (const m of MODES) {
      menu.append(el('button', {
        class: 'item', role: 'menuitem', type: 'button', 'data-mode': m.key,
        onclick: () => { closeMenu(); send(m.key); },
      }, [el('span', { class: 'label' }), el('span', { class: 'hint', textContent: m.hint })]));
    }
    menu.append(el('div', { class: 'sep' }));
    menu.append(el('button', {
      class: 'item', role: 'menuitem', type: 'button',
      onclick: () => { const c = $('.clip', menu); if (c.classList.contains('open')) { c.classList.remove('open'); placeMenu(); } else openClip(); },
    }, [el('span', { textContent: '✂ Clip part of this video…' }), el('span', { class: 'hint', textContent: 'Shift+C' })]));
    menu.append(el('div', { class: 'clip' }, [
      timeRow('Start', 'cs'),
      timeRow('End', 'ce'),
      el('div', { class: 'len' }),
      el('button', { class: 'go', type: 'button', textContent: 'Download clip', onclick: sendClip }),
    ]));
    menu.append(el('div', { class: 'sep' }));
    menu.append(el('button', {
      class: 'item', role: 'menuitem', type: 'button',
      onclick: () => { closeMenu(); location.href = 'ytdl://app'; toast('Opening Video Downloader…'); },
    }, [el('span', { textContent: '⬇ Open Video Downloader' }), el('span', { class: 'hint', textContent: 'progress, pause, history' })]));
    menu.append(el('button', {
      class: 'item', role: 'menuitem', type: 'button',
      onclick: () => { closeMenu(); location.href = 'ytdl://settings'; toast('Opening download settings…'); },
    }, [el('span', { textContent: '⚙ Settings…' }), el('span', { class: 'hint', textContent: 'folders, quality, file names' })]));
    menu.append(el('div', { class: 'tip', textContent: `Shift+${SHORTCUT_KEY} downloads with the ✓ option` }));
    menu.addEventListener('click', (e) => e.stopPropagation());   // clicks inside the menu don't close it
    return menu;
  }

  function buildWidget() {
    const main = el('button', {
      class: 'b main', type: 'button',
      onclick: () => send(getMode()),
    }, [downloadIcon(), el('span', { textContent: 'Download' })]);

    const more = el('button', {
      class: 'b more', type: 'button', title: 'Download options', 'aria-haspopup': 'menu', textContent: '▾',
      onclick: () => { if (isOpen()) closeMenu(); else openMenu(); },
    });

    // clicks on the buttons must not reach YouTube (or our outside-click closer)
    const w = el('div', { id: ID }, [main, more]);
    w.addEventListener('click', (e) => e.stopPropagation());
    return w;
  }

  function refresh() {
    const w = document.getElementById(ID), m = menuEl();
    if (!w || !m) return;
    const cur = getMode();
    $('.main', w).title = `Download as: ${modeInfo(cur).label} (${modeInfo(cur).hint})  ·  Shift+${SHORTCUT_KEY}`;
    for (const item of m.querySelectorAll('.item[data-mode]')) {
      const info = modeInfo(item.dataset.mode);
      $('.label', item).textContent = (info.key === cur ? '✓ ' : '\u2003') + info.label;
    }
  }

  // ---------- where the button goes ----------
  // On normal (long-form) videos it tries spots next to YouTube's own buttons. YouTube hides anything that doesn't
  // fit its button bar, so after placing it we check it's really visible; if not, it tries the next spot, and as a
  // last resort it floats bottom-right like on Shorts (always visible).
  const failedSpots = new Set();
  let spotsFor = '';

  function shownEl(sel, root) {
    for (const e of root.querySelectorAll(sel)) if (e.getClientRects().length) return e;
    return null;
  }

  function watchSpots() {
    if (location.hostname !== 'www.youtube.com' || location.pathname !== '/watch') return [];
    const md = [...document.querySelectorAll('ytd-watch-metadata')].find((e) => e.getClientRects().length) || document;
    const spots = [];
    const row = shownEl('#actions #top-level-buttons-computed', md) || shownEl('#top-level-buttons-computed', md);
    if (row) spots.push({ name: 'actions', put: (w) => row.after(w), here: (w) => w.previousElementSibling === row });
    const owner = shownEl('#owner', md);
    if (owner) spots.push({ name: 'owner', put: (w) => owner.append(w), here: (w) => w.parentElement === owner });
    const title = shownEl('#title', md);
    if (title) spots.push({ name: 'title', put: (w) => title.after(w), here: (w) => w.previousElementSibling === title });
    return spots;
  }

  // really on screen: has a size, isn't hidden, and isn't cut off by a parent that hides overflow
  function isShown(w) {
    const r = w.getBoundingClientRect();
    if (r.width < 20 || r.height < 10) return false;
    for (let p = w.parentElement; p && p !== document.body && p !== document.documentElement; p = p.parentElement) {
      const cs = getComputedStyle(p);
      if (cs.display === 'none' || cs.visibility === 'hidden' || +cs.opacity === 0) return false;
      if (cs.overflowX !== 'visible' || cs.overflowY !== 'visible') {
        const pr = p.getBoundingClientRect();
        if (r.left < pr.left - 1 || r.right > pr.right + 1 || r.top < pr.top - 1 || r.bottom > pr.bottom + 1) return false;
      }
    }
    return true;
  }

  function placeWidget(w) {
    const key = videoId() + '|' + Math.floor(Date.now() / 15000);   // give failed spots another chance every 15 s
    if (key !== spotsFor) { spotsFor = key; failedSpots.clear(); }
    const spots = watchSpots();
    const current = spots.find((sp) => sp.here(w));
    if (current && !w.classList.contains('float') && isShown(w)) return;
    if (current) failedSpots.add(current.name);
    for (const sp of spots) {
      if (failedSpots.has(sp.name)) continue;
      w.classList.remove('float');
      sp.put(w);
      if (isShown(w)) return;
      failedSpots.add(sp.name);
    }
    if (!w.classList.contains('float') || w.parentElement !== document.body) {
      w.classList.add('float');
      document.body.append(w);
    }
  }

  function update() {
    if (!document.body || !document.head) return;
    ensureStyle();
    let w = document.getElementById(ID);
    if (!videoId()) { if (w) w.remove(); closeMenu(); return; }
    if (!menuEl()) document.body.append(buildMenu());
    if (!w) { w = buildWidget(); refresh(); }

    placeWidget(w);
    // never cover a fullscreen video
    w.classList.toggle('hidden', !!document.fullscreenElement && w.classList.contains('float'));
    placeMenu();
  }

  // ---------- events ----------
  document.addEventListener('click', closeMenu);
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') { closeMenu(); return; }
    const t = e.target;
    if (t && (t.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName))) return;   // typing somewhere
    if (!e.shiftKey || e.ctrlKey || e.altKey || e.metaKey || !videoId()) return;
    const k = (e.key || '').toUpperCase();
    if (k === SHORTCUT_KEY) { e.preventDefault(); e.stopPropagation(); send(getMode()); }
    else if (k === CLIP_KEY) { e.preventDefault(); e.stopPropagation(); update(); openClip(); }
  }, true);

  window.addEventListener('yt-navigate-finish', () => { closeMenu(); update(); });   // YouTube switches pages without reloading
  window.addEventListener('yt-page-data-updated', update);
  document.addEventListener('fullscreenchange', () => { closeMenu(); update(); });
  window.addEventListener('scroll', placeMenu, { passive: true, capture: true });
  window.addEventListener('resize', placeMenu);
  setInterval(update, 1000);                                                         // re-attach if YouTube redraws the row
  update();
})();

'use strict';
(() => {
  const $ = (id) => document.getElementById(id);
  const MAX_PARALLEL = 2;
  const TYPE_LABEL = { email: 'Email', chat: 'Teams chat', transcript: 'Transcript', meeting: 'Meeting', file: 'File' };

  try {
    const t = localStorage.getItem('board-theme');
    if (t === 'light' || t === 'dark') document.documentElement.dataset.theme = t;
  } catch { /* ignore */ }

  function el(tag, attrs = {}, ...children) {
    const n = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs)) {
      if (v == null || v === false) continue;
      if (k === 'class') n.className = v;
      else if (k === 'text') n.textContent = v;
      else n.setAttribute(k, v);
    }
    for (const c of children.flat()) if (c != null) n.append(c instanceof Node ? c : document.createTextNode(String(c)));
    return n;
  }

  let job = null;
  try { job = JSON.parse(decodeURIComponent(location.hash.slice(1))); } catch { job = null; }
  const valid = job && typeof job.id === 'string' && Array.isArray(job.items) && job.items.length
    && job.items.every((x) => typeof x === 'string' && x.length && x.length <= 500) && job.items.length <= 12
    && typeof job.cap === 'string' && job.cap.length > 20;

  const cards = [];
  const results = [];

  function spinnerBody() {
    const elapsed = el('span', { text: '0:00' });
    const t0 = Date.now();
    const timer = setInterval(() => {
      const s = Math.floor((Date.now() - t0) / 1000);
      elapsed.textContent = `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
    }, 1000);
    const node = el('div', { class: 'brief-wait' }, el('div', { class: 'spinner', 'aria-hidden': 'true' }),
      el('div', {}, el('p', { class: 'wait-main', text: 'Copilot is drafting this artifact from your mail, chats and transcripts.' }),
        el('p', { class: 'muted-inline' }, 'This usually takes about one minute. ', elapsed)));
    return { node, stop: () => clearInterval(timer) };
  }

  function queuedBody() {
    return el('div', { class: 'brief-wait' }, el('p', { class: 'muted-inline', text: 'Waiting for the previous draft to finish…' }));
  }

  function labelPill(label) {
    if (!label || !label.name) return null;
    const pill = el('div', { class: 'label-pill', title: label.tooltip || '' }, el('span', { class: 'label-dot', 'aria-hidden': 'true' }), `Sources include: ${label.name}`);
    pill.style.setProperty('--label', label.color);
    return pill;
  }

  function renderDoc(d) {
    const a = d.artifact;
    const out = el('div', { class: 'doc' });
    const pill = labelPill(d.label); if (pill) out.append(pill);
    if (!a) {
      out.append(el('p', { class: 'brief-raw', text: d.rawText || 'Copilot returned no draft.' }));
      return out;
    }
    out.append(el('h2', { class: 'doc-title', text: a.title }));
    const meta = el('p', { class: 'doc-meta' });
    if (a.purpose) meta.append(el('b', { text: 'Purpose ' }), a.purpose);
    if (a.purpose && a.audience) meta.append(el('br'));
    if (a.audience) meta.append(el('b', { text: 'Audience ' }), a.audience);
    if (a.purpose || a.audience) out.append(meta);
    for (const s of a.sections) {
      out.append(el('h3', { text: s.heading }));
      if (s.text) out.append(el('p', { text: s.text }));
      if (s.bullets.length) out.append(el('ul', {}, s.bullets.map((b) => el('li', { text: b }))));
      if (s.table) {
        out.append(el('div', { class: 'doc-table-wrap' }, el('table', { class: 'doc-table' },
          el('thead', {}, el('tr', {}, s.table.columns.map((c) => el('th', { text: c })))),
          el('tbody', {}, s.table.rows.map((r) => el('tr', {}, s.table.columns.map((_, i) => el('td', { text: r[i] || '' }))))))));
      }
    }
    if (a.openQuestions.length) {
      out.append(el('h3', { class: 'doc-open', text: 'Open questions' }), el('ul', {}, a.openQuestions.map((q) => el('li', { text: q }))));
    }
    if (a.sources.length) {
      out.append(el('h3', { text: 'Sources Copilot used' }), el('ul', { class: 'src-list' }, a.sources.map((s) => el('li', {},
        el('span', { class: 'src-type', text: TYPE_LABEL[s.type] || 'Source' }),
        s.url ? el('a', { href: s.url, target: '_blank', rel: 'noopener noreferrer', text: s.title }) : el('span', { text: s.title }),
        s.date ? el('span', { class: 'src-date', text: s.date }) : null))));
    }
    return out;
  }

  function errorBody(message, signIn, retry) {
    const box = el('div', { class: 'error', role: 'alert' }, el('div', { text: message }));
    if (signIn) box.append(el('a', { class: 'btn primary', href: '/auth/login', target: '_blank', rel: 'noopener', text: 'Sign in' }));
    else { const b = el('button', { type: 'button', class: 'btn no-export', text: 'Try again' }); b.addEventListener('click', retry); box.append(b); }
    return box;
  }

  function updateProgress() {
    const done = results.filter(Boolean).length;
    const total = job.items.length;
    $('a-progress').textContent = done === total ? `${done} of ${done} drafted` : `${done} of ${total} drafted…`;
    ['a-print', 'a-word', 'a-save'].forEach((b) => { $(b).disabled = done === 0; });
    cards.forEach((c, i) => c.card.classList.toggle('not-ready', !results[i]));
    const note = $('a-excluded');
    note.hidden = done === 0 || done === total;
    note.textContent = `${done} of ${total} drafts are finished. Save and Print include only the finished ones.`;
  }

  // Every draft (first run, Try again and Regenerate) goes through one queue, so at most two run at the same time.
  const queue = [];
  let active = 0;
  function schedule(i) {
    if (cards[i].running || queue.includes(i)) return;
    cards[i].version++;
    results[i] = null;
    cards[i].regen.disabled = true;
    cards[i].body.replaceChildren(queuedBody());
    queue.push(i);
    updateProgress();
    pump();
  }
  function pump() {
    while (active < MAX_PARALLEL && queue.length) {
      const i = queue.shift();
      active++;
      cards[i].running = true;
      draft(i).finally(() => { cards[i].running = false; active--; pump(); });
    }
  }

  // Each run of a card gets a version number; only the newest run may update the card.
  async function draft(i) {
    const card = cards[i];
    const v = ++card.version;
    results[i] = null;
    updateProgress();
    card.regen.disabled = true;
    const wait = spinnerBody();
    card.body.replaceChildren(wait.node);
    try {
      const q = new URLSearchParams({ id: job.id, item: job.items[i], conv: job.conv || '', cap: job.cap || '' });
      let r;
      try { r = await fetch(`/api/artifact?${q}`, { headers: { 'X-Board': '1' }, cache: 'no-store' }); }
      catch { throw Object.assign(new Error('The board service on this computer is not running. Open the board again from the desktop shortcut.'), { code: 'offline' }); }
      const body = await r.json().catch(() => ({}));
      if (v !== card.version) return;
      if (!r.ok) throw Object.assign(new Error((body.error && body.error.message) || 'Copilot could not draft this artifact. Try again in a moment.'), { code: body.error && body.error.code });
      results[i] = body;
      card.body.replaceChildren(renderDoc(body));
    } catch (err) {
      if (v !== card.version) return;
      card.body.replaceChildren(errorBody(err.message, ['signin_required', 'signin_expired', 'consent_required'].includes(err.code), () => schedule(i)));
    } finally {
      wait.stop();
      if (v === card.version) { card.regen.disabled = false; updateProgress(); }
    }
  }

  function exportName(ext) {
    const day = /^\d{4}-\d{2}-\d{2}$/.test(job.date || '') ? job.date : new Date().toISOString().slice(0, 10);
    const name = `${job.items.length === 1 ? 'Draft' : 'Follow-up artifacts'} - ${job.subject || 'meeting'}`.replace(/[\\/:*?"<>|]+/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 90);
    return `${name} - ${day}.${ext}`;
  }

  function download(content, type, filename) {
    const a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob([content], { type }));
    a.download = filename;
    document.body.append(a);
    a.click();
    setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 1000);
  }

  function exportClone() {
    const clone = document.documentElement.cloneNode(true);
    clone.querySelectorAll('script, .no-export, link[rel="stylesheet"], link[rel="icon"], .not-ready, [hidden]').forEach((n) => n.remove());
    return clone;
  }

  async function saveHtml() {
    let css = '';
    try { css = await (await fetch('/styles.css', { cache: 'no-store' })).text(); } catch { /* default look */ }
    css = css.replace(/@font-face\s*\{[^}]*\}/g, '');
    const clone = exportClone();
    const style = document.createElement('style');
    style.textContent = css;
    clone.querySelector('head').append(style);
    download(`<!doctype html>\n${clone.outerHTML}`, 'text/html;charset=utf-8', exportName('html'));
  }

  // Word opens HTML saved as .doc; Word does not understand CSS variables, so this uses plain styles.
  const WORD_CSS = `
    body { font-family: "JetBrains Mono", Consolas, "Courier New", monospace; font-size: 10pt; color: #1b1f24; }
    h1 { font-size: 18pt; color: #166534; margin: 0 0 4pt; } h2 { font-size: 14pt; color: #166534; margin: 14pt 0 4pt; }
    h3 { font-size: 11pt; color: #166534; margin: 10pt 0 3pt; } .eyebrow, .date, .doc-meta, .src-type, .src-date, .foot { color: #5f6b7a; }
    table { border-collapse: collapse; width: 100%; margin: 4pt 0 8pt; } th, td { border: 1px solid #c8d0d9; padding: 3pt 5pt; vertical-align: top; text-align: left; }
    th { background: #edf6f0; color: #166534; } .label-pill { color: #b45309; font-weight: bold; } .panel-head h2 { font-size: 11pt; color: #5f6b7a; }
    .panel { margin-bottom: 14pt; } .doc-open { color: #b45309; }`;

  function saveWord() {
    const clone = exportClone();
    clone.removeAttribute('data-theme');
    clone.setAttribute('xmlns:o', 'urn:schemas-microsoft-com:office:office');
    clone.setAttribute('xmlns:w', 'urn:schemas-microsoft-com:office:word');
    clone.querySelectorAll('[style]').forEach((n) => n.removeAttribute('style'));
    const style = document.createElement('style');
    style.textContent = WORD_CSS;
    clone.querySelector('head').append(style);
    download(`<!doctype html>\n${clone.outerHTML}`, 'application/msword', exportName('doc'));
  }

  $('a-print').addEventListener('click', () => window.print());
  $('a-save').addEventListener('click', saveHtml);
  $('a-word').addEventListener('click', saveWord);

  if (!valid) {
    $('a-title').textContent = 'Nothing to draft';
    $('a-body').replaceChildren(el('section', { class: 'panel' }, el('div', { class: 'error', text: 'This draft link is not valid. Open a pre-meeting briefing from the board and press Draft there.' })));
    return;
  }

  document.title = `Draft · ${job.subject || 'Follow-up artifacts'}`;
  $('a-title').textContent = job.subject || 'Follow-up artifacts';
  $('a-when').textContent = job.when || '';
  job.items.forEach((item, i) => {
    const regen = el('button', { type: 'button', class: 'btn small no-export', text: 'Regenerate', disabled: 'disabled' }); // enabled after the first draft
    const body = el('div', { class: 'panel-body doc-body' }, queuedBody());
    const card = el('section', { class: 'panel artifact-card' },
      el('div', { class: 'panel-head' }, el('h2', { text: `${i + 1}. ${item}` }), regen), body);
    regen.addEventListener('click', () => schedule(i));
    cards.push({ card, body, regen, version: 0, running: false });
    $('a-body').append(card);
  });
  job.items.forEach((_, i) => schedule(i));
})();

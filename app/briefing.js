'use strict';
(() => {
  const $ = (id) => document.getElementById(id);
  const params = new URLSearchParams(location.search);
  const id = params.get('id') || '';
  let data = null;
  let timer = null;

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

  const SECTIONS = [
    ['topics', 'Topics', 'No clear topics found.'],
    ['latestContext', 'Latest context', 'No recent context found.'],
    ['talkingPoints', 'Top talking points', 'No talking points found.'],
    ['risks', 'Risks', 'No risks found.'],
    ['openDecisions', 'Open decisions', 'No open decisions found.'],
    ['questions', 'Questions to ask', 'No questions suggested.'],
    ['artifacts', 'Follow-up artifacts to prepare', 'Nothing to prepare.'],
  ];
  const TYPE_LABEL = { email: 'Email', chat: 'Teams chat', transcript: 'Transcript', meeting: 'Meeting', file: 'File' };

  function startWait() {
    const t0 = Date.now();
    clearInterval(timer);
    timer = setInterval(() => {
      const s = Math.floor((Date.now() - t0) / 1000);
      const e = $('b-elapsed');
      if (e) e.textContent = `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
    }, 1000);
  }

  function waitPanel() {
    return el('section', { class: 'panel brief-wait' },
      el('div', { class: 'spinner', 'aria-hidden': 'true' }),
      el('div', {},
        el('p', { class: 'wait-main', role: 'status', text: 'Microsoft 365 Copilot is reading your mail, Teams chats and meeting transcripts.' }),
        el('p', { class: 'muted-inline' }, 'This usually takes about one minute. ', el('span', { id: 'b-elapsed', 'aria-hidden': 'true', text: '0:00' }))));
  }

  function setButtons(on) { ['b-print', 'b-regen', 'b-save'].forEach((b) => { $(b).disabled = !on; }); }

  function section(title, items, empty, cls) {
    return el('section', { class: `panel brief-sec ${cls || ''}` },
      el('div', { class: 'panel-head' }, el('h2', { text: title }), el('span', { class: 'count', text: String(items.length) })),
      items.length
        ? el('ul', { class: 'brief-list' }, items.map((t) => el('li', { text: t })))
        : el('p', { class: 'muted', text: empty }));
  }

  function render(d) {
    const m = d.meeting;
    document.title = `Briefing · ${m.subject}`;
    $('b-title').textContent = m.subject;
    $('b-when').textContent = `${m.when} · ${m.timeZone}`;

    const facts = el('div', { class: 'brief-facts' });
    if (m.organizer) facts.append(el('span', {}, el('b', { text: 'Organizer ' }), m.organizer));
    if (m.attendees.length) facts.append(el('span', { title: m.attendees.join(', ') }, el('b', { text: 'Attendees ' }), `${m.attendees.length}`));
    if (m.location) facts.append(el('span', {}, el('b', { text: 'Where ' }), m.location));
    (m.rooms || []).forEach((r) => facts.append(el('span', { class: 'room', text: r })));
    if (m.joinUrl) facts.append(el('a', { class: 'join no-export', href: m.joinUrl, target: '_blank', rel: 'noopener noreferrer', text: 'Join' }));
    if (m.link) facts.append(el('a', { class: 'linkbtn no-export', href: m.link, target: '_blank', rel: 'noopener noreferrer', text: 'Open in Outlook' }));

    const out = [];
    const head = el('section', { class: 'panel brief-head' }, facts);
    if (d.label && d.label.name) {
      const pill = el('div', { class: 'label-pill', title: d.label.tooltip || '' },
        el('span', { class: 'label-dot', 'aria-hidden': 'true' }), `Sources include: ${d.label.name}`);
      pill.style.setProperty('--label', d.label.color);
      head.prepend(pill);
    }
    out.push(head);

    if (!d.briefing) {
      out.push(el('section', { class: 'panel brief-sec' },
        el('div', { class: 'panel-head' }, el('h2', { text: 'Briefing' })),
        el('p', { class: 'brief-raw', text: d.rawText || 'Copilot returned no answer.' })));
    } else {
      const b = d.briefing;
      if (b.summary) out.push(el('section', { class: 'panel brief-summary' }, el('p', { text: b.summary })));
      const grid = el('div', { class: 'brief-grid' });
      for (const [key, title, empty] of SECTIONS) {
        const sec = section(title, b[key] || [], empty, `sec-${key}`);
        if (key === 'artifacts' && (b.artifacts || []).length) addDraftButtons(sec, b.artifacts, d);
        grid.append(sec);
      }
      out.push(grid);
      const src = el('section', { class: 'panel brief-sec brief-sources' },
        el('div', { class: 'panel-head' }, el('h2', { text: 'Sources Copilot used' }), el('span', { class: 'count', text: String(b.sources.length) })));
      if (!b.sources.length) src.append(el('p', { class: 'muted', text: 'Copilot did not list its sources.' }));
      else {
        src.append(el('ul', { class: 'src-list' }, b.sources.map((s) => el('li', {},
          el('span', { class: 'src-type', text: TYPE_LABEL[s.type] || 'Source' }),
          s.url ? el('a', { href: s.url, target: '_blank', rel: 'noopener noreferrer', text: s.title }) : el('span', { text: s.title }),
          s.date ? el('span', { class: 'src-date', text: s.date }) : null))));
      }
      out.push(src);
    }
    $('b-body').replaceChildren(...out);
    const gen = new Intl.DateTimeFormat('en-GB', { day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' }).format(new Date(d.generatedAt));
    $('b-foot').textContent = `Generated ${gen} by Microsoft 365 Copilot from your mail, Teams chats and meeting transcripts. Nothing is stored. Check facts before you share.`;
  }

  // Follow-up artifacts: open a drafting tab that asks Copilot (same conversation) to write them.
  function openDrafts(items, d) {
    const payload = { id, conv: d.conversationId || '', cap: d.draftCap || '', subject: d.meeting.subject, when: d.meeting.when, date: d.meeting.date || '', items };
    window.open(`/artifacts#${encodeURIComponent(JSON.stringify(payload))}`, '_blank', 'noopener');
  }
  function addDraftButtons(sec, items, d) {
    const all = el('button', { type: 'button', class: 'btn primary small no-export', title: 'Let Copilot draft every artifact in this list', text: 'Draft all' });
    all.addEventListener('click', () => openDrafts(items, d));
    sec.querySelector('.panel-head').append(all);
    const list = sec.querySelector('.brief-list');
    if (list) list.classList.add('draft-list');
    sec.querySelectorAll('.brief-list li').forEach((li, i) => {
      const text = el('span', { class: 'draft-text', text: li.textContent });
      const b = el('button', { type: 'button', class: 'draft-btn no-export', title: 'Let Copilot draft this artifact', text: 'Draft' });
      b.addEventListener('click', () => openDrafts([items[i]], d));
      li.replaceChildren(text, b);
    });
  }

  function showError(message, signIn) {
    const box = el('div', { class: 'error', role: 'alert' }, el('div', { text: message }));
    if (signIn) box.append(el('a', { class: 'btn primary', href: '/auth/login', text: 'Sign in' }));
    else box.append(el('button', { type: 'button', class: 'btn', id: 'b-retry', text: 'Try again' }));
    $('b-body').replaceChildren(el('section', { class: 'panel' }, box));
    const r = $('b-retry'); if (r) r.addEventListener('click', load);
    $('b-title').textContent = 'Briefing not ready';
  }

  async function load() {
    clearInterval(timer);
    setButtons(false);
    $('b-body').replaceChildren(waitPanel());
    startWait();
    try {
      let r;
      try {
        r = await fetch(`/api/briefing?id=${encodeURIComponent(id)}`, { headers: { 'X-Board': '1' }, cache: 'no-store' });
      } catch {
        throw Object.assign(new Error('The board service on this computer is not running. Open the board again from the desktop shortcut.'), { code: 'offline' });
      }
      const body = await r.json().catch(() => ({}));
      if (!r.ok) throw Object.assign(new Error((body.error && body.error.message) || 'The briefing could not be created. Try again in a moment.'), { code: body.error && body.error.code });
      data = body;
      render(body);
      setButtons(true);
    } catch (err) {
      showError(err.message, ['signin_required', 'signin_expired', 'consent_required'].includes(err.code));
    } finally {
      clearInterval(timer);
    }
  }

  async function saveHtml() {
    if (!data) return;
    let css = '';
    try { css = await (await fetch('/styles.css', { cache: 'no-store' })).text(); } catch { /* keep default look */ }
    css = css.replace(/@font-face\s*\{[^}]*\}/g, '');
    const clone = document.documentElement.cloneNode(true);
    clone.querySelectorAll('script, .no-export, link[rel="stylesheet"], link[rel="icon"]').forEach((n) => n.remove());
    const style = document.createElement('style');
    style.textContent = css;
    clone.querySelector('head').append(style);
    if (!document.documentElement.dataset.theme) clone.removeAttribute('data-theme');
    const html = `<!doctype html>\n${clone.outerHTML}`;
    const day = /^\d{4}-\d{2}-\d{2}$/.test(data.meeting.date || '') ? data.meeting.date : new Date(data.generatedAt).toISOString().slice(0, 10);
    const name = `Briefing - ${data.meeting.subject}`.replace(/[\\/:*?"<>|]+/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 90);
    const a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob([html], { type: 'text/html;charset=utf-8' }));
    a.download = `${name} - ${day}.html`;
    document.body.append(a);
    a.click();
    setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 1000);
  }

  $('b-print').addEventListener('click', () => window.print());
  $('b-regen').addEventListener('click', load);
  $('b-save').addEventListener('click', saveHtml);

  if (!id) showError('No meeting was selected. Open the briefing from a meeting on the board.', false);
  else load();
})();

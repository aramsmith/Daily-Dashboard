'use strict';
(() => {
  const REFRESH_MS = 5 * 60 * 1000;
  const $ = (id) => document.getElementById(id);
  let busy = false;
  let lastOk = null;
  let nextRefreshAt = 0;
  let gen = 0; // raised on sign-out; answers from an older generation are ignored

  // Theme: follows Windows by default; the sun/moon button overrides it. Only this choice is remembered.
  const THEME_KEY = 'board-theme';
  const systemDark = window.matchMedia('(prefers-color-scheme: dark)');
  function savedTheme() { try { return localStorage.getItem(THEME_KEY); } catch { return null; } }
  function applyTheme() {
    const chosen = savedTheme();
    const root = document.documentElement;
    if (chosen === 'light' || chosen === 'dark') root.dataset.theme = chosen; else delete root.dataset.theme;
    const mode = chosen === 'light' || chosen === 'dark' ? chosen : (systemDark.matches ? 'dark' : 'light');
    root.dataset.mode = mode;
    const label = mode === 'dark' ? 'Switch to light mode' : 'Switch to dark mode';
    $('theme').setAttribute('aria-label', label);
    $('theme').title = label;
  }
  applyTheme();

  // Name, customers and version come from the service.
  fetch('/api/config', { headers: { 'X-Board': '1' }, cache: 'no-store' }).then((r) => r.json()).then((cfg) => {
    if (!cfg || !cfg.title) return;
    document.title = cfg.title;
    $('board-title').textContent = cfg.title;
    if (cfg.version) $('version').textContent = `Daily Board ${cfg.version}`;
    if (!cfg.customers || !cfg.customers.length) $('mail-meta').textContent = 'No customers set yet · open Settings';
  }).catch(() => {});
  systemDark.addEventListener('change', applyTheme);
  $('theme').addEventListener('click', () => {
    const next = document.documentElement.dataset.mode === 'dark' ? 'light' : 'dark';
    try { localStorage.setItem(THEME_KEY, next); } catch { /* private mode: still switches for this visit */ document.documentElement.dataset.theme = next; }
    applyTheme();
    if (!savedTheme()) { document.documentElement.dataset.theme = next; document.documentElement.dataset.mode = next; }
  });

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

  async function api(path) {
    let r;
    try {
      r = await fetch(path, { headers: { 'X-Board': '1' }, cache: 'no-store' });
    } catch {
      const e = new Error(window.BoardService ? BoardService.OFFLINE_MESSAGE : 'The board service on this computer has stopped. Open the board again from the desktop shortcut.');
      e.code = 'offline';
      throw e;
    }
    const body = await r.json().catch(() => ({}));
    if (!r.ok) {
      const e = new Error((body.error && body.error.message) || 'Something went wrong. The board will try again at the next refresh.');
      e.code = body.error && body.error.code;
      throw e;
    }
    return body;
  }

  const needsSignIn = (code) => ['signin_required', 'signin_expired', 'consent_required'].includes(code);

  function errorBox(err) {
    const box = el('div', { class: 'error', role: 'alert' }, el('div', { text: err.message }));
    if (needsSignIn(err.code)) box.append(el('a', { class: 'btn primary', href: '/auth/login', text: 'Sign in' }));
    else if (err.code === 'offline' && window.BoardService) box.append(BoardService.startButton(() => refresh()));
    return box;
  }

  function fmtTime(iso, tz, hour12) {
    const d = new Date(iso);
    const opts = { timeZone: tz, hour: '2-digit', minute: '2-digit', hour12: !!hour12 };
    const key = (x) => new Intl.DateTimeFormat('en-CA', { timeZone: tz }).format(x);
    const t = new Intl.DateTimeFormat('en-GB', opts).format(d);
    if (key(d) === key(new Date())) return t;
    if (key(d) === key(new Date(Date.now() - 864e5))) return `Yesterday ${t}`;
    return `${new Intl.DateTimeFormat('en-GB', { timeZone: tz, day: 'numeric', month: 'short' }).format(d)} ${t}`;
  }

  // Emails opened from the board count as read right away; Outlook updates the real status shortly after.
  const opened = new Set();
  let lastMail = null;
  let lastMailLoad = 0;
  const isRead = (m) => m.isRead || opened.has(m.id);
  const customerItems = (d) => (d.customers || []).flatMap((x) => x.items);

  function unreadFromPeople(d) {
    const cutoff = Date.now() - 864e5;
    const ids = new Set([...d.people, ...customerItems(d)].filter((m) => !m.automated && !m.isRead && opened.has(m.id) && Date.parse(m.received) >= cutoff).map((m) => m.id));
    return Math.max(0, d.summary.unreadPeople - ids.size);
  }

  function mailItem(m, tz, hour12) {
    const read = isRead(m);
    return el('li', { class: `item${read ? '' : ' unread'}`, 'data-id': m.id },
      el('span', { class: 'dotcol', 'aria-hidden': 'true' }, read ? null : el('span', { class: 'dot' })),
      el('div', { class: 'main' },
        el('div', { class: 'who', title: m.fromAddress, text: m.fromName }),
        el('a', { class: 'subj', href: m.link, target: '_blank', rel: 'noopener noreferrer', title: m.subject },
          read ? null : el('span', { class: 'sr', text: 'Unread: ' }), m.subject)),
      el('span', { class: 'when', text: fmtTime(m.received, tz, hour12) }));
  }

  function group(title, items, cls, tz, hour12, empty, limit, incomplete) {
    const wrap = el('div', { class: cls || null });
    wrap.append(el('div', { class: 'group-title' }, title, el('span', { class: 'count', text: `${items.length}${incomplete ? '+' : ''}` })));
    if (!items.length) { wrap.append(el('p', { class: 'muted', text: empty })); return wrap; }
    const list = el('ul', { class: 'list' }, items.slice(0, limit || items.length).map((m) => mailItem(m, tz, hour12)));
    wrap.append(list);
    if (limit && items.length > limit) {
      const btn = el('button', { type: 'button', class: 'linkbtn more', text: `Show all ${items.length}` });
      btn.addEventListener('click', () => {
        list.replaceChildren(...items.map((m) => mailItem(m, tz, hour12)));
        btn.remove();
      });
      wrap.append(btn);
    }
    return wrap;
  }

  // Only one mail load runs at a time; answers that arrive after a sign-out are ignored.
  let mailInFlight = null;
  function loadMail() {
    if (mailInFlight) return mailInFlight;
    lastMailLoad = Date.now();
    mailInFlight = loadMailNow().finally(() => { mailInFlight = null; });
    return mailInFlight;
  }

  const plus = (d) => (d.summary.countsExact === false ? '+' : '');

  async function loadMailNow() {
    const body = $('mail-body');
    const g = gen;
    try {
      const d = await api('/api/mail');
      if (g !== gen) return false;
      lastMail = d; lastMailLoad = Date.now();
      for (const m of [...d.people, ...customerItems(d), ...d.automated]) if (m.isRead) opened.delete(m.id);
      const tz = d.timeZoneIana;
      $('s-unread').textContent = unreadFromPeople(d) + plus(d);
      $('s-total').textContent = d.summary.total24 + (d.summary.total24Exact ? '' : '+');
      $('s-auto').textContent = d.summary.automated + plus(d);
      $('mail-meta').textContent = `Latest 25 since yesterday · ${d.timeZone}`;

      const frag = document.createDocumentFragment();
      frag.append(group('From people', d.people, null, tz, d.hour12, 'No mail from people since yesterday.'));

      (d.customers || []).forEach((cust, i) => {
        const color = /^[a-z]+$/.test(cust.color || '') ? cust.color : ['amber', 'blue', 'violet'][i % 3];
        const sec = group(`Related to ${cust.name} · since yesterday`, cust.items, `customer cust-${color}`, tz, d.hour12, `No ${cust.name}-related mail since yesterday.`, 10, cust.truncated);
        if (cust.truncated) sec.append(el('p', { class: 'muted', text: `There is more ${cust.name} mail than the board can read. Search Outlook for the rest.` }));
        if (cust.error) sec.append(el('p', { class: 'inline-error', text: `${cust.name} search failed: ${cust.error}` }));
        frag.append(sec);
      });

      frag.append(group('Newsletters and automated mail', d.automated, 'quiet', tz, d.hour12, 'No automated mail since yesterday.'));

      const senders = el('div', { class: 'senders' });
      senders.append(el('div', { class: 'group-title' }, 'Top automated senders since yesterday'));
      if (!d.topSenders.length) senders.append(el('p', { class: 'muted', text: 'None.' }));
      else {
        senders.append(el('table', {}, el('tbody', {}, d.topSenders.map((s) =>
          el('tr', {}, el('td', {}, s.name, ' ', el('span', { class: 'addr', text: s.address && s.address !== s.name ? `<${s.address}>` : '' })),
            el('td', { class: 'n', text: String(s.count) }))))));
      }
      frag.append(senders);
      if (d.truncated) frag.append(el('p', { class: 'muted', text: 'Only the newest 100 messages were checked.' }));
      body.replaceChildren(frag);
      return true;
    } catch (err) {
      if (g !== gen) return false;
      ['s-unread', 's-total', 's-auto'].forEach((id) => { $(id).textContent = '–'; });
      body.replaceChildren(errorBox(err));
      if (needsSignIn(err.code)) showSignIn(err.message);
      return false;
    }
  }

  function sampleDays(tz, hour12) {
    const t = (h, m) => (hour12 ? `${((h + 11) % 12) + 1}:${String(m).padStart(2, '0')} ${h < 12 ? 'am' : 'pm'}` : `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`);
    return [
      { label: 'Today', events: [{ subject: 'Sample: Team stand-up', time: `${t(9, 30)} – ${t(9, 45)}`, location: 'Microsoft Teams Meeting', response: 'accepted' }] },
      { label: 'Tomorrow', events: [{ subject: 'Sample: Architecture review', time: `${t(14, 0)} – ${t(15, 0)}`, location: '', rooms: ['Room 4.12'], response: 'tentativelyAccepted' }] },
    ];
  }

  const RESPONSES = {
    accepted: ['Accepted', 'ok'],
    organizer: ['Organizer', 'ok'],
    tentativelyAccepted: ['Tentative', 'maybe'],
    notResponded: ['No response', 'none'],
    none: ['No response', 'none'],
  };
  function responseTag(response) {
    const r = RESPONSES[response];
    return r ? el('span', { class: `resp resp-${r[1]}`, text: r[0] }) : null;
  }

  function renderDays(days, sample) {
    const wrap = el('div', { class: sample ? 'sample' : null });
    for (const day of days) {
      const d = el('div', { class: 'day' }, el('div', { class: 'group-title' }, day.label, el('span', { class: 'count', text: String(day.events.length) })));
      for (const ev of day.events) {
        const title = ev.link
          ? el('a', { class: 's', href: ev.link, target: '_blank', rel: 'noopener noreferrer', text: ev.subject })
          : el('span', { class: 's', text: ev.subject });
        d.append(el('div', { class: `ev${ev.past ? ' past' : ''}` },
          el('div', { class: 't' }, el('span', { text: ev.time }), responseTag(ev.response)),
          el('div', {}, title, ev.location ? el('div', { class: 'l', text: ev.location }) : null,
            (ev.rooms && ev.rooms.length) ? el('div', { class: 'rooms' }, ev.rooms.map((r) => el('span', { class: 'room', title: 'Meeting room', text: r }))) : null),
          ev.past ? null : el('div', { class: 'ev-actions' },
            ev.joinUrl ? el('a', { class: 'join', href: ev.joinUrl, target: '_blank', rel: 'noopener noreferrer', text: 'Join' }) : null,
            ev.id ? el('a', { class: 'brief-btn', href: `/briefing?id=${encodeURIComponent(ev.id)}`, target: '_blank', rel: 'noopener', title: 'Create a pre-meeting briefing from your mail, Teams chats and transcripts', text: 'Brief' }) : null)));
      }
      wrap.append(d);
    }
    return wrap;
  }

  async function loadCalendar() {
    const body = $('cal-body');
    const g = gen;
    try {
      const d = await api('/api/calendar');
      if (g !== gen) return false;
      $('s-meet').textContent = d.meetingsCount + (d.truncated ? '+' : '');
      $('cal-meta').textContent = `Times in ${d.timeZone}${d.timeZoneFallback ? ' (mailbox time zone unknown)' : ''}`;
      if (!d.days.length) {
        body.replaceChildren(
          el('div', { class: 'sample-note' }, el('span', { class: 'badge', text: 'Sample data' }), 'No meetings today or tomorrow. These examples disappear when real meetings appear.'),
          renderDays(sampleDays(d.timeZoneIana, d.hour12), true));
      } else {
        body.replaceChildren(renderDays(d.days, false));
        if (d.truncated) body.append(el('p', { class: 'muted', text: 'Only the first 100 events are shown.' }));
      }
      return true;
    } catch (err) {
      if (g !== gen) return false;
      $('s-meet').textContent = '–';
      body.replaceChildren(errorBox(err));
      if (needsSignIn(err.code)) showSignIn(err.message);
      return false;
    }
  }

  function showSignIn(message) {
    $('banner-text').textContent = message;
    $('banner-signin').hidden = false;
    $('banner-start').replaceChildren();
    $('banner').hidden = false;
  }
  function hideBanner() { $('banner').hidden = true; $('banner-start').replaceChildren(); }

  function setUpdated() {
    const t = new Intl.DateTimeFormat('en-GB', { hour: '2-digit', minute: '2-digit', second: '2-digit' });
    $('updated').textContent = lastOk ? `Last updated ${t.format(lastOk)}` : 'Not loaded yet';
  }

  let refreshQueued = false;
  async function refresh() {
    if (busy) { refreshQueued = true; return; }
    busy = true;
    const g = gen;
    const btn = $('refresh');
    btn.disabled = true; btn.textContent = 'Refreshing…';
    $('today').textContent = new Intl.DateTimeFormat('en-GB', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' }).format(new Date());
    try {
      const status = await api('/api/status');
      if (g !== gen) return;
      if (!status.connector || !status.signedIn) {
        showSignIn(status.message);
        $('banner-signin').hidden = !status.connector;
        const msg = el('p', { class: 'muted', text: status.connector ? 'Sign in to load this panel.' : status.message });
        $('mail-body').replaceChildren(msg.cloneNode(true));
        $('cal-body').replaceChildren(msg);
        $('signout').hidden = true;
        return;
      }
      hideBanner();
      const who = status.account && (status.account.name || status.account.username);
      $('account').textContent = `Signed in${who ? ' as ' + who : ''}. Read live from Microsoft 365; nothing is stored.`;
      $('signout').hidden = false;
      const results = await Promise.allSettled([loadMail(), loadCalendar()]);
      if (results.some((r) => r.status === 'fulfilled' && r.value)) lastOk = new Date();
    } catch (err) {
      showSignIn(err.message);
      $('banner-signin').hidden = !needsSignIn(err.code);
      if (err.code === 'offline' && window.BoardService) $('banner-start').replaceChildren(BoardService.startButton(() => refresh()));
    } finally {
      setUpdated();
      nextRefreshAt = Date.now() + REFRESH_MS;
      busy = false; btn.disabled = false; btn.textContent = 'Refresh now';
      tick();
      if (refreshQueued) { refreshQueued = false; setTimeout(refresh, 0); }
    }
  }

  function tick() {
    const cd = $('countdown');
    if (busy) { cd.textContent = 'Refreshing…'; cd.removeAttribute('data-soon'); return; }
    const left = Math.max(0, Math.ceil((nextRefreshAt - Date.now()) / 1000));
    cd.textContent = `Next refresh in ${Math.floor(left / 60)}:${String(left % 60).padStart(2, '0')}`;
    cd.toggleAttribute('data-soon', left <= 10);
    if (left === 0 && !document.hidden) refresh();
  }

  $('refresh').addEventListener('click', refresh);
  $('signout').addEventListener('click', async () => {
    gen++;
    opened.clear(); lastMail = null; lastOk = null;
    ['s-unread', 's-total', 's-auto', 's-meet'].forEach((id) => { $(id).textContent = '–'; });
    const msg = el('p', { class: 'muted', text: 'Signed out.' });
    $('mail-body').replaceChildren(msg.cloneNode(true));
    $('cal-body').replaceChildren(msg);
    $('account').textContent = 'Signed out. Nothing is stored.';
    $('signout').hidden = true;
    await fetch('/api/signout', { method: 'POST', headers: { 'X-Board': '1' } }).catch(() => {});
    refresh();
  });
  function markOpened(ev) {
    const a = ev.target.closest('a.subj');
    if (!a) return;
    const li = a.closest('li[data-id]');
    if (!li) return;
    opened.add(li.dataset.id);
    document.querySelectorAll('#mail-body li[data-id]').forEach((n) => {
      if (n.dataset.id !== li.dataset.id) return;
      n.classList.remove('unread');
      n.querySelectorAll('.dot, .sr').forEach((x) => x.remove());
    });
    if (lastMail) $('s-unread').textContent = unreadFromPeople(lastMail) + plus(lastMail);
  }
  $('mail-body').addEventListener('click', markOpened);
  $('mail-body').addEventListener('auxclick', (ev) => { if (ev.button === 1) markOpened(ev); });

  // Coming back to the board (for example after closing the email tab) rereads the Inbox.
  // 'visibilitychange' and 'focus' usually fire together, so they are merged into one check.
  let returnTimer = null;
  function onReturn() {
    clearTimeout(returnTimer);
    returnTimer = setTimeout(() => {
      if (document.hidden || busy) return;
      if (nextRefreshAt <= Date.now()) { refresh(); return; }
      if (Date.now() - lastMailLoad > 10000) loadMail();
    }, 200);
  }
  document.addEventListener('visibilitychange', onReturn);
  window.addEventListener('focus', onReturn);
  setInterval(tick, 1000);
  refresh();
})();

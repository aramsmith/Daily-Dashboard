'use strict';
(() => {
  const $ = (id) => document.getElementById(id);
  try {
    const t = localStorage.getItem('board-theme');
    if (t === 'light' || t === 'dark') document.documentElement.dataset.theme = t;
  } catch { /* ignore */ }

  const inputs = ['s-c1', 's-c2', 's-c3'].map($);
  let choices = ['amber', 'blue', 'violet', 'pink', 'cyan', 'slate'];
  const picked = ['amber', 'blue', 'violet'];
  const cap = (c) => c.charAt(0).toUpperCase() + c.slice(1);

  function paint(i) { inputs[i].className = `cust-name cust-${picked[i]}`; }

  function renderSwatches() {
    picked.forEach((_, i) => {
      $(`s-k${i + 1}`).replaceChildren(...choices.map((c) => {
        const r = document.createElement('input');
        Object.assign(r, { type: 'radio', name: `k${i + 1}`, value: c, className: `sw cust-${c}`, title: cap(c), checked: picked[i] === c });
        r.setAttribute('aria-label', cap(c));
        r.addEventListener('change', () => { picked[i] = c; paint(i); });
        return r;
      }));
      paint(i);
    });
  }
  renderSwatches();

  function showError(text) {
    $('s-error').textContent = text;
    $('s-error').hidden = !text;
  }

  fetch('/api/config', { headers: { 'X-Board': '1' }, cache: 'no-store' }).then((r) => r.json()).then((cfg) => {
    $('s-title').textContent = cfg.title || 'Daily Board';
    if (cfg.version) $('s-version').textContent = `Daily Board version ${cfg.version}`;
    $('s-name').value = cfg.userName || '';
    (cfg.customers || []).forEach((c, i) => { if (inputs[i]) inputs[i].value = c; });
    if (Array.isArray(cfg.colorChoices) && cfg.colorChoices.length >= picked.length) choices = cfg.colorChoices.filter((c) => /^[a-z]+$/.test(c));
    const saved = (cfg.colors || []).slice(0, picked.length).map((c) => (choices.includes(c) ? c : null));
    for (let i = 0; i < picked.length; i++) {
      picked[i] = saved[i] || choices.slice(i).concat(choices).find((c) => !saved.includes(c) && !picked.slice(0, i).includes(c));
    }
    renderSwatches();
    $('s-name').focus();
  }).catch(() => showError('The settings could not be loaded. Is the board running?'));

  $('s-form').addEventListener('submit', async (ev) => {
    ev.preventDefault();
    showError('');
    const pairs = inputs.map((x, i) => ({ name: x.value.trim(), color: picked[i] })).filter((p) => p.name);
    const body = { userName: $('s-name').value.trim(), customers: pairs.map((p) => p.name), colors: pairs.map((p) => p.color) };
    if (!body.userName) { showError('Please enter your name.'); $('s-name').focus(); return; }
    if (!body.customers.length) { showError('Please enter at least one customer.'); inputs[0].focus(); return; }
    if (new Set(body.colors).size !== body.colors.length) { showError('Pick a different colour for each customer.'); return; }
    $('s-save').disabled = true;
    try {
      const r = await fetch('/api/settings', { method: 'POST', headers: { 'X-Board': '1', 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
      const data = await r.json().catch(() => ({}));
      if (!r.ok) throw new Error((data.error && data.error.message) || 'The settings could not be saved.');
      location.href = '/';
    } catch (err) {
      showError(err.message);
      $('s-save').disabled = false;
    }
  });
})();

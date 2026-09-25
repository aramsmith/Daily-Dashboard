'use strict';
// Keeps the local board service awake while any board page is open (also in a background tab), and offers a
// "Start the board" button when the service has stopped. The button uses the dailyboard:// link that the setup registers.
window.BoardService = (() => {
  const OFFLINE_MESSAGE = 'The board service on this computer has stopped. Click "Start the board" to start it again.';
  const ping = () => fetch('/api/ping', { headers: { 'X-Board': '1' }, cache: 'no-store' }).then((r) => r.ok).catch(() => false);

  // Every 4 minutes: well inside the service's 30-minute idle stop, and slow enough for background-tab throttling.
  setInterval(ping, 4 * 60 * 1000);

  // A button that starts the service and calls onBack() as soon as it answers again (it waits at most one minute).
  function startButton(onBack) {
    const a = document.createElement('a');
    a.className = 'btn primary';
    a.href = 'dailyboard://start';
    a.textContent = 'Start the board';
    let polling = null;
    a.addEventListener('click', () => {
      if (polling) return;
      a.textContent = 'Starting…';
      const t0 = Date.now();
      polling = setInterval(async () => {
        if (await ping()) { clearInterval(polling); polling = null; onBack(); return; }
        if (Date.now() - t0 > 60000) {
          clearInterval(polling); polling = null;
          a.textContent = 'Start the board';
          a.title = 'The board did not start. Use the desktop shortcut instead.';
        }
      }, 2000);
    });
    return a;
  }

  return { ping, startButton, OFFLINE_MESSAGE };
})();

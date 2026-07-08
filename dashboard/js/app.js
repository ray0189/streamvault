// js/app.js — boot sequence. Loaded last; wires everything else together.

const App = (() => {
  async function boot() {
    go('dash');
  }

  function pingHealth() {
    fetch('/health')
      .then(r => {
        document.getElementById('sdot').className = 'st-dot' + (r.ok ? '' : ' off');
        document.getElementById('slbl').textContent = r.ok ? 'Online' : 'Error';
      })
      .catch(() => {
        document.getElementById('sdot').className = 'st-dot off';
        document.getElementById('slbl').textContent = 'Offline';
      });
  }

  function init() {
    Theme.init();
    pingHealth();
    const logoutBtn = document.getElementById('logout-btn');
    if (logoutBtn) logoutBtn.onclick = Auth.logout;
    Auth.tryAutoLogin();
  }

  return { boot, init };
})();

document.addEventListener('DOMContentLoaded', App.init);

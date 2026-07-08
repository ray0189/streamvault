// js/auth.js — login / auto-login / logout against /api/auth.
// The server issues a signed session (httpOnly cookie + a token we keep in
// localStorage for the x-admin-token header Api.call already sends). The raw
// password is only ever sent once, to /api/auth/login.

const Auth = (() => {
  function showAuthPage() {
    const pg = document.getElementById('pg-auth');
    pg.style.display = 'flex';
    pg.classList.add('on');
    document.getElementById('sb').style.display = 'none';
  }
  function hideAuthPage() {
    const pg = document.getElementById('pg-auth');
    pg.style.display = 'none';
    pg.classList.remove('on');
    document.getElementById('sb').style.display = '';
  }

  async function probe() {
    const r = await fetch('/api/auth/me', { headers: { 'x-admin-token': Api.getToken() } });
    return r.status === 200;
  }

  function showError(msg) {
    const el = document.getElementById('aerr');
    el.textContent = msg || 'Invalid username or password';
    el.style.display = 'block';
  }

  async function login() {
    const username = document.getElementById('lg-user').value.trim();
    const password = document.getElementById('pw').value;
    if (!username || !password) return;
    let r;
    try {
      const res = await fetch('/api/auth/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ username, password }),
      });
      r = await res.json();
    } catch {
      return showError('Server unreachable');
    }
    if (!r.ok) return showError(r.error);
    Api.setToken(r.token);
    document.getElementById('aerr').style.display = 'none';
    document.getElementById('pw').value = '';
    hideAuthPage();
    await App.boot();
  }

  async function logout() {
    try { await fetch('/api/auth/logout', { method: 'POST' }); } catch { /* best effort */ }
    Api.clearToken();
    showAuthPage();
  }

  async function tryAutoLogin() {
    if (!Api.getToken()) {
      showAuthPage();
      return;
    }
    const ok = await probe();
    if (!ok) {
      Api.clearToken();
      showAuthPage();
      return;
    }
    hideAuthPage();
    await App.boot();
  }

  Api.onUnauthorized(() => {
    Api.clearToken();
    showAuthPage();
    toast('Session expired — please log in again');
  });

  return { login, logout, tryAutoLogin };
})();

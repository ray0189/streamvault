// js/api.js — token storage + fetch wrapper shared by every page module.
const TOKEN_KEY = 'sv_admin_token';

const Api = (() => {
  let unauthorizedHook = null;

  function getToken() {
    return localStorage.getItem(TOKEN_KEY) || '';
  }
  function setToken(v) {
    localStorage.setItem(TOKEN_KEY, v);
  }
  function clearToken() {
    localStorage.removeItem(TOKEN_KEY);
  }
  function onUnauthorized(fn) {
    unauthorizedHook = fn;
  }

  async function call(path, opts = {}) {
    let res;
    try {
      res = await fetch(path, {
        ...opts,
        headers: {
          'x-admin-token': getToken(),
          'Content-Type': 'application/json',
          ...(opts.headers || {}),
        },
      });
    } catch {
      return { error: 'Network error — server unreachable' };
    }
    if (res.status === 401 && unauthorizedHook) unauthorizedHook();
    try {
      return await res.json();
    } catch {
      return res.ok ? {} : { error: `Request failed (HTTP ${res.status})` };
    }
  }

  return { getToken, setToken, clearToken, onUnauthorized, call };
})();

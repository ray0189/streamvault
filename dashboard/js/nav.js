// js/nav.js — SPA page switching + active sidebar state + per-page onEnter hooks.

// Registry of page-id -> function called each time that page is navigated to.
const NAV_ENTER_HOOKS = {};
function registerOnEnter(id, fn) {
  NAV_ENTER_HOOKS[id] = fn;
}

function go(id) {
  document.querySelectorAll('.pg').forEach(p => {
    if (p.id === 'pg-auth') return;
    p.classList.remove('on');
    p.style.display = '';
  });
  document.querySelectorAll('.ni').forEach(n => n.classList.remove('on'));

  const p = document.getElementById('pg-' + id);
  if (p) p.classList.add('on');
  const n = document.getElementById('ni-' + id);
  if (n) n.classList.add('on');

  if (NAV_ENTER_HOOKS[id]) NAV_ENTER_HOOKS[id]();
}

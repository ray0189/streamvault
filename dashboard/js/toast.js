// js/toast.js — single shared toast notification with success/error variants.
let _toastTimer;
function toast(msg, type = '') {
  const el = document.getElementById('toast');
  if (!el) return;
  el.textContent = msg;
  el.classList.remove('t-success', 't-error');
  if (type === 'success') el.classList.add('t-success');
  if (type === 'error') el.classList.add('t-error');
  el.classList.add('on');
  clearTimeout(_toastTimer);
  _toastTimer = setTimeout(() => el.classList.remove('on'), type === 'error' ? 4000 : 2400);
}

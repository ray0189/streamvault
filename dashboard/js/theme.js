// js/theme.js — light/dark toggle, persisted in localStorage.
// Note: the actual default-theme application happens in an inline <script>
// in <head> (before stylesheets) to avoid a flash of the wrong theme. This
// file just owns the toggle button's behavior after the page has loaded.
const THEME_KEY = 'sv_theme';

const Theme = (() => {
  function get() {
    return document.documentElement.dataset.theme === 'light' ? 'light' : 'dark';
  }
  function set(theme) {
    document.documentElement.dataset.theme = theme;
    localStorage.setItem(THEME_KEY, theme);
    updateIcon();
  }
  function toggle() {
    set(get() === 'light' ? 'dark' : 'light');
  }
  function updateIcon() {
    const btn = document.getElementById('theme-toggle');
    if (!btn) return;
    btn.innerHTML = get() === 'light'
      ? '<svg viewBox="0 0 24 24"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg>'
      : '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M6.34 17.66l-1.41 1.41M19.07 4.93l-1.41 1.41"/></svg>';
  }
  function init() {
    updateIcon();
    const btn = document.getElementById('theme-toggle');
    if (btn) btn.onclick = toggle;
  }
  return { get, set, toggle, init };
})();

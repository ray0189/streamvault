// js/filters.js — per-profile blocked-release-tag editor.

const FILTER_SUGGESTIONS = [
  'CAM', 'CAMRIP', 'HDCAM', 'HD-CAM', 'TS', 'HDTS', 'TELESYNC', 'TC', 'HDTC',
  'TELECINE', 'SCR', 'SCREENER', 'DVDSCR', 'R5', 'WORKPRINT', 'WP', 'HC',
];

const Filters = (() => {
  let currentId = null;
  let currentTags = [];

  async function onEnter() {
    const profs = await Api.call('/api/profiles');
    const sel = document.getElementById('fl-profile-select');
    const list = Array.isArray(profs) ? profs : [];
    if (!list.length) {
      sel.innerHTML = '<option>No profiles yet</option>';
      document.getElementById('filter-panel').innerHTML = `<div class="emp"><div class="emp-t">No profiles yet</div><div class="emp-s">Create a profile first on the Profiles page.</div></div>`;
      return;
    }
    sel.innerHTML = list.map(p => `<option value="${p.configId}">${escapeHtml(p.name)}</option>`).join('');
    if (!currentId || !list.some(p => p.configId === currentId)) currentId = list[0].configId;
    sel.value = currentId;
    sel.onchange = () => { currentId = sel.value; loadProfile(currentId); };
    loadProfile(currentId);
  }

  async function loadProfile(configId) {
    const p = await Api.call(`/api/profiles/${configId}`);
    currentTags = Array.isArray(p?.prefs?.blockedTags) ? [...p.prefs.blockedTags] : [];
    render();
  }

  function render() {
    document.getElementById('bwrap').innerHTML = currentTags.length
      ? currentTags.map(t => `<span class="tagchip">${escapeHtml(t)}<button onclick="Filters.removeTag('${escapeHtml(t)}')">&times;</button></span>`).join('')
      : `<div class="emp-s" style="padding:8px 0">No blocked tags — every release type is allowed.</div>`;

    const remaining = FILTER_SUGGESTIONS.filter(t => !currentTags.includes(t));
    document.getElementById('suggest-wrap').innerHTML = remaining
      .map(t => `<span class="suggest-chip" onclick="Filters.addTag('${escapeHtml(t)}')">+ ${escapeHtml(t)}</span>`).join('');
  }

  function addTag(tag) {
    tag = tag.trim().toUpperCase();
    if (!tag || currentTags.includes(tag)) return;
    currentTags.push(tag);
    render();
  }

  function addFromInput() {
    const input = document.getElementById('fl-newtag');
    addTag(input.value);
    input.value = '';
  }

  function removeTag(tag) {
    currentTags = currentTags.filter(t => t !== tag);
    render();
  }

  async function save() {
    if (!currentId) return;
    await Api.call(`/api/profiles/${currentId}`, { method: 'PATCH', body: JSON.stringify({ blockedTags: currentTags }) });
    toast('Filters saved');
  }

  return { onEnter, loadProfile, addTag, addFromInput, removeTag, save };
})();

registerOnEnter('filters', () => Filters.onEnter());

// js/scoring.js — per-profile scoring weight editor.

const SCORING_LABELS = {
  resolution4K: '4K Bonus', dolbyVision: 'Dolby Vision', hevc: 'HEVC / x265',
  hdrPlus: 'HDR10+', remux: 'Remux', hdr: 'HDR10', bluray: 'BluRay',
  atmos: 'Atmos', webdl: 'WEB-DL', trueHD: 'TrueHD', webrip: 'WEBRip',
  dts: 'DTS', h264: 'x264',
};
const SCORING_MAX = 20;

const Scoring = (() => {
  let currentId = null;

  async function onEnter() {
    const profs = await Api.call('/api/profiles');
    const sel = document.getElementById('sc-profile-select');
    const list = Array.isArray(profs) ? profs : [];
    if (!list.length) {
      sel.innerHTML = '<option>No profiles yet</option>';
      document.getElementById('score-rows').innerHTML = `<div class="emp"><div class="emp-t">No profiles yet</div><div class="emp-s">Create a profile first on the Profiles page.</div></div>`;
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
    const scoring = p?.prefs?.scoring || {};
    const el = document.getElementById('score-rows');
    el.innerHTML = Object.keys(SCORING_LABELS).map(key => {
      const v = scoring[key] ?? 0;
      return `<div class="scrow">
        <span class="scn">${SCORING_LABELS[key]}</span>
        <input type="range" class="slider" min="0" max="${SCORING_MAX}" value="${v}" data-key="${key}" oninput="Scoring.onSlide(this)"/>
        <span class="scnum" id="scnum-${key}">${v}</span>
      </div>`;
    }).join('');
  }

  function onSlide(input) {
    document.getElementById(`scnum-${input.dataset.key}`).textContent = input.value;
  }

  async function save() {
    if (!currentId) return;
    const scoring = {};
    document.querySelectorAll('#score-rows .slider').forEach(s => {
      scoring[s.dataset.key] = parseInt(s.value, 10);
    });
    await Api.call(`/api/profiles/${currentId}`, { method: 'PATCH', body: JSON.stringify({ scoring }) });
    toast('Scoring saved');
  }

  return { onEnter, loadProfile, onSlide, save };
})();

registerOnEnter('scoring', () => Scoring.onEnter());

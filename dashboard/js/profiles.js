// js/profiles.js — Profiles page: list, create, edit, delete.

const QUALITY_OPTIONS = [['2160p', '4K'], ['1080p', '1080p'], ['720p', '720p'], ['480p', '480p']];
const LANGUAGE_OPTIONS = [
  ['en', 'English'], ['ar', 'Arabic'], ['fr', 'French'], ['de', 'German'],
  ['es', 'Spanish'], ['ja', 'Japanese'], ['ko', 'Korean'],
];

function escapeHtml(s) {
  return String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

// Renders a single-select button group into `containerId`, marking `selected` as active.
function renderButtonGroup(containerId, options, selected) {
  const el = document.getElementById(containerId);
  el.innerHTML = options.map(([value, label]) =>
    `<button type="button" class="bgrp-btn${value === selected ? ' sel' : ''}" data-value="${escapeHtml(value)}">${escapeHtml(label)}</button>`
  ).join('');
  el.onclick = (e) => {
    const btn = e.target.closest('.bgrp-btn');
    if (!btn || btn.disabled) return;
    el.querySelectorAll('.bgrp-btn').forEach(b => b.classList.remove('sel'));
    btn.classList.add('sel');
  };
}
function getButtonGroupValue(containerId) {
  const sel = document.querySelector(`#${containerId} .bgrp-btn.sel`);
  return sel ? sel.dataset.value : null;
}

const Profiles = (() => {
  let editingId = null;

  async function load() {
    const profs = await Api.call('/api/profiles');
    const info = await Api.call('/api/info');
    render(Array.isArray(profs) ? profs : [], info);
  }

  function render(profs, info) {
    const el = document.getElementById('prof-panel');
    if (!profs.length) {
      el.innerHTML = `<div class="emp"><div class="emp-i"><svg viewBox="0 0 24 24"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/></svg></div><div class="emp-t">No profiles yet</div><div class="emp-s">Create a profile to get a manifest URL for Stremio.</div></div>`;
      return;
    }
    const port = info?.port || 7000;
    el.innerHTML = profs.map(p => {
      const id = p.configId;
      const pub = info?.publicUrl ? `${String(info.publicUrl).replace(/\/$/, '')}/config/${id}/manifest.json` : null;
      const lan = info?.nasIp ? `http://${info.nasIp}:${port}/config/${id}/manifest.json` : null;
      const urls = [pub ? { b: 'Public', u: pub } : null, lan ? { b: 'LAN', u: lan } : null].filter(Boolean);
      const chips = [
        p.prefs?.cachedOnly ? `<span class="chip chip-success">Cached only</span>` : `<span class="chip">All sources</span>`,
        p.prefs?.minQuality ? `<span class="chip chip-accent">${escapeHtml(p.prefs.minQuality)}+</span>` : '',
      ].join('');
      return `<div class="prof">
        <div class="prof-h">
          <div>
            <div class="prof-name">${escapeHtml(p.name)}</div>
            <div class="prof-id">${id.slice(0, 8).toUpperCase()}… · ${new Date(p.createdAt).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' })}</div>
            <div class="chips">${chips}</div>
          </div>
          <div class="prof-actions">
            <button class="btn btn-ghost btn-xs" onclick="Profiles.openEdit('${id}')">Edit</button>
            <button class="btn btn-danger btn-xs" onclick="Profiles.remove('${id}')">Remove</button>
          </div>
        </div>
        <div class="urls">${urls.map(u => `<div class="urow"><span class="ubadge">${u.b}</span><span class="uval" title="${escapeHtml(u.u)}">${escapeHtml(u.u)}</span><button class="cbtn" onclick="Profiles.copyUrl(this,'${escapeHtml(u.u)}')"><svg viewBox="0 0 24 24"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg></button></div>`).join('')}</div>
      </div>`;
    }).join('');
  }

  function fillForm(prefs = {}) {
    renderButtonGroup('pf-minq', QUALITY_OPTIONS, prefs.minQuality || '1080p');
    renderButtonGroup('pf-maxq', QUALITY_OPTIONS, prefs.maxQuality || '2160p');
    renderButtonGroup('pf-lang', LANGUAGE_OPTIONS, prefs.language || 'en');
    renderButtonGroup('pf-debrid', [['torbox', 'TorBox']], 'torbox');
    document.querySelectorAll('#pf-debrid .bgrp-btn').forEach(b => b.disabled = true);
    document.getElementById('pf-cached').checked = prefs.cachedOnly !== false;
  }

  function openCreate() {
    editingId = null;
    document.getElementById('pf-title').textContent = 'New profile';
    document.getElementById('pf-sub').textContent = 'Creates a unique private manifest URL for a device or person.';
    document.getElementById('pf-save').textContent = 'Generate manifest';
    const nameInput = document.getElementById('pf-name');
    nameInput.value = '';
    nameInput.disabled = false;
    document.getElementById('pf-name-hint').style.display = 'none';
    fillForm({});
    openModal('profile-modal');
  }

  async function openEdit(configId) {
    const p = await Api.call(`/api/profiles/${configId}`);
    if (!p || !p.configId) return;
    editingId = configId;
    document.getElementById('pf-title').textContent = 'Edit profile';
    document.getElementById('pf-sub').textContent = 'Update preferences for this profile.';
    document.getElementById('pf-save').textContent = 'Save changes';
    const nameInput = document.getElementById('pf-name');
    nameInput.value = p.name || '';
    // The backend's PATCH endpoint only updates prefs, not the profile name —
    // renaming isn't supported, so keep this read-only in edit mode.
    nameInput.disabled = true;
    document.getElementById('pf-name-hint').style.display = 'block';
    fillForm(p.prefs || {});
    openModal('profile-modal');
  }

  async function save() {
    const prefs = {
      minQuality: getButtonGroupValue('pf-minq'),
      maxQuality: getButtonGroupValue('pf-maxq'),
      language: getButtonGroupValue('pf-lang'),
      cachedOnly: document.getElementById('pf-cached').checked,
      debridProvider: 'torbox',
    };

    if (editingId) {
      await Api.call(`/api/profiles/${editingId}`, { method: 'PATCH', body: JSON.stringify(prefs) });
      toast('Profile updated');
    } else {
      const name = document.getElementById('pf-name').value.trim() || 'New Profile';
      await Api.call('/api/profiles', { method: 'POST', body: JSON.stringify({ name, prefs }) });
      toast('Profile created');
    }
    closeModal('profile-modal');
    load();
  }

  function remove(configId) {
    confirmDanger({
      title: 'Remove profile',
      body: 'Its manifest URL will stop working immediately. This cannot be undone.',
      confirmLabel: 'Remove',
      onConfirm: async () => {
        await Api.call(`/api/profiles/${configId}`, { method: 'DELETE' });
        toast('Profile removed');
        load();
      },
    });
  }

  function copyUrl(btn, url) {
    navigator.clipboard.writeText(url).then(() => {
      btn.classList.add('ok');
      setTimeout(() => btn.classList.remove('ok'), 1800);
      toast('Copied to clipboard');
    });
  }

  return { load, openCreate, openEdit, save, remove, copyUrl };
})();

registerOnEnter('profiles', () => Profiles.load());

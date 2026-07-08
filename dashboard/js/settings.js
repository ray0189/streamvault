// js/settings.js — Settings page: grouped env-backed config, per-section save,
// TorBox connection test, cache flush, restart.

const Settings = (() => {
  const QUALITIES = ['480p', '720p', '1080p', '1440p', '2160p'];
  let minQuality = '1080p';
  // Secrets: only send when the user actually typed something.
  const touched = new Set();

  function $(id) { return document.getElementById(id); }

  function markTouched(id) {
    $(id).addEventListener('input', () => touched.add(id), { once: false });
  }

  function clearErrors() {
    document.querySelectorAll('.ferr').forEach(e => { e.textContent = ''; e.classList.remove('on'); });
  }

  function fieldError(errId, msg) {
    const el = $(errId);
    if (el) { el.textContent = msg; el.classList.add('on'); }
    return false;
  }

  function isHttpUrl(s) {
    try { const u = new URL(s); return u.protocol === 'http:' || u.protocol === 'https:'; }
    catch { return false; }
  }

  function renderQualityPicker() {
    const wrap = $('set-minq');
    wrap.innerHTML = '';
    QUALITIES.forEach(q => {
      const b = document.createElement('button');
      b.className = 'bgrp-btn' + (q === minQuality ? ' sel' : '');
      b.textContent = q;
      b.onclick = () => { minQuality = q; renderQualityPicker(); };
      wrap.appendChild(b);
    });
  }

  async function onEnter() {
    clearErrors();
    touched.clear();
    $('set-banner').classList.remove('on');
    $('torbox-test-result').textContent = '';
    $('flush-result').textContent = '';

    const s = await Api.call('/api/settings');
    if (s.error) { toast(s.error, 'error'); return; }

    // Streaming
    $('set-public-url').value = s.streaming.publicBaseUrl || '';
    $('set-nas-ip').value = s.streaming.nasLocalIp || '';
    $('set-provider-priority').value = s.streaming.providerPriority || '';
    $('set-ext-fallback').checked = !!s.streaming.externalTorrentFallback;
    $('set-torrentio').checked = !!s.streaming.torrentioEnabled;
    $('set-knightcrawler').checked = !!s.streaming.knightcrawlerEnabled;

    // TorBox — masked placeholder, never echo the key into the field
    const keyInput = $('set-torbox-key');
    keyInput.value = '';
    keyInput.placeholder = s.torbox.apiKeySet ? s.torbox.apiKeyMasked : 'Not set';
    $('set-torbox-url').value = s.torbox.apiUrl || '';
    $('set-torbox-timeout').value = s.torbox.timeoutMs ?? '';
    $('set-torbox-retries').value = s.torbox.retries ?? '';
    $('set-torbox-native').checked = !!s.torbox.nativeSearch;
    $('set-torbox-usenet').checked = !!s.torbox.usenet;
    $('set-torbox-engines').checked = !!s.torbox.userEngines;

    // Cache
    $('set-redis').value = s.cache.redisUrl || '';
    const managed = !!s.cache.redisManaged;
    $('set-redis').disabled = managed;
    $('redis-managed-chip').style.display = managed ? 'inline-flex' : 'none';
    $('redis-hint').textContent = managed
      ? 'Set by docker-compose (environment: REDIS_URL) — edit docker-compose.yml to change it. Redis: ' + s.cache.redisStatus
      : 'Restart to apply. Redis: ' + s.cache.redisStatus;
    $('set-ttl-stream').value = s.cache.streamCacheTtl ?? '';
    $('set-ttl-meta').value = s.cache.metaCacheTtl ?? '';

    // Defaults
    minQuality = s.defaults.minQuality || '1080p';
    renderQualityPicker();
    $('set-language').value = s.defaults.language || 'en';
    $('set-cached-only').checked = !!s.defaults.cachedOnly;

    // Account
    $('set-current-password').value = '';
    $('set-new-password').value = '';

    ['set-torbox-key'].forEach(markTouched);
  }

  function toggleSecret(id, isTorboxKey = false) {
    const input = $(id);
    const btn = input.parentElement.parentElement.querySelector('button') || event.target;
    const showing = input.type === 'text';
    if (showing) {
      input.type = 'password';
      if (event && event.target) event.target.textContent = 'Show';
      return;
    }
    input.type = 'text';
    if (event && event.target) event.target.textContent = 'Hide';
    // Revealing the stored TorBox key fetches it explicitly (never sent on load)
    if (isTorboxKey && !input.value) {
      Api.call('/api/settings/torbox-key').then(r => {
        if (r.torboxApiKey && !input.value) input.placeholder = r.torboxApiKey;
      });
    }
  }

  // ── Per-section validation + payload builders ────────────────
  const SECTIONS = {
    streaming() {
      const pub = $('set-public-url').value.trim();
      if (pub && !isHttpUrl(pub)) return fieldError('err-public-url', 'Must be a valid http(s) URL');
      const prio = $('set-provider-priority').value.trim();
      if (!prio) return fieldError('err-provider-priority', 'Required — e.g. torbox-torrent,torbox-usenet');
      return {
        publicBaseUrl: pub,
        nasLocalIp: $('set-nas-ip').value.trim(),
        providerPriority: prio,
        externalTorrentFallback: $('set-ext-fallback').checked,
        torrentioEnabled: $('set-torrentio').checked,
        knightcrawlerEnabled: $('set-knightcrawler').checked,
      };
    },
    torbox() {
      const url = $('set-torbox-url').value.trim();
      if (!url) return fieldError('err-torbox-url', 'Required');
      if (!isHttpUrl(url)) return fieldError('err-torbox-url', 'Must be a valid http(s) URL');
      const timeout = parseInt($('set-torbox-timeout').value, 10);
      if (!Number.isFinite(timeout) || timeout < 1000 || timeout > 120000)
        return fieldError('err-torbox-timeout', 'Between 1000 and 120000 ms');
      const retries = parseInt($('set-torbox-retries').value, 10);
      if (!Number.isFinite(retries) || retries < 1 || retries > 10)
        return fieldError('err-torbox-retries', 'Between 1 and 10');
      const body = {
        torboxApiUrl: url,
        torboxTimeoutMs: timeout,
        torboxRetries: retries,
        torboxNativeSearch: $('set-torbox-native').checked,
        torboxUsenet: $('set-torbox-usenet').checked,
        torboxUserEngines: $('set-torbox-engines').checked,
      };
      const key = $('set-torbox-key').value.trim();
      if (touched.has('set-torbox-key') && key) {
        if (key.length < 10 || key.includes('•')) return fieldError('err-torbox-key', 'That does not look like a valid key');
        body.torboxApiKey = key;
      }
      return body;
    },
    cache() {
      const body = {};
      if (!$('set-redis').disabled) {
        const r = $('set-redis').value.trim();
        if (!r) return fieldError('err-redis', 'Required');
        if (!r.startsWith('redis://') && !r.startsWith('rediss://'))
          return fieldError('err-redis', 'Must start with redis:// or rediss://');
        body.redisUrl = r;
      }
      const st = parseInt($('set-ttl-stream').value, 10);
      if (!Number.isFinite(st) || st < 60 || st > 604800)
        return fieldError('err-ttl-stream', 'Between 60 and 604800 seconds');
      const mt = parseInt($('set-ttl-meta').value, 10);
      if (!Number.isFinite(mt) || mt < 60 || mt > 604800)
        return fieldError('err-ttl-meta', 'Between 60 and 604800 seconds');
      body.streamCacheTtl = st;
      body.metaCacheTtl = mt;
      return body;
    },
    defaults() {
      const lang = $('set-language').value.trim().toLowerCase();
      if (!/^[a-z]{2,5}$/.test(lang)) return fieldError('err-language', 'Use a short code like en, de, hi');
      return {
        defaultMinQuality: minQuality,
        defaultLanguage: lang,
        defaultCachedOnly: $('set-cached-only').checked,
      };
    },
  };

  async function saveSection(name) {
    clearErrors();
    const body = SECTIONS[name]();
    if (body === false) return;

    const btn = $('save-' + name);
    btn.disabled = true;
    const r = await Api.call('/api/settings', { method: 'PATCH', body: JSON.stringify(body) });
    btn.disabled = false;

    if (r.error) {
      if (r.fieldErrors) toast(Object.values(r.fieldErrors)[0], 'error');
      else toast(r.error, 'error');
      return;
    }

    toast('Saved ' + name + (r.restartRequired ? ' — restart to apply' : ''), 'success');
    if (r.restartRequired) $('set-banner').classList.add('on');
    if (name === 'torbox') onEnter();
  }

  async function changePassword() {
    clearErrors();
    const current = $('set-current-password').value;
    const next = $('set-new-password').value;
    if (!current) return fieldError('err-current-password', 'Required');
    if (next.length < 8) return fieldError('err-new-password', 'At least 8 characters');

    const btn = $('btn-change-password');
    btn.disabled = true;
    const r = await Api.call('/api/auth/change-password', {
      method: 'POST',
      body: JSON.stringify({ currentPassword: current, newPassword: next }),
    });
    btn.disabled = false;
    if (r.error) { toast(r.error, 'error'); return; }
    if (r.token) Api.setToken(r.token); // rotated session
    $('set-current-password').value = '';
    $('set-new-password').value = '';
    toast('Password changed', 'success');
  }

  async function testTorbox() {
    const btn = $('btn-test-torbox');
    const out = $('torbox-test-result');
    btn.disabled = true;
    out.className = 'set-test-result';
    out.textContent = 'Testing…';

    // Test the key in the field if the user typed one, else the stored key
    const body = {};
    const typed = $('set-torbox-key').value.trim();
    if (touched.has('set-torbox-key') && typed && !typed.includes('•')) body.torboxApiKey = typed;

    const r = await Api.call('/api/settings/test-torbox', { method: 'POST', body: JSON.stringify(body) });
    btn.disabled = false;
    if (r.ok) {
      out.classList.add('ok');
      out.textContent = '✓ Connected' + (r.email ? ' — ' + r.email : '');
      toast('TorBox connection OK', 'success');
    } else {
      out.classList.add('fail');
      out.textContent = '✗ ' + (r.error || 'Failed');
      toast('TorBox test failed: ' + (r.error || 'unknown error'), 'error');
    }
  }

  async function flushCache() {
    const btn = $('btn-flush-cache');
    const out = $('flush-result');
    btn.disabled = true;
    out.className = 'set-test-result';
    out.textContent = 'Flushing…';
    const r = await Api.call('/api/settings/flush-cache', { method: 'POST', body: '{}' });
    btn.disabled = false;
    if (r.flushed) {
      out.classList.add('ok');
      out.textContent = '✓ Flushed (' + (r.redisCleared ?? 0) + ' Redis keys)';
      toast('Cache flushed', 'success');
    } else {
      out.classList.add('fail');
      out.textContent = '✗ ' + (r.error || 'Failed');
      toast('Flush failed: ' + (r.error || 'unknown error'), 'error');
    }
  }

  function confirmRestart() {
    confirmDanger({
      title: 'Restart StreamVault?',
      body: 'The service stops and Docker restarts it automatically within a few seconds. Streams may briefly fail during the restart.',
      confirmLabel: 'Restart',
      onConfirm: doRestart,
    });
  }

  async function doRestart() {
    await Api.call('/api/restart', { method: 'POST' });
    toast('Restarting — back in a few seconds…');
    // Poll /health until the container is back, then reload settings
    const started = Date.now();
    const poll = setInterval(async () => {
      try {
        const res = await fetch('/health');
        if (res.ok) {
          clearInterval(poll);
          toast('Service is back', 'success');
          onEnter();
        }
      } catch { /* still down */ }
      if (Date.now() - started > 60000) {
        clearInterval(poll);
        toast('Still down after 60 s — check docker logs', 'error');
      }
    }, 2000);
  }

  return { onEnter, toggleSecret, saveSection, changePassword, testTorbox, flushCache, confirmRestart };
})();

registerOnEnter('settings', () => Settings.onEnter());

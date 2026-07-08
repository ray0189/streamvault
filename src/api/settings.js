// src/api/settings.js — internal REST API for the dashboard Settings page.
//
// Values are persisted to .env via env-file.js and mirrored onto process.env.
// Most config is destructured as constants at require-time elsewhere, so a
// PATCH marks restartRequired — under Docker (restart: unless-stopped) the
// Restart button in the UI is a safe way to apply them.

const express = require('express');
const axios = require('axios');
const router = express.Router();
const envFile = require('../config/env-file');
const cache = require('../cache/store');
const env = require('../config/env');
const { verifySession, tokenFromRequest } = require('../auth/session');

const { ADMIN_PASSWORD } = env;

function adminAuth(req, res, next) {
  // Dashboard/browser path: accept the signed session cookie or Bearer token
  // created by /api/auth/login.
  try {
    const session = verifySession(tokenFromRequest(req));
    if (session) {
      req.session = session;
      return next();
    }
  } catch (_) {
    // Fall through to legacy raw-token check below.
  }

  // CLI/backwards-compatible path: raw ADMIN_PASSWORD via x-admin-token or
  // ?token=... still works for scripts/curl.
  const token = req.headers['x-admin-token'] || req.query.token;
  const current = process.env.ADMIN_PASSWORD || ADMIN_PASSWORD;
  if (token !== current) return res.status(401).json({ error: 'Unauthorised' });
  next();
}

function maskKey(key) {
  if (!key) return '';
  if (key.length <= 4) return '••••';
  return `${'•'.repeat(Math.max(key.length - 4, 8))}${key.slice(-4)}`;
}

function cur(name, fallback = '') {
  return process.env[name] !== undefined ? process.env[name] : (env[name] !== undefined ? String(env[name]) : fallback);
}

function curBool(name, fallback) {
  const v = process.env[name];
  if (v === undefined || v === '') return fallback;
  return !['0', 'false', 'no', 'off'].includes(String(v).toLowerCase());
}

function curInt(name, fallback) {
  const n = parseInt(process.env[name], 10);
  return Number.isFinite(n) ? n : fallback;
}

// True when docker-compose (or the shell) forces a var, making .env edits moot
function isEnvOverridden(name) {
  const fileVal = envFile.readEnvFile().values[name];
  const procVal = process.env[name];
  return procVal !== undefined && fileVal !== undefined && procVal !== fileVal;
}

// ── Field registry: one place defines key, type and validation ──
const FIELDS = {
  // Streaming
  publicBaseUrl: { key: 'PUBLIC_BASE_URL', type: 'url', optional: true },
  nasLocalIp: { key: 'NAS_LOCAL_IP', type: 'string', optional: true },
  providerPriority: { key: 'TORBOX_PROVIDER_PRIORITY', type: 'string' },
  externalTorrentFallback: { key: 'EXTERNAL_TORRENT_FALLBACK', type: 'bool' },
  torrentioEnabled: { key: 'TORRENTIO_ENABLED', type: 'bool' },
  knightcrawlerEnabled: { key: 'KNIGHTCRAWLER_ENABLED', type: 'bool' },
  // TorBox
  torboxApiKey: { key: 'TORBOX_API_KEY', type: 'string', secret: true },
  torboxApiUrl: { key: 'TORBOX_API_URL', type: 'url' },
  torboxTimeoutMs: { key: 'TORBOX_TIMEOUT_MS', type: 'int', min: 1000, max: 120000 },
  torboxRetries: { key: 'TORBOX_RETRIES', type: 'int', min: 1, max: 10 },
  torboxNativeSearch: { key: 'TORBOX_ENABLE_NATIVE_SEARCH', type: 'bool' },
  torboxUsenet: { key: 'TORBOX_ENABLE_USENET', type: 'bool' },
  torboxUserEngines: { key: 'TORBOX_SEARCH_USER_ENGINES', type: 'bool' },
  // Cache
  redisUrl: { key: 'REDIS_URL', type: 'string' },
  streamCacheTtl: { key: 'STREAM_CACHE_TTL', type: 'int', min: 60, max: 604800 },
  metaCacheTtl: { key: 'META_CACHE_TTL', type: 'int', min: 60, max: 604800 },
  // Defaults
  defaultMinQuality: { key: 'DEFAULT_MIN_QUALITY', type: 'enum', values: ['480p', '720p', '1080p', '1440p', '2160p'] },
  defaultCachedOnly: { key: 'DEFAULT_CACHED_ONLY', type: 'bool' },
  defaultLanguage: { key: 'DEFAULT_LANGUAGE', type: 'string' },
  // Advanced
  newAdminPassword: { key: 'ADMIN_PASSWORD', type: 'string', secret: true, minLen: 6 },
  secretKey: { key: 'SECRET_KEY', type: 'string', secret: true, minLen: 16 },
};

// GET /api/settings — everything, secrets masked
router.get('/settings', adminAuth, (req, res) => {
  res.json({
    streaming: {
      publicBaseUrl: cur('PUBLIC_BASE_URL'),
      nasLocalIp: cur('NAS_LOCAL_IP'),
      providerPriority: cur('TORBOX_PROVIDER_PRIORITY', env.TORBOX_PROVIDER_PRIORITY),
      externalTorrentFallback: curBool('EXTERNAL_TORRENT_FALLBACK', true),
      torrentioEnabled: curBool('TORRENTIO_ENABLED', true),
      knightcrawlerEnabled: curBool('KNIGHTCRAWLER_ENABLED', true),
    },
    torbox: {
      apiKeyMasked: maskKey(cur('TORBOX_API_KEY')),
      apiKeySet: !!cur('TORBOX_API_KEY'),
      apiUrl: cur('TORBOX_API_URL', env.TORBOX_API_URL),
      timeoutMs: curInt('TORBOX_TIMEOUT_MS', env.TORBOX_TIMEOUT_MS),
      retries: curInt('TORBOX_RETRIES', env.TORBOX_RETRIES),
      nativeSearch: curBool('TORBOX_ENABLE_NATIVE_SEARCH', true),
      usenet: curBool('TORBOX_ENABLE_USENET', true),
      userEngines: curBool('TORBOX_SEARCH_USER_ENGINES', false),
    },
    cache: {
      redisUrl: cur('REDIS_URL', env.REDIS_URL),
      redisManaged: isEnvOverridden('REDIS_URL'),
      redisStatus: cache.stats().redis,
      streamCacheTtl: curInt('STREAM_CACHE_TTL', env.STREAM_CACHE_TTL),
      metaCacheTtl: curInt('META_CACHE_TTL', env.META_CACHE_TTL),
    },
    defaults: {
      minQuality: cur('DEFAULT_MIN_QUALITY', env.DEFAULT_MIN_QUALITY),
      cachedOnly: curBool('DEFAULT_CACHED_ONLY', true),
      language: cur('DEFAULT_LANGUAGE', env.DEFAULT_LANGUAGE),
    },
    advanced: {
      secretKeySet: !!cur('SECRET_KEY') && cur('SECRET_KEY') !== 'change-me',
      secretKeyMasked: maskKey(cur('SECRET_KEY') === 'change-me' ? '' : cur('SECRET_KEY')),
      port: curInt('PORT', env.PORT),
    },
  });
});

// GET /api/settings/torbox-key — raw key, only fetched on explicit "Reveal"
router.get('/settings/torbox-key', adminAuth, (req, res) => {
  res.json({ torboxApiKey: cur('TORBOX_API_KEY') });
});

function validateField(name, value) {
  const spec = FIELDS[name];
  if (!spec) return { error: `Unknown field: ${name}` };
  switch (spec.type) {
    case 'bool':
      return { value: value === true || value === 'true' ? 'true' : 'false' };
    case 'int': {
      const n = parseInt(value, 10);
      if (!Number.isFinite(n)) return { error: `${name} must be a number` };
      if (spec.min !== undefined && n < spec.min) return { error: `${name} must be ≥ ${spec.min}` };
      if (spec.max !== undefined && n > spec.max) return { error: `${name} must be ≤ ${spec.max}` };
      return { value: String(n) };
    }
    case 'url': {
      const s = String(value).trim();
      if (!s) return spec.optional ? { value: '' } : { error: `${name} is required` };
      try {
        const u = new URL(s);
        if (!['http:', 'https:'].includes(u.protocol)) throw new Error();
      } catch {
        return { error: `${name} must be a valid http(s) URL` };
      }
      return { value: s.replace(/\/+$/, '') };
    }
    case 'enum':
      if (!spec.values.includes(value)) return { error: `${name} must be one of: ${spec.values.join(', ')}` };
      return { value: String(value) };
    default: {
      const s = String(value).trim();
      if (!s && !spec.optional) return { error: `${name} cannot be empty` };
      if (spec.minLen && s.length < spec.minLen) return { error: `${name} must be at least ${spec.minLen} characters` };
      return { value: s };
    }
  }
}

// PATCH /api/settings — persist any subset of fields to .env
router.patch('/settings', adminAuth, (req, res) => {
  const body = req.body || {};
  const updates = {};
  const fieldErrors = {};

  for (const [name, value] of Object.entries(body)) {
    if (!FIELDS[name]) continue;
    const r = validateField(name, value);
    if (r.error) fieldErrors[name] = r.error;
    else updates[FIELDS[name].key] = r.value;
  }

  if (Object.keys(fieldErrors).length) {
    return res.status(400).json({ error: 'Validation failed', fieldErrors });
  }
  if (!Object.keys(updates).length) {
    return res.status(400).json({ error: 'No recognised fields in body' });
  }

  envFile.writeEnvUpdates(updates);

  // ADMIN_PASSWORD is checked against process.env live, so it applies now.
  const liveKeys = ['ADMIN_PASSWORD', 'PUBLIC_BASE_URL'];
  const restartRequired = Object.keys(updates).some(k => !liveKeys.includes(k));
  res.json({ saved: true, restartRequired, savedKeys: Object.keys(updates) });
});

// POST /api/settings/test-torbox — live connectivity check against TorBox
router.post('/settings/test-torbox', adminAuth, async (req, res) => {
  const key = (req.body && req.body.torboxApiKey) || cur('TORBOX_API_KEY');
  if (!key) return res.status(400).json({ ok: false, error: 'No API key set' });
  const base = cur('TORBOX_API_URL', env.TORBOX_API_URL).replace(/\/+$/, '');
  try {
    const r = await axios.get(`${base}/user/me`, {
      headers: { Authorization: `Bearer ${key}` },
      timeout: 10000,
    });
    const d = r.data && r.data.data ? r.data.data : {};
    res.json({ ok: true, email: d.email || null, plan: d.plan ?? null, customer: d.customer || null });
  } catch (err) {
    const status = err.response?.status;
    const detail = err.response?.data?.detail || err.message;
    res.json({ ok: false, error: status === 401 || status === 403 ? 'Invalid API key' : `TorBox unreachable: ${detail}` });
  }
});

// POST /api/settings/flush-cache — clear memory caches + Redis stream keys
router.post('/settings/flush-cache', adminAuth, async (req, res) => {
  const result = await cache.flushCaches();
  res.json({ flushed: true, ...result });
});

// POST /api/restart — exits the process; Docker's restart policy brings it back
router.post('/restart', adminAuth, (req, res) => {
  res.json({ restarting: true });
  res.on('finish', () => {
    setTimeout(() => process.exit(0), 100);
  });
});

module.exports = router;

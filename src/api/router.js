// src/api/router.js — internal REST API for the dashboard

const express     = require('express');
const rateLimit   = require('express-rate-limit');
const router      = express.Router();
const profileStore = require('../profiles/store');
const cache        = require('../cache/store');
const torbox       = require('./torbox');
const { PORT, NAS_LOCAL_IP, TAILSCALE_HOST } = require('../config/env');
const { getPublicBaseUrl, normalizeBaseUrl } = require('../config/public-url');
const { requireAuth: adminAuth } = require('../auth/session');

// ── Rate limiter on profile creation ─────────────────────────
const createLimiter = rateLimit({ windowMs: 60_000, max: 10 });

// ─────────────────────────────────────────────────────────────
//  Profile management
// ─────────────────────────────────────────────────────────────

// GET /api/profiles — list all profiles
router.get('/profiles', adminAuth, (req, res) => {
  res.json(profileStore.listProfiles());
});

// POST /api/profiles — create a new profile
router.post('/profiles', adminAuth, createLimiter, (req, res) => {
  const { name = 'New Profile', prefs = {} } = req.body;
  const configId = profileStore.createProfile(name, prefs);
  const profile  = profileStore.getProfile(configId);

  const manifestBase = buildManifestBase(configId);

  res.json({
    ...profile,
    manifestUrls: manifestBase,
  });
});

// GET /api/profiles/:configId — get one profile
router.get('/profiles/:configId', adminAuth, (req, res) => {
  const p = profileStore.getProfile(req.params.configId);
  if (!p) return res.status(404).json({ error: 'Not found' });
  res.json({ ...p, manifestUrls: buildManifestBase(req.params.configId) });
});

// PATCH /api/profiles/:configId — update preferences
router.patch('/profiles/:configId', adminAuth, (req, res) => {
  const updated = profileStore.updateProfile(req.params.configId, req.body);
  if (!updated) return res.status(404).json({ error: 'Not found' });
  res.json(updated);
});

// DELETE /api/profiles/:configId
router.delete('/profiles/:configId', adminAuth, (req, res) => {
  const ok = profileStore.deleteProfile(req.params.configId);
  if (!ok) return res.status(404).json({ error: 'Not found' });
  res.json({ deleted: true });
});

// ─────────────────────────────────────────────────────────────
//  Cache stats
// ─────────────────────────────────────────────────────────────

router.get('/cache/stats', adminAuth, (req, res) => {
  res.json(cache.stats());
});

router.post('/cache/clear', adminAuth, (req, res) => {
  cache.clearStreams();
  res.json({ cleared: true });
});

// ─────────────────────────────────────────────────────────────
//  Health / info
// ─────────────────────────────────────────────────────────────

router.get('/info', (req, res) => {
  const mem = process.memoryUsage();
  const stats = cache.stats();
  const publicUrl = getPublicBaseUrl(req);
  res.json({
    status: 'ok',
    publicUrl,
    nasIp: NAS_LOCAL_IP,
    tailscale: TAILSCALE_HOST,
    port: PORT,
    redis: stats.redis,
    memory: `${Math.round(mem.rss / 1024 / 1024)} MB`,
    uptime: `${Math.floor(process.uptime() / 60)}m`,
    plan: 'Pro',
  });
});

router.get('/debug/torbox', adminAuth, (req, res) => {
  res.json(torbox.getDiagnostics());
});

// ─────────────────────────────────────────────────────────────
//  Helpers
// ─────────────────────────────────────────────────────────────

function buildManifestBase(configId) {
  const path = `/config/${configId}/manifest.json`;
  const publicBase = normalizeBaseUrl(process.env.PUBLIC_BASE_URL || '');
  return {
    public:    publicBase ? `${publicBase}${path}` : null,
    lan:       NAS_LOCAL_IP  ? `http://${NAS_LOCAL_IP}:${PORT}${path}`  : null,
    tailscale: TAILSCALE_HOST ? `http://${TAILSCALE_HOST}:${PORT}${path}` : null,
    localhost: `http://localhost:${PORT}${path}`,
  };
}

module.exports = router;

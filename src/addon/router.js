// src/addon/router.js — Stremio-compatible addon endpoints

const express  = require('express');
const router   = express.Router();
const { getProfile } = require('../profiles/store');
const { buildManifest } = require('./manifest');
const { handleStream } = require('./streams');

// Every route is prefixed with /config/:configId (mounted in server.js as /config)

// ── Middleware: resolve profile ────────────────────────────────
router.use('/:configId/*', (req, res, next) => {
  const profile = getProfile(req.params.configId);
  if (!profile) return res.status(404).json({ error: 'Unknown config ID' });
  req.profile = profile;
  next();
});

// ── Manifest ───────────────────────────────────────────────────
// GET /config/:configId/manifest.json
router.get('/:configId/manifest.json', (req, res) => {
  res.setHeader('Content-Type', 'application/json');
  res.json(buildManifest(req.profile));
});

// ── Streams ────────────────────────────────────────────────────
// GET /config/:configId/stream/:type/:id.json
// type = "movie" | "series"
// id   = "tt1234567" (movie) | "tt1234567:1:2" (series s1e2)
router.get('/:configId/stream/:type/:id.json', async (req, res) => {
  const { type, id } = req.params;
  try {
    const streams = await handleStream(type, id, req.profile, req);
    res.json({ streams });
  } catch (err) {
    console.error('[Stream] Error:', err.message);
    res.json({ streams: [] });
  }
});

module.exports = router;

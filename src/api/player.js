// src/api/player.js — Web player API routes
// GET /api/player/search?q=inception&type=movie
// GET /api/player/streams/:type/:imdbId[/:season/:episode]
// GET /api/player/play/:torrentId/:fileId  → 302 to TorBox CDN

const express = require('express');
const axios   = require('axios');
const router  = express.Router();

const torbox          = require('./torbox');
const { filterResultsWithReasons } = require('../filters/quality');
const { rankResults }   = require('../scoring/rank');
const { detectResolution } = require('../filters/quality');
const { requireAuth } = require('../auth/session');

// Default prefs for the web player.
const PLAYER_PREFS = {
  minQuality:  '1080p',
  cachedOnly:  true,
  blockedTags: ['CAM','TS','HDCAM','SCR','DVDSCR','TELECINE','TELESYNC','HC','R5'],
  scoring: {
    resolution4K: 12, dolbyVision: 10, hevc: 10, hdrPlus: 9,
    remux: 9, hdr: 8, bluray: 7, atmos: 6, webdl: 6,
    trueHD: 5, webrip: 3, dts: 3, h264: 1,
  },
};

// ── Auth — session-based, shared with the dashboard ─────────
const auth = requireAuth;

// ── Title search via OMDB (free, no key needed for basic search) ──
// Falls back to a direct IMDb ID lookup hint if q looks like tt\d+
router.get('/search', auth, async (req, res) => {
  const { q = '', type = 'movie' } = req.query;
  if (!q) return res.json([]);

  try {
    // If it's already an IMDb ID just return it directly
    if (/^tt\d+$/i.test(q.trim())) {
      const meta = await fetchMeta(q.trim(), type);
      return res.json(meta ? [meta] : []);
    }

    // Use OMDB free search (no API key, s= endpoint, returns up to 10)
    const omdbRes = await axios.get('https://www.omdbapi.com/', {
      params: { apikey: 'trilogy', s: q, type: type === 'series' ? 'series' : 'movie', r: 'json' },
      timeout: 8000,
    }).catch(() => null);

    let results = omdbRes?.data?.Search || [];

    // If OMDB fails, try a fallback via suggestion API
    if (!results.length) {
      const sgRes = await axios.get(`https://v2.sg.media-imdb.com/suggestion/${encodeURIComponent(q[0].toLowerCase())}/${encodeURIComponent(q)}.json`, {
        timeout: 6000,
      }).catch(() => null);
      const raw = sgRes?.data?.d || [];
      results = raw
        .filter(r => r.id?.startsWith('tt') && (!type || (type === 'series' ? r.qid === 'tvSeries' : r.qid === 'movie')))
        .slice(0, 8)
        .map(r => ({ imdbID: r.id, Title: r.l, Year: r.y, Type: r.qid === 'tvSeries' ? 'series' : 'movie', Poster: r.i?.[0] || null }));
    }

    // Normalise and return
    return res.json(results.slice(0, 10).map(r => ({
      imdbId: r.imdbID || r.id,
      title:  r.Title  || r.l,
      year:   r.Year   || r.y,
      type:   r.Type === 'series' ? 'series' : 'movie',
      poster: r.Poster !== 'N/A' ? r.Poster : null,
    })));
  } catch (err) {
    console.error('[Player] search error:', err.message);
    res.json([]);
  }
});

// ── Stream list for a title ─────────────────────────────────
// GET /api/player/streams/movie/tt1234567
// GET /api/player/streams/series/tt1234567/1/2
router.get('/streams/:type/:imdbId/:season?/:episode?', auth, async (req, res) => {
  const { type, imdbId, season = 1, episode = 1 } = req.params;

  try {
    const raw = await torbox.searchStreams(imdbId, type, {
      season:  parseInt(season),
      episode: parseInt(episode),
    });

    if (!raw.length) return res.json([]);

    // Only show cached streams - uncached cannot play immediately.
    const { accepted: filtered, rejected } = filterResultsWithReasons(raw, PLAYER_PREFS);
    if (rejected.length) {
      console.log(`[Player] ${rejected.length} rejected for ${imdbId}`);
    }
    const ranked   = rankResults(filtered, PLAYER_PREFS);

    const streams = ranked.slice(0, 15).map(t => {
      const name  = t.name || t.title || 'Unknown';
      const res   = detectResolution(name) || '?';
      const feats = t._features || {};
      const tags  = [];
      if (feats.remux)        tags.push('REMUX');
      if (feats.bluray)       tags.push('BluRay');
      if (feats.webdl)        tags.push('WEB-DL');
      if (feats.webrip)       tags.push('WEBRip');
      if (feats.hevc)         tags.push('HEVC');
      if (feats.dolbyVision)  tags.push('DV');
      else if (feats.hdrPlus) tags.push('HDR10+');
      else if (feats.hdr)     tags.push('HDR');
      if (feats.atmos)        tags.push('Atmos');
      else if (feats.trueHD)  tags.push('TrueHD');

      return {
        id:       t.id || t.hash,
        kind:     t.kind || 'torrent',
        hash:     t.hash,
        fileId:   t.fileId || t.fileIdx || 0,
        name:     name,
        title:    `${res}${tags.length ? ' · ' + tags.join(' ') : ''}`,
        size:     t.size ? `${(t.size / 1e9).toFixed(1)} GB` : '?',
        score:    t._score || 0,
        cached:   t.cached || false,
        resolution: res,
        features: feats,
        playUrl:  `/api/player/play/${t.kind || 'torrent'}/${encodeURIComponent(torbox.encodeSourceRef(t))}/${t.fileId || t.fileIdx || 0}`,
      };
    });

    res.json(streams);
  } catch (err) {
    console.error('[Player] streams error:', err.message);
    res.json([]);
  }
});

// ── Play redirect ───────────────────────────────────────────
// Resolves a source ref -> TorBox CDN URL and redirects.
router.get('/play/:kind/:ref/:fileId', auth, async (req, res) => {
  const { kind, ref, fileId } = req.params;

  try {
    const url = await torbox.getStreamUrlBySource(kind, decodeURIComponent(ref), parseInt(fileId) || 0);
    if (!url) return res.status(404).json({ error: 'Stream URL not available' });
    res.setHeader('Cache-Control', 'no-store');
    res.redirect(302, url);
  } catch (err) {
    console.error(`[Player] play error kind=${kind} ref=${ref} fileId=${fileId}:`, err.message);
    res.status(500).json({ error: 'Failed to get stream URL' });
  }
});

// Backward-compatible torrent-only route.
router.get('/play/:hash/:fileId', auth, async (req, res) => {
  const { hash, fileId } = req.params;

  try {
    const url = await torbox.getStreamUrlByHash(hash, parseInt(fileId) || 0, 'torrent');
    if (!url) return res.status(404).json({ error: 'Stream URL not available' });
    res.setHeader('Cache-Control', 'no-store');
    res.redirect(302, url);
  } catch (err) {
    console.error(`[Player] play error hash=${hash} fileId=${fileId}:`, err.message);
    res.status(500).json({ error: 'Failed to get stream URL' });
  }
});

// ── Meta helper ────────────────────────────────────────────
async function fetchMeta(imdbId, type) {
  try {
    const r = await axios.get('https://www.omdbapi.com/', {
      params: { apikey: 'trilogy', i: imdbId, r: 'json' },
      timeout: 6000,
    });
    const d = r.data;
    if (d.Response === 'False') return null;
    return {
      imdbId,
      title:  d.Title,
      year:   d.Year,
      type:   d.Type === 'series' ? 'series' : 'movie',
      poster: d.Poster !== 'N/A' ? d.Poster : null,
    };
  } catch { return null; }
}

module.exports = router;

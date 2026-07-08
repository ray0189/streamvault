// src/addon/streams.js - main stream handler pipeline

const crypto             = require('crypto');
const torbox             = require('../api/torbox');
const { filterResultsWithReasons }  = require('../filters/quality');
const { rankResults }    = require('../scoring/rank');
const cache              = require('../cache/store');
const { detectResolution } = require('../filters/quality');
const { absoluteUrl }    = require('../config/public-url');

const SHOW_UNCACHED_IF_EMPTY = true;
const UNCACHED_FALLBACK_LIMIT = 5;
// How many top streams get their TorBox CDN URL pre-resolved into the
// playback cache while the user is still looking at the stream list.
const PREWARM_TOP_N = 3;

function parseId(type, id) {
  if (type === 'series') {
    const [imdbId, season, episode] = id.split(':');
    return { imdbId, season: parseInt(season), episode: parseInt(episode) };
  }
  return { imdbId: id };
}

function prefsSignature(prefs = {}) {
  return crypto
    .createHash('sha1')
    .update(JSON.stringify({
      minQuality: prefs.minQuality,
      cachedOnly: prefs.cachedOnly,
      blockedTags: prefs.blockedTags,
      scoring: prefs.scoring,
    }))
    .digest('hex')
    .slice(0, 10);
}

function formatStream(torrent, profile, req) {
  const name  = torrent.name || torrent.title || 'Unknown';
  const res   = detectResolution(name) || '?';
  const score = torrent._score || 0;
  const feats = torrent._features || {};
  const fileId = Number(torrent.fileId ?? torrent.fileIdx ?? 0) || 0;
  const kind = torrent.kind || 'torrent';
  const sourceRef = encodeURIComponent(torbox.encodeSourceRef(torrent));

  const tags = [];
  if (torrent.cached)       tags.push('Cached');
  if (kind === 'usenet')     tags.push('Usenet');
  if (feats.remux)        tags.push('REMUX');
  if (feats.bluray)       tags.push('BluRay');
  if (feats.webdl)        tags.push('WEB-DL');
  if (feats.hevc)         tags.push('HEVC');
  if (feats.dolbyVision)  tags.push('DV');
  else if (feats.hdrPlus) tags.push('HDR10+');
  else if (feats.hdr)     tags.push('HDR');
  if (feats.atmos)        tags.push('Atmos');
  else if (feats.trueHD)  tags.push('TrueHD');

  const sizeGB = torrent.size ? `${(torrent.size / 1e9).toFixed(1)} GB` : '';
  const source = torrent.source ? `\n${torrent.source}` : '';

  return {
    name:        `${torrent.cached ? '⚡' : '⏳'} ${res} ${tags.join(' ')}`.trim(),
    description: `${name}\n${sizeGB ? `💾 ${sizeGB}` : ''}  ★ ${score}${source}`.trim(),
    // Always resolve fresh via proxy — never cache the CDN URL
    url: absoluteUrl(`/proxy/stream/${kind}/${sourceRef}/${fileId}`, req),
    behaviorHints: {
      notWebReady: false,
      bingeGroup: `torbox-${kind}-${profile.configId}`,
    },
  };
}

// Fire-and-forget: resolve TorBox CDN URLs for the top cached streams into the
// playback cache so the user's click is served straight from Redis. Refs are
// parsed back out of the proxy URLs, so this works for freshly built lists and
// for lists served from the stream cache alike. getStreamUrlBySource checks
// the playback cache first, so already-warm entries cost nothing.
function prewarmPlaybackUrls(streams = []) {
  const targets = streams
    .filter(s => typeof s.url === 'string' && s.name?.startsWith('⚡'))
    .slice(0, PREWARM_TOP_N);
  for (const s of targets) {
    const m = s.url.match(/\/proxy\/stream\/([^/]+)\/([^/]+)\/(\d+)(?:\?|$)/);
    if (!m) continue;
    torbox.getStreamUrlBySource(m[1], decodeURIComponent(m[2]), parseInt(m[3], 10) || 0)
      .catch(err => console.warn('[Prewarm] failed:', err.message));
  }
}

async function handleStream(type, rawId, profile, req) {
  const { imdbId, season, episode } = parseId(type, rawId);
  const prefs    = profile.prefs;
  const cacheKey = cache.cacheKey('stream', profile.configId, prefsSignature(prefs), rawId);

  // ── Cache check (metadata only, no CDN URLs) ──────────────
  const cached = await cache.getStreams(cacheKey);
  if (cached) {
    console.log(`[Stream] Cache HIT — ${cacheKey}`);
    prewarmPlaybackUrls(cached);
    return cached;
  }

  // ── TorBox search ─────────────────────────────────────────
  console.log(`[Stream] Searching TorBox for ${imdbId} (${type})`);
  const raw = await torbox.searchStreams(imdbId, type, { season, episode });

  if (!raw.length) {
    console.log(`[Stream] No results from TorBox for ${imdbId}`);
    return [];
  }

  // ── Filter + rank ─────────────────────────────────────────
  let { accepted: filtered, rejected } = filterResultsWithReasons(raw.slice(0, 150), prefs);
  console.log(`[Stream] ${raw.length} raw -> ${filtered.length} after filter (${rejected.length} rejected)`);

  if (!filtered.length && SHOW_UNCACHED_IF_EMPTY) {
    filtered = raw
      .filter(t => !t.cached)
      .sort((a, b) => (b.seeders || 0) - (a.seeders || 0))
      .slice(0, UNCACHED_FALLBACK_LIMIT)
      .map(t => ({ ...t, name: `⏳ Uncached - Queue to TorBox | ${t.name}` }));
    console.log(`[Stream] uncached fallback -> ${filtered.length} shown`);
  }
  for (const item of rejected.slice(0, 12)) {
    console.log(`[Reject] ${item.reason} cached=${item.cached} hash=${item.hash || '-'} name="${item.name}"`);
  }
  if (!filtered.length) return [];

  const ranked  = rankResults(filtered, prefs);
  const top5    = ranked.slice(0, 8);

  // ── Format with proxy URLs (always fresh at play time) ────
  const streams = top5.map(t => formatStream(t, profile, req));

  // ── Cache metadata only ───────────────────────────────────
  await cache.setStreams(cacheKey, streams);
  prewarmPlaybackUrls(streams);
  return streams;
}

module.exports = { handleStream };

// src/scoring/rank.js - preference-based scoring engine

const defaults = require('../config/defaults');
const { detectResolution } = require('../filters/quality');

// Feature detection patterns
const FEATURE_PATTERNS = {
  hevc:        /\b(x265|hevc|h\.?265)\b/i,
  hdr:         /\bHDR(?!10\+)\b|\bHDR10\b/i,
  hdrPlus:     /\bHDR10\+\b/i,
  dolbyVision: /\b(DV|DoVi|Dolby[\s.]?Vision)\b/i,
  atmos:       /\b(Atmos|TrueHD[\s.]Atmos)\b/i,
  trueHD:      /\bTrueHD\b/i,
  bluray:      /\b(BluRay|Blu-Ray|BDRip|BDRemux)\b/i,
  remux:       /\bREMUX\b/i,
  webdl:       /\bWEB-?DL\b/i,
  webrip:      /\bWEBRip\b/i,
  h264:        /\b(x264|h\.?264|AVC)\b/i,
  dts:         /\bDTS(-HD|-X|-MA)?\b/i,
};

/**
 * Detect which features a torrent name contains
 * Returns an object like { hevc: true, hdr: false, ... }
 */
function detectFeatures(name = '') {
  const result = {};
  for (const [key, pattern] of Object.entries(FEATURE_PATTERNS)) {
    result[key] = pattern.test(name);
  }

  // Resolution bonus
  const res = detectResolution(name);
  result.resolution4K = res === '2160p';

  return result;
}

/**
 * Score a single torrent against the user's prefs
 * @param {object} torrent  TorBox result object
 * @param {object} prefs    user profile prefs
 * @returns {number}        total score
 */
function scoreTorrent(torrent, prefs = {}) {
  const weights = { ...defaults.scoring, ...(prefs.scoring || {}) };
  const name     = torrent.name || torrent.title || '';
  const features = detectFeatures(name);
  const seeders = Number(torrent.seeders ?? torrent.seeds ?? 0) || 0;

  let score = 0;

  if (torrent.cached) score += 100;
  if (torrent.fromLibrary) score += 8;
  if (torrent.matchQuality === 'episode') score += 18;
  if (torrent.matchQuality === 'single-video-pack') score += 6;

  for (const [feature, active] of Object.entries(features)) {
    if (active && weights[feature]) {
      score += weights[feature];
    }
  }

  // Seed count bonus (log-scaled so it doesn't dominate)
  if (seeders > 0) {
    score += Math.min(Math.log10(seeders + 1) * 4, 14);
  }

  score += sizeScore(torrent, features);

  return Math.round(score * 10) / 10;
}

function sizeScore(torrent, features = detectFeatures(torrent.name || torrent.title || '')) {
  const size = torrent.selectedFile?.size || torrent.size || 0;
  const sizeGB = size / 1e9;
  if (!sizeGB) return 0;

  const name = torrent.name || torrent.title || '';
  const res = detectResolution(name);
  const isSeries = torrent.mediaType === 'series';

  if (sizeGB < 0.15) return -40;
  if (isSeries && sizeGB < 0.25) return -18;
  if (!isSeries && sizeGB < 0.6) return -18;

  if (res === '2160p') {
    if (sizeGB < 2) return -10;
    if (sizeGB > 120) return -6;
    return features.remux ? 6 : 4;
  }

  if (res === '1080p') {
    if (isSeries && sizeGB >= 0.7 && sizeGB <= 12) return 5;
    if (!isSeries && sizeGB >= 2 && sizeGB <= 45) return 5;
    if (sizeGB > 80) return -5;
  }

  if (res === '720p' && sizeGB > 20) return -4;
  return 1;
}

/**
 * Sort an array of (filtered) torrents by score descending
 * Attaches ._score to each for debugging
 */
function rankResults(torrents = [], prefs = {}) {
  return torrents
    .map(t => ({ ...t, _score: scoreTorrent(t, prefs), _features: detectFeatures(t.name || t.title || '') }))
    .sort((a, b) => {
      if (!!a.cached !== !!b.cached) return a.cached ? -1 : 1;
      return b._score - a._score;
    });
}

module.exports = { rankResults, scoreTorrent, detectFeatures, sizeScore };

// src/config/defaults.js - default preferences for new user configs
const { DEFAULT_MIN_QUALITY, DEFAULT_CACHED_ONLY, DEFAULT_LANGUAGE } = require('./env');

module.exports = {
  // Minimum quality floor — results below this are dropped
  minQuality: DEFAULT_MIN_QUALITY,          // '1080p' | '2160p'

  // If true, only streams TorBox has already cached are returned
  cachedOnly: DEFAULT_CACHED_ONLY,
  language: DEFAULT_LANGUAGE,

  // ── Blocked release types (always excluded) ───────────────
  blockedTags: [
    'CAM', 'CAMRIP', 'HDCAM', 'HD-CAM', 'TS', 'HDTS', 'TELESYNC',
    'TC', 'HDTC', 'TELECINE', 'SCR', 'SCREENER', 'DVDSCR', 'R5',
    'WORKPRINT', 'WP', 'HC',
  ],

  // ── Scoring weights (higher = more preferred) ─────────────
  scoring: {
    hevc:        10,   // x265 / HEVC encodes
    hdr:         8,    // HDR10 / HDR10+
    dolbyVision: 10,   // Dolby Vision
    atmos:       6,    // Dolby Atmos
    trueHD:      5,    // TrueHD audio
    bluray:      7,    // BluRay source
    remux:       9,    // REMUX (lossless)
    webdl:       6,    // WEB-DL
    webrip:      3,    // WEBRip
    hdrPlus:     9,    // HDR10+
    dts:         3,    // DTS audio
    h264:        1,    // x264 — lower score
    resolution4K:12,   // 4K gets a bonus
  },

  // ── Quality resolution ordering ───────────────────────────
  resolutionRank: {
    '2160p': 5,
    '4k':    5,
    '1440p': 4,
    '1080p': 3,
    '720p':  2,
    '480p':  1,
    '360p':  0,
  },
};

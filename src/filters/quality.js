// src/filters/quality.js - release quality filtering

const defaults = require('../config/defaults');

// Regex patterns for detecting resolution from a title string
const RES_PATTERNS = [
  { regex: /\b(2160p|4k|uhd)\b/i,  res: '2160p' },
  { regex: /\b1440p\b/i,            res: '1440p' },
  { regex: /\b1080p\b/i,            res: '1080p' },
  { regex: /\b720p\b/i,             res: '720p'  },
  { regex: /\b480p\b/i,             res: '480p'  },
];

/**
 * Extract resolution string from a torrent name
 */
function detectResolution(name = '') {
  for (const { regex, res } of RES_PATTERNS) {
    if (regex.test(name)) return res;
  }
  return null;
}

function escapeRegex(value) {
  return String(value).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

/**
 * Returns true if the torrent name contains any blocked tag
 */
function isBlocked(name = '', blockedTags = defaults.blockedTags) {
  const upper = name.toUpperCase();
  return blockedTags.some(tag => {
    // Match as a word boundary so "WEB-DL" doesn't match "TS" inside "EXTRAS"
    const pattern = new RegExp(`(^|[\\s.\\-_\\[\\(])${escapeRegex(tag)}([\\s.\\-_\\]\\)]|$)`, 'i');
    return pattern.test(upper);
  });
}

const BAD_FILE_PATTERNS = [
  /\bsample\b/i,
  /\btrailer\b/i,
  /\bextras?\b/i,
  /\bfeaturette\b/i,
  /\bproof\b/i,
  /\bpassword(ed)?\b/i,
  /\b(fake|camrip|hdcam|hdts|telesync|telecine|dvdscr|screener|workprint)\b/i,
];

const ARCHIVE_OR_EXECUTABLE = /\.(zip|rar|7z|tar|gz|bz2|xz|iso|exe|msi|apk|bat|cmd|scr|com)(\b|$)/i;
const VIDEO_EXTENSIONS = /\.(mkv|mp4|m4v|avi|mov|wmv|webm|mpg|mpeg|m2ts|ts)(\b|$)/i;

function fileNameFor(item = {}) {
  return item.name || item.short_name || item.raw_title || item.title || '';
}

function hasVideoExtension(item = {}) {
  const name = fileNameFor(item);
  const mimetype = item.mimetype || item.mime || '';
  return /^video\//i.test(mimetype) || VIDEO_EXTENSIONS.test(name);
}

function hasBadFilePattern(name = '') {
  return BAD_FILE_PATTERNS.some(pattern => pattern.test(name));
}

function isArchiveOrExecutable(name = '') {
  return ARCHIVE_OR_EXECUTABLE.test(name);
}

/**
 * Returns true if the resolution meets the user's minimum floor
 */
function meetsMinQuality(name = '', minQuality = '1080p') {
  const res = detectResolution(name);
  if (!res) return false; // unknown resolution — block it

  const rank   = defaults.resolutionRank;
  const minRank = rank[minQuality.toLowerCase()] ?? rank['1080p'];
  const resRank = rank[res.toLowerCase()] ?? 0;

  return resRank >= minRank;
}

function explainRejection(torrent = {}, prefs = {}) {
  const minQuality  = prefs.minQuality  || defaults.minQuality;
  const blockedTags = prefs.blockedTags || defaults.blockedTags;
  const cachedOnly  = prefs.cachedOnly  !== undefined ? prefs.cachedOnly : defaults.cachedOnly;
  const name = torrent.name || torrent.title || torrent.raw_title || '';
  const selectedName = torrent.selectedFile?.name || torrent.selectedFile?.short_name || '';
  const candidateName = selectedName || name;

  if (torrent.fileRejectReason) return torrent.fileRejectReason;
  if (cachedOnly && !torrent.cached) return 'uncached';
  if (isArchiveOrExecutable(candidateName)) return 'archive-or-executable';
  if (isBlocked(candidateName, blockedTags) || isBlocked(name, blockedTags)) return 'blocked-release-tag';
  if (hasBadFilePattern(candidateName)) return 'sample-trailer-or-fake';
  if (torrent.selectedFile && !hasVideoExtension(torrent.selectedFile)) return 'non-video-file';
  if (!meetsMinQuality(name, minQuality)) return 'below-min-quality-or-unknown-resolution';

  return null;
}

/**
 * Main filter — returns only torrents that pass all quality gates
 * @param {Array}  torrents  raw TorBox results
 * @param {object} prefs     user profile prefs
 */
function filterResults(torrents = [], prefs = {}) {
  return torrents.filter(t => !explainRejection(t, prefs));
}

function filterResultsWithReasons(torrents = [], prefs = {}) {
  const accepted = [];
  const rejected = [];

  for (const torrent of torrents) {
    const reason = explainRejection(torrent, prefs);
    if (reason) {
      rejected.push({
        hash: torrent.hash,
        name: torrent.name || torrent.title || torrent.raw_title || 'Unknown',
        cached: !!torrent.cached,
        reason,
      });
    } else {
      accepted.push(torrent);
    }
  }

  return { accepted, rejected };
}

module.exports = {
  filterResults,
  filterResultsWithReasons,
  detectResolution,
  isBlocked,
  meetsMinQuality,
  explainRejection,
  hasVideoExtension,
  hasBadFilePattern,
  isArchiveOrExecutable,
};

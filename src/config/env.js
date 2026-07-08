// src/config/env.js — central environment config
function envBool(name, fallback) {
  const value = process.env[name];
  if (value === undefined || value === '') return fallback;
  return !['0', 'false', 'no', 'off'].includes(String(value).toLowerCase());
}

module.exports = {
  PORT:              process.env.PORT              || 7000,
  HOST:              process.env.HOST              || '0.0.0.0',
  NODE_ENV:          process.env.NODE_ENV          || 'development',
  TORBOX_API_KEY:    process.env.TORBOX_API_KEY    || '',
  TORBOX_API_URL:    process.env.TORBOX_API_URL    || 'https://api.torbox.app/v1/api',
  TORBOX_SEARCH_API_URL: process.env.TORBOX_SEARCH_API_URL || 'https://search-api.torbox.app',
  TORBOX_TIMEOUT_MS: parseInt(process.env.TORBOX_TIMEOUT_MS, 10) || 10000,
  TORBOX_RETRIES:    parseInt(process.env.TORBOX_RETRIES, 10)    || 2,
  TORBOX_ENABLE_NATIVE_SEARCH: envBool('TORBOX_ENABLE_NATIVE_SEARCH', true),
  TORBOX_ENABLE_USENET: envBool('TORBOX_ENABLE_USENET', true),
  TORBOX_SEARCH_USER_ENGINES: envBool('TORBOX_SEARCH_USER_ENGINES', false),
  TORBOX_PROVIDER_PRIORITY: process.env.TORBOX_PROVIDER_PRIORITY || 'torbox-torrent,torbox-usenet,library,torrentio,knightcrawler',
  EXTERNAL_TORRENT_FALLBACK: envBool('EXTERNAL_TORRENT_FALLBACK', true),
  TORRENTIO_ENABLED: envBool('TORRENTIO_ENABLED', true),
  KNIGHTCRAWLER_ENABLED: envBool('KNIGHTCRAWLER_ENABLED', true),
  SECRET_KEY:        process.env.SECRET_KEY        || 'change-me',
  STREAM_CACHE_TTL:  parseInt(process.env.STREAM_CACHE_TTL)  || 300,
  // TorBox CDN links stay valid ~3h; keep well inside that window.
  PLAYBACK_URL_TTL:  parseInt(process.env.PLAYBACK_URL_TTL)  || 2700,
  META_CACHE_TTL:    parseInt(process.env.META_CACHE_TTL)    || 3600,
  ADMIN_PASSWORD:    process.env.ADMIN_PASSWORD    || 'changeme',
  PUBLIC_BASE_URL:   process.env.PUBLIC_BASE_URL   || '',
  NAS_LOCAL_IP:      process.env.NAS_LOCAL_IP      || '',
  TAILSCALE_HOST:    process.env.TAILSCALE_HOST    || '',
  REDIS_URL:         process.env.REDIS_URL         || 'redis://127.0.0.1:6379',
  DEFAULT_MIN_QUALITY: process.env.DEFAULT_MIN_QUALITY || '1080p',
  DEFAULT_CACHED_ONLY: process.env.DEFAULT_CACHED_ONLY !== 'false',
  DEFAULT_LANGUAGE:    process.env.DEFAULT_LANGUAGE || 'en',
};

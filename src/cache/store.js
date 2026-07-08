const NodeCache = require('node-cache');
const Redis = require('ioredis');
const { STREAM_CACHE_TTL, META_CACHE_TTL, PLAYBACK_URL_TTL, REDIS_URL } = require('../config/env');

const streamCache = new NodeCache({ stdTTL: STREAM_CACHE_TTL, checkperiod: 60 });
const metaCache = new NodeCache({ stdTTL: META_CACHE_TTL, checkperiod: 120 });
const playbackCache = new NodeCache({ stdTTL: PLAYBACK_URL_TTL, checkperiod: 120 });

let redis;
let redisStatus = 'disabled';
try {
  // Skip Redis in tests: an open connection keeps the event loop (and the
  // test runner) alive after the suite finishes.
  if (REDIS_URL && process.env.NODE_ENV !== 'test') {
    redisStatus = 'connecting';
    redis = new Redis(REDIS_URL, {
      lazyConnect: true,
      connectTimeout: 2000,
      maxRetriesPerRequest: 1,
      enableOfflineQueue: false,
    });
    redis.on('connect', () => { redisStatus = 'connected'; });
    redis.on('error', () => { redisStatus = redisStatus === 'connected' ? 'error' : 'disconnected'; });
    redis.on('close', () => { if (redisStatus !== 'disabled') redisStatus = 'disconnected'; });
    redis.connect()
      .then(() => console.log('[Redis] Connected'))
      .catch(() => { console.warn('[Redis] Not available, using memory cache'); redisStatus = 'disconnected'; });
  }
} catch(e) { redis = null; }

function cacheKey(...parts) { return parts.join(':'); }

async function getStreams(key) {
  if (redisStatus === 'connected') {
    try {
      const v = await redis.get('stream:' + key);
      if (v) return JSON.parse(v);
    } catch(e) {}
  }
  return streamCache.get(key) || null;
}

async function setStreams(key, value) {
  if (redisStatus === 'connected') {
    try { await redis.setex('stream:' + key, STREAM_CACHE_TTL, JSON.stringify(value)); } catch(e) {}
  }
  streamCache.set(key, value);
}

async function getPlaybackUrl(key) {
  if (redisStatus === 'connected') {
    try {
      const v = await redis.get('play:' + key);
      if (v) return v;
    } catch(e) {}
  }
  return playbackCache.get(key) || null;
}

async function setPlaybackUrl(key, url, ttl = PLAYBACK_URL_TTL) {
  if (redisStatus === 'connected') {
    try { await redis.setex('play:' + key, ttl, url); } catch(e) {}
  }
  playbackCache.set(key, url, ttl);
}

function getMeta(key) { return metaCache.get(key) || null; }
function setMeta(key, value) { metaCache.set(key, value); }

function clearStreams() {
  streamCache.flushAll();
}

// Full flush: in-memory caches plus every stream:*/play:* key in Redis.
async function flushCaches() {
  streamCache.flushAll();
  metaCache.flushAll();
  playbackCache.flushAll();
  let redisCleared = 0;
  if (redisStatus === 'connected') {
    for (const pattern of ['stream:*', 'play:*']) {
      try {
        let cursor = '0';
        do {
          const [next, keys] = await redis.scan(cursor, 'MATCH', pattern, 'COUNT', 500);
          cursor = next;
          if (keys.length) redisCleared += await redis.del(...keys);
        } while (cursor !== '0');
      } catch (e) {
        console.warn('[Cache] Redis flush failed:', e.message);
      }
    }
  }
  return { redisCleared, redis: redisStatus };
}

function stats() {
  return {
    streams: streamCache.getStats(),
    meta: metaCache.getStats(),
    playback: playbackCache.getStats(),
    redis: redisStatus,
    ttl: { streams: STREAM_CACHE_TTL, meta: META_CACHE_TTL, playback: PLAYBACK_URL_TTL },
  };
}

module.exports = { cacheKey, getStreams, setStreams, getPlaybackUrl, setPlaybackUrl, getMeta, setMeta, clearStreams, flushCaches, stats, redis };

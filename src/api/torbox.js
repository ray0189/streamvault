const axios = require('axios');
const FormData = require('form-data');
const {
  TORBOX_API_KEY,
  TORBOX_API_URL,
  TORBOX_SEARCH_API_URL,
  TORBOX_TIMEOUT_MS,
  TORBOX_RETRIES,
  TORBOX_ENABLE_NATIVE_SEARCH,
  TORBOX_ENABLE_USENET,
  TORBOX_SEARCH_USER_ENGINES,
  TORBOX_PROVIDER_PRIORITY,
  EXTERNAL_TORRENT_FALLBACK,
  TORRENTIO_ENABLED,
  KNIGHTCRAWLER_ENABLED,
} = require('../config/env');
const {
  hasVideoExtension,
  hasBadFilePattern,
  isArchiveOrExecutable,
} = require('../filters/quality');
const { PLAYBACK_URL_TTL } = require('../config/env');
const cacheStore = require('../cache/store');

const client = axios.create({
  baseURL: TORBOX_API_URL,
  headers: { Authorization: 'Bearer ' + TORBOX_API_KEY },
  timeout: TORBOX_TIMEOUT_MS,
});
const defaultClientGet = client.get.bind(client);

const searchClient = axios.create({
  baseURL: TORBOX_SEARCH_API_URL,
  headers: { Authorization: 'Bearer ' + TORBOX_API_KEY },
  timeout: Math.min(TORBOX_TIMEOUT_MS, 7000),
});
const defaultSearchClientGet = searchClient.get.bind(searchClient);
const defaultExternalGet = axios.get.bind(axios);
let externalGet = defaultExternalGet;

// External indexers are torrent-only fallbacks. Keep timeouts short so one slow
// provider cannot block native TorBox results for long.
const INDEXERS = [
  { key: 'torrentio',     name: 'Torrentio',     base: 'https://torrentio.strem.fun',        timeout: 4500 },
  { key: 'knightcrawler', name: 'Knightcrawler', base: 'https://knightcrawler.elfhosted.com', timeout: 5000 },
];

const DEFAULT_PROVIDER_PRIORITY = ['torbox-torrent', 'torbox-usenet', 'library', 'torrentio', 'knightcrawler'];
const PROVIDER_INFO = {
  'torbox-torrent': {
    group: 'torbox',
    label: 'TorBox Native Torrent Search',
    source: 'torbox-torrent-search',
  },
  'torbox-usenet': {
    group: 'torbox',
    label: 'TorBox Native Usenet Search',
    source: 'torbox-usenet-search',
  },
  library: {
    group: 'torbox',
    label: 'TorBox Library/My List',
    source: 'torbox-library',
  },
  torrentio: {
    group: 'external',
    label: 'Torrentio fallback',
    source: 'Torrentio',
  },
  knightcrawler: {
    group: 'external',
    label: 'Knightcrawler fallback',
    source: 'Knightcrawler',
  },
};
const PROVIDER_ALIASES = {
  'torbox-torrent-search': 'torbox-torrent',
  torrent: 'torbox-torrent',
  torrents: 'torbox-torrent',
  'native-torrent': 'torbox-torrent',
  'torbox-usenet-search': 'torbox-usenet',
  usenet: 'torbox-usenet',
  'native-usenet': 'torbox-usenet',
  mylist: 'library',
  'my-list': 'library',
  torboxlibrary: 'library',
  'torbox-library': 'library',
  torrentio: 'torrentio',
  knightcrawler: 'knightcrawler',
  knight: 'knightcrawler',
  'knight-crawler': 'knightcrawler',
};

const KIND = {
  torrent: {
    searchPath: 'torrents',
    listPath: '/torrents/mylist',
    checkPath: '/torrents/checkcached',
    createPath: '/torrents/createtorrent',
    requestPath: '/torrents/requestdl',
    idParam: 'torrent_id',
    createIdKeys: ['torrent_id', 'id'],
    listTtlMs: 600000,
  },
  usenet: {
    searchPath: 'usenet',
    listPath: '/usenet/mylist',
    checkPath: '/usenet/checkcached',
    createPath: '/usenet/createusenetdownload',
    requestPath: '/usenet/requestdl',
    idParam: 'usenet_id',
    createIdKeys: ['usenetdownload_id', 'usenet_id', 'id'],
    listTtlMs: 30000,
  },
};

const INDEXER_COOLDOWN_MS = 300000;
const SEARCH_COOLDOWN_MS = 300000;
const SEARCH_CACHE_TTL_MS = 120000;
const NATIVE_SEARCH_CACHE_TTL_MS = 15 * 60 * 1000;
const NATIVE_SEARCH_429_BACKOFF_MS = 10 * 60 * 1000;
const SEARCH_RATE_WINDOW_SHORT_MS = 60 * 1000;
const SEARCH_RATE_WINDOW_LONG_MS = 5 * 60 * 1000;
const AVAILABILITY_TTL_MS = 600000;
const NATIVE_RESULT_TARGET = 8;
const MAX_RECENT_EVENTS = 100;
const MAX_SEARCH_REQUEST_LOG = 500;

const indexerHealth = {};
const providerHealth = {};
const listCaches = {
  torrent: { data: null, ts: 0, loading: null },
  usenet: { data: null, ts: 0, loading: null },
};
const downloadIdCaches = { torrent: {}, usenet: {} };
const searchCache = new Map();
const nativeSearchCache = new Map();
const nativeSearchInflight = new Map();
const availabilityCache = new Map();
const recentEvents = [];
const searchApiStats = {
  requestLog: [],
  cacheHits: 0,
  backoffHits: 0,
  coalesced: 0,
  statusCounts: {},
  lastSourceCounts: null,
  lastProviderRun: null,
};
const indexerStats = {};

function recordEvent(type, payload = {}) {
  recentEvents.unshift({ type, ts: new Date().toISOString(), ...payload });
  if (recentEvents.length > MAX_RECENT_EVENTS) recentEvents.pop();
}

function boolish(value, fallback = false) {
  if (value === undefined || value === null || value === '') return fallback;
  if (typeof value === 'boolean') return value;
  if (typeof value === 'number') return value > 0;
  return ['1', 'true', 'yes', 'cached', 'hit'].includes(String(value).toLowerCase());
}

function normalizeKind(kind = 'torrent') {
  return kind === 'usenet' && TORBOX_ENABLE_USENET ? 'usenet' : 'torrent';
}

function isHealthy(name, bucket = indexerHealth) {
  const h = bucket[name];
  return !h || Date.now() > h.retryAt;
}

function durationLabel(ms) {
  if (ms < 60000) return `${Math.max(1, Math.round(ms / 1000))}s`;
  return `${Math.round(ms / 60000)}min`;
}

function markFailed(name, message, bucket = indexerHealth, cooldown = INDEXER_COOLDOWN_MS) {
  bucket[name] = { retryAt: Date.now() + cooldown, message };
  recordEvent('provider_failed', { name, message, retryAt: bucket[name].retryAt });
  console.log(`[${name}] Unhealthy for ${durationLabel(cooldown)}: ${message}`);
}

function markOk(name, bucket = indexerHealth) {
  delete bucket[name];
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function isRetriable(error) {
  const status = error?.response?.status;
  return !status || status === 408 || status === 429 || status >= 500;
}

async function withRetry(label, fn, attempts = TORBOX_RETRIES) {
  let lastError;
  for (let attempt = 1; attempt <= Math.max(1, attempts); attempt += 1) {
    try {
      return await fn();
    } catch (error) {
      lastError = error;
      const status = error?.response?.status;
      const detail = error?.response?.data?.detail || error.message;
      recordEvent('torbox_request_failed', { label, attempt, status, detail });
      if (attempt >= attempts || !isRetriable(error)) break;
      await sleep(250 * attempt);
    }
  }
  throw lastError;
}

async function torboxGet(path, config = {}, label = path) {
  return withRetry(label, () => client.get(path, config));
}

async function torboxPost(path, body, config = {}, label = path) {
  return withRetry(label, () => client.post(path, body, config));
}

function cacheGet(map, key, ttl) {
  const hit = map.get(key);
  if (!hit || Date.now() - hit.ts > ttl) {
    map.delete(key);
    return null;
  }
  return hit.value;
}

function cacheSet(map, key, value) {
  map.set(key, { value, ts: Date.now() });
}

function canonicalProviderKey(value = '') {
  const key = String(value).trim().toLowerCase().replace(/_/g, '-');
  return PROVIDER_INFO[key] ? key : PROVIDER_ALIASES[key] || null;
}

function parseProviderPriority(raw = TORBOX_PROVIDER_PRIORITY) {
  const requested = String(raw || '')
    .split(',')
    .map(canonicalProviderKey)
    .filter(Boolean);
  const ordered = [];
  for (const provider of [...requested, ...DEFAULT_PROVIDER_PRIORITY]) {
    if (!ordered.includes(provider)) ordered.push(provider);
  }

  return [
    ...ordered.filter(provider => PROVIDER_INFO[provider]?.group === 'torbox'),
    ...ordered.filter(provider => PROVIDER_INFO[provider]?.group === 'external'),
  ];
}

function providerEnabled(provider, overrides = {}) {
  const nativeSearch = overrides.TORBOX_ENABLE_NATIVE_SEARCH ?? TORBOX_ENABLE_NATIVE_SEARCH;
  const usenet = overrides.TORBOX_ENABLE_USENET ?? TORBOX_ENABLE_USENET;
  const externalFallback = overrides.EXTERNAL_TORRENT_FALLBACK ?? EXTERNAL_TORRENT_FALLBACK;
  const torrentio = overrides.TORRENTIO_ENABLED ?? TORRENTIO_ENABLED;
  const knightcrawler = overrides.KNIGHTCRAWLER_ENABLED ?? KNIGHTCRAWLER_ENABLED;

  if (provider === 'torbox-torrent') return nativeSearch;
  if (provider === 'torbox-usenet') return nativeSearch && usenet;
  if (provider === 'library') return true;
  if (provider === 'torrentio') return externalFallback && torrentio;
  if (provider === 'knightcrawler') return externalFallback && knightcrawler;
  return false;
}

function providerLabel(provider) {
  return PROVIDER_INFO[provider]?.label || provider || 'Unknown provider';
}

function providerConfig(rawPriority = TORBOX_PROVIDER_PRIORITY, overrides = {}) {
  const effectivePriority = parseProviderPriority(rawPriority);
  return {
    requestedPriority: rawPriority,
    effectivePriority,
    labels: effectivePriority.map(providerLabel),
    enabled: Object.fromEntries(DEFAULT_PROVIDER_PRIORITY.map(provider => [provider, providerEnabled(provider, overrides)])),
    externalFallback: overrides.EXTERNAL_TORRENT_FALLBACK ?? EXTERNAL_TORRENT_FALLBACK,
  };
}

function nativeSearchCacheKey(kind, imdbId, type, opts = {}, params = {}) {
  return [
    normalizeKind(kind),
    type,
    imdbId,
    opts.season || 0,
    opts.episode || 0,
    params.search_user_engines ? 'user-engines' : 'native-only',
    params.cached_only ? 'cached-only' : 'all',
  ].join(':');
}

function cloneNativeSearchItems(items = []) {
  return items.map(item => ({
    ...item,
    selectedFile: item.selectedFile ? { ...item.selectedFile } : item.selectedFile,
    files: Array.isArray(item.files) ? item.files.map(file => ({ ...file })) : item.files,
  }));
}

function getNativeSearchCache(key) {
  const entry = nativeSearchCache.get(key);
  if (!entry) return null;
  if (Date.now() > entry.expiresAt) {
    nativeSearchCache.delete(key);
    return null;
  }
  return entry;
}

function setNativeSearchCache(key, value, ttlMs, meta = {}) {
  nativeSearchCache.set(key, {
    value: cloneNativeSearchItems(value),
    expiresAt: Date.now() + ttlMs,
    ts: Date.now(),
    ...meta,
  });
}

function pruneNativeSearchCache() {
  const now = Date.now();
  for (const [key, entry] of nativeSearchCache.entries()) {
    if (now > entry.expiresAt) nativeSearchCache.delete(key);
  }
}

function retryAfterMs(headers = {}, fallbackMs = NATIVE_SEARCH_429_BACKOFF_MS) {
  const raw = headers['retry-after'] || headers['Retry-After'];
  const value = Array.isArray(raw) ? raw[0] : raw;
  if (!value) return fallbackMs;

  const seconds = Number(value);
  if (Number.isFinite(seconds)) return Math.max(1000, seconds * 1000);

  const date = Date.parse(value);
  if (Number.isFinite(date)) return Math.max(1000, date - Date.now());

  return fallbackMs;
}

function pruneSearchRequestLog(now = Date.now()) {
  searchApiStats.requestLog = searchApiStats.requestLog
    .filter(entry => now - entry.ts <= SEARCH_RATE_WINDOW_LONG_MS);
}

function recordSearchApiRequest(kind, status, ms, retryAfter = null) {
  const now = Date.now();
  const normalizedStatus = String(status || 'ERR');
  pruneSearchRequestLog(now);
  searchApiStats.requestLog.push({ ts: now, kind, status: normalizedStatus, ms, retryAfter });
  if (searchApiStats.requestLog.length > MAX_SEARCH_REQUEST_LOG) {
    searchApiStats.requestLog.splice(0, searchApiStats.requestLog.length - MAX_SEARCH_REQUEST_LOG);
  }
  searchApiStats.statusCounts[normalizedStatus] = (searchApiStats.statusCounts[normalizedStatus] || 0) + 1;
}

function currentSearchRequestRate() {
  const now = Date.now();
  pruneSearchRequestLog(now);
  const last60s = searchApiStats.requestLog.filter(entry => now - entry.ts <= SEARCH_RATE_WINDOW_SHORT_MS).length;
  const last5m = searchApiStats.requestLog.filter(entry => now - entry.ts <= SEARCH_RATE_WINDOW_LONG_MS).length;
  return {
    requestsLast60s: last60s,
    requestsPerMinuteLast60s: last60s,
    requestsLast5m: last5m,
    requestsPerMinuteLast5m: Math.round((last5m / 5) * 100) / 100,
  };
}

function providerKeyForItem(item = {}) {
  if (item.provider && PROVIDER_INFO[item.provider]) return item.provider;
  const source = item.source || item._source || '';
  if (source === 'torbox-torrent-search') return 'torbox-torrent';
  if (source === 'torbox-usenet-search') return 'torbox-usenet';
  if (source === 'torrent-library' || source === 'usenet-library') return 'library';
  if (source === 'Torrentio') return 'torrentio';
  if (source === 'Knightcrawler') return 'knightcrawler';
  return 'unknown';
}

function streamProviderDetails(items = []) {
  return items.slice(0, 100).map(item => {
    const provider = providerKeyForItem(item);
    return {
      provider,
      providerLabel: providerLabel(provider),
      source: item.source || 'unknown',
      kind: item.kind || 'torrent',
      hash: item.hash || '',
      fileId: Number(item.fileId ?? item.fileIdx ?? 0) || 0,
      cached: !!item.cached,
      name: item.name || item.title || item.raw_title || 'Unknown',
    };
  });
}

function sourceCountBuckets(items = []) {
  const counts = {
    torboxTorrent: 0,
    torboxUsenet: 0,
    torboxLibrary: 0,
    torrentioFallback: 0,
    knightcrawlerFallback: 0,
  };
  const bySource = {};
  const byProvider = {};

  for (const item of items) {
    const source = item.source || 'unknown';
    const provider = providerKeyForItem(item);
    bySource[source] = (bySource[source] || 0) + 1;
    byProvider[provider] = (byProvider[provider] || 0) + 1;

    if (provider === 'torbox-torrent') {
      counts.torboxTorrent += 1;
    } else if (provider === 'torbox-usenet') {
      counts.torboxUsenet += 1;
    } else if (provider === 'library') {
      counts.torboxLibrary += 1;
    } else if (provider === 'torrentio') {
      counts.torrentioFallback += 1;
    } else if (provider === 'knightcrawler') {
      counts.knightcrawlerFallback += 1;
    }
  }

  return {
    ...counts,
    labels: {
      'TorBox Torrent': counts.torboxTorrent,
      'TorBox Usenet': counts.torboxUsenet,
      'TorBox Native Torrent Search': counts.torboxTorrent,
      'TorBox Native Usenet Search': counts.torboxUsenet,
      'TorBox Library/My List': counts.torboxLibrary,
      'Torrentio fallback': counts.torrentioFallback,
      'Knightcrawler fallback': counts.knightcrawlerFallback,
    },
    bySource,
    byProvider,
    streams: streamProviderDetails(items),
  };
}

function recordLastSourceCounts(items = [], context = {}) {
  const counts = sourceCountBuckets(items);
  searchApiStats.lastSourceCounts = {
    ts: new Date().toISOString(),
    total: items.length,
    ...context,
    ...counts,
  };
  recordEvent('stream_source_counts', {
    total: items.length,
    torboxTorrent: counts.torboxTorrent,
    torboxUsenet: counts.torboxUsenet,
    torboxLibrary: counts.torboxLibrary,
    torrentioFallback: counts.torrentioFallback,
    knightcrawlerFallback: counts.knightcrawlerFallback,
  });
}

function fileName(file = {}) {
  return file.name || file.short_name || file.shortName || file.raw_title || file.title || '';
}

function normalizeFile(file = {}, index = 0) {
  const id = Number(file.id ?? file.file_id ?? file.fileId ?? file.index ?? index);
  return {
    id: Number.isFinite(id) ? id : index,
    name: fileName(file),
    short_name: file.short_name || file.shortName || '',
    size: Number(file.size || 0),
    mimetype: file.mimetype || file.mime || '',
    infected: !!file.infected,
    hash: file.hash || '',
  };
}

function isLikelyVideoFile(file = {}) {
  if (file.infected) return false;
  const name = fileName(file);
  if (isArchiveOrExecutable(name) || hasBadFilePattern(name)) return false;
  if (hasVideoExtension(file)) return true;
  if (!/\.[a-z0-9]{2,5}$/i.test(name) && Number(file.size || 0) > 100 * 1024 * 1024) return true;
  return false;
}

function matchesEpisode(name = '', season, episode) {
  if (!season || !episode) return true;
  const s = String(Number(season));
  const e = String(Number(episode));
  const sp = s.padStart(2, '0');
  const ep = e.padStart(2, '0');
  const patterns = [
    new RegExp(`(^|[\\s._\\-\\[])S0?${s}E0?${e}(?=$|[\\s._\\-\\]\\)]|E\\d{1,2})`, 'i'),
    new RegExp(`(^|[\\s._\\-\\[])${s}x0?${e}(?=$|[\\s._\\-\\]\\)])`, 'i'),
    new RegExp(`(^|[\\s._\\-\\[])S${sp}E${ep}(?=$|[\\s._\\-\\]\\)]|E\\d{1,2})`, 'i'),
  ];
  return patterns.some(pattern => pattern.test(name));
}

function chooseLargest(files = []) {
  return files.slice().sort((a, b) => (b.size || 0) - (a.size || 0))[0] || null;
}

function selectBestFile(files = [], opts = {}, preferredFileId = 0) {
  const normalized = files.map(normalizeFile);
  if (!normalized.length) {
    return {
      file: { id: Number(preferredFileId) || 0, name: '', size: 0 },
      matchQuality: 'no-file-list',
    };
  }

  const candidates = normalized.filter(isLikelyVideoFile);
  if (!candidates.length) return { rejectReason: 'no-playable-video-file' };

  const preferred = candidates.find(f => String(f.id) === String(preferredFileId));
  if (opts.type === 'series') {
    const matching = candidates.filter(f => matchesEpisode(f.name || f.short_name, opts.season, opts.episode));
    if (preferred && matchesEpisode(preferred.name || preferred.short_name, opts.season, opts.episode)) {
      return { file: preferred, matchQuality: 'episode' };
    }
    if (matching.length) return { file: chooseLargest(matching), matchQuality: 'episode' };
    if (candidates.length === 1) return { file: candidates[0], matchQuality: 'single-video-pack' };
    return { rejectReason: 'no-matching-episode-file-in-pack' };
  }

  if (preferred) return { file: preferred, matchQuality: 'preferred-file' };
  return { file: chooseLargest(candidates), matchQuality: 'largest-video-file' };
}

function listCacheFor(kind) {
  return listCaches[normalizeKind(kind)];
}

function idCacheFor(kind) {
  return downloadIdCaches[normalizeKind(kind)];
}

function indexListItem(kind, item = {}) {
  const hash = String(item.hash || '').toLowerCase();
  if (!hash || !item.id) return;
  idCacheFor(kind)[hash] = item.id;
  for (const alt of item.alternative_hashes || []) {
    if (alt) idCacheFor(kind)[String(alt).toLowerCase()] = item.id;
  }
}

async function getList(kind = 'torrent', force = false) {
  const normalizedKind = normalizeKind(kind);
  const cfg = KIND[normalizedKind];
  const cache = listCacheFor(normalizedKind);
  if (!force && cache.data && Date.now() - cache.ts < cfg.listTtlMs) return cache.data;
  if (!force && cache.loading) return cache.loading;

  cache.loading = (async () => {
    try {
      const params = normalizedKind === 'torrent' ? { bypass_cache: true } : {};
      const res = await torboxGet(cfg.listPath, { params }, `${normalizedKind}/mylist`);
      cache.data = res.data?.data || [];
      cache.ts = Date.now();
      for (const item of cache.data) indexListItem(normalizedKind, item);
    } catch (e) {
      console.error(`[TorBox] getList ${normalizedKind} error:`, e.message);
      recordEvent('mylist_failed', { kind: normalizedKind, message: e.message });
      cache.data = cache.data || [];
    } finally {
      cache.loading = null;
    }
    return cache.data || [];
  })();

  return cache.loading;
}

async function getMyList(force = false) {
  return getList('torrent', force);
}

async function searchLibrary(kind, imdbId, type, opts = {}) {
  try {
    const normalizedKind = normalizeKind(kind);
    if (type !== 'series') return [];
    const list = await getList(normalizedKind);
    if (!list.length) return [];

    const results = [];
    for (const item of list) {
      if (!item.cached || !item.files?.length || !item.hash) continue;
      const selected = selectBestFile(item.files, { type, ...opts }, 0);
      if (!selected.file || selected.rejectReason) continue;
      const name = selected.file.short_name || selected.file.name || item.name;
      results.push(normalizeTorrent({
        kind: normalizedKind,
        hash: item.hash,
        name: `${item.name || name} - ${name}`,
        raw_title: item.name || name,
        size: selected.file.size || item.size || 0,
        seeders: item.seeds || 0,
        fileId: selected.file.id,
        cached: true,
        source: `${normalizedKind}-library`,
        provider: 'library',
        providerLabel: providerLabel('library'),
        fromLibrary: true,
        selectedFile: selected.file,
        matchQuality: selected.matchQuality,
      }, type, opts));
    }

    console.log(`[Library:${normalizedKind}] ${results.length} matches for ${imdbId}`);
    return results;
  } catch (e) {
    console.error(`[Library:${kind}] Error:`, e.message);
    recordEvent('library_search_failed', { kind, message: e.message });
    return [];
  }
}

function extractSize(text = '') {
  const gb = String(text).match(/([\d.]+)\s*GB/i);
  if (gb) return parseFloat(gb[1]) * 1e9;
  const mb = String(text).match(/([\d.]+)\s*MB/i);
  if (mb) return parseFloat(mb[1]) * 1e6;
  return 0;
}

function extractSeeders(text = '') {
  const fromIcon = String(text).match(/(?:seeders?|seeds?|peers?|👤)\s*[:=]?\s*(\d+)/i);
  return fromIcon ? parseInt(fromIcon[1], 10) : 0;
}

function extractHash(input = {}) {
  return String(
    input.hash ||
    input.infoHash ||
    input.info_hash ||
    input.release_hash ||
    input.cached_hash ||
    ''
  ).toLowerCase();
}

function firstValue(input = {}, keys = []) {
  for (const key of keys) {
    const value = input[key];
    if (value !== undefined && value !== null && value !== '') return value;
  }
  return undefined;
}

function hasValue(value) {
  return value !== undefined && value !== null && value !== '';
}

function normalizeTorrent(input = {}, mediaType, opts = {}) {
  const kind = normalizeKind(input.kind || input.type || 'torrent');
  const hash = extractHash(input);
  const name = input.name || input.title || input.raw_title || input.release_title || input.filename || 'Unknown';
  const preferredFileId = Number(input.fileId ?? input.file_id ?? input.fileIdx ?? 0);
  const fileId = Number.isFinite(preferredFileId) ? preferredFileId : 0;
  const selectedFile = input.selectedFile ? normalizeFile(input.selectedFile) : null;
  const files = Array.isArray(input.files) ? input.files.map(normalizeFile) : undefined;
  const searchId = firstValue(input, ['searchId', 'search_id', 'indexer_id', 'nzb_id', 'id']);
  const guid = firstValue(input, ['guid', 'nzb_guid', 'nzbguid', 'download_id', 'downloadId']);
  const downloadUrl = firstValue(input, ['downloadUrl', 'download_url', 'nzb', 'nzb_url', 'link', 'url']);

  return {
    kind,
    hash,
    name,
    raw_title: input.raw_title || input.release_title || name,
    size: Number(selectedFile?.size || input.size || input.fileSize || extractSize(name) || 0),
    seeders: Number(input.seeders ?? input.seeds ?? extractSeeders(name) ?? 0) || 0,
    fileId,
    fileIdx: fileId,
    cached: boolish(input.cached ?? input.is_cached ?? input.cache_hit ?? input.cached_status, false),
    source: input.source || input._source || 'unknown',
    provider: input.provider || providerKeyForItem(input),
    providerLabel: input.providerLabel || providerLabel(input.provider || providerKeyForItem(input)),
    selectedFile,
    files,
    fromLibrary: !!input.fromLibrary,
    matchQuality: input.matchQuality || '',
    fileRejectReason: input.fileRejectReason || '',
    mediaType,
    season: opts.season,
    episode: opts.episode,
    searchId,
    guid,
    downloadUrl,
  };
}

function searchResultArrays(root = {}, kind = 'torrent') {
  if (Array.isArray(root)) return root;
  const data = root.data ?? root;
  if (Array.isArray(data)) return data;

  const keys = kind === 'usenet'
    ? ['usenet', 'usenets', 'nzb', 'nzbs', 'results', 'downloads', 'files']
    : ['torrents', 'torrent', 'results', 'streams', 'files'];
  for (const key of keys) {
    if (Array.isArray(data?.[key])) return data[key];
  }

  if (data && typeof data === 'object') {
    for (const value of Object.values(data)) {
      if (Array.isArray(value)) return value;
    }
  }
  return [];
}

function normalizeSearchResult(input = {}, kind, mediaType, opts = {}) {
  const normalizedKind = normalizeKind(kind);
  const item = normalizeTorrent({
    ...input,
    kind: normalizedKind,
    hash: extractHash(input),
    name: input.raw_title || input.title || input.name || input.release_title || input.filename || 'Unknown',
    raw_title: input.raw_title || input.title || input.name || input.release_title,
    seeders: input.seeders || input.seeds,
    cached: input.cached ?? input.is_cached ?? input.cache_hit ?? true,
    source: `torbox-${normalizedKind}-search`,
    provider: normalizedKind === 'usenet' ? 'torbox-usenet' : 'torbox-torrent',
    providerLabel: providerLabel(normalizedKind === 'usenet' ? 'torbox-usenet' : 'torbox-torrent'),
  }, mediaType, opts);

  if (normalizedKind === 'usenet' && !item.downloadUrl && hasValue(item.searchId) && hasValue(item.guid)) {
    item.downloadUrl = `${TORBOX_SEARCH_API_URL.replace(/\/$/, '')}/usenet/download/${encodeURIComponent(item.searchId)}/${encodeURIComponent(item.guid)}`;
  }
  return item;
}

function cloneNativeSearchResult(result = {}) {
  return {
    ...result,
    items: cloneNativeSearchItems(result.items || []),
  };
}

function classifyNativeSearchError(error = {}) {
  const status = error.response?.status || null;
  const code = error.code || '';
  const message = error.message || '';
  if (status === 429) return 'rate_limited';
  if (code === 'ENOTFOUND' || code === 'EAI_AGAIN' || /getaddrinfo|ENOTFOUND|EAI_AGAIN/i.test(message)) {
    return 'dns_failed';
  }
  if (code === 'ECONNABORTED' || /timeout/i.test(message)) return 'timeout';
  return 'unavailable';
}

async function searchTorBoxNativeResult(kind, imdbId, type, opts = {}) {
  const normalizedKind = normalizeKind(kind);
  const provider = normalizedKind === 'usenet' ? 'torbox-usenet' : 'torbox-torrent';
  if (!TORBOX_ENABLE_NATIVE_SEARCH) {
    return { provider, status: 'disabled', detail: 'native search disabled', items: [] };
  }
  if (normalizedKind === 'usenet' && !TORBOX_ENABLE_USENET) {
    return { provider, status: 'disabled', detail: 'usenet disabled', items: [] };
  }

  const label = `torbox-${normalizedKind}-search`;
  const params = {
    metadata: false,
    check_cache: true,
    check_owned: true,
    search_user_engines: TORBOX_SEARCH_USER_ENGINES,
    cached_only: true,
  };
  if (type === 'series' && opts.season) {
    params.season = opts.season;
    params.episode = opts.episode || 1;
  }

  const cacheKey = nativeSearchCacheKey(normalizedKind, imdbId, type, opts, params);
  const cached = getNativeSearchCache(cacheKey);
  if (cached) {
    searchApiStats.cacheHits += 1;
    if (cached.status === 429) searchApiStats.backoffHits += 1;
    console.log(`[TorBox ${normalizedKind}] Native cache HIT ${imdbId} (${cached.value.length})`);
    const status = cached.status === 429 ? 'rate_limited' : 'cache_hit';
    recordEvent('torbox_search_cache_hit', {
      kind: normalizedKind,
      count: cached.value.length,
      status: cached.status || 200,
    });
    return {
      provider,
      status,
      detail: cached.message || null,
      retryAt: cached.expiresAt || null,
      cacheHit: true,
      items: cloneNativeSearchItems(cached.value),
    };
  }

  const inflight = nativeSearchInflight.get(cacheKey);
  if (inflight) {
    searchApiStats.coalesced += 1;
    recordEvent('torbox_search_coalesced', { kind: normalizedKind, imdbId });
    const result = await inflight;
    return cloneNativeSearchResult({ ...result, coalesced: true });
  }

  if (!isHealthy(label, providerHealth)) {
    searchApiStats.backoffHits += 1;
    recordEvent('torbox_search_backoff', {
      kind: normalizedKind,
      retryAt: providerHealth[label]?.retryAt || null,
      message: providerHealth[label]?.message || null,
    });
    return {
      provider,
      status: 'backoff',
      detail: providerHealth[label]?.message || null,
      retryAt: providerHealth[label]?.retryAt || null,
      items: [],
    };
  }

  const path = `/${KIND[normalizedKind].searchPath}/imdb:${encodeURIComponent(imdbId)}`;
  const promise = Promise.resolve().then(async () => {
    const start = Date.now();
    try {
      const res = await searchClient.get(path, { params });
      const elapsed = Date.now() - start;
      recordSearchApiRequest(normalizedKind, res.status, elapsed);
      const items = searchResultArrays(res.data, normalizedKind)
        .map(item => normalizeSearchResult(item, normalizedKind, type, opts))
        .filter(item => item.hash);
      console.log(`[TorBox ${normalizedKind}] ${items.length} native results in ${elapsed}ms`);
      recordEvent('torbox_search_ok', { kind: normalizedKind, count: items.length, ms: elapsed });
      markOk(label, providerHealth);
      setNativeSearchCache(cacheKey, items, NATIVE_SEARCH_CACHE_TTL_MS, {
        kind: normalizedKind,
        status: res.status,
        count: items.length,
      });
      return {
        provider,
        status: 'ok',
        count: items.length,
        ms: elapsed,
        items,
      };
    } catch (e) {
      const elapsed = Date.now() - start;
      const status = e.response?.status || null;
      const retryAfter = e.response?.headers?.['retry-after'] || null;
      const detail = e.response?.data?.detail || e.response?.data?.error || e.message;
      const failureStatus = classifyNativeSearchError(e);
      recordSearchApiRequest(normalizedKind, status || 'ERR', elapsed, retryAfter);
      console.log(`[TorBox ${normalizedKind}] Search unavailable: ${detail}`);

      if (status === 429) {
        const cooldown = retryAfterMs(e.response?.headers || {}, NATIVE_SEARCH_429_BACKOFF_MS);
        setNativeSearchCache(cacheKey, [], cooldown, {
          kind: normalizedKind,
          status: 429,
          count: 0,
          message: detail,
        });
        recordEvent('torbox_search_rate_limited', {
          kind: normalizedKind,
          retryAfter,
          cooldownMs: cooldown,
          detail,
        });
        markFailed(label, detail, providerHealth, cooldown);
      } else {
        markFailed(label, detail, providerHealth, SEARCH_COOLDOWN_MS);
      }
      return {
        provider,
        status: failureStatus,
        detail,
        retryAfter,
        retryAt: providerHealth[label]?.retryAt || null,
        ms: elapsed,
        items: [],
      };
    } finally {
      nativeSearchInflight.delete(cacheKey);
    }
  });

  nativeSearchInflight.set(cacheKey, promise);
  return cloneNativeSearchResult(await promise);
}

async function searchTorBoxNative(kind, imdbId, type, opts = {}) {
  return (await searchTorBoxNativeResult(kind, imdbId, type, opts)).items;
}

async function fetchFromIndexer(indexer, url) {
  if (!EXTERNAL_TORRENT_FALLBACK || !isHealthy(indexer.name)) return [];
  const start = Date.now();
  try {
    const res = await externalGet(indexer.base + url, { timeout: indexer.timeout });
    const streams = res.data?.streams || [];
    const elapsed = Date.now() - start;
    const previous = indexerStats[indexer.key] || {};
    indexerStats[indexer.key] = {
      lastStatus: 'ok',
      lastCount: streams.length,
      lastMs: elapsed,
      zeroCountStreak: streams.length ? 0 : (previous.zeroCountStreak || 0) + 1,
      lastAt: Date.now(),
    };
    console.log(`[${indexer.name}] ${streams.length} results in ${elapsed}ms`);
    recordEvent('indexer_ok', { name: indexer.name, count: streams.length, ms: elapsed });
    markOk(indexer.name);
    return streams.map(s => ({
      ...s,
      _source: indexer.name,
      _provider: indexer.key,
      _providerLabel: providerLabel(indexer.key),
    }));
  } catch (e) {
    const previous = indexerStats[indexer.key] || {};
    indexerStats[indexer.key] = {
      lastStatus: 'error',
      lastCount: 0,
      lastMs: Date.now() - start,
      zeroCountStreak: previous.zeroCountStreak || 0,
      message: e.message,
      lastAt: Date.now(),
    };
    markFailed(indexer.name, e.message);
    return [];
  }
}

function dedupeAndParse(streams, mediaType, opts = {}) {
  const seen = new Set();
  return streams
    .filter(s => s.infoHash || s.hash)
    .map(s => normalizeTorrent({
      kind: 'torrent',
      hash: s.infoHash || s.hash,
      name: s.title || s.name || 'Unknown',
      raw_title: s.title || s.name || 'Unknown',
      size: s.fileSize || extractSize(s.title) || 0,
      seeders: s.seeders || extractSeeders(s.title) || 0,
      fileId: s.fileIdx ?? s.fileId ?? 0,
      cached: false,
      source: s._source || 'indexer',
      provider: s._provider || providerKeyForItem({ source: s._source }),
      providerLabel: s._providerLabel || providerLabel(s._provider || providerKeyForItem({ source: s._source })),
    }, mediaType, opts))
    .filter(t => {
      const key = `${t.kind}:${t.hash}:${t.fileId}`;
      if (!t.hash || seen.has(key)) return false;
      seen.add(key);
      return true;
    });
}

function normalizeAvailabilityData(data = {}) {
  if (Array.isArray(data)) {
    return Object.fromEntries(data
      .filter(Boolean)
      .map(item => [String(item.hash || '').toLowerCase(), item])
      .filter(([hash]) => hash));
  }
  return Object.fromEntries(Object.entries(data || {}).map(([hash, value]) => [String(hash).toLowerCase(), value]));
}

async function checkCachedForKind(kind = 'torrent', hashes = [], opts = {}) {
  const normalizedKind = normalizeKind(kind);
  const listFiles = opts.listFiles !== false;
  const unique = [...new Set(hashes.filter(Boolean).map(h => String(h).toLowerCase()))];
  const result = {};
  const misses = [];

  for (const hash of unique) {
    const key = `${normalizedKind}:${hash}:${listFiles ? 'files' : 'plain'}`;
    const cached = cacheGet(availabilityCache, key, AVAILABILITY_TTL_MS);
    if (cached !== null) {
      if (cached) result[hash] = cached;
    } else {
      misses.push(hash);
    }
  }

  for (let i = 0; i < misses.length; i += 100) {
    const chunk = misses.slice(i, i + 100);
    try {
      const res = await torboxGet(KIND[normalizedKind].checkPath, {
        params: { hash: chunk.join(','), format: 'object', list_files: listFiles },
      }, `${normalizedKind}/checkcached`);
      const data = normalizeAvailabilityData(res.data?.data || {});
      for (const hash of chunk) {
        const value = data[hash] || data[hash.toUpperCase()] || null;
        cacheSet(availabilityCache, `${normalizedKind}:${hash}:${listFiles ? 'files' : 'plain'}`, value);
        if (value) result[hash] = value;
      }
    } catch (e) {
      console.warn(`[TorBox] ${normalizedKind} checkcached error:`, e.message);
      recordEvent('checkcached_failed', { kind: normalizedKind, message: e.message, count: chunk.length });
    }
  }

  return result;
}

async function checkCached(hashes = [], opts = {}) {
  return checkCachedForKind('torrent', hashes, opts);
}

function filesFromAvailability(entry = {}) {
  if (!entry || entry === true) return [];
  return Array.isArray(entry.files) ? entry.files : [];
}

function applyAvailabilityEntry(t, entry, opts = {}) {
  if (!entry) return { ...t, cached: false };

  const files = filesFromAvailability(entry);
  const selected = selectBestFile(files, { type: t.mediaType, season: opts.season, episode: opts.episode }, t.fileId);
  if (selected.rejectReason) {
    return {
      ...t,
      cached: true,
      name: entry.name || t.name,
      size: entry.size || t.size,
      fileRejectReason: selected.rejectReason,
      files: files.map(normalizeFile),
    };
  }

  const selectedFile = selected.file || null;
  const releaseName = entry.name || t.raw_title || t.name;
  const selectedName = selectedFile?.short_name || selectedFile?.name || '';
  const displayName = selectedName && selectedName !== releaseName
    ? `${releaseName} - ${selectedName}`
    : releaseName;

  return {
    ...t,
    cached: true,
    name: displayName,
    raw_title: releaseName,
    size: selectedFile?.size || entry.size || t.size,
    fileId: Number(selectedFile?.id ?? t.fileId ?? 0),
    fileIdx: Number(selectedFile?.id ?? t.fileId ?? 0),
    selectedFile,
    files: files.map(normalizeFile),
    matchQuality: selected.matchQuality,
  };
}

async function applyCacheCheck(torrents, opts = {}) {
  if (!torrents.length) return torrents;

  const libItems = torrents.filter(t => t.fromLibrary);
  const needsCheck = torrents.filter(t => !t.fromLibrary);
  const byKind = needsCheck.reduce((acc, item) => {
    const kind = normalizeKind(item.kind);
    if (!acc[kind]) acc[kind] = [];
    acc[kind].push(item);
    return acc;
  }, {});

  const checked = [];
  for (const [kind, items] of Object.entries(byKind)) {
    const cachedMap = await checkCachedForKind(kind, items.map(t => t.hash), { listFiles: true });
    for (const item of items) {
      const entry = cachedMap[item.hash] || cachedMap[item.hash?.toUpperCase?.()];
      checked.push(applyAvailabilityEntry(item, entry, opts));
    }
  }

  const result = dedupeNormalized([...libItems, ...checked]);
  const cachedCount = result.filter(t => t.cached && !t.fileRejectReason).length;
  console.log(`[Search] ${cachedCount}/${result.length} playable cached after file selection`);
  recordEvent('cache_check', { total: result.length, cached: cachedCount });
  return result;
}

function dedupeNormalized(torrents = []) {
  const seen = new Set();
  return torrents.filter(t => {
    const kind = normalizeKind(t.kind);
    const key = `${kind}:${t.hash}:${t.fileId}`;
    if (!t.hash || seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function playableCachedCount(items = []) {
  return items.filter(t => t.cached && !t.fileRejectReason).length;
}

function externalStreamUrl(type, imdbId, opts = {}) {
  return (type === 'series' && opts.season && opts.episode)
    ? `/stream/series/${imdbId}:${opts.season}:${opts.episode}.json`
    : `/stream/movie/${imdbId}.json`;
}

async function fetchExternalProvider(provider, type, imdbId, opts = {}) {
  const indexer = INDEXERS.find(ix => ix.key === provider);
  if (!indexer) return { provider, status: 'unknown_provider', items: [] };
  if (!providerEnabled(provider)) return { provider, status: 'disabled', items: [] };
  if (!isHealthy(indexer.name)) {
    return {
      provider,
      status: 'backoff',
      detail: indexerHealth[indexer.name]?.message || null,
      retryAt: indexerHealth[indexer.name]?.retryAt || null,
      items: [],
    };
  }

  const streams = await fetchFromIndexer(indexer, externalStreamUrl(type, imdbId, opts));
  return {
    provider,
    status: 'ok',
    count: streams.length,
    items: dedupeAndParse(streams, type, opts),
  };
}

async function fetchExternalCandidates(type, imdbId, opts = {}) {
  const externalProviders = parseProviderPriority()
    .filter(provider => PROVIDER_INFO[provider]?.group === 'external');
  if (!externalProviders.length) return [];

  const enabledProviders = externalProviders.filter(providerEnabled);
  if (!enabledProviders.length) {
    recordEvent('all_indexers_down', {});
    return [];
  }

  const results = [];
  for (const provider of enabledProviders) {
    const outcome = await fetchExternalProvider(provider, type, imdbId, opts);
    results.push(...outcome.items);
  }
  return dedupeNormalized(results);
}

function outcomeSummary(outcome = {}) {
  return {
    provider: outcome.provider || 'unknown',
    providerLabel: providerLabel(outcome.provider),
    status: outcome.status || 'unknown',
    count: outcome.count ?? outcome.items?.length ?? 0,
    playableCached: outcome.playableCached ?? null,
    detail: outcome.detail || null,
    retryAt: outcome.retryAt || null,
    cacheHit: !!outcome.cacheHit,
    coalesced: !!outcome.coalesced,
  };
}

async function fetchTorBoxProvider(provider, imdbId, type, opts = {}) {
  if (!providerEnabled(provider)) return { provider, status: 'disabled', items: [] };

  if (provider === 'torbox-torrent') return searchTorBoxNativeResult('torrent', imdbId, type, opts);
  if (provider === 'torbox-usenet') return searchTorBoxNativeResult('usenet', imdbId, type, opts);
  if (provider === 'library') {
    const promises = [searchLibrary('torrent', imdbId, type, opts)];
    if (TORBOX_ENABLE_USENET) promises.push(searchLibrary('usenet', imdbId, type, opts));
    const settled = await Promise.allSettled(promises);
    const items = dedupeNormalized(settled.flatMap(result => result.status === 'fulfilled' ? result.value : []));
    return { provider, status: 'ok', count: items.length, items };
  }

  return { provider, status: 'unknown_provider', items: [] };
}

function fallbackReasonFromOutcomes(outcomes = [], playableCount = 0) {
  const statuses = outcomes
    .filter(outcome => PROVIDER_INFO[outcome.provider]?.group === 'torbox')
    .map(outcome => outcome.status);
  if (statuses.includes('rate_limited')) return 'torbox_search_rate_limited';
  if (statuses.includes('dns_failed')) return 'torbox_search_dns_failed';
  if (statuses.includes('timeout')) return 'torbox_search_timeout';
  if (statuses.includes('backoff')) return 'torbox_search_backoff';
  if (statuses.includes('unavailable')) return 'torbox_search_unavailable';
  if (playableCount < NATIVE_RESULT_TARGET) return 'torbox_cached_count_below_target';
  return 'not_needed_native_result_target_met';
}

function recordLastProviderRun(context = {}) {
  searchApiStats.lastProviderRun = {
    ts: new Date().toISOString(),
    ...context,
  };
}

async function searchStreams(imdbId, type, opts = {}) {
  const providers = providerConfig();
  const cacheKey = [
    type,
    imdbId,
    opts.season || 0,
    opts.episode || 0,
    TORBOX_ENABLE_NATIVE_SEARCH ? 'native' : 'no-native',
    TORBOX_ENABLE_USENET ? 'usenet' : 'no-usenet',
    TORBOX_SEARCH_USER_ENGINES ? 'user-engines' : 'native-only',
    EXTERNAL_TORRENT_FALLBACK ? 'fallback' : 'no-fallback',
    TORRENTIO_ENABLED ? 'torrentio' : 'no-torrentio',
    KNIGHTCRAWLER_ENABLED ? 'knightcrawler' : 'no-knightcrawler',
    providers.effectivePriority.join(','),
  ].join(':');
  const cachedSearch = cacheGet(searchCache, cacheKey, SEARCH_CACHE_TTL_MS);
  if (cachedSearch) {
    console.log(`[Search] Cache HIT ${cacheKey}`);
    recordLastSourceCounts(cachedSearch, {
      cache: 'aggregate-hit',
      imdbId,
      type,
      season: opts.season || null,
      episode: opts.episode || null,
      providerPriority: providers.effectivePriority,
      fallbackReason: 'aggregate_cache_hit',
    });
    return cachedSearch;
  }

  try {
    console.log(`[Search] ${type} ${imdbId}${opts.season ? ` S${opts.season}E${opts.episode}` : ''}`);

    const outcomes = [];
    const torboxCandidates = [];
    const torboxProviders = providers.effectivePriority
      .filter(provider => PROVIDER_INFO[provider]?.group === 'torbox');
    const externalProviders = providers.effectivePriority
      .filter(provider => PROVIDER_INFO[provider]?.group === 'external');

    // TorBox providers are independent — query them in parallel; results are
    // merged in priority order since Promise.all preserves input order.
    const torboxOutcomes = await Promise.all(
      torboxProviders.map(provider => fetchTorBoxProvider(provider, imdbId, type, opts))
    );
    for (const outcome of torboxOutcomes) {
      outcomes.push(outcomeSummary(outcome));
      torboxCandidates.push(...(outcome.items || []));
    }

    const nativeMerged = dedupeNormalized(torboxCandidates);
    const nativeChecked = await applyCacheCheck(nativeMerged, { ...opts, type });
    const nativePlayable = playableCachedCount(nativeChecked);

    let merged = nativeChecked;
    let fallbackReason = fallbackReasonFromOutcomes(outcomes, nativePlayable);
    if (nativePlayable < NATIVE_RESULT_TARGET) {
      for (const provider of externalProviders) {
        if (playableCachedCount(merged) >= NATIVE_RESULT_TARGET) {
          outcomes.push(outcomeSummary({ provider, status: 'skipped_target_met', items: [] }));
          continue;
        }

        const outcome = await fetchExternalProvider(provider, type, imdbId, opts);
        if (outcome.items.length) {
          const externalChecked = await applyCacheCheck(outcome.items, { ...opts, type });
          outcome.playableCached = playableCachedCount(externalChecked);
          merged = dedupeNormalized([...merged, ...externalChecked]);
        }
        outcomes.push(outcomeSummary(outcome));
      }
    } else {
      recordEvent('external_fallback_skipped', { reason: 'native_result_target_met', count: nativePlayable });
    }

    console.log(`[Search] ${merged.length} unique candidates total`);
    recordLastProviderRun({
      imdbId,
      type,
      season: opts.season || null,
      episode: opts.episode || null,
      providerPriority: providers.effectivePriority,
      providersAttempted: outcomes,
      fallbackReason,
      torboxPlayableCached: nativePlayable,
      totalPlayableCached: playableCachedCount(merged),
    });
    recordLastSourceCounts(merged, {
      cache: 'fresh',
      imdbId,
      type,
      season: opts.season || null,
      episode: opts.episode || null,
      providerPriority: providers.effectivePriority,
      providersAttempted: outcomes,
      providersUsed: sourceCountBuckets(merged).byProvider,
      fallbackReason,
    });
    cacheSet(searchCache, cacheKey, merged);
    return merged;
  } catch (e) {
    console.error('[Search] Error:', e.message);
    recordEvent('search_failed', { imdbId, type, message: e.message });
    return [];
  }
}

if (process.env.NODE_ENV !== 'test') {
  setTimeout(async () => {
    try {
      await Promise.all([
        getList('torrent'),
        TORBOX_ENABLE_USENET ? getList('usenet') : Promise.resolve([]),
      ]);
      console.log(`[TorBox] Pre-warmed ${Object.keys(downloadIdCaches.torrent).length} torrent IDs and ${Object.keys(downloadIdCaches.usenet).length} Usenet IDs`);
    } catch(e) {}
  }, 0);
}

async function requestDL(kind, downloadId, fileId = 0) {
  const normalizedKind = normalizeKind(kind);
  const cfg = KIND[normalizedKind];
  try {
    const res = await torboxGet(cfg.requestPath, {
      params: {
        token: TORBOX_API_KEY,
        [cfg.idParam]: downloadId,
        file_id: Number(fileId) || 0,
        zip_link: false,
        redirect: false,
        append_name: true,
      },
    }, `${normalizedKind}/requestdl`);
    return typeof res.data?.data === 'string' ? res.data.data : null;
  } catch (e) {
    const detail = e.response?.data?.detail || e.message;
    console.warn(`[TorBox] ${normalizedKind} requestdl error:`, detail);
    recordEvent('requestdl_failed', { kind: normalizedKind, downloadId, fileId, detail });
    return null;
  }
}

function findItemByHash(items = [], hash = '') {
  const h = String(hash).toLowerCase();
  return items.find(item => {
    if (item.hash && String(item.hash).toLowerCase() === h) return true;
    return (item.alternative_hashes || []).some(alt => String(alt).toLowerCase() === h);
  });
}

async function findDownloadId(kind, hash, forceRefresh = false) {
  const normalizedKind = normalizeKind(kind);
  const h = String(hash).toLowerCase();
  if (!forceRefresh && idCacheFor(normalizedKind)[h]) return idCacheFor(normalizedKind)[h];
  const list = await getList(normalizedKind, forceRefresh);
  const existing = findItemByHash(list, h);
  if (existing?.id) {
    indexListItem(normalizedKind, existing);
    return existing.id;
  }
  return null;
}

async function addCachedTorrent(hash) {
  const h = String(hash).toLowerCase();
  console.log(`[TorBox] Adding cached-only magnet for ${h}`);
  const form = new FormData();
  form.append('magnet', `magnet:?xt=urn:btih:${h}`);
  form.append('seed', '3');
  form.append('allow_zip', 'false');
  form.append('add_only_if_cached', 'true');

  try {
    const create = await torboxPost(KIND.torrent.createPath, form, {
      headers: form.getHeaders(),
    }, 'torrents/createtorrent');
    const torrentId = create.data?.data?.torrent_id || create.data?.data?.id;
    if (torrentId) {
      downloadIdCaches.torrent[h] = torrentId;
      listCaches.torrent.ts = 0;
      recordEvent('torrent_added_cached_only', { hash: h, torrentId });
      return torrentId;
    }
  } catch (e) {
    const error = e.response?.data?.error;
    const detail = e.response?.data?.detail || e.message;
    recordEvent('torrent_add_failed', { hash: h, error, detail });
    if (error === 'DUPLICATE_ITEM') return findDownloadId('torrent', h, true);
    console.warn('[TorBox] cached-only torrent add failed:', detail);
  }

  return null;
}

function encodeSourceRef(item = {}) {
  const kind = normalizeKind(item.kind);
  if (kind === 'torrent') return item.hash || '';
  const payload = {
    h: item.hash || '',
    u: item.downloadUrl || '',
    sid: hasValue(item.searchId) ? item.searchId : '',
    g: hasValue(item.guid) ? item.guid : '',
    n: item.raw_title || item.name || '',
  };
  return `ref_${Buffer.from(JSON.stringify(payload)).toString('base64url')}`;
}

function decodeSourceRef(ref = '') {
  const value = String(ref || '');
  if (!value.startsWith('ref_')) return { h: value };
  try {
    return JSON.parse(Buffer.from(value.slice(4), 'base64url').toString('utf8'));
  } catch {
    return { h: value };
  }
}

function usenetDownloadUrlFromRef(refData = {}) {
  if (refData.u) return refData.u;
  if (hasValue(refData.sid) && hasValue(refData.g)) {
    return `${TORBOX_SEARCH_API_URL.replace(/\/$/, '')}/usenet/download/${encodeURIComponent(refData.sid)}/${encodeURIComponent(refData.g)}`;
  }
  return '';
}

async function addCachedUsenet(ref) {
  const refData = decodeSourceRef(ref);
  const hash = String(refData.h || '').toLowerCase();
  const link = usenetDownloadUrlFromRef(refData);
  if (!link) {
    recordEvent('usenet_add_missing_link', { hash });
    return null;
  }

  console.log(`[TorBox] Adding cached-only Usenet download for ${hash || refData.n || 'unknown'}`);
  const form = new FormData();
  form.append('link', link);
  form.append('post_processing', '-1');
  form.append('add_only_if_cached', 'true');
  if (refData.n) form.append('name', refData.n);

  try {
    const create = await torboxPost(KIND.usenet.createPath, form, {
      headers: form.getHeaders(),
    }, 'usenet/createusenetdownload');
    const data = create.data?.data || {};
    const usenetId = KIND.usenet.createIdKeys.map(key => data[key]).find(Boolean);
    const createdHash = String(data.hash || hash || '').toLowerCase();
    if (usenetId) {
      if (createdHash) downloadIdCaches.usenet[createdHash] = usenetId;
      listCaches.usenet.ts = 0;
      recordEvent('usenet_added_cached_only', { hash: createdHash, usenetId });
      return usenetId;
    }
  } catch (e) {
    const error = e.response?.data?.error;
    const detail = e.response?.data?.detail || e.message;
    recordEvent('usenet_add_failed', { hash, error, detail });
    if (error === 'DUPLICATE_ITEM' && hash) return findDownloadId('usenet', hash, true);
    console.warn('[TorBox] cached-only Usenet add failed:', detail);
  }

  return null;
}

async function getTorrentStreamUrl(hash, fileId = 0) {
  const h = String(hash || '').toLowerCase();
  if (!h) return null;

  let torrentId = await findDownloadId('torrent', h);
  if (!torrentId) torrentId = await addCachedTorrent(h);
  if (!torrentId) return null;

  let url = await requestDL('torrent', torrentId, fileId);
  if (url) return url;

  torrentId = await findDownloadId('torrent', h, true) || torrentId;
  url = await requestDL('torrent', torrentId, fileId);
  if (url) recordEvent('requestdl_refresh_success', { kind: 'torrent', hash: h, fileId });
  return url;
}

async function getUsenetStreamUrl(ref, fileId = 0) {
  const refData = decodeSourceRef(ref);
  const h = String(refData.h || '').toLowerCase();

  let usenetId = h ? await findDownloadId('usenet', h) : null;
  if (!usenetId) usenetId = await addCachedUsenet(ref);
  if (!usenetId) return null;

  let url = await requestDL('usenet', usenetId, fileId);
  if (url) return url;

  usenetId = h ? (await findDownloadId('usenet', h, true) || usenetId) : usenetId;
  url = await requestDL('usenet', usenetId, fileId);
  if (url) recordEvent('requestdl_refresh_success', { kind: 'usenet', hash: h, fileId });
  return url;
}

function playbackCacheKey(kind, ref, fileId = 0) {
  const refData = decodeSourceRef(ref);
  const id = String(refData.h || ref).toLowerCase();
  return `${normalizeKind(kind)}:${id}:${Number(fileId) || 0}`;
}

async function getStreamUrlBySource(kind, ref, fileId = 0) {
  const normalizedKind = normalizeKind(kind);
  const cacheKey = playbackCacheKey(normalizedKind, ref, fileId);

  const cachedUrl = await cacheStore.getPlaybackUrl(cacheKey);
  if (cachedUrl) {
    recordEvent('playback_url_cache_hit', { key: cacheKey });
    return cachedUrl;
  }

  const url = normalizedKind === 'usenet'
    ? await getUsenetStreamUrl(ref, fileId)
    : await getTorrentStreamUrl(ref, fileId);
  if (url) await cacheStore.setPlaybackUrl(cacheKey, url, PLAYBACK_URL_TTL);
  return url;
}

async function getStreamUrlByHash(hash, fileId = 0, kind = 'torrent') {
  return getStreamUrlBySource(kind, hash, fileId);
}

async function getStreamUrl(torrentId, fileId = 0) {
  return requestDL('torrent', torrentId, fileId);
}

function providerDiagnostic(name, bucket = providerHealth) {
  return {
    name,
    healthy: isHealthy(name, bucket),
    retryAt: bucket[name]?.retryAt || null,
    message: bucket[name]?.message || null,
  };
}

function setSearchClientGetForTest(fn) {
  searchClient.get = typeof fn === 'function' ? fn : defaultSearchClientGet;
}

function setClientGetForTest(fn) {
  client.get = typeof fn === 'function' ? fn : defaultClientGet;
}

function setExternalGetForTest(fn) {
  externalGet = typeof fn === 'function' ? fn : defaultExternalGet;
}

function resetSearchReliabilityStateForTest() {
  nativeSearchCache.clear();
  nativeSearchInflight.clear();
  searchCache.clear();
  availabilityCache.clear();
  searchApiStats.requestLog = [];
  searchApiStats.cacheHits = 0;
  searchApiStats.backoffHits = 0;
  searchApiStats.coalesced = 0;
  searchApiStats.statusCounts = {};
  searchApiStats.lastSourceCounts = null;
  searchApiStats.lastProviderRun = null;
  for (const key of Object.keys(indexerStats)) delete indexerStats[key];
  for (const key of Object.keys(indexerHealth)) delete indexerHealth[key];
  delete providerHealth['torbox-torrent-search'];
  delete providerHealth['torbox-usenet-search'];
  recentEvents.length = 0;
  setSearchClientGetForTest(null);
  setClientGetForTest(null);
  setExternalGetForTest(null);
}

function getDiagnostics() {
  pruneNativeSearchCache();
  const searchRate = currentSearchRequestRate();
  const torboxSearchProviders = [
    providerDiagnostic('torbox-torrent-search'),
    providerDiagnostic('torbox-usenet-search'),
  ];

  return {
    indexers: INDEXERS.map(ix => ({
      name: ix.name,
      key: ix.key,
      enabled: providerEnabled(ix.key),
      healthy: isHealthy(ix.name),
      retryAt: indexerHealth[ix.name]?.retryAt || null,
      message: indexerHealth[ix.name]?.message || null,
      zeroCountStreak: indexerStats[ix.key]?.zeroCountStreak || 0,
      lastCount: indexerStats[ix.key]?.lastCount ?? null,
      lastStatus: indexerStats[ix.key]?.lastStatus || null,
      lastMs: indexerStats[ix.key]?.lastMs ?? null,
    })),
    providers: providerConfig(),
    torboxSearch: torboxSearchProviders,
    searchApi: {
      requestRate: searchRate,
      cache: {
        entries: nativeSearchCache.size,
        hits: searchApiStats.cacheHits,
        backoffHits: searchApiStats.backoffHits,
        coalesced: searchApiStats.coalesced,
        inflight: nativeSearchInflight.size,
      },
      statusCounts: { ...searchApiStats.statusCounts },
      backoff: {
        torrent: torboxSearchProviders[0],
        usenet: torboxSearchProviders[1],
      },
      lastRequests: searchApiStats.requestLog.slice(-10).map(entry => ({
        ...entry,
        ts: new Date(entry.ts).toISOString(),
      })),
      lastSourceCounts: searchApiStats.lastSourceCounts,
      lastProviderRun: searchApiStats.lastProviderRun,
    },
    lists: {
      torrent: {
        items: listCaches.torrent.data?.length || 0,
        ageMs: listCaches.torrent.ts ? Date.now() - listCaches.torrent.ts : null,
        cachedIds: Object.keys(downloadIdCaches.torrent).length,
      },
      usenet: {
        enabled: TORBOX_ENABLE_USENET,
        items: listCaches.usenet.data?.length || 0,
        ageMs: listCaches.usenet.ts ? Date.now() - listCaches.usenet.ts : null,
        cachedIds: Object.keys(downloadIdCaches.usenet).length,
      },
    },
    caches: {
      search: searchCache.size,
      nativeSearch: nativeSearchCache.size,
      availability: availabilityCache.size,
    },
    config: {
      nativeSearch: TORBOX_ENABLE_NATIVE_SEARCH,
      usenet: TORBOX_ENABLE_USENET,
      userSearchEngines: TORBOX_SEARCH_USER_ENGINES,
      externalTorrentFallback: EXTERNAL_TORRENT_FALLBACK,
      torrentio: TORRENTIO_ENABLED,
      knightcrawler: KNIGHTCRAWLER_ENABLED,
      providerPriority: providerConfig().effectivePriority,
    },
    recentEvents,
  };
}

module.exports = {
  searchStreams,
  checkCached,
  getMyList,
  getList,
  getStreamUrl,
  getStreamUrlByHash,
  getStreamUrlBySource,
  getDiagnostics,
  encodeSourceRef,
  __private: {
    normalizeTorrent,
    normalizeSearchResult,
    searchResultArrays,
    selectBestFile,
    matchesEpisode,
    dedupeAndParse,
    dedupeNormalized,
    normalizeAvailabilityData,
    applyCacheCheck,
    encodeSourceRef,
    decodeSourceRef,
    searchTorBoxNative,
    searchTorBoxNativeResult,
    setSearchClientGetForTest,
    setClientGetForTest,
    setExternalGetForTest,
    resetSearchReliabilityStateForTest,
    sourceCountBuckets,
    recordLastSourceCounts,
    parseProviderPriority,
    providerConfig,
    fetchExternalProvider,
  },
};

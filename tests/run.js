process.env.NODE_ENV = 'test';

const assert = require('assert');

const torbox = require('../src/api/torbox');
const { filterResultsWithReasons, explainRejection } = require('../src/filters/quality');
const { rankResults } = require('../src/scoring/rank');
const { normalizeBaseUrl, absoluteUrl } = require('../src/config/public-url');

const {
  selectBestFile,
  normalizeSearchResult,
  dedupeNormalized,
  encodeSourceRef,
  decodeSourceRef,
  searchTorBoxNative,
  searchTorBoxNativeResult,
  setSearchClientGetForTest,
  setClientGetForTest,
  setExternalGetForTest,
  resetSearchReliabilityStateForTest,
  recordLastSourceCounts,
  parseProviderPriority,
  providerConfig,
} = torbox.__private;

const tests = [];

function test(name, fn) {
  tests.push({ name, fn });
}

async function runTests() {
  for (const { name, fn } of tests) {
    try {
      await fn();
      console.log(`ok - ${name}`);
    } catch (error) {
      console.error(`not ok - ${name}`);
      console.error(error.stack || error.message);
      process.exitCode = 1;
    }
  }

  if (process.exitCode) process.exit(process.exitCode);
}

function searchResponse(kind, items) {
  return {
    status: 200,
    data: {
      data: {
        [kind === 'usenet' ? 'usenet' : 'torrents']: items,
      },
    },
  };
}

function checkCachedResponse(hash, name = 'Movie.2020.1080p.WEB-DL.mkv') {
  return {
    status: 200,
    data: {
      data: {
        [hash.toLowerCase()]: {
          hash: hash.toLowerCase(),
          name,
          size: 5_000_000_000,
          files: [
            { id: 0, name, size: 5_000_000_000, mimetype: 'video/x-matroska' },
          ],
        },
      },
    },
  };
}

test('selectBestFile picks the matching episode inside a pack', () => {
  const selected = selectBestFile([
    { id: 1, name: 'Show.S01E01.1080p.mkv', size: 2_000_000_000, mimetype: 'video/x-matroska' },
    { id: 2, name: 'Show.S01E02.1080p.mkv', size: 1_900_000_000, mimetype: 'video/x-matroska' },
    { id: 3, name: 'sample.mkv', size: 20_000_000, mimetype: 'video/x-matroska' },
  ], { type: 'series', season: 1, episode: 2 }, 0);

  assert.equal(selected.file.id, 2);
  assert.equal(selected.matchQuality, 'episode');
});

test('selectBestFile rejects multi-episode packs without the requested episode', () => {
  const selected = selectBestFile([
    { id: 1, name: 'Show.S01E03.1080p.mkv', size: 2_000_000_000 },
    { id: 2, name: 'Show.S01E04.1080p.mkv', size: 1_900_000_000 },
  ], { type: 'series', season: 1, episode: 2 }, 0);

  assert.equal(selected.rejectReason, 'no-matching-episode-file-in-pack');
});

test('filterResultsWithReasons hides uncached and fake files by default', () => {
  const { accepted, rejected } = filterResultsWithReasons([
    { hash: 'a', name: 'Movie.2020.1080p.WEB-DL.mkv', cached: true, size: 4_000_000_000 },
    { hash: 'b', name: 'Movie.2020.1080p.WEB-DL.mkv', cached: false, size: 4_000_000_000 },
    { hash: 'c', name: 'Movie.2020.1080p.HDCAM.mkv', cached: true, size: 800_000_000 },
  ], { cachedOnly: true, minQuality: '1080p' });

  assert.equal(accepted.length, 1);
  assert.deepEqual(rejected.map(r => r.reason), ['uncached', 'blocked-release-tag']);
});

test('explainRejection blocks archives and executables masquerading as streams', () => {
  const reason = explainRejection({
    hash: 'd',
    name: 'Movie.2020.1080p.WEB-DL.zip',
    cached: true,
    selectedFile: { name: 'movie.exe', size: 100_000_000 },
  }, { cachedOnly: true, minQuality: '1080p' });

  assert.equal(reason, 'archive-or-executable');
});

test('rankResults keeps cached streams ahead and uses seeders', () => {
  const ranked = rankResults([
    { hash: 'uncached', name: 'Movie.2160p.REMUX.DV.Atmos.mkv', cached: false, seeders: 500, size: 40_000_000_000 },
    { hash: 'cached-low', name: 'Movie.1080p.WEB-DL.mkv', cached: true, seeders: 1, size: 4_000_000_000 },
    { hash: 'cached-high', name: 'Movie.1080p.WEB-DL.mkv', cached: true, seeders: 200, size: 4_000_000_000 },
  ], {});

  assert.equal(ranked[0].hash, 'cached-high');
  assert.equal(ranked[1].hash, 'cached-low');
});

test('normalizeSearchResult maps Usenet search hits into stream candidates', () => {
  const result = normalizeSearchResult({
    id: 0,
    guid: 'abc-def',
    hash: 'USENETHASH',
    title: 'Movie.2020.1080p.WEB-DL.mkv',
    size: 5_000_000_000,
  }, 'usenet', 'movie', {});

  assert.equal(result.kind, 'usenet');
  assert.equal(result.hash, 'usenethash');
  assert.equal(result.cached, true);
  assert.equal(result.searchId, 0);
  assert.equal(result.guid, 'abc-def');
  assert.ok(result.downloadUrl.includes('/usenet/download/0/abc-def'));
});

test('source refs preserve Usenet download details but leave torrents hash based', () => {
  const torrentRef = encodeSourceRef({ kind: 'torrent', hash: 'abc123' });
  assert.equal(torrentRef, 'abc123');

  const usenetRef = encodeSourceRef({
    kind: 'usenet',
    hash: 'def456',
    searchId: 7,
    guid: 'guid-1',
    downloadUrl: 'https://search-api.torbox.app/usenet/download/7/guid-1',
    name: 'Movie.2020.1080p.mkv',
  });
  const decoded = decodeSourceRef(usenetRef);
  assert.equal(decoded.h, 'def456');
  assert.equal(decoded.sid, 7);
  assert.equal(decoded.g, 'guid-1');
  assert.equal(decoded.u, 'https://search-api.torbox.app/usenet/download/7/guid-1');
});

test('dedupeNormalized keeps torrent and Usenet candidates distinct', () => {
  const deduped = dedupeNormalized([
    { kind: 'torrent', hash: 'same', fileId: 0 },
    { kind: 'torrent', hash: 'same', fileId: 0 },
    { kind: 'usenet', hash: 'same', fileId: 0 },
  ]);

  assert.equal(deduped.length, 2);
  assert.deepEqual(deduped.map(item => item.kind), ['torrent', 'usenet']);
});

test('native TorBox Search caches repeated IMDb lookups', async () => {
  resetSearchReliabilityStateForTest();
  let calls = 0;
  setSearchClientGetForTest(async () => {
    calls += 1;
    return searchResponse('torrent', [
      { hash: 'ABC123', title: 'Movie.2020.1080p.WEB-DL.mkv', size: 5_000_000_000 },
    ]);
  });

  const first = await searchTorBoxNative('torrent', 'tt-cache', 'movie', {});
  const second = await searchTorBoxNative('torrent', 'tt-cache', 'movie', {});
  const diagnostics = torbox.getDiagnostics();

  assert.equal(calls, 1);
  assert.equal(first.length, 1);
  assert.equal(second.length, 1);
  assert.equal(diagnostics.searchApi.cache.entries, 1);
  assert.equal(diagnostics.searchApi.cache.hits, 1);
  assert.equal(diagnostics.searchApi.requestRate.requestsLast5m, 1);
});

test('native TorBox Search coalesces concurrent identical lookups', async () => {
  resetSearchReliabilityStateForTest();
  let calls = 0;
  let release;
  const gate = new Promise(resolve => { release = resolve; });
  setSearchClientGetForTest(async () => {
    calls += 1;
    await gate;
    return searchResponse('torrent', [
      { hash: 'DEF456', title: 'Movie.2020.2160p.WEB-DL.mkv', size: 9_000_000_000 },
    ]);
  });

  const first = searchTorBoxNative('torrent', 'tt-coalesce', 'movie', {});
  const second = searchTorBoxNative('torrent', 'tt-coalesce', 'movie', {});
  await Promise.resolve();
  assert.equal(calls, 1);
  release();

  const [firstResult, secondResult] = await Promise.all([first, second]);
  const diagnostics = torbox.getDiagnostics();

  assert.equal(firstResult.length, 1);
  assert.equal(secondResult.length, 1);
  assert.equal(diagnostics.searchApi.cache.coalesced, 1);
  assert.equal(diagnostics.searchApi.requestRate.requestsLast5m, 1);
});

test('native TorBox Search 429 enters backoff and suppresses repeat calls', async () => {
  resetSearchReliabilityStateForTest();
  let calls = 0;
  setSearchClientGetForTest(async () => {
    calls += 1;
    const error = new Error('Request failed with status code 429');
    error.response = {
      status: 429,
      headers: { 'retry-after': '60' },
      data: { detail: 'rate limited' },
    };
    throw error;
  });

  const first = await searchTorBoxNative('torrent', 'tt-429', 'movie', {});
  const second = await searchTorBoxNative('torrent', 'tt-429', 'movie', {});
  const diagnostics = torbox.getDiagnostics();

  assert.equal(calls, 1);
  assert.equal(first.length, 0);
  assert.equal(second.length, 0);
  assert.equal(diagnostics.searchApi.statusCounts['429'], 1);
  assert.equal(diagnostics.searchApi.cache.backoffHits, 1);
  assert.equal(diagnostics.searchApi.requestRate.requestsLast5m, 1);
  assert.equal(diagnostics.searchApi.backoff.torrent.healthy, false);
});

test('diagnostics expose last stream source counts', () => {
  resetSearchReliabilityStateForTest();
  recordLastSourceCounts([
    { source: 'torbox-torrent-search' },
    { source: 'torrent-library' },
    { source: 'torbox-usenet-search' },
    { source: 'Torrentio' },
    { source: 'Knightcrawler' },
  ], { imdbId: 'tt-diag', type: 'movie', cache: 'fresh' });

  const counts = torbox.getDiagnostics().searchApi.lastSourceCounts;
  assert.equal(counts.labels['TorBox Native Torrent Search'], 1);
  assert.equal(counts.labels['TorBox Native Usenet Search'], 1);
  assert.equal(counts.labels['TorBox Library/My List'], 1);
  assert.equal(counts.labels['Torrentio fallback'], 1);
  assert.equal(counts.labels['Knightcrawler fallback'], 1);
  assert.equal(counts.bySource['torbox-torrent-search'], 1);
  assert.equal(counts.streams[0].providerLabel, 'TorBox Native Torrent Search');
});

test('provider priority parser keeps external providers behind TorBox providers', () => {
  assert.deepEqual(
    parseProviderPriority('torrentio,knightcrawler,torbox-usenet'),
    ['torbox-usenet', 'torbox-torrent', 'library', 'torrentio', 'knightcrawler']
  );
});

test('external provider disable env vars are reflected in diagnostics', () => {
  const config = providerConfig(undefined, {
    TORRENTIO_ENABLED: false,
    KNIGHTCRAWLER_ENABLED: false,
  });
  assert.equal(config.enabled.torrentio, false);
  assert.equal(config.enabled.knightcrawler, false);
});

test('searchStreams falls back to Torrentio on native 429 and leaves Knightcrawler last', async () => {
  resetSearchReliabilityStateForTest();
  let searchCalls = 0;
  const externalCalls = [];
  setSearchClientGetForTest(async () => {
    searchCalls += 1;
    const error = new Error('Request failed with status code 429');
    error.response = {
      status: 429,
      headers: {},
      data: { detail: 'rate limited' },
    };
    throw error;
  });
  setExternalGetForTest(async url => {
    externalCalls.push(url);
    if (url.includes('torrentio')) {
      return {
        data: {
          streams: Array.from({ length: 8 }, (_, index) => ({
            infoHash: `torrentiohash${index}`,
            title: `Movie.2020.1080p.WEB-DL.Part${index}.mkv`,
            fileSize: 5_000_000_000,
            fileIdx: 0,
          })),
        },
      };
    }
    throw new Error('Knightcrawler should not be called once Torrentio meets the target');
  });
  setClientGetForTest(async (requestPath, config = {}) => {
    if (requestPath.includes('/torrents/checkcached')) {
      const hashes = String(config.params.hash || '').split(',').filter(Boolean);
      return {
        status: 200,
        data: {
          data: Object.fromEntries(hashes.map((hash, index) => [
            hash.toLowerCase(),
            checkCachedResponse(hash, `Movie.2020.1080p.WEB-DL.Part${index}.mkv`).data.data[hash.toLowerCase()],
          ])),
        },
      };
    }
    return { status: 200, data: { data: [] } };
  });

  const results = await torbox.searchStreams('tt-fallback', 'movie', {});
  const diagnostics = torbox.getDiagnostics();

  assert.equal(searchCalls, 2);
  assert.equal(results.length, 8);
  assert.equal(externalCalls.length, 1);
  assert.ok(externalCalls[0].includes('torrentio'));
  assert.equal(diagnostics.searchApi.lastProviderRun.fallbackReason, 'torbox_search_rate_limited');
  assert.equal(diagnostics.searchApi.lastSourceCounts.labels['Torrentio fallback'], 8);
  assert.equal(diagnostics.searchApi.lastSourceCounts.labels['Knightcrawler fallback'], 0);
  assert.deepEqual(diagnostics.providers.effectivePriority, [
    'torbox-torrent',
    'torbox-usenet',
    'library',
    'torrentio',
    'knightcrawler',
  ]);
  assert.equal(
    diagnostics.searchApi.lastProviderRun.providersAttempted.find(item => item.provider === 'knightcrawler').status,
    'skipped_target_met'
  );
});

test('public URL helpers normalize domains and request hosts', () => {
  assert.equal(normalizeBaseUrl('streamvault.example.com/'), 'https://streamvault.example.com');
  assert.equal(absoluteUrl('/proxy/stream/abc/2', {
    headers: { 'x-forwarded-proto': 'https', 'x-forwarded-host': 'sv.example.com' },
    protocol: 'http',
    get: () => 'localhost:7000',
  }), 'https://sv.example.com/proxy/stream/abc/2');
});

runTests();

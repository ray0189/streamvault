#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  StreamVault — Self-hosted TorBox Stremio Addon              ║
# ║  github.com/ray0189/streamvault                              ║
# ║                                                              ║
# ║  curl -fsSL https://raw.githubusercontent.com/              ║
# ║    ray0189/streamvault/main/install.sh | bash                ║
# ╚══════════════════════════════════════════════════════════════╝
set -euo pipefail

R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m'
C='\033[0;36m' W='\033[1;37m' DIM='\033[2m'
NC='\033[0m'   BOLD='\033[1m'

step() { echo -e "\n${C}▶${NC} ${BOLD}$*${NC}"; }
ok()   { echo -e "  ${G}✓${NC} $*"; }
warn() { echo -e "  ${Y}⚠${NC}  $*"; }
err()  { echo -e "\n  ${R}✗ $*${NC}\n"; exit 1; }
sep()  { echo -e "\n  ${DIM}──────────────────────────────────────────${NC}"; }
ask()  { echo -e "\n  ${W}$*${NC}"; }

INSTALL_DIR="$HOME/streamvault"
CLI_BIN="/usr/local/bin/streamvault"
SVC="streamvault"
SUDO=""
[[ $EUID -ne 0 ]] && SUDO="sudo"

# ── Banner ────────────────────────────────────────────────────
clear
echo -e "${C}${BOLD}"
echo '  ____  _                        _   _             _ _  '
echo ' / ___|| |_ _ __ ___  __ _ _ __ | | | | __ _ _   _| | |'
echo ' \___ \| __| '"'"'__/ _ \/ _` | '"'"'_ \| | | |/ _` | | | | | |'
echo '  ___) | |_| | |  __/ (_| | | | | |_| | (_| | |_| | | |'
echo ' |____/ \__|_|  \___|\__,_|_| |_|\___/ \__,_|\__,_|_|_|'
echo -e "${NC}"
echo -e "  ${DIM}Self-hosted TorBox Stremio Addon — installer v1.0${NC}\n"

# ══════════════════════════════════════════════════════════════
#  SYSTEM CHECKS
# ══════════════════════════════════════════════════════════════
step "Checking system"
[[ "$(uname -s)" != "Linux" ]] && err "Linux required (Ubuntu/Debian recommended)"
for cmd in curl git python3; do
  command -v "$cmd" &>/dev/null && ok "$cmd" \
    || err "$cmd required — sudo apt install $cmd"
done

step "Node.js"
if command -v node &>/dev/null && node -e "process.exit(parseInt(process.version.slice(1))<18?1:0)" 2>/dev/null; then
  ok "Node.js $(node --version)"
else
  echo -e "  ${DIM}Installing Node.js v22...${NC}"
  curl -fsSL https://deb.nodesource.com/setup_22.x | $SUDO bash - &>/dev/null
  $SUDO apt-get install -y nodejs &>/dev/null
  ok "Node.js $(node --version)"
fi

step "Redis"
if command -v docker &>/dev/null && docker ps 2>/dev/null | grep -q redis; then
  ok "Redis running (Docker)"
elif $SUDO systemctl is-active --quiet redis-server 2>/dev/null; then
  ok "Redis running (system)"
elif command -v docker &>/dev/null; then
  docker run -d --name redis --restart always -p 6379:6379 redis:alpine &>/dev/null
  ok "Redis started (Docker)"
else
  $SUDO apt-get install -y redis-server &>/dev/null
  $SUDO systemctl enable --now redis-server &>/dev/null
  ok "Redis installed"
fi

# ══════════════════════════════════════════════════════════════
#  WIZARD
# ══════════════════════════════════════════════════════════════
sep
echo -e "\n  ${W}${BOLD}Setup Wizard${NC}"
echo -e "  ${DIM}Press Enter to accept defaults in [brackets]${NC}\n"

ask "TorBox API key — torbox.app/settings"
while true; do
  read -rp "  › " TORBOX_KEY
  [[ -n "$TORBOX_KEY" ]] && break
  echo -e "  ${R}Required${NC}"
done

ask "Admin password for the streamvault CLI (min 6 chars)"
while true; do
  read -rsp "  › " ADMIN_PASS; echo ""
  [[ ${#ADMIN_PASS} -ge 6 ]] && break
  echo -e "  ${R}Min 6 characters${NC}"
done

ask "Port [7000]"
read -rp "  › " PORT_IN
PORT="${PORT_IN:-7000}"

sep
echo -e "\n  ${W}${BOLD}Access method${NC}\n"
echo -e "  ${C}1${NC}  Cloudflare Tunnel  ${DIM}Public HTTPS, needs a domain${NC}"
echo -e "  ${C}2${NC}  Tailscale          ${DIM}Private, no domain needed${NC}"
echo -e "  ${C}3${NC}  Local only         ${DIM}Home network only${NC}"
echo -e "  ${C}4${NC}  All three"
echo ""
while true; do
  read -rp "  › " ACCESS
  [[ "$ACCESS" =~ ^[1-4]$ ]] && break
  echo -e "  ${R}Enter 1-4${NC}"
done

CF_ENABLED=false; TS_ENABLED=false
CF_DOMAIN=""; CF_SUBDOMAIN="streamvault"; CF_TOKEN=""
CF_ACCESS=false; CF_COUNTRY_BLOCK=false; CF_RATE_LIMIT=60
TS_AUTH_KEY=""; TS_HOSTNAME="streamvault"

setup_cf() {
  sep
  echo -e "\n  ${W}${BOLD}Cloudflare Tunnel${NC}"
  echo -e "  ${DIM}Token: dash.cloudflare.com/profile/api-tokens${NC}"
  echo -e "  ${DIM}Perms: Zone:DNS:Edit + Account:Cloudflare Tunnel:Edit${NC}\n"
  ask "Cloudflare API token"
  while true; do read -rsp "  › " CF_TOKEN; echo ""; [[ -n "$CF_TOKEN" ]] && break; echo -e "  ${R}Required${NC}"; done
  ask "Your domain (e.g. yourdomain.com)"
  while true; do read -rp "  › " CF_DOMAIN; [[ -n "$CF_DOMAIN" ]] && break; echo -e "  ${R}Required${NC}"; done
  ask "Subdomain [streamvault]"
  read -rp "  › " CF_SUB_IN; CF_SUBDOMAIN="${CF_SUB_IN:-streamvault}"
  ask "Require login before addon is reachable? (Cloudflare Access) [y/N]"
  read -rp "  › " CF_ACC_IN; [[ "${CF_ACC_IN,,}" == "y" ]] && CF_ACCESS=true
  ask "Block all countries except yours? [y/N]"
  read -rp "  › " CF_CB_IN; [[ "${CF_CB_IN,,}" == "y" ]] && CF_COUNTRY_BLOCK=true
  ask "Rate limit per IP per minute [60]"
  read -rp "  › " CF_RL_IN; CF_RATE_LIMIT="${CF_RL_IN:-60}"
  CF_ENABLED=true
}

setup_ts() {
  sep
  echo -e "\n  ${W}${BOLD}Tailscale${NC}"
  echo -e "  ${DIM}Auth key: login.tailscale.com/admin/settings/keys${NC}\n"
  ask "Tailscale auth key"
  while true; do read -rsp "  › " TS_AUTH_KEY; echo ""; [[ -n "$TS_AUTH_KEY" ]] && break; echo -e "  ${R}Required${NC}"; done
  ask "Device hostname [streamvault]"
  read -rp "  › " TS_HOST_IN; TS_HOSTNAME="${TS_HOST_IN:-streamvault}"
  TS_ENABLED=true
}

case "$ACCESS" in
  1) setup_cf ;;
  2) setup_ts ;;
  3) true ;;
  4) setup_cf; setup_ts ;;
esac

sep
echo -e "\n  ${W}${BOLD}Quality defaults${NC}\n"
ask "Minimum resolution [1080p]  (480p/720p/1080p/2160p)"
read -rp "  › " RES_IN;    MIN_RES="${RES_IN:-1080p}"
ask "Cached streams only? [Y/n]"
read -rp "  › " CACHED_IN; [[ "${CACHED_IN,,}" == "n" ]] && CACHED_ONLY=false || CACHED_ONLY=true
ask "Prefer HEVC/x265? [Y/n]"
read -rp "  › " HEVC_IN;   [[ "${HEVC_IN,,}" == "n" ]]  && PREFER_HEVC=false  || PREFER_HEVC=true
ask "Prefer HDR/Dolby Vision? [Y/n]"
read -rp "  › " HDR_IN;    [[ "${HDR_IN,,}" == "n" ]]   && PREFER_HDR=false   || PREFER_HDR=true
ask "Prefer Atmos/TrueHD? [Y/n]"
read -rp "  › " ATMOS_IN;  [[ "${ATMOS_IN,,}" == "n" ]] && PREFER_ATMOS=false || PREFER_ATMOS=true
ask "Preferred audio language [en]  (en/ar/fr/es/de/any)"
read -rp "  › " LANG_IN;   PREF_LANG="${LANG_IN:-en}"
ask "Max file size GB [80]  (0=no limit)"
read -rp "  › " SIZE_IN;   MAX_SIZE="${SIZE_IN:-80}"

# ══════════════════════════════════════════════════════════════
#  WRITE SOURCE FILES
# ══════════════════════════════════════════════════════════════
step "Writing source files"

mkdir -p "$INSTALL_DIR"/{src/{addon,api,cache,config,filters,profiles,scoring},data,dashboard}

# ── package.json ──────────────────────────────────────────────
cat > "$INSTALL_DIR/package.json" << 'EOF'
{
  "name": "streamvault",
  "version": "1.0.0",
  "description": "Self-hosted TorBox Stremio addon",
  "main": "src/server.js",
  "scripts": {
    "start": "node src/server.js",
    "dev": "nodemon src/server.js"
  },
  "dependencies": {
    "axios": "^1.6.0",
    "chalk": "^4.1.2",
    "cors": "^2.8.5",
    "dotenv": "^16.3.1",
    "express": "^4.18.2",
    "express-rate-limit": "^7.1.5",
    "ioredis": "^5.3.2",
    "morgan": "^1.10.0",
    "node-cache": "^5.1.2",
    "uuid": "^9.0.0"
  },
  "devDependencies": {
    "nodemon": "^3.0.1"
  }
}
EOF

# ── .gitignore ────────────────────────────────────────────────
cat > "$INSTALL_DIR/.gitignore" << 'EOF'
.env
data/
node_modules/
*.log
*.tar.gz
.DS_Store
EOF

# ── src/server.js ─────────────────────────────────────────────
cat > "$INSTALL_DIR/src/server.js" << 'EOF'
require('dotenv').config();
const express = require('express');
const cors    = require('cors');
const morgan  = require('morgan');
const path    = require('path');
const chalk   = require('chalk');

const addonRouter = require('./addon/router');
const apiRouter   = require('./api/router');
const { PORT, HOST, NODE_ENV } = require('./config/env');

const app = express();
app.use(cors());
app.use(express.json());
app.use(morgan(NODE_ENV === 'production' ? 'combined' : 'dev'));
app.use(express.static(path.join(__dirname, '../dashboard')));
app.use('/config', addonRouter);
app.use('/api', apiRouter);
app.get('/', (req, res) => res.sendFile(path.join(__dirname, '../dashboard/index.html')));
app.get('/health', (req, res) => res.json({ status: 'ok', ts: Date.now() }));
app.use((req, res) => res.status(404).json({ error: 'Not found' }));

app.listen(PORT, HOST, () => {
  console.log('');
  console.log(chalk.bold.cyan('  ╔══════════════════════════════════════╗'));
  console.log(chalk.bold.cyan('  ║      StreamVault — Running           ║'));
  console.log(chalk.bold.cyan('  ╚══════════════════════════════════════╝'));
  console.log('');
  console.log(chalk.green(`  ► http://${HOST}:${PORT}`));
  console.log(chalk.green(`  ► Health: http://localhost:${PORT}/health`));
  console.log('');
});
EOF

# ── src/config/env.js ─────────────────────────────────────────
cat > "$INSTALL_DIR/src/config/env.js" << 'EOF'
module.exports = {
  PORT:             process.env.PORT             || 7000,
  HOST:             process.env.HOST             || '0.0.0.0',
  NODE_ENV:         process.env.NODE_ENV         || 'development',
  TORBOX_API_KEY:   process.env.TORBOX_API_KEY   || '',
  TORBOX_API_URL:   process.env.TORBOX_API_URL   || 'https://api.torbox.app/v1/api',
  STREAM_CACHE_TTL: parseInt(process.env.STREAM_CACHE_TTL) || 300,
  META_CACHE_TTL:   parseInt(process.env.META_CACHE_TTL)   || 3600,
  ADMIN_PASSWORD:   process.env.ADMIN_PASSWORD   || 'changeme',
  NAS_LOCAL_IP:     process.env.NAS_LOCAL_IP     || '',
  CF_ENABLED:       process.env.CF_ENABLED        === 'true',
  CF_DOMAIN:        process.env.CF_DOMAIN         || '',
  CF_SUBDOMAIN:     process.env.CF_SUBDOMAIN      || 'streamvault',
  TS_ENABLED:       process.env.TS_ENABLED        === 'true',
  TS_HOSTNAME:      process.env.TS_HOSTNAME       || '',
};
EOF

# ── src/config/defaults.js ────────────────────────────────────
cat > "$INSTALL_DIR/src/config/defaults.js" << 'EOF'
module.exports = {
  minQuality:  '1080p',
  cachedOnly:  true,
  blockedTags: ['CAM','TS','HDCAM','SCR','DVDSCR','TELECINE','TELESYNC','HC','R5'],
  scoring: {
    resolution4K: 12,
    dolbyVision:  10,
    hevc:         10,
    hdrPlus:       9,
    remux:         9,
    hdr:           8,
    bluray:        7,
    atmos:         6,
    webdl:         6,
    trueHD:        5,
    webrip:        3,
    dts:           3,
    h264:          1,
  },
  resolutionRank: { '2160p':5,'4k':5,'1440p':4,'1080p':3,'720p':2,'480p':1,'360p':0 },
};
EOF

# ── src/cache/store.js ────────────────────────────────────────
cat > "$INSTALL_DIR/src/cache/store.js" << 'EOF'
const NodeCache = require('node-cache');
const Redis     = require('ioredis');
const { STREAM_CACHE_TTL, META_CACHE_TTL } = require('../config/env');

const streamCache = new NodeCache({ stdTTL: STREAM_CACHE_TTL, checkperiod: 60 });
const metaCache   = new NodeCache({ stdTTL: META_CACHE_TTL,   checkperiod: 120 });

let redis = null;
try {
  redis = new Redis({ host: '127.0.0.1', port: 6379, lazyConnect: true, connectTimeout: 2000 });
  redis.connect()
    .then(() => console.log('[Redis] Connected'))
    .catch(() => { redis = null; });
} catch { redis = null; }

function cacheKey(...parts) { return parts.join(':'); }

async function getStreams(key) {
  if (redis) { try { const v = await redis.get('stream:'+key); if (v) return JSON.parse(v); } catch {} }
  return streamCache.get(key) || null;
}

async function setStreams(key, value) {
  if (redis) { try { await redis.setex('stream:'+key, STREAM_CACHE_TTL, JSON.stringify(value)); } catch {} }
  streamCache.set(key, value);
}

function getMeta(key)        { return metaCache.get(key) || null; }
function setMeta(key, value) { metaCache.set(key, value); }

function stats() {
  return { streams: streamCache.getStats(), meta: metaCache.getStats(), redis: redis ? 'connected' : 'disconnected' };
}

module.exports = { cacheKey, getStreams, setStreams, getMeta, setMeta, stats, redis };
EOF

# ── src/filters/quality.js ────────────────────────────────────
cat > "$INSTALL_DIR/src/filters/quality.js" << 'EOF'
const defaults = require('../config/defaults');

const RES_PATTERNS = [
  { regex: /\b(2160p|4k|uhd)\b/i, res: '2160p' },
  { regex: /\b1440p\b/i,           res: '1440p' },
  { regex: /\b1080p\b/i,           res: '1080p' },
  { regex: /\b720p\b/i,            res: '720p'  },
  { regex: /\b480p\b/i,            res: '480p'  },
];

function detectResolution(name = '') {
  for (const { regex, res } of RES_PATTERNS) {
    if (regex.test(name)) return res;
  }
  return null;
}

function isBlocked(name = '', blockedTags = defaults.blockedTags) {
  const upper = name.toUpperCase();
  return blockedTags.some(tag => {
    const pattern = new RegExp(`(^|[\\s.\\-_\\[\\(])${tag}([\\s.\\-_\\]\\)]|$)`, 'i');
    return pattern.test(upper);
  });
}

function meetsMinQuality(name = '', minQuality = '1080p') {
  const res = detectResolution(name);
  if (!res) return false;
  const rank    = defaults.resolutionRank;
  const minRank = rank[minQuality.toLowerCase()] ?? rank['1080p'];
  const resRank = rank[res.toLowerCase()] ?? 0;
  return resRank >= minRank;
}

function filterResults(torrents = [], prefs = {}) {
  const minQuality  = prefs.minQuality  || defaults.minQuality;
  const blockedTags = prefs.blockedTags || defaults.blockedTags;
  const cachedOnly  = prefs.cachedOnly !== undefined ? prefs.cachedOnly : defaults.cachedOnly;
  return torrents.filter(t => {
    const name = t.name || t.title || '';
    if (isBlocked(name, blockedTags))      return false;
    if (!meetsMinQuality(name, minQuality)) return false;
    if (cachedOnly && !t.cached)            return false;
    return true;
  });
}

module.exports = { filterResults, detectResolution, isBlocked, meetsMinQuality };
EOF

# ── src/scoring/rank.js ───────────────────────────────────────
cat > "$INSTALL_DIR/src/scoring/rank.js" << 'EOF'
const defaults = require('../config/defaults');
const { detectResolution } = require('../filters/quality');

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

function detectFeatures(name = '') {
  const result = {};
  for (const [key, pattern] of Object.entries(FEATURE_PATTERNS)) {
    result[key] = pattern.test(name);
  }
  result.resolution4K = detectResolution(name) === '2160p';
  return result;
}

function scoreTorrent(torrent, prefs = {}) {
  const weights  = { ...defaults.scoring, ...(prefs.scoring || {}) };
  const name     = torrent.name || torrent.title || '';
  const features = detectFeatures(name);
  let score = 0;
  for (const [feature, active] of Object.entries(features)) {
    if (active && weights[feature]) score += weights[feature];
  }
  if (torrent.seeds > 0) score += Math.min(Math.log10(torrent.seeds) * 2, 5);
  const sizeGB = (torrent.size || 0) / 1e9;
  if (sizeGB < 0.5) score -= 5;
  return Math.round(score * 10) / 10;
}

function rankResults(torrents = [], prefs = {}) {
  return torrents
    .map(t => ({ ...t, _score: scoreTorrent(t, prefs), _features: detectFeatures(t.name || t.title || '') }))
    .sort((a, b) => b._score - a._score);
}

module.exports = { rankResults, scoreTorrent, detectFeatures };
EOF

# ── src/profiles/store.js ─────────────────────────────────────
cat > "$INSTALL_DIR/src/profiles/store.js" << 'EOF'
const fs   = require('fs');
const path = require('path');
const { v4: uuidv4 } = require('uuid');
const defaults = require('../config/defaults');

const STORE_PATH = path.join(__dirname, '../../data/profiles.json');

function ensureDataDir() {
  const dir = path.dirname(STORE_PATH);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
}

function load() {
  ensureDataDir();
  if (!fs.existsSync(STORE_PATH)) return {};
  try { return JSON.parse(fs.readFileSync(STORE_PATH, 'utf8')); }
  catch { return {}; }
}

function save(profiles) {
  ensureDataDir();
  fs.writeFileSync(STORE_PATH, JSON.stringify(profiles, null, 2));
}

function createProfile(name = 'Default', overrides = {}) {
  const profiles = load();
  const configId = uuidv4();
  profiles[configId] = {
    configId,
    name,
    createdAt: new Date().toISOString(),
    prefs: { ...defaults, ...overrides },
  };
  save(profiles);
  return configId;
}

function getProfile(configId)    { return load()[configId] || null; }
function listProfiles()          { return Object.values(load()); }

function updateProfile(configId, updates) {
  const profiles = load();
  if (!profiles[configId]) return null;
  profiles[configId].prefs = { ...profiles[configId].prefs, ...updates };
  profiles[configId].updatedAt = new Date().toISOString();
  save(profiles);
  return profiles[configId];
}

function deleteProfile(configId) {
  const profiles = load();
  if (!profiles[configId]) return false;
  delete profiles[configId];
  save(profiles);
  return true;
}

module.exports = { createProfile, getProfile, listProfiles, updateProfile, deleteProfile };
EOF

# ── src/api/torbox.js ─────────────────────────────────────────
cat > "$INSTALL_DIR/src/api/torbox.js" << 'EOF'
const axios = require('axios');
const cache = require('../cache/store');
const { TORBOX_API_KEY, TORBOX_API_URL } = require('../config/env');

const client = axios.create({
  baseURL: TORBOX_API_URL,
  headers: { Authorization: `Bearer ${TORBOX_API_KEY}`, 'Content-Type': 'application/json' },
  timeout: 15000,
});

const searchClient = axios.create({
  baseURL: 'https://search-api.torbox.app',
  timeout: 15000,
});

const torrentIdCache = {};

async function prewarm() {
  try {
    const res = await client.get('/torrents/mylist', { params: { bypass_cache: true } });
    const torrents = res.data?.data || [];
    for (const t of torrents) {
      if (t.hash && t.id) {
        torrentIdCache[t.hash.toLowerCase()] = t.id;
        if (cache.redis) {
          await cache.redis.setex(`tid:${t.hash.toLowerCase()}`, 86400, String(t.id));
        }
      }
    }
    console.log(`[TorBox] Pre-warmed ${Object.keys(torrentIdCache).length} torrent IDs`);
  } catch (err) {
    console.warn('[TorBox] Pre-warm error:', err.message);
  }
}

setTimeout(prewarm, 5000);

async function searchStreams(imdbId, type, opts = {}) {
  try {
    let url = `/torrents/imdb:${imdbId}`;
    if (type === 'series' && opts.season) {
      url += `?season=${opts.season}&episode=${opts.episode || 1}`;
    }
    const res = await searchClient.get(url);
    const results = res.data?.data || res.data || [];
    console.log(`[TorBox] Found ${results.length} torrents`);
    if (!results.length) return [];

    const hashes = results.map(r => r.hash).filter(Boolean);
    const cached = await checkCached(hashes);
    return results.map(r => ({ ...r, cached: !!(cached[r.hash?.toLowerCase()] || cached[r.hash]) }));
  } catch (err) {
    console.error('[TorBox] searchStreams error:', err.message);
    return [];
  }
}

async function getStreamUrl(torrentId, fileId = 0) {
  try {
    const res = await client.get('/torrents/requestdl', {
      params: { token: TORBOX_API_KEY, torrent_id: torrentId, file_id: fileId, zip_link: false },
    });
    return res.data?.data || null;
  } catch (err) {
    console.error('[TorBox] getStreamUrl error:', err.message);
    return null;
  }
}

async function checkCached(hashes = []) {
  try {
    const res = await client.get('/torrents/checkcached', {
      params: { hash: hashes.join(','), format: 'object', list_files: false },
    });
    return res.data?.data || {};
  } catch (err) {
    console.error('[TorBox] checkCached error:', err.message);
    return {};
  }
}

module.exports = { searchStreams, getStreamUrl, checkCached };
EOF

# ── src/api/router.js ─────────────────────────────────────────
cat > "$INSTALL_DIR/src/api/router.js" << 'EOF'
const express      = require('express');
const rateLimit    = require('express-rate-limit');
const router       = express.Router();
const profileStore = require('../profiles/store');
const cache        = require('../cache/store');
const { ADMIN_PASSWORD, PORT, NAS_LOCAL_IP, CF_ENABLED, CF_DOMAIN, CF_SUBDOMAIN, TS_ENABLED, TS_HOSTNAME } = require('../config/env');

function adminAuth(req, res, next) {
  const token = req.headers['x-admin-token'] || req.query.token;
  if (token !== ADMIN_PASSWORD) return res.status(401).json({ error: 'Unauthorised' });
  next();
}

const createLimiter = rateLimit({ windowMs: 60_000, max: 10 });

router.get('/profiles', adminAuth, (req, res) => res.json(profileStore.listProfiles()));

router.post('/profiles', adminAuth, createLimiter, (req, res) => {
  const { name = 'New Profile', prefs = {} } = req.body;
  const configId = profileStore.createProfile(name, prefs);
  const profile  = profileStore.getProfile(configId);
  res.json({ ...profile, manifestUrls: buildUrls(configId) });
});

router.get('/profiles/:id', adminAuth, (req, res) => {
  const p = profileStore.getProfile(req.params.id);
  if (!p) return res.status(404).json({ error: 'Not found' });
  res.json({ ...p, manifestUrls: buildUrls(req.params.id) });
});

router.patch('/profiles/:id', adminAuth, (req, res) => {
  const updated = profileStore.updateProfile(req.params.id, req.body);
  if (!updated) return res.status(404).json({ error: 'Not found' });
  res.json(updated);
});

router.delete('/profiles/:id', adminAuth, (req, res) => {
  const ok = profileStore.deleteProfile(req.params.id);
  if (!ok) return res.status(404).json({ error: 'Not found' });
  res.json({ deleted: true });
});

router.get('/cache/stats', adminAuth, (req, res) => res.json(cache.stats()));

router.get('/info', adminAuth, (req, res) => res.json({
  status: 'ok',
  port: PORT,
  nasIp: NAS_LOCAL_IP,
  publicUrl: CF_ENABLED ? `${CF_SUBDOMAIN}.${CF_DOMAIN}` : null,
  tailscale: TS_ENABLED ? TS_HOSTNAME : null,
  redis: cache.redis ? 'connected' : 'disconnected',
  uptime: process.uptime(),
}));

function buildUrls(configId) {
  const p = `/config/${configId}/manifest.json`;
  return {
    local:     `http://localhost:${PORT}${p}`,
    lan:       NAS_LOCAL_IP ? `http://${NAS_LOCAL_IP}:${PORT}${p}` : null,
    public:    CF_ENABLED   ? `https://${CF_SUBDOMAIN}.${CF_DOMAIN}${p}` : null,
    tailscale: TS_ENABLED   ? `http://${TS_HOSTNAME}:${PORT}${p}` : null,
  };
}

module.exports = router;
EOF

# ── src/addon/router.js ───────────────────────────────────────
cat > "$INSTALL_DIR/src/addon/router.js" << 'EOF'
const express = require('express');
const router  = express.Router();
const { getProfile }    = require('../profiles/store');
const { buildManifest } = require('./manifest');
const { handleStream }  = require('./streams');

router.use('/:configId/*', (req, res, next) => {
  const profile = getProfile(req.params.configId);
  if (!profile) return res.status(404).json({ error: 'Unknown config ID' });
  req.profile = profile;
  next();
});

router.get('/:configId/manifest.json', (req, res) => {
  res.setHeader('Content-Type', 'application/json');
  res.json(buildManifest(req.profile));
});

router.get('/:configId/stream/:type/:id.json', async (req, res) => {
  const { type, id } = req.params;
  try {
    const streams = await handleStream(type, id, req.profile);
    res.json({ streams });
  } catch (err) {
    console.error('[Stream] Error:', err.message);
    res.json({ streams: [] });
  }
});

module.exports = router;
EOF

# ── src/addon/manifest.js ─────────────────────────────────────
cat > "$INSTALL_DIR/src/addon/manifest.js" << 'EOF'
const { CF_ENABLED, CF_DOMAIN, CF_SUBDOMAIN, TS_ENABLED, TS_HOSTNAME, NAS_LOCAL_IP, PORT } = require('../config/env');

function buildManifest(profile) {
  const { configId, name, prefs } = profile;
  const qualityNote = [
    prefs.minQuality || '1080p',
    prefs.cachedOnly ? 'Cached' : 'All',
    prefs.scoring?.hevc > 0 ? 'HEVC' : '',
    prefs.scoring?.dolbyVision > 0 ? 'DV' : '',
  ].filter(Boolean).join(' · ');

  return {
    id:          `community.streamvault.${configId}`,
    version:     '1.0.0',
    name:        `⚡ ${name}`,
    description: `StreamVault — ${qualityNote}`,
    resources:   ['stream'],
    types:       ['movie', 'series'],
    idPrefixes:  ['tt'],
    behaviorHints: { adult: false, p2p: false },
  };
}

module.exports = { buildManifest };
EOF

# ── src/addon/streams.js ──────────────────────────────────────
cat > "$INSTALL_DIR/src/addon/streams.js" << 'EOF'
const torbox            = require('../api/torbox');
const { filterResults } = require('../filters/quality');
const { rankResults }   = require('../scoring/rank');
const cache             = require('../cache/store');
const { detectResolution } = require('../filters/quality');

function parseId(type, id) {
  if (type === 'series') {
    const [imdbId, season, episode] = id.split(':');
    return { imdbId, season: parseInt(season), episode: parseInt(episode) };
  }
  return { imdbId: id };
}

function formatStream(torrent, profile) {
  const name  = torrent.name || torrent.title || 'Unknown';
  const res   = detectResolution(name) || '?';
  const score = torrent._score || 0;
  const feats = torrent._features || {};
  const tags  = [];
  if (feats.remux)        tags.push('REMUX');
  if (feats.bluray)       tags.push('BluRay');
  if (feats.webdl)        tags.push('WEB-DL');
  if (feats.hevc)         tags.push('HEVC');
  if (feats.dolbyVision)  tags.push('DV');
  else if (feats.hdrPlus) tags.push('HDR10+');
  else if (feats.hdr)     tags.push('HDR');
  if (feats.atmos)        tags.push('Atmos');
  else if (feats.trueHD)  tags.push('TrueHD');
  const sizeGB = torrent.size ? `${(torrent.size/1e9).toFixed(1)} GB` : '';

  return {
    name:        `⚡ ${res} ${tags.join(' ')}`.trim(),
    description: `${name}\n${sizeGB ? `💾 ${sizeGB}` : ''}  ★ ${score}`.trim(),
    url:         torrent.url || `https://api.torbox.app/v1/api/torrents/requestdl?token=${process.env.TORBOX_API_KEY}&torrent_id=${torrent.id}&file_id=${torrent.file_id||0}&zip_link=false`,
    behaviorHints: { notWebReady: false, bingeGroup: `sv-${profile.configId}` },
  };
}

async function handleStream(type, rawId, profile) {
  const { imdbId, season, episode } = parseId(type, rawId);
  const cacheKey = cache.cacheKey('stream', profile.configId, rawId);
  const cached   = await cache.getStreams(cacheKey);
  if (cached) { console.log(`[Stream] Cache HIT — ${rawId}`); return cached; }

  console.log(`[Stream] Searching TorBox for ${imdbId} (${type})`);
  const raw      = await torbox.searchStreams(imdbId, type, { season, episode });
  if (!raw.length) return [];

  const filtered = filterResults(raw, profile.prefs);
  console.log(`[Stream] ${raw.length} raw → ${filtered.length} after filter`);
  if (!filtered.length) return [];

  const ranked  = rankResults(filtered, profile.prefs);
  const streams = ranked.slice(0, 10).map(t => formatStream(t, profile));
  await cache.setStreams(cacheKey, streams);
  return streams;
}

module.exports = { handleStream };
EOF

# ── dashboard/index.html ──────────────────────────────────────
cat > "$INSTALL_DIR/dashboard/index.html" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>StreamVault</title>
<link href="https://fonts.googleapis.com/css2?family=Instrument+Sans:wght@400;500;600&family=Instrument+Serif:ital@0;1&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet"/>
<style>
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
html,body{height:100%}
:root{--bg:#07080a;--s1:#0c0e11;--s2:#111418;--s3:#17191d;--s4:#1e2127;--b1:#ffffff08;--b2:#ffffff10;--b3:#ffffff18;--b4:#ffffff24;--text:#dde1e8;--t2:#8891a0;--t3:#454d5a;--gold:#c8a96e;--gold2:#e2c98a;--gb:#c8a96e0d;--gbr:#c8a96e22;--green:#3ecf7e;--grb:#3ecf7e0c;--grbr:#3ecf7e22;--red:#e05555;--rb:#e055550c;--rbr:#e0555522;--sw:220px}
body{font-family:'Instrument Sans',sans-serif;background:var(--bg);color:var(--text);display:flex;-webkit-font-smoothing:antialiased}
#sb{width:var(--sw);min-width:var(--sw);height:100vh;position:sticky;top:0;background:var(--s1);border-right:1px solid var(--b1);display:flex;flex-direction:column}
.sb-top{padding:24px 20px 22px;border-bottom:1px solid var(--b1)}
.sb-logo{display:flex;align-items:center;gap:11px}
.sb-mark{width:32px;height:32px;border-radius:8px;background:var(--gb);border:1px solid var(--gbr);display:flex;align-items:center;justify-content:center}
.sb-mark svg{width:13px;height:13px;fill:var(--gold)}
.sb-name{font-size:15px;font-weight:600;letter-spacing:-.2px}
.sb-ver{font-size:10px;color:var(--t3);font-family:'JetBrains Mono',monospace;margin-top:2px}
.sb-nav{flex:1;padding:16px 12px;display:flex;flex-direction:column;gap:1px}
.ns{font-size:10px;font-weight:600;color:var(--t3);letter-spacing:.9px;text-transform:uppercase;font-family:'JetBrains Mono',monospace;padding:14px 8px 6px}
.ni{display:flex;align-items:center;gap:9px;padding:8px 10px;border-radius:7px;font-size:13px;font-weight:500;color:var(--t2);cursor:pointer;transition:all .13s;user-select:none;border:1px solid transparent}
.ni:hover{background:var(--s3);color:var(--text)}
.ni.on{background:var(--gb);border-color:var(--gbr);color:var(--gold)}
.ni svg{width:15px;height:15px;stroke:currentColor;fill:none;stroke-width:1.8;stroke-linecap:round;stroke-linejoin:round;flex-shrink:0}
.sb-foot{padding:18px 20px;border-top:1px solid var(--b1)}
.st-row{display:flex;align-items:center;gap:8px}
.st-dot{width:7px;height:7px;border-radius:50%;background:var(--green);flex-shrink:0;animation:stpulse 2.5s ease-in-out infinite}
.st-dot.off{background:var(--red);animation:none}
@keyframes stpulse{0%,100%{opacity:1}50%{opacity:.35}}
.st-lbl{font-size:12px;color:var(--t2);font-family:'JetBrains Mono',monospace}
#main{flex:1;min-width:0;height:100vh;overflow-y:auto}
.pg{display:none;padding:44px 48px;min-height:100%}
.pg.on{display:block}
.pg-t{font-family:'Instrument Serif',serif;font-size:30px;font-weight:400;letter-spacing:-.3px;line-height:1.1;margin-bottom:6px}
.pg-s{font-size:13px;color:var(--t2);line-height:1.55;margin-bottom:36px}
#pg-auth{display:flex;align-items:center;justify-content:center;padding:0;min-height:100vh}
.ac{width:100%;max-width:360px;text-align:center;padding:40px 20px}
.a-emb{width:56px;height:56px;border-radius:14px;background:var(--s2);border:1px solid var(--b2);display:flex;align-items:center;justify-content:center;margin:0 auto 22px}
.a-emb svg{width:22px;height:22px;stroke:var(--gold);fill:none;stroke-width:1.5;stroke-linecap:round;stroke-linejoin:round}
.a-t{font-family:'Instrument Serif',serif;font-size:26px;font-weight:400;margin-bottom:8px}
.a-s{font-size:13px;color:var(--t2);line-height:1.6;margin-bottom:26px}
.a-f{display:flex;gap:8px}
.inp{flex:1;background:var(--s2);border:1px solid var(--b2);border-radius:8px;color:var(--text);font-family:'Instrument Sans',sans-serif;font-size:14px;padding:11px 14px;outline:none;transition:border-color .15s}
.inp:focus{border-color:var(--gbr)}
.inp::placeholder{color:var(--t3)}
.a-err{color:var(--red);font-size:12px;font-family:'JetBrains Mono',monospace;margin-top:10px;display:none}
.btn{display:inline-flex;align-items:center;gap:7px;padding:10px 18px;border-radius:8px;font-family:'Instrument Sans',sans-serif;font-size:13px;font-weight:500;cursor:pointer;border:none;transition:all .14s;white-space:nowrap;line-height:1}
.btn-g{background:var(--gold);color:#07080a}.btn-g:hover{background:var(--gold2)}
.btn-gh{background:transparent;border:1px solid var(--b3);color:var(--t2)}.btn-gh:hover{border-color:var(--b4);color:var(--text);background:var(--s3)}
.btn-r{background:transparent;border:1px solid var(--rbr);color:var(--red)}.btn-r:hover{background:var(--rb)}
.btn-sm{padding:7px 12px;font-size:12px}.btn-xs{padding:5px 9px;font-size:11px}
.sg{display:grid;grid-template-columns:repeat(3,1fr);gap:14px;margin-bottom:32px}
.sc{background:var(--s1);border:1px solid var(--b2);border-radius:12px;padding:20px 22px;position:relative;overflow:hidden}
.sc::after{content:'';position:absolute;inset:0 0 auto;height:1px;background:linear-gradient(90deg,transparent,var(--b3) 40%,var(--b3) 60%,transparent)}
.sc-ey{font-size:10px;font-weight:600;color:var(--t3);text-transform:uppercase;letter-spacing:.9px;font-family:'JetBrains Mono',monospace;margin-bottom:10px}
.sc-v{font-family:'Instrument Serif',serif;font-size:40px;font-weight:400;letter-spacing:-.5px;line-height:1}
.sc-v.g{color:var(--gold)}.sc-v.gr{color:var(--green)}.sc-v.b{color:#5b9cf6}
.sc-sub{font-size:11px;color:var(--t3);margin-top:6px;font-family:'JetBrains Mono',monospace}
.sh{display:flex;align-items:center;justify-content:space-between;margin-bottom:13px}
.sl{font-size:10px;font-weight:600;color:var(--t3);text-transform:uppercase;letter-spacing:.9px;font-family:'JetBrains Mono',monospace}
.pn{background:var(--s1);border:1px solid var(--b1);border-radius:12px;overflow:hidden;margin-bottom:28px}
.srow{display:flex;align-items:center;justify-content:space-between;padding:13px 22px;border-bottom:1px solid var(--b1)}
.srow:last-child{border-bottom:none}.srow:hover{background:var(--s2)}
.srow-l{font-size:13px;color:var(--t2)}.srow-r{font-size:12px;font-family:'JetBrains Mono',monospace}
.prof{padding:20px 22px;border-bottom:1px solid var(--b1);transition:background .1s}
.prof:last-child{border-bottom:none}.prof:hover{background:#0c0e1180}
.prof-h{display:flex;align-items:flex-start;justify-content:space-between;gap:16px}
.prof-name{font-size:15px;font-weight:600;letter-spacing:-.2px}
.prof-id{font-size:11px;color:var(--t3);font-family:'JetBrains Mono',monospace;margin-top:3px}
.chips{display:flex;flex-wrap:wrap;gap:6px;margin-top:10px}
.chip{display:inline-flex;align-items:center;padding:3px 9px;border-radius:999px;font-size:11px;font-weight:500;font-family:'JetBrains Mono',monospace}
.chip-g{background:var(--gb);border:1px solid var(--gbr);color:var(--gold)}
.chip-gr{background:var(--grb);border:1px solid var(--grbr);color:var(--green)}
.chip-d{background:var(--s3);border:1px solid var(--b2);color:var(--t3)}
.urls{margin-top:13px;display:flex;flex-direction:column;gap:5px}
.urow{display:flex;align-items:center;gap:10px;background:var(--s3);border:1px solid var(--b1);border-radius:7px;padding:8px 12px}
.ubadge{font-size:10px;font-weight:600;color:var(--t3);font-family:'JetBrains Mono',monospace;letter-spacing:.4px;min-width:48px}
.uval{font-size:11px;font-family:'JetBrains Mono',monospace;color:var(--gold2);flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.cbtn{width:24px;height:24px;border-radius:5px;background:transparent;border:1px solid var(--b2);color:var(--t3);cursor:pointer;display:flex;align-items:center;justify-content:center;transition:all .12s;flex-shrink:0}
.cbtn:hover{border-color:var(--gbr);color:var(--gold)}.cbtn.ok{border-color:var(--grbr);color:var(--green)}
.cbtn svg{width:11px;height:11px;stroke:currentColor;fill:none;stroke-width:2;stroke-linecap:round;stroke-linejoin:round}
.emp{padding:52px 24px;text-align:center}
.emp-i{width:44px;height:44px;border-radius:10px;background:var(--s2);border:1px solid var(--b1);display:flex;align-items:center;justify-content:center;margin:0 auto 14px}
.emp-i svg{width:18px;height:18px;stroke:var(--t3);fill:none;stroke-width:1.6;stroke-linecap:round;stroke-linejoin:round}
.emp-t{font-size:14px;font-weight:500;color:var(--t2)}.emp-s{font-size:12px;color:var(--t3);margin-top:5px;line-height:1.5}
.scrow{display:flex;align-items:center;gap:14px;padding:12px 22px;border-bottom:1px solid var(--b1)}
.scrow:last-child{border-bottom:none}.scrow:hover{background:var(--s2)}
.scn{font-size:13px;color:var(--t2);width:140px;flex-shrink:0}
.scbw{flex:1;height:3px;background:var(--s4);border-radius:3px;overflow:hidden}
.scf{height:100%;background:var(--gold);border-radius:3px;opacity:.6}
.scnum{font-size:12px;font-family:'JetBrains Mono',monospace;color:var(--gold);min-width:20px;text-align:right}
.bwrap{display:flex;flex-wrap:wrap;gap:8px;padding:22px}
.btag{padding:5px 12px;border-radius:6px;font-size:12px;font-weight:600;font-family:'JetBrains Mono',monospace;background:var(--rb);border:1px solid var(--rbr);color:var(--red)}
.mwrap{display:none;position:fixed;inset:0;background:#000000a0;z-index:200;align-items:center;justify-content:center}
.mwrap.on{display:flex}
.modal{background:var(--s2);border:1px solid var(--b3);border-radius:16px;padding:30px;width:100%;max-width:450px;max-height:90vh;overflow-y:auto}
.mt{font-family:'Instrument Serif',serif;font-size:22px;font-weight:400;margin-bottom:5px}
.ms{font-size:13px;color:var(--t2);margin-bottom:24px;line-height:1.55}
.fg{margin-bottom:16px}
.fl{font-size:11px;font-weight:600;color:var(--t3);text-transform:uppercase;letter-spacing:.7px;font-family:'JetBrains Mono',monospace;margin-bottom:7px;display:block}
.fi,.fsel{width:100%;background:var(--s3);border:1px solid var(--b2);border-radius:8px;color:var(--text);font-family:'Instrument Sans',sans-serif;font-size:14px;padding:11px 14px;outline:none;transition:border-color .15s;-webkit-appearance:none}
.fi:focus,.fsel:focus{border-color:var(--gbr)}.fi::placeholder{color:var(--t3)}.fsel option{background:var(--s3)}
.tr{display:flex;align-items:center;justify-content:space-between;padding:12px 0;border-bottom:1px solid var(--b1)}
.tr:last-of-type{border-bottom:none;margin-bottom:22px}
.trn{font-size:14px;font-weight:500}.trd{font-size:12px;color:var(--t3);margin-top:2px;line-height:1.4}
.tog{position:relative;width:38px;height:21px;flex-shrink:0;cursor:pointer}
.tog input{opacity:0;position:absolute;width:0;height:0}
.tt{position:absolute;inset:0;background:var(--s4);border:1px solid var(--b2);border-radius:11px;transition:.18s}
.tt::after{content:'';position:absolute;top:3px;left:3px;width:13px;height:13px;border-radius:50%;background:var(--t3);transition:.18s}
.tog input:checked+.tt{background:var(--gold);border-color:var(--gold)}
.tog input:checked+.tt::after{left:20px;background:#07080a}
.mrow{display:flex;gap:8px}
#toast{position:fixed;bottom:28px;right:28px;background:var(--s2);border:1px solid var(--b3);color:var(--text);padding:11px 18px;border-radius:8px;font-size:12px;font-family:'JetBrains Mono',monospace;transform:translateY(60px);opacity:0;transition:.22s cubic-bezier(.34,1.56,.64,1);z-index:999;pointer-events:none}
#toast.on{transform:translateY(0);opacity:1}
</style>
</head>
<body>
<div id="toast"></div>
<div class="mwrap" id="modal">
  <div class="modal">
    <div class="mt">New profile</div>
    <div class="ms">Creates a unique private manifest URL for a device or person.</div>
    <div class="fg"><label class="fl">Profile name</label><input class="fi" id="n-name" placeholder="e.g. Living Room 4K"/></div>
    <div class="fg"><label class="fl">Minimum quality</label>
      <select class="fsel" id="n-qual"><option value="1080p">1080p and above</option><option value="2160p">4K only</option></select></div>
    <div class="tr"><div><div class="trn">Cached only</div><div class="trd">Only streams already cached on TorBox</div></div><label class="tog"><input type="checkbox" id="n-cache" checked/><div class="tt"></div></label></div>
    <div class="tr"><div><div class="trn">Prefer HEVC/x265</div><div class="trd">Smaller files at equivalent quality</div></div><label class="tog"><input type="checkbox" id="n-hevc" checked/><div class="tt"></div></label></div>
    <div class="tr"><div><div class="trn">Prefer HDR/Dolby Vision</div><div class="trd">HDR10, HDR10+, Dolby Vision</div></div><label class="tog"><input type="checkbox" id="n-hdr" checked/><div class="tt"></div></label></div>
    <div class="tr"><div><div class="trn">Prefer Atmos/TrueHD</div><div class="trd">Lossless and object-based audio</div></div><label class="tog"><input type="checkbox" id="n-audio" checked/><div class="tt"></div></label></div>
    <div class="mrow"><button class="btn btn-g" style="flex:1" onclick="createProfile()">Generate manifest</button><button class="btn btn-gh" onclick="closeM()">Cancel</button></div>
  </div>
</div>
<div id="sb">
  <div class="sb-top"><div class="sb-logo"><div class="sb-mark"><svg viewBox="0 0 24 24"><path d="M5 3l14 9-14 9V3z"/></svg></div><div><div class="sb-name">StreamVault</div><div class="sb-ver">TorBox Addon</div></div></div></div>
  <nav class="sb-nav">
    <div class="ns">Dashboard</div>
    <div class="ni on" id="ni-dash" onclick="go('dash')"><svg viewBox="0 0 24 24"><rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/></svg>Overview</div>
    <div class="ni" id="ni-profiles" onclick="go('profiles')"><svg viewBox="0 0 24 24"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"/></svg>Profiles</div>
    <div class="ns">Config</div>
    <div class="ni" id="ni-scoring" onclick="go('scoring')"><svg viewBox="0 0 24 24"><line x1="18" y1="20" x2="18" y2="10"/><line x1="12" y1="20" x2="12" y2="4"/><line x1="6" y1="20" x2="6" y2="14"/></svg>Scoring</div>
    <div class="ni" id="ni-filters" onclick="go('filters')"><svg viewBox="0 0 24 24"><polygon points="22 3 2 3 10 12.46 10 19 14 21 14 12.46 22 3"/></svg>Filters</div>
  </nav>
  <div class="sb-foot"><div class="st-row"><div class="st-dot" id="sdot"></div><div class="st-lbl" id="slbl">Connecting…</div></div></div>
</div>
<div id="main">
  <div class="pg on" id="pg-auth" style="display:flex">
    <div class="ac">
      <div class="a-emb"><svg viewBox="0 0 24 24"><rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg></div>
      <div class="a-t">Admin access</div>
      <div class="a-s">Enter your password to manage StreamVault.</div>
      <div class="a-f"><input class="inp" type="password" id="pw" placeholder="Password" onkeydown="if(event.key==='Enter')login()"/><button class="btn btn-g" onclick="login()">Unlock</button></div>
      <div class="a-err" id="aerr">Incorrect password</div>
    </div>
  </div>
  <div class="pg" id="pg-dash">
    <div class="pg-t">Overview</div><div class="pg-s">System health and cache performance.</div>
    <div class="sg">
      <div class="sc"><div class="sc-ey">Active profiles</div><div class="sc-v g" id="sv-p">—</div><div class="sc-sub">manifest URLs live</div></div>
      <div class="sc"><div class="sc-ey">Cache hits</div><div class="sc-v gr" id="sv-h">—</div><div class="sc-sub">stream lookups served</div></div>
      <div class="sc"><div class="sc-ey">Redis keys</div><div class="sc-v b" id="sv-k">—</div><div class="sc-sub">entries cached</div></div>
    </div>
    <div><div class="sh"><div class="sl">System</div></div><div class="pn" id="sys-rows"></div></div>
  </div>
  <div class="pg" id="pg-profiles">
    <div style="display:flex;align-items:flex-start;justify-content:space-between;gap:16px;margin-bottom:36px">
      <div><div class="pg-t">Profiles</div><div class="pg-s">Each profile has a unique manifest URL for Stremio.</div></div>
      <button class="btn btn-g" onclick="openM()" style="flex-shrink:0;margin-top:6px">+ New profile</button>
    </div>
    <div class="pn" id="prof-panel"><div class="emp"><div class="emp-i"><svg viewBox="0 0 24 24"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/></svg></div><div class="emp-t">No profiles yet</div><div class="emp-s">Create a profile to get a manifest URL.</div></div></div>
  </div>
  <div class="pg" id="pg-scoring">
    <div class="pg-t">Scoring weights</div><div class="pg-s">How streams are ranked. Higher = more preferred.</div>
    <div class="pn" id="score-rows"></div>
  </div>
  <div class="pg" id="pg-filters">
    <div class="pg-t">Blocked releases</div><div class="pg-s">Always filtered out regardless of profile.</div>
    <div class="pn"><div class="bwrap" id="bwrap"></div></div>
  </div>
</div>
<script>
const SC={resolution4K:{l:'4K Bonus',v:12},dolbyVision:{l:'Dolby Vision',v:10},hevc:{l:'HEVC/x265',v:10},hdrPlus:{l:'HDR10+',v:9},remux:{l:'Remux',v:9},hdr:{l:'HDR10',v:8},bluray:{l:'BluRay',v:7},atmos:{l:'Atmos',v:6},webdl:{l:'WEB-DL',v:6},trueHD:{l:'TrueHD',v:5},webrip:{l:'WEBRip',v:3},dts:{l:'DTS',v:3},h264:{l:'x264',v:1}};
const BL=['CAM','TS','HDCAM','SCR','DVDSCR','TELECINE','TELESYNC','HC','R5'];
let TOK='',INFO={};
fetch('/health').then(r=>{document.getElementById('sdot').className='st-dot'+(r.ok?'':' off');document.getElementById('slbl').textContent=r.ok?'Online':'Error';}).catch(()=>{document.getElementById('sdot').className='st-dot off';document.getElementById('slbl').textContent='Offline'});
function go(id){document.querySelectorAll('.pg').forEach(p=>{if(p.id==='pg-auth')return;p.classList.remove('on');p.style.display=''});document.querySelectorAll('.ni').forEach(n=>n.classList.remove('on'));const p=document.getElementById('pg-'+id);if(p)p.classList.add('on');const n=document.getElementById('ni-'+id);if(n)n.classList.add('on');}
async function login(){const pw=document.getElementById('pw').value.trim();if(!pw)return;TOK=pw;const r=await fetch('/api/profiles',{headers:{'x-admin-token':TOK}});if(r.status===401){document.getElementById('aerr').style.display='block';TOK='';return}document.getElementById('pg-auth').style.display='none';document.getElementById('pg-auth').classList.remove('on');await loadAll();go('dash');}
async function api(p,o={}){try{const r=await fetch(p,{...o,headers:{'x-admin-token':TOK,'Content-Type':'application/json',...(o.headers||{})}});return r.json()}catch{return{}}}
async function loadAll(){const[profs,info,cs]=await Promise.all([api('/api/profiles'),api('/api/info'),api('/api/cache/stats')]);INFO=info||{};document.getElementById('sv-p').textContent=profs.length;document.getElementById('sv-h').textContent=cs?.streams?.hits??'0';document.getElementById('sv-k').textContent=cs?.streams?.keys??'0';renderSys(info);renderProfiles(profs,info);renderScoring();renderBlocked();}
function renderSys(info){const port=info?.port||7000;const rows=[['Public URL',info?.publicUrl||'—','var(--gold)'],['Local',`${info?.nasIp||'—'}:${port}`,'var(--text)'],['TorBox','Pro','var(--green)'],['Redis',info?.redis||'—',info?.redis==='connected'?'var(--green)':'var(--red)'],['Uptime',info?.uptime?Math.floor(info.uptime/60)+'m':'—','var(--text)']];document.getElementById('sys-rows').innerHTML=rows.map(r=>`<div class="srow"><span class="srow-l">${r[0]}</span><span class="srow-r" style="color:${r[2]}">${r[1]}</span></div>`).join('');}
function renderProfiles(profs,info){const el=document.getElementById('prof-panel');if(!profs.length){el.innerHTML='<div class="emp"><div class="emp-i"><svg viewBox="0 0 24 24"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/></svg></div><div class="emp-t">No profiles yet</div><div class="emp-s">Create a profile to get a manifest URL.</div></div>';return}const port=info?.port||7000;el.innerHTML=profs.map(p=>{const id=p.configId;const urls=p.manifestUrls?Object.entries(p.manifestUrls).filter(([,v])=>v).map(([k,v])=>({b:k,u:v})):[{b:'Local',u:`http://localhost:${port}/config/${id}/manifest.json`}];const chips=[p.prefs?.cachedOnly?'<span class="chip chip-gr">Cached only</span>':'<span class="chip chip-d">All sources</span>',p.prefs?.minQuality?`<span class="chip chip-g">${p.prefs.minQuality}+</span>`:``].join('');return`<div class="prof"><div class="prof-h"><div><div class="prof-name">${p.name}</div><div class="prof-id">${id.slice(0,8).toUpperCase()}…</div><div class="chips">${chips}</div></div><button class="btn btn-r btn-xs" onclick="delP('${id}')">Remove</button></div><div class="urls">${urls.map(u=>`<div class="urow"><span class="ubadge">${u.b}</span><span class="uval" title="${u.u}">${u.u}</span><button class="cbtn" onclick="cpUrl(this,'${u.u}')"><svg viewBox="0 0 24 24"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg></button></div>`).join('')}</div></div>`}).join('');}
function renderScoring(){document.getElementById('score-rows').innerHTML=Object.values(SC).map(s=>`<div class="scrow"><span class="scn">${s.l}</span><div class="scbw"><div class="scf" style="width:${Math.round(s.v/12*100)}%"></div></div><span class="scnum">${s.v}</span></div>`).join('');}
function renderBlocked(){document.getElementById('bwrap').innerHTML=BL.map(t=>`<span class="btag">${t}</span>`).join('');}
function openM(){document.getElementById('modal').classList.add('on')}
function closeM(){document.getElementById('modal').classList.remove('on')}
async function createProfile(){const name=document.getElementById('n-name').value.trim()||'New Profile';const minQuality=document.getElementById('n-qual').value;const cachedOnly=document.getElementById('n-cache').checked;const hevc=document.getElementById('n-hevc').checked;const hdr=document.getElementById('n-hdr').checked;const audio=document.getElementById('n-audio').checked;const scoring=Object.fromEntries(Object.entries(SC).map(([k,v])=>[k,v.v]));if(!hevc)scoring.hevc=0;if(!hdr){scoring.hdr=0;scoring.dolbyVision=0;scoring.hdrPlus=0}if(!audio){scoring.atmos=0;scoring.trueHD=0}await api('/api/profiles',{method:'POST',body:JSON.stringify({name,prefs:{minQuality,cachedOnly,scoring}})});closeM();document.getElementById('n-name').value='';toast('Profile created');loadAll();}
async function delP(id){if(!confirm('Remove this profile? Its manifest URL will stop working.'))return;await api(`/api/profiles/${id}`,{method:'DELETE'});toast('Profile removed');loadAll();}
function cpUrl(btn,url){navigator.clipboard.writeText(url).then(()=>{btn.classList.add('ok');setTimeout(()=>btn.classList.remove('ok'),1800);toast('Copied')});}
let tt;function toast(msg){const el=document.getElementById('toast');el.textContent=msg;el.classList.add('on');clearTimeout(tt);tt=setTimeout(()=>el.classList.remove('on'),2400);}
</script>
</body>
</html>
HTMLEOF

ok "All source files written"

# ── npm install ───────────────────────────────────────────────
step "Installing dependencies"
cd "$INSTALL_DIR"
npm install --silent --no-fund --no-audit
ok "Dependencies installed"

# ══════════════════════════════════════════════════════════════
#  WRITE .env
# ══════════════════════════════════════════════════════════════
step "Writing config"
LOCAL_IP=$(hostname -I | awk '{print $1}')

cat > "$INSTALL_DIR/.env" << EOF
PORT=${PORT}
HOST=0.0.0.0
NODE_ENV=production
ADMIN_PASSWORD=${ADMIN_PASS}
TORBOX_API_KEY=${TORBOX_KEY}
TORBOX_API_URL=https://api.torbox.app/v1/api
NAS_LOCAL_IP=${LOCAL_IP}
CF_ENABLED=${CF_ENABLED}
CF_DOMAIN=${CF_DOMAIN}
CF_SUBDOMAIN=${CF_SUBDOMAIN}
CF_TOKEN=${CF_TOKEN}
CF_ACCESS=${CF_ACCESS}
CF_COUNTRY_BLOCK=${CF_COUNTRY_BLOCK}
CF_RATE_LIMIT=${CF_RATE_LIMIT}
TS_ENABLED=${TS_ENABLED}
TS_HOSTNAME=${TS_HOSTNAME}
DEFAULT_MIN_QUALITY=${MIN_RES}
DEFAULT_CACHED_ONLY=${CACHED_ONLY}
DEFAULT_PREFER_HEVC=${PREFER_HEVC}
DEFAULT_PREFER_HDR=${PREFER_HDR}
DEFAULT_PREFER_ATMOS=${PREFER_ATMOS}
DEFAULT_LANGUAGE=${PREF_LANG}
DEFAULT_MAX_SIZE_GB=${MAX_SIZE}
STREAM_CACHE_TTL=300
META_CACHE_TTL=3600
EOF
ok "Config saved"

# ══════════════════════════════════════════════════════════════
#  CLOUDFLARE
# ══════════════════════════════════════════════════════════════
if [[ "$CF_ENABLED" == "true" ]]; then
  step "Cloudflare Tunnel"
  if ! command -v cloudflared &>/dev/null; then
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg \
      | $SUDO tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main" \
      | $SUDO tee /etc/apt/sources.list.d/cloudflared.list >/dev/null
    $SUDO apt-get update -qq && $SUDO apt-get install -y cloudflared &>/dev/null
    ok "cloudflared installed"
  else
    ok "cloudflared already installed"
  fi
  mkdir -p "$HOME/.cloudflared"
  cat > "$HOME/.cloudflared/config.yml" << CFEOF
ingress:
  - hostname: ${CF_SUBDOMAIN}.${CF_DOMAIN}
    service: http://localhost:${PORT}
  - service: http_status:404
CFEOF
  $SUDO tee /etc/systemd/system/cloudflared.service >/dev/null << CFSVC
[Unit]
Description=Cloudflare Tunnel
After=network.target
[Service]
Type=simple
User=$USER
ExecStart=$(which cloudflared) tunnel run
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
CFSVC
  $SUDO systemctl daemon-reload
  $SUDO systemctl enable cloudflared &>/dev/null
  ok "Tunnel configured"
  warn "Run: cloudflared tunnel login && cloudflared tunnel create streamvault"
  warn "Then: sudo systemctl start cloudflared"
fi

# ══════════════════════════════════════════════════════════════
#  TAILSCALE
# ══════════════════════════════════════════════════════════════
if [[ "$TS_ENABLED" == "true" ]]; then
  step "Tailscale"
  if ! command -v tailscale &>/dev/null; then
    curl -fsSL https://tailscale.com/install.sh | sh &>/dev/null
    ok "Tailscale installed"
  fi
  $SUDO tailscale up --authkey="$TS_AUTH_KEY" --hostname="$TS_HOSTNAME" 2>/dev/null || true
  TS_IP=$(tailscale ip -4 2>/dev/null || echo "pending")
  ok "Tailscale — $TS_IP"
fi

# ══════════════════════════════════════════════════════════════
#  SYSTEMD
# ══════════════════════════════════════════════════════════════
step "System service"
$SUDO tee /etc/systemd/system/${SVC}.service >/dev/null << SVEOF
[Unit]
Description=StreamVault — TorBox Stremio Addon
After=network.target
[Service]
Type=simple
User=$USER
WorkingDirectory=${INSTALL_DIR}
ExecStart=$(which node) src/server.js
Restart=always
RestartSec=5
EnvironmentFile=${INSTALL_DIR}/.env
[Install]
WantedBy=multi-user.target
SVEOF
$SUDO systemctl daemon-reload
$SUDO systemctl enable ${SVC} &>/dev/null
$SUDO systemctl restart ${SVC}
sleep 2
$SUDO systemctl is-active --quiet ${SVC} && ok "Service running" \
  || err "Service failed — check: sudo journalctl -u streamvault -n 30"

# ══════════════════════════════════════════════════════════════
#  CLI
# ══════════════════════════════════════════════════════════════
step "Installing CLI"
$SUDO tee "$CLI_BIN" >/dev/null << 'CLIEOF'
#!/usr/bin/env bash
INSTALL_DIR="$HOME/streamvault"
SVC="streamvault"
R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m' C='\033[0;36m' W='\033[1;37m' DIM='\033[2m' NC='\033[0m' BOLD='\033[1m'
ok(){ echo -e "  ${G}✓${NC} $*"; }
warn(){ echo -e "  ${Y}⚠${NC}  $*"; }
err(){ echo -e "\n  ${R}✗ $*${NC}\n"; exit 1; }
sep(){ echo -e "\n  ${DIM}──────────────────────────────────────────${NC}"; }
ask(){ echo -e "\n  ${W}$*${NC}"; }
[[ -f "$INSTALL_DIR/.env" ]] && source "$INSTALL_DIR/.env" || err "Config not found. Run the installer first."
PORT="${PORT:-7000}"
API="http://localhost:${PORT}/api"
AH="x-admin-token: $ADMIN_PASSWORD"
_get(){ curl -sf "$API/$1" -H "$AH"; }
_post(){ curl -sf -X POST "$API/$1" -H "$AH" -H "Content-Type: application/json" -d "$2"; }
_del(){ curl -sf -X DELETE "$API/$1" -H "$AH"; }
_url(){
  local id="$1" lip; lip=$(hostname -I | awk '{print $1}')
  if [[ "$CF_ENABLED" == "true" ]]; then echo "https://${CF_SUBDOMAIN}.${CF_DOMAIN}/config/${id}/manifest.json"
  elif [[ "$TS_ENABLED" == "true" ]]; then
    local tip; tip=$(tailscale ip -4 2>/dev/null || echo "TS_IP")
    echo "http://${tip}:${PORT}/config/${id}/manifest.json"
  else echo "http://${lip}:${PORT}/config/${id}/manifest.json"; fi
}
_find(){ local name="$1"; _get "profiles" 2>/dev/null | python3 -c "
import sys,json
ps=json.load(sys.stdin); n='$name'.lower()
for p in ps:
  if p['name'].lower()==n or p['configId'].startswith(n): print(p['configId']); break
" 2>/dev/null; }
CMD="${1:-help}"; shift 2>/dev/null || true
case "$CMD" in
status)
  echo -e "\n  ${W}${BOLD}StreamVault Status${NC}"; sep
  systemctl is-active --quiet $SVC && echo -e "  Service   ${G}● Running${NC}" || echo -e "  Service   ${R}● Stopped${NC}"
  curl -sf "http://localhost:${PORT}/health" &>/dev/null && echo -e "  HTTP      ${G}● Online${NC}" || echo -e "  HTTP      ${R}● Unreachable${NC}"
  REDIS=$(docker exec redis redis-cli ping 2>/dev/null || redis-cli ping 2>/dev/null || echo FAIL)
  [[ "$REDIS" == "PONG" ]] && echo -e "  Redis     ${G}● Connected${NC}" || echo -e "  Redis     ${R}● Disconnected${NC}"
  STATS=$(_get "cache/stats" 2>/dev/null)
  HITS=$(echo "$STATS" | python3 -c "import sys,json; print(json.load(sys.stdin).get('streams',{}).get('hits',0))" 2>/dev/null || echo —)
  echo -e "  Hits      ${DIM}$HITS${NC}"; echo "";;
logs) sudo journalctl -u $SVC -f --no-pager;;
restart) sudo systemctl restart $SVC && ok "Restarted";;
update)
  echo -e "  ${DIM}Pulling latest install script...${NC}"
  curl -fsSL https://raw.githubusercontent.com/ray0189/streamvault/main/install.sh | bash
  ok "Updated";;
backup)
  DEST="$HOME/streamvault-backup-$(date +%Y-%m-%d_%H-%M).tar.gz"
  tar -czf "$DEST" -C "$HOME" streamvault --exclude='streamvault/node_modules' 2>/dev/null
  ok "Saved: $DEST";;
profile)
  SUB="${1:-}"; shift 2>/dev/null || true
  case "$SUB" in
  add)
    echo -e "\n  ${W}${BOLD}New Profile${NC}"; sep
    ask "Profile name"; read -rp "  › " P_NAME; [[ -z "$P_NAME" ]] && err "Name required"
    ask "Min resolution [${DEFAULT_MIN_QUALITY:-1080p}]  (480p/720p/1080p/2160p)"; read -rp "  › " P_RES; P_RES="${P_RES:-${DEFAULT_MIN_QUALITY:-1080p}}"
    ask "Max file size GB [${DEFAULT_MAX_SIZE_GB:-80}]  (0=no limit)"; read -rp "  › " P_SIZE; P_SIZE="${P_SIZE:-${DEFAULT_MAX_SIZE_GB:-80}}"
    ask "Cached only? [${DEFAULT_CACHED_ONLY:-true}]  (true/false)"; read -rp "  › " P_CACHED; P_CACHED="${P_CACHED:-${DEFAULT_CACHED_ONLY:-true}}"
    ask "Prefer REMUX? [true]"; read -rp "  › " P_REMUX; P_REMUX="${P_REMUX:-true}"
    ask "Prefer BluRay? [true]"; read -rp "  › " P_BR; P_BR="${P_BR:-true}"
    ask "Codec [hevc]  (hevc/av1/h264/any)"; read -rp "  › " P_CODEC; P_CODEC="${P_CODEC:-hevc}"
    ask "Dolby Vision [prefer]  (prefer/allow/block)"; read -rp "  › " P_DV; P_DV="${P_DV:-prefer}"
    ask "HDR10+ [prefer]  (prefer/allow/block)"; read -rp "  › " P_HDRP; P_HDRP="${P_HDRP:-prefer}"
    ask "HDR10 [prefer]  (prefer/allow/block)"; read -rp "  › " P_HDR; P_HDR="${P_HDR:-prefer}"
    ask "Prefer Atmos? [${DEFAULT_PREFER_ATMOS:-true}]"; read -rp "  › " P_ATMOS; P_ATMOS="${P_ATMOS:-${DEFAULT_PREFER_ATMOS:-true}}"
    ask "Prefer TrueHD? [true]"; read -rp "  › " P_THD; P_THD="${P_THD:-true}"
    ask "Min audio channels [5.1]  (2.0/5.1/7.1)"; read -rp "  › " P_CH; P_CH="${P_CH:-5.1}"
    ask "Audio language [${DEFAULT_LANGUAGE:-en}]"; read -rp "  › " P_LANG; P_LANG="${P_LANG:-${DEFAULT_LANGUAGE:-en}}"
    ask "Subtitle language [any]"; read -rp "  › " P_SLANG; P_SLANG="${P_SLANG:-any}"
    S_4K=12
    S_DV=10;   [[ "$P_DV"    == "block" ]] && S_DV=-5   || [[ "$P_DV"    == "allow" ]] && S_DV=3
    S_HDRP=9;  [[ "$P_HDRP"  == "block" ]] && S_HDRP=-3 || [[ "$P_HDRP"  == "allow" ]] && S_HDRP=2
    S_HDR=8;   [[ "$P_HDR"   == "block" ]] && S_HDR=-3  || [[ "$P_HDR"   == "allow" ]] && S_HDR=2
    S_REMUX=9; [[ "$P_REMUX" == "false" ]] && S_REMUX=3
    S_BR=7;    [[ "$P_BR"    == "false" ]] && S_BR=2
    S_HEVC=10; [[ "$P_CODEC" != "hevc"  ]] && S_HEVC=0
    S_AV1=0;   [[ "$P_CODEC" == "av1"   ]] && S_AV1=8
    S_H264=1;  [[ "$P_CODEC" == "h264"  ]] && S_H264=6
    S_ATMOS=6; [[ "$P_ATMOS" == "false" ]] && S_ATMOS=0
    S_THD=5;   [[ "$P_THD"   == "false" ]] && S_THD=0
    PAYLOAD=$(python3 -c "import json; print(json.dumps({'name':'$P_NAME','prefs':{'minQuality':'$P_RES','cachedOnly':$P_CACHED,'maxSizeGB':$P_SIZE,'language':'$P_LANG','subLanguage':'$P_SLANG','minChannels':'$P_CH','scoring':{'resolution4K':$S_4K,'dolbyVision':$S_DV,'hdrPlus':$S_HDRP,'hdr':$S_HDR,'remux':$S_REMUX,'bluray':$S_BR,'hevc':$S_HEVC,'av1':$S_AV1,'h264':$S_H264,'atmos':$S_ATMOS,'trueHD':$S_THD,'webdl':6,'webrip':3,'dts':3}}}))")
    RESULT=$(_post "profiles" "$PAYLOAD" 2>/dev/null)
    ID=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('configId',''))" 2>/dev/null)
    if [[ -n "$ID" ]]; then
      URL=$(_url "$ID"); sep
      echo -e "\n  ${G}${BOLD}✓ Profile created: $P_NAME${NC}\n"
      echo -e "  ${W}Manifest URL:${NC}\n  ${C}${URL}${NC}"
      echo -e "\n  ${DIM}Stremio → Search addons → paste URL → Install${NC}\n"
    else err "Failed — is StreamVault running? (streamvault status)"; fi;;
  list)
    PROFS=$(_get "profiles" 2>/dev/null)
    COUNT=$(echo "$PROFS" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo 0)
    echo -e "\n  ${W}${BOLD}Profiles ($COUNT)${NC}"; sep
    if [[ "$COUNT" == "0" ]]; then echo -e "\n  ${DIM}None — run: streamvault profile add${NC}\n"
    else
      echo "$PROFS" | python3 -c "
import sys,json
for p in json.load(sys.stdin):
  pr=p.get('prefs',{})
  print(f\"  {p['name']}\")
  print(f\"    {p['configId']}\")
  print(f\"    {pr.get('minQuality','—')} · cached:{pr.get('cachedOnly','—')} · lang:{pr.get('language','—')}\")
  print()
"
      echo -e "  ${DIM}streamvault profile url <name>${NC}\n"; fi;;
  url)
    [[ -z "${1:-}" ]] && err "Usage: streamvault profile url <name>"
    ID=$(_find "$1"); [[ -z "$ID" ]] && err "Profile '$1' not found"
    echo -e "\n  ${C}$(_url "$ID")${NC}\n";;
  del)
    [[ -z "${1:-}" ]] && err "Usage: streamvault profile del <name>"
    ID=$(_find "$1"); [[ -z "$ID" ]] && err "Profile '$1' not found"
    read -rp "  Delete '$1'? [y/N] " CONF; [[ "${CONF,,}" != "y" ]] && echo "Cancelled" && exit 0
    _del "profiles/$ID" >/dev/null && ok "Deleted '$1'";;
  *) echo -e "\n  Usage: streamvault profile <add|list|url <name>|del <name>>\n";;
  esac;;
config)
  echo -e "\n  ${W}${BOLD}Configuration${NC}"; sep
  echo -e "  Port        ${C}${PORT}${NC}"
  echo -e "  TorBox      ${DIM}${TORBOX_API_KEY:0:8}…${NC}"
  echo -e "  CF Tunnel   ${C}${CF_ENABLED}${NC}"
  [[ "$CF_ENABLED" == "true" ]] && echo -e "  CF URL      ${C}https://${CF_SUBDOMAIN}.${CF_DOMAIN}${NC}"
  echo -e "  Tailscale   ${C}${TS_ENABLED}${NC}"
  echo -e "  Min quality ${C}${DEFAULT_MIN_QUALITY:-1080p}${NC}"
  echo -e "  Cached only ${C}${DEFAULT_CACHED_ONLY:-true}${NC}"
  echo -e "  Language    ${C}${DEFAULT_LANGUAGE:-en}${NC}"
  echo -e "  Max size    ${C}${DEFAULT_MAX_SIZE_GB:-80}GB${NC}"; echo "";;
help|--help|-h|"")
  echo -e "\n  ${W}${BOLD}streamvault${NC} — CLI\n"
  echo -e "  ${C}status${NC}                  Health check"
  echo -e "  ${C}logs${NC}                    Live logs"
  echo -e "  ${C}restart${NC}                 Restart service"
  echo -e "  ${C}update${NC}                  Update to latest"
  echo -e "  ${C}backup${NC}                  Backup everything"
  echo -e "  ${C}profile add${NC}             Create profile → manifest URL"
  echo -e "  ${C}profile list${NC}            List all profiles"
  echo -e "  ${C}profile url <name>${NC}      Get manifest URL"
  echo -e "  ${C}profile del <name>${NC}      Delete profile"
  echo -e "  ${C}config${NC}                  Show config"; echo "";;
*) echo -e "\n  ${R}Unknown: $CMD${NC} — run ${C}streamvault help${NC}\n"; exit 1;;
esac
CLIEOF
$SUDO chmod +x "$CLI_BIN"
ok "CLI installed"

# ══════════════════════════════════════════════════════════════
#  DONE
# ══════════════════════════════════════════════════════════════
sep
echo -e "\n  ${G}${BOLD}✓ StreamVault installed${NC}\n"
LOCAL_IP=$(hostname -I | awk '{print $1}')
echo -e "  ${W}Local${NC}     http://${LOCAL_IP}:${PORT}"
[[ "$CF_ENABLED" == "true" ]] && echo -e "  ${W}Public${NC}    https://${CF_SUBDOMAIN}.${CF_DOMAIN}"
[[ "$TS_ENABLED" == "true" ]] && {
  TIP=$(tailscale ip -4 2>/dev/null || echo pending)
  echo -e "  ${W}Tailscale${NC} http://${TIP}:${PORT}"
}
echo -e "\n  ${W}Next:${NC}"
echo -e "  ${DIM}1.${NC} ${C}streamvault profile add${NC}   — create a profile"
echo -e "  ${DIM}2.${NC} ${C}streamvault profile list${NC}  — get your manifest URL"
echo -e "  ${DIM}3.${NC} Paste URL into Stremio → Search addons → Install"
[[ "$CF_ENABLED" == "true" ]] && {
  echo -e "\n  ${Y}Complete Cloudflare setup:${NC}"
  echo -e "  ${C}cloudflared tunnel login${NC}"
  echo -e "  ${C}cloudflared tunnel create streamvault${NC}"
  echo -e "  ${C}sudo systemctl start cloudflared${NC}"
}
echo -e "\n  ${DIM}streamvault help — all commands${NC}\n"

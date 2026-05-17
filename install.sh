#!/usr/bin/env bash
set -euo pipefail

if [[ ! -t 0 && -r /dev/tty ]]; then exec < /dev/tty; fi

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

clear || true
echo -e "${C}${BOLD}"
echo '  ____  _                        _   _             _ _  '
echo ' / ___|| |_ _ __ ___  __ _ _ __ | | | | __ _ _   _| | |'
echo ' \___ \| __| '\''__/ _ \/ _` | '\''_ \| | | |/ _` | | | | | |'
echo '  ___) | |_| | |  __/ (_| | | | | |_| | (_| | |_| | | |'
echo ' |____/ \__|_|  \___|\__,_|_| |_|\___/ \__,_|\__,_|_|_|'
echo -e "${NC}"
echo -e "  ${DIM}Self-hosted TorBox Stremio Addon — installer v1.1${NC}\n"

step "Checking system"
[[ "$(uname -s)" != "Linux" ]] && err "Linux required (Ubuntu/Debian recommended)"
for cmd in curl git python3; do
  command -v "$cmd" &>/dev/null && ok "$cmd" || err "$cmd required — sudo apt install $cmd"
done

step "Node.js"
if command -v node &>/dev/null && node -e "process.exit(parseInt(process.version.slice(1))<18?1:0)" 2>/dev/null; then
  ok "Node.js $(node --version)"
else
  echo -e "  ${DIM}Installing Node.js v22...${NC}"
  curl -fsSL https://deb.nodesource.com/setup_22.x | $SUDO bash - >/dev/null
  $SUDO apt-get install -y nodejs >/dev/null
  ok "Node.js $(node --version)"
fi

step "Redis"
if command -v docker &>/dev/null && docker ps 2>/dev/null | grep -q redis; then
  ok "Redis running (Docker)"
elif command -v redis-cli &>/dev/null && redis-cli ping 2>/dev/null | grep -q PONG; then
  ok "Redis running (system)"
elif $SUDO systemctl is-active --quiet redis-server 2>/dev/null; then
  ok "Redis running (systemd)"
elif command -v docker &>/dev/null; then
  docker rm -f redis >/dev/null 2>&1 || true
  docker run -d --name redis --restart always -p 6379:6379 redis:alpine >/dev/null
  ok "Redis started (Docker)"
else
  $SUDO apt-get update -qq >/dev/null
  $SUDO apt-get install -y redis-server redis-tools >/dev/null
  if command -v systemctl &>/dev/null && systemctl list-units >/dev/null 2>&1; then
    $SUDO systemctl enable --now redis-server >/dev/null 2>&1 || true
  else
    $SUDO service redis-server start >/dev/null 2>&1 || true
  fi
  redis-cli ping >/dev/null 2>&1 && ok "Redis installed" || warn "Redis installed but not responding yet"
fi

sep
echo -e "\n  ${W}${BOLD}Setup Wizard${NC}"
echo -e "  ${DIM}Press Enter to accept defaults in [brackets]${NC}\n"

ask "TorBox API key — torbox.app/settings"
while true; do
  read -rp "  › " TORBOX_KEY
  [[ -n "$TORBOX_KEY" ]] && break
  echo -e "  ${R}Required${NC}"
done

ask "Admin password for the StreamVault dashboard/CLI (min 6 chars)"
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
echo -e "  ${C}3${NC}  Local only         ${DIM}Home/LAN only${NC}"
echo -e "  ${C}4${NC}  All three"
echo ""
while true; do
  read -rp "  › " ACCESS
  [[ "$ACCESS" =~ ^[1-4]$ ]] && break
  echo -e "  ${R}Enter 1-4${NC}"
done

CF_ENABLED=false; TS_ENABLED=false
CF_DOMAIN=""; CF_SUBDOMAIN="streamvault"; CF_TOKEN=""
TS_AUTH_KEY=""; TAILSCALE_HOST=""

setup_cf() {
  sep
  echo -e "\n  ${W}${BOLD}Cloudflare Tunnel${NC}"
  ask "Your domain (e.g. yourdomain.com)"
  while true; do read -rp "  › " CF_DOMAIN; [[ -n "$CF_DOMAIN" ]] && break; echo -e "  ${R}Required${NC}"; done
  ask "Subdomain [streamvault]"
  read -rp "  › " CF_SUB_IN; CF_SUBDOMAIN="${CF_SUB_IN:-streamvault}"
  ask "Cloudflare API token (optional, leave blank if you will configure tunnel manually)"
  read -rsp "  › " CF_TOKEN; echo ""
  CF_ENABLED=true
}

setup_ts() {
  sep
  echo -e "\n  ${W}${BOLD}Tailscale${NC}"
  ask "Tailscale auth key (leave blank to skip automatic tailscale up)"
  read -rsp "  › " TS_AUTH_KEY; echo ""
  ask "Device hostname [streamvault]"
  read -rp "  › " TS_HOST_IN; TAILSCALE_HOST="${TS_HOST_IN:-streamvault}"
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

step "Writing source files"
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

mkdir -p "$INSTALL_DIR/."
cat > "$INSTALL_DIR/.env.example" <<'SVEOF__env_example'
PORT=7000
HOST=0.0.0.0
NODE_ENV=production

TORBOX_API_KEY=your_torbox_api_key_here
TORBOX_API_URL=https://api.torbox.app/v1/api
SECRET_KEY=change_this_to_a_long_random_string

STREAM_CACHE_TTL=300
META_CACHE_TTL=3600
ADMIN_PASSWORD=changeme

NAS_LOCAL_IP=192.168.1.x
TAILSCALE_HOST=
TS_ENABLED=false
CF_ENABLED=false
CF_DOMAIN=
CF_SUBDOMAIN=streamvault
PUBLIC_BASE_URL=
SVEOF__env_example

mkdir -p "$INSTALL_DIR/."
cat > "$INSTALL_DIR/.gitignore" <<'SVEOF__gitignore'
node_modules/
.env
data/
*.log
.DS_Store
SVEOF__gitignore

mkdir -p "$INSTALL_DIR/."
cat > "$INSTALL_DIR/README.md" <<'SVEOF_README_md'
# ⚡ StreamVault — Private Stremio Addon

A fully self-hosted, private Stremio addon platform powered by TorBox.
No Docker. Runs directly on your Ubuntu NAS. Accessible via LAN + Tailscale.

---

## Architecture

```
Stremio App
    │
    ▼ manifest URL (per-device profile)
StreamVault (Node.js on NAS :7000)
    │
    ├─ Filter:  blocks CAM/TS/SCR/HDCAM
    ├─ Score:   ranks by HEVC, DV, Atmos, REMUX…
    └─ Fetch:   TorBox cached stream links
```

---

## Quick Start

### 1. Clone / copy the project to your NAS

```bash
cd ~
git clone <your-repo> stremio-addon   # or copy the folder
cd stremio-addon
```

### 2. Install dependencies

```bash
npm install
```

### 3. Run first-time setup

```bash
node scripts/setup.js
```

This will ask for your TorBox API key, NAS IP, Tailscale hostname, and admin password,
then write a `.env` file automatically.

### 4. Start the server

```bash
npm start
```

Or for development with auto-restart:

```bash
npm run dev
```

### 5. Open the dashboard

```
http://<NAS-IP>:7000/
```

Log in with the admin password you set. Create a profile, copy the manifest URL,
and paste it into Stremio.

---

## Running as a systemd service (auto-start on boot)

```bash
# Edit the service file first — set your username and path
nano streamvault.service

# Install it
sudo cp streamvault.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable streamvault
sudo systemctl start streamvault

# Check logs
sudo journalctl -u streamvault -f
```

---

## Tailscale Remote Access

Since you already have Tailscale running:

1. Make sure your NAS is in your Tailscale network
2. Set `TAILSCALE_HOST=your-nas.tail1234.ts.net` in `.env`
3. The dashboard will show Tailscale manifest URLs automatically
4. Add the Tailscale manifest URL to Stremio on any remote device

---

## Project Structure

```
stremio-addon/
├── src/
│   ├── server.js             ← Entry point
│   ├── config/
│   │   ├── env.js            ← Env var loader
│   │   └── defaults.js       ← Quality defaults & scoring weights
│   ├── addon/
│   │   ├── router.js         ← /config/:id/manifest.json + stream routes
│   │   ├── manifest.js       ← Stremio manifest builder
│   │   └── streams.js        ← Main stream pipeline
│   ├── api/
│   │   ├── router.js         ← Dashboard REST API
│   │   └── torbox.js         ← TorBox API client
│   ├── filters/
│   │   └── quality.js        ← CAM/TS blocker + resolution floor
│   ├── scoring/
│   │   └── rank.js           ← Preference scoring engine
│   ├── cache/
│   │   └── store.js          ← In-memory cache (Redis-ready)
│   └── profiles/
│       └── store.js          ← File-based profile store
├── dashboard/
│   └── index.html            ← Web dashboard
├── data/
│   └── profiles.json         ← Auto-created — stores profiles
├── scripts/
│   └── setup.js              ← First-run interactive setup
├── .env.example
├── streamvault.service       ← systemd unit file
└── package.json
```

---

## Manifest URL Format

```
http://<NAS-IP>:7000/config/<configId>/manifest.json
```

Add to Stremio via:
- Settings → Addons → paste URL

Or via the `stremio://` protocol link from the dashboard.

---

## Quality Filtering

**Always blocked:** `CAM · TS · HDCAM · SCR · DVDSCR · TELECINE · TELESYNC · HC · R5`

**Minimum resolution:** configurable per profile (1080p default, 4K option)

**Cached-only mode:** only returns streams TorBox has already cached (instant playback, no wait)

---

## Scoring Weights (defaults)

| Feature       | Score |
|---------------|-------|
| 4K Bonus      | +12   |
| REMUX         | +9    |
| HDR10+        | +9    |
| HEVC / x265   | +10   |
| Dolby Vision  | +10   |
| BluRay        | +7    |
| HDR10         | +8    |
| Atmos         | +6    |
| WEB-DL        | +6    |
| TrueHD        | +5    |
| WEBRip        | +3    |
| DTS           | +3    |
| x264          | +1    |

---

## Planned Upgrades

- [ ] Redis cache backend
- [ ] Prowlarr integration
- [ ] AI-based release ranking
- [ ] Fake torrent detection
- [ ] Jellyfin integration
- [ ] Per-profile scoring weight editor in dashboard
- [ ] Multi-user auth
SVEOF_README_md

mkdir -p "$INSTALL_DIR/dashboard"
cat > "$INSTALL_DIR/dashboard/index.html" <<'SVEOF_dashboard_index_html'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1.0"/>
<title>StreamVault</title>
<link rel="preconnect" href="https://fonts.googleapis.com"/>
<link href="https://fonts.googleapis.com/css2?family=Instrument+Sans:wght@400;500;600&family=Instrument+Serif:ital@0;1&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet"/>
<style>
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
html,body{height:100%}
:root{
  --bg:#07080a;--s1:#0c0e11;--s2:#111418;--s3:#17191d;--s4:#1e2127;
  --b1:#ffffff08;--b2:#ffffff10;--b3:#ffffff18;--b4:#ffffff24;
  --text:#dde1e8;--t2:#8891a0;--t3:#454d5a;
  --gold:#c8a96e;--gold2:#e2c98a;--gb:#c8a96e0d;--gbr:#c8a96e22;
  --green:#3ecf7e;--grb:#3ecf7e0c;--grbr:#3ecf7e22;
  --red:#e05555;--rb:#e055550c;--rbr:#e0555522;
  --sw:220px;
}
body{font-family:'Instrument Sans',sans-serif;background:var(--bg);color:var(--text);display:flex;-webkit-font-smoothing:antialiased;overflow-x:hidden}

/* ── Sidebar ── */
#sb{width:var(--sw);min-width:var(--sw);height:100vh;position:sticky;top:0;background:var(--s1);border-right:1px solid var(--b1);display:flex;flex-direction:column}
.sb-top{padding:24px 20px 22px;border-bottom:1px solid var(--b1)}
.sb-logo{display:flex;align-items:center;gap:11px}
.sb-mark{width:32px;height:32px;border-radius:8px;background:var(--gb);border:1px solid var(--gbr);display:flex;align-items:center;justify-content:center}
.sb-mark svg{width:13px;height:13px;fill:var(--gold)}
.sb-name{font-size:15px;font-weight:600;letter-spacing:-.2px}
.sb-ver{font-size:10px;color:var(--t3);font-family:'JetBrains Mono',monospace;margin-top:2px}
.sb-nav{flex:1;padding:16px 12px;display:flex;flex-direction:column;gap:1px;overflow-y:auto}
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

/* ── Main ── */
#main{flex:1;min-width:0;height:100vh;overflow-y:auto}
.pg{display:none;padding:44px 48px;min-height:100%}
.pg.on{display:block}
.pg-h{margin-bottom:36px}
.pg-t{font-family:'Instrument Serif',serif;font-size:30px;font-weight:400;letter-spacing:-.3px;line-height:1.1}
.pg-s{font-size:13px;color:var(--t2);margin-top:6px;line-height:1.55}

/* ── Auth ── */
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

/* ── Buttons ── */
.btn{display:inline-flex;align-items:center;gap:7px;padding:10px 18px;border-radius:8px;font-family:'Instrument Sans',sans-serif;font-size:13px;font-weight:500;cursor:pointer;border:none;transition:all .14s;white-space:nowrap;line-height:1}
.btn-g{background:var(--gold);color:#07080a}.btn-g:hover{background:var(--gold2)}
.btn-b{background:#5b9cf618;border:1px solid #5b9cf630;color:var(--blue)}.btn-b:hover{background:#5b9cf628}
.btn-gh{background:transparent;border:1px solid var(--b3);color:var(--t2)}.btn-gh:hover{border-color:var(--b4);color:var(--text);background:var(--s3)}
.btn-r{background:transparent;border:1px solid var(--rbr);color:var(--red)}.btn-r:hover{background:var(--rb)}
.btn-sm{padding:7px 12px;font-size:12px}
.btn-xs{padding:5px 9px;font-size:11px}

/* ── Stats ── */
.sg{display:grid;grid-template-columns:repeat(3,1fr);gap:14px;margin-bottom:32px}
.sc{background:var(--s1);border:1px solid var(--b2);border-radius:12px;padding:20px 22px;position:relative;overflow:hidden}
.sc::after{content:'';position:absolute;inset:0 0 auto;height:1px;background:linear-gradient(90deg,transparent,var(--b3) 40%,var(--b3) 60%,transparent)}
.sc-ey{font-size:10px;font-weight:600;color:var(--t3);text-transform:uppercase;letter-spacing:.9px;font-family:'JetBrains Mono',monospace;margin-bottom:10px}
.sc-v{font-family:'Instrument Serif',serif;font-size:40px;font-weight:400;letter-spacing:-.5px;line-height:1}
.sc-v.g{color:var(--gold)}.sc-v.gr{color:var(--green)}.sc-v.b{color:var(--blue)}
.sc-sub{font-size:11px;color:var(--t3);margin-top:6px;font-family:'JetBrains Mono',monospace}

/* ── Section ── */
.sh{display:flex;align-items:center;justify-content:space-between;margin-bottom:13px}
.sl{font-size:10px;font-weight:600;color:var(--t3);text-transform:uppercase;letter-spacing:.9px;font-family:'JetBrains Mono',monospace}
.pn{background:var(--s1);border:1px solid var(--b1);border-radius:12px;overflow:hidden;margin-bottom:28px}
.srow{display:flex;align-items:center;justify-content:space-between;padding:13px 22px;border-bottom:1px solid var(--b1)}
.srow:last-child{border-bottom:none}
.srow:hover{background:var(--s2)}
.srow-l{font-size:13px;color:var(--t2)}
.srow-r{font-size:12px;font-family:'JetBrains Mono',monospace}

/* ── Profiles ── */
.prof{padding:20px 22px;border-bottom:1px solid var(--b1);transition:background .1s}
.prof:last-child{border-bottom:none}
.prof:hover{background:#0c0e1180}
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
.cbtn:hover{border-color:var(--gbr);color:var(--gold)}
.cbtn.ok{border-color:var(--grbr);color:var(--green)}
.cbtn svg{width:11px;height:11px;stroke:currentColor;fill:none;stroke-width:2;stroke-linecap:round;stroke-linejoin:round}

/* ── Empty ── */
.emp{padding:52px 24px;text-align:center}
.emp-i{width:44px;height:44px;border-radius:10px;background:var(--s2);border:1px solid var(--b1);display:flex;align-items:center;justify-content:center;margin:0 auto 14px}
.emp-i svg{width:18px;height:18px;stroke:var(--t3);fill:none;stroke-width:1.6;stroke-linecap:round;stroke-linejoin:round}
.emp-t{font-size:14px;font-weight:500;color:var(--t2)}
.emp-s{font-size:12px;color:var(--t3);margin-top:5px;line-height:1.5}

/* ── Scoring ── */
.scrow{display:flex;align-items:center;gap:14px;padding:12px 22px;border-bottom:1px solid var(--b1)}
.scrow:last-child{border-bottom:none}
.scrow:hover{background:var(--s2)}
.scn{font-size:13px;color:var(--t2);width:140px;flex-shrink:0}
.scbw{flex:1;height:3px;background:var(--s4);border-radius:3px;overflow:hidden}
.scf{height:100%;background:var(--gold);border-radius:3px;opacity:.6}
.scnum{font-size:12px;font-family:'JetBrains Mono',monospace;color:var(--gold);min-width:20px;text-align:right}
.bwrap{display:flex;flex-wrap:wrap;gap:8px;padding:22px}
.btag{padding:5px 12px;border-radius:6px;font-size:12px;font-weight:600;font-family:'JetBrains Mono',monospace;background:var(--rb);border:1px solid var(--rbr);color:var(--red)}

/* ── Modal ── */
.mwrap{display:none;position:fixed;inset:0;background:#000000a0;z-index:200;align-items:center;justify-content:center}
.mwrap.on{display:flex}
.modal{background:var(--s2);border:1px solid var(--b3);border-radius:16px;padding:30px;width:100%;max-width:450px;max-height:90vh;overflow-y:auto}
.mt{font-family:'Instrument Serif',serif;font-size:22px;font-weight:400;margin-bottom:5px}
.ms{font-size:13px;color:var(--t2);margin-bottom:24px;line-height:1.55}
.fg{margin-bottom:16px}
.fl{font-size:11px;font-weight:600;color:var(--t3);text-transform:uppercase;letter-spacing:.7px;font-family:'JetBrains Mono',monospace;margin-bottom:7px;display:block}
.fi,.fsel{width:100%;background:var(--s3);border:1px solid var(--b2);border-radius:8px;color:var(--text);font-family:'Instrument Sans',sans-serif;font-size:14px;padding:11px 14px;outline:none;transition:border-color .15s;-webkit-appearance:none}
.fi:focus,.fsel:focus{border-color:var(--gbr)}
.fi::placeholder{color:var(--t3)}
.fsel option{background:var(--s3)}
.tr{display:flex;align-items:center;justify-content:space-between;padding:12px 0;border-bottom:1px solid var(--b1)}
.tr:last-of-type{border-bottom:none;margin-bottom:22px}
.trn{font-size:14px;font-weight:500}
.trd{font-size:12px;color:var(--t3);margin-top:2px;line-height:1.4}
.tog{position:relative;width:38px;height:21px;flex-shrink:0;cursor:pointer}
.tog input{opacity:0;position:absolute;width:0;height:0}
.tt{position:absolute;inset:0;background:var(--s4);border:1px solid var(--b2);border-radius:11px;transition:.18s}
.tt::after{content:'';position:absolute;top:3px;left:3px;width:13px;height:13px;border-radius:50%;background:var(--t3);transition:.18s}
.tog input:checked+.tt{background:var(--gold);border-color:var(--gold)}
.tog input:checked+.tt::after{left:20px;background:#07080a}
.mrow{display:flex;gap:8px}

/* ── Toast ── */
#toast{position:fixed;bottom:28px;right:28px;background:var(--s2);border:1px solid var(--b3);color:var(--text);padding:11px 18px;border-radius:8px;font-size:12px;font-family:'JetBrains Mono',monospace;transform:translateY(60px);opacity:0;transition:.22s cubic-bezier(.34,1.56,.64,1);z-index:999;pointer-events:none}
#toast.on{transform:translateY(0);opacity:1}

@media(max-width:680px){
  body{flex-direction:column}
  #sb{width:100%;min-width:0;height:auto;position:static;border-right:none;border-bottom:1px solid var(--b1);padding:16px 16px 0}
  .sb-nav{flex-direction:row;flex-wrap:wrap;gap:4px;padding:10px 0}
  .ns,.sb-foot,.sb-ver{display:none}
  .ni{font-size:12px;padding:7px 10px}
  #main{height:auto}
  .pg{padding:24px 20px}
  .sg{grid-template-columns:1fr 1fr}
  .sg .sc:last-child{grid-column:span 2}
  .w-search,.w-continue,.w-results,.wp-streams,.wp-header{padding-left:20px;padding-right:20px}
  #pg-watch{height:auto}
}
</style>
</head>
<body>
<div id="toast"></div>

<!-- Profile Modal -->
<div class="mwrap" id="modal">
  <div class="modal">
    <div class="mt">New profile</div>
    <div class="ms">Creates a unique private manifest URL for a device or person.</div>
    <div class="fg"><label class="fl">Profile name</label><input class="fi" id="n-name" placeholder="e.g. Living Room 4K, Rayyan iPad"/></div>
    <div class="fg"><label class="fl">Minimum quality</label>
      <select class="fsel" id="n-qual"><option value="1080p">1080p and above</option><option value="2160p">4K only</option></select>
    </div>
    <div class="tr"><div><div class="trn">Cached only</div><div class="trd">Only streams already cached on TorBox</div></div><label class="tog"><input type="checkbox" id="n-cache" checked/><div class="tt"></div></label></div>
    <div class="tr"><div><div class="trn">Prefer HEVC / x265</div><div class="trd">Smaller files at equivalent quality</div></div><label class="tog"><input type="checkbox" id="n-hevc" checked/><div class="tt"></div></label></div>
    <div class="tr"><div><div class="trn">Prefer HDR / Dolby Vision</div><div class="trd">HDR10, HDR10+, Dolby Vision</div></div><label class="tog"><input type="checkbox" id="n-hdr" checked/><div class="tt"></div></label></div>
    <div class="tr"><div><div class="trn">Prefer Atmos / TrueHD</div><div class="trd">Lossless and object-based audio formats</div></div><label class="tog"><input type="checkbox" id="n-audio" checked/><div class="tt"></div></label></div>
    <div class="mrow"><button class="btn btn-g" style="flex:1" onclick="createProfile()">Generate manifest</button><button class="btn btn-gh" onclick="closeM()">Cancel</button></div>
  </div>
</div>

<!-- Sidebar -->
<div id="sb">
  <div class="sb-top">
    <div class="sb-logo">
      <div class="sb-mark"><svg viewBox="0 0 24 24"><path d="M5 3l14 9-14 9V3z"/></svg></div>
      <div><div class="sb-name">StreamVault</div><div class="sb-ver">TorBox Pro</div></div>
    </div>
  </div>
  <nav class="sb-nav">
    <div class="ns">Dashboard</div>
    <div class="ni on" id="ni-dash" onclick="go('dash')">
      <svg viewBox="0 0 24 24"><rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/></svg>Overview
    </div>
    <div class="ni" id="ni-profiles" onclick="go('profiles')">
      <svg viewBox="0 0 24 24"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"/></svg>Profiles
    </div>
    <div class="ns">Config</div>
    <div class="ni" id="ni-scoring" onclick="go('scoring')">
      <svg viewBox="0 0 24 24"><line x1="18" y1="20" x2="18" y2="10"/><line x1="12" y1="20" x2="12" y2="4"/><line x1="6" y1="20" x2="6" y2="14"/></svg>Scoring
    </div>
    <div class="ni" id="ni-filters" onclick="go('filters')">
      <svg viewBox="0 0 24 24"><polygon points="22 3 2 3 10 12.46 10 19 14 21 14 12.46 22 3"/></svg>Filters
    </div>
  </nav>
  <div class="sb-foot">
    <div class="st-row"><div class="st-dot" id="sdot"></div><div class="st-lbl" id="slbl">Connecting…</div></div>
  </div>
</div>

<!-- Main -->
<div id="main">

  <!-- Auth -->
  <div class="pg on" id="pg-auth" style="display:flex">
    <div class="ac">
      <div class="a-emb"><svg viewBox="0 0 24 24"><rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg></div>
      <div class="a-t">Admin access</div>
      <div class="a-s">Enter your password to access StreamVault.</div>
      <div class="a-f"><input class="inp" type="password" id="pw" placeholder="Password" onkeydown="if(event.key==='Enter')login()"/><button class="btn btn-g" onclick="login()">Unlock</button></div>
      <div class="a-err" id="aerr">Incorrect password</div>
    </div>
  </div>

  <!-- Overview -->
  <div class="pg" id="pg-dash">
    <div class="pg-h"><div class="pg-t">Overview</div><div class="pg-s">System health and cache performance.</div></div>
    <div class="sg">
      <div class="sc"><div class="sc-ey">Active profiles</div><div class="sc-v g" id="sv-p">—</div><div class="sc-sub">manifest URLs live</div></div>
      <div class="sc"><div class="sc-ey">Cache hits</div><div class="sc-v gr" id="sv-h">—</div><div class="sc-sub">stream lookups served</div></div>
      <div class="sc"><div class="sc-ey">Redis keys</div><div class="sc-v b" id="sv-k">—</div><div class="sc-sub">entries cached</div></div>
    </div>
    <div><div class="sh"><div class="sl">System</div></div><div class="pn" id="sys-rows"></div></div>
  </div>

  <!-- Profiles -->
  <div class="pg" id="pg-profiles">
    <div class="pg-h">
      <div style="display:flex;align-items:flex-start;justify-content:space-between;gap:16px">
        <div><div class="pg-t">Profiles</div><div class="pg-s">Each profile has a unique manifest URL for Stremio.</div></div>
        <button class="btn btn-g" onclick="openM()" style="flex-shrink:0;margin-top:6px">+ New profile</button>
      </div>
    </div>
    <div class="pn" id="prof-panel">
      <div class="emp"><div class="emp-i"><svg viewBox="0 0 24 24"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/></svg></div><div class="emp-t">No profiles yet</div><div class="emp-s">Create a profile to get a manifest URL for Stremio.</div></div>
    </div>
  </div>

  <!-- Scoring -->
  <div class="pg" id="pg-scoring">
    <div class="pg-h"><div class="pg-t">Scoring weights</div><div class="pg-s">How streams are ranked. Higher weight = more preferred.</div></div>
    <div class="pn" id="score-rows"></div>
  </div>

  <!-- Filters -->
  <div class="pg" id="pg-filters">
    <div class="pg-h"><div class="pg-t">Blocked releases</div><div class="pg-s">These release types are always filtered out regardless of profile.</div></div>
    <div class="pn"><div class="bwrap" id="bwrap"></div></div>
  </div>

</div><!-- /main -->

<script>
// ══════════════════════════════════════════
//  Config
// ══════════════════════════════════════════
const SC={resolution4K:{l:'4K Bonus',v:12},dolbyVision:{l:'Dolby Vision',v:10},hevc:{l:'HEVC / x265',v:10},hdrPlus:{l:'HDR10+',v:9},remux:{l:'Remux',v:9},hdr:{l:'HDR10',v:8},bluray:{l:'BluRay',v:7},atmos:{l:'Atmos',v:6},webdl:{l:'WEB-DL',v:6},trueHD:{l:'TrueHD',v:5},webrip:{l:'WEBRip',v:3},dts:{l:'DTS',v:3},h264:{l:'x264',v:1}};
const BL=['CAM','TS','HDCAM','SCR','DVDSCR','TELECINE','TELESYNC','HC','R5'];
let TOK='',INFO={};

// ══════════════════════════════════════════
//  Init
// ══════════════════════════════════════════
fetch('/health').then(r=>{
  document.getElementById('sdot').className='st-dot'+(r.ok?'':' off');
  document.getElementById('slbl').textContent=r.ok?'Online':'Error';
}).catch(()=>{document.getElementById('sdot').className='st-dot off';document.getElementById('slbl').textContent='Offline'});

// ══════════════════════════════════════════
//  Nav
// ══════════════════════════════════════════
function go(id){
  document.querySelectorAll('.pg').forEach(p=>{if(p.id==='pg-auth')return;p.classList.remove('on');p.style.display=''});
  document.querySelectorAll('.ni').forEach(n=>n.classList.remove('on'));
  const p=document.getElementById('pg-'+id);
  if(p){p.classList.add('on');if(id==='watch')p.style.display='flex'}
  const n=document.getElementById('ni-'+id);
  if(n)n.classList.add('on');
  if(id==='watch')renderCW();
}

// ══════════════════════════════════════════
//  Auth
// ══════════════════════════════════════════
async function login(){
  const pw=document.getElementById('pw').value.trim();if(!pw)return;
  TOK=pw;
  const r=await fetch('/api/profiles',{headers:{'x-admin-token':TOK}});
  if(r.status===401){document.getElementById('aerr').style.display='block';TOK='';return}
  document.getElementById('pg-auth').style.display='none';
  document.getElementById('pg-auth').classList.remove('on');
  await loadAll();go('dash');
}

async function api(p,o={}){
  try{const r=await fetch(p,{...o,headers:{'x-admin-token':TOK,'Content-Type':'application/json',...(o.headers||{})}});return r.json()}catch{return{}}
}

// ══════════════════════════════════════════
//  Dashboard data
// ══════════════════════════════════════════
async function loadAll(){
  const [profs,info,cs]=await Promise.all([api('/api/profiles'),api('/api/info'),api('/api/cache/stats')]);
  INFO=info||{};
  document.getElementById('sv-p').textContent=profs.length;
  document.getElementById('sv-h').textContent=cs?.streams?.hits??'0';
  document.getElementById('sv-k').textContent=cs?.streams?.keys??'0';
  renderSys(info);renderProfiles(profs,info);renderScoring();renderBlocked();
}

function renderSys(info){
  const port=info?.port||7000;
  const rows=[
    ['Public URL',info?.publicUrl||'streamvault.raystro.win','var(--gold)'],
    ['Local address',`${info?.nasIp||'192.168.50.198'}:${port}`,'var(--text)'],
    ['TorBox plan',info?.plan||'Pro','var(--green)'],
    ['Redis',info?.redis||'connected','var(--green)'],
    ['Uptime',info?.uptime||'—','var(--text)'],
  ];
  document.getElementById('sys-rows').innerHTML=rows.map(r=>`<div class="srow"><span class="srow-l">${r[0]}</span><span class="srow-r" style="color:${r[2]}">${r[1]}</span></div>`).join('');
}

function renderProfiles(profs,info){
  const el=document.getElementById('prof-panel');
  if(!profs.length){el.innerHTML=`<div class="emp"><div class="emp-i"><svg viewBox="0 0 24 24"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/></svg></div><div class="emp-t">No profiles yet</div><div class="emp-s">Create a profile to get a manifest URL.</div></div>`;return}
  const port=info?.port||7000;
  el.innerHTML=profs.map(p=>{
    const id=p.configId;
    const pub=info?.publicUrl?`https://${info.publicUrl}/config/${id}/manifest.json`:null;
    const lan=info?.nasIp?`http://${info.nasIp}:${port}/config/${id}/manifest.json`:null;
    const urls=[pub?{b:'Public',u:pub}:null,lan?{b:'LAN',u:lan}:null].filter(Boolean);
    const chips=[p.prefs?.cachedOnly?`<span class="chip chip-gr">Cached only</span>`:`<span class="chip chip-d">All sources</span>`,p.prefs?.minQuality?`<span class="chip chip-g">${p.prefs.minQuality}+</span>`:``].join('');
    return`<div class="prof"><div class="prof-h"><div><div class="prof-name">${p.name}</div><div class="prof-id">${id.slice(0,8).toUpperCase()}… · ${new Date(p.createdAt).toLocaleDateString('en-GB',{day:'numeric',month:'short',year:'numeric'})}</div><div class="chips">${chips}</div></div><button class="btn btn-r btn-xs" onclick="delP('${id}')">Remove</button></div><div class="urls">${urls.map(u=>`<div class="urow"><span class="ubadge">${u.b}</span><span class="uval" title="${u.u}">${u.u}</span><button class="cbtn" onclick="cpUrl(this,'${u.u}')"><svg viewBox="0 0 24 24"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg></button></div>`).join('')}</div></div>`;
  }).join('');
}

function renderScoring(){
  document.getElementById('score-rows').innerHTML=Object.values(SC).map(s=>`<div class="scrow"><span class="scn">${s.l}</span><div class="scbw"><div class="scf" style="width:${Math.round(s.v/12*100)}%"></div></div><span class="scnum">${s.v}</span></div>`).join('');
}
function renderBlocked(){
  document.getElementById('bwrap').innerHTML=BL.map(t=>`<span class="btag">${t}</span>`).join('');
}

function openM(){document.getElementById('modal').classList.add('on')}
function closeM(){document.getElementById('modal').classList.remove('on')}

async function createProfile(){
  const name=document.getElementById('n-name').value.trim()||'New Profile';
  const minQuality=document.getElementById('n-qual').value;
  const cachedOnly=document.getElementById('n-cache').checked;
  const hevc=document.getElementById('n-hevc').checked;
  const hdr=document.getElementById('n-hdr').checked;
  const audio=document.getElementById('n-audio').checked;
  const scoring=Object.fromEntries(Object.entries(SC).map(([k,v])=>[k,v.v]));
  if(!hevc)scoring.hevc=0;
  if(!hdr){scoring.hdr=0;scoring.dolbyVision=0;scoring.hdrPlus=0}
  if(!audio){scoring.atmos=0;scoring.trueHD=0}
  await api('/api/profiles',{method:'POST',body:JSON.stringify({name,prefs:{minQuality,cachedOnly,scoring}})});
  closeM();document.getElementById('n-name').value='';
  toast('Profile created');loadAll();
}

async function delP(id){
  if(!confirm('Remove this profile? Its manifest URL will stop working immediately.'))return;
  await api(`/api/profiles/${id}`,{method:'DELETE'});
  toast('Profile removed');loadAll();
}

function cpUrl(btn,url){
  navigator.clipboard.writeText(url).then(()=>{btn.classList.add('ok');setTimeout(()=>btn.classList.remove('ok'),1800);toast('Copied to clipboard')});
}

// ══════════════════════════════════════
//  Toast
// ══════════════════════════════════════════
let tt;
function toast(msg){
  const el=document.getElementById('toast');el.textContent=msg;el.classList.add('on');
  clearTimeout(tt);tt=setTimeout(()=>el.classList.remove('on'),2400);
}
</script>
</body>
</html>
SVEOF_dashboard_index_html

mkdir -p "$INSTALL_DIR/."
cat > "$INSTALL_DIR/package-lock.json" <<'SVEOF_package_lock_json'
{
  "name": "stremio-private-addon",
  "version": "1.0.0",
  "lockfileVersion": 3,
  "requires": true,
  "packages": {
    "": {
      "name": "stremio-private-addon",
      "version": "1.0.0",
      "dependencies": {
        "axios": "^1.6.0",
        "chalk": "^4.1.2",
        "cors": "^2.8.5",
        "dotenv": "^16.3.1",
        "express": "^4.18.2",
        "express-rate-limit": "^7.1.5",
        "form-data": "^4.0.5",
        "ioredis": "^5.10.1",
        "morgan": "^1.10.0",
        "node-cache": "^5.1.2",
        "uuid": "^9.0.0"
      },
      "devDependencies": {
        "nodemon": "^3.0.1"
      }
    },
    "node_modules/@ioredis/commands": {
      "version": "1.5.1",
      "resolved": "https://registry.npmjs.org/@ioredis/commands/-/commands-1.5.1.tgz",
      "integrity": "sha512-JH8ZL/ywcJyR9MmJ5BNqZllXNZQqQbnVZOqpPQqE1vHiFgAw4NHbvE0FOduNU8IX9babitBT46571OnPTT0Zcw==",
      "license": "MIT"
    },
    "node_modules/accepts": {
      "version": "1.3.8",
      "resolved": "https://registry.npmjs.org/accepts/-/accepts-1.3.8.tgz",
      "integrity": "sha512-PYAthTa2m2VKxuvSD3DPC/Gy+U+sOA1LAuT8mkmRuvw+NACSaeXEQ+NHcVF7rONl6qcaxV3Uuemwawk+7+SJLw==",
      "license": "MIT",
      "dependencies": {
        "mime-types": "~2.1.34",
        "negotiator": "0.6.3"
      },
      "engines": {
        "node": ">= 0.6"
      }
    },
    "node_modules/agent-base": {
      "version": "6.0.2",
      "resolved": "https://registry.npmjs.org/agent-base/-/agent-base-6.0.2.tgz",
      "integrity": "sha512-RZNwNclF7+MS/8bDg70amg32dyeZGZxiDuQmZxKLAlQjr3jGyLx+4Kkk58UO7D2QdgFIQCovuSuZESne6RG6XQ==",
      "license": "MIT",
      "dependencies": {
        "debug": "4"
      },
      "engines": {
        "node": ">= 6.0.0"
      }
    },
    "node_modules/agent-base/node_modules/debug": {
      "version": "4.4.3",
      "resolved": "https://registry.npmjs.org/debug/-/debug-4.4.3.tgz",
      "integrity": "sha512-RGwwWnwQvkVfavKVt22FGLw+xYSdzARwm0ru6DhTVA3umU5hZc28V3kO4stgYryrTlLpuvgI9GiijltAjNbcqA==",
      "license": "MIT",
      "dependencies": {
        "ms": "^2.1.3"
      },
      "engines": {
        "node": ">=6.0"
      },
      "peerDependenciesMeta": {
        "supports-color": {
          "optional": true
        }
      }
    },
    "node_modules/agent-base/node_modules/ms": {
      "version": "2.1.3",
      "resolved": "https://registry.npmjs.org/ms/-/ms-2.1.3.tgz",
      "integrity": "sha512-6FlzubTLZG3J2a/NVCAleEhjzq5oxgHyaCU9yYXvcLsvoVaHJq/s5xXI6/XXP6tz7R9xAOtHnSO/tXtF3WRTlA==",
      "license": "MIT"
    },
    "node_modules/ansi-styles": {
      "version": "4.3.0",
      "resolved": "https://registry.npmjs.org/ansi-styles/-/ansi-styles-4.3.0.tgz",
      "integrity": "sha512-zbB9rCJAT1rbjiVDb2hqKFHNYLxgtk8NURxZ3IZwD3F6NtxbXZQCnnSi1Lkx+IDohdPlFp222wVALIheZJQSEg==",
      "license": "MIT",
      "dependencies": {
        "color-convert": "^2.0.1"
      },
      "engines": {
        "node": ">=8"
      },
      "funding": {
        "url": "https://github.com/chalk/ansi-styles?sponsor=1"
      }
    },
    "node_modules/anymatch": {
      "version": "3.1.3",
      "resolved": "https://registry.npmjs.org/anymatch/-/anymatch-3.1.3.tgz",
      "integrity": "sha512-KMReFUr0B4t+D+OBkjR3KYqvocp2XaSzO55UcB6mgQMd3KbcE+mWTyvVV7D/zsdEbNnV6acZUutkiHQXvTr1Rw==",
      "dev": true,
      "license": "ISC",
      "dependencies": {
        "normalize-path": "^3.0.0",
        "picomatch": "^2.0.4"
      },
      "engines": {
        "node": ">= 8"
      }
    },
    "node_modules/array-flatten": {
      "version": "1.1.1",
      "resolved": "https://registry.npmjs.org/array-flatten/-/array-flatten-1.1.1.tgz",
      "integrity": "sha512-PCVAQswWemu6UdxsDFFX/+gVeYqKAod3D3UVm91jHwynguOwAvYPhx8nNlM++NqRcK6CxxpUafjmhIdKiHibqg==",
      "license": "MIT"
    },
    "node_modules/asynckit": {
      "version": "0.4.0",
      "resolved": "https://registry.npmjs.org/asynckit/-/asynckit-0.4.0.tgz",
      "integrity": "sha512-Oei9OH4tRh0YqU3GxhX79dM/mwVgvbZJaSNaRk+bshkj0S5cfHcgYakreBjrHwatXKbz+IoIdYLxrKim2MjW0Q==",
      "license": "MIT"
    },
    "node_modules/axios": {
      "version": "1.16.1",
      "resolved": "https://registry.npmjs.org/axios/-/axios-1.16.1.tgz",
      "integrity": "sha512-caYkukvroVPO8KrzuJEb50Hm07KwfBZPEC3VeFHTsqWHvKTsy54hjJz9BS/cdaypROE2rH6xvm9mHX4fgWkr3A==",
      "license": "MIT",
      "dependencies": {
        "follow-redirects": "^1.16.0",
        "form-data": "^4.0.5",
        "https-proxy-agent": "^5.0.1",
        "proxy-from-env": "^2.1.0"
      }
    },
    "node_modules/balanced-match": {
      "version": "4.0.4",
      "resolved": "https://registry.npmjs.org/balanced-match/-/balanced-match-4.0.4.tgz",
      "integrity": "sha512-BLrgEcRTwX2o6gGxGOCNyMvGSp35YofuYzw9h1IMTRmKqttAZZVU67bdb9Pr2vUHA8+j3i2tJfjO6C6+4myGTA==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": "18 || 20 || >=22"
      }
    },
    "node_modules/basic-auth": {
      "version": "2.0.1",
      "resolved": "https://registry.npmjs.org/basic-auth/-/basic-auth-2.0.1.tgz",
      "integrity": "sha512-NF+epuEdnUYVlGuhaxbbq+dvJttwLnGY+YixlXlME5KpQ5W3CnXA5cVTneY3SPbPDRkcjMbifrwmFYcClgOZeg==",
      "license": "MIT",
      "dependencies": {
        "safe-buffer": "5.1.2"
      },
      "engines": {
        "node": ">= 0.8"
      }
    },
    "node_modules/basic-auth/node_modules/safe-buffer": {
      "version": "5.1.2",
      "resolved": "https://registry.npmjs.org/safe-buffer/-/safe-buffer-5.1.2.tgz",
      "integrity": "sha512-Gd2UZBJDkXlY7GbJxfsE8/nvKkUEU1G38c1siN6QP6a9PT9MmHB8GnpscSmMJSoF8LOIrt8ud/wPtojys4G6+g==",
      "license": "MIT"
    },
    "node_modules/binary-extensions": {
      "version": "2.3.0",
      "resolved": "https://registry.npmjs.org/binary-extensions/-/binary-extensions-2.3.0.tgz",
      "integrity": "sha512-Ceh+7ox5qe7LJuLHoY0feh3pHuUDHAcRUeyL2VYghZwfpkNIy/+8Ocg0a3UuSoYzavmylwuLWQOf3hl0jjMMIw==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=8"
      },
      "funding": {
        "url": "https://github.com/sponsors/sindresorhus"
      }
    },
    "node_modules/body-parser": {
      "version": "1.20.5",
      "resolved": "https://registry.npmjs.org/body-parser/-/body-parser-1.20.5.tgz",
      "integrity": "sha512-3grm+/2tUOvu2cjJkvsIxrv/wVpfXQW4PsQHYm7yk4vfpu7Ekl6nEsYBoJUL6qDwZUx8wUhQ8tR2qz+ad9c9OA==",
      "license": "MIT",
      "dependencies": {
        "bytes": "~3.1.2",
        "content-type": "~1.0.5",
        "debug": "2.6.9",
        "depd": "2.0.0",
        "destroy": "~1.2.0",
        "http-errors": "~2.0.1",
        "iconv-lite": "~0.4.24",
        "on-finished": "~2.4.1",
        "qs": "~6.15.1",
        "raw-body": "~2.5.3",
        "type-is": "~1.6.18",
        "unpipe": "~1.0.0"
      },
      "engines": {
        "node": ">= 0.8",
        "npm": "1.2.8000 || >= 1.4.16"
      }
    },
    "node_modules/brace-expansion": {
      "version": "5.0.6",
      "resolved": "https://registry.npmjs.org/brace-expansion/-/brace-expansion-5.0.6.tgz",
      "integrity": "sha512-kLpxurY4Z4r9sgMsyG0Z9uzsBlgiU/EFKhj/h91/8yHu0edo7XuixOIH3VcJ8kkxs6/jPzoI6U9Vj3WqbMQ94g==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "balanced-match": "^4.0.2"
      },
      "engines": {
        "node": "18 || 20 || >=22"
      }
    },
    "node_modules/braces": {
      "version": "3.0.3",
      "resolved": "https://registry.npmjs.org/braces/-/braces-3.0.3.tgz",
      "integrity": "sha512-yQbXgO/OSZVD2IsiLlro+7Hf6Q18EJrKSEsdoMzKePKXct3gvD8oLcOQdIzGupr5Fj+EDe8gO/lxc1BzfMpxvA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "fill-range": "^7.1.1"
      },
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/bytes": {
      "version": "3.1.2",
      "resolved": "https://registry.npmjs.org/bytes/-/bytes-3.1.2.tgz",
      "integrity": "sha512-/Nf7TyzTx6S3yRJObOAV7956r8cr2+Oj8AC5dt8wSP3BQAoeX58NoHyCU8P8zGkNXStjTSi6fzO6F0pBdcYbEg==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.8"
      }
    },
    "node_modules/call-bind-apply-helpers": {
      "version": "1.0.2",
      "resolved": "https://registry.npmjs.org/call-bind-apply-helpers/-/call-bind-apply-helpers-1.0.2.tgz",
      "integrity": "sha512-Sp1ablJ0ivDkSzjcaJdxEunN5/XvksFJ2sMBFfq6x0ryhQV/2b/KwFe21cMpmHtPOSij8K99/wSfoEuTObmuMQ==",
      "license": "MIT",
      "dependencies": {
        "es-errors": "^1.3.0",
        "function-bind": "^1.1.2"
      },
      "engines": {
        "node": ">= 0.4"
      }
    },
    "node_modules/call-bound": {
      "version": "1.0.4",
      "resolved": "https://registry.npmjs.org/call-bound/-/call-bound-1.0.4.tgz",
      "integrity": "sha512-+ys997U96po4Kx/ABpBCqhA9EuxJaQWDQg7295H4hBphv3IZg0boBKuwYpt4YXp6MZ5AmZQnU/tyMTlRpaSejg==",
      "license": "MIT",
      "dependencies": {
        "call-bind-apply-helpers": "^1.0.2",
        "get-intrinsic": "^1.3.0"
      },
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/chalk": {
      "version": "4.1.2",
      "resolved": "https://registry.npmjs.org/chalk/-/chalk-4.1.2.tgz",
      "integrity": "sha512-oKnbhFyRIXpUuez8iBMmyEa4nbj4IOQyuhc/wy9kY7/WVPcwIO9VA668Pu8RkO7+0G76SLROeyw9CpQ061i4mA==",
      "license": "MIT",
      "dependencies": {
        "ansi-styles": "^4.1.0",
        "supports-color": "^7.1.0"
      },
      "engines": {
        "node": ">=10"
      },
      "funding": {
        "url": "https://github.com/chalk/chalk?sponsor=1"
      }
    },
    "node_modules/chokidar": {
      "version": "3.6.0",
      "resolved": "https://registry.npmjs.org/chokidar/-/chokidar-3.6.0.tgz",
      "integrity": "sha512-7VT13fmjotKpGipCW9JEQAusEPE+Ei8nl6/g4FBAmIm0GOOLMua9NDDo/DWp0ZAxCr3cPq5ZpBqmPAQgDda2Pw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "anymatch": "~3.1.2",
        "braces": "~3.0.2",
        "glob-parent": "~5.1.2",
        "is-binary-path": "~2.1.0",
        "is-glob": "~4.0.1",
        "normalize-path": "~3.0.0",
        "readdirp": "~3.6.0"
      },
      "engines": {
        "node": ">= 8.10.0"
      },
      "funding": {
        "url": "https://paulmillr.com/funding/"
      },
      "optionalDependencies": {
        "fsevents": "~2.3.2"
      }
    },
    "node_modules/clone": {
      "version": "2.1.2",
      "resolved": "https://registry.npmjs.org/clone/-/clone-2.1.2.tgz",
      "integrity": "sha512-3Pe/CF1Nn94hyhIYpjtiLhdCoEoz0DqQ+988E9gmeEdQZlojxnOb74wctFyuwWQHzqyf9X7C7MG8juUpqBJT8w==",
      "license": "MIT",
      "engines": {
        "node": ">=0.8"
      }
    },
    "node_modules/cluster-key-slot": {
      "version": "1.1.2",
      "resolved": "https://registry.npmjs.org/cluster-key-slot/-/cluster-key-slot-1.1.2.tgz",
      "integrity": "sha512-RMr0FhtfXemyinomL4hrWcYJxmX6deFdCxpJzhDttxgO1+bcCnkk+9drydLVDmAMG7NE6aN/fl4F7ucU/90gAA==",
      "license": "Apache-2.0",
      "engines": {
        "node": ">=0.10.0"
      }
    },
    "node_modules/color-convert": {
      "version": "2.0.1",
      "resolved": "https://registry.npmjs.org/color-convert/-/color-convert-2.0.1.tgz",
      "integrity": "sha512-RRECPsj7iu/xb5oKYcsFHSppFNnsj/52OVTRKb4zP5onXwVF3zVmmToNcOfGC+CRDpfK/U584fMg38ZHCaElKQ==",
      "license": "MIT",
      "dependencies": {
        "color-name": "~1.1.4"
      },
      "engines": {
        "node": ">=7.0.0"
      }
    },
    "node_modules/color-name": {
      "version": "1.1.4",
      "resolved": "https://registry.npmjs.org/color-name/-/color-name-1.1.4.tgz",
      "integrity": "sha512-dOy+3AuW3a2wNbZHIuMZpTcgjGuLU/uBL/ubcZF9OXbDo8ff4O8yVp5Bf0efS8uEoYo5q4Fx7dY9OgQGXgAsQA==",
      "license": "MIT"
    },
    "node_modules/combined-stream": {
      "version": "1.0.8",
      "resolved": "https://registry.npmjs.org/combined-stream/-/combined-stream-1.0.8.tgz",
      "integrity": "sha512-FQN4MRfuJeHf7cBbBMJFXhKSDq+2kAArBlmRBvcvFE5BB1HZKXtSFASDhdlz9zOYwxh8lDdnvmMOe/+5cdoEdg==",
      "license": "MIT",
      "dependencies": {
        "delayed-stream": "~1.0.0"
      },
      "engines": {
        "node": ">= 0.8"
      }
    },
    "node_modules/content-disposition": {
      "version": "0.5.4",
      "resolved": "https://registry.npmjs.org/content-disposition/-/content-disposition-0.5.4.tgz",
      "integrity": "sha512-FveZTNuGw04cxlAiWbzi6zTAL/lhehaWbTtgluJh4/E95DqMwTmha3KZN1aAWA8cFIhHzMZUvLevkw5Rqk+tSQ==",
      "license": "MIT",
      "dependencies": {
        "safe-buffer": "5.2.1"
      },
      "engines": {
        "node": ">= 0.6"
      }
    },
    "node_modules/content-type": {
      "version": "1.0.5",
      "resolved": "https://registry.npmjs.org/content-type/-/content-type-1.0.5.tgz",
      "integrity": "sha512-nTjqfcBFEipKdXCv4YDQWCfmcLZKm81ldF0pAopTvyrFGVbcR6P/VAAd5G7N+0tTr8QqiU0tFadD6FK4NtJwOA==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.6"
      }
    },
    "node_modules/cookie": {
      "version": "0.7.2",
      "resolved": "https://registry.npmjs.org/cookie/-/cookie-0.7.2.tgz",
      "integrity": "sha512-yki5XnKuf750l50uGTllt6kKILY4nQ1eNIQatoXEByZ5dWgnKqbnqmTrBE5B4N7lrMJKQ2ytWMiTO2o0v6Ew/w==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.6"
      }
    },
    "node_modules/cookie-signature": {
      "version": "1.0.7",
      "resolved": "https://registry.npmjs.org/cookie-signature/-/cookie-signature-1.0.7.tgz",
      "integrity": "sha512-NXdYc3dLr47pBkpUCHtKSwIOQXLVn8dZEuywboCOJY/osA0wFSLlSawr3KN8qXJEyX66FcONTH8EIlVuK0yyFA==",
      "license": "MIT"
    },
    "node_modules/cors": {
      "version": "2.8.6",
      "resolved": "https://registry.npmjs.org/cors/-/cors-2.8.6.tgz",
      "integrity": "sha512-tJtZBBHA6vjIAaF6EnIaq6laBBP9aq/Y3ouVJjEfoHbRBcHBAHYcMh/w8LDrk2PvIMMq8gmopa5D4V8RmbrxGw==",
      "license": "MIT",
      "dependencies": {
        "object-assign": "^4",
        "vary": "^1"
      },
      "engines": {
        "node": ">= 0.10"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/express"
      }
    },
    "node_modules/debug": {
      "version": "2.6.9",
      "resolved": "https://registry.npmjs.org/debug/-/debug-2.6.9.tgz",
      "integrity": "sha512-bC7ElrdJaJnPbAP+1EotYvqZsb3ecl5wi6Bfi6BJTUcNowp6cvspg0jXznRTKDjm/E7AdgFBVeAPVMNcKGsHMA==",
      "license": "MIT",
      "dependencies": {
        "ms": "2.0.0"
      }
    },
    "node_modules/delayed-stream": {
      "version": "1.0.0",
      "resolved": "https://registry.npmjs.org/delayed-stream/-/delayed-stream-1.0.0.tgz",
      "integrity": "sha512-ZySD7Nf91aLB0RxL4KGrKHBXl7Eds1DAmEdcoVawXnLD7SDhpNgtuII2aAkg7a7QS41jxPSZ17p4VdGnMHk3MQ==",
      "license": "MIT",
      "engines": {
        "node": ">=0.4.0"
      }
    },
    "node_modules/denque": {
      "version": "2.1.0",
      "resolved": "https://registry.npmjs.org/denque/-/denque-2.1.0.tgz",
      "integrity": "sha512-HVQE3AAb/pxF8fQAoiqpvg9i3evqug3hoiwakOyZAwJm+6vZehbkYXZ0l4JxS+I3QxM97v5aaRNhj8v5oBhekw==",
      "license": "Apache-2.0",
      "engines": {
        "node": ">=0.10"
      }
    },
    "node_modules/depd": {
      "version": "2.0.0",
      "resolved": "https://registry.npmjs.org/depd/-/depd-2.0.0.tgz",
      "integrity": "sha512-g7nH6P6dyDioJogAAGprGpCtVImJhpPk/roCzdb3fIh61/s/nPsfR6onyMwkCAR/OlC3yBC0lESvUoQEAssIrw==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.8"
      }
    },
    "node_modules/destroy": {
      "version": "1.2.0",
      "resolved": "https://registry.npmjs.org/destroy/-/destroy-1.2.0.tgz",
      "integrity": "sha512-2sJGJTaXIIaR1w4iJSNoN0hnMY7Gpc/n8D4qSCJw8QqFWXf7cuAgnEHxBpweaVcPevC2l3KpjYCx3NypQQgaJg==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.8",
        "npm": "1.2.8000 || >= 1.4.16"
      }
    },
    "node_modules/dotenv": {
      "version": "16.6.1",
      "resolved": "https://registry.npmjs.org/dotenv/-/dotenv-16.6.1.tgz",
      "integrity": "sha512-uBq4egWHTcTt33a72vpSG0z3HnPuIl6NqYcTrKEg2azoEyl2hpW0zqlxysq2pK9HlDIHyHyakeYaYnSAwd8bow==",
      "license": "BSD-2-Clause",
      "engines": {
        "node": ">=12"
      },
      "funding": {
        "url": "https://dotenvx.com"
      }
    },
    "node_modules/dunder-proto": {
      "version": "1.0.1",
      "resolved": "https://registry.npmjs.org/dunder-proto/-/dunder-proto-1.0.1.tgz",
      "integrity": "sha512-KIN/nDJBQRcXw0MLVhZE9iQHmG68qAVIBg9CqmUYjmQIhgij9U5MFvrqkUL5FbtyyzZuOeOt0zdeRe4UY7ct+A==",
      "license": "MIT",
      "dependencies": {
        "call-bind-apply-helpers": "^1.0.1",
        "es-errors": "^1.3.0",
        "gopd": "^1.2.0"
      },
      "engines": {
        "node": ">= 0.4"
      }
    },
    "node_modules/ee-first": {
      "version": "1.1.1",
      "resolved": "https://registry.npmjs.org/ee-first/-/ee-first-1.1.1.tgz",
      "integrity": "sha512-WMwm9LhRUo+WUaRN+vRuETqG89IgZphVSNkdFgeb6sS/E4OrDIN7t48CAewSHXc6C8lefD8KKfr5vY61brQlow==",
      "license": "MIT"
    },
    "node_modules/encodeurl": {
      "version": "2.0.0",
      "resolved": "https://registry.npmjs.org/encodeurl/-/encodeurl-2.0.0.tgz",
      "integrity": "sha512-Q0n9HRi4m6JuGIV1eFlmvJB7ZEVxu93IrMyiMsGC0lrMJMWzRgx6WGquyfQgZVb31vhGgXnfmPNNXmxnOkRBrg==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.8"
      }
    },
    "node_modules/es-define-property": {
      "version": "1.0.1",
      "resolved": "https://registry.npmjs.org/es-define-property/-/es-define-property-1.0.1.tgz",
      "integrity": "sha512-e3nRfgfUZ4rNGL232gUgX06QNyyez04KdjFrF+LTRoOXmrOgFKDg4BCdsjW8EnT69eqdYGmRpJwiPVYNrCaW3g==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.4"
      }
    },
    "node_modules/es-errors": {
      "version": "1.3.0",
      "resolved": "https://registry.npmjs.org/es-errors/-/es-errors-1.3.0.tgz",
      "integrity": "sha512-Zf5H2Kxt2xjTvbJvP2ZWLEICxA6j+hAmMzIlypy4xcBg1vKVnx89Wy0GbS+kf5cwCVFFzdCFh2XSCFNULS6csw==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.4"
      }
    },
    "node_modules/es-object-atoms": {
      "version": "1.1.1",
      "resolved": "https://registry.npmjs.org/es-object-atoms/-/es-object-atoms-1.1.1.tgz",
      "integrity": "sha512-FGgH2h8zKNim9ljj7dankFPcICIK9Cp5bm+c2gQSYePhpaG5+esrLODihIorn+Pe6FGJzWhXQotPv73jTaldXA==",
      "license": "MIT",
      "dependencies": {
        "es-errors": "^1.3.0"
      },
      "engines": {
        "node": ">= 0.4"
      }
    },
    "node_modules/es-set-tostringtag": {
      "version": "2.1.0",
      "resolved": "https://registry.npmjs.org/es-set-tostringtag/-/es-set-tostringtag-2.1.0.tgz",
      "integrity": "sha512-j6vWzfrGVfyXxge+O0x5sh6cvxAog0a/4Rdd2K36zCMV5eJ+/+tOAngRO8cODMNWbVRdVlmGZQL2YS3yR8bIUA==",
      "license": "MIT",
      "dependencies": {
        "es-errors": "^1.3.0",
        "get-intrinsic": "^1.2.6",
        "has-tostringtag": "^1.0.2",
        "hasown": "^2.0.2"
      },
      "engines": {
        "node": ">= 0.4"
      }
    },
    "node_modules/escape-html": {
      "version": "1.0.3",
      "resolved": "https://registry.npmjs.org/escape-html/-/escape-html-1.0.3.tgz",
      "integrity": "sha512-NiSupZ4OeuGwr68lGIeym/ksIZMJodUGOSCZ/FSnTxcrekbvqrgdUxlJOMpijaKZVjAJrWrGs/6Jy8OMuyj9ow==",
      "license": "MIT"
    },
    "node_modules/etag": {
      "version": "1.8.1",
      "resolved": "https://registry.npmjs.org/etag/-/etag-1.8.1.tgz",
      "integrity": "sha512-aIL5Fx7mawVa300al2BnEE4iNvo1qETxLrPI/o05L7z6go7fCw1J6EQmbK4FmJ2AS7kgVF/KEZWufBfdClMcPg==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.6"
      }
    },
    "node_modules/express": {
      "version": "4.22.2",
      "resolved": "https://registry.npmjs.org/express/-/express-4.22.2.tgz",
      "integrity": "sha512-IuL+Elrou2ZvCFHs18/CIzy2Nzvo25nZ1/D2eIZlz7c+QUayAcYoiM2BthCjs+EBHVpjYjcuLDAiCWgeIX3X1Q==",
      "license": "MIT",
      "dependencies": {
        "accepts": "~1.3.8",
        "array-flatten": "1.1.1",
        "body-parser": "~1.20.5",
        "content-disposition": "~0.5.4",
        "content-type": "~1.0.4",
        "cookie": "~0.7.1",
        "cookie-signature": "~1.0.6",
        "debug": "2.6.9",
        "depd": "2.0.0",
        "encodeurl": "~2.0.0",
        "escape-html": "~1.0.3",
        "etag": "~1.8.1",
        "finalhandler": "~1.3.1",
        "fresh": "~0.5.2",
        "http-errors": "~2.0.0",
        "merge-descriptors": "1.0.3",
        "methods": "~1.1.2",
        "on-finished": "~2.4.1",
        "parseurl": "~1.3.3",
        "path-to-regexp": "~0.1.12",
        "proxy-addr": "~2.0.7",
        "qs": "~6.15.1",
        "range-parser": "~1.2.1",
        "safe-buffer": "5.2.1",
        "send": "~0.19.0",
        "serve-static": "~1.16.2",
        "setprototypeof": "1.2.0",
        "statuses": "~2.0.1",
        "type-is": "~1.6.18",
        "utils-merge": "1.0.1",
        "vary": "~1.1.2"
      },
      "engines": {
        "node": ">= 0.10.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/express"
      }
    },
    "node_modules/express-rate-limit": {
      "version": "7.5.1",
      "resolved": "https://registry.npmjs.org/express-rate-limit/-/express-rate-limit-7.5.1.tgz",
      "integrity": "sha512-7iN8iPMDzOMHPUYllBEsQdWVB6fPDMPqwjBaFrgr4Jgr/+okjvzAy+UHlYYL/Vs0OsOrMkwS6PJDkFlJwoxUnw==",
      "license": "MIT",
      "engines": {
        "node": ">= 16"
      },
      "funding": {
        "url": "https://github.com/sponsors/express-rate-limit"
      },
      "peerDependencies": {
        "express": ">= 4.11"
      }
    },
    "node_modules/fill-range": {
      "version": "7.1.1",
      "resolved": "https://registry.npmjs.org/fill-range/-/fill-range-7.1.1.tgz",
      "integrity": "sha512-YsGpe3WHLK8ZYi4tWDg2Jy3ebRz2rXowDxnld4bkQB00cc/1Zw9AWnC0i9ztDJitivtQvaI9KaLyKrc+hBW0yg==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "to-regex-range": "^5.0.1"
      },
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/finalhandler": {
      "version": "1.3.2",
      "resolved": "https://registry.npmjs.org/finalhandler/-/finalhandler-1.3.2.tgz",
      "integrity": "sha512-aA4RyPcd3badbdABGDuTXCMTtOneUCAYH/gxoYRTZlIJdF0YPWuGqiAsIrhNnnqdXGswYk6dGujem4w80UJFhg==",
      "license": "MIT",
      "dependencies": {
        "debug": "2.6.9",
        "encodeurl": "~2.0.0",
        "escape-html": "~1.0.3",
        "on-finished": "~2.4.1",
        "parseurl": "~1.3.3",
        "statuses": "~2.0.2",
        "unpipe": "~1.0.0"
      },
      "engines": {
        "node": ">= 0.8"
      }
    },
    "node_modules/follow-redirects": {
      "version": "1.16.0",
      "resolved": "https://registry.npmjs.org/follow-redirects/-/follow-redirects-1.16.0.tgz",
      "integrity": "sha512-y5rN/uOsadFT/JfYwhxRS5R7Qce+g3zG97+JrtFZlC9klX/W5hD7iiLzScI4nZqUS7DNUdhPgw4xI8W2LuXlUw==",
      "funding": [
        {
          "type": "individual",
          "url": "https://github.com/sponsors/RubenVerborgh"
        }
      ],
      "license": "MIT",
      "engines": {
        "node": ">=4.0"
      },
      "peerDependenciesMeta": {
        "debug": {
          "optional": true
        }
      }
    },
    "node_modules/form-data": {
      "version": "4.0.5",
      "resolved": "https://registry.npmjs.org/form-data/-/form-data-4.0.5.tgz",
      "integrity": "sha512-8RipRLol37bNs2bhoV67fiTEvdTrbMUYcFTiy3+wuuOnUog2QBHCZWXDRijWQfAkhBj2Uf5UnVaiWwA5vdd82w==",
      "license": "MIT",
      "dependencies": {
        "asynckit": "^0.4.0",
        "combined-stream": "^1.0.8",
        "es-set-tostringtag": "^2.1.0",
        "hasown": "^2.0.2",
        "mime-types": "^2.1.12"
      },
      "engines": {
        "node": ">= 6"
      }
    },
    "node_modules/forwarded": {
      "version": "0.2.0",
      "resolved": "https://registry.npmjs.org/forwarded/-/forwarded-0.2.0.tgz",
      "integrity": "sha512-buRG0fpBtRHSTCOASe6hD258tEubFoRLb4ZNA6NxMVHNw2gOcwHo9wyablzMzOA5z9xA9L1KNjk/Nt6MT9aYow==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.6"
      }
    },
    "node_modules/fresh": {
      "version": "0.5.2",
      "resolved": "https://registry.npmjs.org/fresh/-/fresh-0.5.2.tgz",
      "integrity": "sha512-zJ2mQYM18rEFOudeV4GShTGIQ7RbzA7ozbU9I/XBpm7kqgMywgmylMwXHxZJmkVoYkna9d2pVXVXPdYTP9ej8Q==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.6"
      }
    },
    "node_modules/fsevents": {
      "version": "2.3.3",
      "resolved": "https://registry.npmjs.org/fsevents/-/fsevents-2.3.3.tgz",
      "integrity": "sha512-5xoDfX+fL7faATnagmWPpbFtwh/R77WmMMqqHGS65C3vvB0YHrgF+B1YmZ3441tMj5n63k0212XNoJwzlhffQw==",
      "dev": true,
      "hasInstallScript": true,
      "license": "MIT",
      "optional": true,
      "os": [
        "darwin"
      ],
      "engines": {
        "node": "^8.16.0 || ^10.6.0 || >=11.0.0"
      }
    },
    "node_modules/function-bind": {
      "version": "1.1.2",
      "resolved": "https://registry.npmjs.org/function-bind/-/function-bind-1.1.2.tgz",
      "integrity": "sha512-7XHNxH7qX9xG5mIwxkhumTox/MIRNcOgDrxWsMt2pAr23WHp6MrRlN7FBSFpCpr+oVO0F744iUgR82nJMfG2SA==",
      "license": "MIT",
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/get-intrinsic": {
      "version": "1.3.0",
      "resolved": "https://registry.npmjs.org/get-intrinsic/-/get-intrinsic-1.3.0.tgz",
      "integrity": "sha512-9fSjSaos/fRIVIp+xSJlE6lfwhES7LNtKaCBIamHsjr2na1BiABJPo0mOjjz8GJDURarmCPGqaiVg5mfjb98CQ==",
      "license": "MIT",
      "dependencies": {
        "call-bind-apply-helpers": "^1.0.2",
        "es-define-property": "^1.0.1",
        "es-errors": "^1.3.0",
        "es-object-atoms": "^1.1.1",
        "function-bind": "^1.1.2",
        "get-proto": "^1.0.1",
        "gopd": "^1.2.0",
        "has-symbols": "^1.1.0",
        "hasown": "^2.0.2",
        "math-intrinsics": "^1.1.0"
      },
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/get-proto": {
      "version": "1.0.1",
      "resolved": "https://registry.npmjs.org/get-proto/-/get-proto-1.0.1.tgz",
      "integrity": "sha512-sTSfBjoXBp89JvIKIefqw7U2CCebsc74kiY6awiGogKtoSGbgjYE/G/+l9sF3MWFPNc9IcoOC4ODfKHfxFmp0g==",
      "license": "MIT",
      "dependencies": {
        "dunder-proto": "^1.0.1",
        "es-object-atoms": "^1.0.0"
      },
      "engines": {
        "node": ">= 0.4"
      }
    },
    "node_modules/glob-parent": {
      "version": "5.1.2",
      "resolved": "https://registry.npmjs.org/glob-parent/-/glob-parent-5.1.2.tgz",
      "integrity": "sha512-AOIgSQCepiJYwP3ARnGx+5VnTu2HBYdzbGP45eLw1vr3zB3vZLeyed1sC9hnbcOc9/SrMyM5RPQrkGz4aS9Zow==",
      "dev": true,
      "license": "ISC",
      "dependencies": {
        "is-glob": "^4.0.1"
      },
      "engines": {
        "node": ">= 6"
      }
    },
    "node_modules/gopd": {
      "version": "1.2.0",
      "resolved": "https://registry.npmjs.org/gopd/-/gopd-1.2.0.tgz",
      "integrity": "sha512-ZUKRh6/kUFoAiTAtTYPZJ3hw9wNxx+BIBOijnlG9PnrJsCcSjs1wyyD6vJpaYtgnzDrKYRSqf3OO6Rfa93xsRg==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/has-flag": {
      "version": "4.0.0",
      "resolved": "https://registry.npmjs.org/has-flag/-/has-flag-4.0.0.tgz",
      "integrity": "sha512-EykJT/Q1KjTWctppgIAgfSO0tKVuZUjhgMr17kqTumMl6Afv3EISleU7qZUzoXDFTAHTDC4NOoG/ZxU3EvlMPQ==",
      "license": "MIT",
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/has-symbols": {
      "version": "1.1.0",
      "resolved": "https://registry.npmjs.org/has-symbols/-/has-symbols-1.1.0.tgz",
      "integrity": "sha512-1cDNdwJ2Jaohmb3sg4OmKaMBwuC48sYni5HUw2DvsC8LjGTLK9h+eb1X6RyuOHe4hT0ULCW68iomhjUoKUqlPQ==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/has-tostringtag": {
      "version": "1.0.2",
      "resolved": "https://registry.npmjs.org/has-tostringtag/-/has-tostringtag-1.0.2.tgz",
      "integrity": "sha512-NqADB8VjPFLM2V0VvHUewwwsw0ZWBaIdgo+ieHtK3hasLz4qeCRjYcqfB6AQrBggRKppKF8L52/VqdVsO47Dlw==",
      "license": "MIT",
      "dependencies": {
        "has-symbols": "^1.0.3"
      },
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/hasown": {
      "version": "2.0.3",
      "resolved": "https://registry.npmjs.org/hasown/-/hasown-2.0.3.tgz",
      "integrity": "sha512-ej4AhfhfL2Q2zpMmLo7U1Uv9+PyhIZpgQLGT1F9miIGmiCJIoCgSmczFdrc97mWT4kVY72KA+WnnhJ5pghSvSg==",
      "license": "MIT",
      "dependencies": {
        "function-bind": "^1.1.2"
      },
      "engines": {
        "node": ">= 0.4"
      }
    },
    "node_modules/http-errors": {
      "version": "2.0.1",
      "resolved": "https://registry.npmjs.org/http-errors/-/http-errors-2.0.1.tgz",
      "integrity": "sha512-4FbRdAX+bSdmo4AUFuS0WNiPz8NgFt+r8ThgNWmlrjQjt1Q7ZR9+zTlce2859x4KSXrwIsaeTqDoKQmtP8pLmQ==",
      "license": "MIT",
      "dependencies": {
        "depd": "~2.0.0",
        "inherits": "~2.0.4",
        "setprototypeof": "~1.2.0",
        "statuses": "~2.0.2",
        "toidentifier": "~1.0.1"
      },
      "engines": {
        "node": ">= 0.8"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/express"
      }
    },
    "node_modules/https-proxy-agent": {
      "version": "5.0.1",
      "resolved": "https://registry.npmjs.org/https-proxy-agent/-/https-proxy-agent-5.0.1.tgz",
      "integrity": "sha512-dFcAjpTQFgoLMzC2VwU+C/CbS7uRL0lWmxDITmqm7C+7F0Odmj6s9l6alZc6AELXhrnggM2CeWSXHGOdX2YtwA==",
      "license": "MIT",
      "dependencies": {
        "agent-base": "6",
        "debug": "4"
      },
      "engines": {
        "node": ">= 6"
      }
    },
    "node_modules/https-proxy-agent/node_modules/debug": {
      "version": "4.4.3",
      "resolved": "https://registry.npmjs.org/debug/-/debug-4.4.3.tgz",
      "integrity": "sha512-RGwwWnwQvkVfavKVt22FGLw+xYSdzARwm0ru6DhTVA3umU5hZc28V3kO4stgYryrTlLpuvgI9GiijltAjNbcqA==",
      "license": "MIT",
      "dependencies": {
        "ms": "^2.1.3"
      },
      "engines": {
        "node": ">=6.0"
      },
      "peerDependenciesMeta": {
        "supports-color": {
          "optional": true
        }
      }
    },
    "node_modules/https-proxy-agent/node_modules/ms": {
      "version": "2.1.3",
      "resolved": "https://registry.npmjs.org/ms/-/ms-2.1.3.tgz",
      "integrity": "sha512-6FlzubTLZG3J2a/NVCAleEhjzq5oxgHyaCU9yYXvcLsvoVaHJq/s5xXI6/XXP6tz7R9xAOtHnSO/tXtF3WRTlA==",
      "license": "MIT"
    },
    "node_modules/iconv-lite": {
      "version": "0.4.24",
      "resolved": "https://registry.npmjs.org/iconv-lite/-/iconv-lite-0.4.24.tgz",
      "integrity": "sha512-v3MXnZAcvnywkTUEZomIActle7RXXeedOR31wwl7VlyoXO4Qi9arvSenNQWne1TcRwhCL1HwLI21bEqdpj8/rA==",
      "license": "MIT",
      "dependencies": {
        "safer-buffer": ">= 2.1.2 < 3"
      },
      "engines": {
        "node": ">=0.10.0"
      }
    },
    "node_modules/ignore-by-default": {
      "version": "1.0.1",
      "resolved": "https://registry.npmjs.org/ignore-by-default/-/ignore-by-default-1.0.1.tgz",
      "integrity": "sha512-Ius2VYcGNk7T90CppJqcIkS5ooHUZyIQK+ClZfMfMNFEF9VSE73Fq+906u/CWu92x4gzZMWOwfFYckPObzdEbA==",
      "dev": true,
      "license": "ISC"
    },
    "node_modules/inherits": {
      "version": "2.0.4",
      "resolved": "https://registry.npmjs.org/inherits/-/inherits-2.0.4.tgz",
      "integrity": "sha512-k/vGaX4/Yla3WzyMCvTQOXYeIHvqOKtnqBduzTHpzpQZzAskKMhZ2K+EnBiSM9zGSoIFeMpXKxa4dYeZIQqewQ==",
      "license": "ISC"
    },
    "node_modules/ioredis": {
      "version": "5.10.1",
      "resolved": "https://registry.npmjs.org/ioredis/-/ioredis-5.10.1.tgz",
      "integrity": "sha512-HuEDBTI70aYdx1v6U97SbNx9F1+svQKBDo30o0b9fw055LMepzpOOd0Ccg9Q6tbqmBSJaMuY0fB7yw9/vjBYCA==",
      "license": "MIT",
      "dependencies": {
        "@ioredis/commands": "1.5.1",
        "cluster-key-slot": "^1.1.0",
        "debug": "^4.3.4",
        "denque": "^2.1.0",
        "lodash.defaults": "^4.2.0",
        "lodash.isarguments": "^3.1.0",
        "redis-errors": "^1.2.0",
        "redis-parser": "^3.0.0",
        "standard-as-callback": "^2.1.0"
      },
      "engines": {
        "node": ">=12.22.0"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/ioredis"
      }
    },
    "node_modules/ioredis/node_modules/debug": {
      "version": "4.4.3",
      "resolved": "https://registry.npmjs.org/debug/-/debug-4.4.3.tgz",
      "integrity": "sha512-RGwwWnwQvkVfavKVt22FGLw+xYSdzARwm0ru6DhTVA3umU5hZc28V3kO4stgYryrTlLpuvgI9GiijltAjNbcqA==",
      "license": "MIT",
      "dependencies": {
        "ms": "^2.1.3"
      },
      "engines": {
        "node": ">=6.0"
      },
      "peerDependenciesMeta": {
        "supports-color": {
          "optional": true
        }
      }
    },
    "node_modules/ioredis/node_modules/ms": {
      "version": "2.1.3",
      "resolved": "https://registry.npmjs.org/ms/-/ms-2.1.3.tgz",
      "integrity": "sha512-6FlzubTLZG3J2a/NVCAleEhjzq5oxgHyaCU9yYXvcLsvoVaHJq/s5xXI6/XXP6tz7R9xAOtHnSO/tXtF3WRTlA==",
      "license": "MIT"
    },
    "node_modules/ipaddr.js": {
      "version": "1.9.1",
      "resolved": "https://registry.npmjs.org/ipaddr.js/-/ipaddr.js-1.9.1.tgz",
      "integrity": "sha512-0KI/607xoxSToH7GjN1FfSbLoU0+btTicjsQSWQlh/hZykN8KpmMf7uYwPW3R+akZ6R/w18ZlXSHBYXiYUPO3g==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.10"
      }
    },
    "node_modules/is-binary-path": {
      "version": "2.1.0",
      "resolved": "https://registry.npmjs.org/is-binary-path/-/is-binary-path-2.1.0.tgz",
      "integrity": "sha512-ZMERYes6pDydyuGidse7OsHxtbI7WVeUEozgR/g7rd0xUimYNlvZRE/K2MgZTjWy725IfelLeVcEM97mmtRGXw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "binary-extensions": "^2.0.0"
      },
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/is-extglob": {
      "version": "2.1.1",
      "resolved": "https://registry.npmjs.org/is-extglob/-/is-extglob-2.1.1.tgz",
      "integrity": "sha512-SbKbANkN603Vi4jEZv49LeVJMn4yGwsbzZworEoyEiutsN3nJYdbO36zfhGJ6QEDpOZIFkDtnq5JRxmvl3jsoQ==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=0.10.0"
      }
    },
    "node_modules/is-glob": {
      "version": "4.0.3",
      "resolved": "https://registry.npmjs.org/is-glob/-/is-glob-4.0.3.tgz",
      "integrity": "sha512-xelSayHH36ZgE7ZWhli7pW34hNbNl8Ojv5KVmkJD4hBdD3th8Tfk9vYasLM+mXWOZhFkgZfxhLSnrwRr4elSSg==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "is-extglob": "^2.1.1"
      },
      "engines": {
        "node": ">=0.10.0"
      }
    },
    "node_modules/is-number": {
      "version": "7.0.0",
      "resolved": "https://registry.npmjs.org/is-number/-/is-number-7.0.0.tgz",
      "integrity": "sha512-41Cifkg6e8TylSpdtTpeLVMqvSBEVzTttHvERD741+pnZ8ANv0004MRL43QKPDlK9cGvNp6NZWZUBlbGXYxxng==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=0.12.0"
      }
    },
    "node_modules/lodash.defaults": {
      "version": "4.2.0",
      "resolved": "https://registry.npmjs.org/lodash.defaults/-/lodash.defaults-4.2.0.tgz",
      "integrity": "sha512-qjxPLHd3r5DnsdGacqOMU6pb/avJzdh9tFX2ymgoZE27BmjXrNy/y4LoaiTeAb+O3gL8AfpJGtqfX/ae2leYYQ==",
      "license": "MIT"
    },
    "node_modules/lodash.isarguments": {
      "version": "3.1.0",
      "resolved": "https://registry.npmjs.org/lodash.isarguments/-/lodash.isarguments-3.1.0.tgz",
      "integrity": "sha512-chi4NHZlZqZD18a0imDHnZPrDeBbTtVN7GXMwuGdRH9qotxAjYs3aVLKc7zNOG9eddR5Ksd8rvFEBc9SsggPpg==",
      "license": "MIT"
    },
    "node_modules/math-intrinsics": {
      "version": "1.1.0",
      "resolved": "https://registry.npmjs.org/math-intrinsics/-/math-intrinsics-1.1.0.tgz",
      "integrity": "sha512-/IXtbwEk5HTPyEwyKX6hGkYXxM9nbj64B+ilVJnC/R6B0pH5G4V3b0pVbL7DBj4tkhBAppbQUlf6F6Xl9LHu1g==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.4"
      }
    },
    "node_modules/media-typer": {
      "version": "0.3.0",
      "resolved": "https://registry.npmjs.org/media-typer/-/media-typer-0.3.0.tgz",
      "integrity": "sha512-dq+qelQ9akHpcOl/gUVRTxVIOkAJ1wR3QAvb4RsVjS8oVoFjDGTc679wJYmUmknUF5HwMLOgb5O+a3KxfWapPQ==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.6"
      }
    },
    "node_modules/merge-descriptors": {
      "version": "1.0.3",
      "resolved": "https://registry.npmjs.org/merge-descriptors/-/merge-descriptors-1.0.3.tgz",
      "integrity": "sha512-gaNvAS7TZ897/rVaZ0nMtAyxNyi/pdbjbAwUpFQpN70GqnVfOiXpeUUMKRBmzXaSQ8DdTX4/0ms62r2K+hE6mQ==",
      "license": "MIT",
      "funding": {
        "url": "https://github.com/sponsors/sindresorhus"
      }
    },
    "node_modules/methods": {
      "version": "1.1.2",
      "resolved": "https://registry.npmjs.org/methods/-/methods-1.1.2.tgz",
      "integrity": "sha512-iclAHeNqNm68zFtnZ0e+1L2yUIdvzNoauKU4WBA3VvH/vPFieF7qfRlwUZU+DA9P9bPXIS90ulxoUoCH23sV2w==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.6"
      }
    },
    "node_modules/mime": {
      "version": "1.6.0",
      "resolved": "https://registry.npmjs.org/mime/-/mime-1.6.0.tgz",
      "integrity": "sha512-x0Vn8spI+wuJ1O6S7gnbaQg8Pxh4NNHb7KSINmEWKiPE4RKOplvijn+NkmYmmRgP68mc70j2EbeTFRsrswaQeg==",
      "license": "MIT",
      "bin": {
        "mime": "cli.js"
      },
      "engines": {
        "node": ">=4"
      }
    },
    "node_modules/mime-db": {
      "version": "1.52.0",
      "resolved": "https://registry.npmjs.org/mime-db/-/mime-db-1.52.0.tgz",
      "integrity": "sha512-sPU4uV7dYlvtWJxwwxHD0PuihVNiE7TyAbQ5SWxDCB9mUYvOgroQOwYQQOKPJ8CIbE+1ETVlOoK1UC2nU3gYvg==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.6"
      }
    },
    "node_modules/mime-types": {
      "version": "2.1.35",
      "resolved": "https://registry.npmjs.org/mime-types/-/mime-types-2.1.35.tgz",
      "integrity": "sha512-ZDY+bPm5zTTF+YpCrAU9nK0UgICYPT0QtT1NZWFv4s++TNkcgVaT0g6+4R2uI4MjQjzysHB1zxuWL50hzaeXiw==",
      "license": "MIT",
      "dependencies": {
        "mime-db": "1.52.0"
      },
      "engines": {
        "node": ">= 0.6"
      }
    },
    "node_modules/minimatch": {
      "version": "10.2.5",
      "resolved": "https://registry.npmjs.org/minimatch/-/minimatch-10.2.5.tgz",
      "integrity": "sha512-MULkVLfKGYDFYejP07QOurDLLQpcjk7Fw+7jXS2R2czRQzR56yHRveU5NDJEOviH+hETZKSkIk5c+T23GjFUMg==",
      "dev": true,
      "license": "BlueOak-1.0.0",
      "dependencies": {
        "brace-expansion": "^5.0.5"
      },
      "engines": {
        "node": "18 || 20 || >=22"
      },
      "funding": {
        "url": "https://github.com/sponsors/isaacs"
      }
    },
    "node_modules/morgan": {
      "version": "1.10.1",
      "resolved": "https://registry.npmjs.org/morgan/-/morgan-1.10.1.tgz",
      "integrity": "sha512-223dMRJtI/l25dJKWpgij2cMtywuG/WiUKXdvwfbhGKBhy1puASqXwFzmWZ7+K73vUPoR7SS2Qz2cI/g9MKw0A==",
      "license": "MIT",
      "dependencies": {
        "basic-auth": "~2.0.1",
        "debug": "2.6.9",
        "depd": "~2.0.0",
        "on-finished": "~2.3.0",
        "on-headers": "~1.1.0"
      },
      "engines": {
        "node": ">= 0.8.0"
      }
    },
    "node_modules/morgan/node_modules/on-finished": {
      "version": "2.3.0",
      "resolved": "https://registry.npmjs.org/on-finished/-/on-finished-2.3.0.tgz",
      "integrity": "sha512-ikqdkGAAyf/X/gPhXGvfgAytDZtDbr+bkNUJ0N9h5MI/dmdgCs3l6hoHrcUv41sRKew3jIwrp4qQDXiK99Utww==",
      "license": "MIT",
      "dependencies": {
        "ee-first": "1.1.1"
      },
      "engines": {
        "node": ">= 0.8"
      }
    },
    "node_modules/ms": {
      "version": "2.0.0",
      "resolved": "https://registry.npmjs.org/ms/-/ms-2.0.0.tgz",
      "integrity": "sha512-Tpp60P6IUJDTuOq/5Z8cdskzJujfwqfOTkrwIwj7IRISpnkJnT6SyJ4PCPnGMoFjC9ddhal5KVIYtAt97ix05A==",
      "license": "MIT"
    },
    "node_modules/negotiator": {
      "version": "0.6.3",
      "resolved": "https://registry.npmjs.org/negotiator/-/negotiator-0.6.3.tgz",
      "integrity": "sha512-+EUsqGPLsM+j/zdChZjsnX51g4XrHFOIXwfnCVPGlQk/k5giakcKsuxCObBRu6DSm9opw/O6slWbJdghQM4bBg==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.6"
      }
    },
    "node_modules/node-cache": {
      "version": "5.1.2",
      "resolved": "https://registry.npmjs.org/node-cache/-/node-cache-5.1.2.tgz",
      "integrity": "sha512-t1QzWwnk4sjLWaQAS8CHgOJ+RAfmHpxFWmc36IWTiWHQfs0w5JDMBS1b1ZxQteo0vVVuWJvIUKHDkkeK7vIGCg==",
      "license": "MIT",
      "dependencies": {
        "clone": "2.x"
      },
      "engines": {
        "node": ">= 8.0.0"
      }
    },
    "node_modules/nodemon": {
      "version": "3.1.14",
      "resolved": "https://registry.npmjs.org/nodemon/-/nodemon-3.1.14.tgz",
      "integrity": "sha512-jakjZi93UtB3jHMWsXL68FXSAosbLfY0In5gtKq3niLSkrWznrVBzXFNOEMJUfc9+Ke7SHWoAZsiMkNP3vq6Jw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "chokidar": "^3.5.2",
        "debug": "^4",
        "ignore-by-default": "^1.0.1",
        "minimatch": "^10.2.1",
        "pstree.remy": "^1.1.8",
        "semver": "^7.5.3",
        "simple-update-notifier": "^2.0.0",
        "supports-color": "^5.5.0",
        "touch": "^3.1.0",
        "undefsafe": "^2.0.5"
      },
      "bin": {
        "nodemon": "bin/nodemon.js"
      },
      "engines": {
        "node": ">=10"
      },
      "funding": {
        "type": "opencollective",
        "url": "https://opencollective.com/nodemon"
      }
    },
    "node_modules/nodemon/node_modules/debug": {
      "version": "4.4.3",
      "resolved": "https://registry.npmjs.org/debug/-/debug-4.4.3.tgz",
      "integrity": "sha512-RGwwWnwQvkVfavKVt22FGLw+xYSdzARwm0ru6DhTVA3umU5hZc28V3kO4stgYryrTlLpuvgI9GiijltAjNbcqA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "ms": "^2.1.3"
      },
      "engines": {
        "node": ">=6.0"
      },
      "peerDependenciesMeta": {
        "supports-color": {
          "optional": true
        }
      }
    },
    "node_modules/nodemon/node_modules/has-flag": {
      "version": "3.0.0",
      "resolved": "https://registry.npmjs.org/has-flag/-/has-flag-3.0.0.tgz",
      "integrity": "sha512-sKJf1+ceQBr4SMkvQnBDNDtf4TXpVhVGateu0t918bl30FnbE2m4vNLX+VWe/dpjlb+HugGYzW7uQXH98HPEYw==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=4"
      }
    },
    "node_modules/nodemon/node_modules/ms": {
      "version": "2.1.3",
      "resolved": "https://registry.npmjs.org/ms/-/ms-2.1.3.tgz",
      "integrity": "sha512-6FlzubTLZG3J2a/NVCAleEhjzq5oxgHyaCU9yYXvcLsvoVaHJq/s5xXI6/XXP6tz7R9xAOtHnSO/tXtF3WRTlA==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/nodemon/node_modules/supports-color": {
      "version": "5.5.0",
      "resolved": "https://registry.npmjs.org/supports-color/-/supports-color-5.5.0.tgz",
      "integrity": "sha512-QjVjwdXIt408MIiAqCX4oUKsgU2EqAGzs2Ppkm4aQYbjm+ZEWEcW4SfFNTr4uMNZma0ey4f5lgLrkB0aX0QMow==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "has-flag": "^3.0.0"
      },
      "engines": {
        "node": ">=4"
      }
    },
    "node_modules/normalize-path": {
      "version": "3.0.0",
      "resolved": "https://registry.npmjs.org/normalize-path/-/normalize-path-3.0.0.tgz",
      "integrity": "sha512-6eZs5Ls3WtCisHWp9S2GUy8dqkpGi4BVSz3GaqiE6ezub0512ESztXUwUB6C6IKbQkY2Pnb/mD4WYojCRwcwLA==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=0.10.0"
      }
    },
    "node_modules/object-assign": {
      "version": "4.1.1",
      "resolved": "https://registry.npmjs.org/object-assign/-/object-assign-4.1.1.tgz",
      "integrity": "sha512-rJgTQnkUnH1sFw8yT6VSU3zD3sWmu6sZhIseY8VX+GRu3P6F7Fu+JNDoXfklElbLJSnc3FUQHVe4cU5hj+BcUg==",
      "license": "MIT",
      "engines": {
        "node": ">=0.10.0"
      }
    },
    "node_modules/object-inspect": {
      "version": "1.13.4",
      "resolved": "https://registry.npmjs.org/object-inspect/-/object-inspect-1.13.4.tgz",
      "integrity": "sha512-W67iLl4J2EXEGTbfeHCffrjDfitvLANg0UlX3wFUUSTx92KXRFegMHUVgSqE+wvhAbi4WqjGg9czysTV2Epbew==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/on-finished": {
      "version": "2.4.1",
      "resolved": "https://registry.npmjs.org/on-finished/-/on-finished-2.4.1.tgz",
      "integrity": "sha512-oVlzkg3ENAhCk2zdv7IJwd/QUD4z2RxRwpkcGY8psCVcCYZNq4wYnVWALHM+brtuJjePWiYF/ClmuDr8Ch5+kg==",
      "license": "MIT",
      "dependencies": {
        "ee-first": "1.1.1"
      },
      "engines": {
        "node": ">= 0.8"
      }
    },
    "node_modules/on-headers": {
      "version": "1.1.0",
      "resolved": "https://registry.npmjs.org/on-headers/-/on-headers-1.1.0.tgz",
      "integrity": "sha512-737ZY3yNnXy37FHkQxPzt4UZ2UWPWiCZWLvFZ4fu5cueciegX0zGPnrlY6bwRg4FdQOe9YU8MkmJwGhoMybl8A==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.8"
      }
    },
    "node_modules/parseurl": {
      "version": "1.3.3",
      "resolved": "https://registry.npmjs.org/parseurl/-/parseurl-1.3.3.tgz",
      "integrity": "sha512-CiyeOxFT/JZyN5m0z9PfXw4SCBJ6Sygz1Dpl0wqjlhDEGGBP1GnsUVEL0p63hoG1fcj3fHynXi9NYO4nWOL+qQ==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.8"
      }
    },
    "node_modules/path-to-regexp": {
      "version": "0.1.13",
      "resolved": "https://registry.npmjs.org/path-to-regexp/-/path-to-regexp-0.1.13.tgz",
      "integrity": "sha512-A/AGNMFN3c8bOlvV9RreMdrv7jsmF9XIfDeCd87+I8RNg6s78BhJxMu69NEMHBSJFxKidViTEdruRwEk/WIKqA==",
      "license": "MIT"
    },
    "node_modules/picomatch": {
      "version": "2.3.2",
      "resolved": "https://registry.npmjs.org/picomatch/-/picomatch-2.3.2.tgz",
      "integrity": "sha512-V7+vQEJ06Z+c5tSye8S+nHUfI51xoXIXjHQ99cQtKUkQqqO1kO/KCJUfZXuB47h/YBlDhah2H3hdUGXn8ie0oA==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=8.6"
      },
      "funding": {
        "url": "https://github.com/sponsors/jonschlinkert"
      }
    },
    "node_modules/proxy-addr": {
      "version": "2.0.7",
      "resolved": "https://registry.npmjs.org/proxy-addr/-/proxy-addr-2.0.7.tgz",
      "integrity": "sha512-llQsMLSUDUPT44jdrU/O37qlnifitDP+ZwrmmZcoSKyLKvtZxpyV0n2/bD/N4tBAAZ/gJEdZU7KMraoK1+XYAg==",
      "license": "MIT",
      "dependencies": {
        "forwarded": "0.2.0",
        "ipaddr.js": "1.9.1"
      },
      "engines": {
        "node": ">= 0.10"
      }
    },
    "node_modules/proxy-from-env": {
      "version": "2.1.0",
      "resolved": "https://registry.npmjs.org/proxy-from-env/-/proxy-from-env-2.1.0.tgz",
      "integrity": "sha512-cJ+oHTW1VAEa8cJslgmUZrc+sjRKgAKl3Zyse6+PV38hZe/V6Z14TbCuXcan9F9ghlz4QrFr2c92TNF82UkYHA==",
      "license": "MIT",
      "engines": {
        "node": ">=10"
      }
    },
    "node_modules/pstree.remy": {
      "version": "1.1.8",
      "resolved": "https://registry.npmjs.org/pstree.remy/-/pstree.remy-1.1.8.tgz",
      "integrity": "sha512-77DZwxQmxKnu3aR542U+X8FypNzbfJ+C5XQDk3uWjWxn6151aIMGthWYRXTqT1E5oJvg+ljaa2OJi+VfvCOQ8w==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/qs": {
      "version": "6.15.1",
      "resolved": "https://registry.npmjs.org/qs/-/qs-6.15.1.tgz",
      "integrity": "sha512-6YHEFRL9mfgcAvql/XhwTvf5jKcOiiupt2FiJxHkiX1z4j7WL8J/jRHYLluORvc1XxB5rV20KoeK00gVJamspg==",
      "license": "BSD-3-Clause",
      "dependencies": {
        "side-channel": "^1.1.0"
      },
      "engines": {
        "node": ">=0.6"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/range-parser": {
      "version": "1.2.1",
      "resolved": "https://registry.npmjs.org/range-parser/-/range-parser-1.2.1.tgz",
      "integrity": "sha512-Hrgsx+orqoygnmhFbKaHE6c296J+HTAQXoxEF6gNupROmmGJRoyzfG3ccAveqCBrwr/2yxQ5BVd/GTl5agOwSg==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.6"
      }
    },
    "node_modules/raw-body": {
      "version": "2.5.3",
      "resolved": "https://registry.npmjs.org/raw-body/-/raw-body-2.5.3.tgz",
      "integrity": "sha512-s4VSOf6yN0rvbRZGxs8Om5CWj6seneMwK3oDb4lWDH0UPhWcxwOWw5+qk24bxq87szX1ydrwylIOp2uG1ojUpA==",
      "license": "MIT",
      "dependencies": {
        "bytes": "~3.1.2",
        "http-errors": "~2.0.1",
        "iconv-lite": "~0.4.24",
        "unpipe": "~1.0.0"
      },
      "engines": {
        "node": ">= 0.8"
      }
    },
    "node_modules/readdirp": {
      "version": "3.6.0",
      "resolved": "https://registry.npmjs.org/readdirp/-/readdirp-3.6.0.tgz",
      "integrity": "sha512-hOS089on8RduqdbhvQ5Z37A0ESjsqz6qnRcffsMU3495FuTdqSm+7bhJ29JvIOsBDEEnan5DPu9t3To9VRlMzA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "picomatch": "^2.2.1"
      },
      "engines": {
        "node": ">=8.10.0"
      }
    },
    "node_modules/redis-errors": {
      "version": "1.2.0",
      "resolved": "https://registry.npmjs.org/redis-errors/-/redis-errors-1.2.0.tgz",
      "integrity": "sha512-1qny3OExCf0UvUV/5wpYKf2YwPcOqXzkwKKSmKHiE6ZMQs5heeE/c8eXK+PNllPvmjgAbfnsbpkGZWy8cBpn9w==",
      "license": "MIT",
      "engines": {
        "node": ">=4"
      }
    },
    "node_modules/redis-parser": {
      "version": "3.0.0",
      "resolved": "https://registry.npmjs.org/redis-parser/-/redis-parser-3.0.0.tgz",
      "integrity": "sha512-DJnGAeenTdpMEH6uAJRK/uiyEIH9WVsUmoLwzudwGJUwZPp80PDBWPHXSAGNPwNvIXAbe7MSUB1zQFugFml66A==",
      "license": "MIT",
      "dependencies": {
        "redis-errors": "^1.0.0"
      },
      "engines": {
        "node": ">=4"
      }
    },
    "node_modules/safe-buffer": {
      "version": "5.2.1",
      "resolved": "https://registry.npmjs.org/safe-buffer/-/safe-buffer-5.2.1.tgz",
      "integrity": "sha512-rp3So07KcdmmKbGvgaNxQSJr7bGVSVk5S9Eq1F+ppbRo70+YeaDxkw5Dd8NPN+GD6bjnYm2VuPuCXmpuYvmCXQ==",
      "funding": [
        {
          "type": "github",
          "url": "https://github.com/sponsors/feross"
        },
        {
          "type": "patreon",
          "url": "https://www.patreon.com/feross"
        },
        {
          "type": "consulting",
          "url": "https://feross.org/support"
        }
      ],
      "license": "MIT"
    },
    "node_modules/safer-buffer": {
      "version": "2.1.2",
      "resolved": "https://registry.npmjs.org/safer-buffer/-/safer-buffer-2.1.2.tgz",
      "integrity": "sha512-YZo3K82SD7Riyi0E1EQPojLz7kpepnSQI9IyPbHHg1XXXevb5dJI7tpyN2ADxGcQbHG7vcyRHk0cbwqcQriUtg==",
      "license": "MIT"
    },
    "node_modules/semver": {
      "version": "7.8.0",
      "resolved": "https://registry.npmjs.org/semver/-/semver-7.8.0.tgz",
      "integrity": "sha512-AcM7dV/5ul4EekoQ29Agm5vri8JNqRyj39o0qpX6vDF2GZrtutZl5RwgD1XnZjiTAfncsJhMI48QQH3sN87YNA==",
      "dev": true,
      "license": "ISC",
      "bin": {
        "semver": "bin/semver.js"
      },
      "engines": {
        "node": ">=10"
      }
    },
    "node_modules/send": {
      "version": "0.19.2",
      "resolved": "https://registry.npmjs.org/send/-/send-0.19.2.tgz",
      "integrity": "sha512-VMbMxbDeehAxpOtWJXlcUS5E8iXh6QmN+BkRX1GARS3wRaXEEgzCcB10gTQazO42tpNIya8xIyNx8fll1OFPrg==",
      "license": "MIT",
      "dependencies": {
        "debug": "2.6.9",
        "depd": "2.0.0",
        "destroy": "1.2.0",
        "encodeurl": "~2.0.0",
        "escape-html": "~1.0.3",
        "etag": "~1.8.1",
        "fresh": "~0.5.2",
        "http-errors": "~2.0.1",
        "mime": "1.6.0",
        "ms": "2.1.3",
        "on-finished": "~2.4.1",
        "range-parser": "~1.2.1",
        "statuses": "~2.0.2"
      },
      "engines": {
        "node": ">= 0.8.0"
      }
    },
    "node_modules/send/node_modules/ms": {
      "version": "2.1.3",
      "resolved": "https://registry.npmjs.org/ms/-/ms-2.1.3.tgz",
      "integrity": "sha512-6FlzubTLZG3J2a/NVCAleEhjzq5oxgHyaCU9yYXvcLsvoVaHJq/s5xXI6/XXP6tz7R9xAOtHnSO/tXtF3WRTlA==",
      "license": "MIT"
    },
    "node_modules/serve-static": {
      "version": "1.16.3",
      "resolved": "https://registry.npmjs.org/serve-static/-/serve-static-1.16.3.tgz",
      "integrity": "sha512-x0RTqQel6g5SY7Lg6ZreMmsOzncHFU7nhnRWkKgWuMTu5NN0DR5oruckMqRvacAN9d5w6ARnRBXl9xhDCgfMeA==",
      "license": "MIT",
      "dependencies": {
        "encodeurl": "~2.0.0",
        "escape-html": "~1.0.3",
        "parseurl": "~1.3.3",
        "send": "~0.19.1"
      },
      "engines": {
        "node": ">= 0.8.0"
      }
    },
    "node_modules/setprototypeof": {
      "version": "1.2.0",
      "resolved": "https://registry.npmjs.org/setprototypeof/-/setprototypeof-1.2.0.tgz",
      "integrity": "sha512-E5LDX7Wrp85Kil5bhZv46j8jOeboKq5JMmYM3gVGdGH8xFpPWXUMsNrlODCrkoxMEeNi/XZIwuRvY4XNwYMJpw==",
      "license": "ISC"
    },
    "node_modules/side-channel": {
      "version": "1.1.0",
      "resolved": "https://registry.npmjs.org/side-channel/-/side-channel-1.1.0.tgz",
      "integrity": "sha512-ZX99e6tRweoUXqR+VBrslhda51Nh5MTQwou5tnUDgbtyM0dBgmhEDtWGP/xbKn6hqfPRHujUNwz5fy/wbbhnpw==",
      "license": "MIT",
      "dependencies": {
        "es-errors": "^1.3.0",
        "object-inspect": "^1.13.3",
        "side-channel-list": "^1.0.0",
        "side-channel-map": "^1.0.1",
        "side-channel-weakmap": "^1.0.2"
      },
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/side-channel-list": {
      "version": "1.0.1",
      "resolved": "https://registry.npmjs.org/side-channel-list/-/side-channel-list-1.0.1.tgz",
      "integrity": "sha512-mjn/0bi/oUURjc5Xl7IaWi/OJJJumuoJFQJfDDyO46+hBWsfaVM65TBHq2eoZBhzl9EchxOijpkbRC8SVBQU0w==",
      "license": "MIT",
      "dependencies": {
        "es-errors": "^1.3.0",
        "object-inspect": "^1.13.4"
      },
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/side-channel-map": {
      "version": "1.0.1",
      "resolved": "https://registry.npmjs.org/side-channel-map/-/side-channel-map-1.0.1.tgz",
      "integrity": "sha512-VCjCNfgMsby3tTdo02nbjtM/ewra6jPHmpThenkTYh8pG9ucZ/1P8So4u4FGBek/BjpOVsDCMoLA/iuBKIFXRA==",
      "license": "MIT",
      "dependencies": {
        "call-bound": "^1.0.2",
        "es-errors": "^1.3.0",
        "get-intrinsic": "^1.2.5",
        "object-inspect": "^1.13.3"
      },
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/side-channel-weakmap": {
      "version": "1.0.2",
      "resolved": "https://registry.npmjs.org/side-channel-weakmap/-/side-channel-weakmap-1.0.2.tgz",
      "integrity": "sha512-WPS/HvHQTYnHisLo9McqBHOJk2FkHO/tlpvldyrnem4aeQp4hai3gythswg6p01oSoTl58rcpiFAjF2br2Ak2A==",
      "license": "MIT",
      "dependencies": {
        "call-bound": "^1.0.2",
        "es-errors": "^1.3.0",
        "get-intrinsic": "^1.2.5",
        "object-inspect": "^1.13.3",
        "side-channel-map": "^1.0.1"
      },
      "engines": {
        "node": ">= 0.4"
      },
      "funding": {
        "url": "https://github.com/sponsors/ljharb"
      }
    },
    "node_modules/simple-update-notifier": {
      "version": "2.0.0",
      "resolved": "https://registry.npmjs.org/simple-update-notifier/-/simple-update-notifier-2.0.0.tgz",
      "integrity": "sha512-a2B9Y0KlNXl9u/vsW6sTIu9vGEpfKu2wRV6l1H3XEas/0gUIzGzBoP/IouTcUQbm9JWZLH3COxyn03TYlFax6w==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "semver": "^7.5.3"
      },
      "engines": {
        "node": ">=10"
      }
    },
    "node_modules/standard-as-callback": {
      "version": "2.1.0",
      "resolved": "https://registry.npmjs.org/standard-as-callback/-/standard-as-callback-2.1.0.tgz",
      "integrity": "sha512-qoRRSyROncaz1z0mvYqIE4lCd9p2R90i6GxW3uZv5ucSu8tU7B5HXUP1gG8pVZsYNVaXjk8ClXHPttLyxAL48A==",
      "license": "MIT"
    },
    "node_modules/statuses": {
      "version": "2.0.2",
      "resolved": "https://registry.npmjs.org/statuses/-/statuses-2.0.2.tgz",
      "integrity": "sha512-DvEy55V3DB7uknRo+4iOGT5fP1slR8wQohVdknigZPMpMstaKJQWhwiYBACJE3Ul2pTnATihhBYnRhZQHGBiRw==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.8"
      }
    },
    "node_modules/supports-color": {
      "version": "7.2.0",
      "resolved": "https://registry.npmjs.org/supports-color/-/supports-color-7.2.0.tgz",
      "integrity": "sha512-qpCAvRl9stuOHveKsn7HncJRvv501qIacKzQlO/+Lwxc9+0q2wLyv4Dfvt80/DPn2pqOBsJdDiogXGR9+OvwRw==",
      "license": "MIT",
      "dependencies": {
        "has-flag": "^4.0.0"
      },
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/to-regex-range": {
      "version": "5.0.1",
      "resolved": "https://registry.npmjs.org/to-regex-range/-/to-regex-range-5.0.1.tgz",
      "integrity": "sha512-65P7iz6X5yEr1cwcgvQxbbIw7Uk3gOy5dIdtZ4rDveLqhrdJP+Li/Hx6tyK0NEb+2GCyneCMJiGqrADCSNk8sQ==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "is-number": "^7.0.0"
      },
      "engines": {
        "node": ">=8.0"
      }
    },
    "node_modules/toidentifier": {
      "version": "1.0.1",
      "resolved": "https://registry.npmjs.org/toidentifier/-/toidentifier-1.0.1.tgz",
      "integrity": "sha512-o5sSPKEkg/DIQNmH43V0/uerLrpzVedkUh8tGNvaeXpfpuwjKenlSox/2O/BTlZUtEe+JG7s5YhEz608PlAHRA==",
      "license": "MIT",
      "engines": {
        "node": ">=0.6"
      }
    },
    "node_modules/touch": {
      "version": "3.1.1",
      "resolved": "https://registry.npmjs.org/touch/-/touch-3.1.1.tgz",
      "integrity": "sha512-r0eojU4bI8MnHr8c5bNo7lJDdI2qXlWWJk6a9EAFG7vbhTjElYhBVS3/miuE0uOuoLdb8Mc/rVfsmm6eo5o9GA==",
      "dev": true,
      "license": "ISC",
      "bin": {
        "nodetouch": "bin/nodetouch.js"
      }
    },
    "node_modules/type-is": {
      "version": "1.6.18",
      "resolved": "https://registry.npmjs.org/type-is/-/type-is-1.6.18.tgz",
      "integrity": "sha512-TkRKr9sUTxEH8MdfuCSP7VizJyzRNMjj2J2do2Jr3Kym598JVdEksuzPQCnlFPW4ky9Q+iA+ma9BGm06XQBy8g==",
      "license": "MIT",
      "dependencies": {
        "media-typer": "0.3.0",
        "mime-types": "~2.1.24"
      },
      "engines": {
        "node": ">= 0.6"
      }
    },
    "node_modules/undefsafe": {
      "version": "2.0.5",
      "resolved": "https://registry.npmjs.org/undefsafe/-/undefsafe-2.0.5.tgz",
      "integrity": "sha512-WxONCrssBM8TSPRqN5EmsjVrsv4A8X12J4ArBiiayv3DyyG3ZlIg6yysuuSYdZsVz3TKcTg2fd//Ujd4CHV1iA==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/unpipe": {
      "version": "1.0.0",
      "resolved": "https://registry.npmjs.org/unpipe/-/unpipe-1.0.0.tgz",
      "integrity": "sha512-pjy2bYhSsufwWlKwPc+l3cN7+wuJlK6uz0YdJEOlQDbl6jo/YlPi4mb8agUkVC8BF7V8NuzeyPNqRksA3hztKQ==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.8"
      }
    },
    "node_modules/utils-merge": {
      "version": "1.0.1",
      "resolved": "https://registry.npmjs.org/utils-merge/-/utils-merge-1.0.1.tgz",
      "integrity": "sha512-pMZTvIkT1d+TFGvDOqodOclx0QWkkgi6Tdoa8gC8ffGAAqz9pzPTZWAybbsHHoED/ztMtkv/VoYTYyShUn81hA==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.4.0"
      }
    },
    "node_modules/uuid": {
      "version": "9.0.1",
      "resolved": "https://registry.npmjs.org/uuid/-/uuid-9.0.1.tgz",
      "integrity": "sha512-b+1eJOlsR9K8HJpow9Ok3fiWOWSIcIzXodvv0rQjVoOVNpWMpxf1wZNpt4y9h10odCNrqnYp1OBzRktckBe3sA==",
      "deprecated": "uuid@10 and below is no longer supported.  For ESM codebases, update to uuid@latest.  For CommonJS codebases, use uuid@11 (but be aware this version will likely be deprecated in 2028).",
      "funding": [
        "https://github.com/sponsors/broofa",
        "https://github.com/sponsors/ctavan"
      ],
      "license": "MIT",
      "bin": {
        "uuid": "dist/bin/uuid"
      }
    },
    "node_modules/vary": {
      "version": "1.1.2",
      "resolved": "https://registry.npmjs.org/vary/-/vary-1.1.2.tgz",
      "integrity": "sha512-BNGbWLfd0eUPabhkXUVm0j8uuvREyTh5ovRa/dyow/BqAbZJyC+5fU+IzQOzmAKzYqYRAISoRhdQr3eIZ/PXqg==",
      "license": "MIT",
      "engines": {
        "node": ">= 0.8"
      }
    }
  }
}
SVEOF_package_lock_json

mkdir -p "$INSTALL_DIR/."
cat > "$INSTALL_DIR/package.json" <<'SVEOF_package_json'
{
  "name": "streamvault",
  "version": "1.0.0",
  "description": "Self-hosted TorBox Stremio addon",
  "main": "src/server.js",
  "scripts": {
    "start": "node src/server.js",
    "dev": "nodemon src/server.js",
    "setup": "node scripts/setup.js"
  },
  "dependencies": {
    "axios": "^1.6.0",
    "chalk": "^4.1.2",
    "cors": "^2.8.5",
    "dotenv": "^16.3.1",
    "express": "^4.18.2",
    "express-rate-limit": "^7.1.5",
    "form-data": "^4.0.5",
    "ioredis": "^5.10.1",
    "morgan": "^1.10.0",
    "node-cache": "^5.1.2",
    "uuid": "^9.0.0"
  },
  "devDependencies": {
    "nodemon": "^3.0.1"
  }
}
SVEOF_package_json

mkdir -p "$INSTALL_DIR/scripts"
cat > "$INSTALL_DIR/scripts/setup.js" <<'SVEOF_scripts_setup_js'
#!/usr/bin/env node
// scripts/setup.js — interactive first-run setup

const fs   = require('fs');
const path = require('path');
const readline = require('readline');

const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
const ask = (q) => new Promise(res => rl.question(q, res));

const ENV_PATH = path.join(__dirname, '../.env');

async function main() {
  console.log('\n╔══════════════════════════════════════════╗');
  console.log('║   StreamVault — First Run Setup          ║');
  console.log('╚══════════════════════════════════════════╝\n');

  if (fs.existsSync(ENV_PATH)) {
    const overwrite = await ask('.env already exists. Overwrite? (y/N): ');
    if (overwrite.toLowerCase() !== 'y') { console.log('Skipped.'); rl.close(); return; }
  }

  const torboxKey    = await ask('TorBox API key: ');
  const nasIp        = await ask('NAS local IP (e.g. 192.168.1.10): ');
  const tailscale    = await ask('Tailscale hostname (leave blank to skip): ');
  const adminPass    = await ask('Admin dashboard password: ');
  const port         = await ask('Port [7000]: ') || '7000';
  const secretKey    = Math.random().toString(36).slice(2) + Math.random().toString(36).slice(2);

  const env = `# Auto-generated by setup.js
PORT=${port}
HOST=0.0.0.0
NODE_ENV=production

TORBOX_API_KEY=${torboxKey}
TORBOX_API_URL=https://api.torbox.app/v1/api

SECRET_KEY=${secretKey}

STREAM_CACHE_TTL=300
META_CACHE_TTL=3600

ADMIN_PASSWORD=${adminPass}

NAS_LOCAL_IP=${nasIp}
TAILSCALE_HOST=${tailscale}
`;

  fs.writeFileSync(ENV_PATH, env);
  fs.mkdirSync(path.join(__dirname, '../data'), { recursive: true });

  console.log('\n✅ .env written.');
  console.log(`\n  npm start\n`);
  console.log(`  Then open: http://${nasIp}:${port}/\n`);

  rl.close();
}

main().catch(err => { console.error(err); rl.close(); });
SVEOF_scripts_setup_js

mkdir -p "$INSTALL_DIR/src/addon"
cat > "$INSTALL_DIR/src/addon/manifest.js" <<'SVEOF_src_addon_manifest_js'
// src/addon/manifest.js — builds the Stremio manifest for a given profile

const { PORT, NAS_LOCAL_IP, TAILSCALE_HOST, PUBLIC_BASE_URL } = require('../config/env');

function buildManifest(profile) {
  const { configId, name, prefs } = profile;

  const qualityNote = [
    prefs.minQuality || '1080p',
    prefs.cachedOnly ? 'Cached Only' : 'All',
    prefs.scoring?.hevc > 0 ? 'HEVC Pref' : '',
    prefs.scoring?.dolbyVision > 0 ? 'DV Pref' : '',
  ].filter(Boolean).join(' · ');

  return {
    id:          `community.streamvault.${configId}`, 
    version:     '1.0.0',
    name:        `⚡ ${name}`,
    description: `StreamVault — ${qualityNote}`, 
    logo:        '',

    // Resources this addon provides
    resources:   ['stream'],
    catalogs:    [],

    // Content types
    types:       ['movie', 'series'],

    // Stremio uses IMDb IDs
    idPrefixes:  ['tt'],

    // Behaviour hints
    behaviorHints: {
      adult:           false,
      p2p:             false,
      configurable:    false,
      configurationRequired: false,
    },

    // Optional: where the user can manage this config
    // (points to your NAS dashboard)
    contactEmail: '',

    // Useful for debugging
    _meta: {
      configId,
      profile: name,
      generatedAt: new Date().toISOString(),
      endpoints: {
        base:      PUBLIC_BASE_URL || (NAS_LOCAL_IP ? `http://${NAS_LOCAL_IP}:${PORT}` : null),
        lan:       NAS_LOCAL_IP ? `http://${NAS_LOCAL_IP}:${PORT}` : null,
        tailscale: TAILSCALE_HOST ? `http://${TAILSCALE_HOST}:${PORT}` : null,
      },
    },
  };
}

module.exports = { buildManifest };
SVEOF_src_addon_manifest_js

mkdir -p "$INSTALL_DIR/src/addon"
cat > "$INSTALL_DIR/src/addon/router.js" <<'SVEOF_src_addon_router_js'
// src/addon/router.js — Stremio-compatible addon endpoints

const express  = require('express');
const router   = express.Router();
const { getProfile } = require('../profiles/store');
const { buildManifest } = require('./manifest');
const { handleStream } = require('./streams');

// Every route is prefixed with /config/:configId (mounted in server.js as /config)

// ── Middleware: resolve profile ────────────────────────────────
router.use('/:configId/*', (req, res, next) => {
  const profile = getProfile(req.params.configId);
  if (!profile) return res.status(404).json({ error: 'Unknown config ID' });
  req.profile = profile;
  next();
});

// ── Manifest ───────────────────────────────────────────────────
// GET /config/:configId/manifest.json
router.get('/:configId/manifest.json', (req, res) => {
  res.setHeader('Content-Type', 'application/json');
  res.json(buildManifest(req.profile));
});

// ── Streams ────────────────────────────────────────────────────
// GET /config/:configId/stream/:type/:id.json
// type = "movie" | "series"
// id   = "tt1234567" (movie) | "tt1234567:1:2" (series s1e2)
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
SVEOF_src_addon_router_js

mkdir -p "$INSTALL_DIR/src/addon"
cat > "$INSTALL_DIR/src/addon/streams.js" <<'SVEOF_src_addon_streams_js'
// src/addon/streams.js — main stream handler pipeline
const torbox = require('../api/torbox');
const { filterResults, detectResolution } = require('../filters/quality');
const { rankResults } = require('../scoring/rank');
const cache = require('../cache/store');
const { PORT, NAS_LOCAL_IP, PUBLIC_BASE_URL, CF_ENABLED, CF_DOMAIN, CF_SUBDOMAIN, TAILSCALE_HOST } = require('../config/env');

function parseId(type, id) {
  if (type === 'series') {
    const [imdbId, season, episode] = id.split(':');
    return { imdbId, season: parseInt(season), episode: parseInt(episode) };
  }
  return { imdbId: id };
}

function baseUrl() {
  if (PUBLIC_BASE_URL) return PUBLIC_BASE_URL.replace(/\/$/, '');
  if (CF_ENABLED && CF_DOMAIN) return `https://${CF_SUBDOMAIN}.${CF_DOMAIN}`;
  if (TAILSCALE_HOST) return `http://${TAILSCALE_HOST}:${PORT}`;
  if (NAS_LOCAL_IP) return `http://${NAS_LOCAL_IP}:${PORT}`;
  return `http://localhost:${PORT}`;
}

function formatStream(torrent, profile, directUrl) {
  const name = torrent.name || torrent.raw_title || torrent.title || 'Unknown';
  const res = detectResolution(name) || '?';
  const score = torrent._score || 0;
  const feats = torrent._features || {};
  const tags = [];
  if (feats.remux) tags.push('REMUX');
  if (feats.bluray) tags.push('BluRay');
  if (feats.webdl) tags.push('WEB-DL');
  if (feats.webrip) tags.push('WEBRip');
  if (feats.hevc) tags.push('HEVC');
  if (feats.dolbyVision) tags.push('DV');
  else if (feats.hdrPlus) tags.push('HDR10+');
  else if (feats.hdr) tags.push('HDR');
  if (feats.atmos) tags.push('Atmos');
  else if (feats.trueHD) tags.push('TrueHD');
  const sizeGB = torrent.size ? `${(torrent.size / 1e9).toFixed(1)} GB` : '';
  const hash = String(torrent.hash || '').toLowerCase();
  return {
    name: `⚡ ${res} ${tags.join(' ')}`.trim(),
    description: `${name}\n${sizeGB ? `💾 ${sizeGB}` : ''}  ★ ${score}${torrent.cached ? '  ✅ Cached' : ''}`.trim(),
    url: directUrl || `${baseUrl()}/proxy/stream/${hash}/0`,
    behaviorHints: { notWebReady: false, bingeGroup: `torbox-${profile.configId}` },
  };
}

async function handleStream(type, rawId, profile) {
  const { imdbId, season, episode } = parseId(type, rawId);
  const prefs = profile.prefs || {};
  const cacheKey = cache.cacheKey('stream', profile.configId, rawId);
  const cached = await cache.getStreams(cacheKey);
  if (cached) {
    console.log(`[Stream] Cache HIT — ${cacheKey}`);
    return cached;
  }

  console.log(`[Stream] Searching TorBox for ${imdbId} (${type})`);
  const raw = await torbox.searchStreams(imdbId, type, { season, episode });
  if (!raw.length) return [];

  const top = raw.slice(0, 150);
  const filtered = filterResults(top, prefs);
  console.log(`[Stream] ${raw.length} raw → ${filtered.length} after filter`);
  if (!filtered.length) return [];

  const ranked = rankResults(filtered, prefs);
  const topStreams = ranked.slice(0, 10);

  // Pre-resolve only the best few direct URLs. If TorBox needs longer to import,
  // Stremio still receives the local proxy URL, which resolves on playback.
  const urlCache = {};
  const toResolve = topStreams.slice(0, 4).filter(t => t.cached);
  const resolvePromise = Promise.all(toResolve.map(async t => {
    try {
      const url = await torbox.getStreamUrlByHash(t.hash, 0);
      if (url) urlCache[String(t.hash).toLowerCase()] = url;
    } catch (_) {}
  }));
  await Promise.race([resolvePromise, new Promise(r => setTimeout(r, 4000))]);

  const streams = topStreams.map(t => formatStream(t, profile, urlCache[String(t.hash).toLowerCase()]));
  await cache.setStreams(cacheKey, streams);
  return streams;
}

module.exports = { handleStream };
SVEOF_src_addon_streams_js

mkdir -p "$INSTALL_DIR/src/api"
cat > "$INSTALL_DIR/src/api/player.js" <<'SVEOF_src_api_player_js'
// src/api/player.js — Web player API routes
// GET /api/player/search?q=inception&type=movie
// GET /api/player/streams/:type/:imdbId[/:season/:episode]
// GET /api/player/play/:torrentId/:fileId  → 302 to TorBox CDN

const express = require('express');
const axios   = require('axios');
const router  = express.Router();

const torbox          = require('./torbox');
const { filterResults } = require('../filters/quality');
const { rankResults }   = require('../scoring/rank');
const { detectResolution } = require('../filters/quality');
const { TORBOX_API_KEY, ADMIN_PASSWORD } = require('../config/env');

// Default permissive prefs for the web player (no cachedOnly restriction)
const PLAYER_PREFS = {
  minQuality:  '1080p',
  cachedOnly:  false,   // show all, mark cached ones
  blockedTags: ['CAM','TS','HDCAM','SCR','DVDSCR','TELECINE','TELESYNC','HC','R5'],
  scoring: {
    resolution4K: 12, dolbyVision: 10, hevc: 10, hdrPlus: 9,
    remux: 9, hdr: 8, bluray: 7, atmos: 6, webdl: 6,
    trueHD: 5, webrip: 3, dts: 3, h264: 1,
  },
};

// ── Auth (same simple token) ────────────────────────────────
function auth(req, res, next) {
  const token = req.headers['x-admin-token'] || req.query.token;
  if (token !== ADMIN_PASSWORD) return res.status(401).json({ error: 'Unauthorised' });
  next();
}

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

    // Only show cached streams — uncached can't play
    const filtered = filterResults(raw, { ...PLAYER_PREFS, cachedOnly: true });
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
        hash:     t.hash,
        fileId:   t.file_id || 0,
        name:     name,
        title:    `${res}${tags.length ? ' · ' + tags.join(' ') : ''}`,
        size:     t.size ? `${(t.size / 1e9).toFixed(1)} GB` : '?',
        score:    t._score || 0,
        cached:   t.cached || false,
        resolution: res,
        features: feats,
        playUrl:  `/api/player/play/${t.id}/${t.file_id || 0}`,
      };
    });

    res.json(streams);
  } catch (err) {
    console.error('[Player] streams error:', err.message);
    res.json([]);
  }
});

// ── Play redirect ───────────────────────────────────────────
// Resolves torrent ID → TorBox CDN URL and redirects
router.get('/play/:torrentId/:fileId', auth, async (req, res) => {
  const { torrentId, fileId } = req.params;
  const axios = require('axios');
  const headers = { Authorization: `Bearer ${TORBOX_API_KEY}` };

  try {
    // 1. Check mylist first
    let numericId = null;
    try {
      const listRes = await axios.get('https://api.torbox.app/v1/api/torrents/mylist', { headers, timeout: 12000 });
      const found = (listRes.data?.data || []).find(t => t.hash?.toLowerCase() === torrentId.toLowerCase());
      if (found) numericId = found.id;
    } catch(e) { console.warn('[Player] mylist error:', e.message); }

    // 2. Not in mylist — add via hash (instant for cached torrents on TorBox Pro)
    if (!numericId) {
      console.log(`[Player] Adding ${torrentId} to mylist...`);
      try {
        const addRes = await axios.post(
          'https://api.torbox.app/v1/api/torrents/addmagnet',
          { magnet: `magnet:?xt=urn:btih:${torrentId}`, seed: 1, allow_zip: false },
          { headers: { ...headers, 'Content-Type': 'application/json' }, timeout: 12000 }
        );
        numericId = addRes.data?.data?.torrent_id || addRes.data?.data?.id;
        console.log(`[Player] Added torrent, ID: ${numericId}`);
        // Small wait for TorBox to register it
        if (numericId) await new Promise(r => setTimeout(r, 1500));
      } catch(e) { console.error('[Player] addmagnet error:', e.message); }
    }

    if (!numericId) return res.status(503).json({ error: 'Could not add torrent to TorBox' });

    // 3. Request download link
    const url = await torbox.getStreamUrl(numericId, parseInt(fileId));
    if (!url) return res.status(404).json({ error: 'Stream URL not available — may still be processing' });

    res.redirect(302, url);
  } catch (err) {
    console.error('[Player] play error:', err.message);
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
SVEOF_src_api_player_js

mkdir -p "$INSTALL_DIR/src/api"
cat > "$INSTALL_DIR/src/api/router.js" <<'SVEOF_src_api_router_js'
// src/api/router.js — internal REST API for the dashboard

const express     = require('express');
const rateLimit   = require('express-rate-limit');
const router      = express.Router();
const profileStore = require('../profiles/store');
const cache        = require('../cache/store');
const { ADMIN_PASSWORD, PORT, NAS_LOCAL_IP, TAILSCALE_HOST, PUBLIC_BASE_URL, CF_ENABLED, CF_DOMAIN, CF_SUBDOMAIN } = require('../config/env');

// ── Simple admin auth middleware ───────────────────────────────
function adminAuth(req, res, next) {
  const token = req.headers['x-admin-token'] || req.query.token;
  if (token !== ADMIN_PASSWORD) return res.status(401).json({ error: 'Unauthorised' });
  next();
}

// ── Rate limiter on profile creation ─────────────────────────
const createLimiter = rateLimit({ windowMs: 60_000, max: 10 });

// ─────────────────────────────────────────────────────────────
//  Profile management
// ─────────────────────────────────────────────────────────────

// GET /api/profiles — list all profiles
router.get('/profiles', adminAuth, (req, res) => {
  res.json(profileStore.listProfiles());
});

// POST /api/profiles — create a new profile
router.post('/profiles', adminAuth, createLimiter, (req, res) => {
  const { name = 'New Profile', prefs = {} } = req.body;
  const configId = profileStore.createProfile(name, prefs);
  const profile  = profileStore.getProfile(configId);

  const manifestBase = buildManifestBase(configId);

  res.json({
    ...profile,
    manifestUrls: manifestBase,
  });
});

// GET /api/profiles/:configId — get one profile
router.get('/profiles/:configId', adminAuth, (req, res) => {
  const p = profileStore.getProfile(req.params.configId);
  if (!p) return res.status(404).json({ error: 'Not found' });
  res.json({ ...p, manifestUrls: buildManifestBase(req.params.configId) });
});

// PATCH /api/profiles/:configId — update preferences
router.patch('/profiles/:configId', adminAuth, (req, res) => {
  const updated = profileStore.updateProfile(req.params.configId, req.body);
  if (!updated) return res.status(404).json({ error: 'Not found' });
  res.json(updated);
});

// DELETE /api/profiles/:configId
router.delete('/profiles/:configId', adminAuth, (req, res) => {
  const ok = profileStore.deleteProfile(req.params.configId);
  if (!ok) return res.status(404).json({ error: 'Not found' });
  res.json({ deleted: true });
});

// ─────────────────────────────────────────────────────────────
//  Cache stats
// ─────────────────────────────────────────────────────────────

router.get('/cache/stats', adminAuth, (req, res) => {
  res.json(cache.stats());
});

// ─────────────────────────────────────────────────────────────
//  Health / info
// ─────────────────────────────────────────────────────────────

router.get('/info', (req, res) => {
  res.json({
    status: 'ok',
    nasIp: NAS_LOCAL_IP,
    tailscale: TAILSCALE_HOST,
    publicBaseUrl: PUBLIC_BASE_URL,
    cloudflare: CF_ENABLED && CF_DOMAIN ? `${CF_SUBDOMAIN}.${CF_DOMAIN}` : null,
    port: PORT,
  });
});

// ─────────────────────────────────────────────────────────────
//  Helpers
// ─────────────────────────────────────────────────────────────

function buildManifestBase(configId) {
  const path = `/config/${configId}/manifest.json`;
  return {
    lan:       NAS_LOCAL_IP  ? `http://${NAS_LOCAL_IP}:${PORT}${path}`  : null,
    tailscale: TAILSCALE_HOST ? `http://${TAILSCALE_HOST}:${PORT}${path}` : null,
    public: PUBLIC_BASE_URL ? `${PUBLIC_BASE_URL.replace(/\/$/, '')}${path}` : (CF_ENABLED && CF_DOMAIN ? `https://${CF_SUBDOMAIN}.${CF_DOMAIN}${path}` : null),
    localhost: `http://localhost:${PORT}${path}`,
  };
}

module.exports = router;
SVEOF_src_api_router_js

mkdir -p "$INSTALL_DIR/src/api"
cat > "$INSTALL_DIR/src/api/torbox.js" <<'SVEOF_src_api_torbox_js'
const axios = require('axios');
const FormData = require('form-data');
const { TORBOX_API_KEY, TORBOX_API_URL } = require('../config/env');
const cache = require('../cache/store');

const client = axios.create({
  baseURL: TORBOX_API_URL,
  headers: { Authorization: 'Bearer ' + TORBOX_API_KEY, 'Content-Type': 'application/json' },
  timeout: 20000,
});

const searchClient = axios.create({
  baseURL: 'https://search-api.torbox.app',
  headers: { Authorization: 'Bearer ' + TORBOX_API_KEY },
  timeout: 20000,
});

const torrentIdCache = {};
const myListCache = { data: null, ts: 0, loading: false };

function normaliseHash(h) { return String(h || '').toLowerCase(); }
function isVideoFile(f) { return /\.(mkv|mp4|avi|mov|m4v|webm)$/i.test(f?.name || f?.short_name || ''); }
function pickVideoFile(files = [], requestedFileId = 0) {
  if (!Array.isArray(files) || !files.length) return { id: requestedFileId || 0 };
  const exact = files.find(f => Number(f.id) === Number(requestedFileId) && isVideoFile(f));
  if (exact) return exact;
  const videos = files.filter(isVideoFile).sort((a,b)=>(b.size||0)-(a.size||0));
  return videos[0] || files.sort((a,b)=>(b.size||0)-(a.size||0))[0] || { id: requestedFileId || 0 };
}

async function searchStreams(imdbId, type, opts = {}) {
  try {
    let url = '/torrents/imdb:' + imdbId;
    if (type === 'series' && opts.season) url += '?season=' + opts.season + '&episode=' + (opts.episode || 1);
    const res = await searchClient.get(url);
    const results = res.data?.data?.torrents || res.data?.torrents || [];
    console.log('[TorBox] Found ' + results.length + ' torrents');

    const hashes = results.map(r => r.hash).filter(Boolean);
    let cached = {};
    for (let i = 0; i < hashes.length; i += 50) {
      const part = await checkCached(hashes.slice(i, i + 50));
      Object.assign(cached, part);
    }

    return results.map(r => {
      const hash = normaliseHash(r.hash);
      return {
        ...r,
        name: r.raw_title || r.title || r.name || hash,
        seeds: r.last_known_seeders || r.seeds || 0,
        cached: !!(cached[hash] || cached[r.hash] || r.cached),
      };
    });
  } catch (err) {
    console.error('[TorBox] searchStreams error:', err.response?.status || '', err.message);
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
    console.error('[TorBox] getStreamUrl error:', err.response?.status || '', err.message);
    return null;
  }
}

async function checkCached(hashes = []) {
  if (!hashes.length) return {};
  try {
    const res = await client.get('/torrents/checkcached', {
      params: { hash: hashes.join(','), format: 'object', list_files: false },
    });
    return res.data?.data || {};
  } catch (err) {
    console.error('[TorBox] checkCached error:', err.response?.status || '', err.message);
    return {};
  }
}

async function getMyList(force = false) {
  if (!force && myListCache.data && Date.now() - myListCache.ts < 300000) return myListCache.data;
  if (myListCache.loading) return myListCache.data || [];
  myListCache.loading = true;
  try {
    const res = await client.get('/torrents/mylist', { params: { bypass_cache: true } });
    myListCache.data = res.data?.data || [];
    myListCache.ts = Date.now();
    for (const t of myListCache.data) {
      if (t.hash && t.id) torrentIdCache[normaliseHash(t.hash)] = t.id;
    }
  } catch (err) {
    console.error('[TorBox] getMyList error:', err.response?.status || '', err.message);
    myListCache.data = myListCache.data || [];
  } finally {
    myListCache.loading = false;
  }
  return myListCache.data;
}

setTimeout(async () => {
  try {
    const list = await getMyList(true);
    console.log('[TorBox] Pre-warmed ' + list.length + ' torrents');
  } catch (err) {
    console.error('[TorBox] Pre-warm error:', err.message);
  }
}, 2500);

async function addHashToTorBox(hash) {
  // Try the newer JSON endpoint first, then fall back to form endpoint.
  try {
    const r = await client.post('/torrents/addmagnet', {
      magnet: 'magnet:?xt=urn:btih:' + hash,
      seed: 1,
      allow_zip: false,
    });
    return r.data?.data?.torrent_id || r.data?.data?.id || null;
  } catch (_) {}

  try {
    const form = new FormData();
    form.append('magnet', 'magnet:?xt=urn:btih:' + hash);
    form.append('seed', '1');
    form.append('allow_zip', 'false');
    const r = await client.post('/torrents/createtorrent', form, { headers: form.getHeaders() });
    return r.data?.data?.torrent_id || r.data?.data?.id || null;
  } catch (err) {
    console.error('[TorBox] addHashToTorBox error:', err.response?.status || '', err.message);
    return null;
  }
}

async function getStreamUrlByHash(hash, fileId = 0) {
  hash = normaliseHash(hash);
  if (!hash) return null;

  try {
    if (cache.redis) {
      const cachedUrl = await cache.redis.get('url:' + hash + ':' + fileId).catch(() => null);
      if (cachedUrl) return cachedUrl;
    }

    let list = await getMyList(false);
    let existing = list.find(t => normaliseHash(t.hash) === hash);

    if (!existing) {
      const torrentId = await addHashToTorBox(hash);
      if (!torrentId) return null;
      torrentIdCache[hash] = torrentId;
      await new Promise(r => setTimeout(r, 1500));
      list = await getMyList(true);
      existing = list.find(t => normaliseHash(t.hash) === hash) || { id: torrentId, files: [] };
    }

    const video = pickVideoFile(existing.files, fileId);
    const url = await getStreamUrl(existing.id, video.id || fileId || 0);
    if (url && cache.redis) await cache.redis.setex('url:' + hash + ':' + (video.id || fileId || 0), 600, url).catch(() => null);
    return url;
  } catch (err) {
    console.error('[TorBox] getStreamUrlByHash error:', err.response?.status || '', err.message);
    return null;
  }
}

module.exports = { searchStreams, getStreamUrl, getStreamUrlByHash, checkCached, getMyList };
SVEOF_src_api_torbox_js

mkdir -p "$INSTALL_DIR/src/cache"
cat > "$INSTALL_DIR/src/cache/store.js" <<'SVEOF_src_cache_store_js'
const NodeCache = require('node-cache');
const Redis = require('ioredis');
const { STREAM_CACHE_TTL, META_CACHE_TTL } = require('../config/env');

const streamCache = new NodeCache({ stdTTL: STREAM_CACHE_TTL, checkperiod: 60 });
const metaCache = new NodeCache({ stdTTL: META_CACHE_TTL, checkperiod: 120 });

let redis;
try {
  redis = new Redis({ host: '127.0.0.1', port: 6379, lazyConnect: true, connectTimeout: 2000 });
  redis.connect().then(() => console.log('[Redis] Connected')).catch(e => { console.warn('[Redis] Not available, using memory cache'); redis = null; });
} catch(e) { redis = null; }

function cacheKey(...parts) { return parts.join(':'); }

async function getStreams(key) {
  if (redis) { try { const v = await redis.get('stream:' + key); if (v) return JSON.parse(v); } catch(e) {} }
  return streamCache.get(key) || null;
}

async function setStreams(key, value) {
  if (redis) { try { await redis.setex('stream:' + key, STREAM_CACHE_TTL, JSON.stringify(value)); } catch(e) {} }
  streamCache.set(key, value);
}

function getMeta(key) { return metaCache.get(key) || null; }
function setMeta(key, value) { metaCache.set(key, value); }

function stats() { return { streams: streamCache.getStats(), meta: metaCache.getStats(), redis: redis ? 'connected' : 'disconnected' }; }

module.exports = { cacheKey, getStreams, setStreams, getMeta, setMeta, stats, redis };
SVEOF_src_cache_store_js

mkdir -p "$INSTALL_DIR/src/config"
cat > "$INSTALL_DIR/src/config/defaults.js" <<'SVEOF_src_config_defaults_js'
// src/config/defaults.js — default preferences for new user configs

const bool = (v, fallback) => {
  if (v === undefined || v === '') return fallback;
  return String(v).toLowerCase() !== 'false' && String(v).toLowerCase() !== '0' && String(v).toLowerCase() !== 'no';
};

module.exports = {
  minQuality: process.env.DEFAULT_MIN_QUALITY || '1080p',
  cachedOnly: bool(process.env.DEFAULT_CACHED_ONLY, true),
  maxSizeGB: parseInt(process.env.DEFAULT_MAX_SIZE_GB || '80', 10),
  language: process.env.DEFAULT_LANGUAGE || 'en',
  blockedTags: ['CAM', 'TS', 'HDCAM', 'SCR', 'DVDSCR', 'TELECINE', 'TELESYNC', 'HC', 'R5'],
  scoring: {
    hevc:        bool(process.env.DEFAULT_PREFER_HEVC, true) ? 10 : 0,
    hdr:         bool(process.env.DEFAULT_PREFER_HDR, true) ? 8 : 0,
    dolbyVision: bool(process.env.DEFAULT_PREFER_HDR, true) ? 10 : 0,
    atmos:       bool(process.env.DEFAULT_PREFER_ATMOS, true) ? 6 : 0,
    trueHD:      bool(process.env.DEFAULT_PREFER_ATMOS, true) ? 5 : 0,
    bluray:      7,
    remux:       9,
    webdl:       6,
    webrip:      3,
    hdrPlus:     bool(process.env.DEFAULT_PREFER_HDR, true) ? 9 : 0,
    dts:         3,
    h264:        1,
    resolution4K:12,
  },
  resolutionRank: { '2160p': 5, '4k': 5, '1440p': 4, '1080p': 3, '720p': 2, '480p': 1, '360p': 0 },
};
SVEOF_src_config_defaults_js

mkdir -p "$INSTALL_DIR/src/config"
cat > "$INSTALL_DIR/src/config/env.js" <<'SVEOF_src_config_env_js'
// src/config/env.js — central environment config
module.exports = {
  PORT:              process.env.PORT              || 7000,
  HOST:              process.env.HOST              || '0.0.0.0',
  NODE_ENV:          process.env.NODE_ENV          || 'development',
  TORBOX_API_KEY:    process.env.TORBOX_API_KEY    || '',
  TORBOX_API_URL:    process.env.TORBOX_API_URL    || 'https://api.torbox.app/v1/api',
  SECRET_KEY:        process.env.SECRET_KEY        || 'change-me',
  STREAM_CACHE_TTL:  parseInt(process.env.STREAM_CACHE_TTL)  || 300,
  META_CACHE_TTL:    parseInt(process.env.META_CACHE_TTL)    || 3600,
  ADMIN_PASSWORD:    process.env.ADMIN_PASSWORD    || 'changeme',
  NAS_LOCAL_IP:      process.env.NAS_LOCAL_IP      || '',
  TAILSCALE_HOST:    process.env.TAILSCALE_HOST    || process.env.TS_HOSTNAME || '',
  TS_ENABLED:        process.env.TS_ENABLED        === 'true',
  CF_ENABLED:        process.env.CF_ENABLED        === 'true',
  CF_DOMAIN:         process.env.CF_DOMAIN         || '',
  CF_SUBDOMAIN:      process.env.CF_SUBDOMAIN      || 'streamvault',
  PUBLIC_BASE_URL:   process.env.PUBLIC_BASE_URL   || '',
};
SVEOF_src_config_env_js

mkdir -p "$INSTALL_DIR/src/filters"
cat > "$INSTALL_DIR/src/filters/quality.js" <<'SVEOF_src_filters_quality_js'
// src/filters/quality.js — release quality filtering

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

/**
 * Returns true if the torrent name contains any blocked tag
 */
function isBlocked(name = '', blockedTags = defaults.blockedTags) {
  const upper = name.toUpperCase();
  return blockedTags.some(tag => {
    // Match as a word boundary so "WEB-DL" doesn't match "TS" inside "EXTRAS"
    const pattern = new RegExp(`(^|[\\s.\\-_\\[\\(])${tag}([\\s.\\-_\\]\\)]|$)`, 'i');
    return pattern.test(upper);
  });
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

/**
 * Main filter — returns only torrents that pass all quality gates
 * @param {Array}  torrents  raw TorBox results
 * @param {object} prefs     user profile prefs
 */
function filterResults(torrents = [], prefs = {}) {
  const minQuality  = prefs.minQuality  || defaults.minQuality;
  const blockedTags = prefs.blockedTags || defaults.blockedTags;
  const cachedOnly  = prefs.cachedOnly  !== undefined ? prefs.cachedOnly : defaults.cachedOnly;

  return torrents.filter(t => {
    const name = t.name || t.title || '';

    // 1. Blocked release type check
    if (isBlocked(name, blockedTags)) return false;

    // 2. Minimum resolution check
    if (!meetsMinQuality(name, minQuality)) return false;

    // 3. Cached-only gate
    if (cachedOnly && !t.cached) return false;

    return true;
  });
}

module.exports = { filterResults, detectResolution, isBlocked, meetsMinQuality };
SVEOF_src_filters_quality_js

mkdir -p "$INSTALL_DIR/src/profiles"
cat > "$INSTALL_DIR/src/profiles/store.js" <<'SVEOF_src_profiles_store_js'
// src/profiles/store.js
// Lightweight file-based profile store (no DB required)
// Profiles live in profiles.json next to this file

const fs   = require('fs');
const path = require('path');
const { v4: uuidv4 } = require('uuid');
const defaults = require('../config/defaults');

const STORE_PATH = path.join(__dirname, '../../data/profiles.json');

// ── Helpers ───────────────────────────────────────────────────

function ensureDataDir() {
  const dir = path.dirname(STORE_PATH);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
}

function load() {
  ensureDataDir();
  if (!fs.existsSync(STORE_PATH)) return {};
  try {
    return JSON.parse(fs.readFileSync(STORE_PATH, 'utf8'));
  } catch {
    return {};
  }
}

function save(profiles) {
  ensureDataDir();
  fs.writeFileSync(STORE_PATH, JSON.stringify(profiles, null, 2));
}

// ── Public API ────────────────────────────────────────────────

/**
 * Create a new profile and return its configId
 */
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

/**
 * Get a single profile by configId
 */
function getProfile(configId) {
  return load()[configId] || null;
}

/**
 * List all profiles
 */
function listProfiles() {
  return Object.values(load());
}

/**
 * Update prefs for a given configId
 */
function updateProfile(configId, updates) {
  const profiles = load();
  if (!profiles[configId]) return null;
  profiles[configId].prefs = { ...profiles[configId].prefs, ...updates };
  profiles[configId].updatedAt = new Date().toISOString();
  save(profiles);
  return profiles[configId];
}

/**
 * Delete a profile
 */
function deleteProfile(configId) {
  const profiles = load();
  if (!profiles[configId]) return false;
  delete profiles[configId];
  save(profiles);
  return true;
}

module.exports = { createProfile, getProfile, listProfiles, updateProfile, deleteProfile };
SVEOF_src_profiles_store_js

mkdir -p "$INSTALL_DIR/src/scoring"
cat > "$INSTALL_DIR/src/scoring/rank.js" <<'SVEOF_src_scoring_rank_js'
// src/scoring/rank.js — preference-based scoring engine

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

  let score = 0;

  for (const [feature, active] of Object.entries(features)) {
    if (active && weights[feature]) {
      score += weights[feature];
    }
  }

  // Seed count bonus (log-scaled so it doesn't dominate)
  if (torrent.seeds && torrent.seeds > 0) {
    score += Math.min(Math.log10(torrent.seeds) * 2, 5);
  }

  // File size sanity: flag suspiciously small files (likely fake/mislabelled)
  const sizeGB = (torrent.size || 0) / 1e9;
  if (sizeGB < 0.5) score -= 5; // < 500MB for a "1080p" file is suspicious

  return Math.round(score * 10) / 10;
}

/**
 * Sort an array of (filtered) torrents by score descending
 * Attaches ._score to each for debugging
 */
function rankResults(torrents = [], prefs = {}) {
  return torrents
    .map(t => ({ ...t, _score: scoreTorrent(t, prefs), _features: detectFeatures(t.name || t.title || '') }))
    .sort((a, b) => b._score - a._score);
}

module.exports = { rankResults, scoreTorrent, detectFeatures };
SVEOF_src_scoring_rank_js

mkdir -p "$INSTALL_DIR/src"
cat > "$INSTALL_DIR/src/server.js" <<'SVEOF_src_server_js'
require('dotenv').config();
const express = require('express');
const cors = require('cors');
const morgan = require('morgan');
const path = require('path');
const chalk = require('chalk');

const addonRouter  = require('./addon/router');
const apiRouter    = require('./api/router');
const playerRouter = require('./api/player');
const torbox       = require('./api/torbox');
const { PORT, HOST, NODE_ENV } = require('./config/env');

const app = express();
app.use(cors());
app.use(express.json());
app.use(morgan(NODE_ENV === 'production' ? 'combined' : 'dev'));
app.use(express.static(path.join(__dirname, '../dashboard')));

app.use('/config', addonRouter);
app.use('/api/player', playerRouter);
app.use('/api', apiRouter);

// Stremio-friendly redirect endpoint. The stream list can return this URL;
// when playback starts, it resolves the hash through TorBox and redirects to
// the direct TorBox CDN URL.
app.get('/proxy/stream/:hash/:fileId?', async (req, res) => {
  try {
    const url = await torbox.getStreamUrlByHash(req.params.hash, parseInt(req.params.fileId || '0', 10));
    if (!url) return res.status(404).json({ error: 'TorBox stream URL unavailable. The torrent may still be importing.' });
    res.redirect(302, url);
  } catch (err) {
    console.error('[Proxy] stream error:', err.message);
    res.status(500).json({ error: 'Failed to resolve TorBox stream' });
  }
});

app.get('/', (req, res) => res.sendFile(path.join(__dirname, '../dashboard/index.html')));
app.get('/health', (req, res) => res.json({ status: 'ok', ts: Date.now() }));
app.use((req, res) => res.status(404).json({ error: 'Not found' }));

app.listen(PORT, HOST, () => {
  console.log('');
  console.log(chalk.bold.cyan('  ╔══════════════════════════════════════╗'));
  console.log(chalk.bold.cyan('  ║      StreamVault — Running           ║'));
  console.log(chalk.bold.cyan('  ╚══════════════════════════════════════╝'));
  console.log('');
  console.log(chalk.green(`  ► Local:     http://${HOST}:${PORT}`));
  console.log(chalk.green(`  ► Dashboard: http://localhost:${PORT}/`));
  console.log(chalk.green(`  ► Health:    http://localhost:${PORT}/health`));
  console.log('');
});
SVEOF_src_server_js

mkdir -p "$INSTALL_DIR/."
cat > "$INSTALL_DIR/streamvault.service" <<'SVEOF_streamvault_service'
[Unit]
Description=StreamVault — Private Stremio Addon
After=network.target

[Service]
Type=simple
User=YOUR_USERNAME
WorkingDirectory=/path/to/stremio-addon
ExecStart=/usr/bin/node src/server.js
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
SVEOF_streamvault_service


ok "Source files written"

step "Installing dependencies"
cd "$INSTALL_DIR"
npm install --silent --no-fund --no-audit
ok "Dependencies installed"

step "Writing config"
LOCAL_IP=$(hostname -I | awk '{print $1}')
[[ -z "$LOCAL_IP" ]] && LOCAL_IP="127.0.0.1"
PUBLIC_BASE_URL="http://${LOCAL_IP}:${PORT}"
[[ "$TS_ENABLED" == "true" && -n "$TAILSCALE_HOST" ]] && PUBLIC_BASE_URL="http://${TAILSCALE_HOST}:${PORT}"
[[ "$CF_ENABLED" == "true" && -n "$CF_DOMAIN" ]] && PUBLIC_BASE_URL="https://${CF_SUBDOMAIN}.${CF_DOMAIN}"
SECRET_KEY=$(python3 - <<'PY'
import secrets
print(secrets.token_urlsafe(32))
PY
)
cat > "$INSTALL_DIR/.env" << EOF
PORT=${PORT}
HOST=0.0.0.0
NODE_ENV=production
TORBOX_API_KEY=${TORBOX_KEY}
TORBOX_API_URL=https://api.torbox.app/v1/api
SECRET_KEY=${SECRET_KEY}
STREAM_CACHE_TTL=300
META_CACHE_TTL=3600
ADMIN_PASSWORD=${ADMIN_PASS}
NAS_LOCAL_IP=${LOCAL_IP}
TAILSCALE_HOST=${TAILSCALE_HOST}
TS_ENABLED=${TS_ENABLED}
CF_ENABLED=${CF_ENABLED}
CF_DOMAIN=${CF_DOMAIN}
CF_SUBDOMAIN=${CF_SUBDOMAIN}
CF_TOKEN=${CF_TOKEN}
PUBLIC_BASE_URL=${PUBLIC_BASE_URL}
DEFAULT_MIN_QUALITY=${MIN_RES}
DEFAULT_CACHED_ONLY=${CACHED_ONLY}
DEFAULT_PREFER_HEVC=${PREFER_HEVC}
DEFAULT_PREFER_HDR=${PREFER_HDR}
DEFAULT_PREFER_ATMOS=${PREFER_ATMOS}
DEFAULT_LANGUAGE=${PREF_LANG}
DEFAULT_MAX_SIZE_GB=${MAX_SIZE}
EOF
chmod 600 "$INSTALL_DIR/.env"
ok "Config saved"

if [[ "$TS_ENABLED" == "true" ]]; then
  step "Tailscale"
  if ! command -v tailscale &>/dev/null; then
    curl -fsSL https://tailscale.com/install.sh | sh >/dev/null
    ok "Tailscale installed"
  fi
  if [[ -n "$TS_AUTH_KEY" ]]; then
    $SUDO tailscale up --authkey="$TS_AUTH_KEY" --hostname="$TAILSCALE_HOST" 2>/dev/null || true
  fi
  ok "Tailscale ready"
fi

if [[ "$CF_ENABLED" == "true" ]]; then
  step "Cloudflare Tunnel"
  if ! command -v cloudflared &>/dev/null; then
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | $SUDO tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main" | $SUDO tee /etc/apt/sources.list.d/cloudflared.list >/dev/null
    $SUDO apt-get update -qq >/dev/null && $SUDO apt-get install -y cloudflared >/dev/null
    ok "cloudflared installed"
  else
    ok "cloudflared already installed"
  fi
  mkdir -p "$HOME/.cloudflared"
  cat > "$HOME/.cloudflared/config.yml" << EOF
# Run these once if you have not already:
# cloudflared tunnel login
# cloudflared tunnel create streamvault
# cloudflared tunnel route dns streamvault ${CF_SUBDOMAIN}.${CF_DOMAIN}
ingress:
  - hostname: ${CF_SUBDOMAIN}.${CF_DOMAIN}
    service: http://localhost:${PORT}
  - service: http_status:404
EOF
  warn "Complete Cloudflare once: cloudflared tunnel login && cloudflared tunnel create streamvault && cloudflared tunnel route dns streamvault ${CF_SUBDOMAIN}.${CF_DOMAIN}"
fi

step "System service"
NODE_BIN=$(command -v node)
$SUDO tee /etc/systemd/system/${SVC}.service >/dev/null << EOF
[Unit]
Description=StreamVault — TorBox Stremio Addon
After=network.target
[Service]
Type=simple
User=$USER
WorkingDirectory=${INSTALL_DIR}
ExecStart=${NODE_BIN} src/server.js
Restart=always
RestartSec=5
EnvironmentFile=${INSTALL_DIR}/.env
[Install]
WantedBy=multi-user.target
EOF
if command -v systemctl &>/dev/null && systemctl list-units >/dev/null 2>&1; then
  $SUDO systemctl daemon-reload
  $SUDO systemctl enable ${SVC} >/dev/null
  $SUDO systemctl restart ${SVC}
  sleep 2
  $SUDO systemctl is-active --quiet ${SVC} && ok "Service running" || err "Service failed — check: sudo journalctl -u streamvault -n 50"
else
  warn "systemd not available. Starting with nohup fallback. For production, use Ubuntu/Debian with systemd."
  pkill -f "$INSTALL_DIR/src/server.js" 2>/dev/null || true
  nohup env $(cat "$INSTALL_DIR/.env" | xargs) node "$INSTALL_DIR/src/server.js" > "$INSTALL_DIR/streamvault.log" 2>&1 &
  sleep 2
  curl -sf "http://localhost:${PORT}/health" >/dev/null && ok "Service running" || warn "Started fallback, check $INSTALL_DIR/streamvault.log"
fi

step "Installing CLI"
$SUDO tee "$CLI_BIN" >/dev/null << 'CLIEOF'
#!/usr/bin/env bash
INSTALL_DIR="$HOME/streamvault"
SVC="streamvault"
R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m' C='\033[0;36m' W='\033[1;37m' DIM='\033[2m' NC='\033[0m' BOLD='\033[1m'
ok(){ echo -e "  ${G}✓${NC} $*"; }
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
_url(){ local id="$1"; if [[ -n "${PUBLIC_BASE_URL:-}" ]]; then echo "${PUBLIC_BASE_URL%/}/config/${id}/manifest.json"; elif [[ "${CF_ENABLED:-false}" == "true" ]]; then echo "https://${CF_SUBDOMAIN}.${CF_DOMAIN}/config/${id}/manifest.json"; elif [[ -n "${TAILSCALE_HOST:-}" ]]; then echo "http://${TAILSCALE_HOST}:${PORT}/config/${id}/manifest.json"; else local lip; lip=$(hostname -I | awk '{print $1}'); echo "http://${lip}:${PORT}/config/${id}/manifest.json"; fi; }
_find(){ local name="$1"; _get "profiles" 2>/dev/null | python3 -c "import sys,json; ps=json.load(sys.stdin); n='$name'.lower(); [print(p['configId']) for p in ps if p['name'].lower()==n or p['configId'].startswith(n)][:1]" 2>/dev/null | head -1; }
CMD="${1:-help}"; shift 2>/dev/null || true
case "$CMD" in
status)
  echo -e "\n  ${W}${BOLD}StreamVault Status${NC}"; sep
  systemctl is-active --quiet $SVC 2>/dev/null && echo -e "  Service   ${G}● Running${NC}" || echo -e "  Service   ${Y}● Unknown/fallback${NC}"
  curl -sf "http://localhost:${PORT}/health" >/dev/null && echo -e "  HTTP      ${G}● Online${NC}" || echo -e "  HTTP      ${R}● Unreachable${NC}"
  REDIS=$(redis-cli ping 2>/dev/null || docker exec redis redis-cli ping 2>/dev/null || echo FAIL)
  [[ "$REDIS" == "PONG" ]] && echo -e "  Redis     ${G}● Connected${NC}" || echo -e "  Redis     ${R}● Disconnected${NC}"
  echo "";;
logs) sudo journalctl -u $SVC -f --no-pager 2>/dev/null || tail -f "$INSTALL_DIR/streamvault.log";;
restart) sudo systemctl restart $SVC 2>/dev/null || (pkill -f "$INSTALL_DIR/src/server.js" 2>/dev/null; cd "$INSTALL_DIR" && nohup node src/server.js > streamvault.log 2>&1 &); ok "Restarted";;
backup) DEST="$HOME/streamvault-backup-$(date +%Y-%m-%d_%H-%M).tar.gz"; tar -czf "$DEST" -C "$HOME" streamvault --exclude='streamvault/node_modules' 2>/dev/null; ok "Saved: $DEST";;
profile)
  SUB="${1:-}"; shift 2>/dev/null || true
  case "$SUB" in
  add)
    echo -e "\n  ${W}${BOLD}New Profile${NC}"; sep
    ask "Profile name"; read -rp "  › " P_NAME; [[ -z "$P_NAME" ]] && err "Name required"
    ask "Min resolution [${DEFAULT_MIN_QUALITY:-1080p}]"; read -rp "  › " P_RES; P_RES="${P_RES:-${DEFAULT_MIN_QUALITY:-1080p}}"
    ask "Cached only? [${DEFAULT_CACHED_ONLY:-true}] true/false"; read -rp "  › " P_CACHED; P_CACHED="${P_CACHED:-${DEFAULT_CACHED_ONLY:-true}}"
    PAYLOAD=$(python3 -c "import json; print(json.dumps({'name':'$P_NAME','prefs':{'minQuality':'$P_RES','cachedOnly':$P_CACHED,'maxSizeGB':${DEFAULT_MAX_SIZE_GB:-80},'language':'${DEFAULT_LANGUAGE:-en}'}}))")
    RESULT=$(_post "profiles" "$PAYLOAD" 2>/dev/null); ID=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('configId',''))" 2>/dev/null)
    [[ -z "$ID" ]] && err "Failed — is StreamVault running?"
    echo -e "\n  ${G}${BOLD}✓ Profile created${NC}\n  ${C}$(_url "$ID")${NC}\n";;
  list)
    _get "profiles" | python3 -c "import sys,json; ps=json.load(sys.stdin); [print(f'{p[\"name\"]}\n  {p[\"configId\"]}\n  {p.get(\"prefs\",{}).get(\"minQuality\",\"—\")} cached:{p.get(\"prefs\",{}).get(\"cachedOnly\",\"—\")}\n') for p in ps]";;
  url) [[ -z "${1:-}" ]] && err "Usage: streamvault profile url <name>"; ID=$(_find "$1"); [[ -z "$ID" ]] && err "Profile not found"; echo -e "\n  ${C}$(_url "$ID")${NC}\n";;
  del) [[ -z "${1:-}" ]] && err "Usage: streamvault profile del <name>"; ID=$(_find "$1"); [[ -z "$ID" ]] && err "Profile not found"; _del "profiles/$ID" >/dev/null && ok "Deleted";;
  *) echo "Usage: streamvault profile <add|list|url|del>";;
  esac;;
config) echo -e "\n  Port        ${C}${PORT}${NC}\n  Base URL    ${C}${PUBLIC_BASE_URL:-}${NC}\n  TorBox      ${DIM}${TORBOX_API_KEY:0:8}…${NC}\n";;
help|--help|-h|"") echo -e "\n  ${W}${BOLD}streamvault${NC}\n  ${C}status${NC} | ${C}logs${NC} | ${C}restart${NC} | ${C}backup${NC}\n  ${C}profile add${NC} | ${C}profile list${NC} | ${C}profile url <name>${NC} | ${C}profile del <name>${NC}\n  ${C}config${NC}\n";;
*) echo "Unknown: $CMD"; exit 1;;
esac
CLIEOF
$SUDO chmod +x "$CLI_BIN"
ok "CLI installed"

sep
echo -e "\n  ${G}${BOLD}✓ StreamVault installed${NC}\n"
echo -e "  ${W}Dashboard${NC}  ${C}${PUBLIC_BASE_URL}${NC}"
echo -e "\n  ${W}Next:${NC}"
echo -e "  ${DIM}1.${NC} Open ${C}${PUBLIC_BASE_URL}${NC}"
echo -e "  ${DIM}2.${NC} Create a profile in dashboard or run ${C}streamvault profile add${NC}"
echo -e "  ${DIM}3.${NC} Add the manifest URL in Stremio"
[[ "$CF_ENABLED" == "true" ]] && echo -e "\n  ${Y}Cloudflare reminder:${NC} finish tunnel login/create/route commands printed above."
echo -e "\n  ${DIM}streamvault help — all commands${NC}\n"

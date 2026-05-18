#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════╗
# ║  StreamVault — Self-hosted TorBox Stremio Addon          ║
# ║  One-line install:                                       ║
# ║  curl -fsSL https://raw.githubusercontent.com/          ║
# ║    YOURNAME/streamvault/main/install.sh | bash           ║
# ╚══════════════════════════════════════════════════════════╝
set -euo pipefail

# ── Colours ───────────────────────────────────────────────────
R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m'
C='\033[0;36m' W='\033[1;37m' DIM='\033[2m'
NC='\033[0m'   BOLD='\033[1m'

# ── Helpers ───────────────────────────────────────────────────
step() { echo -e "\n${C}▶${NC} ${BOLD}$*${NC}"; }
ok()   { echo -e "  ${G}✓${NC} $*"; }
warn() { echo -e "  ${Y}⚠${NC}  $*"; }
err()  { echo -e "\n  ${R}✗ $*${NC}\n"; exit 1; }
sep()  { echo -e "\n  ${DIM}──────────────────────────────────────────${NC}"; }
ask()  { echo -e "\n  ${W}$*${NC}"; }

REPO="https://github.com/YOURNAME/streamvault"
INSTALL_DIR="$HOME/streamvault"
CLI_BIN="/usr/local/bin/streamvault"
SVC="streamvault"

# ── Banner ────────────────────────────────────────────────────
clear
echo -e "${C}${BOLD}"
echo '   ____  _                        _   _             _ _  '
echo '  / ___|| |_ _ __ ___  __ _ _ __ | | | | __ _ _   _| | |'
echo '  \___ \| __| '"'"'__/ _ \/ _` | '"'"'_ \| | | |/ _` | | | | | |'
echo '   ___) | |_| | |  __/ (_| | | | | |_| | (_| | |_| | | |'
echo '  |____/ \__|_|  \___|\__,_|_| |_|\___/ \__,_|\__,_|_|_|'
echo -e "${NC}"
echo -e "  ${DIM}Self-hosted TorBox Stremio Addon${NC}\n"

# ══════════════════════════════════════════════════════════════
#  SYSTEM CHECKS
# ══════════════════════════════════════════════════════════════
step "Checking system"

OS="$(uname -s)"
[[ "$OS" != "Linux" && "$OS" != "Darwin" ]] && err "Linux or macOS required"
IS_MAC=false; [[ "$OS" == "Darwin" ]] && IS_MAC=true
ok "OS: $OS"

SUDO=""
[[ $EUID -ne 0 ]] && SUDO="sudo"

# On macOS ensure Homebrew is available
if [[ "$IS_MAC" == "true" ]] && ! command -v brew &>/dev/null; then
  echo -e "  ${DIM}Installing Homebrew...${NC}"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || eval "$(/usr/local/bin/brew shellenv)" 2>/dev/null || true
fi

for cmd in curl git python3; do
  if command -v "$cmd" &>/dev/null; then
    ok "$cmd"
  elif [[ "$IS_MAC" == "true" ]]; then
    brew install "$cmd" >/dev/null && ok "$cmd installed"
  else
    err "$cmd is required — sudo apt install $cmd"
  fi
done

# ── Node.js ───────────────────────────────────────────────────
step "Node.js"
if command -v node &>/dev/null && node -e "process.exit(parseInt(process.version.slice(1))<18?1:0)" 2>/dev/null; then
  ok "Node.js $(node --version)"
else
  echo -e "  ${DIM}Installing Node.js v22...${NC}"
  if [[ "$IS_MAC" == "true" ]]; then
    brew install node@22 >/dev/null 2>&1 && brew link node@22 --force --overwrite >/dev/null 2>&1 || brew install node >/dev/null 2>&1
    export PATH="/opt/homebrew/opt/node@22/bin:/usr/local/opt/node@22/bin:$PATH"
  else
    curl -fsSL https://deb.nodesource.com/setup_22.x | $SUDO bash - >/dev/null
    $SUDO apt-get install -y nodejs >/dev/null
  fi
  ok "Node.js $(node --version) installed"
fi

# ── Redis ─────────────────────────────────────────────────────
step "Redis"
if command -v docker &>/dev/null && docker ps 2>/dev/null | grep -q redis; then
  ok "Redis running (Docker)"
elif $SUDO systemctl is-active --quiet redis-server 2>/dev/null; then
  ok "Redis running (system)"
elif command -v redis-cli &>/dev/null && redis-cli ping 2>/dev/null | grep -q PONG; then
  ok "Redis running"
elif command -v docker &>/dev/null; then
  echo -e "  ${DIM}Starting Redis via Docker...${NC}"
  docker run -d --name redis --restart always -p 6379:6379 redis:alpine &>/dev/null
  ok "Redis started"
elif [[ "$IS_MAC" == "true" ]]; then
  echo -e "  ${DIM}Installing Redis via Homebrew...${NC}"
  brew install redis >/dev/null 2>&1
  brew services start redis >/dev/null 2>&1
  sleep 1
  redis-cli ping >/dev/null 2>&1 && ok "Redis started (Homebrew)" || warn "Redis installed — may need a moment to start"
else
  echo -e "  ${DIM}Installing Redis...${NC}"
  $SUDO apt-get install -y redis-server &>/dev/null
  $SUDO systemctl enable --now redis-server &>/dev/null
  ok "Redis installed"
fi

# ══════════════════════════════════════════════════════════════
#  CLONE / UPDATE
# ══════════════════════════════════════════════════════════════
step "StreamVault"

if [[ -d "$INSTALL_DIR/.git" ]]; then
  warn "Existing install found — updating"
  cd "$INSTALL_DIR" && git pull --quiet origin main
  ok "Updated"
else
  echo -e "  ${DIM}Cloning...${NC}"
  git clone --quiet "$REPO" "$INSTALL_DIR"
  ok "Cloned to $INSTALL_DIR"
fi

cd "$INSTALL_DIR"
echo -e "  ${DIM}Installing dependencies...${NC}"
npm install --silent --no-fund --no-audit
mkdir -p data
ok "Ready"

# ══════════════════════════════════════════════════════════════
#  CONFIGURATION WIZARD
# ══════════════════════════════════════════════════════════════
sep
echo -e "\n  ${W}${BOLD}Setup Wizard${NC}"
echo -e "  ${DIM}Press Enter to accept defaults shown in [brackets]${NC}\n"

# ── TorBox API key ────────────────────────────────────────────
ask "TorBox API key — get it from torbox.app/settings"
while true; do
  read -rp "  › " TORBOX_KEY
  [[ -n "$TORBOX_KEY" ]] && break
  echo -e "  ${R}Required${NC}"
done

# ── Admin password ────────────────────────────────────────────
ask "Admin password (used by the streamvault CLI)"
while true; do
  read -rsp "  › " ADMIN_PASS; echo ""
  [[ ${#ADMIN_PASS} -ge 6 ]] && break
  echo -e "  ${R}Minimum 6 characters${NC}"
done

# ── Port ─────────────────────────────────────────────────────
ask "Port [7000]"
read -rp "  › " PORT_IN
PORT="${PORT_IN:-7000}"

# ── Access method ─────────────────────────────────────────────
sep
echo -e "\n  ${W}${BOLD}How will you access StreamVault?${NC}\n"
echo -e "  ${C}1${NC}  Cloudflare Tunnel  ${DIM}Public HTTPS — no port forwarding, needs a domain${NC}"
echo -e "  ${C}2${NC}  Tailscale          ${DIM}Private — only your Tailscale devices, no domain needed${NC}"
echo -e "  ${C}3${NC}  Local only         ${DIM}LAN only — home network access via IP:port${NC}"
echo -e "  ${C}4${NC}  All three          ${DIM}Cloudflare + Tailscale + Local${NC}"
echo ""
while true; do
  read -rp "  › " ACCESS
  [[ "$ACCESS" =~ ^[1-4]$ ]] && break
  echo -e "  ${R}Enter 1, 2, 3 or 4${NC}"
done

CF_ENABLED=false; TS_ENABLED=false
CF_DOMAIN=""; CF_SUBDOMAIN="streamvault"; CF_TOKEN=""
CF_ACCESS=false; CF_COUNTRY_BLOCK=false; CF_RATE_LIMIT=60
TS_AUTH_KEY=""; TS_HOSTNAME="streamvault"

setup_cloudflare() {
  sep
  echo -e "\n  ${W}${BOLD}Cloudflare Tunnel${NC}"
  echo -e "  ${DIM}Needs: domain on Cloudflare + API token${NC}"
  echo -e "  ${DIM}Token: dash.cloudflare.com/profile/api-tokens${NC}"
  echo -e "  ${DIM}Permissions: Zone:DNS:Edit + Account:Cloudflare Tunnel:Edit${NC}\n"

  ask "Cloudflare API token"
  while true; do
    read -rsp "  › " CF_TOKEN; echo ""
    [[ -n "$CF_TOKEN" ]] && break
    echo -e "  ${R}Required${NC}"
  done

  ask "Your domain (e.g. yourdomain.com)"
  while true; do
    read -rp "  › " CF_DOMAIN
    [[ -n "$CF_DOMAIN" ]] && break
    echo -e "  ${R}Required${NC}"
  done

  ask "Subdomain [streamvault]"
  read -rp "  › " CF_SUB_IN
  CF_SUBDOMAIN="${CF_SUB_IN:-streamvault}"

  ask "Enable Cloudflare Access (require login before addon is reachable)? [y/N]"
  read -rp "  › " CF_ACC_IN
  [[ "${CF_ACC_IN,,}" == "y" ]] && CF_ACCESS=true

  ask "Block all countries except yours? [y/N]"
  read -rp "  › " CF_CB_IN
  [[ "${CF_CB_IN,,}" == "y" ]] && CF_COUNTRY_BLOCK=true

  ask "Rate limit — requests per minute per IP [60]"
  read -rp "  › " CF_RL_IN
  CF_RATE_LIMIT="${CF_RL_IN:-60}"

  CF_ENABLED=true
}

setup_tailscale() {
  sep
  echo -e "\n  ${W}${BOLD}Tailscale${NC}"
  echo -e "  ${DIM}Get an auth key: login.tailscale.com/admin/settings/keys${NC}\n"

  ask "Tailscale auth key"
  while true; do
    read -rsp "  › " TS_AUTH_KEY; echo ""
    [[ -n "$TS_AUTH_KEY" ]] && break
    echo -e "  ${R}Required${NC}"
  done

  ask "Device hostname [streamvault]"
  read -rp "  › " TS_HOST_IN
  TS_HOSTNAME="${TS_HOST_IN:-streamvault}"
  TS_ENABLED=true
}

case "$ACCESS" in
  1) setup_cloudflare ;;
  2) setup_tailscale ;;
  3) true ;;
  4) setup_cloudflare; setup_tailscale ;;
esac

# ── Quality defaults ──────────────────────────────────────────
sep
echo -e "\n  ${W}${BOLD}Quality Defaults${NC}"
echo -e "  ${DIM}Applied to all profiles unless overridden${NC}\n"

ask "Minimum resolution [1080p]  (480p / 720p / 1080p / 2160p)"
read -rp "  › " RES_IN
MIN_RES="${RES_IN:-1080p}"

ask "Cached streams only (instant play)? [Y/n]"
read -rp "  › " CACHED_IN
[[ "${CACHED_IN,,}" == "n" ]] && CACHED_ONLY=false || CACHED_ONLY=true

ask "Prefer HEVC/x265? [Y/n]"
read -rp "  › " HEVC_IN
[[ "${HEVC_IN,,}" == "n" ]] && PREFER_HEVC=false || PREFER_HEVC=true

ask "Prefer HDR / Dolby Vision? [Y/n]"
read -rp "  › " HDR_IN
[[ "${HDR_IN,,}" == "n" ]] && PREFER_HDR=false || PREFER_HDR=true

ask "Prefer Atmos / TrueHD audio? [Y/n]"
read -rp "  › " ATMOS_IN
[[ "${ATMOS_IN,,}" == "n" ]] && PREFER_ATMOS=false || PREFER_ATMOS=true

ask "Preferred audio language [en]  (en / ar / fr / es / de / any)"
read -rp "  › " LANG_IN
PREF_LANG="${LANG_IN:-en}"

ask "Maximum file size in GB [80]  (0 = no limit)"
read -rp "  › " SIZE_IN
MAX_SIZE="${SIZE_IN:-80}"

# ══════════════════════════════════════════════════════════════
#  WRITE .env
# ══════════════════════════════════════════════════════════════
step "Writing config"
LOCAL_IP=$(hostname -I | awk '{print $1}')

cat > "$INSTALL_DIR/.env" << EOF
# StreamVault — generated $(date)

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
#  CLOUDFLARE TUNNEL
# ══════════════════════════════════════════════════════════════
if [[ "$CF_ENABLED" == "true" ]]; then
  step "Cloudflare Tunnel"

  if ! command -v cloudflared &>/dev/null; then
    echo -e "  ${DIM}Installing cloudflared...${NC}"
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg \
      | $SUDO tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] \
https://pkg.cloudflare.com/cloudflared any main" \
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
Description=Cloudflare Tunnel — StreamVault
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
  ok "Cloudflare Tunnel configured"
  warn "Complete setup: cloudflared tunnel login"
  warn "Then: cloudflared tunnel create streamvault"
  warn "Then: sudo systemctl start cloudflared"
fi

# ══════════════════════════════════════════════════════════════
#  TAILSCALE
# ══════════════════════════════════════════════════════════════
if [[ "$TS_ENABLED" == "true" ]]; then
  step "Tailscale"

  if ! command -v tailscale &>/dev/null; then
    echo -e "  ${DIM}Installing Tailscale...${NC}"
    curl -fsSL https://tailscale.com/install.sh | sh &>/dev/null
    ok "Tailscale installed"
  else
    ok "Tailscale already installed"
  fi

  $SUDO tailscale up --authkey="$TS_AUTH_KEY" --hostname="$TS_HOSTNAME" 2>/dev/null || true
  TS_IP=$(tailscale ip -4 2>/dev/null || echo "pending")
  ok "Tailscale connected — $TS_IP"
fi

# ══════════════════════════════════════════════════════════════
#  SYSTEMD SERVICE
# ══════════════════════════════════════════════════════════════
step "System service"
NODE_BIN=$(command -v node)

if [[ "$IS_MAC" == "true" ]]; then
  # macOS — use launchd
  PLIST_DIR="$HOME/Library/LaunchAgents"
  PLIST_PATH="$PLIST_DIR/com.streamvault.plist"
  mkdir -p "$PLIST_DIR"

  # Build env dict from .env
  ENV_DICT=""
  while IFS='=' read -r key val; do
    [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
    val="${val//&/&amp;}"
    ENV_DICT+="    <key>$key</key><string>$val</string>\n"
  done < <(grep -v '^#' "$INSTALL_DIR/.env" | grep '=')

  cat > "$PLIST_PATH" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.streamvault</string>
  <key>ProgramArguments</key>
  <array>
    <string>${NODE_BIN}</string>
    <string>${INSTALL_DIR}/src/server.js</string>
  </array>
  <key>WorkingDirectory</key>
  <string>${INSTALL_DIR}</string>
  <key>EnvironmentVariables</key>
  <dict>
$(while IFS='=' read -r key val; do [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue; echo "    <key>$key</key><string>$val</string>"; done < <(grep -v '^#' "$INSTALL_DIR/.env" | grep '='))
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${INSTALL_DIR}/streamvault.log</string>
  <key>StandardErrorPath</key>
  <string>${INSTALL_DIR}/streamvault.log</string>
</dict>
</plist>
PLISTEOF

  launchctl unload "$PLIST_PATH" 2>/dev/null || true
  launchctl load -w "$PLIST_PATH"
  sleep 2
  curl -sf "http://localhost:${PORT}/health" >/dev/null \
    && ok "Service started (launchd)" \
    || warn "Service may still be starting — check: tail -f $INSTALL_DIR/streamvault.log"

else
  # Linux — use systemd
  $SUDO tee /etc/systemd/system/${SVC}.service >/dev/null << SVEOF
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
SVEOF

  $SUDO systemctl daemon-reload
  $SUDO systemctl enable ${SVC} &>/dev/null
  $SUDO systemctl restart ${SVC}
  sleep 2

  $SUDO systemctl is-active --quiet ${SVC} \
    && ok "Service started (systemd)" \
    || err "Service failed — check: sudo journalctl -u streamvault -n 30"
fi

# ══════════════════════════════════════════════════════════════
#  CLI
# ══════════════════════════════════════════════════════════════
step "Installing CLI"

$SUDO tee "$CLI_BIN" >/dev/null << 'CLIEOF'
#!/usr/bin/env bash
# streamvault — CLI management tool

INSTALL_DIR="$HOME/streamvault"
SVC="streamvault"
R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m'
C='\033[0;36m' W='\033[1;37m' DIM='\033[2m'
NC='\033[0m'   BOLD='\033[1m'

ok()  { echo -e "  ${G}✓${NC} $*"; }
warn(){ echo -e "  ${Y}⚠${NC}  $*"; }
err() { echo -e "\n  ${R}✗ $*${NC}\n"; exit 1; }
sep() { echo -e "\n  ${DIM}──────────────────────────────────────────${NC}"; }
ask() { echo -e "\n  ${W}$*${NC}"; }

ENV_FILE="$INSTALL_DIR/.env"
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE" \
  || err "Config not found. Run the installer first."

PORT="${PORT:-7000}"
API="http://localhost:${PORT}/api"
AH="x-admin-token: $ADMIN_PASSWORD"

_get()  { curl -sf "$API/$1" -H "$AH"; }
_post() { curl -sf -X POST "$API/$1" -H "$AH" -H "Content-Type: application/json" -d "$2"; }
_del()  { curl -sf -X DELETE "$API/$1" -H "$AH"; }

_url() {
  local id="$1"
  local lip; lip=$(hostname -I | awk '{print $1}')
  if   [[ "$CF_ENABLED" == "true" ]]; then echo "https://${CF_SUBDOMAIN}.${CF_DOMAIN}/config/${id}/manifest.json"
  elif [[ "$TS_ENABLED" == "true"  ]]; then
    local tip; tip=$(tailscale ip -4 2>/dev/null || echo "YOUR_TS_IP")
    echo "http://${tip}:${PORT}/config/${id}/manifest.json"
  else echo "http://${lip}:${PORT}/config/${id}/manifest.json"
  fi
}

_find_profile() {
  local name="$1"
  _get "profiles" 2>/dev/null | python3 -c "
import sys,json
ps=json.load(sys.stdin)
n='$name'.lower()
for p in ps:
    if p['name'].lower()==n or p['configId'].startswith(n):
        print(p['configId']); break
" 2>/dev/null
}

CMD="${1:-help}"; shift 2>/dev/null || true

case "$CMD" in

# ── Service ───────────────────────────────────────────────────
status)
  echo -e "\n  ${W}${BOLD}StreamVault Status${NC}"
  sep
  systemctl is-active --quiet $SVC \
    && echo -e "  Service   ${G}● Running${NC}" \
    || echo -e "  Service   ${R}● Stopped${NC}"

  curl -sf "http://localhost:${PORT}/health" &>/dev/null \
    && echo -e "  HTTP      ${G}● Online${NC}" \
    || echo -e "  HTTP      ${R}● Unreachable${NC}"

  REDIS=$(docker exec redis redis-cli ping 2>/dev/null \
       || redis-cli ping 2>/dev/null || echo FAIL)
  [[ "$REDIS" == "PONG" ]] \
    && echo -e "  Redis     ${G}● Connected${NC}" \
    || echo -e "  Redis     ${R}● Disconnected${NC}"

  [[ "$CF_ENABLED" == "true" ]] && {
    systemctl is-active --quiet cloudflared \
      && echo -e "  Tunnel    ${G}● Active${NC}" \
      || echo -e "  Tunnel    ${Y}● Stopped${NC}"
  }

  STATS=$(_get "cache/stats" 2>/dev/null)
  HITS=$(echo "$STATS" | python3 -c \
    "import sys,json; print(json.load(sys.stdin).get('streams',{}).get('hits',0))" 2>/dev/null || echo —)
  STARTED=$(systemctl show $SVC --property=ActiveEnterTimestamp \
    | cut -d= -f2)
  echo -e "  Hits      ${DIM}$HITS${NC}"
  echo -e "  Started   ${DIM}$STARTED${NC}"
  echo ""
  ;;

logs)
  if [[ "$(uname -s)" == "Darwin" ]]; then
    tail -f "$INSTALL_DIR/streamvault.log"
  else
    sudo journalctl -u $SVC -f --no-pager
  fi
  ;;
restart)
  if [[ "$(uname -s)" == "Darwin" ]]; then
    launchctl unload "$HOME/Library/LaunchAgents/com.streamvault.plist" 2>/dev/null
    launchctl load -w "$HOME/Library/LaunchAgents/com.streamvault.plist"
  else
    sudo systemctl restart $SVC
  fi
  ok "Restarted" ;;

update)
  echo -e "  ${DIM}Pulling latest...${NC}"
  cd "$INSTALL_DIR"
  git pull --quiet origin main
  npm install --silent --no-fund --no-audit
  sudo systemctl restart $SVC
  ok "Updated and restarted"
  ;;

backup)
  DEST="$HOME/streamvault-backup-$(date +%Y-%m-%d_%H-%M).tar.gz"
  echo -e "  ${DIM}Creating backup...${NC}"
  tar -czf "$DEST" -C "$HOME" streamvault \
    --exclude='streamvault/node_modules' 2>/dev/null
  ok "Saved: $DEST"
  ;;

# ── Profiles ──────────────────────────────────────────────────
profile)
  SUB="${1:-}"; shift 2>/dev/null || true

  case "$SUB" in
  add)
    echo -e "\n  ${W}${BOLD}New Profile${NC}"
    sep

    ask "Profile name"
    read -rp "  › " P_NAME
    [[ -z "$P_NAME" ]] && err "Name required"

    ask "Min resolution [${DEFAULT_MIN_QUALITY:-1080p}]  (480p/720p/1080p/2160p)"
    read -rp "  › " P_RES
    P_RES="${P_RES:-${DEFAULT_MIN_QUALITY:-1080p}}"

    ask "Max file size GB [${DEFAULT_MAX_SIZE_GB:-80}]  (0=no limit)"
    read -rp "  › " P_SIZE
    P_SIZE="${P_SIZE:-${DEFAULT_MAX_SIZE_GB:-80}}"

    ask "Cached only? [${DEFAULT_CACHED_ONLY:-true}]  (true/false)"
    read -rp "  › " P_CACHED
    P_CACHED="${P_CACHED:-${DEFAULT_CACHED_ONLY:-true}}"

    ask "Prefer REMUX? [true]  (true/false)"
    read -rp "  › " P_REMUX
    P_REMUX="${P_REMUX:-true}"

    ask "Prefer BluRay? [true]  (true/false)"
    read -rp "  › " P_BR
    P_BR="${P_BR:-true}"

    ask "Video codec preference [hevc]  (hevc/av1/h264/any)"
    read -rp "  › " P_CODEC
    P_CODEC="${P_CODEC:-hevc}"

    ask "Dolby Vision [prefer]  (prefer/allow/block)"
    read -rp "  › " P_DV
    P_DV="${P_DV:-prefer}"

    ask "HDR10+ [prefer]  (prefer/allow/block)"
    read -rp "  › " P_HDRP
    P_HDRP="${P_HDRP:-prefer}"

    ask "HDR10 [prefer]  (prefer/allow/block)"
    read -rp "  › " P_HDR
    P_HDR="${P_HDR:-prefer}"

    ask "Prefer Atmos? [${DEFAULT_PREFER_ATMOS:-true}]  (true/false)"
    read -rp "  › " P_ATMOS
    P_ATMOS="${P_ATMOS:-${DEFAULT_PREFER_ATMOS:-true}}"

    ask "Prefer TrueHD? [true]  (true/false)"
    read -rp "  › " P_THD
    P_THD="${P_THD:-true}"

    ask "Min audio channels [5.1]  (2.0/5.1/7.1)"
    read -rp "  › " P_CH
    P_CH="${P_CH:-5.1}"

    ask "Audio language [${DEFAULT_LANGUAGE:-en}]  (en/ar/fr/es/de/any)"
    read -rp "  › " P_LANG
    P_LANG="${P_LANG:-${DEFAULT_LANGUAGE:-en}}"

    ask "Subtitle language [any]"
    read -rp "  › " P_SLANG
    P_SLANG="${P_SLANG:-any}"

    ask "Block embedded subs (hardcoded)? [true]  (true/false)"
    read -rp "  › " P_HC
    P_HC="${P_HC:-true}"

    # Build scoring from preferences
    S_4K=12
    S_DV=10;  [[ "$P_DV"   == "block" ]] && S_DV=-5  || [[ "$P_DV"   == "allow" ]] && S_DV=3
    S_HDRP=9; [[ "$P_HDRP" == "block" ]] && S_HDRP=-3 || [[ "$P_HDRP" == "allow" ]] && S_HDRP=2
    S_HDR=8;  [[ "$P_HDR"  == "block" ]] && S_HDR=-3  || [[ "$P_HDR"  == "allow" ]] && S_HDR=2
    S_REMUX=9; [[ "$P_REMUX" == "false" ]] && S_REMUX=3
    S_BR=7;    [[ "$P_BR" == "false" ]]    && S_BR=2
    S_HEVC=10; [[ "$P_CODEC" != "hevc" ]] && S_HEVC=0
    S_AV1=0;   [[ "$P_CODEC" == "av1"  ]] && S_AV1=8
    S_H264=1;  [[ "$P_CODEC" == "h264" ]] && S_H264=6
    S_ATMOS=6; [[ "$P_ATMOS" == "false" ]] && S_ATMOS=0
    S_THD=5;   [[ "$P_THD" == "false" ]]   && S_THD=0

    PAYLOAD=$(python3 -c "
import json
print(json.dumps({
  'name': '$P_NAME',
  'prefs': {
    'minQuality':   '$P_RES',
    'cachedOnly':   $P_CACHED,
    'maxSizeGB':    $P_SIZE,
    'language':     '$P_LANG',
    'subLanguage':  '$P_SLANG',
    'minChannels':  '$P_CH',
    'blockHC':      $P_HC,
    'scoring': {
      'resolution4K': $S_4K,
      'dolbyVision':  $S_DV,
      'hdrPlus':      $S_HDRP,
      'hdr':          $S_HDR,
      'remux':        $S_REMUX,
      'bluray':       $S_BR,
      'hevc':         $S_HEVC,
      'av1':          $S_AV1,
      'h264':         $S_H264,
      'atmos':        $S_ATMOS,
      'trueHD':       $S_THD,
      'webdl':        6,
      'webrip':       3,
      'dts':          3,
    }
  }
}))
")

    RESULT=$(_post "profiles" "$PAYLOAD" 2>/dev/null)
    ID=$(echo "$RESULT" | python3 -c \
      "import sys,json; print(json.load(sys.stdin).get('configId',''))" 2>/dev/null)

    if [[ -n "$ID" ]]; then
      URL=$(_url "$ID")
      sep
      echo -e "\n  ${G}${BOLD}✓ Profile created: $P_NAME${NC}\n"
      echo -e "  ${W}Manifest URL:${NC}"
      echo -e "  ${C}${URL}${NC}"
      echo -e "\n  ${DIM}Add to Stremio: Search addons → paste URL → Install${NC}\n"
    else
      err "Failed — is StreamVault running? (streamvault status)"
    fi
    ;;

  list)
    PROFS=$(_get "profiles" 2>/dev/null)
    COUNT=$(echo "$PROFS" | python3 -c \
      "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo 0)

    echo -e "\n  ${W}${BOLD}Profiles ($COUNT)${NC}"
    sep

    if [[ "$COUNT" == "0" ]]; then
      echo -e "\n  ${DIM}None yet — run: streamvault profile add${NC}\n"
    else
      echo "$PROFS" | python3 - << 'PYEOF'
import sys, json
ps = json.load(sys.stdin)
for p in ps:
    pr = p.get('prefs', {})
    print(f"  {p['name']}")
    print(f"    ID:       {p['configId']}")
    print(f"    Quality:  {pr.get('minQuality','—')}  Cached: {pr.get('cachedOnly','—')}  Lang: {pr.get('language','—')}")
    print()
PYEOF
      echo -e "  ${DIM}streamvault profile url <name>  →  get manifest URL${NC}\n"
    fi
    ;;

  url)
    [[ -z "${1:-}" ]] && err "Usage: streamvault profile url <name>"
    ID=$(_find_profile "$1")
    [[ -z "$ID" ]] && err "Profile '$1' not found"
    echo -e "\n  ${C}$(_url "$ID")${NC}\n"
    ;;

  del)
    [[ -z "${1:-}" ]] && err "Usage: streamvault profile del <name>"
    ID=$(_find_profile "$1")
    [[ -z "$ID" ]] && err "Profile '$1' not found"
    read -rp "  Delete '$1'? Its manifest URL will stop working. [y/N] " CONF
    [[ "${CONF,,}" != "y" ]] && echo "Cancelled" && exit 0
    _del "profiles/$ID" >/dev/null
    ok "Deleted '$1'"
    ;;

  *)
    echo -e "\n  Usage: streamvault profile <add|list|url <name>|del <name>>\n"
    ;;
  esac
  ;;

# ── Config ────────────────────────────────────────────────────
config)
  SUB="${1:-show}"
  case "$SUB" in
  show)
    echo -e "\n  ${W}${BOLD}Configuration${NC}"
    sep
    echo -e "  Port          ${C}${PORT}${NC}"
    echo -e "  TorBox key    ${DIM}${TORBOX_API_KEY:0:8}…${NC}"
    echo -e "  CF Tunnel     ${C}${CF_ENABLED}${NC}"
    [[ "$CF_ENABLED" == "true" ]] && \
      echo -e "  CF URL        ${C}https://${CF_SUBDOMAIN}.${CF_DOMAIN}${NC}"
    echo -e "  Tailscale     ${C}${TS_ENABLED}${NC}"
    [[ "$TS_ENABLED" == "true" ]] && {
      TIP=$(tailscale ip -4 2>/dev/null || echo —)
      echo -e "  TS IP         ${C}${TIP}${NC}"
    }
    echo -e "  Min quality   ${C}${DEFAULT_MIN_QUALITY:-1080p}${NC}"
    echo -e "  Cached only   ${C}${DEFAULT_CACHED_ONLY:-true}${NC}"
    echo -e "  Language      ${C}${DEFAULT_LANGUAGE:-en}${NC}"
    echo -e "  Max size      ${C}${DEFAULT_MAX_SIZE_GB:-80}GB${NC}"
    echo -e "  Install dir   ${DIM}${INSTALL_DIR}${NC}"
    echo ""
    ;;
  *)
    echo -e "\n  Usage: streamvault config show\n"
    ;;
  esac
  ;;

# ── Help ──────────────────────────────────────────────────────
help|--help|-h|"")
  echo -e "\n  ${W}${BOLD}streamvault${NC} — StreamVault CLI\n"
  echo -e "  ${W}Service${NC}"
  echo -e "    ${C}status${NC}                    Health check and stats"
  echo -e "    ${C}logs${NC}                      Live log tail"
  echo -e "    ${C}restart${NC}                   Restart the service"
  echo -e "    ${C}update${NC}                    Pull latest and restart"
  echo -e "    ${C}backup${NC}                    Create a backup archive"
  echo -e "\n  ${W}Profiles${NC}"
  echo -e "    ${C}profile add${NC}               Create a profile (prints manifest URL)"
  echo -e "    ${C}profile list${NC}              List all profiles"
  echo -e "    ${C}profile url <name>${NC}        Print manifest URL"
  echo -e "    ${C}profile del <name>${NC}        Delete a profile"
  echo -e "\n  ${W}Config${NC}"
  echo -e "    ${C}config show${NC}               Print current config"
  echo ""
  ;;

*)
  echo -e "\n  ${R}Unknown: $CMD${NC}  —  run ${C}streamvault help${NC}\n"
  exit 1
  ;;
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
echo -e "  ${W}Local${NC}    http://${LOCAL_IP}:${PORT}"
[[ "$CF_ENABLED" == "true" ]] && \
  echo -e "  ${W}Public${NC}   https://${CF_SUBDOMAIN}.${CF_DOMAIN}"
[[ "$TS_ENABLED" == "true" ]] && {
  TIP=$(tailscale ip -4 2>/dev/null || echo pending)
  echo -e "  ${W}Tailscale${NC} http://${TIP}:${PORT}"
}

echo -e "\n  ${W}Next steps:${NC}"
echo -e "  ${DIM}1.${NC} ${C}streamvault profile add${NC}    — create a profile"
echo -e "  ${DIM}2.${NC} ${C}streamvault profile list${NC}   — get your manifest URL"
echo -e "  ${DIM}3.${NC} Paste the URL into Stremio → Search addons → Install"
[[ "$CF_ENABLED" == "true" ]] && {
  echo -e "\n  ${Y}Cloudflare: complete tunnel setup:${NC}"
  echo -e "  ${C}cloudflared tunnel login${NC}"
  echo -e "  ${C}cloudflared tunnel create streamvault${NC}"
  echo -e "  ${C}sudo systemctl start cloudflared${NC}"
}
echo -e "\n  ${DIM}streamvault help  —  all commands${NC}\n"

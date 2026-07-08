#!/usr/bin/env bash
# StreamVault installer — Option A / working NAS model.
# Usage:
#   sudo bash install.sh [--dir /opt/streamvault] [--port 7005]
#   sudo bash install.sh --reconfigure
set -euo pipefail

INSTALL_DIR="/opt/streamvault"
PORT="7005"
REPO_URL=""
SERVICE_USER="streamvault"
SERVICE_NAME="streamvault"
NODE_MAJOR="22"
RECONFIGURE=0

log()  { printf '\033[1;36m[streamvault]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[streamvault]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[streamvault]\033[0m %s\n' "$*" >&2; exit 1; }

write_default_env_example() {
  cat > .env.example <<'ENVEOF'
PORT=7005
HOST=0.0.0.0
NODE_ENV=production
TORBOX_API_KEY=
TORBOX_API_URL=https://api.torbox.app/v1/api
TORBOX_SEARCH_API_URL=https://search-api.torbox.app
TORBOX_TIMEOUT_MS=10000
TORBOX_RETRIES=2
TORBOX_ENABLE_NATIVE_SEARCH=true
TORBOX_ENABLE_USENET=true
TORBOX_SEARCH_USER_ENGINES=false
TORBOX_PROVIDER_PRIORITY=torbox-torrent,torbox-usenet,library,torrentio,knightcrawler
EXTERNAL_TORRENT_FALLBACK=true
TORRENTIO_ENABLED=true
KNIGHTCRAWLER_ENABLED=true
ADMIN_PASSWORD=
SECRET_KEY=
PUBLIC_BASE_URL=
NAS_LOCAL_IP=
TAILSCALE_HOST=
REDIS_URL=redis://127.0.0.1:6379
STREAM_CACHE_TTL=1800
META_CACHE_TTL=7200
DEFAULT_MIN_QUALITY=1080p
DEFAULT_CACHED_ONLY=true
DEFAULT_LANGUAGE=en
CF_TUNNEL_TOKEN=
CF_DOMAIN=
ENVEOF
}

ensure_env_template() {
  if [ ! -f .env.example ]; then
    warn "Missing .env.example — writing a safe default template instead of stopping."
    write_default_env_example
  fi
}

append_node_option() {
  case " ${NODE_OPTIONS:-} " in
    *" --dns-result-order="*) ;;
    *) export NODE_OPTIONS="${NODE_OPTIONS:+$NODE_OPTIONS }--dns-result-order=ipv4first" ;;
  esac
}

maybe_prefer_ipv4_for_node() {
  if command -v curl >/dev/null 2>&1; then
    if curl -fsS --connect-timeout 5 -4 https://registry.npmjs.org/ >/dev/null 2>&1; then
      if ! curl -fsS --connect-timeout 5 -6 https://registry.npmjs.org/ >/dev/null 2>&1; then
        warn "IPv4 npm registry works but IPv6 does not; using NODE_OPTIONS=--dns-result-order=ipv4first."
        append_node_option
      fi
    fi
  fi
}

npm_install_production() {
  local log_file="/tmp/streamvault-npm-install.log"
  maybe_prefer_ipv4_for_node
  log "Installing npm dependencies…"
  set +e
  npm install --omit=dev --no-audit --no-fund 2>&1 | tee "$log_file"
  local status=${PIPESTATUS[0]}
  set -e
  if [ "$status" -eq 0 ]; then return 0; fi
  if grep -qiE 'ENETUNREACH|EHOSTUNREACH|network is unreachable|IPv6' "$log_file"; then
    warn "npm failed with a network/IPv6-looking error. Retrying with IPv4-first DNS."
    append_node_option
    npm install --omit=dev --no-audit --no-fund
    return $?
  fi
  die "npm install failed. See $log_file"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dir) INSTALL_DIR="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --repo) REPO_URL="$2"; shift 2 ;;
    --reconfigure) RECONFIGURE=1; shift ;;
    -h|--help) grep '^#' "$0" | head -20; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

[ "$(uname -s)" = "Linux" ] || die "This installer supports Linux only."
[ "$(id -u)" -eq 0 ] || die "Run as root: sudo bash install.sh"
command -v systemctl >/dev/null 2>&1 || die "systemd is required (systemctl not found)."

run_wizard() {
  [ -t 0 ] || die "The setup wizard needs an interactive terminal. Re-run from SSH/console."
  node "$INSTALL_DIR/scripts/setup.js"
  chown -R "$SERVICE_USER":"$SERVICE_USER" "$INSTALL_DIR/data" "$INSTALL_DIR/logs" 2>/dev/null || true
  [ -f "$INSTALL_DIR/.env" ] && chown "$SERVICE_USER":"$SERVICE_USER" "$INSTALL_DIR/.env" && chmod 600 "$INSTALL_DIR/.env"
  [ -d "$INSTALL_DIR/bin" ] && chown -R "$SERVICE_USER":"$SERVICE_USER" "$INSTALL_DIR/bin"
}

if [ "$RECONFIGURE" -eq 1 ]; then
  [ -f "$INSTALL_DIR/package.json" ] || die "No StreamVault install found in $INSTALL_DIR (use --dir if it lives elsewhere)."
  cd "$INSTALL_DIR"
  run_wizard
  log "Restarting ${SERVICE_NAME}…"
  systemctl restart "${SERVICE_NAME}.service" || warn "Could not restart — is the service installed?"
  log "Done."
  exit 0
fi

PKG=""
if command -v apt-get >/dev/null 2>&1; then PKG="apt"
elif command -v dnf >/dev/null 2>&1; then PKG="dnf"
elif command -v yum >/dev/null 2>&1; then PKG="yum"
elif command -v pacman >/dev/null 2>&1; then PKG="pacman"
fi

pkg_install() {
  case "$PKG" in
    apt) DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" ;;
    dnf) dnf install -y "$@" ;;
    yum) yum install -y "$@" ;;
    pacman) pacman -S --noconfirm "$@" ;;
    *) die "No supported package manager found — install $* manually and re-run." ;;
  esac
}

[ "$PKG" = "apt" ] && apt-get update -qq
command -v git >/dev/null 2>&1 || { log "Installing git…"; pkg_install git; }
command -v curl >/dev/null 2>&1 || { log "Installing curl…"; pkg_install curl; }

need_node=1
if command -v node >/dev/null 2>&1; then
  ver="$(node -v | sed 's/^v//' | cut -d. -f1)"
  [ "$ver" -ge 18 ] && need_node=0
fi
if [ "$need_node" -eq 1 ]; then
  if [ "$PKG" = "apt" ]; then
    log "Installing Node.js ${NODE_MAJOR}.x (NodeSource)…"
    curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash -
    apt-get install -y nodejs
  else
    die "Install Node.js 18+ manually on this distro, then re-run."
  fi
fi
log "Node: $(node -v)"

if ! command -v redis-server >/dev/null 2>&1; then
  log "Installing Redis…"
  case "$PKG" in apt) pkg_install redis-server ;; *) pkg_install redis ;; esac
fi
systemctl enable --now redis-server 2>/dev/null || systemctl enable --now redis 2>/dev/null || warn "Could not start Redis via systemd — the app falls back to in-memory cache."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
mkdir -p "$INSTALL_DIR"
if [ -f "$SCRIPT_DIR/package.json" ] && [ "$SCRIPT_DIR" != "$INSTALL_DIR" ]; then
  log "Copying app from $SCRIPT_DIR to $INSTALL_DIR…"
  (cd "$SCRIPT_DIR" && tar -cf - --exclude=node_modules --exclude=data --exclude=logs --exclude=backups --exclude=.env --exclude=.git --exclude='*.bak.*' .) | tar -xf - -C "$INSTALL_DIR"
elif [ -f "$INSTALL_DIR/package.json" ]; then
  log "Using existing app in $INSTALL_DIR"
elif [ -n "$REPO_URL" ]; then
  log "Cloning $REPO_URL…"
  git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
else
  die "No app found. Run this script from inside the StreamVault repo, or pass --repo <git-url>."
fi

cd "$INSTALL_DIR"
if ! id "$SERVICE_USER" >/dev/null 2>&1; then
  log "Creating service user '$SERVICE_USER'…"
  useradd --system --home-dir "$INSTALL_DIR" --shell /usr/sbin/nologin "$SERVICE_USER" 2>/dev/null || useradd -r -d "$INSTALL_DIR" -s /sbin/nologin "$SERVICE_USER"
fi

npm_install_production
ensure_env_template
if [ ! -f .env ]; then
  log "Writing .env from template…"
  cp .env.example .env
fi
sed -i "s/^PORT=.*/PORT=${PORT}/" .env
if ! grep -q '^SECRET_KEY=..*' .env; then
  SECRET_KEY="$(openssl rand -hex 32 2>/dev/null || head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  if grep -q '^SECRET_KEY=' .env; then sed -i "s/^SECRET_KEY=.*/SECRET_KEY=${SECRET_KEY}/" .env; else printf '\nSECRET_KEY=%s\n' "$SECRET_KEY" >> .env; fi
fi

mkdir -p data logs bin
chown -R "$SERVICE_USER":"$SERVICE_USER" "$INSTALL_DIR"
chmod 600 .env
chmod 700 data

log "Installing systemd service…"
NODE_BIN="$(command -v node)"
cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<SERVICEEOF
[Unit]
Description=StreamVault — private Stremio addon
After=network-online.target redis-server.service redis.service
Wants=network-online.target

[Service]
Type=simple
User=${SERVICE_USER}
Group=${SERVICE_USER}
WorkingDirectory=${INSTALL_DIR}
ExecStart=${NODE_BIN} src/server.js
Restart=always
RestartSec=3
Environment=NODE_ENV=production
NoNewPrivileges=true
ProtectSystem=full
ReadWritePaths=${INSTALL_DIR}
PrivateTmp=true

[Install]
WantedBy=multi-user.target
SERVICEEOF

systemctl daemon-reload
log "Starting the setup wizard…"
run_wizard
systemctl enable --now "${SERVICE_NAME}.service"

log "Waiting for the server to come up…"
for _ in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then break; fi
  sleep 1
done

LAN_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
BASE_URL="$(grep '^PUBLIC_BASE_URL=' "$INSTALL_DIR/.env" 2>/dev/null | cut -d= -f2-)"
APP_PORT="$(grep '^PORT=' "$INSTALL_DIR/.env" 2>/dev/null | cut -d= -f2-)"
APP_PORT="${APP_PORT:-$PORT}"
if printf '%s' "$BASE_URL" | grep -q '^https://'; then
  warn "PUBLIC_BASE_URL is HTTPS. StreamVault itself serves HTTP only; keep Caddy/Nginx proxying HTTPS to http://127.0.0.1:${APP_PORT}."
fi

echo
log "──────────────────────────────────────────────────────"
log "StreamVault is installed and running."
log "Dashboard:    ${BASE_URL:-http://${LAN_IP:-<this-machine>}:${APP_PORT}}"
log "Service:      systemctl status ${SERVICE_NAME}"
log "Logs:         journalctl -u ${SERVICE_NAME} -f"
log "Reconfigure:  sudo bash install.sh --reconfigure"
log "──────────────────────────────────────────────────────"

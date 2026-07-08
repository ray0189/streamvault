#!/usr/bin/env bash
#
# StreamVault installer — Linux only (Debian/Ubuntu preferred, generic fallback).
#
# Usage:
#   sudo bash install.sh [--dir /opt/streamvault] [--port 7005] [--repo <git-url>]
#   sudo bash install.sh --reconfigure    # re-run the setup wizard only
#
# What it does:
#   * installs Node.js LTS, Redis and git if missing
#   * copies (or clones) the app into the install dir
#   * npm install, generates a fresh SECRET_KEY
#   * runs the interactive terminal setup wizard (admin account + access mode)
#   * creates a systemd service (streamvault.service) running as its own user
#   * starts the server and prints the dashboard login URL
#
# API keys (TorBox, TMDB) are entered later in the web dashboard Settings
# page, after logging in with the account created by the wizard.

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

while [ $# -gt 0 ]; do
  case "$1" in
    --dir)  INSTALL_DIR="$2"; shift 2 ;;
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

# Terminal setup wizard: admin account + access mode. Runs as root (data/ and
# .env get chown'd to the service user right after), then the service picks
# up the result on (re)start.
run_wizard() {
  [ -t 0 ] || die "The setup wizard needs an interactive terminal. Re-run from an SSH session, or run: cd $INSTALL_DIR && sudo node scripts/setup.js"
  node "$INSTALL_DIR/scripts/setup.js"
  chown -R "$SERVICE_USER":"$SERVICE_USER" "$INSTALL_DIR/data" 2>/dev/null || true
  [ -f "$INSTALL_DIR/.env" ] && chown "$SERVICE_USER":"$SERVICE_USER" "$INSTALL_DIR/.env" && chmod 600 "$INSTALL_DIR/.env"
  [ -d "$INSTALL_DIR/bin" ] && chown -R "$SERVICE_USER":"$SERVICE_USER" "$INSTALL_DIR/bin"
}

if [ "$RECONFIGURE" -eq 1 ]; then
  [ -f "$INSTALL_DIR/package.json" ] || die "No StreamVault install found in $INSTALL_DIR (use --dir if it lives elsewhere)."
  cd "$INSTALL_DIR"
  run_wizard
  log "Restarting ${SERVICE_NAME}…"
  systemctl restart "${SERVICE_NAME}.service" || warn "Could not restart — is the service installed? (systemctl status ${SERVICE_NAME})"
  log "Done. Log in at the URL printed by the wizard above."
  exit 0
fi

# ── Detect package manager ────────────────────────────────────────────────
PKG=""
if command -v apt-get >/dev/null 2>&1; then PKG="apt"
elif command -v dnf >/dev/null 2>&1; then PKG="dnf"
elif command -v yum >/dev/null 2>&1; then PKG="yum"
elif command -v pacman >/dev/null 2>&1; then PKG="pacman"
fi

pkg_install() {
  case "$PKG" in
    apt)    DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" ;;
    dnf)    dnf install -y "$@" ;;
    yum)    yum install -y "$@" ;;
    pacman) pacman -S --noconfirm "$@" ;;
    *)      die "No supported package manager found — install $* manually and re-run." ;;
  esac
}

[ "$PKG" = "apt" ] && apt-get update -qq

# ── git + curl ────────────────────────────────────────────────────────────
command -v git  >/dev/null 2>&1 || { log "Installing git…";  pkg_install git; }
command -v curl >/dev/null 2>&1 || { log "Installing curl…"; pkg_install curl; }

# ── Node.js LTS ───────────────────────────────────────────────────────────
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
    log "Installing Node.js LTS via nvm (generic fallback)…"
    export NVM_DIR="/usr/local/nvm"
    mkdir -p "$NVM_DIR"
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | NVM_DIR="$NVM_DIR" bash
    # shellcheck disable=SC1091
    . "$NVM_DIR/nvm.sh"
    nvm install --lts
    ln -sf "$(command -v node)" /usr/local/bin/node
    ln -sf "$(command -v npm)"  /usr/local/bin/npm
  fi
fi
log "Node: $(node -v)"

# ── Redis ────────────────────────────────────────────────────────────────
if ! command -v redis-server >/dev/null 2>&1; then
  log "Installing Redis…"
  case "$PKG" in
    apt) pkg_install redis-server ;;
    *)   pkg_install redis ;;
  esac
fi
systemctl enable --now redis-server 2>/dev/null || systemctl enable --now redis 2>/dev/null || warn "Could not start Redis via systemd — the app degrades to in-memory cache."

# ── App files ────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
mkdir -p "$INSTALL_DIR"

if [ -f "$SCRIPT_DIR/package.json" ] && [ "$SCRIPT_DIR" != "$INSTALL_DIR" ]; then
  log "Copying app from $SCRIPT_DIR to $INSTALL_DIR…"
  # rsync-free copy: everything except runtime/local artifacts
  (cd "$SCRIPT_DIR" && tar -cf - \
      --exclude=node_modules --exclude=data --exclude=logs --exclude=backups \
      --exclude=.env --exclude=.git --exclude='*.deb' --exclude='*.bak.*' .) | tar -xf - -C "$INSTALL_DIR"
elif [ -f "$INSTALL_DIR/package.json" ]; then
  log "Using existing app in $INSTALL_DIR"
elif [ -n "$REPO_URL" ]; then
  log "Cloning $REPO_URL…"
  git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
else
  die "No app found. Run this script from inside the StreamVault repo, or pass --repo <git-url>."
fi

cd "$INSTALL_DIR"

# ── Service user + permissions ───────────────────────────────────────────
if ! id "$SERVICE_USER" >/dev/null 2>&1; then
  log "Creating service user '$SERVICE_USER'…"
  useradd --system --home-dir "$INSTALL_DIR" --shell /usr/sbin/nologin "$SERVICE_USER" 2>/dev/null \
    || useradd -r -d "$INSTALL_DIR" -s /sbin/nologin "$SERVICE_USER"
fi

log "Installing npm dependencies…"
npm install --omit=dev --no-audit --no-fund

# ── .env: non-secret config + fresh SECRET_KEY. No admin password here —
#    the web wizard forces you to create one on first visit. ──────────────
if [ ! -f .env ]; then
  log "Writing .env from template…"
  cp .env.example .env
fi
sed -i "s/^PORT=.*/PORT=${PORT}/" .env
if ! grep -q '^SECRET_KEY=..*' .env; then
  SECRET_KEY="$(openssl rand -hex 32 2>/dev/null || head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  if grep -q '^SECRET_KEY=' .env; then
    sed -i "s/^SECRET_KEY=.*/SECRET_KEY=${SECRET_KEY}/" .env
  else
    printf '\nSECRET_KEY=%s\n' "$SECRET_KEY" >> .env
  fi
  log "Generated a fresh SECRET_KEY."
fi

mkdir -p data bin
chown -R "$SERVICE_USER":"$SERVICE_USER" "$INSTALL_DIR"
chmod 600 .env
chmod 700 data

# ── systemd service ──────────────────────────────────────────────────────
log "Installing systemd service…"
NODE_BIN="$(command -v node)"
cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
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
EOF

systemctl daemon-reload

# ── Terminal setup wizard (admin account + access mode) ──────────────────
echo
log "Starting the setup wizard…"
run_wizard

# ── Start the service and print the login URL ────────────────────────────
systemctl enable --now "${SERVICE_NAME}.service"

log "Waiting for the server to come up…"
for _ in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then break; fi
  sleep 1
done

LAN_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
BASE_URL="$(grep '^PUBLIC_BASE_URL=' "$INSTALL_DIR/.env" 2>/dev/null | cut -d= -f2-)"
echo
log "──────────────────────────────────────────────────────"
log "StreamVault is installed and running."
log ""
log "Log in to the dashboard with the account you just created:"
log "    ${BASE_URL:-http://${LAN_IP:-<this-machine>}:${PORT}}"
log ""
log "Then add your TorBox API key on the Settings page."
log ""
log "Service:      systemctl status ${SERVICE_NAME}"
log "Logs:         journalctl -u ${SERVICE_NAME} -f"
log "Reconfigure:  sudo bash install.sh --reconfigure"
log "──────────────────────────────────────────────────────"

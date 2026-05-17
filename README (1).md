# StreamVault

Self-hosted **TorBox Stremio addon** with a local dashboard, profile-based manifest URLs, quality filtering, stream scoring, caching, and optional remote access through Cloudflare Tunnel or Tailscale.

The public repository intentionally contains only the installer script. The installer writes the full app source onto the target Linux machine during setup.

---

## What StreamVault does

StreamVault runs a private Stremio addon on your own Linux server. It searches TorBox streams for movies and series, filters out low-quality releases, ranks the best results, and exposes them to Stremio through private manifest URLs.

Main features:

- Self-hosted Stremio addon
- TorBox API integration
- Movie and series stream support
- Per-device or per-user profiles
- Private manifest URLs
- Dashboard for managing profiles
- Quality filtering: 1080p/4K, cached-only, HEVC, HDR, Dolby Vision, Atmos, TrueHD
- Bad release filtering: CAM, TS, HDCAM, SCR, DVDSCR, TELECINE, TELESYNC, HC, R5
- Stream ranking/scoring system
- Node.js + Express backend
- Redis support for caching
- systemd service for auto-start
- `streamvault` command-line tool
- Optional Cloudflare Tunnel public HTTPS access
- Optional Tailscale private access
- Local/LAN-only mode

---

## Install

Run this on an Ubuntu/Debian Linux machine:

```bash
curl -fsSL https://raw.githubusercontent.com/ray0189/streamvault/main/install.sh | bash
```

The installer is interactive. It will ask for:

- TorBox API key
- Admin password
- Port, default `7000`
- Access method:
  - Cloudflare Tunnel
  - Tailscale
  - Local only
  - All three
- Quality defaults:
  - Minimum resolution
  - Cached-only mode
  - HEVC preference
  - HDR/Dolby Vision preference
  - Atmos/TrueHD preference
  - Preferred language
  - Max file size

---

## Requirements

Recommended:

- Ubuntu/Debian Linux
- `curl`
- `git`
- `python3`
- `sudo`
- internet access
- TorBox account/API key

The installer checks for required tools and installs Node.js v22 if Node.js 18+ is not already installed.

Redis is handled automatically:

- If Docker Redis is already running, StreamVault uses it.
- If system Redis is running, StreamVault uses it.
- If Docker is available, the installer starts `redis:alpine`.
- Otherwise, it installs `redis-server`.

---

## How it works

The installer creates the app in:

```bash
~/streamvault
```

It writes all required files from inside the installer, including:

```text
~/streamvault/package.json
~/streamvault/.env
~/streamvault/src/server.js
~/streamvault/src/config/env.js
~/streamvault/src/config/defaults.js
~/streamvault/src/cache/store.js
~/streamvault/src/api/torbox.js
~/streamvault/src/api/router.js
~/streamvault/src/addon/router.js
~/streamvault/src/addon/manifest.js
~/streamvault/src/addon/streams.js
~/streamvault/src/filters/quality.js
~/streamvault/src/scoring/rank.js
~/streamvault/src/profiles/store.js
~/streamvault/dashboard/index.html
```

It then:

1. Installs Node dependencies with `npm install`
2. Saves your private config to `~/streamvault/.env`
3. Optionally configures Cloudflare Tunnel
4. Optionally configures Tailscale
5. Creates a systemd service called `streamvault`
6. Installs a CLI command at:

```bash
/usr/local/bin/streamvault
```

The app runs as a background service using systemd.

---

## Dashboard

After installation, open the dashboard using one of these URLs:

Local server:

```text
http://localhost:7000
```

From another device on your LAN:

```text
http://SERVER_LAN_IP:7000
```

If Cloudflare Tunnel is enabled:

```text
https://streamvault.yourdomain.com
```

If Tailscale is enabled:

```text
http://TAILSCALE_IP:7000
```

Log in using the admin password you set during installation.

---

## Using with Stremio

Create a profile from the dashboard or CLI.

Each profile generates a private manifest URL like:

```text
http://SERVER_IP:7000/config/YOUR_CONFIG_ID/manifest.json
```

Add that manifest URL in Stremio as an addon.

Each profile can have different preferences, so you can create separate profiles for:

- Living room TV
- Phone
- 4K-only setup
- Cached-only setup
- Family device
- Testing profile

---

## CLI commands

After installation, use:

```bash
streamvault help
```

Available commands:

```bash
streamvault status
streamvault logs
streamvault restart
streamvault update
streamvault backup
streamvault config

streamvault profile add
streamvault profile list
streamvault profile url <name>
streamvault profile del <name>
```

Examples:

```bash
streamvault status
streamvault logs
streamvault profile add
streamvault profile list
```

---

## Service management

StreamVault runs as a systemd service.

Check status:

```bash
sudo systemctl status streamvault
```

Restart:

```bash
sudo systemctl restart streamvault
```

View logs:

```bash
sudo journalctl -u streamvault -f
```

---

## Configuration

Private configuration is stored in:

```bash
~/streamvault/.env
```

This file contains sensitive values such as:

- TorBox API key
- Admin password
- Cloudflare token
- Tailscale settings
- Port
- default quality preferences

Do not upload `.env` to GitHub.

The installer also creates `.gitignore` to exclude:

```text
.env
data/
node_modules/
*.log
*.tar.gz
.DS_Store
```

---

## Profiles

Profiles are stored locally in:

```bash
~/streamvault/data/profiles.json
```

Each profile gets a unique `configId`. Stremio uses that `configId` inside the manifest URL.

Deleting a profile stops that manifest URL from working.

---

## Stream filtering

StreamVault removes bad releases before ranking results.

Blocked tags include:

```text
CAM
TS
HDCAM
SCR
DVDSCR
TELECINE
TELESYNC
HC
R5
```

It also filters by minimum resolution, for example:

- `720p`
- `1080p`
- `2160p`

Cached-only mode only shows streams already cached by TorBox.

---

## Stream scoring

Streams are ranked using weighted scoring.

Higher priority is given to:

- 4K
- Dolby Vision
- HDR10+
- HDR
- HEVC/x265
- REMUX
- BluRay
- WEB-DL
- Atmos
- TrueHD
- DTS

The best-ranked results are shown first in Stremio.

---

## Access methods

### Local only

Best for home network use.

The addon is reachable only on your server/LAN, for example:

```text
http://192.168.1.50:7000
```

### Tailscale

Best for private remote access without exposing the service publicly.

The installer can install Tailscale and join your Tailnet using an auth key.

### Cloudflare Tunnel

Best for public HTTPS access using your own domain.

The installer writes a Cloudflare tunnel config and service file, but you may still need to complete Cloudflare login/tunnel creation:

```bash
cloudflared tunnel login
cloudflared tunnel create streamvault
sudo systemctl start cloudflared
```

---

## Updating

Use:

```bash
streamvault update
```

Or rerun the installer if you want a clean rebuild.

---

## Backup

Use:

```bash
streamvault backup
```

Backups are useful before editing config or upgrading.

---

## Security notes

- Keep your TorBox API key private.
- Keep your admin password private.
- Do not commit `.env`.
- Do not commit `data/profiles.json`.
- Treat manifest URLs as private because anyone with a working manifest URL may be able to access that profile.
- For public access, use Cloudflare protection where possible.
- For private access, Tailscale is safer than exposing the port directly.

---

## Troubleshooting

### Service failed to start

Check logs:

```bash
sudo journalctl -u streamvault -n 50
```

### Port already in use

Change the port in:

```bash
~/streamvault/.env
```

Then restart:

```bash
sudo systemctl restart streamvault
```

### Dashboard does not load

Check the service:

```bash
streamvault status
```

Also test health:

```bash
curl http://localhost:7000/health
```

### Redis not connected

StreamVault can still use in-memory cache, but Redis is better for persistent caching.

Check Docker Redis:

```bash
docker ps | grep redis
```

Check system Redis:

```bash
sudo systemctl status redis-server
```

### Stremio addon does not show streams

Check:

- TorBox API key is correct
- The content has TorBox search results
- Cached-only mode is not filtering everything out
- Minimum quality is not set too high
- Manifest URL matches an existing profile

---

## Repository structure

This public repo is intentionally minimal:

```text
streamvault/
└── install.sh
```

The full app is generated on the target machine by `install.sh`.

---

## Disclaimer

StreamVault is a self-hosted tool for connecting Stremio to your TorBox account. You are responsible for how you use it and for complying with laws, terms of service, and content rights in your country.

# StreamVault — Deploy Guide

The recommended path is the Linux installer, which ends in a terminal setup
wizard. There is no web-based setup: until the wizard has been run on the
server, the web UI only shows a "run setup on the server" notice.

## Quick install (Debian/Ubuntu, generic Linux fallback)

```bash
git clone <your-repo-url> streamvault
cd streamvault
sudo bash install.sh            # options: --dir /opt/streamvault --port 7005
```

The installer:

- installs Node.js LTS (NodeSource on Debian/Ubuntu, nvm elsewhere), Redis and git if missing
- copies the app to `/opt/streamvault` and runs `npm install`
- generates a fresh `SECRET_KEY` (never reuses one, never sets a default admin password)
- **runs the interactive setup wizard in your terminal** (see below)
- creates and enables `streamvault.service` (systemd) so it survives reboots
- starts the server and prints the dashboard login URL

## The terminal setup wizard

Runs automatically at the end of `install.sh`. Re-run it any time with
`sudo bash install.sh --reconfigure` (or `streamvault setup`) — it lets you
keep the existing admin account and just change the access mode.

**Step 1 — Admin account.** Username + password (min 8 chars, typed hidden,
confirmed). This is the only dashboard login; it's stored bcrypt-hashed
inside an encrypted store (`data/auth.db`), never in `.env`.

**Step 2 — Access mode.** Three genuinely different paths:

| Mode | Who it's for | What happens |
|---|---|---|
| **1. Own public IP / domain** | You have a public/static IP or a domain pointing at it, and can port-forward | You enter the IP/domain + port (+ http/https); `PUBLIC_BASE_URL` is set to expose the server directly. No Cloudflare, no tunnel. The wizard reminds you to forward the port (TCP) on your router. |
| **2. Cloudflare Tunnel** | No public IP (CGNAT) or no desire to port-forward | Paste the tunnel token + hostname from Cloudflare Zero Trust. cloudflared is downloaded automatically if missing and the token is validated on the spot, then stored encrypted. The tunnel runs supervised by the service and restarts with it. |
| **3. Local only (LAN/Tailscale)** | No public exposure at all | Confirms your LAN IP (auto-detected); manifest URLs are LAN-only. Use Tailscale for remote access without exposure. |

**Step 3 —** the wizard prints the dashboard URL. Log in with the account
from step 1.

## After login (web dashboard)

Enter your **TorBox API key** in **Settings** —
not in `.env`. Secrets are stored encrypted at rest in `data/secrets.db`,
keyed off `SECRET_KEY`. Password changes are in Settings → Account.

`.env` only holds non-sensitive runtime config (port, cache TTLs, provider
toggles).

## Day-to-day

| Task | Command |
|---|---|
| Status | `systemctl status streamvault` |
| Logs | `journalctl -u streamvault -f` |
| Restart | `systemctl restart streamvault` (or the Restart button in Settings) |
| Change access mode / reset admin | `sudo bash install.sh --reconfigure` |
| Update code | pull/copy new code into the install dir, `npm install`, restart |

## What persists where

- `.env` — non-secret runtime config
- `data/auth.db` — admin credentials (encrypted, bcrypt-hashed password)
- `data/secrets.db` — TorBox key, CF tunnel token (encrypted)
- `data/profiles.json` — Stremio profiles
- Redis — stream cache (safe to flush)

**Back up `data/` together with the `SECRET_KEY` line of `.env`** — the
encrypted stores are unreadable without it. Never change `SECRET_KEY` after
setup; if you lose it, delete `data/auth.db`/`data/secrets.db` and re-run the
wizard.

## Docker (alternative)

`docker compose up -d --build` still works, but you must run the wizard
inside the container once: `docker compose exec -it streamvault npm run setup`.
`REDIS_URL` is forced to `redis://redis:6379` by docker-compose.

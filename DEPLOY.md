# StreamVault — Deploy Guide

Everything runs in Docker: the app, Redis, and the Cloudflare Tunnel.
You do **not** need Node.js or Redis installed on the host.

## First-time setup

1. Install Docker (includes Compose): https://docs.docker.com/engine/install/
2. Copy the env template and fill it in:
   ```bash
   cp .env.example .env
   nano .env       # set TORBOX_API_KEY, ADMIN_PASSWORD, SECRET_KEY, CF_TUNNEL_TOKEN
   ```
   - `TORBOX_API_KEY` — from https://torbox.app → Settings → API
   - `CF_TUNNEL_TOKEN` — from Cloudflare Zero Trust → Networks → Tunnels
     (create a tunnel, add a public hostname pointing to `http://localhost:7005`)
   - `SECRET_KEY` — any long random string: `openssl rand -hex 32`
3. Start everything:
   ```bash
   docker compose up -d --build
   ```
4. Open `http://<server-ip>:7005` (or your tunnel domain) and log in with
   `ADMIN_PASSWORD`.

## Day-to-day

| Task | Command |
|---|---|
| Status | `docker compose ps` |
| App logs | `docker compose logs -f streamvault` |
| Tunnel logs | `docker compose logs -f cloudflared` |
| Restart app | `docker compose restart streamvault` |
| Apply code changes | `docker compose up -d --build` |
| Stop everything | `docker compose down` |

Settings changed in the dashboard are written to `.env` (bind-mounted into
the container) and survive restarts. Most need a restart to apply — use the
Restart button on the Settings page; Docker brings the app back automatically.

## What persists where

- `.env` — all configuration (bind mount)
- `./data/` — profiles (bind mount)
- `redis-data` volume — stream cache

## Gotchas

- `REDIS_URL` is forced to `redis://redis:6379` by docker-compose; editing it
  in the dashboard has no effect (the UI shows it as managed).
- The tunnel reuses your existing Cloudflare tunnel token — no DNS changes
  needed when moving hosts; just stop the old connector.


## VPS troubleshooting notes

### npm `ENETUNREACH` / broken IPv6

If `npm install` fails with `ENETUNREACH` but normal IPv4 internet works, the VPS likely has broken IPv6 routing while Node prefers IPv6 DNS answers. The installer detects this by checking:

```bash
curl -4 https://registry.npmjs.org/
curl -6 https://registry.npmjs.org/
```

When IPv4 works and IPv6 fails, it automatically exports:

```bash
NODE_OPTIONS=--dns-result-order=ipv4first
```

Manual fallback:

```bash
sudo env NODE_OPTIONS=--dns-result-order=ipv4first bash install.sh
```

### `.env.example`

`.env.example` is required because the installer copies it to `.env` on first install. It is included in the repo. If it is missing from a broken checkout, the installer writes a safe default template and continues.

### HTTPS / Caddy / DuckDNS

StreamVault only serves HTTP. Use HTTPS through a reverse proxy for Stremio iOS and other strict clients.

Example DuckDNS + Caddy setup:

```caddy
vault.example.com {
    reverse_proxy 127.0.0.1:7005
}
```

If another service such as S-UI already owns port `443`, use an alternate HTTPS port temporarily:

```caddy
https://vault.example.com:8444 {
    reverse_proxy 127.0.0.1:7005
}
```

Open the matching firewall port and set:

```env
PUBLIC_BASE_URL=https://vault.example.com:8444
```

Do not point Stremio at `https://<ip>:7005`; StreamVault is not a TLS server and trusted public TLS certs are normally issued for hostnames, not bare IP addresses.

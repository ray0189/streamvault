# StreamVault

StreamVault is a private self-hosted Stremio addon that uses your own TorBox account.
This branch uses the simple working NAS model: all runtime configuration lives in `.env`, including the TorBox API key and dashboard password.

## Install on Ubuntu/Debian VPS or NAS

```bash
git clone https://github.com/ray0189/streamvault.git
cd streamvault
sudo bash install.sh
```

The installer sets up Node.js, Redis, npm dependencies, `.env`, and `streamvault.service`, then runs the terminal setup wizard.

## Important files

- `.env.example` — template copied to `.env`
- `.env` — local runtime config; never commit this
- `data/profiles.json` — Stremio profiles
- Redis — stream cache

## Required `.env` values

```env
TORBOX_API_KEY=your_torbox_key
TORBOX_API_URL=https://api.torbox.app/v1/api
TORBOX_SEARCH_API_URL=https://search-api.torbox.app
TORBOX_ENABLE_NATIVE_SEARCH=true
TORBOX_ENABLE_USENET=true
TORBOX_PROVIDER_PRIORITY=torbox-torrent,torbox-usenet,library,torrentio,knightcrawler
DEFAULT_CACHED_ONLY=true
DEFAULT_MIN_QUALITY=1080p
```

## HTTPS / reverse proxy

For Caddy or any reverse proxy, point it to the local StreamVault port and set:

```env
PUBLIC_BASE_URL=https://your-domain.example
```

Your VPS setup used Caddy + DuckDNS successfully, so the app only needs the correct `PUBLIC_BASE_URL` and the proxy to forward to the StreamVault port.

## Commands

```bash
sudo systemctl status streamvault --no-pager
sudo journalctl -u streamvault -f
sudo systemctl restart streamvault
sudo bash install.sh --reconfigure
npm test
```

## Docker alternative

```bash
cp .env.example .env
nano .env
docker compose up -d --build
```


## VPS fixes included

### Broken IPv6 during npm install

Some VPS images have working IPv4 but broken IPv6 routing. In that state `apt update` and `git clone` can work, while `npm install` fails with `ENETUNREACH` because Node tries IPv6 first for `registry.npmjs.org`.

The installer now checks the npm registry over IPv4 and IPv6. If IPv4 works and IPv6 fails, it automatically runs npm with:

```bash
NODE_OPTIONS=--dns-result-order=ipv4first
```

It also retries `npm install` with IPv4-first DNS if npm fails with a network-unreachable style error.

### Missing `.env.example`

The repo includes `.env.example`. The installer also has a built-in fallback template, so a damaged or incomplete checkout will not die at:

```text
cp: cannot stat '.env.example'
```

### HTTPS for Stremio iOS

StreamVault serves HTTP locally. For Stremio iOS, use a trusted HTTPS hostname through a reverse proxy. Example Caddyfile for your VPS:

```caddy
https://vault.example.com:8444 {
    reverse_proxy 127.0.0.1:7005
}
```

Then set:

```env
PUBLIC_BASE_URL=https://vault.example.com:8444
```

If port `443` is already occupied by S-UI or another panel, either move that service off `443` or run Caddy on an alternate HTTPS port such as `8444` and open that TCP port in the firewall.

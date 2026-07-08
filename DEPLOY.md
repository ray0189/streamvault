# StreamVault VPS Installation & HTTPS Setup Report

## Overview

During deployment of StreamVault on a fresh Ubuntu VPS, three install/runtime issues were identified and fixed on this branch:

1. `npm install` can fail with `ENETUNREACH` when the VPS has broken IPv6 routing and Node/npm prefers IPv6 DNS results.
2. The installer expected `.env.example`; if that template was missing, install failed with `cp: cannot stat '.env.example'`.
3. Stremio iOS may fail to fetch addon manifests over plain HTTP, so production use should expose StreamVault through a trusted HTTPS reverse proxy.

## 1. npm installation failure caused by broken IPv6

### Problem

`apt update`, Git clone, and IPv4 connectivity worked, but `npm install` failed with a network unreachable error.

Testing showed:

```bash
curl -4 https://registry.npmjs.org
```

worked, while:

```bash
curl -6 https://registry.npmjs.org
```

failed immediately. The VPS advertised/attempted IPv6, but did not have working IPv6 routing.

### Fix

The installer now detects this condition and automatically applies:

```bash
NODE_OPTIONS=--dns-result-order=ipv4first
```

for the npm install step. If npm still fails with `ENETUNREACH`, `EHOSTUNREACH`, `network is unreachable`, or an IPv6-looking error, the installer retries npm with IPv4-first DNS.

Manual fallback:

```bash
export NODE_OPTIONS=--dns-result-order=ipv4first
sudo env NODE_OPTIONS=--dns-result-order=ipv4first bash install.sh
```

## 2. Missing `.env.example`

### Problem

The installer previously failed when `.env.example` was missing:

```text
cp: cannot stat '.env.example'
```

### Fix

This branch includes `.env.example` and the installer also has a built-in fallback template. If the file is missing, it writes a safe default template and continues instead of terminating.

The template uses the working NAS model:

```env
TORBOX_API_KEY=
TORBOX_API_URL=https://api.torbox.app/v1/api
DEFAULT_CACHED_ONLY=true
DEFAULT_MIN_QUALITY=1080p
PUBLIC_BASE_URL=
REDIS_URL=redis://127.0.0.1:6379
```

Do not commit the real `.env` file because it contains secrets.

## 3. HTTPS for Stremio iOS

StreamVault itself serves plain HTTP. If Stremio iOS fails with `Failed to fetch` and the StreamVault logs show no incoming request, the failure is likely happening before the app receives the request. Use a trusted HTTPS endpoint.

### DuckDNS

Example hostname:

```text
rvault.duckdns.org
```

pointing to the VPS IP:

```text
57.129.128.16
```

Verify DNS:

```bash
dig +short rvault.duckdns.org
```

### Caddy reverse proxy

When port 443 is free:

```caddy
rvault.duckdns.org {
    reverse_proxy 127.0.0.1:7005
}
```

Set:

```env
PUBLIC_BASE_URL=https://rvault.duckdns.org
```

### S-UI / port 443 conflict

If S-UI or another service is already listening on port 443, Caddy cannot bind to 443:

```text
listen tcp :443: bind: address already in use
```

Check:

```bash
sudo ss -lntp | grep ':443'
```

Temporary alternate-port Caddy config:

```caddy
https://rvault.duckdns.org:8444 {
    reverse_proxy 127.0.0.1:7005
}
```

Open the firewall:

```bash
sudo ufw allow 8444/tcp
```

Set:

```env
PUBLIC_BASE_URL=https://rvault.duckdns.org:8444
```

Verify:

```bash
curl -kI https://rvault.duckdns.org:8444/health
curl -k https://rvault.duckdns.org:8444/health
```

## Current known-good VPS shape

```text
StreamVault app:  http://127.0.0.1:7005
Caddy HTTPS:      https://rvault.duckdns.org:8444
Systemd service:  streamvault.service
Config file:      /opt/streamvault/.env
```

Health check:

```bash
curl http://127.0.0.1:7005/health
curl -k https://rvault.duckdns.org:8444/health
```

## Reinstall on VPS

```bash
sudo systemctl disable --now streamvault 2>/dev/null || true
sudo rm -rf /opt/streamvault ~/streamvault

git clone https://github.com/ray0189/streamvault.git ~/streamvault
cd ~/streamvault
sudo bash install.sh --dir /opt/streamvault --port 7005
```

For the current Caddy alternate HTTPS port setup, use this public URL in the setup wizard:

```text
https://rvault.duckdns.org:8444
```

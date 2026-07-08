# StreamVault

Private self-hosted Stremio addon backed by your own TorBox account.

This branch restores the working NAS install model: runtime configuration lives in `.env`, including `TORBOX_API_KEY`, `ADMIN_PASSWORD`, public URL, Redis URL and provider toggles. Do **not** commit your real `.env`.

## Install

```bash
git clone https://github.com/ray0189/streamvault.git
cd streamvault
sudo bash install.sh --dir /opt/streamvault --port 7005
```

For your VPS + Caddy setup, use the local app port behind Caddy. If Caddy proxies to `127.0.0.1:7005`, keep `--port 7005`. If it proxies to `127.0.0.1:7000`, use `--port 7000`.

## VPS fixes in this installer

The installer now handles two issues found during the VPS deployment:

- If IPv4 access to `registry.npmjs.org` works but IPv6 fails, it automatically uses `NODE_OPTIONS=--dns-result-order=ipv4first` for npm.
- If `.env.example` is missing, it writes a safe default template instead of failing with `cp: cannot stat '.env.example'`.

## HTTPS for Stremio iOS

StreamVault itself serves plain HTTP. For Stremio iOS, use a trusted HTTPS reverse proxy such as Caddy.

Example DuckDNS + Caddy config when port 443 is free:

```caddy
rvault.duckdns.org {
    reverse_proxy 127.0.0.1:7005
}
```

If S-UI or another panel already owns port 443, run Caddy on an alternate HTTPS port temporarily:

```caddy
https://rvault.duckdns.org:8444 {
    reverse_proxy 127.0.0.1:7005
}
```

Then set:

```env
PUBLIC_BASE_URL=https://rvault.duckdns.org:8444
```

Open the firewall port too:

```bash
sudo ufw allow 8444/tcp
```

## Useful commands

```bash
systemctl status streamvault --no-pager
journalctl -u streamvault -f
curl http://127.0.0.1:7005/health
curl -k https://rvault.duckdns.org:8444/health
```

See `DEPLOY.md` for the full VPS/HTTPS report.

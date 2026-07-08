# Option A — Restore working NAS install model

This package is a sanitized repo snapshot built from the working NAS StreamVault code.
It intentionally excludes `.env`, `data/`, `logs/`, `node_modules/`, backups, and `cloudflared.deb`.

## Main install-side changes

- Adds `.env.example` back to the repo.
- Restores the simple `.env` model used by the working NAS:
  - `TORBOX_API_KEY` lives in `.env`.
  - `ADMIN_PASSWORD` lives in `.env`.
  - No encrypted `data/secrets.db` flow is required.
- Replaces the setup wizard with an `.env` writer that works cleanly with `install.sh`.
- Keeps TorBox native torrent + Usenet search defaults enabled.
- Keeps provider priority: `torbox-torrent,torbox-usenet,library,torrentio,knightcrawler`.
- Keeps default cached-only streams and 1080p minimum quality.

## Apply to a local clone

```bash
git clone https://github.com/ray0189/streamvault.git
cd streamvault
unzip /path/to/streamvault-option-a-nas-github.zip -d /tmp/option-a
bash /tmp/option-a/tools/apply_option_a_to_repo.sh /tmp/option-a .
npm install
npm test
git status
git add .
git commit -m "Restore NAS working install model"
git push
```

## Fresh VPS install after pushing

```bash
sudo systemctl disable --now streamvault 2>/dev/null || true
sudo rm -rf /opt/streamvault
cd ~
rm -rf streamvault
git clone https://github.com/ray0189/streamvault.git
cd streamvault
sudo bash install.sh --dir /opt/streamvault --port 7000
```

For HTTPS installs, create your own hostname first, configure your reverse proxy, then set `PUBLIC_BASE_URL` in the wizard to your own URL, for example:

```text
https://your-hostname.example:8444
```


## VPS install fixes added

- Installer now detects broken IPv6 to `registry.npmjs.org` and uses `NODE_OPTIONS=--dns-result-order=ipv4first` for npm when needed.
- Installer retries npm with IPv4-first DNS after `ENETUNREACH` / network-unreachable failures.
- Installer now has a built-in `.env.example` fallback template, so a missing template no longer kills installation.
- Setup wizard warns when `PUBLIC_BASE_URL` is plain HTTP because Stremio iOS may require trusted HTTPS.
- Setup wizard warns when `PUBLIC_BASE_URL` is HTTPS because StreamVault itself is HTTP-only and needs a reverse proxy such as Caddy.
- README/DEPLOY now document user-provided hostname + Caddy, alternate HTTPS port `8444`, and S-UI port `443` conflicts.

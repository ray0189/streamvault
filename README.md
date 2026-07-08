# StreamVault

StreamVault is a private, self-hosted [Stremio](https://www.stremio.com/) addon
that streams movies and shows through your own [TorBox](https://torbox.app)
account. You run it on a Linux box you control (home server, NAS, VPS); it
searches TorBox's cached torrents/usenet (plus optional public indexers),
ranks results by quality, and hands Stremio a personal manifest URL per
device or person. Nothing is shared with anyone else: your TorBox key, your
server, your streams.

## Requirements

- **Linux** with systemd (Debian/Ubuntu best supported; Fedora/Arch work via
  a generic fallback). Root/`sudo` for installation.
- A **TorBox account + API key** (added after install, in the dashboard).
- **Network, depending on the access mode you pick in the wizard:**

  | Access mode | Inbound ports needed | Notes |
  |---|---|---|
  | Own public IP / domain | The port you choose (default **7005/TCP**) must be forwarded on your router/firewall to this machine | You need a public or static IP, or a domain whose DNS points at it |
  | Cloudflare Tunnel | **None** — only outbound HTTPS (443) | Works behind CGNAT; needs a free Cloudflare account with your domain on it |
  | Local only (LAN/Tailscale) | The port (default 7005/TCP) reachable on your LAN only | Nothing exposed to the internet |

Node.js (LTS), Redis and git are installed automatically if missing.

## Install

```bash
git clone <repo-url> streamvault
cd streamvault
sudo bash install.sh
```

Optional flags: `--dir /opt/streamvault` (install location), `--port 7005`.

The installer sets up Node, Redis, the app, and a systemd service
(`streamvault.service`, starts on boot), then drops you into a **terminal
setup wizard**:

**Step 1 — Admin account.** Pick a username and password (min 8 characters,
typed hidden). This is the only login for the web dashboard. It's stored
bcrypt-hashed in an encrypted local store — never in a plain config file.

**Step 2 — Access mode.** How will Stremio (on your TV, phone, laptop)
reach this server?

1. **Own public IP / domain** — choose this if your internet connection has
   a public or static IP and you can forward a port on your router. You
   enter the IP (or a domain already pointing at it) and the port; devices
   connect to it directly, with no third-party service involved. Remember to
   actually forward the port, or nothing outside your network can connect.
2. **Cloudflare Tunnel** — choose this if you don't have a public IP (mobile
   or CGNAT internet), can't port-forward, or just don't want an open port.
   In the Cloudflare Zero Trust dashboard you create a free tunnel, point a
   hostname at `http://localhost:7005`, and paste the tunnel token into the
   wizard. The connector (`cloudflared`) is downloaded automatically, the
   token is validated on the spot and stored encrypted, and the tunnel runs
   with the service. Your server only makes outbound connections.
3. **Local only (LAN / Tailscale)** — choose this if the addon should never
   be reachable from the internet. The wizard confirms your LAN IP and
   manifest URLs are LAN-only. For remote access without exposure, put the
   server and your devices on [Tailscale](https://tailscale.com) and use the
   Tailscale IP.

**Step 3 —** the wizard prints the dashboard URL. Open it and log in.

## After install: add your API keys

In the dashboard, go to **Settings**:

- **TorBox → API key** — from torbox.app → Settings → API. Use *Test TorBox
  connection* to verify.

Keys are stored encrypted at rest on the server (`data/secrets.db`), not in
`.env` and never shown in full again after saving. Then create a **Profile**
per device/person — each gets a private manifest URL to paste into Stremio
(Addons → paste URL → Install).

## Reconfigure or reset

- **Change access mode or replace the admin account:**
  `sudo bash install.sh --reconfigure` (or `streamvault setup`). Existing
  data is kept; you can keep the current admin and only change the network
  mode.
- **Forgot the admin password:** delete `data/auth.db` in the install
  directory, then run `--reconfigure` to create a new account. Other
  settings and profiles are untouched.
- **Full reset:** stop the service (`sudo systemctl stop streamvault`),
  delete `data/` and `.env` in the install directory, then re-run
  `sudo bash install.sh`. (Keep a backup of `data/` **plus the `SECRET_KEY`
  line of `.env`** if you ever want to restore — the encrypted stores are
  unreadable without that key.)
- **Uninstall:** `sudo systemctl disable --now streamvault`, remove
  `/etc/systemd/system/streamvault.service` and the install directory.

## Day-to-day

| Task | Command |
|---|---|
| Status | `systemctl status streamvault` |
| Logs | `journalctl -u streamvault -f` |
| Restart | `systemctl restart streamvault` (or the Restart button in Settings) |
| CLI helper | `node bin/streamvault help` (status, profiles, backup) |

## Alternative installs

- **Standalone install.sh** (you only downloaded the script, not the repo):
  `sudo bash install.sh --repo <repo-url>` clones the repo for you.
- **Docker:** `docker compose up -d --build`, then run the wizard once inside
  the container: `docker compose exec -it streamvault npm run setup`.

See [DEPLOY.md](DEPLOY.md) for more operational detail.

## Development

```bash
npm install
npm run setup      # terminal wizard: admin account + access mode
npm start
npm test
```

# StreamVault

Self-hosted **TorBox Stremio addon** with a local dashboard, profile-based manifest URLs, quality filtering, stream scoring, Redis caching, and optional remote access through Cloudflare Tunnel or Tailscale.

---

# Install

## Recommended install method

Use this instead of `curl | bash`.

```bash
curl -fsSL https://raw.githubusercontent.com/ray0189/streamvault/main/install.sh -o install.sh
chmod +x install.sh
./install.sh
```

This method is more reliable for interactive prompts and avoids issues when running inside:

- WSL
- SSH sessions
- tmux/screen
- some terminal emulators

---

# WSL Support

StreamVault fully supports:

- Windows 11 + WSL2
- Ubuntu on WSL
- Stremio running on Windows
- StreamVault running inside Linux/WSL

## Install on WSL

Inside Ubuntu on WSL:

```bash
curl -fsSL https://raw.githubusercontent.com/ray0189/streamvault/main/install.sh -o install.sh
chmod +x install.sh
./install.sh
```

Choose:

```text
3
```

for:

```text
Local only
```

---

# Important WSL Notes

When using WSL:

DO NOT use the temporary WSL IP like:

```text
http://172.x.x.x:7000
```

WSL IPs change often.

Instead use:

```text
http://127.0.0.1:7000
```

Example manifest URL:

```text
http://127.0.0.1:7000/config/YOUR_PROFILE_ID/manifest.json
```

This is the recommended method for:

- Stremio on Windows
- StreamVault in WSL

---

# Testing

Health endpoint:

```text
http://127.0.0.1:7000/health
```

Expected response:

```json
{"status":"ok"}
```

Manifest test:

```text
http://127.0.0.1:7000/config/YOUR_PROFILE_ID/manifest.json
```

---

# Features

- Self-hosted Stremio addon
- TorBox integration
- Cached stream support
- Quality filtering
- HDR / Dolby Vision preference
- HEVC/x265 preference
- Atmos / TrueHD preference
- Redis caching
- Dashboard
- CLI tools
- Cloudflare Tunnel support
- Tailscale support
- Local-only mode
- WSL support

---

# Dashboard

Open:

```text
http://127.0.0.1:7000
```

or on a LAN/NAS:

```text
http://SERVER_IP:7000
```

---

# Stremio Setup

Add the generated manifest URL into Stremio.

Example:

```text
http://127.0.0.1:7000/config/YOUR_PROFILE_ID/manifest.json
```

---

# Troubleshooting

## Stremio says “Failed to fetch”

First test the manifest in your browser.

If browser works but Stremio fails:

1. Fully close Stremio
2. Reopen it
3. Use:

```text
http://127.0.0.1:7000/config/YOUR_PROFILE_ID/manifest.json
```

NOT the temporary WSL IP.

---

## Restart service

```bash
sudo systemctl restart streamvault
```

Logs:

```bash
sudo journalctl -u streamvault -f
```

---

# Security

Do NOT upload:

```text
.env
profiles.json
```

Keep your:

- TorBox API key
- admin password
- manifest URLs

private.


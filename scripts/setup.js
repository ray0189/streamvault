#!/usr/bin/env node
// scripts/setup.js — terminal first-run wizard: identity + network access.
//
// Creates the admin login (bcrypt-hashed, in the encrypted data/auth.db) and
// configures how the server is reached (own public IP / Cloudflare Tunnel /
// LAN-only). Everything else — TorBox key, profiles — is done in the web
// dashboard after logging in.
//
// Run via: sudo bash install.sh   (called automatically at the end)
//          sudo bash install.sh --reconfigure
//          streamvault setup
//          npm run setup
//
// Safe to re-run: an existing admin account can be kept, and the access mode
// can be changed without wiping anything.

const path = require('path');
const readline = require('readline');

// Load .env then make sure SECRET_KEY exists before touching the vaults.
require('dotenv').config({ path: path.join(__dirname, '../.env') });
require('../src/config/bootstrap').ensureSecretKey();
require('../src/config/secrets').loadIntoEnv();

const users = require('../src/auth/users');
const secrets = require('../src/config/secrets');
const envFile = require('../src/config/env-file');
const cloudflared = require('../src/setup/cloudflared');

const R = '\x1b[31m', G = '\x1b[32m', Y = '\x1b[33m', C = '\x1b[36m',
      W = '\x1b[1m\x1b[37m', DIM = '\x1b[2m', NC = '\x1b[0m';
const ok = m => console.log(`  ${G}✓${NC} ${m}`);
const warn = m => console.log(`  ${Y}!${NC} ${m}`);
const sep = () => console.log(`\n  ${DIM}${'─'.repeat(48)}${NC}`);

const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
const ask = q => new Promise(res => rl.question(q, res));

// Hidden input for passwords: readline still collects keystrokes, we just
// suppress the echo while the prompt is active.
function askHidden(q) {
  return new Promise(res => {
    const orig = rl._writeToOutput;
    rl.question(q, answer => {
      rl._writeToOutput = orig;
      process.stdout.write('\n');
      res(answer);
    });
    rl._writeToOutput = function (s) {
      // Echo the prompt itself, mask everything typed after it.
      if (s.startsWith(q)) process.stdout.write(q);
    };
  });
}

function lanIps() {
  const out = [];
  for (const ifaces of Object.values(require('os').networkInterfaces())) {
    for (const i of ifaces || []) {
      if (i.family === 'IPv4' && !i.internal) out.push(i.address);
    }
  }
  return out;
}

function port() {
  return parseInt(process.env.PORT, 10) || 7005;
}

// ── Step 1: admin account ──────────────────────────────────────────────────
async function stepAdmin() {
  console.log(`\n  ${W}Step 1 — Admin account${NC}`);
  console.log(`  ${DIM}The only login for the web dashboard.${NC}\n`);

  if (users.hasAdmin()) {
    const keep = (await ask(`  ${Y}An admin account already exists. Keep it? [Y/n]: ${NC}`)).trim().toLowerCase();
    if (keep !== 'n') { ok('Keeping existing admin account'); return; }
  }

  let username = '';
  while (!username) {
    username = (await ask(`  Username ${DIM}[admin]${NC}: `)).trim() || 'admin';
    if (!/^[a-zA-Z0-9._-]{3,32}$/.test(username)) {
      console.log(`  ${R}3–32 characters: letters, digits, . _ -${NC}`);
      username = '';
    }
  }

  let password = '';
  while (!password) {
    const p1 = await askHidden('  Password (min 8 chars, hidden): ');
    if (p1.length < 8) { console.log(`  ${R}At least 8 characters${NC}`); continue; }
    const p2 = await askHidden('  Confirm password: ');
    if (p1 !== p2) { console.log(`  ${R}Passwords do not match${NC}`); continue; }
    password = p1;
  }

  users.resetAdmin(username, password);
  ok(`Admin account '${username}' saved to the encrypted store`);
}

// ── Step 2: access mode ────────────────────────────────────────────────────
async function stepAccessMode() {
  sep();
  console.log(`\n  ${W}Step 2 — How should StreamVault be reached?${NC}\n`);
  console.log(`  ${C}1${NC}  Own public IP / domain  ${DIM}You have a public/static IP and can port-forward. Direct, no third party.${NC}`);
  console.log(`  ${C}2${NC}  Cloudflare Tunnel       ${DIM}No public IP or no port-forwarding (works behind CGNAT).${NC}`);
  console.log(`  ${C}3${NC}  Local only (LAN/Tailscale)  ${DIM}No public exposure at all.${NC}`);

  let mode = '';
  while (!['1', '2', '3'].includes(mode)) mode = (await ask('\n  › ')).trim();

  if (mode === '1') return modePublicIp();
  if (mode === '2') return modeCloudflare();
  return modeLocal();
}

async function modePublicIp() {
  console.log(`\n  ${W}${C}Own public IP / domain${NC}\n`);
  let host = '';
  while (!host) {
    host = (await ask(`  Public IP or domain ${DIM}(e.g. 203.0.113.7 or vault.example.com)${NC}: `)).trim();
    if (!/^[a-zA-Z0-9.:\-\[\]]+$/.test(host)) { console.log(`  ${R}That does not look like an IP or domain${NC}`); host = ''; }
  }
  let p = 0;
  while (!p) {
    const inp = (await ask(`  Port to expose ${DIM}[${port()}]${NC}: `)).trim() || String(port());
    p = parseInt(inp, 10);
    if (!Number.isFinite(p) || p < 1 || p > 65535) { console.log(`  ${R}1–65535${NC}`); p = 0; }
  }
  const httpsIn = (await ask(`  HTTPS? (only if a reverse proxy terminates TLS) [y/N]: `)).trim().toLowerCase();
  const scheme = httpsIn === 'y' ? 'https' : 'http';
  const defaultPort = scheme === 'https' ? 443 : 80;
  const base = `${scheme}://${host}${p === defaultPort ? '' : `:${p}`}`;

  envFile.writeEnvUpdates({ PUBLIC_BASE_URL: base, CF_DOMAIN: '' });
  secrets.set({ CF_TUNNEL_TOKEN: '' });
  ok(`Public base URL set to ${base}`);
  warn(`If this server is behind a router, forward TCP port ${p} to this machine,`);
  console.log(`    or Stremio won't reach it from outside. A domain must already point at your IP.`);
  return base;
}

async function modeCloudflare() {
  console.log(`\n  ${W}${C}Cloudflare Tunnel${NC}\n`);
  console.log(`  ${DIM}In Cloudflare Zero Trust → Networks → Tunnels:${NC}`);
  console.log(`  ${DIM}1. Create a tunnel and copy the connector token${NC}`);
  console.log(`  ${DIM}2. Add a public hostname pointing at http://localhost:${port()}${NC}\n`);

  let token = '';
  while (!token) {
    token = (await askHidden('  Tunnel token (hidden): ')).trim();
    if (token.length < 32) { console.log(`  ${R}That is too short to be a tunnel token${NC}`); token = ''; }
  }
  let domain = '';
  while (!domain) {
    domain = (await ask(`  Public hostname ${DIM}(e.g. vault.example.com)${NC}: `)).trim().toLowerCase();
    if (!/^[a-z0-9.-]+\.[a-z]{2,}$/.test(domain)) { console.log(`  ${R}Enter a hostname like vault.example.com${NC}`); domain = ''; }
  }

  console.log(`\n  ${DIM}Checking cloudflared and validating the token…${NC}`);
  try {
    await cloudflared.start(token); // downloads the binary into bin/ if missing
    cloudflared.stop();             // the systemd service resumes it on start
  } catch (err) {
    throw new Error(`Tunnel failed to start: ${err.message}`);
  }

  secrets.set({ CF_TUNNEL_TOKEN: token });
  const base = `https://${domain}`;
  envFile.writeEnvUpdates({ PUBLIC_BASE_URL: base, CF_DOMAIN: domain });
  ok('Tunnel token verified and stored encrypted');
  ok(`Public base URL set to ${base} — the tunnel starts with the service`);
  return base;
}

async function modeLocal() {
  console.log(`\n  ${W}${C}Local only (LAN / Tailscale)${NC}\n`);
  const detected = lanIps()[0] || '';
  let ip = '';
  while (!ip) {
    ip = (await ask(`  LAN IP of this machine ${DIM}[${detected || 'none detected'}]${NC}: `)).trim() || detected;
    if (!ip) { console.log(`  ${R}Enter the machine's LAN IP${NC}`); continue; }
    if (!/^[0-9a-fA-F.:]+$/.test(ip)) { console.log(`  ${R}That does not look like an IP address${NC}`); ip = ''; }
  }
  envFile.writeEnvUpdates({ PUBLIC_BASE_URL: '', CF_DOMAIN: '', NAS_LOCAL_IP: ip });
  secrets.set({ CF_TUNNEL_TOKEN: '' });
  ok(`LAN-only mode — nothing is exposed to the internet`);
  warn('For remote access without exposure, put this machine on Tailscale and use its Tailscale IP.');
  return `http://${ip}:${port()}`;
}

// ── Main ───────────────────────────────────────────────────────────────────
async function main() {
  console.log(`\n  ${C}${W}╔══════════════════════════════════════════╗${NC}`);
  console.log(`  ${C}${W}║   StreamVault — Terminal Setup           ║${NC}`);
  console.log(`  ${C}${W}╚══════════════════════════════════════════╝${NC}`);

  if (!process.stdin.isTTY) {
    console.error(`\n  ${R}✗ Not an interactive terminal.${NC} Run this over SSH/console:\n` +
      `    sudo bash install.sh --reconfigure   (installed systems)\n` +
      `    npm run setup                        (manual installs)\n`);
    process.exit(1);
  }

  await stepAdmin();
  const base = await stepAccessMode();

  sep();
  console.log(`\n  ${G}${W}Setup complete.${NC}\n`);
  console.log(`  Log in to the dashboard:  ${C}${base}${NC}`);
  console.log(`  ${DIM}Then add your TorBox API key on the Settings page,${NC}`);
  console.log(`  ${DIM}and create profiles to get Stremio manifest URLs.${NC}\n`);
  console.log(`  ${DIM}If the service is running, restart it to pick up the changes:${NC}`);
  console.log(`  ${C}sudo systemctl restart streamvault${NC}\n`);
  rl.close();
}

main().catch(err => {
  console.error(`\n  ${R}✗ ${err.message}${NC}\n`);
  rl.close();
  process.exit(1);
});

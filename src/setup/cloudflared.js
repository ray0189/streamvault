// src/setup/cloudflared.js — install + supervise a Cloudflare Tunnel connector.
//
// The connector runs as a child process of the app (no root, no systemd unit
// needed): the wizard stores the tunnel token in the encrypted secrets vault,
// and on every boot the server restarts the tunnel if a token is present.
// If the cloudflared binary is missing we download the official static build
// into <repo>/bin/, which works from an unprivileged service account.

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawn, execFileSync } = require('child_process');
const axios = require('axios');

const BIN_DIR = path.join(__dirname, '../../bin');
const LOCAL_BIN = path.join(BIN_DIR, 'cloudflared');

let child = null;
let lastError = '';

function findBinary() {
  if (fs.existsSync(LOCAL_BIN)) return LOCAL_BIN;
  try {
    return execFileSync('which', ['cloudflared'], { encoding: 'utf8' }).trim() || null;
  } catch {
    return null;
  }
}

function downloadUrl() {
  const arch = { x64: 'amd64', arm64: 'arm64', arm: 'arm' }[os.arch()];
  if (os.platform() !== 'linux' || !arch) return null;
  return `https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${arch}`;
}

async function ensureInstalled() {
  const existing = findBinary();
  if (existing) return existing;
  const url = downloadUrl();
  if (!url) throw new Error(`No cloudflared build for ${os.platform()}/${os.arch()} — install it manually`);
  fs.mkdirSync(BIN_DIR, { recursive: true });
  console.log(`[Tunnel] Downloading cloudflared from ${url}`);
  const res = await axios.get(url, { responseType: 'arraybuffer', timeout: 120000, maxRedirects: 5 });
  const tmp = `${LOCAL_BIN}.tmp`;
  fs.writeFileSync(tmp, Buffer.from(res.data), { mode: 0o755 });
  fs.renameSync(tmp, LOCAL_BIN);
  return LOCAL_BIN;
}

function isRunning() {
  return !!(child && child.exitCode === null);
}

async function start(token) {
  if (!token) throw new Error('No tunnel token provided');
  const bin = await ensureInstalled();
  stop();
  lastError = '';
  child = spawn(bin, ['tunnel', 'run', '--token', token], { stdio: ['ignore', 'pipe', 'pipe'] });
  child.stdout.on('data', d => process.env.DEBUG_TUNNEL && console.log(`[Tunnel] ${d}`.trim()));
  child.stderr.on('data', d => {
    const line = String(d).trim();
    if (/error|failed/i.test(line)) lastError = line.slice(0, 300);
    if (process.env.DEBUG_TUNNEL) console.log(`[Tunnel] ${line}`);
  });
  child.on('exit', (code) => {
    console.warn(`[Tunnel] cloudflared exited (code ${code})`);
    // Backoff-restart while a token is still configured.
    const stillWanted = child && !child.killedByUs;
    child = null;
    if (stillWanted && code !== 0) {
      setTimeout(() => {
        const secrets = require('../config/secrets');
        const t = secrets.get('CF_TUNNEL_TOKEN');
        if (t) start(t).catch(err => console.error(`[Tunnel] Restart failed: ${err.message}`));
      }, 10000);
    }
  });
  // Give it a moment to fail fast on a bad token.
  await new Promise(r => setTimeout(r, 3000));
  if (!isRunning()) throw new Error(lastError || 'cloudflared exited immediately — check the token');
  console.log('[Tunnel] cloudflared connector running');
}

function stop() {
  if (child) {
    child.killedByUs = true;
    child.kill('SIGTERM');
    child = null;
  }
}

function status() {
  return { installed: !!findBinary(), running: isRunning(), lastError };
}

// Called from server boot: resume the tunnel if a token was configured.
function resumeIfConfigured() {
  const secrets = require('../config/secrets');
  const token = secrets.get('CF_TUNNEL_TOKEN');
  if (token) {
    start(token).catch(err => console.error(`[Tunnel] Could not start tunnel: ${err.message}`));
  }
}

module.exports = { ensureInstalled, start, stop, status, resumeIfConfigured };

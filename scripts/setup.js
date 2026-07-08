#!/usr/bin/env node
// scripts/setup.js — interactive first-run setup for the simple .env-based NAS model.

const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const readline = require('readline');

const ROOT = path.join(__dirname, '..');
const ENV_PATH = path.join(ROOT, '.env');
const EXAMPLE_PATH = path.join(ROOT, '.env.example');

const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
const ask = q => new Promise(resolve => rl.question(q, resolve));

function readEnv(file) {
  const values = {};
  if (!fs.existsSync(file)) return values;
  for (const line of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
    if (!line.trim() || line.trim().startsWith('#')) continue;
    const idx = line.indexOf('=');
    if (idx === -1) continue;
    values[line.slice(0, idx).trim()] = line.slice(idx + 1);
  }
  return values;
}

function writeEnv(values) {
  const order = [
    ['# StreamVault — Environment'],
    ['PORT'], ['HOST'], ['NODE_ENV'], [''],
    ['# TorBox'],
    ['TORBOX_API_KEY'], ['TORBOX_API_URL'], ['TORBOX_SEARCH_API_URL'],
    ['TORBOX_TIMEOUT_MS'], ['TORBOX_RETRIES'],
    ['TORBOX_ENABLE_NATIVE_SEARCH'], ['TORBOX_ENABLE_USENET'], ['TORBOX_SEARCH_USER_ENGINES'],
    ['TORBOX_PROVIDER_PRIORITY'], ['EXTERNAL_TORRENT_FALLBACK'], ['TORRENTIO_ENABLED'], ['KNIGHTCRAWLER_ENABLED'], [''],
    ['# Dashboard admin'],
    ['ADMIN_PASSWORD'], ['SECRET_KEY'], [''],
    ['# Access URLs'],
    ['PUBLIC_BASE_URL'], ['NAS_LOCAL_IP'], ['TAILSCALE_HOST'], [''],
    ['# Redis / cache'],
    ['REDIS_URL'], ['STREAM_CACHE_TTL'], ['META_CACHE_TTL'], [''],
    ['# Profile defaults'],
    ['DEFAULT_MIN_QUALITY'], ['DEFAULT_CACHED_ONLY'], ['DEFAULT_LANGUAGE'], [''],
    ['# Cloudflare tunnel, optional'],
    ['CF_TUNNEL_TOKEN'], ['CF_DOMAIN'],
  ];

  const seen = new Set();
  const lines = [];
  for (const entry of order) {
    const key = entry[0];
    if (key === '') { lines.push(''); continue; }
    if (key.startsWith('#')) { lines.push(key); continue; }
    seen.add(key);
    lines.push(`${key}=${values[key] ?? ''}`);
  }
  for (const key of Object.keys(values).sort()) {
    if (!seen.has(key)) lines.push(`${key}=${values[key]}`);
  }
  fs.writeFileSync(ENV_PATH, lines.join('\n') + '\n', { mode: 0o600 });
}

function firstLanIp() {
  for (const ifaces of Object.values(os.networkInterfaces())) {
    for (const i of ifaces || []) {
      if (i.family === 'IPv4' && !i.internal) return i.address;
    }
  }
  return '';
}

async function prompt(label, fallback = '', required = false) {
  const suffix = fallback ? ` [${fallback}]` : '';
  while (true) {
    const value = (await ask(`${label}${suffix}: `)).trim();
    const out = value || fallback;
    if (!required || out) return out;
    console.log('  Required.');
  }
}


function warnPublicBaseUrl(baseUrl, portValue) {
  const raw = String(baseUrl || '').trim();
  if (!raw) return;
  try {
    const u = new URL(raw);
    const hostLooksLikeIp = /^\d+\.\d+\.\d+\.\d+$/.test(u.hostname) || u.hostname.includes(':');
    if (u.protocol === 'https:') {
      console.log('\n  HTTPS note: StreamVault serves plain HTTP locally. Use Caddy/Nginx to terminate HTTPS');
      console.log(`  and reverse_proxy to http://127.0.0.1:${portValue || '7005'}.`);
      if (hostLooksLikeIp) {
        console.log('  Warning: trusted public certificates are normally for domain names, not bare IP addresses.');
      }
    } else if (u.protocol === 'http:') {
      console.log('\n  HTTP note: Stremio iOS may fail before reaching StreamVault over plain HTTP.');
      console.log('  Use a trusted HTTPS hostname, e.g. DuckDNS + Caddy, for iOS installs.');
    }
  } catch {
    console.log('\n  Public base URL warning: enter a full URL like https://vault.example.com:8444');
  }
}

async function main() {
  console.log('\n╔══════════════════════════════════════════╗');
  console.log('║   StreamVault — First Run Setup          ║');
  console.log('╚══════════════════════════════════════════╝\n');

  const defaults = {
    ...readEnv(EXAMPLE_PATH),
    ...readEnv(ENV_PATH),
  };

  const values = { ...defaults };
  values.PORT = await prompt('Port', values.PORT || '7005');
  values.HOST = values.HOST || '0.0.0.0';
  values.NODE_ENV = values.NODE_ENV || 'production';

  values.TORBOX_API_KEY = await prompt('TorBox API key', values.TORBOX_API_KEY || '', true);
  values.TORBOX_API_URL = values.TORBOX_API_URL || 'https://api.torbox.app/v1/api';
  values.TORBOX_SEARCH_API_URL = values.TORBOX_SEARCH_API_URL || 'https://search-api.torbox.app';
  values.TORBOX_TIMEOUT_MS = values.TORBOX_TIMEOUT_MS || '10000';
  values.TORBOX_RETRIES = values.TORBOX_RETRIES || '2';
  values.TORBOX_ENABLE_NATIVE_SEARCH = values.TORBOX_ENABLE_NATIVE_SEARCH || 'true';
  values.TORBOX_ENABLE_USENET = values.TORBOX_ENABLE_USENET || 'true';
  values.TORBOX_SEARCH_USER_ENGINES = values.TORBOX_SEARCH_USER_ENGINES || 'false';
  values.TORBOX_PROVIDER_PRIORITY = values.TORBOX_PROVIDER_PRIORITY || 'torbox-torrent,torbox-usenet,library,torrentio,knightcrawler';
  values.EXTERNAL_TORRENT_FALLBACK = values.EXTERNAL_TORRENT_FALLBACK || 'true';
  values.TORRENTIO_ENABLED = values.TORRENTIO_ENABLED || 'true';
  values.KNIGHTCRAWLER_ENABLED = values.KNIGHTCRAWLER_ENABLED || 'true';

  values.ADMIN_PASSWORD = await prompt('Admin dashboard password', values.ADMIN_PASSWORD || '', true);
  values.SECRET_KEY = values.SECRET_KEY && values.SECRET_KEY !== 'change-me'
    ? values.SECRET_KEY
    : crypto.randomBytes(32).toString('hex');

  values.NAS_LOCAL_IP = await prompt('NAS/server local IP', values.NAS_LOCAL_IP || firstLanIp() || '127.0.0.1');
  values.PUBLIC_BASE_URL = await prompt('Public base URL (domain/reverse proxy, blank okay)', values.PUBLIC_BASE_URL || '');
  warnPublicBaseUrl(values.PUBLIC_BASE_URL, values.PORT);
  values.TAILSCALE_HOST = await prompt('Tailscale hostname/IP (blank okay)', values.TAILSCALE_HOST || '');

  values.REDIS_URL = values.REDIS_URL || 'redis://127.0.0.1:6379';
  values.STREAM_CACHE_TTL = values.STREAM_CACHE_TTL || '1800';
  values.META_CACHE_TTL = values.META_CACHE_TTL || '7200';
  values.DEFAULT_MIN_QUALITY = await prompt('Default minimum quality', values.DEFAULT_MIN_QUALITY || '1080p');
  values.DEFAULT_CACHED_ONLY = await prompt('Cached only by default? true/false', values.DEFAULT_CACHED_ONLY || 'true');
  values.DEFAULT_LANGUAGE = await prompt('Default language', values.DEFAULT_LANGUAGE || 'en');
  values.CF_TUNNEL_TOKEN = values.CF_TUNNEL_TOKEN || '';
  values.CF_DOMAIN = values.CF_DOMAIN || '';

  fs.mkdirSync(path.join(ROOT, 'data'), { recursive: true });
  fs.mkdirSync(path.join(ROOT, 'logs'), { recursive: true });
  writeEnv(values);

  const base = (values.PUBLIC_BASE_URL || `http://${values.NAS_LOCAL_IP}:${values.PORT}`).replace(/\/$/, '');
  console.log('\n✅ .env written.');
  console.log(`Dashboard: ${base}/`);
  console.log(`Manifest example: ${base}/config/<profile-id>/manifest.json\n`);
  rl.close();
}

main().catch(err => {
  console.error(err);
  rl.close();
  process.exit(1);
});

// src/config/env-file.js — read/write the repo-root .env file in place.
// Preserves comments and line order; only touches lines for keys being updated.
// Also mirrors every write onto process.env so already-running code that reads
// process.env.X live (rather than a constant destructured at require-time) sees
// the change immediately. Constants destructured elsewhere (e.g. router.js's
// ADMIN_PASSWORD) will NOT pick this up until the process restarts.

const fs = require('fs');
const path = require('path');

const ENV_PATH = path.join(__dirname, '../../.env');

function readEnvFile() {
  let raw = '';
  try {
    raw = fs.readFileSync(ENV_PATH, 'utf8');
  } catch {
    raw = '';
  }
  const values = {};
  for (const line of raw.split('\n')) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eq = trimmed.indexOf('=');
    if (eq === -1) continue;
    values[trimmed.slice(0, eq).trim()] = trimmed.slice(eq + 1).trim();
  }
  return { raw, values };
}

function writeEnvUpdates(updates) {
  const { raw } = readEnvFile();
  const lines = raw ? raw.split('\n') : [];
  const seen = new Set();

  for (let i = 0; i < lines.length; i++) {
    const trimmed = lines[i].trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eq = trimmed.indexOf('=');
    if (eq === -1) continue;
    const key = trimmed.slice(0, eq).trim();
    if (Object.prototype.hasOwnProperty.call(updates, key)) {
      lines[i] = `${key}=${updates[key]}`;
      seen.add(key);
    }
  }

  for (const key of Object.keys(updates)) {
    if (!seen.has(key)) {
      if (lines.length && lines[lines.length - 1].trim() !== '') lines.push('');
      lines.push(`${key}=${updates[key]}`);
    }
  }

  fs.writeFileSync(ENV_PATH, lines.join('\n'));

  for (const [key, value] of Object.entries(updates)) {
    process.env[key] = String(value);
  }
}

module.exports = { ENV_PATH, readEnvFile, writeEnvUpdates };

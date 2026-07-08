// src/config/secrets.js — encrypted store for API credentials (data/secrets.db).
//
// Secrets never live in .env. At boot, loadIntoEnv() decrypts the vault and
// mirrors each value onto process.env BEFORE config/env.js is required, so
// every existing module (torbox.js etc.) keeps reading its config unchanged.
// Writes go back to the vault and are mirrored live onto process.env.

const vault = require('../auth/vault');

const FILE = 'secrets.db';

// The full set of env keys that must live in the vault, not .env.
const SECRET_ENV_KEYS = ['TORBOX_API_KEY', 'CF_TUNNEL_TOKEN'];

function readAll() {
  try {
    return vault.load(FILE);
  } catch (err) {
    console.error(`[Secrets] Cannot read secrets vault: ${err.message}`);
    return {};
  }
}

function loadIntoEnv() {
  const secrets = readAll();
  for (const key of SECRET_ENV_KEYS) {
    if (secrets[key]) process.env[key] = secrets[key];
  }
}

function get(key) {
  return readAll()[key] || '';
}

function set(updates) {
  const secrets = readAll();
  for (const [key, value] of Object.entries(updates)) {
    if (!SECRET_ENV_KEYS.includes(key)) throw new Error(`${key} is not a managed secret`);
    if (value === '' || value === null) {
      delete secrets[key];
      delete process.env[key];
    } else {
      secrets[key] = String(value);
      process.env[key] = String(value);
    }
  }
  vault.save(FILE, secrets);
}

function isSecretEnvKey(key) {
  return SECRET_ENV_KEYS.includes(key);
}

module.exports = { SECRET_ENV_KEYS, loadIntoEnv, get, set, isSecretEnvKey };

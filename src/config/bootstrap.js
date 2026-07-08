// src/config/bootstrap.js — must run before any other config module.
// Guarantees a real SECRET_KEY exists (the vaults and sessions depend on it):
// the installer normally writes one, but a bare `npm start` on a fresh clone
// gets a generated key persisted to .env so first run still works.

const crypto = require('crypto');
const envFile = require('./env-file');

function ensureSecretKey() {
  if (process.env.SECRET_KEY && process.env.SECRET_KEY !== 'change-me') return;
  const fromFile = envFile.readEnvFile().values.SECRET_KEY;
  if (fromFile && fromFile !== 'change-me') {
    process.env.SECRET_KEY = fromFile;
    return;
  }
  const key = crypto.randomBytes(32).toString('hex');
  envFile.writeEnvUpdates({ SECRET_KEY: key });
  console.log('[Bootstrap] Generated a new SECRET_KEY and saved it to .env');
}

module.exports = { ensureSecretKey };

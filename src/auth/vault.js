// src/auth/vault.js — encrypted-at-rest JSON file store.
//
// Each vault file (data/auth.db, data/secrets.db) is a JSON envelope holding
// an AES-256-GCM ciphertext of a JSON object. The encryption key is derived
// from SECRET_KEY with scrypt and a per-file random salt, so the files are
// useless without the .env on the same machine.
//
// SECRET_KEY is read lazily from process.env on every operation (not from
// config/env.js) so vault code works before the config module is loaded.

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const DATA_DIR = path.join(__dirname, '../../data');

function secretKey() {
  const k = process.env.SECRET_KEY;
  if (!k || k === 'change-me') {
    throw new Error('SECRET_KEY is not set — required to encrypt local credential stores');
  }
  return k;
}

function deriveKey(salt) {
  return crypto.scryptSync(secretKey(), salt, 32);
}

function vaultPath(name) {
  return path.join(DATA_DIR, name);
}

function load(name) {
  const file = vaultPath(name);
  let raw;
  try {
    raw = fs.readFileSync(file, 'utf8');
  } catch {
    return {};
  }
  const env = JSON.parse(raw);
  if (env.v !== 1) throw new Error(`${name}: unsupported vault version ${env.v}`);
  const salt = Buffer.from(env.salt, 'base64');
  const iv = Buffer.from(env.iv, 'base64');
  const tag = Buffer.from(env.tag, 'base64');
  const decipher = crypto.createDecipheriv('aes-256-gcm', deriveKey(salt), iv);
  decipher.setAuthTag(tag);
  const plain = Buffer.concat([decipher.update(Buffer.from(env.data, 'base64')), decipher.final()]);
  return JSON.parse(plain.toString('utf8'));
}

function save(name, obj) {
  fs.mkdirSync(DATA_DIR, { recursive: true });
  const salt = crypto.randomBytes(16);
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', deriveKey(salt), iv);
  const data = Buffer.concat([cipher.update(JSON.stringify(obj), 'utf8'), cipher.final()]);
  const envlope = {
    v: 1,
    salt: salt.toString('base64'),
    iv: iv.toString('base64'),
    tag: cipher.getAuthTag().toString('base64'),
    data: data.toString('base64'),
  };
  const file = vaultPath(name);
  const tmp = `${file}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(envlope), { mode: 0o600 });
  fs.renameSync(tmp, file);
}

function exists(name) {
  return fs.existsSync(vaultPath(name));
}

module.exports = { load, save, exists };

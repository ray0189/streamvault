// src/auth/users.js — admin credential store (data/auth.db, encrypted vault).
// A single admin account created by the first-run wizard. Passwords are
// bcrypt-hashed before encryption, so even a decrypted vault never exposes
// the plaintext password.

const bcrypt = require('bcryptjs');
const vault = require('./vault');

const FILE = 'auth.db';
const BCRYPT_ROUNDS = 12;

function read() {
  return vault.load(FILE);
}

function hasAdmin() {
  try {
    const db = read();
    return !!(db.admin && db.admin.username && db.admin.passwordHash);
  } catch {
    // Unreadable vault (e.g. SECRET_KEY changed) — treat as no admin so the
    // operator can re-run setup rather than being locked out forever.
    return false;
  }
}

function createAdmin(username, password) {
  if (hasAdmin()) throw new Error('Admin account already exists');
  return resetAdmin(username, password);
}

// Overwrites any existing admin — used by the terminal wizard when the
// operator explicitly chooses to replace the account.
function resetAdmin(username, password) {
  const u = String(username || '').trim();
  if (!/^[a-zA-Z0-9._-]{3,32}$/.test(u)) {
    throw new Error('Username must be 3–32 characters (letters, digits, . _ -)');
  }
  if (typeof password !== 'string' || password.length < 8) {
    throw new Error('Password must be at least 8 characters');
  }
  vault.save(FILE, {
    admin: {
      username: u,
      passwordHash: bcrypt.hashSync(password, BCRYPT_ROUNDS),
      createdAt: new Date().toISOString(),
    },
  });
  return { username: u };
}

function verifyLogin(username, password) {
  if (!hasAdmin()) return null;
  const { admin } = read();
  const userOk = cryptoSafeEqual(String(username || '').trim(), admin.username);
  // Always run the bcrypt compare so response timing doesn't leak whether the
  // username was right.
  const passOk = bcrypt.compareSync(String(password || ''), admin.passwordHash);
  return userOk && passOk ? { username: admin.username } : null;
}

function changePassword(currentPassword, newPassword) {
  const db = read();
  if (!db.admin) throw new Error('No admin account');
  if (!bcrypt.compareSync(String(currentPassword || ''), db.admin.passwordHash)) {
    throw new Error('Current password is incorrect');
  }
  if (typeof newPassword !== 'string' || newPassword.length < 8) {
    throw new Error('New password must be at least 8 characters');
  }
  db.admin.passwordHash = bcrypt.hashSync(newPassword, BCRYPT_ROUNDS);
  db.admin.updatedAt = new Date().toISOString();
  vault.save(FILE, db);
}

function cryptoSafeEqual(a, b) {
  const crypto = require('crypto');
  const ba = Buffer.from(String(a));
  const bb = Buffer.from(String(b));
  if (ba.length !== bb.length) return false;
  return crypto.timingSafeEqual(ba, bb);
}

module.exports = { hasAdmin, createAdmin, resetAdmin, verifyLogin, changePassword };

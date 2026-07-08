// src/auth/users.js — simple .env-backed admin auth for the working NAS model.
//
// The dashboard still uses /api/auth/login and signed sessions, but credentials
// are read from .env instead of data/auth.db. Username is deliberately flexible
// so existing installs can log in with admin/rayyan/etc.; the password is the
// ADMIN_PASSWORD value from .env.

const fs = require('fs');
const path = require('path');
const envFile = require('../config/env-file');

function currentPassword() {
  const fileVal = envFile.readEnvFile().values.ADMIN_PASSWORD;
  return process.env.ADMIN_PASSWORD || fileVal || '';
}

function currentUsername(fallback = 'admin') {
  const fileVal = envFile.readEnvFile().values.ADMIN_USERNAME;
  return process.env.ADMIN_USERNAME || fileVal || fallback;
}

function hasAdmin() {
  return !!currentPassword();
}

function resetAdmin(username, password) {
  const u = String(username || 'admin').trim() || 'admin';
  if (!/^[a-zA-Z0-9._-]{3,32}$/.test(u)) {
    throw new Error('Username must be 3–32 characters (letters, digits, . _ -)');
  }
  if (typeof password !== 'string' || password.length < 4) {
    throw new Error('Password must be at least 4 characters');
  }
  envFile.writeEnvUpdates({ ADMIN_USERNAME: u, ADMIN_PASSWORD: password });
  return { username: u };
}

function createAdmin(username, password) {
  return resetAdmin(username, password);
}

function verifyLogin(username, password) {
  const configuredPassword = currentPassword();
  if (!configuredPassword) return null;
  const suppliedPassword = String(password || '');
  if (suppliedPassword !== configuredPassword) return null;

  const suppliedUsername = String(username || '').trim();
  return { username: suppliedUsername || currentUsername() };
}

function changePassword(currentPasswordInput, newPassword) {
  if (String(currentPasswordInput || '') !== currentPassword()) {
    throw new Error('Current password is incorrect');
  }
  if (typeof newPassword !== 'string' || newPassword.length < 4) {
    throw new Error('New password must be at least 4 characters');
  }
  envFile.writeEnvUpdates({ ADMIN_PASSWORD: newPassword });
}

module.exports = { hasAdmin, createAdmin, resetAdmin, verifyLogin, changePassword };

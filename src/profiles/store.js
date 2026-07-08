// src/profiles/store.js
// Lightweight file-based profile store (no DB required)
// Profiles live in profiles.json next to this file

const fs   = require('fs');
const path = require('path');
const { v4: uuidv4 } = require('uuid');
const defaults = require('../config/defaults');

const STORE_PATH = path.join(__dirname, '../../data/profiles.json');

// ── Helpers ───────────────────────────────────────────────────

function ensureDataDir() {
  const dir = path.dirname(STORE_PATH);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
}

function load() {
  ensureDataDir();
  if (!fs.existsSync(STORE_PATH)) return {};
  try {
    return JSON.parse(fs.readFileSync(STORE_PATH, 'utf8'));
  } catch {
    return {};
  }
}

function save(profiles) {
  ensureDataDir();
  fs.writeFileSync(STORE_PATH, JSON.stringify(profiles, null, 2));
}

// ── Public API ────────────────────────────────────────────────

/**
 * Create a new profile and return its configId
 */
function createProfile(name = 'Default', overrides = {}) {
  const profiles = load();
  const configId = uuidv4();
  profiles[configId] = {
    configId,
    name,
    createdAt: new Date().toISOString(),
    prefs: { ...defaults, ...overrides },
  };
  save(profiles);
  return configId;
}

/**
 * Get a single profile by configId
 */
function getProfile(configId) {
  return load()[configId] || null;
}

/**
 * List all profiles
 */
function listProfiles() {
  return Object.values(load());
}

/**
 * Update prefs for a given configId
 */
function updateProfile(configId, updates) {
  const profiles = load();
  if (!profiles[configId]) return null;
  profiles[configId].prefs = { ...profiles[configId].prefs, ...updates };
  profiles[configId].updatedAt = new Date().toISOString();
  save(profiles);
  return profiles[configId];
}

/**
 * Delete a profile
 */
function deleteProfile(configId) {
  const profiles = load();
  if (!profiles[configId]) return false;
  delete profiles[configId];
  save(profiles);
  return true;
}

module.exports = { createProfile, getProfile, listProfiles, updateProfile, deleteProfile };

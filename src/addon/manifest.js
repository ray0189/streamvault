// src/addon/manifest.js — builds the Stremio manifest for a given profile

const { PORT, NAS_LOCAL_IP, TAILSCALE_HOST } = require('../config/env');

function buildManifest(profile) {
  const { configId, name, prefs } = profile;

  const qualityNote = [
    prefs.minQuality || '1080p',
    prefs.cachedOnly ? 'Cached Only' : 'All',
    prefs.scoring?.hevc > 0 ? 'HEVC Pref' : '',
    prefs.scoring?.dolbyVision > 0 ? 'DV Pref' : '',
  ].filter(Boolean).join(' · ');

  return {
    id:          `community.private.torbox.${configId}`,
    version:     '1.0.0',
    name:        `⚡ ${name}`,
    description: `Private TorBox addon — ${qualityNote}`,
    logo:        '',

    // Resources this addon provides
    resources:   ['stream'],

    // Content types
    types:       ['movie', 'series'],

    // Stremio uses IMDb IDs
    idPrefixes:  ['tt'],

    // Behaviour hints
    behaviorHints: {
      adult:           false,
      p2p:             false,
      configurable:    false,
      configurationRequired: false,
    },

    // Optional: where the user can manage this config
    // (points to your NAS dashboard)
    contactEmail: '',

    // Useful for debugging
    _meta: {
      configId,
      profile: name,
      generatedAt: new Date().toISOString(),
      endpoints: {
        lan:       NAS_LOCAL_IP ? `http://${NAS_LOCAL_IP}:${PORT}` : null,
        tailscale: TAILSCALE_HOST ? `http://${TAILSCALE_HOST}:${PORT}` : null,
      },
    },
  };
}

module.exports = { buildManifest };

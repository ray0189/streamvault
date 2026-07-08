// src/setup/routes.js — first-run gate.
//
// Setup is done in the terminal (scripts/setup.js, run by install.sh or
// `streamvault setup`), never in the browser. Until an admin account exists,
// the web UI serves a "run setup on the server" notice and the API returns
// 503 — there is no web wizard to find or abuse.

const express = require('express');
const users = require('../auth/users');

const router = express.Router();

function isFirstRun() {
  return !users.hasAdmin();
}

const SETUP_NOTICE = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1.0"/>
<title>StreamVault — Setup required</title>
<style>
  body { margin:0; min-height:100vh; display:flex; align-items:center; justify-content:center;
         background:#0d1117; color:#e6edf3; font:15px/1.6 -apple-system, 'Segoe UI', sans-serif; }
  .card { max-width:520px; padding:36px; border:1px solid #30363d; border-radius:12px; background:#161b22; }
  h1 { font-size:20px; margin:0 0 10px; }
  p { opacity:.85; margin:0 0 14px; }
  code { display:block; padding:10px 14px; margin:6px 0; background:#0d1117; border:1px solid #30363d;
         border-radius:8px; font:13px 'SF Mono', Menlo, monospace; color:#79c0ff; }
  .dim { opacity:.6; font-size:13px; }
</style>
</head>
<body>
<div class="card">
  <h1>Setup hasn't been run yet</h1>
  <p>StreamVault is installed but has no admin account. Setup happens in the
     terminal on the server, not in the browser.</p>
  <p>SSH into the server and run one of:</p>
  <code>sudo bash install.sh --reconfigure</code>
  <code>streamvault setup</code>
  <p class="dim">The wizard creates the admin login and configures how this
     server is reached. Refresh this page when it's done.</p>
</div>
</body>
</html>`;

// Static assets (CSS/JS/fonts/images) that must always be served, otherwise a
// browser holding a cached dashboard shell during first run would render it
// unstyled. Matched by extension so express.static can handle them.
const STATIC_ASSET_RE = /\.(css|js|mjs|map|svg|png|jpe?g|gif|ico|webp|woff2?|ttf|eot)$/i;

// Mounted in server.js ahead of every other route. During first run only
// /health and static assets respond normally; browsers get the notice for
// page requests, API clients get 503.
function firstRunGate(req, res, next) {
  if (!isFirstRun()) return next();
  if (req.path === '/health') return next();
  // Let static assets fall through to express.static — never gate them, so
  // the notice page (and any cached shell) can style itself.
  if (req.method === 'GET' && STATIC_ASSET_RE.test(req.path)) return next();
  if (req.method === 'GET' && (req.headers.accept || '').includes('text/html')) {
    return res.status(503).send(SETUP_NOTICE);
  }
  return res.status(503).json({ error: 'Setup not complete — run `streamvault setup` on the server' });
}

module.exports = { router, isFirstRun, firstRunGate };

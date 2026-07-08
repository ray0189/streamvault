require('dotenv').config();
// Order matters: SECRET_KEY must exist and vault secrets must be mirrored onto
// process.env before config/env.js (required transitively below) snapshots it.
require('./config/bootstrap').ensureSecretKey();
require('./config/secrets').loadIntoEnv();

const express = require('express');
const cors    = require('cors');
const morgan  = require('morgan');
const path    = require('path');
const chalk   = require('chalk');

const addonRouter = require('./addon/router');
const apiRouter   = require('./api/router');
const playerRouter = require('./api/player');
const settingsRouter = require('./api/settings');
const authRouter  = require('./auth/routes');
const setup       = require('./setup/routes');
const cloudflared = require('./setup/cloudflared');
const torbox      = require('./api/torbox');
const cache       = require('./cache/store');
const { PORT, HOST, NODE_ENV } = require('./config/env');

const app = express();

app.use(cors());
app.use(express.json());
app.use(morgan(NODE_ENV === 'production' ? 'combined' : 'dev'));
app.use(setup.firstRunGate);
app.use(setup.router);
app.use(express.static(path.join(__dirname, '../dashboard')));

app.use('/api/auth', authRouter);
app.use('/config', addonRouter);
app.use('/api/player', playerRouter);
app.use('/api', apiRouter);
app.use('/api', settingsRouter);

// ── Proxy stream — resolves fresh TorBox CDN URL at play time ─
// GET /proxy/stream/:kind/:ref/:fileId
app.get('/proxy/stream/:kind/:ref/:fileId', async (req, res) => {
  const { kind, ref, fileId } = req.params;
  try {
    const url = await torbox.getStreamUrlBySource(kind, decodeURIComponent(ref), parseInt(fileId) || 0);
    if (!url) {
      console.warn(`[Proxy] Stream unavailable kind=${kind} ref=${ref} fileId=${fileId}`);
      return res.status(404).json({ error: 'Stream not available' });
    }
    res.setHeader('Cache-Control', 'no-store');
    res.redirect(302, url);
  } catch (err) {
    console.error(`[Proxy] Error kind=${kind} ref=${ref} fileId=${fileId}:`, err.message);
    res.status(500).json({ error: 'Failed to resolve stream' });
  }
});

// Backward-compatible torrent-only route for cached stream metadata created by
// older StreamVault versions.
app.get('/proxy/stream/:hash/:fileId', async (req, res) => {
  const { hash, fileId } = req.params;
  try {
    const url = await torbox.getStreamUrlByHash(hash, parseInt(fileId) || 0, 'torrent');
    if (!url) {
      console.warn(`[Proxy] Stream unavailable hash=${hash} fileId=${fileId}`);
      return res.status(404).json({ error: 'Stream not available' });
    }
    res.setHeader('Cache-Control', 'no-store');
    res.redirect(302, url);
  } catch (err) {
    console.error(`[Proxy] Error hash=${hash} fileId=${fileId}:`, err.message);
    res.status(500).json({ error: 'Failed to resolve stream' });
  }
});

app.get('/', (req, res) => res.sendFile(path.join(__dirname, '../dashboard/index.html')));
app.get('/health', (req, res) => {
  const mem = process.memoryUsage();
  res.json({
    status: 'ok',
    ts: Date.now(),
    uptime: process.uptime(),
    memory: {
      rss: mem.rss,
      heapUsed: mem.heapUsed,
      heapTotal: mem.heapTotal,
    },
    redis: cache.stats().redis,
  });
});
app.use((req, res) => res.status(404).json({ error: 'Not found' }));

cloudflared.resumeIfConfigured();

app.listen(PORT, HOST, () => {
  console.log('');
  if (setup.isFirstRun()) {
    console.log(chalk.bold.yellow('  ► First run — no admin account yet. Run the terminal setup:'));
    console.log(chalk.bold.white('  ►   sudo bash install.sh --reconfigure   (or: streamvault setup)'));
    console.log('');
  }
  console.log(chalk.bold.cyan('  ╔══════════════════════════════════════╗'));
  console.log(chalk.bold.cyan('  ║   Stremio Private Addon — Running    ║'));
  console.log(chalk.bold.cyan('  ╚══════════════════════════════════════╝'));
  console.log('');
  console.log(chalk.green(`  ► Local:      http://${HOST}:${PORT}`));
  console.log(chalk.green(`  ► Dashboard:  http://localhost:${PORT}/`));
  console.log(chalk.green(`  ► Health:     http://localhost:${PORT}/health`));
  console.log('');
  console.log(chalk.yellow('  Add a manifest URL like:'));
  console.log(chalk.white(`  stremio://localhost:${PORT}/config/<your-id>/manifest.json`));
  console.log('');
});

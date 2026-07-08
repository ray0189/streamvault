// src/auth/routes.js — /api/auth/* login, logout, session info, password change.

const express = require('express');
const rateLimit = require('express-rate-limit');
const router = express.Router();
const users = require('./users');
const {
  createSession, setSessionCookie, clearSessionCookie, requireAuth,
} = require('./session');

const loginLimiter = rateLimit({
  windowMs: 15 * 60_000,
  max: 20,
  message: { error: 'Too many login attempts — try again in 15 minutes' },
});

// POST /api/auth/login {username, password}
router.post('/login', loginLimiter, (req, res) => {
  const { username, password } = req.body || {};
  const user = users.verifyLogin(username, password);
  if (!user) return res.status(401).json({ error: 'Invalid username or password' });
  const token = createSession(user.username);
  setSessionCookie(req, res, token);
  // Token also returned for header-based API clients (Bearer / x-admin-token).
  res.json({ ok: true, username: user.username, token });
});

// POST /api/auth/logout
router.post('/logout', (req, res) => {
  clearSessionCookie(res);
  res.json({ ok: true });
});

// GET /api/auth/me — session probe for the dashboard
router.get('/me', requireAuth, (req, res) => {
  res.json({ username: req.session.username });
});

// POST /api/auth/change-password {currentPassword, newPassword}
router.post('/change-password', requireAuth, (req, res) => {
  const { currentPassword, newPassword } = req.body || {};
  try {
    users.changePassword(currentPassword, newPassword);
  } catch (err) {
    return res.status(400).json({ error: err.message });
  }
  // Rotate the session so the client holds a fresh token.
  const token = createSession(req.session.username);
  setSessionCookie(req, res, token);
  res.json({ ok: true, token });
});

module.exports = router;

// src/auth/session.js — stateless signed session tokens.
//
// Token format: base64url(payload).base64url(hmac-sha256(payload, SECRET_KEY))
// where payload = {u: username, exp: epoch-ms}. Sent as an httpOnly cookie
// (browser dashboard) and also accepted via Authorization: Bearer / the
// legacy x-admin-token header so scripted API clients keep working — they
// just send a session token now instead of the raw admin password.

const crypto = require('crypto');

const COOKIE_NAME = 'sv_session';
const SESSION_TTL_MS = 7 * 24 * 60 * 60 * 1000; // 7 days

function signingKey() {
  const k = process.env.SECRET_KEY;
  if (!k || k === 'change-me') throw new Error('SECRET_KEY is not set');
  return crypto.createHash('sha256').update(`sv-session:${k}`).digest();
}

function b64url(buf) {
  return Buffer.from(buf).toString('base64url');
}

function sign(payload) {
  return crypto.createHmac('sha256', signingKey()).update(payload).digest('base64url');
}

function createSession(username) {
  const payload = b64url(JSON.stringify({ u: username, exp: Date.now() + SESSION_TTL_MS }));
  return `${payload}.${sign(payload)}`;
}

function verifySession(token) {
  if (typeof token !== 'string') return null;
  const dot = token.lastIndexOf('.');
  if (dot === -1) return null;
  const payload = token.slice(0, dot);
  const sig = token.slice(dot + 1);
  const expected = sign(payload);
  const a = Buffer.from(sig);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null;
  let data;
  try {
    data = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'));
  } catch {
    return null;
  }
  if (!data.u || !data.exp || Date.now() > data.exp) return null;
  return { username: data.u };
}

function parseCookies(req) {
  const out = {};
  const header = req.headers.cookie;
  if (!header) return out;
  for (const part of header.split(';')) {
    const eq = part.indexOf('=');
    if (eq === -1) continue;
    out[part.slice(0, eq).trim()] = decodeURIComponent(part.slice(eq + 1).trim());
  }
  return out;
}

function tokenFromRequest(req) {
  const auth = req.headers.authorization || '';
  if (auth.startsWith('Bearer ')) return auth.slice(7);
  if (req.headers['x-admin-token']) return req.headers['x-admin-token'];
  return parseCookies(req)[COOKIE_NAME] || null;
}

function setSessionCookie(req, res, token) {
  const secure = req.secure || req.headers['x-forwarded-proto'] === 'https';
  res.setHeader('Set-Cookie',
    `${COOKIE_NAME}=${encodeURIComponent(token)}; Path=/; HttpOnly; SameSite=Lax; ` +
    `Max-Age=${Math.floor(SESSION_TTL_MS / 1000)}${secure ? '; Secure' : ''}`);
}

function clearSessionCookie(res) {
  res.setHeader('Set-Cookie', `${COOKIE_NAME}=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0`);
}

// Express middleware — gates dashboard/API routes behind a valid session.
function requireAuth(req, res, next) {
  const session = verifySession(tokenFromRequest(req));
  if (!session) return res.status(401).json({ error: 'Unauthorised' });
  req.session = session;
  next();
}

module.exports = {
  COOKIE_NAME,
  createSession,
  verifySession,
  tokenFromRequest,
  setSessionCookie,
  clearSessionCookie,
  requireAuth,
};

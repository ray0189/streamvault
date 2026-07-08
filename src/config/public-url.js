const { PUBLIC_BASE_URL } = require('./env');

function normalizeBaseUrl(value) {
  if (!value) return '';
  const trimmed = String(value).trim().replace(/\/+$/, '');
  if (!trimmed) return '';
  return /^https?:\/\//i.test(trimmed) ? trimmed : `https://${trimmed}`;
}

function getRequestBaseUrl(req) {
  if (!req) return '';
  const forwardedProto = String(req.headers['x-forwarded-proto'] || '').split(',')[0].trim();
  const proto = forwardedProto || req.protocol || 'http';
  const forwardedHost = String(req.headers['x-forwarded-host'] || '').split(',')[0].trim();
  const host = forwardedHost || req.get?.('host') || req.headers.host || '';
  return host ? normalizeBaseUrl(`${proto}://${host}`) : '';
}

function getPublicBaseUrl(req) {
  return normalizeBaseUrl(PUBLIC_BASE_URL) || getRequestBaseUrl(req);
}

function absoluteUrl(path, req) {
  const base = getPublicBaseUrl(req);
  if (!base) return path;
  return `${base}${path.startsWith('/') ? path : `/${path}`}`;
}

module.exports = { normalizeBaseUrl, getRequestBaseUrl, getPublicBaseUrl, absoluteUrl };

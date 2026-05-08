/**
 * Express middleware that verifies an `Authorization: Bearer <jwt>` header
 * against our app-issued JWT and attaches `req.user` (the loaded User
 * document) to the request.
 *
 * If the header is missing or invalid, returns 401.
 *
 * Used on routes that require an authenticated iOS user. Existing
 * Telegram-authenticated routes (Mini App via initData) keep working
 * unchanged — they don't go through this middleware.
 */

const { verifyAppJWT } = require('../services/appleAuthService');
const User = require('../models/User');
const logger = require('../utils/logger');

function requireAuth() {
  const secret = process.env.JWT_SECRET;
  if (!secret) {
    // Fail loud at startup rather than silently letting unauth requests through.
    logger.error('JWT_SECRET is not configured — auth middleware will reject everything');
  }

  return async function (req, res, next) {
    if (!secret) {
      return res.status(500).json({ error: 'Server auth not configured' });
    }
    const header = req.headers.authorization || '';
    if (!header.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'Missing Bearer token' });
    }
    const token = header.slice('Bearer '.length).trim();
    try {
      const claims = await verifyAppJWT(token, secret);
      const user = await User.findById(claims.sub);
      if (!user) {
        return res.status(401).json({ error: 'User no longer exists' });
      }
      req.user = user;
      next();
    } catch (err) {
      logger.warn('JWT verify failed: ' + err.message);
      return res.status(401).json({ error: 'Invalid or expired token' });
    }
  };
}

module.exports = { requireAuth };

const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const rateLimit = require('express-rate-limit');
const { randomUUID } = require('crypto');
const { pool } = require('../db');
const authMiddleware = require('../middleware/auth');
const { sendError } = require('../utils/errors');
const { recordUsage } = require('../utils/usage');
const logger = require('../utils/logger');
const { observe } = require('../utils/metrics');
const SESSION_TTL_HOURS = Number(process.env.SESSION_TTL_HOURS || 24);

const router = express.Router();

const USERNAME_PATTERN = /^[a-z0-9_]{3,30}$/;
const MIN_PASSWORD_LENGTH = 8;

const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: (req) => ({
    error: 'Too many login attempts, please try again later.',
    code: 'RATE_LIMITED',
    request_id: req.requestId,
  }),
});

function normalizeUsername(username) {
  return String(username || '').toLowerCase().trim();
}

function validateUsername(username) {
  return USERNAME_PATTERN.test(username);
}

function validatePassword(password) {
  return typeof password === 'string' && password.length >= MIN_PASSWORD_LENGTH;
}

function getClientIp(req) {
  return (
    req.ip ||
    req.headers['x-forwarded-for']?.split(',')[0]?.trim() ||
    req.socket.remoteAddress ||
    null
  );
}

async function createSession(req, user) {
  const sessionId = randomUUID();
  const expiresAt = new Date(Date.now() + SESSION_TTL_HOURS * 60 * 60 * 1000);

  await pool.query(
    `INSERT INTO sessions (id, user_id, user_agent, ip, expires_at)
     VALUES ($1, $2, $3, $4::inet, $5)`,
    [sessionId, user.id, req.get('user-agent') || null, getClientIp(req), expiresAt]
  );

  return { sessionId, expiresAt };
}

function signToken(user, sessionId) {
  return jwt.sign(
    { userId: user.id, username: user.username, role: user.role || 'user', sessionId },
    process.env.JWT_SECRET,
    { expiresIn: `${SESSION_TTL_HOURS}h` }
  );
}

async function issueToken(req, user) {
  const session = await createSession(req, user);
  observe('session_ttl_hours', SESSION_TTL_HOURS, { role: user.role || 'user' });
  return {
    token: signToken(user, session.sessionId),
    expires_at: session.expiresAt.toISOString(),
    session_id: session.sessionId,
  };
}

function publicSession(row) {
  return {
    id: row.id,
    current: row.id === row.current_session_id,
    user_agent: row.user_agent,
    ip: row.ip,
    created_at: row.created_at,
    expires_at: row.expires_at,
    revoked_at: row.revoked_at,
  };
}

router.post('/register', async (req, res) => {
  const username = normalizeUsername(req.body.username);
  const { password } = req.body;
  const clientIp = getClientIp(req);

  if (!validateUsername(username)) {
    return res.status(400).json({
      error:
        'Username must be 3-30 characters and only use lowercase letters, numbers, or underscore',
      code: 'INVALID_USERNAME',
      request_id: req.requestId,
    });
  }

  if (!validatePassword(password)) {
    return res.status(400).json({
      error: 'Password must be at least 8 characters',
      code: 'INVALID_PASSWORD',
      request_id: req.requestId,
    });
  }

  try {
    const existing = await pool.query('SELECT id FROM users WHERE username = $1', [username]);
    if (existing.rows.length > 0) {
      return res.status(409).json({
        error: 'Username already exists',
        code: 'USERNAME_EXISTS',
        request_id: req.requestId,
      });
    }

    const passwordHash = await bcrypt.hash(password, 12);
    const result = await pool.query(
      `INSERT INTO users (username, password_hash, created_ip)
       VALUES ($1, $2, $3::inet)
       RETURNING id, username, role`,
      [username, passwordHash, clientIp]
    );

    const user = result.rows[0];
    const tokenData = await issueToken(req, user);
    logger.info('auth_register_success', { request_id: req.requestId, user_id: logger.redact(user.id) });
    await recordUsage(user.id, 'auth_register', 1, { ip: clientIp ? 'present' : 'missing' });

    res.status(201).json({
      ...tokenData,
      user: { id: user.id, username: user.username, role: user.role || 'user' },
    });
  } catch (err) {
    return sendError(res, req, 500, 'Server error', err);
  }
});

router.post('/login', loginLimiter, async (req, res) => {
  const username = normalizeUsername(req.body.username);
  const { password } = req.body;

  if (!username || !password) {
    return res.status(400).json({
      error: 'Username and password required',
      code: 'MISSING_CREDENTIALS',
      request_id: req.requestId,
    });
  }

  try {
    const result = await pool.query(
      'SELECT id, username, password_hash, role FROM users WHERE username = $1',
      [username]
    );

    if (result.rows.length === 0) {
      logger.warn('auth_login_failed', { request_id: req.requestId, username });
      return sendError(res, req, 401, 'Invalid credentials', null, 'INVALID_CREDENTIALS');
    }

    const user = result.rows[0];
    const valid = await bcrypt.compare(password, user.password_hash);

    if (!valid) {
      logger.warn('auth_login_failed', { request_id: req.requestId, user_id: logger.redact(user.id) });
      return sendError(res, req, 401, 'Invalid credentials', null, 'INVALID_CREDENTIALS');
    }

    await pool.query('UPDATE users SET last_login_at = NOW() WHERE id = $1', [user.id]);
    const tokenData = await issueToken(req, user);
    logger.info('auth_login_success', { request_id: req.requestId, user_id: logger.redact(user.id) });
    await recordUsage(user.id, 'auth_login', 1, { ip: getClientIp(req) ? 'present' : 'missing' });

    res.json({
      ...tokenData,
      user: { id: user.id, username: user.username, role: user.role || 'user' },
    });
  } catch (err) {
    return sendError(res, req, 500, 'Server error', err);
  }
});

router.post('/logout', authMiddleware, async (req, res) => {
  try {
    await pool.query('UPDATE sessions SET revoked_at = NOW() WHERE id = $1 AND user_id = $2', [
      req.sessionId,
      req.userId,
    ]);
    res.json({ logged_out: true });
  } catch (err) {
    return sendError(res, req, 500, 'Logout failed', err);
  }
});

router.post('/logout-all', authMiddleware, async (req, res) => {
  try {
    await pool.query(
      'UPDATE sessions SET revoked_at = NOW() WHERE user_id = $1 AND revoked_at IS NULL',
      [req.userId]
    );
    logger.info('auth_logout_all', { request_id: req.requestId, user_id: logger.redact(req.userId) });
    res.json({ logged_out_all: true });
  } catch (err) {
    return sendError(res, req, 500, 'Logout failed', err);
  }
});

router.get('/sessions', authMiddleware, async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT id, $2::uuid AS current_session_id, user_agent, host(ip) AS ip,
              created_at, expires_at, revoked_at
       FROM sessions
       WHERE user_id = $1
       ORDER BY created_at DESC
       LIMIT 20`,
      [req.userId, req.sessionId]
    );
    res.json({ sessions: result.rows.map(publicSession) });
  } catch (err) {
    return sendError(res, req, 500, 'Failed to load sessions', err);
  }
});

router.delete('/sessions/:sessionId', authMiddleware, async (req, res) => {
  try {
    const result = await pool.query(
      `UPDATE sessions SET revoked_at = NOW()
       WHERE id = $1 AND user_id = $2 AND revoked_at IS NULL
       RETURNING id`,
      [req.params.sessionId, req.userId]
    );

    if (result.rows.length === 0) {
      return sendError(res, req, 404, 'Session not found', null, 'SESSION_NOT_FOUND');
    }

    logger.info('auth_session_revoked', {
      request_id: req.requestId,
      user_id: logger.redact(req.userId),
      session_id: logger.redact(req.params.sessionId),
    });
    res.json({ revoked: true, session_id: req.params.sessionId });
  } catch (err) {
    return sendError(res, req, 500, 'Failed to revoke session', err);
  }
});

module.exports = router;

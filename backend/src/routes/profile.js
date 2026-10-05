const express = require('express');
const multer = require('multer');
const { v4: uuidv4 } = require('uuid');
const { pool } = require('../db');
const authMiddleware = require('../middleware/auth');
const { uploadFile, deleteFile, getPublicUrl } = require('../utils/minio');
const { sendError } = require('../utils/errors');
const metrics = require('../utils/metrics');
const logger = require('../utils/logger');

const router = express.Router();
router.use(authMiddleware);

const AVATAR_MAX_SIZE = 2 * 1024 * 1024; // 2MB
const ALLOWED_MIME = new Set([
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/gif',
]);

const displayPattern = /^[a-zA-Z0-9_\u00C0-\u024F .'-]{2,50}$/;

function mimeToExt(mime) {
  switch (mime) {
    case 'image/png':
      return 'png';
    case 'image/webp':
      return 'webp';
    case 'image/gif':
      return 'gif';
    default:
      return 'jpg';
  }
}

const avatarUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: AVATAR_MAX_SIZE },
});

// Current profile
router.get('/', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT id, username, display_name, avatar_url, role FROM users WHERE id = $1',
      [req.userId]
    );
    if (result.rows.length === 0) {
      return sendError(res, req, 404, 'User not found', null, 'USER_NOT_FOUND');
    }
    const user = result.rows[0];
    res.json({
      user: {
        id: user.id,
        username: user.username,
        display_name: user.display_name || user.username,
        avatar_url: user.avatar_url,
        role: user.role || 'user',
      },
    });
  } catch (err) {
    return sendError(res, req, 500, 'Failed to load profile', err);
  }
});

// Update display_name (nickname)
router.put('/', async (req, res) => {
  const displayName =
    typeof req.body.display_name === 'string'
      ? req.body.display_name.trim()
      : '';

  if (displayName.length < 2 || displayName.length > 50 || !displayPattern.test(displayName)) {
    return sendError(
      res,
      req,
      400,
      'Display name must be 2-50 characters (letters, numbers, underscore, spaces, basic punctuation)',
      null,
      'INVALID_DISPLAY_NAME'
    );
  }

  try {
    const result = await pool.query(
      `UPDATE users SET display_name = $1, updated_at = NOW()
       WHERE id = $2
       RETURNING id, username, display_name, avatar_url, role`,
      [displayName, req.userId]
    );

    if (result.rows.length === 0) {
      return sendError(res, req, 404, 'User not found', null, 'USER_NOT_FOUND');
    }

    logger.info('profile_display_name_updated', {
      request_id: req.requestId,
      user_id: logger.redact(req.userId),
    });

    res.json({
      user: {
        ...result.rows[0],
        display_name: result.rows[0].display_name || result.rows[0].username,
      },
    });
  } catch (err) {
    return sendError(res, req, 500, 'Failed to update display name', err);
  }
});

// Upload avatar image
router.post('/avatar', avatarUpload.single('avatar'), async (req, res) => {
  if (!req.file) {
    return sendError(res, req, 400, 'Avatar file required', null, 'AVATAR_REQUIRED');
  }

  if (!ALLOWED_MIME.has(req.file.mimetype)) {
    return sendError(
      res,
      req,
      415,
      'Unsupported avatar type. Use JPG, PNG, WEBP, or GIF.',
      null,
      'AVATAR_TYPE'
    );
  }

  const ext = mimeToExt(req.file.mimetype);
  const key = `avatars/${req.userId}/${uuidv4()}.${ext}`;

  try {
    await uploadFile(key, req.file.buffer, req.file.mimetype);
    const publicUrl = getPublicUrl(key);

    // Replace old avatar if present
    const old = await pool.query('SELECT avatar_url FROM users WHERE id = $1', [
      req.userId,
    ]);
    const oldKey = old.rows[0]?.avatar_url;
    if (oldKey) {
      try {
        const marker = '/api/files/';
        const idx = oldKey.indexOf(marker);
        const normalized =
          idx !== -1 ? decodeURIComponent(oldKey.slice(idx + marker.length)) : oldKey;
        if (normalized.startsWith('avatars/')) {
          await deleteFile(normalized);
        }
      } catch (_) {
        // Best-effort: a stale avatar object is not fatal.
      }
    }

    await pool.query(
      `UPDATE users SET avatar_url = $1, updated_at = NOW() WHERE id = $2`,
      [publicUrl, req.userId]
    );

    logger.info('profile_avatar_updated', {
      request_id: req.requestId,
      user_id: logger.redact(req.userId),
    });

    res.status(200).json({ avatar_url: publicUrl });
  } catch (err) {
    metrics.inc('avatar_uploads_failures_total', { code: err.code || 'AVATAR_FAILED' });
    return sendError(res, req, err.statusCode || 500, 'Avatar upload failed', err);
  }
});

// Remove avatar
router.delete('/avatar', async (req, res) => {
  try {
    const old = await pool.query('SELECT avatar_url FROM users WHERE id = $1', [
      req.userId,
    ]);
    const oldKey = old.rows[0]?.avatar_url;
    if (oldKey) {
      try {
        const marker = '/api/files/';
        const idx = oldKey.indexOf(marker);
        const normalized =
          idx !== -1 ? decodeURIComponent(oldKey.slice(idx + marker.length)) : oldKey;
        if (normalized.startsWith('avatars/')) {
          await deleteFile(normalized);
        }
      } catch (_) {}
    }

    await pool.query(
      `UPDATE users SET avatar_url = NULL, updated_at = NOW() WHERE id = $1`,
      [req.userId]
    );

    logger.info('profile_avatar_removed', {
      request_id: req.requestId,
      user_id: logger.redact(req.userId),
    });

    res.json({ avatar_url: null });
  } catch (err) {
    return sendError(res, req, 500, 'Failed to remove avatar', err);
  }
});

module.exports = router;

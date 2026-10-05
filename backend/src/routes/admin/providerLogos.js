const express = require('express');
const { pool } = require('../../db');
const authMiddleware = require('../../middleware/auth');
const { adminOnly } = require('../../middleware/admin');
const { sendError } = require('../../utils/errors');
const { invalidateCache } = require('../../utils/modelCatalog');
const { uploadFile, getPublicUrl } = require('../../utils/minio');
const { v4: uuidv4 } = require('uuid');

const router = express.Router();
router.use(authMiddleware);
router.use(adminOnly);

// List all provider logos.
router.get('/', async (req, res) => {
  try {
    const result = await pool.query('SELECT provider, logo_url, updated_at FROM provider_logos ORDER BY provider ASC');
    res.json({ logos: result.rows });
  } catch (err) {
    return sendError(res, req, 500, 'Failed to load provider logos', err);
  }
});

// Upload a provider logo. Body: { provider, image: <base64 data URL or path> }.
// Expects a base64-encoded image (data URI or raw base64) plus the provider name.
router.post('/', async (req, res) => {
  const provider = (req.body?.provider || '').toString().trim();
  const image = (req.body?.image || '').toString().trim();
  if (!provider || !image) {
    return sendError(res, req, 400, 'Missing required fields: provider, image', null, 'MISSING_FIELDS');
  }

  // Accept a data URI (data:image/png;base64,...) or raw base64.
  const dataMatch = image.match(/^data:(image\/[a-zA-Z0-9.+-]+);base64,(.+)$/);
  let buffer;
  let contentType = 'application/octet-stream';
  if (dataMatch) {
    contentType = dataMatch[1];
    buffer = Buffer.from(dataMatch[2], 'base64');
  } else {
    buffer = Buffer.from(image, 'base64');
    contentType = 'image/png';
  }

  if (buffer.length === 0 || buffer.length > 2 * 1024 * 1024) {
    return sendError(res, req, 400, 'Image must be 1–2 MB', null, 'INVALID_IMAGE');
  }

  try {
    const key = `provider-logos/${provider.toLowerCase()}-${uuidv4()}.png`;
    await uploadFile(key, buffer, contentType, { provider });
    const publicUrl = getPublicUrl(key);

    await pool.query(
      `INSERT INTO provider_logos (provider, logo_url, updated_at)
       VALUES ($1, $2, NOW())
       ON CONFLICT (provider) DO UPDATE SET logo_url = EXCLUDED.logo_url, updated_at = NOW()
       RETURNING provider, logo_url`,
      [provider, publicUrl]
    );

    invalidateCache();
    res.status(201).json({ provider, logo_url: publicUrl });
  } catch (err) {
    return sendError(res, req, 500, 'Failed to upload provider logo', err);
  }
});

// Delete a provider logo.
router.delete('/:provider', async (req, res) => {
  const provider = req.params.provider;
  try {
    const result = await pool.query('DELETE FROM provider_logos WHERE provider = $1 RETURNING provider', [provider]);
    if (!result.rows.length) {
      return sendError(res, req, 404, 'Provider logo not found', null, 'NOT_FOUND');
    }
    invalidateCache();
    res.json({ success: true });
  } catch (err) {
    return sendError(res, req, 500, 'Failed to delete provider logo', err);
  }
});

module.exports = router;

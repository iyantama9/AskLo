const express = require('express');
const { pool } = require('../../db');
const authMiddleware = require('../../middleware/auth');
const { adminOnly } = require('../../middleware/admin');
const { sendError } = require('../../utils/errors');

const router = express.Router();
router.use(authMiddleware);
router.use(adminOnly);

// Get all settings
router.get('/', async (req, res) => {
  try {
    const result = await pool.query('SELECT key, value FROM admin_settings');
    const settings = {};
    for (const row of result.rows) {
      settings[row.key] = row.value;
    }
    res.json({ settings });
  } catch (err) {
    return sendError(res, req, 500, 'Failed to fetch settings', err);
  }
});

// Update a setting
router.put('/:key', async (req, res) => {
  const { key } = req.params;
  const { value } = req.body;

  if (value === undefined) {
    return sendError(res, req, 400, 'Missing value', null, 'MISSING_VALUE');
  }

  try {
    const result = await pool.query(
      `INSERT INTO admin_settings (key, value, updated_at)
       VALUES ($1, $2::jsonb, NOW())
       ON CONFLICT (key) DO UPDATE SET value = $2::jsonb, updated_at = NOW()
       RETURNING key, value, updated_at`,
      [key, JSON.stringify(value)]
    );

    res.json({ setting: result.rows[0] });
  } catch (err) {
    return sendError(res, req, 500, 'Failed to update setting', err);
  }
});

module.exports = router;

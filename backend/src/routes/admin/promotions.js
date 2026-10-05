const express = require('express');
const { pool } = require('../../db');
const authMiddleware = require('../../middleware/auth');
const { adminOnly } = require('../../middleware/admin');
const { sendError } = require('../../utils/errors');

const router = express.Router();
router.use(authMiddleware);
router.use(adminOnly);

// Get all promotions
router.get('/', async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT p.*, u.username as created_by_username,
              (SELECT COUNT(*) FROM user_promotions WHERE promotion_id = p.id) as user_count
       FROM promotions p
       LEFT JOIN users u ON p.created_by = u.id
       ORDER BY p.start_date DESC`
    );
    res.json({ promotions: result.rows });
  } catch (err) {
    return sendError(res, req, 500, 'Failed to fetch promotions', err);
  }
});

// Get single promotion with assigned users
router.get('/:id', async (req, res) => {
  try {
    const promoResult = await pool.query(
      `SELECT p.*, u.username as created_by_username
       FROM promotions p
       LEFT JOIN users u ON p.created_by = u.id
       WHERE p.id = $1`,
      [req.params.id]
    );

    if (!promoResult.rows.length) {
      return sendError(res, req, 404, 'Promotion not found', null, 'PROMO_NOT_FOUND');
    }

    const usersResult = await pool.query(
      `SELECT u.id, u.username, u.role, up.assigned_at,
              a.username as assigned_by_username
       FROM user_promotions up
       JOIN users u ON up.user_id = u.id
       LEFT JOIN users a ON up.assigned_by = a.id
       WHERE up.promotion_id = $1
       ORDER BY up.assigned_at DESC`,
      [req.params.id]
    );

    res.json({
      promotion: promoResult.rows[0],
      assigned_users: usersResult.rows,
    });
  } catch (err) {
    return sendError(res, req, 500, 'Failed to fetch promotion', err);
  }
});

// Create promotion
router.post('/', async (req, res) => {
  const {
    name,
    description,
    start_date,
    end_date,
    unlimited_quota,
    quota_multiplier,
    custom_limits,
    is_active,
  } = req.body;

  if (!name || !start_date || !end_date) {
    return sendError(res, req, 400, 'Missing required fields: name, start_date, end_date', null, 'MISSING_FIELDS');
  }

  if (new Date(start_date) >= new Date(end_date)) {
    return sendError(res, req, 400, 'end_date must be after start_date', null, 'INVALID_DATES');
  }

  try {
    const result = await pool.query(
      `INSERT INTO promotions (
        name, description, start_date, end_date, unlimited_quota,
        quota_multiplier, custom_limits, is_active, created_by
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
      RETURNING *`,
      [
        name,
        description || null,
        start_date,
        end_date,
        unlimited_quota !== false,
        quota_multiplier || 1.0,
        JSON.stringify(custom_limits || {}),
        is_active !== false,
        req.userId,
      ]
    );

    res.status(201).json({ promotion: result.rows[0] });
  } catch (err) {
    return sendError(res, req, 500, 'Failed to create promotion', err);
  }
});

// Update promotion
router.put('/:id', async (req, res) => {
  const {
    name,
    description,
    start_date,
    end_date,
    unlimited_quota,
    quota_multiplier,
    custom_limits,
    is_active,
  } = req.body;

  try {
    const result = await pool.query(
      `UPDATE promotions SET
        name = COALESCE($2, name),
        description = COALESCE($3, description),
        start_date = COALESCE($4, start_date),
        end_date = COALESCE($5, end_date),
        unlimited_quota = COALESCE($6, unlimited_quota),
        quota_multiplier = COALESCE($7, quota_multiplier),
        custom_limits = COALESCE($8, custom_limits),
        is_active = COALESCE($9, is_active),
        updated_at = NOW()
      WHERE id = $1
      RETURNING *`,
      [
        req.params.id,
        name,
        description,
        start_date,
        end_date,
        unlimited_quota,
        quota_multiplier,
        custom_limits ? JSON.stringify(custom_limits) : null,
        is_active,
      ]
    );

    if (!result.rows.length) {
      return sendError(res, req, 404, 'Promotion not found', null, 'PROMO_NOT_FOUND');
    }

    res.json({ promotion: result.rows[0] });
  } catch (err) {
    return sendError(res, req, 500, 'Failed to update promotion', err);
  }
});

// Delete promotion
router.delete('/:id', async (req, res) => {
  try {
    const result = await pool.query(
      'DELETE FROM promotions WHERE id = $1 RETURNING id',
      [req.params.id]
    );

    if (!result.rows.length) {
      return sendError(res, req, 404, 'Promotion not found', null, 'PROMO_NOT_FOUND');
    }

    res.json({ success: true, deleted_id: result.rows[0].id });
  } catch (err) {
    return sendError(res, req, 500, 'Failed to delete promotion', err);
  }
});

// Toggle promotion active/inactive
router.patch('/:id/toggle', async (req, res) => {
  try {
    const result = await pool.query(
      `UPDATE promotions SET is_active = NOT is_active, updated_at = NOW()
       WHERE id = $1
       RETURNING *`,
      [req.params.id]
    );

    if (!result.rows.length) {
      return sendError(res, req, 404, 'Promotion not found', null, 'PROMO_NOT_FOUND');
    }

    res.json({ promotion: result.rows[0] });
  } catch (err) {
    return sendError(res, req, 500, 'Failed to toggle promotion', err);
  }
});

// Assign promotion to users
router.post('/:id/assign', async (req, res) => {
  const { user_ids } = req.body;

  if (!Array.isArray(user_ids) || user_ids.length === 0) {
    return sendError(res, req, 400, 'user_ids must be a non-empty array', null, 'INVALID_USER_IDS');
  }

  try {
    // Check if promotion exists
    const promoCheck = await pool.query('SELECT id FROM promotions WHERE id = $1', [req.params.id]);
    if (!promoCheck.rows.length) {
      return sendError(res, req, 404, 'Promotion not found', null, 'PROMO_NOT_FOUND');
    }

    // Insert user promotions (ignore duplicates)
    const values = user_ids.map((userId, i) => `($1, $${i + 2}, $${user_ids.length + 2})`).join(',');
    const params = [req.params.id, ...user_ids, req.userId];

    await pool.query(
      `INSERT INTO user_promotions (promotion_id, user_id, assigned_by)
       VALUES ${values}
       ON CONFLICT (user_id, promotion_id) DO NOTHING`,
      params
    );

    res.json({ success: true, message: `Promotion assigned to ${user_ids.length} users` });
  } catch (err) {
    return sendError(res, req, 500, 'Failed to assign promotion', err);
  }
});

// Remove promotion from user
router.delete('/:id/assign/:userId', async (req, res) => {
  try {
    const result = await pool.query(
      'DELETE FROM user_promotions WHERE promotion_id = $1 AND user_id = $2 RETURNING *',
      [req.params.id, req.params.userId]
    );

    if (!result.rows.length) {
      return sendError(res, req, 404, 'Assignment not found', null, 'ASSIGNMENT_NOT_FOUND');
    }

    res.json({ success: true, message: 'Promotion removed from user' });
  } catch (err) {
    return sendError(res, req, 500, 'Failed to remove promotion', err);
  }
});

module.exports = router;

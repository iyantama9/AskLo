const express = require('express');
const { pool } = require('../../db');
const authMiddleware = require('../../middleware/auth');
const { adminOnly } = require('../../middleware/admin');
const { sendError } = require('../../utils/errors');
const { getUsage, DEFAULT_LIMITS } = require('../../utils/usage');

const router = express.Router();
router.use(authMiddleware);
router.use(adminOnly);

// Get all users with stats
router.get('/', async (req, res) => {
  const { page = 1, limit = 50, search = '', role = '' } = req.query;
  const offset = (page - 1) * limit;

  try {
    let whereClause = 'WHERE 1=1';
    const params = [];

    if (search) {
      params.push(`%${search}%`);
      whereClause += ` AND username ILIKE $${params.length}`;
    }

    if (role) {
      params.push(role);
      whereClause += ` AND role = $${params.length}`;
    }

    params.push(limit, offset);

    const result = await pool.query(
      `SELECT u.id, u.username, u.role, u.created_at, u.last_login_at,
              COUNT(DISTINCT c.id) as chat_count,
              COUNT(DISTINCT up.promotion_id) as active_promotions
       FROM users u
       LEFT JOIN chats c ON u.id = c.user_id
       LEFT JOIN user_promotions up ON u.id = up.user_id
       LEFT JOIN promotions p ON up.promotion_id = p.id AND p.is_active = true
         AND NOW() BETWEEN p.start_date AND p.end_date
       ${whereClause}
       GROUP BY u.id
       ORDER BY u.created_at DESC
       LIMIT $${params.length - 1} OFFSET $${params.length}`,
      params
    );

    const countResult = await pool.query(
      `SELECT COUNT(*) as total FROM users ${whereClause}`,
      params.slice(0, -2)
    );

    res.json({
      users: result.rows,
      pagination: {
        page: parseInt(page),
        limit: parseInt(limit),
        total: parseInt(countResult.rows[0].total),
        pages: Math.ceil(countResult.rows[0].total / limit),
      },
    });
  } catch (err) {
    return sendError(res, req, 500, 'Failed to fetch users', err);
  }
});

// Get user stats summary
router.get('/stats/summary', async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT
        COUNT(*) as total_users,
        COUNT(*) FILTER (WHERE role = 'admin') as admin_count,
        COUNT(*) FILTER (WHERE role = 'user') as user_count,
        COUNT(*) FILTER (WHERE last_login_at > NOW() - INTERVAL '24 hours') as active_24h,
        COUNT(*) FILTER (WHERE last_login_at > NOW() - INTERVAL '7 days') as active_7d,
        COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '7 days') as new_7d
      FROM users
    `);

    res.json({ stats: result.rows[0] });
  } catch (err) {
    return sendError(res, req, 500, 'Failed to fetch stats', err);
  }
});

// Get single user with details
router.get('/:id', async (req, res) => {
  try {
    const userResult = await pool.query(
      `SELECT u.id, u.username, u.role, u.created_at, u.last_login_at, u.created_ip,
              COUNT(DISTINCT c.id) as chat_count,
              COUNT(DISTINCT f.id) as file_count
       FROM users u
       LEFT JOIN chats c ON u.id = c.user_id
       LEFT JOIN files f ON u.id = f.owner_id
       WHERE u.id = $1
       GROUP BY u.id`,
      [req.params.id]
    );

    if (!userResult.rows.length) {
      return sendError(res, req, 404, 'User not found', null, 'USER_NOT_FOUND');
    }

    const user = userResult.rows[0];

    // Get usage stats
    const usage = await Promise.all(
      Object.keys(DEFAULT_LIMITS).map(async (kind) => {
        const used = await getUsage(req.params.id, kind);
        return { kind, used, limit: DEFAULT_LIMITS[kind] };
      })
    );

    // Get active promotions
    const promosResult = await pool.query(
      `SELECT p.*, up.assigned_at, a.username as assigned_by_username
       FROM user_promotions up
       JOIN promotions p ON up.promotion_id = p.id
       LEFT JOIN users a ON up.assigned_by = a.id
       WHERE up.user_id = $1 AND p.is_active = true
       ORDER BY up.assigned_at DESC`,
      [req.params.id]
    );

    res.json({
      user,
      usage,
      promotions: promosResult.rows,
    });
  } catch (err) {
    return sendError(res, req, 500, 'Failed to fetch user', err);
  }
});

// Update user role
router.patch('/:id/role', async (req, res) => {
  const { role } = req.body;

  if (!['user', 'admin'].includes(role)) {
    return sendError(res, req, 400, 'Invalid role. Must be "user" or "admin"', null, 'INVALID_ROLE');
  }

  try {
    const result = await pool.query(
      'UPDATE users SET role = $2 WHERE id = $1 RETURNING id, username, role',
      [req.params.id, role]
    );

    if (!result.rows.length) {
      return sendError(res, req, 404, 'User not found', null, 'USER_NOT_FOUND');
    }

    res.json({ user: result.rows[0] });
  } catch (err) {
    return sendError(res, req, 500, 'Failed to update user role', err);
  }
});

// Delete user (soft delete - revoke all sessions)
router.delete('/:id', async (req, res) => {
  // Prevent self-deletion
  if (parseInt(req.params.id) === req.userId) {
    return sendError(res, req, 400, 'Cannot delete your own account', null, 'SELF_DELETE');
  }

  try {
    // Revoke all sessions
    await pool.query(
      'UPDATE sessions SET revoked_at = NOW() WHERE user_id = $1 AND revoked_at IS NULL',
      [req.params.id]
    );

    // Delete user data
    const result = await pool.query(
      'DELETE FROM users WHERE id = $1 RETURNING id, username',
      [req.params.id]
    );

    if (!result.rows.length) {
      return sendError(res, req, 404, 'User not found', null, 'USER_NOT_FOUND');
    }

    res.json({ success: true, deleted_user: result.rows[0] });
  } catch (err) {
    return sendError(res, req, 500, 'Failed to delete user', err);
  }
});

module.exports = router;

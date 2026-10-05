const { sendError } = require('../utils/errors');

/**
 * Middleware to check if user is admin
 */
async function adminOnly(req, res, next) {
  if (!req.userId) {
    return sendError(res, req, 401, 'Authentication required', null, 'AUTH_REQUIRED');
  }

  // Check user role from database
  const { pool } = require('../db');
  const result = await pool.query(
    'SELECT role FROM users WHERE id = $1',
    [req.userId]
  );

  if (!result.rows.length) {
    return sendError(res, req, 401, 'User not found', null, 'USER_NOT_FOUND');
  }

  const user = result.rows[0];
  if (user.role !== 'admin') {
    return sendError(res, req, 403, 'Admin access required', null, 'ADMIN_ONLY');
  }

  next();
}

module.exports = { adminOnly };

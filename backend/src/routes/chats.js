const express = require('express');
const { pool } = require('../db');
const authMiddleware = require('../middleware/auth');
const { sendError } = require('../utils/errors');
const { assertValidModel, getFallbackModel } = require('../utils/modelCatalog');

const router = express.Router();
router.use(authMiddleware);

// List user's chats
router.get('/', async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT id, title, model, created_at, updated_at
       FROM chats WHERE user_id = $1
       ORDER BY updated_at DESC`,
      [req.userId]
    );
    res.json(result.rows);
  } catch (err) {
    return sendError(res, req, 500, 'Server error', err);
  }
});

// Create new chat
router.post('/', async (req, res) => {
  const { title, model } = req.body;

  try {
    const selectedModel = model || await getFallbackModel('chat');
    if (!selectedModel) {
      const error = new Error('No enabled chat model is available');
      error.statusCode = 503;
      error.code = 'NO_CHAT_MODEL';
      throw error;
    }
    await assertValidModel(selectedModel);
    const result = await pool.query(
      `INSERT INTO chats (user_id, title, model)
       VALUES ($1, $2, $3) RETURNING *`,
      [req.userId, title || 'New Chat', selectedModel]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    return sendError(res, req, err.statusCode || 500, err.publicMessage || err.message || 'Server error', err);
  }
});

// Update chat (title and/or model)
router.put('/:id', async (req, res) => {
  const { title, model } = req.body;
  try {
    if (model) await assertValidModel(model);
    const result = await pool.query(
      `UPDATE chats SET
        title = COALESCE($1, title),
        model = COALESCE($2, model),
        updated_at = NOW()
       WHERE id = $3 AND user_id = $4 RETURNING *`,
      [title, model, req.params.id, req.userId]
    );
    if (result.rows.length === 0) {
      return sendError(res, req, 404, 'Chat not found');
    }
    res.json(result.rows[0]);
  } catch (err) {
    return sendError(res, req, err.statusCode || 500, err.publicMessage || err.message || 'Server error', err);
  }
});

// Delete chat
router.delete('/:id', async (req, res) => {
  try {
    const result = await pool.query(
      'DELETE FROM chats WHERE id = $1 AND user_id = $2 RETURNING id',
      [req.params.id, req.userId]
    );
    if (result.rows.length === 0) {
      return sendError(res, req, 404, 'Chat not found');
    }
    res.json({ deleted: true });
  } catch (err) {
    return sendError(res, req, 500, 'Server error', err);
  }
});

// Search across chats
router.get('/search', async (req, res) => {
  const { q } = req.query;
  if (!q || q.trim().length < 2) {
    return sendError(res, req, 400, 'Query too short', null, 'QUERY_TOO_SHORT');
  }
  try {
    const result = await pool.query(
      `SELECT DISTINCT c.id, c.title, c.model, c.updated_at,
              (SELECT content FROM messages WHERE chat_id = c.id AND content ILIKE $2 ORDER BY created_at DESC LIMIT 1) as matched_content
       FROM chats c
       LEFT JOIN messages m ON m.chat_id = c.id
       WHERE c.user_id = $1 AND (c.title ILIKE $2 OR m.content ILIKE $2)
       ORDER BY c.updated_at DESC
       LIMIT 20`,
      [req.userId, `%${q.trim()}%`]
    );
    res.json(result.rows);
  } catch (err) {
    return sendError(res, req, 500, 'Search failed', err);
  }
});

module.exports = router;

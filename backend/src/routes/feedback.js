const express = require('express');
const { pool } = require('../db');
const authMiddleware = require('../middleware/auth');
const { sendError } = require('../utils/errors');

const router = express.Router();
router.use(authMiddleware);

router.post('/', async (req, res) => {
  const content = typeof req.body.content === 'string' ? req.body.content.trim() : '';
  const chatId = req.body.chat_id ?? null;
  const model = typeof req.body.model === 'string' ? req.body.model.trim().slice(0, 100) : null;

  if (!content) {
    return sendError(res, req, 400, 'Kritik dan saran wajib diisi', null, 'FEEDBACK_REQUIRED');
  }

  if (content.length > 2000) {
    return sendError(res, req, 400, 'Kritik dan saran maksimal 2000 karakter', null, 'FEEDBACK_TOO_LONG');
  }

  try {
    let feedbackChatId = null;
    if (chatId != null) {
      const chat = await pool.query(
        'SELECT id FROM chats WHERE id = $1 AND user_id = $2',
        [chatId, req.userId]
      );
      if (chat.rows.length === 0) {
        return sendError(res, req, 404, 'Chat not found', null, 'CHAT_NOT_FOUND');
      }
      feedbackChatId = chat.rows[0].id;
    }

    const result = await pool.query(
      `INSERT INTO feedback (user_id, chat_id, content, model, user_agent, ip)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING id, created_at`,
      [
        req.userId,
        feedbackChatId,
        content,
        model || null,
        req.get('user-agent') || null,
        req.ip || null,
      ]
    );

    return res.status(201).json({
      ...result.rows[0],
      request_id: req.requestId,
    });
  } catch (err) {
    return sendError(res, req, 500, 'Gagal mengirim kritik dan saran', err, 'FEEDBACK_FAILED');
  }
});

module.exports = router;

const express = require('express');
const multer = require('multer');
const { uploadFile, getFile } = require('../utils/minio');
const { v4: uuidv4 } = require('uuid');
const authMiddleware = require('../middleware/auth');
const { recordFile, assertCanReadR2Key } = require('../utils/files');
const { sendError } = require('../utils/errors');
const { assertQuota, recordUsage } = require('../utils/usage');
const metrics = require('../utils/metrics');

const router = express.Router();
router.use(authMiddleware);

const MAX_SIZE = 1 * 1024 * 1024; // 1MB

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_SIZE },
});

// Upload file
router.post('/', upload.single('file'), async (req, res) => {
  if (!req.file) {
    return sendError(res, req, 400, 'No file provided', null, 'FILE_REQUIRED');
  }

  const ext = req.file.originalname.split('.').pop();
  const key = `uploads/${req.userId}/${uuidv4()}.${ext}`;

  try {
    await assertQuota(req.userId, 'upload_count', 1);
    await assertQuota(req.userId, 'upload_bytes', req.file.size);

    await uploadFile(key, req.file.buffer, req.file.mimetype);

    const file = await recordFile({
      ownerId: req.userId,
      key,
      fileName: req.file.originalname,
      contentType: req.file.mimetype,
      size: req.file.size,
      visibility: 'private',
    });

    await recordUsage(req.userId, 'upload_count', 1, { file_id: file.id });
    await recordUsage(req.userId, 'upload_bytes', req.file.size, { file_id: file.id });

    res.json({
      id: file.id,
      key,
      file_name: req.file.originalname,
      size: req.file.size,
      content_type: req.file.mimetype,
    });
  } catch (err) {
    metrics.inc('upload_failures_total', { code: err.code || 'UPLOAD_FAILED' });
    return sendError(res, req, err.statusCode || 500, 'Upload failed', err);
  }
});

// Download private file (proxy from MinIO)
router.get('/:key(*)', async (req, res) => {
  try {
    const key = await assertCanReadR2Key(req.userId, req.params.key);
    const metadata = await getFileMetadata(key);
    const stream = await getFile(key);

    res.set('Content-Type', metadata.ContentType || 'application/octet-stream');
    res.set('X-Content-Type-Options', 'nosniff');
    res.set('Content-Disposition', `attachment; filename="${key.split('/').pop()}"`);
    stream.pipe(res);
  } catch (err) {
    return sendError(res, req, err.statusCode || 404, 'File not found', err);
  }
});

module.exports = router;

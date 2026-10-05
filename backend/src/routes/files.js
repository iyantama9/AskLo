const express = require('express');
const { getFileMetadata, getFile } = require('../utils/minio');
const { isPublicKey, normalizeR2Key } = require('../utils/files');
const { sendError } = require('../utils/errors');

const router = express.Router();

function normalizeEtag(etag) {
  if (!etag) return null;
  return etag.startsWith('"') ? etag : `"${etag}"`;
}

function isFresh(req, etag, lastModified) {
  const ifNoneMatch = req.headers['if-none-match'];
  if (etag && ifNoneMatch) {
    return ifNoneMatch
      .split(',')
      .map((item) => item.trim())
      .includes(etag);
  }

  const ifModifiedSince = req.headers['if-modified-since'];
  if (lastModified && ifModifiedSince) {
    const sinceTime = new Date(ifModifiedSince).getTime();
    if (!Number.isNaN(sinceTime)) {
      return lastModified.getTime() <= sinceTime;
    }
  }

  return false;
}

function setCacheHeaders(res, meta) {
  const etag = normalizeEtag(meta.ETag);
  const lastModified = meta.LastModified instanceof Date ? meta.LastModified : null;

  res.set('Content-Type', meta.ContentType || 'application/octet-stream');
  res.set('X-Content-Type-Options', 'nosniff');
  res.set('Cache-Control', meta.CacheControl || 'public, max-age=31536000, immutable');
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, If-None-Match, If-Modified-Since');
  if (etag) res.set('ETag', etag);
  if (lastModified) res.set('Last-Modified', lastModified.toUTCString());

  return { etag, lastModified };
}

// Handle CORS preflight
router.options('/*', (req, res) => {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, If-None-Match, If-Modified-Since');
  res.set('Access-Control-Max-Age', '86400'); // 24 hours
  res.status(204).end();
});

// Serve public generated images/screenshots only.
router.get('/*', async (req, res) => {
  const key = normalizeR2Key(req.params[0]);
  if (!key) return sendError(res, req, 400, 'File key required', null, 'FILE_KEY_REQUIRED');

  if (!isPublicKey(key)) {
    return sendError(res, req, 404, 'File not found');
  }

  try {
    const head = await getFileMetadata(key);

    const { etag, lastModified } = setCacheHeaders(res, head);
    if (isFresh(req, etag, lastModified)) {
      return res.status(304).end();
    }

    if (head.ContentLength != null) {
      res.set('Content-Length', String(head.ContentLength));
    }

    const stream = await getFile(key);
    stream.pipe(res);
  } catch (err) {
    return sendError(res, req, 404, 'File not found', err);
  }
});

module.exports = router;

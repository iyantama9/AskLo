const { pool } = require('../db');

const PUBLIC_PREFIXES = ['generated/', 'browse/', 'avatars/'];

function isPublicKey(key) {
  return PUBLIC_PREFIXES.some((prefix) => key.startsWith(prefix));
}

function normalizeR2Key(value) {
  if (!value) return '';
  const raw = String(value).trim();
  const marker = '/api/files/';
  const markerIndex = raw.indexOf(marker);
  if (markerIndex !== -1) {
    return decodeURIComponent(raw.slice(markerIndex + marker.length));
  }
  return raw.replace(/^\/+/, '');
}

async function recordFile({ ownerId, key, fileName, contentType, size, visibility = 'private' }) {
  const result = await pool.query(
    `INSERT INTO files (owner_id, r2_key, file_name, content_type, size, visibility)
     VALUES ($1, $2, $3, $4, $5, $6)
     ON CONFLICT (r2_key) DO UPDATE SET
       file_name = EXCLUDED.file_name,
       content_type = EXCLUDED.content_type,
       size = EXCLUDED.size,
       visibility = EXCLUDED.visibility
     RETURNING id, r2_key, file_name, content_type, size, visibility`,
    [ownerId, key, fileName, contentType, size, visibility]
  );
  return result.rows[0];
}

async function canReadR2Key(userId, rawKey) {
  const key = normalizeR2Key(rawKey);
  if (!key) return { allowed: false, key };
  if (isPublicKey(key)) return { allowed: true, key, visibility: 'public' };

  const file = await pool.query(
    'SELECT owner_id, visibility FROM files WHERE r2_key = $1',
    [key]
  );

  if (file.rows.length > 0) {
    const row = file.rows[0];
    return {
      allowed: row.visibility === 'public' || Number(row.owner_id) === Number(userId),
      key,
      visibility: row.visibility,
    };
  }

  const legacyPrefix = `uploads/${userId}/`;
  return {
    allowed: key.startsWith(legacyPrefix),
    key,
    visibility: 'private',
  };
}

async function assertCanReadR2Key(userId, rawKey) {
  const result = await canReadR2Key(userId, rawKey);
  if (!result.allowed) {
    const err = new Error('File not found');
    err.statusCode = 404;
    throw err;
  }
  return result.key;
}

module.exports = { PUBLIC_PREFIXES, isPublicKey, normalizeR2Key, recordFile, canReadR2Key, assertCanReadR2Key };

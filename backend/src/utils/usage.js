const { pool } = require('../db');
const metrics = require('./metrics');

const DEFAULT_LIMITS = {
  ai_request: 100,
  browse_request: 30,
  image_generation: 20,
  upload_count: 50,
  upload_bytes: 20 * 1024 * 1024,
};

const ENV_NAMES = {
  ai_request: 'QUOTA_AI_REQUESTS_PER_DAY',
  browse_request: 'QUOTA_BROWSE_REQUESTS_PER_DAY',
  image_generation: 'QUOTA_IMAGE_GENERATIONS_PER_DAY',
  upload_count: 'QUOTA_UPLOADS_PER_DAY',
  upload_bytes: 'QUOTA_UPLOAD_BYTES_PER_DAY',
};

function getLimit(kind) {
  const value = Number(process.env[ENV_NAMES[kind]] || DEFAULT_LIMITS[kind]);
  return Number.isFinite(value) && value >= 0 ? value : DEFAULT_LIMITS[kind];
}

async function getUsage(userId, kind) {
  const result = await pool.query(
    `SELECT COALESCE(SUM(amount), 0)::int AS total
     FROM usage_events
     WHERE user_id = $1 AND kind = $2 AND created_at > NOW() - INTERVAL '24 hours'`,
    [userId, kind]
  );
  return result.rows[0]?.total || 0;
}

async function checkQuota(userId, kind, amount = 1) {
  const limit = getLimit(kind);
  if (limit === 0) return { allowed: false, used: await getUsage(userId, kind), limit };

  // Check for active promotions with unlimited quota
  const promoResult = await pool.query(
    `SELECT p.unlimited_quota, p.quota_multiplier, p.custom_limits
     FROM user_promotions up
     JOIN promotions p ON up.promotion_id = p.id
     WHERE up.user_id = $1
       AND p.is_active = true
       AND NOW() BETWEEN p.start_date AND p.end_date
     ORDER BY p.unlimited_quota DESC, p.quota_multiplier DESC
     LIMIT 1`,
    [userId]
  );

  // If user has unlimited promotion, allow
  if (promoResult.rows.length > 0 && promoResult.rows[0].unlimited_quota) {
    return {
      allowed: true,
      used: await getUsage(userId, kind),
      limit: Infinity,
      remaining: Infinity,
      promotion: true,
    };
  }

  // If user has quota multiplier, apply it
  let effectiveLimit = limit;
  if (promoResult.rows.length > 0 && promoResult.rows[0].quota_multiplier) {
    effectiveLimit = Math.floor(limit * promoResult.rows[0].quota_multiplier);
  }

  // Check custom limits from promotion
  if (promoResult.rows.length > 0 && promoResult.rows[0].custom_limits) {
    const customLimits = promoResult.rows[0].custom_limits;
    if (customLimits[kind]) {
      effectiveLimit = customLimits[kind];
    }
  }

  const used = await getUsage(userId, kind);
  return {
    allowed: used + amount <= effectiveLimit,
    used,
    limit: effectiveLimit,
    remaining: Math.max(0, effectiveLimit - used),
    promotion: promoResult.rows.length > 0,
  };
}

async function assertQuota(userId, kind, amount = 1) {
  const quota = await checkQuota(userId, kind, amount);
  if (!quota.allowed) {
    metrics.inc('quota_exceeded_total', { kind });
    const err = new Error(
      `Quota harian tercapai untuk ${kind}. Terpakai ${quota.used}/${quota.limit}. Coba lagi besok atau hubungi admin.`
    );
    err.statusCode = 429;
    err.code = 'QUOTA_EXCEEDED';
    err.quota = { kind, amount, used: quota.used, limit: quota.limit };
    throw err;
  }
  return quota;
}

async function recordUsage(userId, kind, amount = 1, metadata = {}) {
  await pool.query(
    `INSERT INTO usage_events (user_id, kind, amount, metadata)
     VALUES ($1, $2, $3, $4::jsonb)`,
    [userId, kind, amount, JSON.stringify(metadata)]
  );
}

module.exports = { DEFAULT_LIMITS, getLimit, getUsage, checkQuota, assertQuota, recordUsage };

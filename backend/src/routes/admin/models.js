const express = require('express');
const { pool } = require('../../db');
const authMiddleware = require('../../middleware/auth');
const { adminOnly } = require('../../middleware/admin');
const { sendError } = require('../../utils/errors');
const { invalidateCache } = require('../../utils/modelCatalog');

const router = express.Router();
router.use(authMiddleware);
router.use(adminOnly);

// ── Helpers ──────────────────────────────────────────────────────────────────
function _displayNameFromId(modelId) {
  const parts = modelId.split('/');
  const raw = parts[parts.length - 1] || modelId;
  return raw.replace(/[-_]/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());
}

function _providerFromId(modelId) {
  const prefix = modelId.split('/')[0];
  const map = {
    mk: 'Anthropic', bm: 'OpenRouter', cv: 'OpenAI',
    kc: 'KimiChain', wz: 'WuZhi', qc: 'QwenChain',
    dh: 'DongHai', at: 'AT-Router',
  };
  return map[prefix] || prefix.toUpperCase();
}

function _guessCapabilities(modelId) {
  const lower = modelId.toLowerCase();
  const isVision = /vision|vl|multimodal|phi-4-multimodal|llama.*vision/i.test(lower);
  const isImage = /image|wan2|z-image/i.test(lower);
  const isImageEdit = /image.edit/i.test(lower);
  const isReasoning = /thinking|reason|o1|o3|opus.*thinking/i.test(lower);
  return {
    supports_reasoning: isReasoning,
    supports_vision: isVision || isImageEdit,
    supports_image_generation: isImage || isImageEdit,
    supports_browse: !isImage && !isImageEdit,
    cost_tier: isImage || isImageEdit ? 'image' : 'standard',
  };
}

// ── Sync models from active router into DB ───────────────────────────────────
router.post('/sync', async (req, res) => {
  try {
    // 1. Find active router config
    const configResult = await pool.query(
      `SELECT base_url, api_key, timeout_ms FROM router_configs
       WHERE is_active = true ORDER BY id ASC LIMIT 1`
    );

    if (!configResult.rows.length) {
      return sendError(res, req, 404, 'No active router configured', null, 'NO_ACTIVE_ROUTER');
    }

    const config = configResult.rows[0];
    const timeout = config.timeout_ms || 15000;

    // 2. Fetch models from router
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeout);

    let routerData;
    try {
      const response = await fetch(`${config.base_url}/v1/models`, {
        method: 'GET',
        headers: {
          'Authorization': `Bearer ${config.api_key}`,
          'Content-Type': 'application/json',
        },
        signal: controller.signal,
      });
      clearTimeout(timer);

      if (!response.ok) {
        return sendError(res, req, 502, `Router returned ${response.status}`, null, 'ROUTER_ERROR');
      }
      routerData = await response.json();
    } catch (fetchErr) {
      clearTimeout(timer);
      const msg = fetchErr.name === 'AbortError' ? 'Router timed out' : fetchErr.message;
      return sendError(res, req, 502, `Router unreachable: ${msg}`, fetchErr, 'ROUTER_UNREACHABLE');
    }

    const routerModels = (routerData.data || []);
    let synced = 0;

    // 3. Upsert each model
    for (const m of routerModels) {
      const caps = _guessCapabilities(m.id);
      await pool.query(
        `INSERT INTO models (id, owned_by, display_name, supports_reasoning, supports_vision,
           supports_image_generation, supports_browse, cost_tier, enabled, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, true, NOW())
         ON CONFLICT (id) DO NOTHING`,
        [
          m.id,
          _providerFromId(m.id),
          _displayNameFromId(m.id),
          caps.supports_reasoning,
          caps.supports_vision,
          caps.supports_image_generation,
          caps.supports_browse,
          caps.cost_tier,
        ]
      );
      synced++;
    }

    // 4. Invalidate cache so /api/models picks up changes
    invalidateCache();

    res.json({
      success: true,
      synced,
      message: `Synced ${synced} models from router`,
    });
  } catch (err) {
    return sendError(res, req, 500, 'Failed to sync models', err);
  }
});

// Get all models — the live catalog (router + DB overrides), same view the
// client sees, so the dashboard manages what users actually get.
router.get('/', async (req, res) => {
  try {
    const { listModels } = require('../../utils/modelCatalog');
    const { invalidateCache } = require('../../utils/modelCatalog');
    invalidateCache();
    const models = await listModels();
    res.json({ models });
  } catch (err) {
    return sendError(res, req, 500, 'Failed to fetch models', err);
  }
});

// Reorder models on the main page. Body: { ordered_ids: ["id1", "id2", ...] }.
// Assigns explicit sort_order 0..N so the catalog (and the picker) shows the
// models in exactly this sequence.
router.post('/reorder', async (req, res) => {
  const orderedIds = Array.isArray(req.body?.ordered_ids)
    ? req.body.ordered_ids.filter((id) => typeof id === 'string' && id.length)
    : [];
  if (!orderedIds.length) {
    return sendError(res, req, 400, 'ordered_ids must be a non-empty array', null, 'MISSING_ORDER');
  }

  try {
    // Ensure override rows exist for router-only models before ordering them.
    await pool.query(
      `INSERT INTO models (id, owned_by, display_name, enabled, updated_at)
       SELECT m.id, split_part(m.id, '/', 1), m.id, true, NOW()
       FROM unnest($1::text[]) AS m(id)
       ON CONFLICT (id) DO NOTHING`,
      [orderedIds]
    );

    await Promise.all(
      orderedIds.map((id, index) =>
        pool.query('UPDATE models SET sort_order = $2, updated_at = NOW() WHERE id = $1', [id, index])
      )
    );

    invalidateCache();
    res.json({ success: true, reordered: orderedIds.length });
  } catch (err) {
    return sendError(res, req, 500, 'Failed to reorder models', err);
  }
});

// Get single model
router.get('/:id', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT * FROM models WHERE id = $1',
      [req.params.id]
    );

    if (!result.rows.length) {
      return sendError(res, req, 404, 'Model not found', null, 'MODEL_NOT_FOUND');
    }

    res.json({ model: result.rows[0] });
  } catch (err) {
    return sendError(res, req, 500, 'Failed to fetch model', err);
  }
});

// Create new model (upsert so router-only models can be overridden)
router.post('/', async (req, res) => {
  const {
    id,
    owned_by,
    display_name,
    supports_reasoning,
    supports_vision,
    supports_image_generation,
    supports_browse,
    cost_tier,
    enabled,
  } = req.body;

  if (!id || !owned_by || !display_name) {
    return sendError(res, req, 400, 'Missing required fields: id, owned_by, display_name', null, 'MISSING_FIELDS');
  }

  try {
    const result = await pool.query(
      `INSERT INTO models (
        id, owned_by, display_name, supports_reasoning, supports_vision,
        supports_image_generation, supports_browse, cost_tier, enabled
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
      ON CONFLICT (id) DO UPDATE SET
        owned_by = EXCLUDED.owned_by,
        display_name = EXCLUDED.display_name,
        supports_reasoning = EXCLUDED.supports_reasoning,
        supports_vision = EXCLUDED.supports_vision,
        supports_image_generation = EXCLUDED.supports_image_generation,
        supports_browse = EXCLUDED.supports_browse,
        cost_tier = EXCLUDED.cost_tier,
        enabled = EXCLUDED.enabled,
        updated_at = NOW()
      RETURNING *`,
      [
        id,
        owned_by,
        display_name,
        supports_reasoning || false,
        supports_vision || false,
        supports_image_generation || false,
        supports_browse || false,
        cost_tier || 'standard',
        enabled !== false,
      ]
    );

    res.status(201).json({ model: result.rows[0] });
    invalidateCache();
  } catch (err) {
    if (err.code === '23505') {
      return sendError(res, req, 409, 'Model ID already exists', err, 'MODEL_EXISTS');
    }
    return sendError(res, req, 500, 'Failed to create model', err);
  }
});

// Update model
router.put('/:id', async (req, res) => {
  const {
    owned_by,
    display_name,
    supports_reasoning,
    supports_vision,
    supports_image_generation,
    supports_browse,
    cost_tier,
    enabled,
  } = req.body;

  try {
    const result = await pool.query(
      `UPDATE models SET
        owned_by = COALESCE($2, owned_by),
        display_name = COALESCE($3, display_name),
        supports_reasoning = COALESCE($4, supports_reasoning),
        supports_vision = COALESCE($5, supports_vision),
        supports_image_generation = COALESCE($6, supports_image_generation),
        supports_browse = COALESCE($7, supports_browse),
        cost_tier = COALESCE($8, cost_tier),
        enabled = COALESCE($9, enabled),
        updated_at = NOW()
      WHERE id = $1
      RETURNING *`,
      [
        req.params.id,
        owned_by,
        display_name,
        supports_reasoning,
        supports_vision,
        supports_image_generation,
        supports_browse,
        cost_tier,
        enabled,
      ]
    );

    if (!result.rows.length) {
      return sendError(res, req, 404, 'Model not found', null, 'MODEL_NOT_FOUND');
    }

    res.json({ model: result.rows[0] });
    invalidateCache();
  } catch (err) {
    return sendError(res, req, 500, 'Failed to update model', err);
  }
});

// Bulk enable/disable — a single statement keeps 40-model toggles atomic.
// A trailing segment that is none of the known sub-resources is treated as
// the model id; ids are still path-encoded (e.g. wz%2Fgrok-4.7) in that case.
router.patch('/bulk', async (req, res) => {
  const ids = Array.isArray(req.body?.ids) ? req.body.ids : [];
  const enabled = typeof req.body?.enabled === 'boolean' ? req.body.enabled : true;
  if (!ids.length) {
    return sendError(res, req, 400, 'ids must be a non-empty array', null, 'MISSING_IDS');
  }

  try {
    // Ensure override rows exist for router-only models first.
    await pool.query(
      `INSERT INTO models (id, owned_by, display_name, enabled, updated_at)
       SELECT m.id,
              split_part(m.id, '/', 1),
              m.id,
              $2,
              NOW()
       FROM unnest($1::text[]) AS m(id)
       ON CONFLICT (id) DO NOTHING`,
      [ids, enabled]
    );

    const result = await pool.query(
      `UPDATE models SET enabled = $2, updated_at = NOW()
       WHERE id = ANY($1::text[])
       RETURNING id`,
      [ids, enabled]
    );

    invalidateCache();
    res.json({ success: true, updated: result.rows.length });
  } catch (err) {
    return sendError(res, req, 500, 'Failed to update models', err);
  }
});

// Delete model (removes the override; a router-advertised model with no
// override row simply reverts to its router-provided metadata)
router.delete('/:id', async (req, res) => {
  try {
    const result = await pool.query(
      'DELETE FROM models WHERE id = $1 RETURNING id',
      [req.params.id]
    );

    if (!result.rows.length) {
      return sendError(res, req, 404, 'Model not found', null, 'MODEL_NOT_FOUND');
    }

    res.json({ success: true, deleted_id: result.rows[0].id });
  } catch (err) {
    return sendError(res, req, 500, 'Failed to delete model', err);
  }
});

// Toggle model enabled/disabled. Router-advertised models without a DB
// override row get one created (enabled=true) so the first toggle disables it.
router.patch('/:id/toggle', async (req, res) => {
  try {
    await pool.query(
      `INSERT INTO models (id, owned_by, display_name, enabled, updated_at)
       VALUES ($1, $2, $3, true, NOW())
       ON CONFLICT (id) DO NOTHING`,
      [
        req.params.id,
        _providerFromId(req.params.id),
        _displayNameFromId(req.params.id),
      ]
    );

    const result = await pool.query(
      `UPDATE models SET enabled = NOT enabled, updated_at = NOW()
       WHERE id = $1
       RETURNING *`,
      [req.params.id]
    );

    if (!result.rows.length) {
      return sendError(res, req, 404, 'Model not found', null, 'MODEL_NOT_FOUND');
    }

    res.json({ model: result.rows[0] });
    invalidateCache();
  } catch (err) {
    return sendError(res, req, 500, 'Failed to toggle model', err);
  }
});

module.exports = router;

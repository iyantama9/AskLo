/**
 * Dynamic model catalog.
 *
 * The active router owns catalog membership. Database rows are metadata and
 * enablement overrides only; they can never add a model that the router does
 * not currently advertise.
 */
const { pool } = require('../db');
const { fetchRouterModels } = require('./routerClient');

let modelsCache = null;
let lastCacheUpdate = 0;
const CACHE_TTL = 5 * 60 * 1000;

function displayNameFromId(modelId) {
  const raw = modelId.split('/').pop() || modelId;
  return raw.replace(/[-_]/g, ' ').replace(/\b\w/g, (character) => character.toUpperCase());
}

function providerFromId(modelId, advertisedOwner) {
  if (advertisedOwner && advertisedOwner !== 'iyan-router') return advertisedOwner;
  const prefix = modelId.split('/')[0];
  const providers = {
    mk: 'Anthropic', bm: 'OpenRouter', cv: 'OpenAI', kc: 'KimiChain',
    wz: 'WuZhi', qc: 'QwenChain', dh: 'DongHai', at: 'AT-Router',
    ynd: 'Iyan Router', nn: 'Nara',
  };
  return providers[prefix] || prefix.toUpperCase();
}

function guessCapabilities(modelId) {
  const lower = modelId.toLowerCase();
  const isVision = /vision|vl|multimodal|phi-4-multimodal|llama.*vision/i.test(lower);
  const isImage = /image|wan2|z-image/i.test(lower);
  const isImageEdit = /image.edit|image-edit/i.test(lower);
  const isReasoning = /thinking|reason|o1|o3|opus.*thinking/i.test(lower);
  return {
    supports_reasoning: isReasoning,
    supports_vision: isVision || isImageEdit,
    supports_image_generation: isImage || isImageEdit,
    supports_browse: !isImage && !isImageEdit,
    cost_tier: isImage || isImageEdit ? 'image' : 'standard',
  };
}

async function loadDbOverrides() {
  const result = await pool.query('SELECT * FROM models ORDER BY display_name ASC');
  return result.rows;
}

/**
 * Load admin-uploaded brand logos per provider. Returns a Map keyed by the
 * provider name (owned_by) to its public logo URL.
 */
async function loadProviderLogos() {
  try {
    const result = await pool.query('SELECT provider, logo_url FROM provider_logos');
    const map = new Map();
    for (const row of result.rows) map.set(row.provider, row.logo_url);
    return map;
  } catch (error) {
    // Table may not exist yet on a fresh deploy; degrade to no logos.
    return new Map();
  }
}

function mergeRouterModels(routerModels, dbModels, logoMap) {
  const overrides = new Map(dbModels.map((model) => [model.id, model]));
  const logos = logoMap || new Map();
  const merged = [];

  for (const advertised of routerModels) {
    const override = overrides.get(advertised.id);
    if (override?.enabled === false) continue;
    const inferred = guessCapabilities(advertised.id);
    const provider = override?.owned_by || providerFromId(advertised.id, advertised.owned_by);
    merged.push({
      id: advertised.id,
      owned_by: provider,
      display_name: override?.display_name || displayNameFromId(advertised.id),
      logo_url: logos.get(provider) || null,
      supports_reasoning: override?.supports_reasoning ?? inferred.supports_reasoning,
      supports_vision: override?.supports_vision ?? inferred.supports_vision,
      supports_image_generation: override?.supports_image_generation ?? inferred.supports_image_generation,
      supports_browse: override?.supports_browse ?? inferred.supports_browse,
      cost_tier: override?.cost_tier || inferred.cost_tier,
      sort_order: override?.sort_order ?? null,
      enabled: true,
      source: override ? 'router+db' : 'router',
    });
  }

  // Admin-controlled ordering: explicit sort_order wins (lower first, nulls
  // last); remaining ties fall back to display name for a stable catalog.
  merged.sort((a, b) => {
    const ao = a.sort_order;
    const bo = b.sort_order;
    if (ao != null && bo != null) return ao - bo;
    if (ao != null) return -1;
    if (bo != null) return 1;
    return (a.display_name || '').localeCompare(b.display_name || '');
  });
  return merged;
}

async function refreshModelsCache() {
  try {
    const [routerModels, dbModels, logoMap] = await Promise.all([
      fetchRouterModels(),
      loadDbOverrides(),
      loadProviderLogos(),
    ]);
    const merged = mergeRouterModels(routerModels, dbModels, logoMap);
    // Purge stale overrides: models that are in the DB but no longer advertised
  // by the active router would otherwise leak into the catalog on the next
  // refresh. The router owns catalog membership.
  const advertised = new Set(routerModels.map((m) => m.id));
  await pool.query(
    'DELETE FROM models WHERE id = ANY($1::text[])',
    [dbModels.map((m) => m.id).filter((id) => !advertised.has(id))]
  );

  if (merged.length === 0) {
      const error = new Error('No enabled models are available from the active router');
      error.code = 'EMPTY_MODEL_CATALOG';
      error.statusCode = 503;
      throw error;
    }
    modelsCache = merged;
    lastCacheUpdate = Date.now();
    return modelsCache;
  } catch (error) {
    // Keep the last known good catalog for transient failures; fail closed on a
    // cold start rather than advertising models the router may not serve.
    if (modelsCache?.length) return modelsCache;
    throw error;
  }
}

async function getModelsFromDB() {
  if (!modelsCache || Date.now() - lastCacheUpdate > CACHE_TTL) return refreshModelsCache();
  return modelsCache;
}

async function listModels() {
  return getModelsFromDB();
}

async function findModel(id) {
  const models = await getModelsFromDB();
  return models.find((model) => model.id === id) || null;
}

async function assertValidModel(id) {
  const model = await findModel(id);
  if (model) return model;
  const error = new Error('Model is not available');
  error.statusCode = 400;
  error.code = 'MODEL_NOT_AVAILABLE';
  throw error;
}

function invalidateCache() {
  modelsCache = null;
  lastCacheUpdate = 0;
}

async function configuredModel(settingKey) {
  const result = await pool.query('SELECT value FROM admin_settings WHERE key = $1', [settingKey]);
  if (!result.rows.length) return null;
  const value = result.rows[0].value;
  if (value == null) return null;
  return typeof value === 'string' ? value : String(value || '');
}

async function getFallbackModel(type = 'chat') {
  const settingKey = type === 'image' ? 'fallback_image' : 'fallback_chat';
  const configured = await configuredModel(settingKey);
  if (configured && await findModel(configured)) return configured;
  const wantsImage = type === 'image';
  const models = await getModelsFromDB();
  return models.find((model) => model.supports_image_generation === wantsImage)?.id || null;
}

// The admin-configured default model; falls back to the configured fallback so
// the client always receives a model that currently exists in the catalog.
async function getDefaultModel() {
  const configured = await configuredModel('default_model');
  if (configured && await findModel(configured)) return configured;
  return getFallbackModel('chat');
}

async function getFallbackModels(type = 'chat') {
  const primary = await getFallbackModel(type);
  const wantsImage = type === 'image';
  const models = await getModelsFromDB();
  const candidates = models
    .filter((model) => model.supports_image_generation === wantsImage)
    .map((model) => model.id);
  return [primary, ...candidates].filter((value, index, values) =>
    value && values.indexOf(value) === index
  );
}

module.exports = {
  listModels, findModel, assertValidModel, invalidateCache,
  refreshModelsCache, getFallbackModel, getFallbackModels, getDefaultModel,
  mergeRouterModels,
};

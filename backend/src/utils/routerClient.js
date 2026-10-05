const { pool } = require('../db');

const DEFAULT_TIMEOUT_MS = 15000;
// Streaming responses can be long: use a much longer cap so the connection
// and the stream aren't killed mid-answer. The consumer adds an idle
// watchdog so a truly hung stream still surfaces instead of hanging forever.
const STREAM_TIMEOUT_MS = 300000; // 5 minutes
const MAX_MODELS = 5000;

function normalizeRouterBaseUrl(value) {
  let url;
  try {
    url = new URL(String(value || '').trim());
  } catch (_) {
    throw new Error('Router base URL must be a valid http(s) URL');
  }

  if (url.protocol !== 'http:' && url.protocol !== 'https:') {
    throw new Error('Router base URL must use http or https');
  }
  if (url.username || url.password) {
    throw new Error('Router base URL must not contain credentials');
  }
  if (url.search || url.hash) {
    throw new Error('Router base URL must not contain query strings or fragments');
  }

  const pathname = url.pathname.replace(/\/+$/, '');
  url.pathname = pathname.endsWith('/v1') ? pathname : `${pathname}/v1`;
  return url.toString().replace(/\/$/, '');
}

function buildRouterEndpoint(baseUrl, resource) {
  const cleanResource = String(resource || '').replace(/^\/+/, '');
  if (!cleanResource) throw new Error('Router resource is required');
  return `${normalizeRouterBaseUrl(baseUrl)}/${cleanResource}`;
}

async function getActiveRouterConfig() {
  const result = await pool.query(
    `SELECT id, name, base_url, api_key, timeout_ms, max_retries, metadata
     FROM router_configs
     WHERE is_active = true
     ORDER BY id ASC
     LIMIT 1`
  );
  if (!result.rows.length) {
    const error = new Error('No active router configured');
    error.code = 'NO_ACTIVE_ROUTER';
    error.statusCode = 503;
    throw error;
  }
  return result.rows[0];
}

function timeoutSignal(timeoutMs) {
  return AbortSignal.timeout(Number(timeoutMs) || DEFAULT_TIMEOUT_MS);
}

async function fetchRouterModels({ config, strict = true } = {}) {
  const activeConfig = config || await getActiveRouterConfig();
  let response;
  try {
    response = await fetch(buildRouterEndpoint(activeConfig.base_url, 'models'), {
      method: 'GET',
      headers: {
        Authorization: `Bearer ${activeConfig.api_key}`,
        'Content-Type': 'application/json',
      },
      redirect: 'error',
      signal: timeoutSignal(activeConfig.timeout_ms),
    });
  } catch (cause) {
    if (!strict) return null;
    const error = new Error('Router model catalog is unreachable');
    error.code = 'ROUTER_UNREACHABLE';
    error.statusCode = 502;
    error.cause = cause;
    throw error;
  }

  if (!response.ok) {
    if (!strict) return null;
    const error = new Error(`Router model catalog returned HTTP ${response.status}`);
    error.code = 'ROUTER_ERROR';
    error.statusCode = 502;
    throw error;
  }

  let payload;
  try {
    payload = await response.json();
  } catch (cause) {
    if (!strict) return null;
    const error = new Error('Router model catalog returned invalid JSON');
    error.code = 'INVALID_ROUTER_RESPONSE';
    error.statusCode = 502;
    error.cause = cause;
    throw error;
  }

  const source = Array.isArray(payload?.data) ? payload.data : [];
  const seen = new Set();
  const models = [];
  for (const item of source.slice(0, MAX_MODELS)) {
    const id = typeof item?.id === 'string' ? item.id.trim() : '';
    if (!id || id.length > 255 || seen.has(id)) continue;
    seen.add(id);
    models.push({ ...item, id });
  }

  if (strict && models.length === 0) {
    const error = new Error('Router model catalog is empty');
    error.code = 'EMPTY_ROUTER_CATALOG';
    error.statusCode = 502;
    throw error;
  }
  return models;
}

async function requestRouterMessages({
  model,
  messages,
  system,
  stream = false,
  max_tokens = null,
}) {
  const config = await getActiveRouterConfig();
  const payload = {
    model,
    messages: system
      ? [{ role: 'system', content: system }, ...messages]
      : messages,
    stream,
  };
  // Only cap output length when a caller explicitly asks for one
  // (e.g. title generation). Regular chat is sent without a limit so
  // long answers are not cut off mid-code.
  if (max_tokens) payload.max_tokens = max_tokens;
  // Streaming calls get a longer hard cap so long answers are not cut off
  // mid-stream; non-streaming calls keep the router's configured timeout.
  const signal = stream
    ? AbortSignal.timeout(
        Math.max(Number(config.timeout_ms) || DEFAULT_TIMEOUT_MS, STREAM_TIMEOUT_MS)
      )
    : timeoutSignal(config.timeout_ms);
  return fetch(buildRouterEndpoint(config.base_url, 'chat/completions'), {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${config.api_key}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
    redirect: 'error',
    signal,
  });
}

module.exports = {
  normalizeRouterBaseUrl,
  buildRouterEndpoint,
  getActiveRouterConfig,
  fetchRouterModels,
  requestRouterMessages,
};

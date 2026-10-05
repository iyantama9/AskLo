jest.mock('../src/db', () => ({
  pool: { query: jest.fn() },
}));

const { pool } = require('../src/db');

const CONFIG = {
  id: 7,
  name: 'Iyan Router',
  base_url: 'https://routers.iyantama.tech/v1',
  api_key: 'test-router-key',
  timeout_ms: 15000,
  metadata: {},
};

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

describe('routerClient', () => {
  beforeEach(() => {
    pool.query.mockReset();
    global.fetch = jest.fn();
  });

  afterEach(() => {
    delete global.fetch;
  });

  test.each([
    ['https://router.example.com', 'https://router.example.com/v1'],
    ['https://router.example.com/', 'https://router.example.com/v1'],
    ['https://router.example.com/v1', 'https://router.example.com/v1'],
    ['https://router.example.com/v1/', 'https://router.example.com/v1'],
  ])('normalizes %s without duplicating /v1', (input, expected) => {
    const { normalizeRouterBaseUrl } = require('../src/utils/routerClient');
    expect(normalizeRouterBaseUrl(input)).toBe(expected);
  });

  test('builds one /v1/models segment', () => {
    const { buildRouterEndpoint } = require('../src/utils/routerClient');
    expect(buildRouterEndpoint(CONFIG.base_url, 'models')).toBe(
      'https://routers.iyantama.tech/v1/models'
    );
  });

  test('loads the single active router from the database', async () => {
    pool.query.mockResolvedValue({ rows: [CONFIG] });
    const { getActiveRouterConfig } = require('../src/utils/routerClient');

    await expect(getActiveRouterConfig()).resolves.toEqual(CONFIG);
    expect(pool.query).toHaveBeenCalledWith(expect.stringContaining('WHERE is_active = true'));
  });

  test('fetches and deduplicates the 17-model router catalog', async () => {
    const data = Array.from({ length: 17 }, (_, index) => ({
      id: `provider/model-${index + 1}`,
      object: 'model',
    }));
    global.fetch.mockResolvedValue(jsonResponse({ object: 'list', data: [...data, data[0]] }));

    const { fetchRouterModels } = require('../src/utils/routerClient');
    const models = await fetchRouterModels({ config: CONFIG });

    expect(models).toHaveLength(17);
    expect(global.fetch).toHaveBeenCalledWith(
      'https://routers.iyantama.tech/v1/models',
      expect.objectContaining({
        headers: expect.objectContaining({
          Authorization: 'Bearer test-router-key',
        }),
      })
    );
  });

  test('routes OpenAI chat completions through the active database router', async () => {
    pool.query.mockResolvedValue({ rows: [CONFIG] });
    global.fetch.mockResolvedValue(jsonResponse({
      choices: [{ message: { role: 'assistant', content: 'ok' } }],
    }));

    const { requestRouterMessages } = require('../src/utils/routerClient');
    const response = await requestRouterMessages({
      model: 'provider/model-1',
      messages: [{ role: 'user', content: 'hello' }],
      system: 'Be concise.',
      max_tokens: 32,
      stream: false,
    });

    expect(response.ok).toBe(true);
    expect(global.fetch).toHaveBeenCalledWith(
      'https://routers.iyantama.tech/v1/chat/completions',
      expect.objectContaining({
        method: 'POST',
        headers: expect.objectContaining({
          Authorization: 'Bearer test-router-key',
        }),
        body: JSON.stringify({
          model: 'provider/model-1',
          messages: [
            { role: 'system', content: 'Be concise.' },
            { role: 'user', content: 'hello' },
          ],
          max_tokens: 32,
          stream: false,
        }),
      })
    );
  });

  test('rejects base URLs that could leak credentials', () => {
    const { normalizeRouterBaseUrl } = require('../src/utils/routerClient');
    expect(() => normalizeRouterBaseUrl('ftp://router.example.com')).toThrow('http');
    expect(() => normalizeRouterBaseUrl('https://user:pass@router.example.com')).toThrow(
      'credentials'
    );
  });
});

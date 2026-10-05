jest.mock('../src/db', () => ({
  pool: { query: jest.fn() },
}));

jest.mock('../src/utils/routerClient', () => ({
  fetchRouterModels: jest.fn(),
}));

const { pool } = require('../src/db');
const { fetchRouterModels } = require('../src/utils/routerClient');
const catalog = require('../src/utils/modelCatalog');

describe('dynamic model catalog', () => {
  beforeEach(() => {
    pool.query.mockReset();
    fetchRouterModels.mockReset();
    catalog.invalidateCache();
  });

  test('uses router membership only and excludes stale DB-only rows', async () => {
    fetchRouterModels.mockResolvedValue([
      { id: 'wz/live-model' },
      { id: 'ynd/yr/auto' },
    ]);
    pool.query.mockResolvedValue({
      rows: [
        { id: 'wz/live-model', display_name: 'Live override', enabled: true },
        { id: 'old/hardcoded-model', display_name: 'Stale', enabled: true },
      ],
    });

    const { listModels } = catalog;
    const models = await listModels();

    expect(models.map((model) => model.id)).toEqual(['wz/live-model', 'ynd/yr/auto']);
    expect(models[0].display_name).toBe('Live override');
    expect(models.some((model) => model.id === 'old/hardcoded-model')).toBe(false);
  });

  test('honors a disabled DB override for a live router model', async () => {
    fetchRouterModels.mockResolvedValue([
      { id: 'wz/disabled-model' },
      { id: 'wz/enabled-model' },
    ]);
    pool.query.mockResolvedValue({
      rows: [{ id: 'wz/disabled-model', enabled: false }],
    });

    const { listModels } = catalog;
    const models = await listModels();

    expect(models.map((model) => model.id)).toEqual(['wz/enabled-model']);
  });

  test('fails closed on cold start when the router is unavailable', async () => {
    fetchRouterModels.mockRejectedValue(new Error('router down'));
    pool.query.mockResolvedValue({ rows: [] });

    const { listModels } = catalog;
    await expect(listModels()).rejects.toThrow('router down');
  });

  test('keeps the last known good catalog during a transient refresh failure', async () => {
    fetchRouterModels
      .mockResolvedValueOnce([{ id: 'wz/live-model' }])
      .mockRejectedValueOnce(new Error('temporary outage'));
    pool.query.mockResolvedValue({ rows: [] });

    const { listModels, refreshModelsCache } = catalog;
    await expect(listModels()).resolves.toHaveLength(1);
    await expect(refreshModelsCache()).resolves.toHaveLength(1);
    await expect(listModels()).resolves.toEqual(
      expect.arrayContaining([expect.objectContaining({ id: 'wz/live-model' })])
    );
  });
});

const express = require('express');
const request = require('supertest');

jest.mock('../src/db', () => ({
  pool: { query: jest.fn() },
}));
jest.mock('../src/middleware/auth', () => (req, res, next) => {
  req.userId = 42;
  next();
});
jest.mock('../src/utils/modelCatalog', () => ({
  assertValidModel: jest.fn(),
  getFallbackModel: jest.fn(),
}));

const { pool } = require('../src/db');
const { assertValidModel, getFallbackModel } = require('../src/utils/modelCatalog');
const chatsRouter = require('../src/routes/chats');

const app = express();
app.use(express.json());
app.use('/chats', chatsRouter);

describe('dynamic chat model selection', () => {
  beforeEach(() => {
    pool.query.mockReset();
    assertValidModel.mockReset();
    getFallbackModel.mockReset();
  });

  test('creates a chat with the dynamic fallback when no model is supplied', async () => {
    getFallbackModel.mockResolvedValue('router/live-model');
    assertValidModel.mockResolvedValue({ id: 'router/live-model' });
    pool.query.mockResolvedValue({
      rows: [{ id: 1, title: 'New Chat', model: 'router/live-model' }],
    });

    const response = await request(app).post('/chats').send({});

    expect(response.status).toBe(201);
    expect(getFallbackModel).toHaveBeenCalledWith('chat');
    expect(assertValidModel).toHaveBeenCalledWith('router/live-model');
    expect(pool.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO chats'),
      [42, 'New Chat', 'router/live-model']
    );
  });

  test('awaits model validation before updating a chat', async () => {
    const invalid = Object.assign(new Error('Model is not available'), { statusCode: 400 });
    assertValidModel.mockRejectedValue(invalid);

    const response = await request(app)
      .put('/chats/1')
      .send({ model: 'router/missing-model' });

    expect(response.status).toBe(400);
    expect(pool.query).not.toHaveBeenCalled();
  });
});

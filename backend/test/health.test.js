jest.mock('../src/db', () => ({
  initDB: jest.fn(),
  pool: {
    query: jest.fn(),
  },
}));

jest.mock('../src/routes/auth', () => {
  const express = require('express');
  return express.Router();
});
jest.mock('../src/routes/chats', () => {
  const express = require('express');
  return express.Router();
});
jest.mock('../src/routes/messages', () => {
  const express = require('express');
  return express.Router();
});
jest.mock('../src/routes/upload', () => {
  const express = require('express');
  return express.Router();
});
jest.mock('../src/routes/files', () => {
  const express = require('express');
  return express.Router();
});
jest.mock('../src/routes/browse', () => {
  const express = require('express');
  return express.Router();
});

const request = require('supertest');
const { pool } = require('../src/db');

const ORIGINAL_ENV = { ...process.env };
const REQUIRED_ENV = {
  DATABASE_URL: 'postgres://test:test@localhost/test',
  JWT_SECRET: 'test-secret',
  AI_BASE_URL: 'https://ai.example.test',
  AI_API_KEY: 'test-ai-key',
  MINIO_ENDPOINT: 'localhost:9000',
  MINIO_ACCESS_KEY: 'test-access',
  MINIO_SECRET_KEY: 'test-secret-key',
  MINIO_BUCKET: 'test-bucket',
  MINIO_PUBLIC_ENDPOINT: 'localhost:9000',
};

process.env = { ...ORIGINAL_ENV, ...REQUIRED_ENV };
const { app, getMissingEnv } = require('../src/index');

describe('health endpoints', () => {
  beforeEach(() => {
    process.env = { ...ORIGINAL_ENV, ...REQUIRED_ENV };
    pool.query.mockReset();
  });

  afterAll(() => {
    process.env = ORIGINAL_ENV;
  });

  test('liveness endpoint returns ok', async () => {
    await request(app).get('/api/health/live').expect(200, { status: 'ok' });
  });

  test('legacy health endpoint remains available', async () => {
    await request(app).get('/api/health').expect(200, { status: 'ok' });
  });

  test('readiness endpoint checks config and database', async () => {
    pool.query.mockResolvedValue({ rows: [{ '?column?': 1 }] });

    const response = await request(app).get('/api/health/ready').expect(200);

    expect(response.body).toMatchObject({
      status: 'ok',
      checks: { config: 'ok', database: 'ok' },
    });
    expect(response.body.db_pool).toBeDefined();
    expect(pool.query).toHaveBeenCalledWith('SELECT 1');
  });

  test('readiness fails when required env is missing', async () => {
    delete process.env.JWT_SECRET;

    const response = await request(app).get('/api/health/ready').expect(503);

    expect(response.body.error).toBe('Readiness check failed');
    expect(response.body.code).toBe('READINESS_FAILED');
    expect(response.body.missing_env).toContain('JWT_SECRET');
    expect(response.body.request_id).toBeDefined();
    expect(response.body.status).toBeUndefined();
  });

  test('getMissingEnv lists missing config names', () => {
    delete process.env.AI_API_KEY;
    expect(getMissingEnv()).toContain('AI_API_KEY');
  });
});

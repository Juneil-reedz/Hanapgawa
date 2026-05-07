const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');

const { app } = require('../src/app');

test('GET / returns API metadata', async () => {
  const response = await request(app).get('/');

  assert.equal(response.status, 200);
  assert.equal(response.body.name, 'HanapGawa Backend API');
  assert.equal(response.body.version, '0.1.0');
  assert.equal(response.body.docsHint, '/api/v1/health');
});

test('GET /api/v1/health returns ok status', async () => {
  const response = await request(app).get('/api/v1/health');

  assert.equal(response.status, 200);
  assert.equal(response.body.service, 'hanapgawa-backend');
  assert.equal(response.body.status, 'ok');
  assert.equal(typeof response.body.databases, 'object');
});

test('POST /api/v1/auth/register rejects invalid payload', async () => {
  const response = await request(app).post('/api/v1/auth/register').send({
    email: 'bad-email',
    password: '123',
    role: 'client',
    fullName: 'A',
  });

  assert.equal(response.status, 400);
  assert.equal(response.body.error.message, 'Invalid registration payload.');
});

test('POST /api/v1/auth/login rejects invalid payload', async () => {
  const response = await request(app).post('/api/v1/auth/login').send({
    email: 'bad-email',
    password: '123',
  });

  assert.equal(response.status, 400);
  assert.equal(response.body.error.message, 'Invalid login payload.');
});

test('GET /api/v1/auth/me requires bearer token', async () => {
  const response = await request(app).get('/api/v1/auth/me');

  assert.equal(response.status, 401);
  assert.equal(response.body.error.message, 'Missing bearer token.');
});

test('POST /api/v1/providers requires authentication', async () => {
  const response = await request(app).post('/api/v1/providers').send({
    displayName: 'Test Provider',
    category: 'Carpentry',
    municipality: 'Bongao',
    services: ['Door repair'],
    portfolio: [],
  });

  assert.equal(response.status, 401);
  assert.equal(response.body.error.message, 'Missing bearer token.');
});

test('POST /api/v1/bookings requires authentication', async () => {
  const response = await request(app).post('/api/v1/bookings').send({
    providerUserId: '550e8400-e29b-41d4-a716-446655440000',
    serviceCategory: 'Carpentry',
    municipality: 'Bongao',
    notes: 'Need a repair',
  });

  assert.equal(response.status, 401);
  assert.equal(response.body.error.message, 'Missing bearer token.');
});

test('POST /api/v1/reviews requires authentication', async () => {
  const response = await request(app).post('/api/v1/reviews').send({
    bookingId: '550e8400-e29b-41d4-a716-446655440000',
    rating: 5,
    comment: 'Great service',
  });

  assert.equal(response.status, 401);
  assert.equal(response.body.error.message, 'Missing bearer token.');
});

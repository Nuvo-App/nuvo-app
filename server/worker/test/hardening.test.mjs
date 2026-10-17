// Global JSON error handling, /health, /config and bad-body guards.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test from 'node:test';
const require = createRequire(import.meta.url);
const app = require('../.tmp-test-dist/index.js').default;
const { signJwt } = require('../.tmp-test-dist/lib/jwt.js');

const okDb = { prepare: () => ({ bind() { return this; }, first: async () => ({ 1: 1 }), all: async () => ({ results: [] }), run: async () => ({}) }) };
const badDb = { prepare: () => { throw new Error('d1 down'); } };
const ctx = { waitUntil() {}, passThroughOnException() {} };

test('/health reports db true/false and is always 200', async () => {
  let r = await app.request('/health', {}, { DB: okDb, JWT_SECRET: 's' }, ctx);
  assert.equal(r.status, 200);
  const j = await r.json();
  assert.equal(j.ok, true); assert.equal(j.db, true); assert.ok(j.version); assert.ok(j.time);
  r = await app.request('/health', {}, { DB: badDb, JWT_SECRET: 's' }, ctx);
  assert.equal(r.status, 200);
  assert.equal((await r.json()).db, false);
});

test('uncaught throw becomes JSON server_error, with CORS kept; 404 is JSON', async () => {
  const token = await signJwt({ sub: 'u1', iat: 0, exp: 9999999999 }, 's');
  const r = await app.request('/squads', { headers: { Authorization: `Bearer ${token}`, Origin: 'https://getnuvo.net' } }, { DB: badDb, JWT_SECRET: 's' }, ctx);
  assert.equal(r.status, 500);
  assert.match(r.headers.get('content-type'), /json/);
  assert.equal(r.headers.get('access-control-allow-origin'), 'https://getnuvo.net');
  const j = await r.json();
  assert.deepEqual(j, { ok: false, error: 'Something went wrong on our side. Try again.', code: 'server_error' });
  const nf = await app.request('/nope', {}, { DB: okDb, JWT_SECRET: 's' }, ctx);
  assert.equal(nf.status, 404);
  assert.equal((await nf.json()).ok, false);
});

test('/config never throws, even with a broken DB and a bad token', async () => {
  const r = await app.request('/config', { headers: { Authorization: 'Bearer junk' } }, { DB: badDb, JWT_SECRET: 's', CUSTOM_MOTION_USERS: 'a@b.c' }, ctx);
  assert.equal(r.status, 200);
  assert.equal((await r.json()).custom_motion, false);
});

test('null JSON bodies are a clean 400, not a 500', async () => {
  const token = await signJwt({ sub: 'u1', iat: 0, exp: 9999999999 }, 's');
  for (const [m, p] of [['POST', '/invites'], ['PATCH', '/notifications/preferences']]) {
    const r = await app.request(p, { method: m, headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: 'null' }, { DB: okDb, JWT_SECRET: 's' }, ctx);
    assert.equal(r.status, 400, p);
    assert.equal((await r.json()).ok, false);
  }
});

import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test from 'node:test';

const require = createRequire(import.meta.url);
const { Hono } = require('hono');
const { devicesRouter } = require('../.tmp-test-dist/routes/devices.js');
const { signJwt } = require('../.tmp-test-dist/lib/jwt.js');
const { sendPush } = require('../.tmp-test-dist/domain/push.js');

const JWT_SECRET = 'test-secret';

async function tokenFor(sub) {
  return signJwt({ sub, iat: 0, exp: 9999999999 }, JWT_SECRET);
}

// In-memory device_tokens table modelling the schema's UNIQUE(user_id, token)
// plus every statement devices.ts / sendPush issues against it.
function devicesDb() {
  const rows = []; // {id, user_id, token, platform, app_version, disabled_at}
  const stmt = (sql, args) => {
    const q = sql.replace(/\s+/g, ' ');
    if (q.startsWith('DELETE FROM device_tokens WHERE token = ? AND user_id != ?')) {
      const [token, userId] = args;
      for (let i = rows.length - 1; i >= 0; i--) {
        if (rows[i].token === token && rows[i].user_id !== userId) rows.splice(i, 1);
      }
    } else if (q.startsWith('DELETE FROM device_tokens WHERE user_id = ? AND token = ?')) {
      const [userId, token] = args;
      for (let i = rows.length - 1; i >= 0; i--) {
        if (rows[i].user_id === userId && rows[i].token === token) rows.splice(i, 1);
      }
    } else if (q.startsWith('INSERT INTO device_tokens')) {
      const [id, user_id, token, platform, app_version] = args;
      const existing = rows.find((r) => r.user_id === user_id && r.token === token);
      if (existing) {
        existing.platform = platform;
        existing.app_version = app_version;
        existing.disabled_at = null;
      } else {
        rows.push({ id, user_id, token, platform, app_version, disabled_at: null });
      }
    } else if (q.startsWith('UPDATE device_tokens SET disabled_at')) {
      const row = rows.find((r) => r.id === args[0]);
      if (row) row.disabled_at = 'now';
    }
  };
  return {
    rows,
    prepare(sql) {
      let args = [];
      const bound = {
        bind(...a) { args = a; return bound; },
        async run() { stmt(sql, args); return { meta: { changes: 1 } }; },
        async first() {
          // sendPush's badge lookup: COUNT(*) unread notifications — stub 0.
          if (sql.includes('COUNT(*)')) return { n: 0 };
          return null;
        },
        async all() {
          if (sql.includes('FROM device_tokens')) {
            return {
              results: rows.filter(
                (r) => r.user_id === args[0] && r.disabled_at === null,
              ),
            };
          }
          return { results: [] };
        },
      };
      return bound;
    },
    async batch(stmts) {
      for (const s of stmts) await s.run();
      return [];
    },
  };
}

function makeApp(db) {
  const app = new Hono();
  app.route('/devices', devicesRouter);
  const env = { DB: db, JWT_SECRET };
  return {
    post: async (sub, body) =>
      app.request('/devices', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${await tokenFor(sub)}`,
        },
        body: JSON.stringify(body),
      }, env),
    del: async (sub, token) =>
      app.request(`/devices/${encodeURIComponent(token)}`, {
        method: 'DELETE',
        headers: { Authorization: `Bearer ${await tokenFor(sub)}` },
      }, env),
    unauth: async () =>
      app.request('/devices', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ token: 't', platform: 'ios' }),
      }, env),
  };
}

const activeFor = (db, token) =>
  db.rows.filter((r) => r.token === token && r.disabled_at === null);

test('A registers T — only A owns T', async () => {
  const db = devicesDb();
  const app = makeApp(db);
  const res = await app.post('A', { token: 'T', platform: 'ios' });
  assert.equal(res.status, 200);
  assert.deepEqual(activeFor(db, 'T').map((r) => r.user_id), ['A']);
});

test('A unregisters — A no longer owns active T', async () => {
  const db = devicesDb();
  const app = makeApp(db);
  await app.post('A', { token: 'T', platform: 'ios' });
  const res = await app.del('A', 'T');
  assert.equal(res.status, 200);
  assert.equal(activeFor(db, 'T').length, 0);
});

test('stale A row + B registers same T — ownership transfers to B, one active row', async () => {
  const db = devicesDb();
  const app = makeApp(db);
  await app.post('A', { token: 'T', platform: 'ios' });
  // A signs out WITHOUT unregistering (the stale-row scenario).
  await app.post('B', { token: 'T', platform: 'ios' });
  const owners = activeFor(db, 'T');
  assert.equal(owners.length, 1);
  assert.equal(owners[0].user_id, 'B');
});

test('B registers T again — idempotent, still exactly one row', async () => {
  const db = devicesDb();
  const app = makeApp(db);
  await app.post('B', { token: 'T', platform: 'ios' });
  await app.post('B', { token: 'T', platform: 'ios', appVersion: '1.2.3' });
  assert.equal(activeFor(db, 'T').length, 1);
});

test('token refresh T1→T2 — B owns both tokens it registered', async () => {
  const db = devicesDb();
  const app = makeApp(db);
  await app.post('A', { token: 'T1', platform: 'ios' });
  await app.post('B', { token: 'T1', platform: 'ios' }); // device switched to B
  await app.post('B', { token: 'T2', platform: 'ios' }); // refresh on B
  assert.deepEqual(activeFor(db, 'T1').map((r) => r.user_id), ['B']);
  assert.deepEqual(activeFor(db, 'T2').map((r) => r.user_id), ['B']);
});

test('re-register after disable reactivates the same owner row', async () => {
  const db = devicesDb();
  const app = makeApp(db);
  await app.post('A', { token: 'T', platform: 'ios' });
  db.rows[0].disabled_at = '2025-01-01'; // FCM marked it invalid
  await app.post('A', { token: 'T', platform: 'ios' });
  assert.equal(activeFor(db, 'T').length, 1);
  assert.equal(db.rows.length, 1);
});

test('unauthenticated registration is rejected and writes nothing', async () => {
  const db = devicesDb();
  const app = makeApp(db);
  const res = await app.unauth();
  assert.equal(res.status, 401);
  assert.equal(db.rows.length, 0);
});

// A throwaway RSA key so sendPush's service-account JWT sign succeeds; fetch is
// stubbed so nothing leaves the test process.
async function fakeServiceAccount() {
  const pair = await crypto.subtle.generateKey(
    {
      name: 'RSASSA-PKCS1-v1_5',
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: 'SHA-256',
    },
    true,
    ['sign', 'verify'],
  );
  const der = await crypto.subtle.exportKey('pkcs8', pair.privateKey);
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...new Uint8Array(der)))}\n-----END PRIVATE KEY-----`;
  return JSON.stringify({
    client_email: 'push@test.iam.gserviceaccount.com',
    private_key: pem,
    token_uri: 'https://oauth.example.test/token',
  });
}

test('after ownership moves to B: A notification cannot target T, B notification can', async () => {
  const db = devicesDb();
  const app = makeApp(db);
  await app.post('A', { token: 'T', platform: 'ios' });
  await app.post('B', { token: 'T', platform: 'ios' });

  const fcmCalls = [];
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (url, init) => {
    if (String(url).includes('oauth')) {
      return new Response(JSON.stringify({ access_token: 'stub' }));
    }
    fcmCalls.push(JSON.parse(init.body).message.token);
    return new Response('{}');
  };
  const env = { DB: db, FCM_PROJECT_ID: 'p', FCM_SERVICE_ACCOUNT: await fakeServiceAccount() };
  try {
    // A push to A — T was transferred to B, so A's device list is empty.
    assert.equal(await sendPush(env, 'A', { title: 't', category: 'race_joined' }), 0);
    assert.equal(fcmCalls.length, 0);

    // A push to B — reaches T.
    assert.equal(await sendPush(env, 'B', { title: 't', category: 'race_joined' }), 1);
    assert.deepEqual(fcmCalls, ['T']);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

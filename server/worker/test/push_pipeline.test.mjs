// Push delivery pipeline: every outcome is distinguishable and logged, only a
// dead token is ever disabled, and the diagnostic/test routes can reach exactly
// one user. FCM and the OAuth endpoint are stubbed; nothing leaves the process.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test from 'node:test';

const require = createRequire(import.meta.url);
const app = require('../.tmp-test-dist/index.js').default;
const { sendPushDetailed, tokenIsDead, parseFcmError } = require('../.tmp-test-dist/domain/push.js');

const KEY = 'internal-test-key';

async function fakeServiceAccount(projectId = 'nuvo-test') {
  const pair = await crypto.subtle.generateKey(
    { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
    true,
    ['sign', 'verify'],
  );
  const der = await crypto.subtle.exportKey('pkcs8', pair.privateKey);
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...new Uint8Array(der)))}\n-----END PRIVATE KEY-----`;
  return JSON.stringify({
    client_email: 'push@test.iam.gserviceaccount.com',
    private_key: pem,
    project_id: projectId,
    token_uri: 'https://oauth.example.test/token',
  });
}

// In-memory D1: device_tokens, users, notifications — only what these paths run.
function makeDb({ devices = [], users = [], notifications = [] } = {}) {
  const rows = devices.map((d, i) => ({ id: `d${i}`, disabled_at: null, platform: 'ios', created_at: 'c', last_seen_at: 'l', ...d }));
  return {
    rows,
    prepare(sql) {
      const q = sql.replace(/\s+/g, ' ').trim();
      let a = [];
      const stmt = {
        bind(...x) { a = x; return stmt; },
        async run() {
          if (q.startsWith('UPDATE device_tokens SET disabled_at')) {
            const r = rows.find((x) => x.id === a[0]);
            if (r) r.disabled_at = 'now';
          }
          return { meta: { changes: 1 } };
        },
        async first() {
          if (q.includes('COUNT(*) AS n FROM notifications')) {
            return { n: notifications.filter((n) => n.user_id === a[0] && !n.read_at).length };
          }
          if (q.includes('AS activeUsers')) {
            const active = rows.filter((r) => !r.disabled_at);
            return {
              activeUsers: users.length,
              usersWithDevices: new Set(active.map((r) => r.user_id)).size,
              activeDevices: active.length,
              disabledDevices: rows.length - active.length,
            };
          }
          if (q.startsWith('SELECT id, primary_email FROM users WHERE id = ?')) {
            return users.find((u) => u.id === a[0]) ?? null;
          }
          if (q.startsWith('SELECT id, primary_email FROM users WHERE LOWER(primary_email)')) {
            return users.find((u) => (u.primary_email ?? '').toLowerCase() === a[0]) ?? null;
          }
          return null;
        },
        async all() {
          if (q.includes('FROM device_tokens WHERE user_id = ? AND disabled_at IS NULL')) {
            return { results: rows.filter((r) => r.user_id === a[0] && !r.disabled_at) };
          }
          if (q.includes('FROM device_tokens WHERE user_id = ? ORDER BY')) {
            return {
              results: rows
                .filter((r) => r.user_id === a[0])
                .map((r) => ({ platform: r.platform, app_version: null, created_at: r.created_at, last_seen_at: r.last_seen_at, disabled_at: r.disabled_at, token_suffix: r.token.slice(-6) })),
            };
          }
          if (q.includes('FROM notifications WHERE user_id = ? ORDER BY')) {
            return { results: notifications.filter((n) => n.user_id === a[0]).slice(0, 5) };
          }
          if (q.includes('FROM device_tokens') && q.includes('SUBSTR(token, -6)')) {
            return { results: rows.filter((r) => r.user_id === a[0] && !r.disabled_at).map((r) => ({ platform: r.platform, last_seen_at: r.last_seen_at, token_suffix: r.token.slice(-6) })) };
          }
          return { results: [] };
        },
      };
      return stmt;
    },
  };
}

// Stub fetch: OAuth always ok unless `oauth` says otherwise; FCM answers per token.
function stubFetch({ oauth = () => new Response(JSON.stringify({ access_token: 'stub' })), fcm }) {
  const calls = [];
  const original = globalThis.fetch;
  globalThis.fetch = async (url, init) => {
    if (String(url).includes('oauth.example.test')) return oauth();
    const message = JSON.parse(init.body).message;
    calls.push(message);
    return fcm(message);
  };
  return { calls, restore: () => { globalThis.fetch = original; } };
}

function captureLogs() {
  const lines = [];
  const log = console.log;
  const error = console.error;
  console.log = (...x) => lines.push(x.join(' '));
  console.error = (...x) => lines.push(x.join(' '));
  return { lines, restore: () => { console.log = log; console.error = error; } };
}

const payload = { title: 'T', category: 'race_invite' };
const err = (httpStatus, status, message, errorCode) =>
  new Response(JSON.stringify({ error: { status, message, details: errorCode ? [{ errorCode }] : [] } }), { status: httpStatus });

test('parseFcmError / tokenIsDead: only a dead TOKEN disables a device', () => {
  assert.equal(parseFcmError(JSON.stringify({ error: { status: 'NOT_FOUND', details: [{ errorCode: 'UNREGISTERED' }] } })).code, 'UNREGISTERED');
  assert.equal(tokenIsDead(404, {}), true);
  assert.equal(tokenIsDead(400, { code: 'UNREGISTERED' }), true);
  assert.equal(tokenIsDead(400, { code: 'INVALID_ARGUMENT', message: 'The registration token is not a valid FCM registration token' }), true);
  // a payload problem must NOT kill healthy tokens
  assert.equal(tokenIsDead(400, { code: 'INVALID_ARGUMENT', message: 'Invalid JSON payload received' }), false);
  assert.equal(tokenIsDead(403, { code: 'SENDER_ID_MISMATCH' }), false);
});

test('outcome no_devices: logged, nothing fetched', async () => {
  const logs = captureLogs();
  const f = stubFetch({ fcm: () => new Response('{}') });
  try {
    const r = await sendPushDetailed({ DB: makeDb(), FCM_PROJECT_ID: 'p', FCM_SERVICE_ACCOUNT: await fakeServiceAccount() }, 'u1', payload);
    assert.equal(r.outcome, 'no_devices');
    assert.equal(f.calls.length, 0);
    assert.ok(logs.lines.some((l) => l.includes('outcome=no_devices') && l.includes('user=u1') && l.includes('category=race_invite')));
  } finally { logs.restore(); f.restore(); }
});

test('outcome dormant: devices exist but FCM is not configured', async () => {
  const logs = captureLogs();
  try {
    const r = await sendPushDetailed({ DB: makeDb({ devices: [{ user_id: 'u1', token: 'tok' }] }) }, 'u1', payload);
    assert.equal(r.outcome, 'dormant');
    assert.equal(r.configured, false);
    assert.ok(logs.lines.some((l) => l.includes('outcome=dormant')));
  } finally { logs.restore(); }
});

test('outcome auth_failed: credentials configured but the OAuth exchange fails', async () => {
  const logs = captureLogs();
  const f = stubFetch({ oauth: () => new Response('nope', { status: 400 }), fcm: () => new Response('{}') });
  try {
    const r = await sendPushDetailed({ DB: makeDb({ devices: [{ user_id: 'u1', token: 'tok' }] }), FCM_PROJECT_ID: 'p', FCM_SERVICE_ACCOUNT: await fakeServiceAccount() }, 'u1', payload);
    assert.equal(r.outcome, 'auth_failed');
    assert.match(r.error, /token endpoint 400/);
    assert.equal(f.calls.length, 0);
    assert.ok(logs.lines.some((l) => l.includes('outcome=auth_failed')));
  } finally { logs.restore(); f.restore(); }
});

test('outcome sent: FCM accepts every device; payload carries the destination', async () => {
  const f = stubFetch({ fcm: () => new Response('{}') });
  try {
    const db = makeDb({ devices: [{ user_id: 'u1', token: 'tokA' }, { user_id: 'u1', token: 'tokB', platform: 'android' }, { user_id: 'u2', token: 'other' }] });
    const r = await sendPushDetailed(
      { DB: db, FCM_PROJECT_ID: 'p', FCM_SERVICE_ACCOUNT: await fakeServiceAccount() },
      'u1',
      { ...payload, notificationId: 'n1', dest: { type: 'race', id: 'r9' } },
    );
    assert.equal(r.outcome, 'sent');
    assert.equal(r.accepted, 2);
    assert.deepEqual(f.calls.map((m) => m.token).sort(), ['tokA', 'tokB']); // never u2's device
    assert.equal(f.calls[0].data.destType, 'race');
    assert.equal(f.calls[0].data.destId, 'r9');
    assert.equal(f.calls[0].data.notificationId, 'n1');
  } finally { f.restore(); }
});

test('SENDER_ID_MISMATCH (wrong Firebase project): rejected, logged, token NOT disabled', async () => {
  const logs = captureLogs();
  const f = stubFetch({ fcm: () => err(403, 'PERMISSION_DENIED', 'SenderId mismatch', 'SENDER_ID_MISMATCH') });
  try {
    const db = makeDb({ devices: [{ user_id: 'u1', token: 'tok' }] });
    const r = await sendPushDetailed({ DB: db, FCM_PROJECT_ID: 'p', FCM_SERVICE_ACCOUNT: await fakeServiceAccount() }, 'u1', payload);
    assert.equal(r.outcome, 'rejected');
    assert.equal(r.results[0].code, 'SENDER_ID_MISMATCH');
    assert.equal(db.rows[0].disabled_at, null);
    assert.ok(logs.lines.some((l) => l.includes('outcome=rejected') && l.includes('403/SENDER_ID_MISMATCH')));
  } finally { logs.restore(); f.restore(); }
});

test('UNREGISTERED disables the token; a payload INVALID_ARGUMENT does not', async () => {
  const f = stubFetch({
    fcm: (m) => (m.token === 'dead'
      ? err(404, 'NOT_FOUND', 'Requested entity was not found.', 'UNREGISTERED')
      : err(400, 'INVALID_ARGUMENT', 'Invalid JSON payload received', null)),
  });
  try {
    const db = makeDb({ devices: [{ user_id: 'u1', token: 'dead' }, { user_id: 'u1', token: 'healthy' }] });
    const r = await sendPushDetailed({ DB: db, FCM_PROJECT_ID: 'p', FCM_SERVICE_ACCOUNT: await fakeServiceAccount() }, 'u1', payload);
    assert.equal(r.outcome, 'rejected');
    assert.equal(db.rows.find((x) => x.token === 'dead').disabled_at, 'now');
    assert.equal(db.rows.find((x) => x.token === 'healthy').disabled_at, null);
  } finally { f.restore(); }
});

test('outcome partial: one device accepted, one refused', async () => {
  const f = stubFetch({ fcm: (m) => (m.token === 'ok' ? new Response('{}') : err(404, 'NOT_FOUND', 'gone', 'UNREGISTERED')) });
  try {
    const db = makeDb({ devices: [{ user_id: 'u1', token: 'ok' }, { user_id: 'u1', token: 'gone' }] });
    const r = await sendPushDetailed({ DB: db, FCM_PROJECT_ID: 'p', FCM_SERVICE_ACCOUNT: await fakeServiceAccount() }, 'u1', payload);
    assert.equal(r.outcome, 'partial');
    assert.equal(r.accepted, 1);
  } finally { f.restore(); }
});

// ── Diagnostic + test routes ─────────────────────────────────────────────────

const call = (env, method, path, body, key = KEY) =>
  app.request(`/internal${path}`, {
    method,
    headers: { ...(key ? { 'X-Internal-Key': key } : {}), 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  }, env);

async function routeEnv({ fcm = true } = {}) {
  const db = makeDb({
    users: [{ id: 'A', primary_email: 'a@test.dev' }, { id: 'B', primary_email: 'b@test.dev' }],
    devices: [
      { user_id: 'A', token: 'tokenOfAliceDevice' },
      { user_id: 'B', token: 'tokenOfBobsDevice' },
    ],
    notifications: [{ user_id: 'A', category: 'race_invite', title: 'x', created_at: 't', read_at: null }],
  });
  return {
    db,
    env: {
      DB: db,
      JWT_SECRET: 's',
      INTERNAL_API_KEY: KEY,
      ...(fcm ? { FCM_PROJECT_ID: 'nuvo-test', FCM_SERVICE_ACCOUNT: await fakeServiceAccount('nuvo-test') } : {}),
    },
  };
}

test('GET /internal/push/status: needs the key; proves credentials; never returns tokens', async () => {
  const { env } = await routeEnv();
  const f = stubFetch({ fcm: () => new Response('{}') });
  try {
    assert.equal((await call(env, 'GET', '/push/status', null, null)).status, 403);
    const res = await call(env, 'GET', '/push/status?email=a@test.dev');
    assert.equal(res.status, 200);
    const text = await res.text();
    const json = JSON.parse(text);
    assert.equal(json.credentials.configured, true);
    assert.equal(json.credentials.tokenExchange, 'ok');
    assert.equal(json.credentials.projectsMatch, true);
    assert.equal(json.totals.usersWithDevices, 2);
    assert.equal(json.user.id, 'A');
    assert.equal(json.user.activeDevices, 1);
    assert.equal(json.user.devices[0].token_suffix, 'Device'.slice(-6));
    assert.ok(!text.includes('tokenOfAliceDevice'), 'full token must never be returned');
  } finally { f.restore(); }
});

test('status reports a project mismatch between the service account and FCM_PROJECT_ID', async () => {
  const { env } = await routeEnv();
  env.FCM_PROJECT_ID = 'some-other-project';
  const f = stubFetch({ fcm: () => new Response('{}') });
  try {
    const json = await (await call(env, 'GET', '/push/status')).json();
    assert.equal(json.credentials.projectsMatch, false);
  } finally { f.restore(); }
});

test('POST /internal/push/test: exactly one recipient, dry run by default, confirm required', async () => {
  const { env } = await routeEnv();
  const f = stubFetch({ fcm: () => new Response('{}') });
  try {
    assert.equal((await call(env, 'POST', '/push/test', {}, null)).status, 403);
    assert.equal((await call(env, 'POST', '/push/test', {})).status, 400); // no recipient
    assert.equal((await call(env, 'POST', '/push/test', { userId: 'A', email: 'b@test.dev' })).status, 400); // two
    assert.equal((await call(env, 'POST', '/push/test', { userId: ['A', 'B'] })).status, 400); // list
    assert.equal((await call(env, 'POST', '/push/test', { userId: 'nobody' })).status, 404);
    assert.equal((await call(env, 'POST', '/push/test', { userId: 'A', dest: { type: 'bogus' } })).status, 400);

    // dry run: lists devices, sends nothing
    const dry = await (await call(env, 'POST', '/push/test', { userId: 'A' })).json();
    assert.equal(dry.dryRun, true);
    assert.equal(dry.devices.length, 1);
    assert.equal(f.calls.length, 0);

    // real send without confirmation is refused
    const unconfirmed = await call(env, 'POST', '/push/test', { userId: 'A', dryRun: false });
    assert.equal(unconfirmed.status, 400);
    assert.equal(f.calls.length, 0);

    // wrong confirmation is refused too
    assert.equal((await call(env, 'POST', '/push/test', { userId: 'A', dryRun: false, confirmUserId: 'B' })).status, 400);
    assert.equal(f.calls.length, 0);

    // confirmed: ONE FCM request, to A's device only — never B's
    const sent = await (await call(env, 'POST', '/push/test', { email: 'a@test.dev', dryRun: false, confirmUserId: 'A', dest: { type: 'notifications' } })).json();
    assert.equal(sent.result.outcome, 'sent');
    assert.equal(f.calls.length, 1);
    assert.equal(f.calls[0].token, 'tokenOfAliceDevice');
    assert.equal(f.calls[0].data.destType, 'notifications');
    assert.equal(f.calls[0].data.category, 'test');
  } finally { f.restore(); }
});

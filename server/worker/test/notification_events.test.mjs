// Event → notification → FCM request, end to end against the captured PROD schema
// (real SQLite, real routes). Only FCM and its OAuth endpoint are stubbed. Each
// test follows ONE event and asserts who got an inbox row, who got a push
// request, and — just as important — who did not.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';

const require = createRequire(import.meta.url);
const app = require('../.tmp-test-dist/index.js').default;
const { signJwt } = require('../.tmp-test-dist/lib/jwt.js');

const JWT_SECRET = 'test-secret';
const { checkFcmCredentials } = require('../.tmp-test-dist/domain/push.js');
void checkFcmCredentials;
const root = new URL('..', import.meta.url);
const SCHEMA = [
  readFileSync(new URL('test/fixtures/prod_schema_2026-09-28.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0042_achievements.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0043_proof_votes.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0044_custom_verifier_seed.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0046_squads.sql', root), 'utf8'),
];

// ── D1 adapter over node:sqlite ──────────────────────────────────────────────
function d1(sqlite) {
  const norm = (args) =>
    args.map((v) => (v === undefined ? null : typeof v === 'boolean' ? (v ? 1 : 0) : v));
  const stmt = (sql, args = []) => ({
    bind: (...a) => stmt(sql, a),
    async first(col) {
      const row = sqlite.prepare(sql).get(...norm(args));
      if (!row) return null;
      const o = { ...row };
      return col ? o[col] : o;
    },
    async all() {
      return { success: true, meta: {}, results: sqlite.prepare(sql).all(...norm(args)).map((r) => ({ ...r })) };
    },
    async run() {
      return this.runSync();
    },
    runSync() {
      if (/^\s*(SELECT|WITH)\b/i.test(sql)) {
        return { success: true, meta: {}, results: sqlite.prepare(sql).all(...norm(args)).map((r) => ({ ...r })) };
      }
      const info = sqlite.prepare(sql).run(...norm(args));
      return { success: true, meta: { changes: Number(info.changes), last_row_id: Number(info.lastInsertRowid) } };
    },
  });
  return {
    prepare: (sql) => stmt(sql),
    // Synchronous inside the transaction — like D1, a batch is one atomic
    // unit that never interleaves with other in-flight work.
    async batch(stmts) {
      sqlite.exec('BEGIN');
      try {
        const out = stmts.map((s) => s.runSync());
        sqlite.exec('COMMIT');
        return out;
      } catch (err) {
        sqlite.exec('ROLLBACK');
        throw err;
      }
    },
  };
}


function world() {
  const sqlite = new DatabaseSync(':memory:');
  for (const sql of SCHEMA) sqlite.exec(sql);
  sqlite.exec('PRAGMA foreign_keys = ON');
  const db = d1(sqlite);
  const pending = [];
  const env = { DB: db, JWT_SECRET };
  const ctx = { waitUntil: (p) => pending.push(p), passThroughOnException() {} };
  const q = (sql, ...a) => sqlite.prepare(sql).all(...a).map((r) => ({ ...r }));
  const one = (sql, ...a) => q(sql, ...a)[0];
  const exec = (sql, ...a) => sqlite.prepare(sql).run(...a);
  const req = async (sub, method, path, body) => {
    const headers = { 'Content-Type': 'application/json' };
    if (sub) headers.Authorization = `Bearer ${await signJwt({ sub, iat: 0, exp: 9999999999 }, JWT_SECRET)}`;
    const res = await app.request(path, { method, headers, body: body == null ? undefined : JSON.stringify(body) }, env, ctx);
    const text = await res.text();
    let json = null;
    try { json = JSON.parse(text); } catch { /* non-JSON */ }
    return { status: res.status, json, text };
  };
  const user = (id) => {
    exec("INSERT INTO users (id, primary_email, status, terms_accepted_at, created_at, updated_at) VALUES (?, ?, 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)", id, `${id}@example.com`);
    exec('INSERT INTO profiles (user_id, full_name) VALUES (?, ?)', id, id);
    exec('INSERT INTO people (id, person_key, user_id, display_name) VALUES (?, ?, ?, ?)', `p-${id}`, `user-${id}`, id, id);
  };
  let joinN = 0;
  const member = (raceId, userId, role = 'racer', status = 'active', value = 0) => {
    exec(
      "INSERT INTO race_members (id, race_id, person_id, user_id, role, status, joined_at) VALUES (?, ?, ?, ?, ?, ?, datetime('now', ?))",
      `rm-${raceId}-${userId}`, raceId, `p-${userId}`, userId, role, status, `-${1000 - ++joinN} seconds`,
    );
    exec('INSERT INTO race_progress (id, race_id, user_id, progress_value, progress_percent) VALUES (?, ?, ?, ?, 0)', `rp-${raceId}-${userId}`, raceId, userId, value);
  };
  const race = (id, creator, over = {}) => {
    const r = {
      format: 'most_in_window', race_type: 'most_in_window', status: 'active', visibility: 'public_demo',
      target_value: null, start_at: null, end_at: null, ...over,
    };
    exec(
      `INSERT INTO races (id, creator_id, title, race_type, format, verification_type, status, visibility, public_join_enabled,
         scoring_rule, score_direction, target_value, target_unit, metric, verifier_type, proof_review_mode, start_at, end_at,
         created_at, updated_at)
       VALUES (?, ?, 'Race', ?, ?, 'manual', ?, ?, 1, 'cumulative_sum', 'higher', ?, 'pages', 'reps', 'manual_log', 'auto_accept', ?, ?,
         CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)`,
      id, creator, r.race_type, r.format, r.status, r.visibility, r.target_value, r.start_at, r.end_at,
    );
    member(id, creator, 'creator');
    return id;
  };
  const status = (raceId, userId) => one('SELECT status FROM race_members WHERE race_id = ? AND user_id = ?', raceId, userId)?.status;
  const rank = (raceId, userId) => one('SELECT rank_cache FROM race_progress WHERE race_id = ? AND user_id = ?', raceId, userId)?.rank_cache;
  const mint = async (creator, raceId, extra = {}) => {
    const res = await req(creator, 'POST', '/invites', { kind: 'race_join', targetId: raceId, ...extra });
    assert.equal(res.status, 200, res.text);
    return res.json;
  };
  const flush = async () => { await Promise.all(pending.splice(0)); };
  return { sqlite, env, req, q, one, exec, user, race, member, status, rank, mint, flush };
}


async function fakeServiceAccount() {
  const pair = await crypto.subtle.generateKey(
    { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
    true, ['sign', 'verify'],
  );
  const der = await crypto.subtle.exportKey('pkcs8', pair.privateKey);
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...new Uint8Array(der)))}\n-----END PRIVATE KEY-----`;
  return JSON.stringify({ client_email: 'push@test.iam.gserviceaccount.com', private_key: pem, project_id: 'nuvo-test', token_uri: 'https://oauth.example.test/token' });
}

// A world with FCM configured and a recording stub for FCM.
async function pushWorld({ configured = true } = {}) {
  const w = world();
  if (configured) {
    w.env.FCM_PROJECT_ID = 'nuvo-test';
    w.env.FCM_SERVICE_ACCOUNT = await fakeServiceAccount();
  }
  const fcm = [];
  const logs = [];
  const original = { fetch: globalThis.fetch, log: console.log, error: console.error };
  globalThis.fetch = async (url, init) => {
    if (String(url).includes('oauth.example.test')) return new Response(JSON.stringify({ access_token: 'stub' }));
    fcm.push(JSON.parse(init.body).message);
    return new Response('{}');
  };
  console.log = (...x) => logs.push(x.join(' '));
  console.error = (...x) => logs.push(x.join(' '));
  w.restore = () => Object.assign(globalThis, { fetch: original.fetch }) && Object.assign(console, { log: original.log, error: original.error });
  w.device = (userId, token, platform = 'ios') =>
    w.exec("INSERT INTO device_tokens (id, user_id, token, platform, created_at, last_seen_at) VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)", `dev-${token}`, userId, token, platform);
  w.inbox = (userId, category) => w.q('SELECT * FROM notifications WHERE user_id = ? AND category = ?', userId, category);
  return Object.assign(w, { fcm, logs });
}

test('race invite: creator adds B → B gets the inbox row AND a push to B\'s device only', async () => {
  const w = await pushWorld();
  try {
    w.user('A'); w.user('B'); w.user('C');
    w.race('r1', 'A');
    w.device('A', 'tok-A'); w.device('B', 'tok-B'); w.device('C', 'tok-C');

    const res = await w.req('A', 'POST', '/races/r1/participants', { userId: 'B' });
    assert.equal(res.status, 200, res.text);
    await w.flush();

    const rows = w.inbox('B', 'race_invite');
    assert.equal(rows.length, 1);
    assert.equal(rows[0].dest_type, 'race');
    assert.equal(rows[0].dest_id, 'r1');
    assert.match(rows[0].title, /added you to/);

    assert.equal(w.fcm.length, 1, 'exactly one push request');
    assert.equal(w.fcm[0].token, 'tok-B');
    assert.equal(w.fcm[0].data.category, 'race_invite');
    assert.equal(w.fcm[0].data.destType, 'race');
    assert.equal(w.fcm[0].data.destId, 'r1');
    assert.equal(w.fcm[0].data.notificationId, rows[0].id, 'tap can be matched to the inbox row');
    assert.ok(w.logs.some((l) => l.includes('outcome=sent') && l.includes('category=race_invite') && l.includes('user=B')));

    // The creator and bystander got nothing.
    assert.equal(w.inbox('A', 'race_invite').length, 0);
    assert.equal(w.inbox('C', 'race_invite').length, 0);
    assert.ok(!w.fcm.some((m) => m.token === 'tok-A' || m.token === 'tok-C'));
  } finally { w.restore(); }
});

test('race invite, recipient has NO device token: inbox row yes, push no — and the log says why', async () => {
  const w = await pushWorld();
  try {
    w.user('A'); w.user('B');
    w.race('r1', 'A');
    const res = await w.req('A', 'POST', '/races/r1/participants', { userId: 'B' });
    assert.equal(res.status, 200, res.text);
    await w.flush();

    assert.equal(w.inbox('B', 'race_invite').length, 1);
    assert.equal(w.fcm.length, 0);
    assert.ok(w.logs.some((l) => l.includes('outcome=no_devices') && l.includes('user=B')), w.logs.join('\n'));
  } finally { w.restore(); }
});

test('race invite, push preference off: inbox row yes, push never attempted', async () => {
  const w = await pushWorld();
  try {
    w.user('A'); w.user('B');
    w.race('r1', 'A');
    w.device('B', 'tok-B');
    w.exec("INSERT INTO notification_preferences (user_id, category, in_app, push) VALUES ('B', 'race_invite', 1, 0)");
    await w.req('A', 'POST', '/races/r1/participants', { userId: 'B' });
    await w.flush();
    assert.equal(w.inbox('B', 'race_invite').length, 1);
    assert.equal(w.fcm.length, 0);
  } finally { w.restore(); }
});

test('FCM not configured: the invite still lands in the inbox and the log says dormant', async () => {
  const w = await pushWorld({ configured: false });
  try {
    w.user('A'); w.user('B');
    w.race('r1', 'A');
    w.device('B', 'tok-B');
    await w.req('A', 'POST', '/races/r1/participants', { userId: 'B' });
    await w.flush();
    assert.equal(w.inbox('B', 'race_invite').length, 1);
    assert.equal(w.fcm.length, 0);
    assert.ok(w.logs.some((l) => l.includes('outcome=dormant') && l.includes('user=B')));
  } finally { w.restore(); }
});

test('someone joins your race: the CREATOR is notified (not the joiner)', async () => {
  const w = await pushWorld();
  try {
    w.user('A'); w.user('B');
    w.race('r1', 'A');
    w.device('A', 'tok-A'); w.device('B', 'tok-B');
    const res = await w.req('B', 'POST', '/races/r1/join');
    assert.equal(res.status, 200, res.text);
    await w.flush();
    assert.equal(w.inbox('A', 'race_joined').length, 1);
    assert.equal(w.fcm.length, 1);
    assert.equal(w.fcm[0].token, 'tok-A');
    assert.equal(w.fcm[0].data.category, 'race_joined');
    assert.equal(w.inbox('B', 'race_joined').length, 0);
  } finally { w.restore(); }
});

test('friend request: the person asked is pushed, the requester is not', async () => {
  const w = await pushWorld();
  try {
    w.user('A'); w.user('B');
    w.device('A', 'tok-A'); w.device('B', 'tok-B');
    const res = await w.req('A', 'POST', '/crew/add', { userId: 'B' });
    assert.equal(res.status, 200, res.text + '\n' + w.logs.join('\n'));
    await w.flush();
    assert.equal(w.inbox('B', 'crew_request').length, 1);
    assert.deepEqual(w.fcm.map((m) => m.token), ['tok-B']);
    assert.equal(w.fcm[0].data.category, 'crew_request');
  } finally { w.restore(); }
});

test('friend request accepted: inbox only by design (no push)', async () => {
  const w = await pushWorld();
  try {
    w.user('A'); w.user('B');
    w.device('A', 'tok-A'); w.device('B', 'tok-B');
    await w.req('A', 'POST', '/crew/add', { userId: 'B' });
    await w.flush();
    w.fcm.length = 0;
    const res = await w.req('B', 'POST', '/crew/requests/A/accept');
    assert.equal(res.status, 200, res.text);
    await w.flush();
    assert.equal(w.inbox('A', 'crew_request_accepted').length, 1);
    assert.equal(w.fcm.length, 0);
  } finally { w.restore(); }
});

test('a blocked user can never be invited, so no row and no push is created', async () => {
  const w = await pushWorld();
  try {
    w.user('A'); w.user('B');
    w.race('r1', 'A');
    w.device('B', 'tok-B');
    w.exec("INSERT INTO blocked_users (id, user_id, blocked_user_id, created_at) VALUES ('bl1', 'B', 'A', CURRENT_TIMESTAMP)");
    const res = await w.req('A', 'POST', '/races/r1/participants', { userId: 'B' });
    assert.equal(res.status, 403);
    await w.flush();
    assert.equal(w.inbox('B', 'race_invite').length, 0);
    assert.equal(w.fcm.length, 0);
  } finally { w.restore(); }
});

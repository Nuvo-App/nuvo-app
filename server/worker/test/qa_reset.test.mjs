import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test from 'node:test';

const require = createRequire(import.meta.url);
const app = require('../.tmp-test-dist/index.js').default;

const KEY = 'internal-test-key';

// Permissive D1 fake: every statement runs, selects return the caller's
// configured user row only for the qa/reset user lookup, empty sets for all
// relational scans. hardDeleteAccount executes ~25 statements — the fake just
// records them so the test can assert canonical deletion actually ran.
function fakeDb({ user = null } = {}) {
  const calls = [];
  const bound = (sql, args) => ({
    async first() {
      if (sql.includes("FROM users WHERE primary_email = ?")) return user;
      return null;
    },
    async all() {
      return { results: [] };
    },
    async run() {
      calls.push(sql);
      return { success: true, meta: { changes: 1 } };
    },
  });
  return {
    calls,
    prepare(sql) {
      return {
        bind: (...args) => bound(sql, args),
        first: () => bound(sql).first(),
        all: () => bound(sql).all(),
        run: () => bound(sql).run(),
      };
    },
    batch: async (stmts) => Promise.all(stmts.map(() => ({ success: true }))),
  };
}

const fakeR2 = { async delete() {}, async get() { return null; }, async put() {} };

function env(db) {
  return {
    DB: db,
    PROFILE_PHOTOS: fakeR2,
    INTERNAL_API_KEY: KEY,
    JWT_SECRET: 'test-secret',
    MOTION_DATA_MASTER_KEY: 'master-key',
  };
}

function resetReq(email, key = KEY) {
  return app.request('/internal/qa/reset', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-Internal-Key': key },
    body: JSON.stringify({ email }),
  }, env(fakeDb()));
}

test('qa/reset rejects without the internal key', async () => {
  const res = await app.request('/internal/qa/reset', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: 'testing@getnuvo.net' }),
  }, env(fakeDb()));
  assert.equal(res.status, 403);
});

test('qa/reset rejects any identity that is not the QA account', async () => {
  for (const email of ['real@example.com', 'team@getnuvo.net', 'testing@getnuvo.net.evil.com', '']) {
    const res = await resetReq(email);
    assert.equal(res.status, 403, email);
    const body = await res.json();
    assert.equal(body.ok, false);
  }
});

test('qa/reset with no existing account is a safe no-op', async () => {
  const res = await resetReq('testing@getnuvo.net');
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.ok, true);
  assert.equal(body.reset, false);
});

test('qa/reset deletes the QA account via the canonical path', async () => {
  const db = fakeDb({ user: { id: 'u-qa-1' } });
  const res = await app.request('/internal/qa/reset', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-Internal-Key': KEY },
    body: JSON.stringify({ email: 'Testing@GetNuvo.net' }),
  }, env(db));
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.reset, true);
  assert.equal(body.previousUserId, 'u-qa-1');
  // Canonical hard-delete markers — profile, sessions, progression, and the
  // user tombstone must all have run; nothing per-table was skipped.
  for (const needle of [
    'DELETE FROM profiles WHERE user_id = ?',
    'DELETE FROM sessions WHERE user_id = ?',
    'DELETE FROM user_progression WHERE user_id = ?',
    'DELETE FROM crew_connections WHERE user_id = ? OR crew_user_id = ?',
    'DELETE FROM notifications WHERE user_id = ?',
    'DELETE FROM auth_identities WHERE user_id = ? AND provider_refresh_token IS NULL',
    "SET status = 'deleted'",
  ]) {
    assert.ok(db.calls.some((sql) => sql.includes(needle)), needle);
  }
});

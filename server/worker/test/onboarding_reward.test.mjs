// Onboarding v2 reward (migration 0052): POST /onboarding/complete grants
// 100 XP exactly once via an idempotent xp_events ledger row, lands a fresh
// account on Level 2, grants the Day One badge, and keeps the old response
// shape (additive only).
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';

const require = createRequire(import.meta.url);
const app = require('../.tmp-test-dist/index.js').default;
const { signJwt } = require('../.tmp-test-dist/lib/jwt.js');
const { xpForLevel, levelForXp } = require('../.tmp-test-dist/domain/progression.js');

const JWT_SECRET = 'test-secret';
const root = new URL('..', import.meta.url);
const SCHEMA = [
  readFileSync(new URL('test/fixtures/prod_schema_2026-09-28.sql', root), 'utf8'),
  ...['0042_achievements', '0043_proof_votes', '0044_custom_verifier_seed', '0045_teach_sessions',
    '0046_squads', '0047_reconcile_prod', '0048_v13_profile', '0050_race_rules_version',
    '0052_onboarding_v2_reward'].map((n) => readFileSync(new URL(`migrations/${n}.sql`, root), 'utf8')),
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

function fakeR2() {
  const objects = new Map();
  return {
    objects,
    async put(key, body, opts) { objects.set(key, { body, opts }); },
    async get(key) {
      const o = objects.get(key);
      return o ? { body: 'bytes', customMetadata: o.opts?.customMetadata ?? {}, writeHttpMetadata() {} } : null;
    },
    async delete(key) { objects.delete(key); },
  };
}

function world() {
  const sqlite = new DatabaseSync(':memory:');
  for (const sql of SCHEMA) sqlite.exec(sql);
  sqlite.exec('PRAGMA foreign_keys = ON');
  const env = {
    DB: d1(sqlite),
    JWT_SECRET,
    PROFILE_PHOTOS: fakeR2(),
    APPLE_BUNDLE_ID: 'net.getnuvo.app',
    REVIEWER_PASSWORD_HASH: createHash('sha256').update('x').digest('hex'),
  };
  const ctx = { waitUntil() {}, passThroughOnException() {} };
  const q = (sql, ...a) => sqlite.prepare(sql).all(...a).map((r) => ({ ...r }));
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
  return { q, exec, req, user };
}

test('curve: 100 XP is Level 2 and not Level 3', () => {
  assert.ok(xpForLevel(2) <= 100 && 100 < xpForLevel(3));
  assert.equal(levelForXp(100).level, 2);
});

test('onboarding/complete: grants 100 XP once, Level 2, Day One badge, old shape kept', async () => {
  const w = world();
  w.user('u1');
  const r1 = await w.req('u1', 'POST', '/onboarding/complete', {});
  assert.equal(r1.status, 200, r1.text);
  assert.equal(r1.json.ok, true);
  assert.equal(r1.json.onboardingComplete, true);
  assert.equal(r1.json.reward.xpGranted, 100);
  assert.equal(r1.json.reward.totalXp, 100);
  assert.equal(r1.json.reward.level, 2);
  assert.equal(r1.json.reward.previousLevel, 1);
  assert.equal(r1.json.reward.leveledUp, true);
  assert.equal(r1.json.reward.badge.name, 'Day One');
  assert.ok(r1.json.reward.streakDays >= 1);

  const r2 = await w.req('u1', 'POST', '/onboarding/complete', {});
  assert.equal(r2.status, 200, r2.text);
  assert.equal(r2.json.reward.xpGranted, 0);
  assert.equal(r2.json.reward.totalXp, 100);
  assert.equal(r2.json.reward.level, 2);
  assert.equal(r2.json.reward.leveledUp, false);

  const rows = w.q("SELECT * FROM xp_events WHERE user_id = 'u1' AND source_type = 'onboarding_v2'");
  assert.equal(rows.length, 1);
  assert.equal(rows[0].xp_amount, 100);
  assert.equal(w.q("SELECT * FROM user_unlocks WHERE user_id = 'u1' AND unlock_id = 'bdg-day-one'").length, 1);
});

test('onboarding/complete: grant survives later reconcile and is per-user', async () => {
  const w = world();
  w.user('a');
  w.user('b');
  await w.req('a', 'POST', '/onboarding/complete', {});
  const p = await w.req('a', 'GET', '/progression');
  assert.equal(p.status, 200, p.text);
  assert.equal(p.json.progression?.totalXp ?? p.json.totalXp, 100);
  assert.equal(w.q("SELECT * FROM xp_events WHERE user_id = 'b'").length, 0);
});

test('migration 0052 is additive: Day One is a badge, not one of the 43 achievements', () => {
  const sqlite = new DatabaseSync(':memory:');
  for (const sql of SCHEMA) sqlite.exec(sql);
  const n = sqlite.prepare("SELECT COUNT(*) AS n FROM unlock_definitions WHERE unlock_type = 'achievement' AND active = 1").get().n;
  assert.equal(n, 43);
  assert.equal(sqlite.prepare("SELECT unlock_type FROM unlock_definitions WHERE id = 'bdg-day-one'").get().unlock_type, 'badge');
});

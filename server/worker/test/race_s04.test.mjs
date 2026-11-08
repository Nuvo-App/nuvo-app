// S4 strict rules for new races (rules_version >= 1):
//   - camera-contract races are camera-only at proof time (gap 8);
//   - a v1 create can never downgrade the race's proof contract — a preset /
//     registry / custom race stays camera proof, a custom goal stays photo
//     proof, whatever the client sent (gaps 8 + 13 + N19);
//   - custom goals only race First to / Most total (gap 13).
// v0 rows and old builds keep every legacy behaviour — covered here and in
// race_compat.test.mjs.

import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';

const require = createRequire(import.meta.url);
const app = require('../.tmp-test-dist/index.js').default;
const { signJwt } = require('../.tmp-test-dist/lib/jwt.js');

const JWT_SECRET = 'test-secret';
const REVIEWER_PASSWORD = 'test-review-pass';
const root = new URL('..', import.meta.url);
const SCHEMA = [
  readFileSync(new URL('test/fixtures/prod_schema_2026-09-28.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0042_achievements.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0043_proof_votes.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0044_custom_verifier_seed.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0046_squads.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0047_reconcile_prod.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0050_race_rules_version.sql', root), 'utf8'),
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
  const db = d1(sqlite);
  const r2 = fakeR2();
  const pending = [];
  const env = {
    DB: db,
    JWT_SECRET,
    PROFILE_PHOTOS: r2,
    APPLE_BUNDLE_ID: 'net.getnuvo.app',
    REVIEWER_PASSWORD_HASH: createHash('sha256').update(REVIEWER_PASSWORD).digest('hex'),
  };
  const ctx = { waitUntil: (p) => pending.push(p), passThroughOnException() {} };
  const q = (sql, ...a) => sqlite.prepare(sql).all(...a).map((r) => ({ ...r }));
  const one = (sql, ...a) => q(sql, ...a)[0];
  const exec = (sql, ...a) => sqlite.prepare(sql).run(...a);

  const req = async (sub, method, path, body) => {
    const headers = { 'Content-Type': 'application/json' };
    if (sub) headers.Authorization = `Bearer ${await signJwt({ sub, iat: 0, exp: 9999999999 }, JWT_SECRET)}`;
    const res = await app.request(path, {
      method,
      headers,
      body: body == null ? undefined : JSON.stringify(body),
    }, env, ctx);
    const text = await res.text();
    let json = null;
    try { json = JSON.parse(text); } catch { /* non-JSON */ }
    return { status: res.status, json, text };
  };

  const user = (id, { email = `${id}@example.com`, name = id } = {}) => {
    exec("INSERT INTO users (id, primary_email, status, terms_accepted_at, created_at, updated_at) VALUES (?, ?, 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)", id, email);
    exec('INSERT INTO profiles (user_id, full_name) VALUES (?, ?)', id, name);
    exec('INSERT INTO people (id, person_key, user_id, display_name) VALUES (?, ?, ?, ?)', `p-${id}`, `user-${id}`, id, name);
  };
  const member = (raceId, userId, role = 'racer', status = 'active') => {
    exec(
      "INSERT INTO race_members (id, race_id, person_id, user_id, role, status, joined_at) VALUES (?, ?, ?, ?, ?, ?, datetime('now'))",
      `rm-${raceId}-${userId}`, raceId, `p-${userId}`, userId, role, status,
    );
    exec('INSERT INTO race_progress (id, race_id, user_id, progress_value, progress_percent) VALUES (?, ?, ?, 0, 0)', `rp-${raceId}-${userId}`, raceId, userId);
  };
  let mediaN = 0;
  const photo = (raceId, owner) => {
    const key = `proof-evidence/${raceId}/${owner}/${++mediaN}.jpg`;
    exec("INSERT INTO media_objects (id, owner_user_id, bucket, object_key, media_type, purpose, status) VALUES (?, ?, 'nuvor2', ?, 'image', 'proof_evidence', 'active')", `mo-${mediaN}`, owner, key);
    r2.objects.set(key, { body: 'jpg' });
    return key;
  };
  const progress = (raceId, userId) =>
    one('SELECT progress_value FROM race_progress WHERE race_id = ? AND user_id = ?', raceId, userId)?.progress_value;
  const flush = async () => { await Promise.all(pending.splice(0)); };

  return { sqlite, db, r2, env, req, q, one, exec, user, member, photo, progress, flush };
}

const iso = (ms) => new Date(Date.now() + ms).toISOString();
const HOUR = 3600_000;

// A preset (static-catalog) camera race body — the shape the app sends for a
// movement the camera verifies.
const presetBody = (over = {}) => ({
  title: 'Pushup Sprint',
  goalType: 'first_to_goal',
  targetValue: 50,
  activityId: 'push_ups',
  aiActivityType: 'push_ups',
  metric: 'reps',
  targetUnit: 'reps',
  proofRequirement: 'ai_check',
  proofMode: 'ai_check',
  verificationMethod: 'ai',
  ...over,
});

// A custom-goal (honor-logged) body — the shape _manualCreatePayload sends.
const manualBody = (over = {}) => ({
  title: 'Read 100 pages',
  goalType: 'first_to_goal',
  targetValue: 100,
  unit: 'pages',
  targetUnit: 'pages',
  metric: 'reps',
  format: 'first_to_goal',
  proofRequirement: 'photo_video',
  proofMode: 'photo_video',
  ...over,
});

// ── gap 8: v1 camera races are camera-only at proof time ─────────────────────

test('test_gap8_camera_only_rejects_manual_proof', async () => {
  const w = world();
  w.user('A');
  w.user('B');

  // v1 preset camera race: a manual + photo proof can never score.
  const v1 = await w.req('A', 'POST', '/races', presetBody({ rulesVersion: 1 }));
  assert.equal(v1.status, 201, v1.text);
  const v1Id = v1.json.race.id;
  w.member(v1Id, 'B');

  const rejected = await w.req('B', 'POST', `/races/${v1Id}/proof`, {
    proofType: 'manual',
    value: 10,
    mediaObjectKey: w.photo(v1Id, 'B'),
  });
  assert.equal(rejected.status, 400, rejected.text);
  assert.equal(rejected.json.error, 'This race uses camera proof.');
  assert.equal(
    w.q('SELECT id FROM move_logs WHERE race_id = ?', v1Id).length,
    0,
    'rejection writes no move row — the photo stays usable',
  );
  assert.equal(w.progress(v1Id, 'B') ?? 0, 0);

  // The gate fires before the media check too — a bare self-report gets the
  // same honest error, not "photo required".
  const bare = await w.req('B', 'POST', `/races/${v1Id}/proof`, {
    proofType: 'manual',
    value: 10,
  });
  assert.equal(bare.status, 400, bare.text);
  assert.equal(bare.json.error, 'This race uses camera proof.');

  // v0 preset camera race: identical submission still scores — the manual +
  // photo path old builds rely on is untouched.
  const v0 = await w.req('A', 'POST', '/races', presetBody());
  assert.equal(v0.status, 201, v0.text);
  const v0Id = v0.json.race.id;
  w.member(v0Id, 'B');

  const accepted = await w.req('B', 'POST', `/races/${v0Id}/proof`, {
    proofType: 'manual',
    value: 10,
    mediaObjectKey: w.photo(v0Id, 'B'),
  });
  assert.equal(accepted.status, 200, accepted.text);
  assert.equal(w.progress(v0Id, 'B'), 10, 'v0 manual proof still scores');
});

test('test_gap8_rules_version_echoed_in_race_response', async () => {
  const w = world();
  w.user('A');

  const v1 = await w.req('A', 'POST', '/races', presetBody({ rulesVersion: 1 }));
  assert.equal(v1.status, 201, v1.text);
  assert.equal(v1.json.race.rulesVersion, 1, 'create response echoes rulesVersion');
  const got1 = await w.req('A', 'GET', `/races/${v1.json.race.id}`);
  assert.equal(got1.status, 200, got1.text);
  assert.equal(got1.json.race.rulesVersion, 1, 'GET echoes rulesVersion');

  const v0 = await w.req('A', 'POST', '/races', presetBody());
  assert.equal(v0.status, 201, v0.text);
  assert.equal(v0.json.race.rulesVersion, 0);
  const got0 = await w.req('A', 'GET', `/races/${v0.json.race.id}`);
  assert.equal(got0.status, 200, got0.text);
  assert.equal(got0.json.race.rulesVersion, 0, 'v0 race echoes rulesVersion: 0');
});

test('test_gap8_v1_preset_race_is_camera_contract', async () => {
  const w = world();
  w.user('A');
  w.user('B');

  // A v1 client sending a photo/manual proofRequirement on a camera race is
  // ignored — the stored contract is still camera proof.
  const created = await w.req('A', 'POST', '/races', presetBody({
    rulesVersion: 1,
    proofRequirement: 'photo_video',
    proofMode: 'photo_video',
  }));
  assert.equal(created.status, 201, created.text);
  const raceId = created.json.race.id;
  assert.equal(
    w.one('SELECT verification_type FROM races WHERE id = ?', raceId).verification_type,
    'movecheck',
    'photo_video cannot downgrade a v1 camera race',
  );
  assert.equal(created.json.race.proofRequirement, 'ai_check');
  assert.equal(created.json.race.proofMode, 'ai_check');
  assert.equal(created.json.race.verificationMethod, 'camera_pose');

  // And because the contract stayed camera, a manual proof rejects.
  w.member(raceId, 'B');
  const proof = await w.req('B', 'POST', `/races/${raceId}/proof`, {
    proofType: 'manual',
    value: 10,
    mediaObjectKey: w.photo(raceId, 'B'),
  });
  assert.equal(proof.status, 400, proof.text);
  assert.equal(proof.json.error, 'This race uses camera proof.');

  // v0 keeps the literal request: the same body stores the photo contract
  // (legacy quirk old builds may already rely on).
  const v0 = await w.req('A', 'POST', '/races', presetBody({
    proofRequirement: 'photo_video',
    proofMode: 'photo_video',
  }));
  assert.equal(v0.status, 201, v0.text);
  assert.equal(
    w.one('SELECT verification_type FROM races WHERE id = ?', v0.json.race.id).verification_type,
    'photo',
    'v0 stores whatever the client asked for',
  );
});

// ── gap 13: v1 custom goals race First to / Most total + take photo proof ────

test('test_gap13_manual_goal_rejects_attempt_formats', async () => {
  const w = world();
  w.user('A');

  for (const format of ['best_attempt', 'timed_attempt']) {
    const res = await w.req('A', 'POST', '/races', manualBody({
      format,
      goalType: format,
      targetValue: undefined,
      finishLineAt: iso(48 * HOUR),
      attemptDurationSeconds: 30,
      attemptLimit: 3,
      rulesVersion: 1,
    }));
    assert.equal(res.status, 400, `${format}: ${res.text}`);
    assert.equal(res.json.error, 'Custom goals race First to or Most total.');
  }
  assert.equal(w.q('SELECT id FROM races').length, 0, 'no race row written');

  // First to and Most total still create under v1.
  const goal = await w.req('A', 'POST', '/races', manualBody({ rulesVersion: 1 }));
  assert.equal(goal.status, 201, goal.text);
  const most = await w.req('A', 'POST', '/races', manualBody({
    format: 'most_in_window',
    goalType: 'most_in_window',
    targetValue: undefined,
    finishLineAt: iso(48 * HOUR),
    rulesVersion: 1,
  }));
  assert.equal(most.status, 201, most.text);

  // v0 unchanged: a manual best_attempt race still creates.
  const v0 = await w.req('A', 'POST', '/races', manualBody({
    format: 'best_attempt',
    goalType: 'best_attempt',
    targetValue: undefined,
    finishLineAt: iso(48 * HOUR),
    attemptLimit: 3,
  }));
  assert.equal(v0.status, 201, v0.text);
});

test('test_gap13_v1_manual_goal_proof_normalised_to_photo', async () => {
  const w = world();
  w.user('A');

  // Whatever legacy proof mode a v1 client sends on a custom goal, the
  // stored contract is photo proof — the proof route demands a photo anyway.
  for (const proof of ['note', 'link', 'daily_check', 'manual']) {
    const res = await w.req('A', 'POST', '/races', manualBody({
      proofRequirement: proof,
      proofMode: proof,
      rulesVersion: 1,
    }));
    assert.equal(res.status, 201, `${proof}: ${res.text}`);
    const row = w.one('SELECT verification_type FROM races WHERE id = ?', res.json.race.id);
    assert.equal(row.verification_type, 'photo', `${proof} normalised to photo`);
    assert.equal(res.json.race.proofRequirement, 'photo_video', `${proof} echoes photo_video`);
    assert.equal(res.json.race.proofMode, 'photo_video');
  }

  // v0 keeps the literal mode — a note-proof custom goal stays 'manual'.
  const v0 = await w.req('A', 'POST', '/races', manualBody({
    proofRequirement: 'note',
    proofMode: 'note',
  }));
  assert.equal(v0.status, 201, v0.text);
  assert.equal(
    w.one('SELECT verification_type FROM races WHERE id = ?', v0.json.race.id).verification_type,
    'manual',
    'v0 stores whatever the client asked for',
  );
});

test('test_gap13_existing_manual_attempt_race_still_scores', async () => {
  const w = world();
  w.user('A');
  w.user('B');

  // An existing v0 custom-goal best_attempt race keeps working end to end —
  // the strict format rejection only applies to new v1 creates.
  const created = await w.req('A', 'POST', '/races', manualBody({
    format: 'best_attempt',
    goalType: 'best_attempt',
    targetValue: undefined,
    finishLineAt: iso(48 * HOUR),
    attemptLimit: 3,
  }));
  assert.equal(created.status, 201, created.text);
  const raceId = created.json.race.id;
  assert.equal(w.one('SELECT format FROM races WHERE id = ?', raceId).format, 'best_attempt');
  w.member(raceId, 'B');

  const proof = await w.req('B', 'POST', `/races/${raceId}/proof`, {
    proofType: 'manual',
    value: 42,
    mediaObjectKey: w.photo(raceId, 'B'),
  });
  assert.equal(proof.status, 200, proof.text);
  assert.equal(w.progress(raceId, 'B'), 42, 'v0 manual attempt proof still scores');
  assert.equal(
    w.one("SELECT status FROM race_attempts WHERE race_id = ? AND user_id = 'B'", raceId).status,
    'submitted',
    'the proof bound + closed an attempt',
  );
});

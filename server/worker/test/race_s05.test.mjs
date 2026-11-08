// S5 timed battle — gap 7 Worker side. Strict rules (rules_version >= 1)
// make the server's attempt window authoritative for timed_attempt races:
//   - a seconds-metric proof can never outlast attempt_duration_seconds;
//   - rep rate is judged against the bound attempt's real window
//     (started_at..now), never the client-reported durationMs;
//   - a proof after the attempt deadline has nothing to bind to.
// Legacy races (v0) keep every old behaviour — the same calls score.

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
  const flush = async () => { await Promise.all(pending.splice(0)); };

  return { sqlite, db, r2, env, req, q, one, exec, user, member, flush };
}

const iso = (ms) => new Date(Date.now() + ms).toISOString();
const HOUR = 3600_000;
const CAPS = { runtimeCapabilities: ['pose_landmarks_v1', 'derived_features_v1', 'sequence_match_v1'] };

// Seeds the registry rows a preset race's verification session needs
// (same shape as race_s01 / final_matrix).
function seedPreset(w, activityId = 'push_ups', formats = ['first_to_goal']) {
  w.exec(
    `INSERT INTO motion_activities (id, display_name, category, proof_label, measurement_type, metric,
       suggested_targets_json, supported_formats_json, icon_key, availability)
     VALUES (?, 'Pushups', 'upper_body', 'pushups', 'repetitions', 'reps', '[10]', ?, 'x', 'supported')`,
    activityId, JSON.stringify(formats),
  );
  const cols = w.q("SELECT name FROM pragma_table_info('verifier_releases')").map((c) => c.name);
  const seeded = w.one("SELECT spec_json FROM verifier_releases WHERE activity_id = 'custom_pose_sequence' LIMIT 1");
  const spec = { ...JSON.parse(seeded.spec_json), releaseId: `rel-${activityId}`, activityId };
  const values = { id: `rel-${activityId}`, activity_id: activityId, semver: '2026.09.0', change_class: 'minor', engine_type: 'native_v1', spec_schema_version: 1, spec_json: JSON.stringify(spec), checksum: `sum-${activityId}`, required_capabilities_json: '[]', minimum_app_build: 'legacy', compatibility_group: 'g1', status: 'stable' };
  const use = cols.filter((c) => values[c] !== undefined);
  w.exec(`INSERT INTO verifier_releases (${use.join(', ')}) VALUES (${use.map(() => '?').join(', ')})`, ...use.map((c) => values[c]));
  w.exec("INSERT INTO activity_channel_releases (activity_id, channel, release_id, rollout_percent) VALUES (?, 'stable', ?, 100)", activityId, `rel-${activityId}`);
}

// Creates a timed_attempt preset race through POST /races.
async function timedRace(w, over = {}) {
  const res = await w.req('A', 'POST', '/races', {
    title: 'Timed battle',
    goalType: 'first_to_goal',
    activityId: 'push_ups',
    aiActivityType: 'push_ups',
    metric: 'reps',
    targetUnit: 'reps',
    format: 'timed_attempt',
    attemptLimit: 3,
    attemptDurationSeconds: 30,
    finishLineAt: iso(48 * HOUR),
    proofRequirement: 'ai_check',
    proofMode: 'ai_check',
    proofReviewMode: 'auto_accept',
    verificationMethod: 'ai',
    ...over,
  });
  assert.equal(res.status, 201, res.text);
  return res.json.race.id;
}

let subN = 0;
// Mints + completes a verification session, then submits the AI proof.
async function aiProof(w, raceId, userId, value, { metric = 'reps', durationMs, csId } = {}) {
  const mint = await w.req(userId, 'POST', `/races/${raceId}/verification-sessions`, CAPS);
  assert.equal(mint.status, 201, `mint session: ${mint.text}`);
  const vs = mint.json.session;
  const done = await w.req(userId, 'POST', `/verification-sessions/${vs.id}/complete`, {
    releaseId: vs.releaseId, releaseChecksum: vs.releaseChecksum, status: 'completed', resultValue: value,
  });
  assert.equal(done.status, 200, `complete session: ${done.text}`);
  const res = await w.req(userId, 'POST', `/races/${raceId}/proof`, {
    proofType: 'ai_motion',
    metric,
    value,
    durationMs,
    clientSubmissionId: csId ?? `cs-${++subN}`,
    verificationSessionId: vs.id,
    verificationStatus: 'ai_verified',
    activityType: 'push_ups',
  });
  return { res, sessionId: vs.id };
}

const openAttempt = (w, raceId, userId) =>
  w.req(userId, 'POST', `/races/${raceId}/attempts`, {});

// ── gap 7: v1 timed attempts cap the seconds metric at the duration ──────────

test('test_gap7_timed_seconds_value_capped_at_duration', async () => {
  const w = world();
  w.user('A');
  w.user('B');
  seedPreset(w);

  // Strict race stored as a seconds-metric timed battle — no preset activity
  // supports timed seconds today, so the row is bent to the shape the rule
  // guards (the same shape a legacy/manual-metric race could carry).
  const raceId = await timedRace(w, { rulesVersion: 1 });
  w.exec("UPDATE races SET metric = 'seconds' WHERE id = ?", raceId);
  w.member(raceId, 'B');

  const att = await openAttempt(w, raceId, 'B');
  assert.equal(att.status, 200, att.text);

  // 31 s of hold inside a 30 s window is impossible — rejected.
  const over = await aiProof(w, raceId, 'B', 31, { metric: 'seconds' });
  assert.equal(over.res.status, 400, over.res.text);
  assert.match(over.res.text, /attempt duration/);
  assert.equal(
    w.one("SELECT status FROM race_attempts WHERE race_id = ? AND user_id = 'B'", raceId).status,
    'open',
    'the rejected proof leaves the attempt open for a retry',
  );

  // Exactly at the duration scores and binds normally.
  const atCap = await aiProof(w, raceId, 'B', 30, { metric: 'seconds' });
  assert.equal(atCap.res.status, 200, atCap.res.text);
  assert.equal(
    w.one("SELECT status FROM race_attempts WHERE race_id = ? AND user_id = 'B'", raceId).status,
    'submitted',
  );

  // v0: the identical call keeps the old behaviour — no duration cap, the
  // proof binds its open attempt and scores.
  const legacyId = await timedRace(w);
  w.exec("UPDATE races SET metric = 'seconds' WHERE id = ?", legacyId);
  w.member(legacyId, 'B');
  const legacyAtt = await openAttempt(w, legacyId, 'B');
  assert.equal(legacyAtt.status, 200, legacyAtt.text);
  const legacy = await aiProof(w, legacyId, 'B', 31, { metric: 'seconds' });
  assert.equal(legacy.res.status, 200, legacy.res.text);
});

// ── gap 7: v1 proofs after the attempt deadline have nothing to bind ─────────

test('test_gap7_proof_after_attempt_deadline_rejected', async () => {
  const w = world();
  w.user('A');
  w.user('B');
  seedPreset(w);

  const raceId = await timedRace(w, { rulesVersion: 1 });
  w.member(raceId, 'B');
  const att = await openAttempt(w, raceId, 'B');
  assert.equal(att.status, 200, att.text);

  // The attempt's window closed before the proof arrived — past the submit
  // grace the attempt reads expired and a v1 timed race never auto-opens.
  w.exec(
    "UPDATE race_attempts SET deadline_at = ? WHERE race_id = ? AND user_id = 'B'",
    iso(-60 * 1000),
    raceId,
  );
  const late = await aiProof(w, raceId, 'B', 10);
  assert.equal(late.res.status, 400, late.res.text);
  assert.match(late.res.text, /Start an attempt/);

  // v0: the same shape still scores — the stale attempt expires and the
  // legacy auto-open declares a fresh one for the proof to bind.
  const legacyId = await timedRace(w);
  w.member(legacyId, 'B');
  const legacyAtt = await openAttempt(w, legacyId, 'B');
  assert.equal(legacyAtt.status, 200, legacyAtt.text);
  w.exec(
    "UPDATE race_attempts SET deadline_at = ? WHERE race_id = ? AND user_id = 'B'",
    iso(-60 * 1000),
    legacyId,
  );
  const legacy = await aiProof(w, legacyId, 'B', 10);
  assert.equal(legacy.res.status, 200, legacy.res.text);
  assert.equal(
    w.one("SELECT status FROM race_attempts WHERE race_id = ? AND user_id = 'B' AND status = 'submitted'", legacyId).status,
    'submitted',
  );
});

// ── gap 7: v1 rep rate is judged against the attempt window, not durationMs ──

test('test_gap7_rep_rate_uses_attempt_window', async () => {
  const w = world();
  w.user('A');
  w.user('B');
  seedPreset(w);

  const raceId = await timedRace(w, { rulesVersion: 1 });
  w.member(raceId, 'B');
  const att = await openAttempt(w, raceId, 'B');
  assert.equal(att.status, 200, att.text);

  // The client claims a 60 s recording (20 reps < 5 + 60*5, so the old
  // client-clock check passes) — but the attempt has been open ~0 s, so the
  // real window cannot possibly hold 20 verified reps.
  const implausible = await aiProof(w, raceId, 'B', 20, { durationMs: 60_000 });
  assert.equal(implausible.res.status, 400, implausible.res.text);
  assert.match(implausible.res.text, /attempt window/);

  // The same attempt takes an honest count for a ~0 s window — 5 reps is
  // the generous per-second bound, so it scores and binds.
  const honest = await aiProof(w, raceId, 'B', 5, { durationMs: 60_000 });
  assert.equal(honest.res.status, 200, honest.res.text);

  // v0: identical shapes keep judging by the client-reported durationMs —
  // 20 reps inside a claimed 60 s window is plausible and scores.
  const legacyId = await timedRace(w);
  w.member(legacyId, 'B');
  const legacyAtt = await openAttempt(w, legacyId, 'B');
  assert.equal(legacyAtt.status, 200, legacyAtt.text);
  const legacy = await aiProof(w, legacyId, 'B', 20, { durationMs: 60_000 });
  assert.equal(legacy.res.status, 200, legacy.res.text);
});

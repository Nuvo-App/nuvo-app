// S1 race-rules fixes — attempt auto-open, session reuse, rematch finish
// lines, score-direction coercion, timed duration defaults, stale untimed
// attempts, PATCH hardening, and review-accept binding + events.

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
const CAPS = { runtimeCapabilities: ['pose_landmarks_v1', 'derived_features_v1', 'sequence_match_v1'] };

// Seeds the registry rows a preset race's verification session needs
// (same shape as release_p0_sql / final_matrix).
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

// Creates an attempt-format preset race through POST /races.
async function attemptRace(w, format, over = {}) {
  const res = await w.req('A', 'POST', '/races', {
    title: `${format} race`,
    goalType: 'first_to_goal',
    activityId: 'push_ups',
    aiActivityType: 'push_ups',
    metric: 'reps',
    targetUnit: 'reps',
    format,
    attemptLimit: 3,
    finishLineAt: iso(48 * HOUR),
    proofRequirement: 'ai_check',
    proofMode: 'ai_check',
    proofReviewMode: 'auto_accept',
    verificationMethod: 'ai',
    ...(format === 'timed_attempt' ? { attemptDurationSeconds: 30 } : {}),
    ...over,
  });
  assert.equal(res.status, 201, res.text);
  return res.json.race.id;
}

let subN = 0;
// Mints + completes a verification session, then submits the AI proof.
// Returns the proof response and the session id (for retry assertions).
async function aiProof(w, raceId, userId, value, csId) {
  const mint = await w.req(userId, 'POST', `/races/${raceId}/verification-sessions`, CAPS);
  assert.equal(mint.status, 201, `mint session: ${mint.text}`);
  const vs = mint.json.session;
  const done = await w.req(userId, 'POST', `/verification-sessions/${vs.id}/complete`, {
    releaseId: vs.releaseId, releaseChecksum: vs.releaseChecksum, status: 'completed', resultValue: value,
  });
  assert.equal(done.status, 200, `complete session: ${done.text}`);
  const res = await w.req(userId, 'POST', `/races/${raceId}/proof`, {
    proofType: 'ai_motion',
    metric: 'reps',
    value,
    clientSubmissionId: csId ?? `cs-${++subN}`,
    verificationSessionId: vs.id,
    verificationStatus: 'ai_verified',
    activityType: 'push_ups',
  });
  return { res, sessionId: vs.id };
}

// ── gap 4: auto-open on bind miss ────────────────────────────────────────────

test('test_gap4_ai_proof_auto_opens_attempt', async () => {
  const w = world();
  w.user('A');
  w.user('B');
  seedPreset(w);

  // best_attempt: verified proof with no open attempt auto-opens one.
  const raceId = await attemptRace(w, 'best_attempt');
  w.member(raceId, 'B');
  const { res } = await aiProof(w, raceId, 'B', 12);
  assert.equal(res.status, 200, res.text);
  const attempt = w.one("SELECT * FROM race_attempts WHERE race_id = ? AND user_id = 'B'", raceId);
  assert.equal(attempt.status, 'submitted', 'auto-opened attempt closed by the proof');
  assert.equal(attempt.score, 12);
  const events = w.q('SELECT event_type FROM race_events WHERE race_id = ?', raceId).map((r) => r.event_type);
  assert.ok(events.includes('attempt_started'), 'same event as POST /attempts');
  assert.ok(events.includes('attempt_completed'));
  assert.equal(w.progress(raceId, 'B'), 12);

  // timed_attempt on legacy rules (v0): same auto-open applies.
  const legacyId = await attemptRace(w, 'timed_attempt');
  w.member(legacyId, 'B');
  const legacy = await aiProof(w, legacyId, 'B', 15);
  assert.equal(legacy.res.status, 200, legacy.res.text);
  assert.equal(
    w.one("SELECT status FROM race_attempts WHERE race_id = ? AND user_id = 'B'", legacyId).status,
    'submitted',
  );

  // timed_attempt on strict rules (v1): the explicit attempt flow is
  // required — a bare proof still rejects.
  const strictId = await attemptRace(w, 'timed_attempt', { rulesVersion: 1 });
  w.member(strictId, 'B');
  const strict = await aiProof(w, strictId, 'B', 15);
  assert.equal(strict.res.status, 400, strict.res.text);
});

test('test_gap4_auto_open_respects_attempt_limit', async () => {
  const w = world();
  w.user('A');
  w.user('B');
  seedPreset(w);
  const raceId = await attemptRace(w, 'best_attempt', { attemptLimit: 1 });
  w.member(raceId, 'B');

  // Attempt 1: explicit open + bind consumes the only attempt.
  const att = await w.req('B', 'POST', `/races/${raceId}/attempts`, {});
  assert.equal(att.status, 200, att.text);
  const first = await aiProof(w, raceId, 'B', 12);
  assert.equal(first.res.status, 200, first.res.text);

  // No attempts left → auto-open refuses; the rejection stays a clean 400.
  const second = await aiProof(w, raceId, 'B', 9);
  assert.equal(second.res.status, 400, second.res.text);
  assert.match(second.res.text, /Start an attempt/);
  assert.equal(
    w.q("SELECT id FROM race_attempts WHERE race_id = ? AND user_id = 'B'", raceId).length,
    1,
    'no extra attempt row was opened',
  );
});

test('test_gap4_explicit_attempt_still_binds_first', async () => {
  const w = world();
  w.user('A');
  w.user('B');
  seedPreset(w);
  const raceId = await attemptRace(w, 'best_attempt');
  w.member(raceId, 'B');

  const att = await w.req('B', 'POST', `/races/${raceId}/attempts`, {});
  assert.equal(att.status, 200, att.text);
  const attemptId = att.json.attempt.id;

  const { res } = await aiProof(w, raceId, 'B', 12);
  assert.equal(res.status, 200, res.text);
  const rows = w.q("SELECT * FROM race_attempts WHERE race_id = ? AND user_id = 'B'", raceId);
  assert.equal(rows.length, 1, 'proof binds the explicit attempt — no auto-open');
  assert.equal(rows[0].id, attemptId);
  assert.equal(rows[0].status, 'submitted');
  assert.equal(rows[0].score, 12);
});

// ── N4: rejected bind must not consume the session ───────────────────────────

test('test_gap8_rejected_bind_does_not_consume_session', async () => {
  const w = world();
  w.user('A');
  w.user('B');
  seedPreset(w);

  // A first_to_goal preset race keeps attempts out of the picture — this
  // test isolates the session / client-submission reuse.
  const created = await w.req('A', 'POST', '/races', {
    title: 'Sprint',
    goalType: 'first_to_goal',
    targetValue: 50,
    activityId: 'push_ups',
    aiActivityType: 'push_ups',
    metric: 'reps',
    targetUnit: 'reps',
    proofRequirement: 'ai_check',
    proofMode: 'ai_check',
    verificationMethod: 'ai',
  });
  assert.equal(created.status, 201, created.text);
  const raceId = created.json.race.id;
  w.member(raceId, 'B');

  // Simulate the legacy failure shape: a move_log rejected for a race-state
  // reason still carries the session + submission ids in its metadata.
  const mint = await w.req('B', 'POST', `/races/${raceId}/verification-sessions`, CAPS);
  assert.equal(mint.status, 201, mint.text);
  const vs = mint.json.session;
  const done = await w.req('B', 'POST', `/verification-sessions/${vs.id}/complete`, {
    releaseId: vs.releaseId, releaseChecksum: vs.releaseChecksum, status: 'completed', resultValue: 10,
  });
  assert.equal(done.status, 200, done.text);
  w.exec(
    `INSERT INTO move_logs (id, race_id, user_id, source, status, value, client_submission_id, metadata_json, created_at)
     VALUES ('m-old', ?, 'B', 'movecheck', 'rejected', 10, 'cs-1', ?, CURRENT_TIMESTAMP)`,
    raceId,
    JSON.stringify({ verification_session_id: vs.id }),
  );

  // Retrying the same submission + session must proceed and score — a
  // rejected row is not a committed proof.
  const res = await w.req('B', 'POST', `/races/${raceId}/proof`, {
    proofType: 'ai_motion',
    metric: 'reps',
    value: 10,
    clientSubmissionId: 'cs-1',
    verificationSessionId: vs.id,
    verificationStatus: 'ai_verified',
    activityType: 'push_ups',
  });
  assert.equal(res.status, 200, res.text);
  const rows = w.q("SELECT status FROM move_logs WHERE race_id = ? AND client_submission_id = 'cs-1'", raceId);
  assert.equal(rows.length, 1, 'the rejected row is revived in place');
  assert.equal(rows[0].status, 'verified');
  assert.equal(w.progress(raceId, 'B'), 10);
});

test('test_gap8_retry_after_opening_attempt_scores', async () => {
  const w = world();
  w.user('A');
  w.user('B');
  seedPreset(w);

  // Strict rules make the failure reachable: v1 timed_attempt never
  // auto-opens, so the bare proof rejects with nothing written.
  const raceId = await attemptRace(w, 'timed_attempt', { rulesVersion: 1 });
  w.member(raceId, 'B');

  const first = await aiProof(w, raceId, 'B', 7, 'cs-retry');
  assert.equal(first.res.status, 400, first.res.text);
  assert.equal(
    w.q('SELECT id FROM move_logs WHERE race_id = ?', raceId).length,
    0,
    'rejection writes no move row — session, media, and submission id stay fresh',
  );

  const att = await w.req('B', 'POST', `/races/${raceId}/attempts`, {});
  assert.equal(att.status, 200, att.text);

  // Identical retry payload: same session, same clientSubmissionId.
  const retry = await w.req('B', 'POST', `/races/${raceId}/proof`, {
    proofType: 'ai_motion',
    metric: 'reps',
    value: 7,
    clientSubmissionId: 'cs-retry',
    verificationSessionId: first.sessionId,
    verificationStatus: 'ai_verified',
    activityType: 'push_ups',
  });
  assert.equal(retry.status, 200, retry.text);
  assert.equal(w.progress(raceId, 'B'), 7);
  assert.equal(
    w.one("SELECT status FROM race_attempts WHERE race_id = ? AND user_id = 'B'", raceId).status,
    'submitted',
  );
});

// ── N2: rematch finish line ──────────────────────────────────────────────────

test('test_gap3_rematch_window_race_gets_finish_line', async () => {
  const w = world();
  w.user('A');
  w.user('B');

  // Source race with a real window (start +1h, finish +49h → 48h window).
  const created = await w.req('A', 'POST', '/races', {
    title: 'Pages Week',
    goalType: 'manual',
    unit: 'pages',
    targetUnit: 'pages',
    format: 'most_in_window',
    proofRequirement: 'photo_video',
    startLineAt: iso(HOUR),
    finishLineAt: iso(49 * HOUR),
  });
  assert.equal(created.status, 201, created.text);
  const raceId = created.json.race.id;
  w.member(raceId, 'B');

  const rematch = await w.req('B', 'POST', `/races/${raceId}/rematch`, {});
  assert.equal(rematch.status, 201, rematch.text);
  const newEnd = w.one('SELECT end_at FROM races WHERE id = ?', rematch.json.race.id).end_at;
  assert.ok(newEnd, 'rematch of a window race gets a finish line');
  const expected = Date.now() + 48 * HOUR;
  assert.ok(
    Math.abs(new Date(newEnd).getTime() - expected) < 60_000,
    `original 48h window is preserved, got ${newEnd}`,
  );

  // Legacy hole: source row with no start/end — the create-time default
  // (7 days for most_in_window) applies instead.
  w.exec(
    `INSERT INTO races (id, creator_id, title, race_type, format, verification_type, status, visibility)
     VALUES ('legacy-window', 'A', 'Old Window', 'most_in_window', 'most_in_window', 'manual', 'completed', 'crew_only')`,
  );
  w.member('legacy-window', 'B');
  const rematch2 = await w.req('B', 'POST', '/races/legacy-window/rematch', {});
  assert.equal(rematch2.status, 201, rematch2.text);
  const end2 = w.one('SELECT end_at FROM races WHERE id = ?', rematch2.json.race.id).end_at;
  assert.ok(end2, 'default finish line applied');
  const expected2 = Date.now() + 7 * 24 * HOUR;
  assert.ok(
    Math.abs(new Date(end2).getTime() - expected2) < 60_000,
    `7-day default applied, got ${end2}`,
  );
});

test('test_gap3_rematch_first_to_goal_keeps_null_end', async () => {
  const w = world();
  w.user('A');
  w.user('B');
  const created = await w.req('A', 'POST', '/races', {
    title: 'First to 50',
    goalType: 'manual',
    targetValue: 50,
    unit: 'pages',
    proofRequirement: 'manual',
  });
  assert.equal(created.status, 201, created.text);
  const raceId = created.json.race.id;
  w.member(raceId, 'B');

  const rematch = await w.req('B', 'POST', `/races/${raceId}/rematch`, {});
  assert.equal(rematch.status, 201, rematch.text);
  assert.equal(
    w.one('SELECT end_at FROM races WHERE id = ?', rematch.json.race.id).end_at,
    null,
    'first_to_goal is decided at the goal — no finish line',
  );
});

// ── gap 11: score_direction coerced on cumulative formats ────────────────────

test('test_gap11_score_direction_coerced_on_cumulative_formats', async () => {
  const w = world();
  w.user('A');

  // Create-time coercion for both cumulative formats.
  const win = await w.req('A', 'POST', '/races', {
    title: 'Window',
    goalType: 'manual',
    unit: 'pages',
    format: 'most_in_window',
    proofRequirement: 'manual',
    finishLineAt: iso(48 * HOUR),
    scoreDirection: 'lower',
  });
  assert.equal(win.status, 201, win.text);
  assert.equal(w.one('SELECT score_direction FROM races WHERE id = ?', win.json.race.id).score_direction, 'higher');
  assert.equal(win.json.race.scoreDirection, 'higher');

  const goal = await w.req('A', 'POST', '/races', {
    title: 'Goal',
    goalType: 'manual',
    targetValue: 10,
    unit: 'pages',
    proofRequirement: 'manual',
    scoreDirection: 'lower',
  });
  assert.equal(goal.status, 201, goal.text);
  assert.equal(w.one('SELECT score_direction FROM races WHERE id = ?', goal.json.race.id).score_direction, 'higher');
  assert.equal(goal.json.race.scoreDirection, 'higher');

  // Attempt formats keep the stored direction — 'lower' is meaningful
  // (lowest verified attempt wins).
  const attempt = await w.req('A', 'POST', '/races', {
    title: 'Attempt',
    goalType: 'manual',
    unit: 'seconds',
    format: 'best_attempt',
    attemptLimit: 3,
    proofRequirement: 'manual',
    finishLineAt: iso(48 * HOUR),
    scoreDirection: 'lower',
  });
  assert.equal(attempt.status, 201, attempt.text);
  assert.equal(w.one('SELECT score_direction FROM races WHERE id = ?', attempt.json.race.id).score_direction, 'lower');
  assert.equal(attempt.json.race.scoreDirection, 'lower');

  // Read-time coercion: a legacy row already poisoned with 'lower' reads
  // 'higher' — the leaderboard can never invert.
  w.exec(
    `INSERT INTO races (id, creator_id, title, race_type, format, verification_type, status, visibility, score_direction)
     VALUES ('poisoned', 'A', 'Old', 'most_in_window', 'most_in_window', 'manual', 'active', 'crew_only', 'lower')`,
  );
  w.member('poisoned', 'A', 'creator');
  const got = await w.req('A', 'GET', '/races/poisoned');
  assert.equal(got.status, 200, got.text);
  assert.equal(got.json.race.scoreDirection, 'higher', 'read path coerces stored lower on cumulative formats');
});

// ── gap 6: timed_attempt duration default / requirement ──────────────────────

test('test_gap6_preset_timed_attempt_defaults_duration', async () => {
  const w = world();
  w.user('A');
  seedPreset(w);

  // Legacy rules: a timed attempt without an explicit clock keeps the
  // historical 60-second default.
  const res = await w.req('A', 'POST', '/races', {
    title: 'Timed',
    goalType: 'first_to_goal',
    activityId: 'push_ups',
    aiActivityType: 'push_ups',
    metric: 'reps',
    format: 'timed_attempt',
    attemptLimit: 3,
    finishLineAt: iso(48 * HOUR),
    proofRequirement: 'ai_check',
    verificationMethod: 'ai',
  });
  assert.equal(res.status, 201, res.text);
  assert.equal(
    w.one('SELECT attempt_duration_seconds FROM races WHERE id = ?', res.json.race.id).attempt_duration_seconds,
    60,
    'v0 timed_attempt defaults to 60s',
  );
  assert.equal(res.json.race.attemptDurationSeconds, 60);

  // Registry path (control-plane activity this Worker predates): same
  // default applies.
  seedPreset(w, 'wall_sit_hold', ['timed_attempt']);
  const reg = await w.req('A', 'POST', '/races', {
    title: 'Registry Timed',
    goalType: 'first_to_goal',
    activityId: 'wall_sit_hold',
    metric: 'reps',
    format: 'timed_attempt',
    attemptLimit: 3,
    finishLineAt: iso(48 * HOUR),
    proofRequirement: 'ai_check',
    verificationMethod: 'ai',
  });
  assert.equal(reg.status, 201, reg.text);
  assert.equal(
    w.one('SELECT attempt_duration_seconds FROM races WHERE id = ?', reg.json.race.id).attempt_duration_seconds,
    60,
    'registry timed_attempt defaults to 60s under v0',
  );
});

test('test_gap6_v1_timed_attempt_requires_duration', async () => {
  const w = world();
  w.user('A');
  seedPreset(w);

  const res = await w.req('A', 'POST', '/races', {
    title: 'Timed',
    goalType: 'first_to_goal',
    activityId: 'push_ups',
    aiActivityType: 'push_ups',
    metric: 'reps',
    format: 'timed_attempt',
    attemptLimit: 3,
    finishLineAt: iso(48 * HOUR),
    proofRequirement: 'ai_check',
    verificationMethod: 'ai',
    rulesVersion: 1,
  });
  assert.equal(res.status, 400, res.text);
  assert.equal(res.json.error, 'Attempt duration is required.');
  assert.equal(w.q('SELECT id FROM races').length, 0, 'no race row written');

  // Registry path: same requirement under v1.
  seedPreset(w, 'wall_sit_hold', ['timed_attempt']);
  const reg = await w.req('A', 'POST', '/races', {
    title: 'Registry Timed',
    goalType: 'first_to_goal',
    activityId: 'wall_sit_hold',
    metric: 'reps',
    format: 'timed_attempt',
    attemptLimit: 3,
    finishLineAt: iso(48 * HOUR),
    proofRequirement: 'ai_check',
    verificationMethod: 'ai',
    rulesVersion: 1,
  });
  assert.equal(reg.status, 400, reg.text);
  assert.equal(reg.json.error, 'Attempt duration is required.');
});

// ── N7: stale untimed attempts ───────────────────────────────────────────────

test('test_gap12_stale_untimed_attempt_expires', async () => {
  const w = world();
  w.user('A');
  w.user('B');
  seedPreset(w);
  const raceId = await attemptRace(w, 'best_attempt');
  w.member(raceId, 'B');

  // An untimed attempt abandoned 7h ago (OPEN_ATTEMPT_TTL_MS = 6h).
  w.exec(
    `INSERT INTO race_attempts (id, race_id, user_id, attempt_index, status, started_at, deadline_at, created_at)
     VALUES ('stale-1', ?, 'B', 1, 'open', ?, NULL, CURRENT_TIMESTAMP)`,
    raceId,
    new Date(Date.now() - 7 * HOUR).toISOString(),
  );

  const { res } = await aiProof(w, raceId, 'B', 12);
  assert.equal(res.status, 200, res.text);
  assert.equal(
    w.one("SELECT status FROM race_attempts WHERE id = 'stale-1'").status,
    'expired',
    'stale untimed attempt expires instead of binding',
  );
  const bound = w.one("SELECT * FROM race_attempts WHERE race_id = ? AND user_id = 'B' AND status = 'submitted'", raceId);
  assert.ok(bound, 'auto-open produced a fresh attempt for the proof');
  assert.notEqual(bound.id, 'stale-1');
  assert.equal(bound.score, 12);
});

test('test_gap12_fresh_untimed_attempt_binds', async () => {
  const w = world();
  w.user('A');
  w.user('B');
  seedPreset(w);
  const raceId = await attemptRace(w, 'best_attempt');
  w.member(raceId, 'B');

  // An untimed attempt opened 1h ago is inside the 6h TTL — still bindable.
  w.exec(
    `INSERT INTO race_attempts (id, race_id, user_id, attempt_index, status, started_at, deadline_at, created_at)
     VALUES ('fresh-1', ?, 'B', 1, 'open', ?, NULL, CURRENT_TIMESTAMP)`,
    raceId,
    new Date(Date.now() - HOUR).toISOString(),
  );

  const { res } = await aiProof(w, raceId, 'B', 12);
  assert.equal(res.status, 200, res.text);
  const rows = w.q("SELECT * FROM race_attempts WHERE race_id = ? AND user_id = 'B'", raceId);
  assert.equal(rows.length, 1, 'fresh untimed attempt binds — no auto-open');
  assert.equal(rows[0].id, 'fresh-1');
  assert.equal(rows[0].status, 'submitted');
});

// ── N8: PATCH clearing the finish line ───────────────────────────────────────

test('test_gap13_clearing_finish_line_400s_for_all_deadline_formats', async () => {
  const w = world();
  w.user('A');
  seedPreset(w);

  for (const format of ['most_in_window', 'best_attempt', 'timed_attempt']) {
    const raceId = await attemptRace(w, format);
    const res = await w.req('A', 'PATCH', `/races/${raceId}`, { finishLineAt: null });
    assert.equal(res.status, 400, `${format}: ${res.text}`);
    assert.match(res.text, /finish line is required/i);
    assert.ok(
      w.one('SELECT end_at FROM races WHERE id = ?', raceId).end_at,
      `${format} finish line survives the rejected clear`,
    );
  }

  // first_to_goal has no deadline contract — clearing stays legal.
  const goal = await w.req('A', 'POST', '/races', {
    title: 'Goal',
    goalType: 'manual',
    targetValue: 10,
    unit: 'pages',
    proofRequirement: 'manual',
    finishLineAt: iso(48 * HOUR),
  });
  assert.equal(goal.status, 201, goal.text);
  const cleared = await w.req('A', 'PATCH', `/races/${goal.json.race.id}`, { finishLineAt: null });
  assert.equal(cleared.status, 200, cleared.text);
  assert.equal(w.one('SELECT end_at FROM races WHERE id = ?', goal.json.race.id).end_at, null);
});

// ── N9: PATCH goalType must not overwrite race_type ──────────────────────────

test('test_gap14_settings_patch_preserves_race_type', async () => {
  const w = world();
  w.user('A');
  seedPreset(w);

  const raceId = await attemptRace(w, 'best_attempt');
  const patched = await w.req('A', 'PATCH', `/races/${raceId}`, { goalType: 'manual', title: 'Renamed' });
  assert.equal(patched.status, 200, patched.text);
  const row = w.one('SELECT race_type, format FROM races WHERE id = ?', raceId);
  assert.equal(row.format, 'best_attempt');
  assert.equal(row.race_type, 'best_attempt', 'canonical format wins — goalType cannot rewrite race_type');

  // A legacy-vocabulary row (race_type diverged from the format column
  // default) still honours the old goalType mapping.
  w.exec(
    `INSERT INTO races (id, creator_id, title, race_type, verification_type, status, visibility)
     VALUES ('legacy-rt', 'A', 'Old', 'daily_streak', 'manual', 'active', 'crew_only')`,
  );
  const legacy = await w.req('A', 'PATCH', '/races/legacy-rt', { goalType: 'most' });
  assert.equal(legacy.status, 200, legacy.text);
  assert.equal(
    w.one('SELECT race_type FROM races WHERE id = ?', 'legacy-rt').race_type,
    'most_in_time',
    'legacy-vocabulary rows keep the goalType mapping',
  );
});

// ── N5 + N6: review-accept binds by proof time + emits events ────────────────

test('test_gap9_review_accept_after_attempt_expiry_scores', async () => {
  const w = world();
  w.user('A');
  w.user('B');
  seedPreset(w);
  const raceId = await attemptRace(w, 'timed_attempt', { proofReviewMode: 'peer_review' });
  w.member(raceId, 'B');

  // Attempt window: started 80s ago, deadline 50s ago (+15s grace → binds
  // proof produced up to 35s ago). The proof's created_at sits inside.
  const mediaKey = w.photo(raceId, 'B');
  w.exec(
    `INSERT INTO race_attempts (id, race_id, user_id, attempt_index, status, started_at, deadline_at, created_at)
     VALUES ('att-1', ?, 'B', 1, 'open', ?, ?, CURRENT_TIMESTAMP)`,
    raceId,
    new Date(Date.now() - 80_000).toISOString(),
    new Date(Date.now() - 50_000).toISOString(),
  );
  w.exec(
    `INSERT INTO move_logs (id, race_id, user_id, source, status, value, media_object_key, created_at)
     VALUES ('mv-1', ?, 'B', 'manual', 'pending', 25, ?, ?)`,
    raceId,
    mediaKey,
    new Date(Date.now() - 40_000).toISOString().replace('T', ' ').slice(0, 19),
  );

  const review = await w.req('A', 'PATCH', `/races/${raceId}/proofs/mv-1`, { verificationStatus: 'accepted' });
  assert.equal(review.status, 200, review.text);
  assert.equal(w.progress(raceId, 'B'), 25, 'proof accepted by its own time window');
  const attempt = w.one("SELECT * FROM race_attempts WHERE id = 'att-1'");
  assert.equal(attempt.status, 'submitted');
  assert.equal(attempt.move_log_id, 'mv-1');
  assert.equal(attempt.score, 25);
});

test('test_gap10_review_accept_emits_race_finished_event', async () => {
  const w = world();
  w.user('A');
  w.user('B');

  // first_to_goal peer_review race, target 10 — B is one accept away.
  const created = await w.req('A', 'POST', '/races', {
    title: 'Finish It',
    goalType: 'manual',
    targetValue: 10,
    unit: 'pages',
    proofRequirement: 'photo_video',
    proofReviewMode: 'peer_review',
  });
  assert.equal(created.status, 201, created.text);
  const raceId = created.json.race.id;
  w.member(raceId, 'B');
  w.exec('UPDATE race_progress SET progress_value = 8 WHERE race_id = ? AND user_id = ?', raceId, 'B');

  // Pending proof worth 5 — accepting it pushes B past the goal.
  const mediaKey = w.photo(raceId, 'B');
  w.exec(
    `INSERT INTO move_logs (id, race_id, user_id, source, status, value, media_object_key, created_at)
     VALUES ('mv-win', ?, 'B', 'manual', 'pending', 5, ?, CURRENT_TIMESTAMP)`,
    raceId,
    mediaKey,
  );

  const review = await w.req('A', 'PATCH', `/races/${raceId}/proofs/mv-win`, { verificationStatus: 'accepted' });
  assert.equal(review.status, 200, review.text);
  assert.equal(w.one('SELECT status, winner_user_id FROM races WHERE id = ?', raceId).status, 'completed');
  assert.equal(w.one('SELECT winner_user_id FROM races WHERE id = ?', raceId).winner_user_id, 'B');

  const events = w.q('SELECT event_type FROM race_events WHERE race_id = ?', raceId).map((r) => r.event_type);
  assert.ok(events.includes('race_finished'), 'review-accept persists the finish event');
  assert.ok(events.includes('progress_accepted'));
  assert.ok(events.includes('participant_finished'));
});

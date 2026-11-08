// Race stage S7 (M1 + N12 + N13): the flat per-proof caps (3,000 reps /
// 8 h / 100 k manual) are gone — a proof is judged by per-movement
// plausibility: reps by a generous rate, treadmill distance as metres
// (~10 m/s, 100 km extreme ceiling), seconds against the recorded clock,
// with the 1,000,000 absolute ceiling as the only global bound.
// Replays the PROD schema in real SQLite and drives the compiled app.
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
// Test-only credential for /auth/reviewer — never a real review password.
const REVIEWER_PASSWORD = 'test-review-pass';
const root = new URL('..', import.meta.url);
const SCHEMA = [
  readFileSync(new URL('test/fixtures/prod_schema_2026-09-28.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0042_achievements.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0043_proof_votes.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0044_custom_verifier_seed.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0050_race_rules_version.sql', root), 'utf8'),
];
const MIGRATION_0051 = readFileSync(
  new URL('migrations/0051_registry_timed_attempt.sql', root),
  'utf8',
);

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

  const req = async (sub, method, path, body, raw) => {
    const headers = { 'Content-Type': 'application/json' };
    if (sub) headers.Authorization = `Bearer ${await signJwt({ sub, iat: 0, exp: 9999999999 }, JWT_SECRET)}`;
    const res = await app.request(path, {
      method,
      headers,
      body: raw ?? (body == null ? undefined : JSON.stringify(body)),
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
  const progress = (raceId, userId) => one('SELECT progress_value FROM race_progress WHERE race_id = ? AND user_id = ?', raceId, userId)?.progress_value;

  return { sqlite, db, r2, env, req, q, one, exec, user, progress };
}

const iso = (ms) => new Date(Date.now() + ms).toISOString();
const HOUR = 3600_000;
const CAPS = { runtimeCapabilities: ['pose_landmarks_v1', 'derived_features_v1', 'sequence_match_v1'] };

// Seeds a registry row + stable release + channel pointer for an activity —
// the rows a preset or registry race needs before it can mint sessions.
function seedActivity(
  w,
  activityId,
  {
    measurementType = 'repetitions',
    metric = 'reps',
    targets = '[10,20,40]',
    formats = '["first_to_goal","most_in_window","best_attempt","timed_attempt"]',
    availability = 'supported',
  } = {},
) {
  w.exec(
    `INSERT INTO motion_activities (id, display_name, category, proof_label, measurement_type, metric,
       suggested_targets_json, supported_formats_json, icon_key, availability)
     VALUES (?, ?, 'cardio', ?, ?, ?, ?, ?, 'x', ?)`,
    activityId, activityId, activityId, measurementType, metric, targets, formats, availability,
  );
  const cols = w.q("SELECT name FROM pragma_table_info('verifier_releases')").map((c) => c.name);
  const seeded = w.one("SELECT spec_json FROM verifier_releases WHERE activity_id = 'custom_pose_sequence' LIMIT 1");
  const spec = { ...JSON.parse(seeded.spec_json), releaseId: `rel-${activityId}`, activityId };
  const values = {
    id: `rel-${activityId}`, activity_id: activityId, semver: '2026.09.0',
    change_class: 'minor', engine_type: 'native_v1', spec_schema_version: 1,
    spec_json: JSON.stringify(spec), checksum: `sum-${activityId}`,
    required_capabilities_json: '[]', minimum_app_build: 'legacy',
    compatibility_group: `g-${activityId}`, status: 'stable',
  };
  const use = cols.filter((c) => values[c] !== undefined);
  w.exec(`INSERT INTO verifier_releases (${use.join(', ')}) VALUES (${use.map(() => '?').join(', ')})`, ...use.map((c) => values[c]));
  w.exec("INSERT INTO activity_channel_releases (activity_id, channel, release_id, rollout_percent) VALUES (?, 'stable', ?, 100)", activityId, `rel-${activityId}`);
}

// Creates a camera-verified race through the API — the same body the composer
// sends — so verifier assignment and session minting run the real path.
async function createCameraRace(w, userId, { activityId, format = 'first_to_goal', targetValue, metric = 'reps', attemptDurationSeconds }) {
  const body = {
    title: `S7 ${activityId} ${format}`,
    goalType: format,
    activityId,
    aiActivityType: activityId,
    metric,
    unit: metric,
    targetUnit: metric,
    format,
    proofRequirement: 'ai_check',
    proofMode: 'ai_check',
    proofReviewMode: 'auto_accept',
  };
  if (format === 'first_to_goal') body.targetValue = targetValue;
  else {
    body.finishLineAt = iso(48 * HOUR);
    if (format === 'timed_attempt') body.attemptDurationSeconds = attemptDurationSeconds ?? 60;
  }
  const res = await w.req(userId, 'POST', '/races', body);
  assert.equal(res.status, 201, `create race: ${res.text}`);
  return res.json.race.id;
}

let subN = 0;
// Mints, completes, and submits one AI Motion Proof — the client's real flow.
async function aiProof(w, raceId, userId, { value, durationMs, activityType, metric = 'reps' }) {
  const mint = await w.req(userId, 'POST', `/races/${raceId}/verification-sessions`, CAPS);
  assert.equal(mint.status, 201, `mint session: ${mint.text}`);
  const vs = mint.json.session;
  const done = await w.req(userId, 'POST', `/verification-sessions/${vs.id}/complete`, {
    releaseId: vs.releaseId,
    releaseChecksum: vs.releaseChecksum,
    status: 'completed',
    resultValue: value,
  });
  assert.equal(done.status, 200, `complete session: ${done.text}`);
  return w.req(userId, 'POST', `/races/${raceId}/proof`, {
    proofType: 'ai_motion',
    metric,
    value,
    clientSubmissionId: `cs-${++subN}`,
    verificationSessionId: vs.id,
    verificationStatus: 'ai_verified',
    activityType,
    ...(durationMs !== undefined ? { durationMs } : {}),
  });
}

// ── gap 10: registry rep motions offer timed_attempt after migration 0051 ───

test('migration 0051 gives rep registry rows timed_attempt — not holds or basketball — and reruns cleanly', () => {
  const w = world();
  // Pre-0051 registry shapes: a remote rep motion, a duration hold, basketball.
  for (const [id, measurement, formats] of [
    ['reach_taps', 'repetitions', '["first_to_goal","most_in_window","best_attempt"]'],
    ['hold_stretch', 'duration', '["first_to_goal","most_in_window","best_attempt"]'],
    ['basketball_shot', 'repetitions', '["first_to_goal","most_in_window","best_attempt"]'],
  ]) {
    w.exec(
      `INSERT INTO motion_activities (id, display_name, category, proof_label, measurement_type, metric,
         suggested_targets_json, supported_formats_json, icon_key, availability)
       VALUES (?, ?, 'cardio', ?, ?, 'reps', '[10]', ?, 'x', 'supported')`,
      id, id, id, measurement, formats,
    );
  }
  const formatsOf = (id) => JSON.parse(w.one('SELECT supported_formats_json AS f FROM motion_activities WHERE id = ?', id).f);

  w.sqlite.exec(MIGRATION_0051);
  assert.deepEqual(formatsOf('reach_taps'), ['first_to_goal', 'most_in_window', 'best_attempt', 'timed_attempt']);
  assert.ok(!formatsOf('hold_stretch').includes('timed_attempt'), 'a hold is never a timed rep battle');
  assert.ok(!formatsOf('basketball_shot').includes('timed_attempt'), 'basketball stays untimed');
  // The seeded hidden custom seed is a rep movement — it offers the mode too.
  assert.ok(formatsOf('custom_pose_sequence').includes('timed_attempt'));

  w.sqlite.exec(MIGRATION_0051); // idempotent: a second run appends nothing.
  assert.equal(formatsOf('reach_taps').filter((f) => f === 'timed_attempt').length, 1);
});

test('a registry rep motion races timed_attempt after migration 0051', async () => {
  const w = world();
  w.user('A');
  seedActivity(w, 'reach_taps', {
    formats: '["first_to_goal","most_in_window","best_attempt"]',
  });
  w.sqlite.exec(MIGRATION_0051);
  const res = await w.req('A', 'POST', '/races', {
    title: 'Timed reach taps',
    goalType: 'timed_attempt',
    activityId: 'reach_taps',
    aiActivityType: 'reach_taps',
    metric: 'reps',
    format: 'timed_attempt',
    attemptDurationSeconds: 60,
    finishLineAt: iso(48 * HOUR),
    proofRequirement: 'ai_check',
    proofMode: 'ai_check',
    proofReviewMode: 'auto_accept',
  });
  assert.equal(res.status, 201, res.text);
  assert.equal(res.json.race.format, 'timed_attempt');
});

// ── M1: treadmill proofs are metres, judged by distance plausibility ────────

test('test_gapM1_treadmill_5k_proof_accepted', async () => {
  const w = world();
  w.user('A');
  seedActivity(w, 'treadmill_running', {
    measurementType: 'distance',
    targets: '[400,800,1600,3200,5000]',
  });
  const raceId = await createCameraRace(w, 'A', {
    activityId: 'treadmill_running',
    targetValue: 5000,
  });
  // A real 5 km run in 40 minutes — the old 3,000-rep cap refused this
  // outright; as metres at ~2 m/s it is plainly honest work.
  const res = await aiProof(w, raceId, 'A', {
    value: 5000,
    durationMs: 40 * 60 * 1000,
    activityType: 'treadmill_running',
  });
  assert.equal(res.status, 200, res.text);
  assert.equal(res.json.submissionResult.raceCompleted, true, 'the 5k crosses the finish line');
  assert.equal(w.progress(raceId, 'A'), 5000);
});

test('test_gapM1_fast_distance_not_rep_rate_refused', async () => {
  const w = world();
  w.user('A');
  seedActivity(w, 'treadmill_running', {
    measurementType: 'distance',
    targets: '[400,800,1600,3200,5000]',
  });
  const raceId = await createCameraRace(w, 'A', {
    activityId: 'treadmill_running',
    format: 'most_in_window',
  });
  // 5,000 m in 400 s ≈ 12.5 m/s — impossible sustained speed: refused by the
  // distance-rate bound, which is a different physics than the rep counter.
  const fast = await aiProof(w, raceId, 'A', {
    value: 5000,
    durationMs: 400_000,
    activityType: 'treadmill_running',
  });
  assert.equal(fast.status, 400, fast.text);
  assert.match(fast.json.error, /not possible/i);
  // The extreme ceiling: 150 km is refused even with no recorded duration —
  // the only thing bounded without a clock.
  const mint = await w.req('A', 'POST', `/races/${raceId}/verification-sessions`, CAPS);
  const vs = mint.json.session;
  await w.req('A', 'POST', `/verification-sessions/${vs.id}/complete`, {
    releaseId: vs.releaseId,
    releaseChecksum: vs.releaseChecksum,
    status: 'completed',
    resultValue: 150_000,
  });
  const huge = await w.req('A', 'POST', `/races/${raceId}/proof`, {
    proofType: 'ai_motion',
    metric: 'reps',
    value: 150_000,
    clientSubmissionId: `cs-${++subN}`,
    verificationSessionId: vs.id,
    verificationStatus: 'ai_verified',
    activityType: 'treadmill_running',
  });
  assert.equal(huge.status, 400, huge.text);
  // An honest 5 km in 40 minutes still lands — the race is untouched by the
  // refused attempts.
  const honest = await aiProof(w, raceId, 'A', {
    value: 5000,
    durationMs: 40 * 60 * 1000,
    activityType: 'treadmill_running',
  });
  assert.equal(honest.status, 200, honest.text);
  assert.equal(w.progress(raceId, 'A'), 5000);
});

// ── N12: rep proofs are judged by rate, not a flat cap ──────────────────────

test('test_gapN12_large_honest_rep_set_accepted', async () => {
  const w = world();
  w.user('A');
  seedActivity(w, 'push_ups');
  const raceId = await createCameraRace(w, 'A', {
    activityId: 'push_ups',
    format: 'most_in_window',
  });
  // 4,000 pushups over an 80-minute session — over the old 3,000-rep cap but
  // comfortably inside the generous rep-rate bound (~0.8 reps/s).
  const res = await aiProof(w, raceId, 'A', {
    value: 4000,
    durationMs: 80 * 60 * 1000,
    activityType: 'push_ups',
  });
  assert.equal(res.status, 200, res.text);
  assert.equal(w.progress(raceId, 'A'), 4000);
});

test('test_gapN12_absurd_value_still_rejected', async () => {
  const w = world();
  w.user('A');
  seedActivity(w, 'push_ups');
  const raceId = await createCameraRace(w, 'A', {
    activityId: 'push_ups',
    format: 'most_in_window',
  });
  // 50,000 reps in one minute is physically impossible — the rate bound
  // replaces the old cap for this kind of claim.
  const burst = await aiProof(w, raceId, 'A', {
    value: 50_000,
    durationMs: 60_000,
    activityType: 'push_ups',
  });
  assert.equal(burst.status, 400, burst.text);
  assert.match(burst.json.error, /not possible/i);
  // The hidden absolute ceiling: no proof carries more than 1,000,000.
  const mint = await w.req('A', 'POST', `/races/${raceId}/verification-sessions`, CAPS);
  const vs = mint.json.session;
  await w.req('A', 'POST', `/verification-sessions/${vs.id}/complete`, {
    releaseId: vs.releaseId,
    releaseChecksum: vs.releaseChecksum,
    status: 'completed',
    resultValue: 1_000_001,
  });
  const over = await w.req('A', 'POST', `/races/${raceId}/proof`, {
    proofType: 'ai_motion',
    metric: 'reps',
    value: 1_000_001,
    clientSubmissionId: `cs-${++subN}`,
    verificationSessionId: vs.id,
    verificationStatus: 'ai_verified',
    activityType: 'push_ups',
  });
  assert.equal(over.status, 400, over.text);
  assert.equal(w.progress(raceId, 'A'), 0);
});

// ── N13: seconds metrics judge against the recorded wall clock ──────────────

test('S7: a seconds-metric proof cannot exceed the recorded clock', async () => {
  const w = world();
  w.user('A');
  seedActivity(w, 'plank_hold', {
    measurementType: 'duration',
    metric: 'seconds',
    targets: '[20,30,60,120,600]',
    formats: '["first_to_goal","most_in_window","best_attempt"]',
  });
  const raceId = await createCameraRace(w, 'A', {
    activityId: 'plank_hold',
    format: 'most_in_window',
    metric: 'seconds',
  });
  // Claiming 4,000 held seconds in a one-hour recording: implausible.
  const over = await aiProof(w, raceId, 'A', {
    value: 4000,
    durationMs: 3600_000,
    activityType: 'plank_hold',
    metric: 'seconds',
  });
  assert.equal(over.status, 400, over.text);
  // 55 minutes held inside a one-hour recording: honest, accepted.
  const honest = await aiProof(w, raceId, 'A', {
    value: 3300,
    durationMs: 3600_000,
    activityType: 'plank_hold',
    metric: 'seconds',
  });
  assert.equal(honest.status, 200, honest.text);
  assert.equal(w.progress(raceId, 'A'), 3300);
});

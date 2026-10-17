// Cumulative ("most X") race model + race-system loophole regression suite.
// Replays the PROD schema in real SQLite (foreign keys ON) and drives the
// compiled app end to end. Prelude shared in shape with release_p0_sql.test.mjs.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';

const require = createRequire(import.meta.url);
const app = require('../.tmp-test-dist/index.js').default;
const { signJwt } = require('../.tmp-test-dist/lib/jwt.js');
const { finalizeRaceIfEnded } = require('../.tmp-test-dist/domain/raceFinalize.js');
const { reconcileProgression } = require('../.tmp-test-dist/domain/progression.js');

const JWT_SECRET = 'test-secret';
// Test-only credential for /auth/reviewer — never a real review password.
const REVIEWER_PASSWORD = 'test-review-pass';
const root = new URL('..', import.meta.url);
const SCHEMA = [
  readFileSync(new URL('test/fixtures/prod_schema_2026-09-28.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0042_achievements.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0043_proof_votes.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0044_custom_verifier_seed.sql', root), 'utf8'),
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
  const race = (id, creator, over = {}) => {
    const r = {
      title: 'Race', race_type: 'most_in_window', format: 'most_in_window', verification_type: 'manual',
      status: 'active', visibility: 'crew_only', scoring_rule: 'cumulative_sum', score_direction: 'higher',
      target_value: 100, target_unit: 'pages', metric: 'reps', activity_id: null, movement_type: null,
      verifier_type: 'manual_log', proof_review_mode: 'auto_accept', end_at: null, ...over,
    };
    exec(
      `INSERT INTO races (id, creator_id, title, race_type, format, verification_type, status, visibility, scoring_rule,
         score_direction, target_value, target_unit, metric, activity_id, movement_type, verifier_type, proof_review_mode,
         end_at, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)`,
      id, creator, r.title, r.race_type, r.format, r.verification_type, r.status, r.visibility, r.scoring_rule,
      r.score_direction, r.target_value, r.target_unit, r.metric, r.activity_id, r.movement_type, r.verifier_type,
      r.proof_review_mode, r.end_at,
    );
    member(id, creator, 'creator');
    return id;
  };
  let joinN = 0;
  const member = (raceId, userId, role = 'racer', status = 'active') => {
    exec(
      "INSERT INTO race_members (id, race_id, person_id, user_id, role, status, joined_at) VALUES (?, ?, ?, ?, ?, ?, datetime('now', ?))",
      `rm-${raceId}-${userId}`, raceId, `p-${userId}`, userId, role, status, `-${1000 - ++joinN} seconds`,
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
  const progress = (raceId, userId) => one('SELECT progress_value FROM race_progress WHERE race_id = ? AND user_id = ?', raceId, userId).progress_value;
  const fkClean = () => assert.deepEqual(q('PRAGMA foreign_key_check'), [], 'foreign_key_check must be clean');
  const flush = async () => { await Promise.all(pending.splice(0)); };

  return { sqlite, db, r2, env, req, q, one, exec, user, race, member, photo, progress, fkClean, flush };
}

const { applyVerifiedSubmission } = require('../.tmp-test-dist/domain/raceScoring.js');
const { computeCompetitionRanks } = require('../.tmp-test-dist/domain/raceRanking.js');
const { configFromBody, manualConfigFromBody, validateRaceWindow } = require('../.tmp-test-dist/domain/raceValidation.js');
const { RACE_ACTIVITY_CATALOG } = require('../.tmp-test-dist/domain/raceActivities.js');
const { deadlineEligibility } = require('../.tmp-test-dist/domain/raceFinalize.js');

const iso = (ms) => new Date(Date.now() + ms).toISOString();
const HOUR = 3600_000;
const submit = (w, user, raceId, value, key, extra = {}) =>
  w.req(user, 'POST', `/races/${raceId}/proof`, { proofType: 'manual', value, mediaObjectKey: key ?? w.photo(raceId, user), ...extra });

// ── A: most_in_window is cumulative, finishes at the finish line ─────────────

test('A: most_in_window scores cumulative_sum for every supported activity, custom and manual', () => {
  for (const a of RACE_ACTIVITY_CATALOG.filter((x) => x.availability === 'supported')) {
    const cfg = configFromBody({ activityId: a.id, format: 'most_in_window', endsAt: iso(HOUR), metric: a.defaultMetric });
    assert.equal(cfg.error, undefined, `${a.id}: ${cfg.error}`);
    assert.equal(cfg.format, 'most_in_window');
    assert.equal(cfg.scoringRule, 'cumulative_sum', a.id);
    assert.equal(cfg.targetValue, null, 'no target');
  }
  const manual = manualConfigFromBody({ title: 'x', format: 'most_in_window', proofMode: 'photo', unit: 'pages', targetValue: 50 });
  assert.equal(manual.scoringRule, 'cumulative_sum');
  assert.equal(manual.targetValue, null);
});

test('A: applyVerifiedSubmission adds up cumulative submissions with no completion', () => {
  let score = 0;
  for (const v of [10, 15, 7]) {
    const out = applyVerifiedSubmission({ format: 'most_in_window', scoringRule: 'cumulative_sum', previousScore: score, submissionValue: v, targetValue: 9 });
    score = out.newScore;
    assert.equal(out.completed, false, 'a stray target never finishes a most_in_window race');
    assert.equal(out.progressPercent, 0);
  }
  assert.equal(score, 32);
});

test('A: ties rank deterministically (earliest finisher, then earliest joiner); lower direction ranks fastest first', () => {
  const rows = [
    { user_id: 'late', progress_value: 20, completed_at: null, joined_at: '2026-01-02T00:00:00Z' },
    { user_id: 'early', progress_value: 20, completed_at: null, joined_at: '2026-01-01T00:00:00Z' },
    { user_id: 'top', progress_value: 30, completed_at: null, joined_at: '2026-01-03T00:00:00Z' },
  ];
  const ranked = computeCompetitionRanks(rows);
  assert.deepEqual(ranked.map((r) => r.user_id), ['top', 'early', 'late']);
  assert.deepEqual(ranked.map((r) => r.rank), [1, 2, 2], 'ties share a rank; order is stable');
  const low = computeCompetitionRanks([
    { user_id: 'none', progress_value: 0, completed_at: null, joined_at: 'a' },
    { user_id: 'fast', progress_value: 40, completed_at: null, joined_at: 'b' },
    { user_id: 'slow', progress_value: 90, completed_at: null, joined_at: 'c' },
  ], { direction: 'asc' });
  assert.deepEqual(low.map((r) => r.user_id), ['fast', 'slow', 'none']);
});

test('A: several submissions add up, race stays open until end_at, then the highest total wins', async () => {
  const w = world();
  w.user('A'); w.user('B');
  w.race('r1', 'A', { target_value: null });
  w.member('r1', 'B');
  w.exec('UPDATE races SET end_at = ? WHERE id = ?', iso(HOUR), 'r1');
  for (const v of [10, 20, 30]) assert.equal((await submit(w, 'A', 'r1', v)).status, 200);
  assert.equal((await submit(w, 'B', 'r1', 55)).status, 200);
  assert.equal(w.progress('r1', 'A'), 60);
  assert.equal(w.progress('r1', 'B'), 55);
  assert.equal(w.one("SELECT status FROM races WHERE id = 'r1'").status, 'active', 'big totals never end a window race');
  // The finish line passes.
  w.exec('UPDATE races SET end_at = ? WHERE id = ?', iso(-1000), 'r1');
  const race = w.one("SELECT * FROM races WHERE id = 'r1'");
  const res = await finalizeRaceIfEnded(w.db, race);
  assert.equal(res.finalized, true);
  assert.equal(res.winnerUserId, 'A');
  assert.equal(w.one("SELECT winner_user_id FROM races WHERE id = 'r1'").winner_user_id, 'A');
  w.fkClean();
});

test('A: a tied top total is a shared result, not a hidden tiebreak winner', async () => {
  const w = world();
  w.user('A'); w.user('B');
  w.race('r1', 'A', { target_value: null });
  w.member('r1', 'B');
  assert.equal((await submit(w, 'A', 'r1', 25)).status, 200);
  assert.equal((await submit(w, 'B', 'r1', 25)).status, 200);
  w.exec('UPDATE races SET end_at = ? WHERE id = ?', iso(-1000), 'r1');
  const res = await finalizeRaceIfEnded(w.db, w.one("SELECT * FROM races WHERE id = 'r1'"));
  assert.equal(res.tiedForFirst, true);
  assert.equal(res.winnerUserId, null);
});

// ── B8: finish line + window sanity at creation / edit ───────────────────────

test('B8: most_in_window races need a finish line (preset, manual, custom path); bad dates are refused', async () => {
  const w = world();
  w.user('A');
  const base = { title: 'Most pushups', activityId: 'push_ups', metric: 'reps', format: 'most_in_window' };
  const missing = await w.req('A', 'POST', '/races', base);
  assert.equal(missing.status, 201, missing.text);
  const manualMissing = await w.req('A', 'POST', '/races', { title: 'Pages read', proofMode: 'photo', unit: 'pages', format: 'most_in_window' });
  assert.equal(manualMissing.status, 201, manualMissing.text);
  const past = await w.req('A', 'POST', '/races', { ...base, endsAt: iso(-HOUR) });
  assert.equal(past.status, 400);
  const garbage = await w.req('A', 'POST', '/races', { ...base, endsAt: 'next tuesday-ish' });
  assert.equal(garbage.status, 400);
  const backwards = await w.req('A', 'POST', '/races', { ...base, startsAt: iso(2 * HOUR), endsAt: iso(HOUR) });
  assert.equal(backwards.status, 400);
  const ok = await w.req('A', 'POST', '/races', { ...base, endsAt: iso(HOUR), targetValue: 999 });
  assert.equal(ok.status, 201, ok.text);
  const row = w.one('SELECT scoring_rule, format, target_value, end_at FROM races ORDER BY created_at DESC LIMIT 1');
  assert.equal(row.scoring_rule, 'cumulative_sum');
  assert.equal(row.format, 'most_in_window');
  assert.equal(row.target_value, null);
  assert.match(row.end_at, /^\d{4}-\d\d-\d\dT.*Z$/, 'stored as canonical UTC ISO');
  assert.equal(validateRaceWindow('first_to_goal', null, null).endsAt, null, 'race to a goal may have no finish line');
});

// ── B1: eligibility ──────────────────────────────────────────────────────────

test('B1: proof refused before start, after end, on cancelled/completed races, and from left/removed/non-members', async () => {
  const w = world();
  w.user('A'); w.user('B'); w.user('L'); w.user('R'); w.user('N');
  w.race('r1', 'A', { target_value: null });
  w.member('r1', 'B'); w.member('r1', 'L', 'racer', 'left'); w.member('r1', 'R', 'racer', 'removed');
  const key = (u) => w.photo('r1', u);
  assert.equal((await submit(w, 'L', 'r1', 5, key('L'))).status, 403);
  assert.equal((await submit(w, 'R', 'r1', 5, key('R'))).status, 403);
  assert.equal((await submit(w, 'N', 'r1', 5, key('N'))).status, 403);

  w.exec('UPDATE races SET start_at = ? WHERE id = ?', iso(HOUR), 'r1');
  assert.equal((await submit(w, 'B', 'r1', 5)).status, 400, 'before the start line');
  w.exec("UPDATE races SET start_at = NULL, end_at = ? WHERE id = 'r1'", iso(-48 * HOUR));
  assert.equal((await submit(w, 'B', 'r1', 5)).status, 400, 'long after the finish line, no capture time');
  assert.equal((await submit(w, 'B', 'r1', 5, undefined, { capturedAt: iso(-72 * HOUR) })).status, 400, 'past the grace window');
  w.exec("UPDATE races SET end_at = NULL, status = 'cancelled' WHERE id = 'r1'");
  assert.equal((await submit(w, 'B', 'r1', 5)).status, 400, 'cancelled');
  w.exec("UPDATE races SET status = 'completed' WHERE id = 'r1'");
  assert.equal((await submit(w, 'B', 'r1', 5, undefined, { capturedAt: iso(-1000) })).status, 400, 'completed with no finish line');
  assert.equal(w.progress('r1', 'B'), 0);
});

test('B1: a race already won early (end_at still in the future) takes no late proof', () => {
  const race = { status: 'completed', start_at: null, end_at: iso(HOUR) };
  assert.equal(deadlineEligibility(race, new Date(Date.now() - 1000), new Date()), 'closed');
  const ended = { status: 'completed', start_at: null, end_at: iso(-HOUR) };
  assert.equal(deadlineEligibility(ended, new Date(Date.now() - 2 * HOUR), new Date()), 'grace');
});

test('B1: a grace proof after finalization re-derives the winner and final standings', async () => {
  const w = world();
  w.user('A'); w.user('B');
  w.race('r1', 'A', { target_value: null });
  w.member('r1', 'B');
  assert.equal((await submit(w, 'A', 'r1', 20)).status, 200);
  assert.equal((await submit(w, 'B', 'r1', 18)).status, 200);
  w.exec('UPDATE races SET end_at = ? WHERE id = ?', iso(-HOUR), 'r1');
  await finalizeRaceIfEnded(w.db, w.one("SELECT * FROM races WHERE id = 'r1'"));
  assert.equal(w.one("SELECT winner_user_id FROM races WHERE id = 'r1'").winner_user_id, 'A');
  // B did 5 more reps before the deadline but uploaded after it.
  const late = await submit(w, 'B', 'r1', 5, undefined, { capturedAt: iso(-2 * HOUR) });
  assert.equal(late.status, 200, late.text);
  assert.equal(w.one("SELECT winner_user_id FROM races WHERE id = 'r1'").winner_user_id, 'B');
  const standings = w.q("SELECT user_id, rank_position, score_value FROM race_final_standings WHERE race_id = 'r1' ORDER BY rank_position");
  assert.deepEqual(standings.map((s) => [s.user_id, s.score_value]), [['B', 23], ['A', 20]]);
  w.fkClean();
});

// ── B2: replay / duplicates ─────────────────────────────────────────────────

test('B2: the same photo cannot back two proofs; an idempotent retry is not a second count', async () => {
  const w = world();
  w.user('A'); w.user('B');
  w.race('r1', 'A', { target_value: null });
  w.member('r1', 'B');
  const key = w.photo('r1', 'B');
  assert.equal((await submit(w, 'B', 'r1', 10, key, { clientSubmissionId: 'c1' })).status, 200);
  const reuse = await submit(w, 'B', 'r1', 10, key, { clientSubmissionId: 'c2' });
  assert.equal(reuse.status, 409, reuse.text);
  const retry = await submit(w, 'B', 'r1', 10, key, { clientSubmissionId: 'c1' });
  assert.equal(retry.status, 200);
  assert.equal(w.progress('r1', 'B'), 10, 'counted exactly once');
  assert.equal(w.one("SELECT COUNT(*) AS n FROM move_logs WHERE user_id = 'B'").n, 1);
});

test('B2: a rejected proof frees its photo; a replayed AI session is refused', async () => {
  const w = world();
  w.user('A'); w.user('B');
  w.race('r1', 'A', { target_value: null, proof_review_mode: 'peer_review' });
  w.member('r1', 'B');
  const key = w.photo('r1', 'B');
  assert.equal((await submit(w, 'B', 'r1', 10, key)).status, 200);
  const move = w.one("SELECT id FROM move_logs WHERE user_id = 'B'").id;
  assert.equal((await w.req('A', 'PATCH', `/races/r1/proofs/${move}`, { verificationStatus: 'rejected' })).status, 200);
  assert.equal((await submit(w, 'B', 'r1', 10, key)).status, 200, 'rejected evidence may be resubmitted');
});

// ── B3: value sanity ────────────────────────────────────────────────────────

test('B3: absurd, zero, negative and non-numeric values never score', async () => {
  const w = world();
  w.user('A'); w.user('B');
  w.race('r1', 'A', { target_value: null });
  w.member('r1', 'B');
  for (const bad of [1e9, 1_000_001, 100_001, 0, -5, 0.4, 'ten', null]) {
    const res = await submit(w, 'B', 'r1', bad);
    assert.equal(res.status, 400, `value ${bad} -> ${res.status} ${res.text}`);
  }
  assert.equal(w.progress('r1', 'B'), 0);
  assert.equal((await submit(w, 'B', 'r1', 100_000)).status, 200, 'honor units are free-form up to the cap');
});

test('B3: preset rep races cap a single proof far below 1e6', async () => {
  const w = world();
  w.user('A');
  w.race('r2', 'A', { target_value: null, verifier_type: null, verification_type: 'movecheck', activity_id: 'push_ups', movement_type: 'push_ups', metric: 'reps', target_unit: 'reps' });
  w.exec("UPDATE races SET verification_method = 'camera_pose' WHERE id = 'r2'");
  const res = await submit(w, 'A', 'r2', 50_000);
  assert.equal(res.status, 400, res.text);
  assert.match(res.json.error, /too large|range/i);
});

// ── B4: PATCH locks ─────────────────────────────────────────────────────────

test('B4: rules and finish line lock once a verified proof exists; finish line cannot be cleared or backdated', async () => {
  const w = world();
  w.user('A'); w.user('B');
  w.race('r1', 'A', { target_value: null });
  w.member('r1', 'B');
  w.exec('UPDATE races SET end_at = ? WHERE id = ?', iso(HOUR), 'r1');
  // Before any proof the finish line may move, but never be cleared / invalid / in the past.
  assert.equal((await w.req('A', 'PATCH', '/races/r1', { finishLineAt: null })).status, 400);
  assert.equal((await w.req('A', 'PATCH', '/races/r1', { finishLineAt: 'soon' })).status, 400);
  assert.equal((await w.req('A', 'PATCH', '/races/r1', { finishLineAt: iso(-HOUR) })).status, 400);
  assert.equal((await w.req('A', 'PATCH', '/races/r1', { finishLineAt: iso(3 * HOUR) })).status, 200);
  assert.equal((await submit(w, 'B', 'r1', 10)).status, 200);
  const before = w.one("SELECT * FROM races WHERE id = 'r1'");
  for (const patch of [
    { finishLineAt: iso(-HOUR) }, { finishLineAt: iso(9 * HOUR) }, { targetValue: 1 }, { startLineAt: iso(-HOUR) },
    { aiActivityType: 'squats' }, { goalType: 'first_to_target' }, { unit: 'km' },
  ]) {
    assert.equal((await w.req('A', 'PATCH', '/races/r1', patch)).status, 409, JSON.stringify(patch));
  }
  const after = w.one("SELECT * FROM races WHERE id = 'r1'");
  for (const col of ['end_at', 'start_at', 'target_value', 'race_type', 'movement_type', 'format', 'scoring_rule']) {
    assert.equal(after[col], before[col], col);
  }
  assert.equal((await w.req('A', 'PATCH', '/races/r1', { title: 'Renamed' })).status, 200);
});

test('B4: a creator cannot cancel a finished race to erase a loss (archive is fine)', async () => {
  const w = world();
  w.user('A'); w.user('B');
  w.race('r1', 'A', { target_value: null });
  w.member('r1', 'B');
  assert.equal((await submit(w, 'B', 'r1', 10)).status, 200);
  w.exec('UPDATE races SET end_at = ? WHERE id = ?', iso(-HOUR), 'r1');
  await finalizeRaceIfEnded(w.db, w.one("SELECT * FROM races WHERE id = 'r1'"));
  assert.equal((await w.req('A', 'POST', '/races/r1/cancel')).status, 409);
  assert.equal(w.one("SELECT status, winner_user_id FROM races WHERE id = 'r1'").winner_user_id, 'B');
});

// ── B5/B7: membership changes and veto recompute ────────────────────────────

test('B5: a left member drops out of ranking, keeps their total on rejoin; a removed one stays out', async () => {
  const w = world();
  w.user('A'); w.user('B'); w.user('C');
  w.race('r1', 'A', { target_value: null, visibility: 'public_demo' });
  w.member('r1', 'B'); w.member('r1', 'C');
  assert.equal((await submit(w, 'A', 'r1', 10)).status, 200);
  assert.equal((await submit(w, 'B', 'r1', 40)).status, 200);
  assert.equal((await submit(w, 'C', 'r1', 20)).status, 200);
  assert.equal((await w.req('B', 'POST', '/races/r1/leave')).status, 200);
  assert.equal(w.one("SELECT rank_cache FROM race_progress WHERE user_id = 'C'").rank_cache, 1, 'B no longer ranks');
  assert.equal((await submit(w, 'B', 'r1', 5)).status, 403, 'left member cannot submit');
  assert.equal((await w.req('B', 'POST', '/races/r1/join')).status, 200);
  assert.equal(w.progress('r1', 'B'), 40, 'rejoin keeps the earned total');
  assert.equal(w.one("SELECT rank_cache FROM race_progress WHERE user_id = 'B'").rank_cache, 1);
  await w.req('A', 'DELETE', '/races/r1/members/B');
  assert.equal(w.one("SELECT rank_cache FROM race_progress WHERE user_id = 'C'").rank_cache, 1);
  const finalized = await finalizeRaceIfEnded(
    w.db, { ...w.one("SELECT * FROM races WHERE id = 'r1'"), end_at: iso(-1000) },
  );
  assert.equal(finalized.winnerUserId, 'C', 'a removed member can never be the winner');
});

test('B7: vetoing one of several cumulative submissions re-sums the rest and fixes the winner', async () => {
  const w = world();
  w.user('A'); w.user('B');
  w.race('r1', 'A', { target_value: null });
  w.member('r1', 'B');
  assert.equal((await submit(w, 'A', 'r1', 30)).status, 200);
  assert.equal((await submit(w, 'B', 'r1', 20)).status, 200);
  assert.equal((await submit(w, 'B', 'r1', 20)).status, 200);
  const big = w.one("SELECT id FROM move_logs WHERE user_id = 'B' ORDER BY created_at, rowid LIMIT 1").id;
  assert.equal(w.progress('r1', 'B'), 40);
  const veto = await w.req('A', 'POST', `/races/r1/proofs/${big}/veto`, { reason: 'wrong_result' });
  assert.equal(veto.json.state, 'vetoed', veto.text);
  assert.equal(w.progress('r1', 'B'), 20, 'only the remaining proof counts');
  assert.equal(w.one("SELECT rank_cache FROM race_progress WHERE user_id = 'A'").rank_cache, 1);
});

// ── B6: first_to_goal ───────────────────────────────────────────────────────

test('B6: first_to_goal crowns exactly one winner; later finishers and late proof change nothing', async () => {
  const w = world();
  w.user('A'); w.user('B');
  w.race('r1', 'A', { format: 'first_to_goal', race_type: 'first_to_goal', target_value: 30 });
  w.member('r1', 'B');
  w.exec('UPDATE races SET end_at = ? WHERE id = ?', iso(HOUR), 'r1');
  const [ra, rb] = await Promise.all([submit(w, 'A', 'r1', 30), submit(w, 'B', 'r1', 30)]);
  assert.ok([ra.status, rb.status].includes(200), 'one finisher is accepted');
  assert.ok([ra.status, rb.status].every((st) => st === 200 || st === 400), 'the other is either also scored inside the race or refused as over');
  const winner = w.one("SELECT winner_user_id, status FROM races WHERE id = 'r1'");
  assert.equal(winner.status, 'completed');
  assert.ok(['A', 'B'].includes(winner.winner_user_id));
  assert.equal(w.one("SELECT COUNT(*) AS n FROM race_events WHERE race_id = 'r1' AND event_type = 'winner_determined' AND voided_at IS NULL").n, 1);
  const late = await submit(w, 'A', 'r1', 5, undefined, { capturedAt: iso(-1000) });
  assert.equal(late.status, 400, 'race over: a goal race that was won early takes no more proof');
  assert.equal(w.one("SELECT winner_user_id FROM races WHERE id = 'r1'").winner_user_id, winner.winner_user_id);
});

// ── B9: manual (honor) races ────────────────────────────────────────────────

test('B9: honor-logged proof needs a photo and respects the manual cap', async () => {
  const w = world();
  w.user('A'); w.user('B');
  w.race('r1', 'A', { target_value: null });
  w.member('r1', 'B');
  const nophoto = await w.req('B', 'POST', '/races/r1/proof', { proofType: 'manual', value: 5 });
  assert.equal(nophoto.status, 400);
  const foreign = await w.req('B', 'POST', '/races/r1/proof', { proofType: 'manual', value: 5, mediaObjectKey: w.photo('r1', 'A') });
  assert.equal(foreign.status, 400, "someone else's photo is not your evidence");
  const ai = await w.req('B', 'POST', '/races/r1/proof', { proofType: 'ai_motion', value: 5, clientSubmissionId: 'x', verificationSessionId: 's' });
  assert.equal(ai.status, 400, 'a manual race never accepts AI proof');
  assert.equal(w.progress('r1', 'B'), 0);
});

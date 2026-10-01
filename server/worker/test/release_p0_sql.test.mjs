// Release P0 regression suite against REAL SQLite semantics.
//
// Every other Worker suite uses a hand-written fake D1, which cannot see
// foreign keys, NOT NULL, or schema drift. This suite replays the captured
// PROD schema (test/fixtures/prod_schema_2026-09-28.sql) plus the pending
// migrations 0042/0043, turns foreign keys ON (D1 enforces them), and drives
// the compiled Hono app end to end. Each test ends with PRAGMA
// foreign_key_check.
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

// ── P0-1: testing@ is the canonical reviewer identity ────────────────────────

test('P0-1: testing@ reviewer credential is server-validated; email sign-in seeds no races', async () => {
  const w = world();
  // Wrong password is a real rejection — never a silent success.
  const wrong = await w.req(null, 'POST', '/auth/reviewer', { email: 'testing@getnuvo.net', password: 'anything' });
  assert.equal(wrong.status, 401);
  // The retired team@ alias must NOT authenticate even with the right
  // credential — the reviewer identity is testing@ only.
  const retired = await w.req(null, 'POST', '/auth/reviewer', { email: 'team@getnuvo.net', password: REVIEWER_PASSWORD });
  assert.equal(retired.status, 401);
  // Right credential on the canonical identity authenticates. The true
  // first-time reset leaves the account in a just-created shape — onboarding
  // incomplete, real (non-demo) data world — so the client walks the genuine
  // setup path every run.
  const ok = await w.req(null, 'POST', '/auth/reviewer', { email: 'testing@getnuvo.net', password: REVIEWER_PASSWORD });
  assert.equal(ok.status, 200, ok.text);
  assert.equal(ok.json.user.isDemo, false);
  assert.equal(ok.json.user.onboardingComplete, false);
  assert.equal(ok.json.user.email, 'testing@getnuvo.net');

  const hash = createHash('sha256').update('123456').digest('hex');
  w.exec(
    "INSERT INTO email_codes (id, email, code_hash, attempts, expires_at, created_at) VALUES ('c1', 'testing@getnuvo.net', ?, 0, '2999-01-01T00:00:00.000Z', CURRENT_TIMESTAMP)",
    hash,
  );
  w.user('someone-real');
  const res = await w.req(null, 'POST', '/auth/email/verify', { email: 'testing@getnuvo.net', code: '123456' });
  assert.equal(res.status, 200, res.text);
  // Same account — the email path resolves to the reviewer-created user, it
  // does not fork a second identity or seed anything.
  assert.equal(res.json.user.isDemo, false);
  assert.equal(res.json.user.id, ok.json.user.id);
  assert.equal(w.one('SELECT COUNT(*) AS n FROM races').n, 0, 'no demo races seeded');
  assert.equal(w.one('SELECT COUNT(*) AS n FROM race_members').n, 0, 'no real user pulled into anything');
  w.fkClean();
});

// ── P0-1b: /auth/email/start resend throttle ─────────────────────────────────

test('P0-1b: email/start throttles repeat sends with a same-shape response', async () => {
  const w = world();
  const count = () => w.one("SELECT COUNT(*) AS n FROM email_codes WHERE email = 'member@example.com'").n;

  const first = await w.req(null, 'POST', '/auth/email/start', { email: 'member@example.com' });
  assert.equal(first.status, 200);
  assert.equal(first.json.ok, true);
  assert.equal(count(), 1);

  // Repeat inside the window: identical response, no second code issued.
  const again = await w.req(null, 'POST', '/auth/email/start', { email: 'member@example.com' });
  assert.equal(again.status, 200);
  assert.deepEqual(again.json, first.json);
  assert.equal(count(), 1, 'throttled resend must not issue another code');

  // Once the newest code ages past the window a fresh send is allowed.
  w.exec("UPDATE email_codes SET created_at = datetime('now', '-2 minutes') WHERE email = 'member@example.com'");
  const later = await w.req(null, 'POST', '/auth/email/start', { email: 'member@example.com' });
  assert.equal(later.status, 200);
  assert.equal(count(), 2);
  w.fkClean();
});

// ── P0-2: /move-log is retired ───────────────────────────────────────────────

test('P0-2: /move-log cannot change race truth for any source/status/member', async () => {
  const w = world();
  w.user('A'); w.user('B'); w.user('X');
  const r = w.race('r1', 'A');
  w.member(r, 'B');
  for (const [sub, body] of [
    ['A', { source: 'manual', value: 10 }],
    ['A', { source: 'demo', value: 5000 }],
    ['A', { source: 'import', value: 5000 }],
    ['A', { source: 'movecheck', value: 5000, status: 'verified' }],
    ['B', { value: 1e6, status: 'verified' }],
    ['X', { source: 'demo', value: 5 }],
  ]) {
    const res = await w.req(sub, 'POST', `/races/${r}/move-log`, body);
    assert.equal(res.status, 410, `${sub} ${JSON.stringify(body)}`);
  }
  assert.equal(w.one('SELECT COUNT(*) AS n FROM move_logs').n, 0);
  assert.equal(w.progress(r, 'A'), 0);
  assert.equal(w.one("SELECT COUNT(*) AS n FROM race_members WHERE user_id = 'X'").n, 0, 'no auto-join');
  w.fkClean();
});

// ── P0-3: /proof contract ────────────────────────────────────────────────────

test('P0-3: photo race rejects fake AI proof, missing photo, and out-of-range values', async () => {
  const w = world();
  w.user('A'); w.user('B'); w.user('X');
  const r = w.race('r1', 'A');
  w.member(r, 'B');

  const fakeAi = await w.req('A', 'POST', `/races/${r}/proof`, {
    proofType: 'ai_motion', value: 100, clientSubmissionId: 'cs1', verificationStatus: 'ai_verified',
  });
  assert.equal(fakeAi.status, 400, fakeAi.text);
  const noPhoto = await w.req('A', 'POST', `/races/${r}/proof`, { proofType: 'manual', value: 10 });
  assert.equal(noPhoto.status, 400);
  const key = w.photo(r, 'A');
  const huge = await w.req('A', 'POST', `/races/${r}/proof`, null, `{"proofType":"manual","value":1e309,"mediaObjectKey":"${key}"}`);
  assert.equal(huge.status, 400, 'Infinity rejected');
  const big = await w.req('A', 'POST', `/races/${r}/proof`, { proofType: 'manual', value: 1_000_001, mediaObjectKey: key });
  assert.equal(big.status, 400);
  const neg = await w.req('A', 'POST', `/races/${r}/proof`, { proofType: 'manual', value: -5, mediaObjectKey: key });
  assert.equal(neg.status, 400);
  const stranger = await w.req('X', 'POST', `/races/${r}/proof`, { proofType: 'manual', value: 5, mediaObjectKey: key });
  assert.equal(stranger.status, 403);
  assert.equal(w.one('SELECT COUNT(*) AS n FROM move_logs').n, 0, 'nothing written by rejected proofs');

  const ok = await w.req('A', 'POST', `/races/${r}/proof`, { proofType: 'manual', value: 40, mediaObjectKey: key });
  assert.equal(ok.status, 200, ok.text);
  assert.equal(w.progress(r, 'A'), 40);
  const move = w.one("SELECT id FROM move_logs WHERE user_id = 'A'");
  assert.ok(w.one("SELECT id FROM race_events WHERE event_type = 'progress_accepted' AND move_log_id = ?", move.id));
  await w.flush();
  w.fkClean();
});

function motionWorld() {
  const w = world();
  w.exec(
    `INSERT INTO motion_activities (id, display_name, category, proof_label, measurement_type, metric,
       suggested_targets_json, supported_formats_json, icon_key)
     VALUES ('push_ups', 'Pushups', 'strength', 'reps', 'repetitions', 'reps', '[]', '[]', 'x')`,
  );
  const cols = w.q("SELECT name, \"notnull\" AS nn, dflt_value AS d FROM pragma_table_info('verifier_releases')");
  const values = { id: 'rel1', activity_id: 'push_ups', semver: '1.0.0', change_class: 'major', engine_type: 'phase_machine', spec_schema_version: 1, spec_json: '{}', checksum: 'sum1', required_capabilities_json: '[]', minimum_app_build: '1', compatibility_group: 'g1', status: 'stable' };
  const use = cols.filter((c) => values[c.name] !== undefined);
  w.exec(`INSERT INTO verifier_releases (${use.map((c) => c.name).join(', ')}) VALUES (${use.map(() => '?').join(', ')})`, ...use.map((c) => values[c.name]));
  w.user('A'); w.user('B');
  const r = w.race('m1', 'A', {
    verification_type: 'movecheck', verifier_type: null, activity_id: 'push_ups', movement_type: 'push_ups',
    target_unit: 'reps', metric: 'reps', target_value: 100,
  });
  w.member(r, 'B');
  const session = (id, userId, raceId, status, value) => w.exec(
    `INSERT INTO verification_sessions (id, race_id, user_id, activity_id, release_id, release_checksum, spec_schema_version,
       engine_type, app_version, app_build, runtime_capabilities_json, status, result_value)
     VALUES (?, ?, ?, 'push_ups', 'rel1', 'sum1', 1, 'phase_machine', 'v', '1', '[]', ?, ?)`,
    id, raceId, userId, status, value,
  );
  const ai = (sub, extra) => w.req(sub, 'POST', `/races/${r}/proof`, {
    proofType: 'ai_motion', activityType: 'push_ups', metric: 'reps', verificationStatus: 'ai_verified', ...extra,
  });
  return { w, r, session, ai };
}

test('P0-3: motion race binds AI proof to a real, owned, completed verification session', async () => {
  const { w, r, session, ai } = motionWorld();
  w.race('other', 'B');
  session('vs-ok', 'A', r, 'completed', 20);
  session('vs-b', 'B', r, 'completed', 20);
  session('vs-other-race', 'A', 'other', 'completed', 20);
  session('vs-running', 'A', r, 'running', null);

  assert.equal((await ai('A', { value: 10, clientSubmissionId: 'a1', verificationSessionId: 'vs-fabricated' })).status, 400);
  assert.equal((await ai('A', { value: 10, clientSubmissionId: 'a2', verificationSessionId: 'vs-b' })).status, 400, 'another user’s session');
  assert.equal((await ai('A', { value: 10, clientSubmissionId: 'a3', verificationSessionId: 'vs-other-race' })).status, 400, 'another race’s session');
  assert.equal((await ai('A', { value: 10, clientSubmissionId: 'a4', verificationSessionId: 'vs-running' })).status, 400, 'unfinished session');
  assert.equal((await ai('A', { value: 25, clientSubmissionId: 'a5', verificationSessionId: 'vs-ok' })).status, 400, 'claims more than verified');
  assert.equal(w.progress(r, 'A'), 0);

  const ok = await ai('A', { value: 20, clientSubmissionId: 'a6', verificationSessionId: 'vs-ok' });
  assert.equal(ok.status, 200, ok.text);
  assert.equal(w.progress(r, 'A'), 20);
  const replay = await ai('A', { value: 20, clientSubmissionId: 'a7', verificationSessionId: 'vs-ok' });
  assert.equal(replay.status, 409, 'one session backs one proof');
  const retry = await ai('A', { value: 20, clientSubmissionId: 'a6', verificationSessionId: 'vs-ok' });
  assert.equal(retry.status, 200, 'same clientSubmissionId is an idempotent replay');
  assert.equal(w.progress(r, 'A'), 20);
  await w.flush();
  w.fkClean();
});

// ── P0-4: creator cannot override race truth ─────────────────────────────────

test('P0-4: creator cannot set progress, rewrite status, re-accept a veto, or reject counted rival proof', async () => {
  const w = world();
  w.user('A'); w.user('B'); w.user('Z');
  const r = w.race('r1', 'A');
  w.member(r, 'B');
  w.exec("INSERT INTO blocked_users (id, user_id, blocked_user_id) VALUES ('bl1', 'Z', 'A')");

  const setProgress = await w.req('A', 'PATCH', `/races/${r}/progress/A`, { progressValue: 100 });
  assert.equal(setProgress.status, 410);
  const addBlocked = await w.req('A', 'PATCH', `/races/${r}/progress/Z`, { progressValue: 1 });
  assert.equal(addBlocked.status, 410);
  assert.equal(w.one("SELECT COUNT(*) AS n FROM race_members WHERE user_id = 'Z'").n, 0, 'blocked user never added');

  // A (creator) and B each score with photos.
  const aKey = w.photo(r, 'A');
  const bKey = w.photo(r, 'B');
  assert.equal((await w.req('A', 'POST', `/races/${r}/proof`, { proofType: 'manual', value: 60, mediaObjectKey: aKey })).status, 200);
  assert.equal((await w.req('B', 'POST', `/races/${r}/proof`, { proofType: 'manual', value: 50, mediaObjectKey: bKey })).status, 200);
  const aMove = w.one("SELECT id FROM move_logs WHERE user_id = 'A'").id;
  const bMove = w.one("SELECT id FROM move_logs WHERE user_id = 'B'").id;

  // 1v1: B's single veto is consensus → A's proof stops counting.
  const veto = await w.req('B', 'POST', `/races/${r}/proofs/${aMove}/veto`, { reason: 'wrong_result' });
  assert.equal(veto.status, 200, veto.text);
  assert.equal(veto.json.state, 'vetoed');
  assert.equal(w.progress(r, 'A'), 0);

  const reaccept = await w.req('A', 'PATCH', `/races/${r}/proofs/${aMove}`, { verificationStatus: 'accepted' });
  assert.equal(reaccept.status, 409, 'vetoed proof stays vetoed');
  assert.equal(w.progress(r, 'A'), 0);
  assert.equal(w.one('SELECT status FROM move_logs WHERE id = ?', aMove).status, 'rejected');

  const rejectRival = await w.req('A', 'PATCH', `/races/${r}/proofs/${bMove}`, { verificationStatus: 'rejected' });
  assert.equal(rejectRival.status, 409, 'counted proof is disputed through veto, not creator fiat');
  assert.equal(w.progress(r, 'B'), 50);

  for (const status of ['completed', 'active', 'draft', 'scheduled']) {
    const res = await w.req('A', 'PATCH', `/races/${r}`, { status });
    if (status === 'active') assert.equal(res.status, 200, 'same status is a no-op');
    else assert.equal(res.status, 409, `status ${status}`);
  }
  assert.equal(w.one('SELECT status, winner_user_id FROM races WHERE id = ?', r).status, 'active');

  w.exec("UPDATE races SET status = 'completed', winner_user_id = 'B' WHERE id = ?", r);
  assert.equal((await w.req('A', 'PATCH', `/races/${r}`, { status: 'active' })).status, 409, 'cannot reopen');
  assert.equal((await w.req('A', 'PATCH', `/races/${r}`, { status: 'cancelled' })).status, 200, 'withdrawing is allowed');
  await w.flush();
  w.fkClean();
});

test('P0-4: peer-review still works for held photo proof, but never for your own', async () => {
  const w = world();
  w.user('A'); w.user('B');
  const r = w.race('r1', 'A', { proof_review_mode: 'peer_review' });
  w.member(r, 'B');
  const bKey = w.photo(r, 'B');
  const aKey = w.photo(r, 'A');
  assert.equal((await w.req('B', 'POST', `/races/${r}/proof`, { proofType: 'manual', value: 30, mediaObjectKey: bKey })).status, 200);
  assert.equal((await w.req('A', 'POST', `/races/${r}/proof`, { proofType: 'manual', value: 99, mediaObjectKey: aKey })).status, 200);
  assert.equal(w.progress(r, 'B'), 0, 'held until reviewed');
  const bMove = w.one("SELECT id FROM move_logs WHERE user_id = 'B'").id;
  const aMove = w.one("SELECT id FROM move_logs WHERE user_id = 'A'").id;

  assert.equal((await w.req('A', 'PATCH', `/races/${r}/proofs/${aMove}`, { verificationStatus: 'accepted' })).status, 403, 'no self-review');
  assert.equal(w.progress(r, 'A'), 0);
  const accept = await w.req('A', 'PATCH', `/races/${r}/proofs/${bMove}`, { verificationStatus: 'accepted' });
  assert.equal(accept.status, 200, accept.text);
  assert.equal(w.progress(r, 'B'), 30);
  await w.flush();
  w.fkClean();
});

// ── P0-7: lower-wins standings ───────────────────────────────────────────────

test('P0-7: golf — veto of the winning proof re-ranks standings lower-is-better everywhere', async () => {
  const w = world();
  w.user('A'); w.user('B');
  const r = w.race('golf', 'A', {
    title: 'Golf', score_direction: 'lower', scoring_rule: 'minimum_attempt', target_value: 200, target_unit: 'strokes',
    end_at: '2999-01-01T00:00:00.000Z',
  });
  w.member(r, 'B');
  for (const [u, v] of [['A', 90], ['A', 78], ['B', 82]]) {
    const res = await w.req(u, 'POST', `/races/${r}/proof`, { proofType: 'manual', value: v, mediaObjectKey: w.photo(r, u) });
    assert.equal(res.status, 200, res.text);
  }
  assert.equal(w.progress(r, 'A'), 78);

  // The deadline passes → canonical finalization.
  w.exec("UPDATE races SET end_at = '2000-01-01T00:00:00.000Z' WHERE id = ?", r);
  const row = w.one('SELECT * FROM races WHERE id = ?', r);
  const fin = await finalizeRaceIfEnded(w.db, row);
  assert.equal(fin.winnerUserId, 'A');
  assert.deepEqual(w.q('SELECT user_id, rank_position FROM race_final_standings WHERE race_id = ? ORDER BY rank_position', r),
    [{ user_id: 'A', rank_position: 1 }, { user_id: 'B', rank_position: 2 }]);

  // B vetoes A's 78 → A's best valid round is 90, B's 82 now wins.
  const move78 = w.one("SELECT id FROM move_logs WHERE user_id = 'A' AND value = 78").id;
  const veto = await w.req('B', 'POST', `/races/${r}/proofs/${move78}/veto`, { reason: 'wrong_result' });
  assert.equal(veto.status, 200, veto.text);
  await w.flush();

  assert.equal(w.progress(r, 'A'), 90);
  assert.equal(w.one('SELECT winner_user_id FROM races WHERE id = ?', r).winner_user_id, 'B');
  assert.deepEqual(w.q('SELECT user_id, rank_position, score_value FROM race_final_standings WHERE race_id = ? ORDER BY rank_position', r),
    [{ user_id: 'B', rank_position: 1, score_value: 82 }, { user_id: 'A', rank_position: 2, score_value: 90 }]);
  const liveWinners = w.q("SELECT subject_user_id FROM race_events WHERE race_id = ? AND event_type = 'winner_determined' AND voided_at IS NULL", r);
  assert.deepEqual(liveWinners, [{ subject_user_id: 'B' }]);

  const view = await w.req('B', 'GET', `/races/${r}`);
  assert.equal(view.status, 200, view.text);
  assert.deepEqual(view.json.race.finalStandings.map((s) => [s.userId, s.rank]), [['B', 1], ['A', 2]]);

  await reconcileProgression(w.db, 'A');
  await reconcileProgression(w.db, 'B');
  assert.equal(w.one("SELECT COUNT(*) AS n FROM xp_events WHERE source_type = 'winner_determined' AND user_id = 'A'").n, 0);
  assert.equal(w.one("SELECT COUNT(*) AS n FROM xp_events WHERE source_type = 'winner_determined' AND user_id = 'B'").n, 1);
  w.fkClean();
});

// ── P0-5: account deletion on real foreign keys ──────────────────────────────

test('P0-5: hard delete succeeds first try with attempts, PBs, votes, XP, and shared-race photo proof', async () => {
  const w = world();
  w.user('U'); w.user('V'); w.user('W');

  // Solo race U created; V raced, voted, then left.
  const solo = w.race('solo', 'U', { format: 'best_attempt', race_type: 'best_attempt', scoring_rule: 'maximum_attempt' });
  w.member(solo, 'V', 'racer', 'left');
  const soloKey = w.photo(solo, 'U');
  const vKey = w.photo(solo, 'V');
  w.exec("INSERT INTO move_logs (id, race_id, user_id, source, value, status, media_object_key) VALUES ('m-u', 'solo', 'U', 'manual', 12, 'verified', ?)", soloKey);
  w.exec("INSERT INTO move_logs (id, race_id, user_id, source, value, status, media_object_key) VALUES ('m-v', 'solo', 'V', 'manual', 9, 'verified', ?)", vKey);
  w.exec("INSERT INTO race_attempts (id, race_id, user_id, attempt_index, status, move_log_id) VALUES ('at-u', 'solo', 'U', 1, 'submitted', 'm-u')");
  w.exec("INSERT INTO personal_bests (id, user_id, activity_id, metric, best_value, race_id, move_log_id) VALUES ('pb-u', 'U', 'manual:pages', 'reps', 12, 'solo', 'm-u')");
  w.exec("INSERT INTO personal_bests (id, user_id, activity_id, metric, best_value, race_id, move_log_id) VALUES ('pb-v', 'V', 'manual:pages', 'reps', 9, 'solo', 'm-v')");
  w.exec("INSERT INTO proof_votes (id, move_log_id, race_id, voter_user_id, reason) VALUES ('pv1', 'm-u', 'solo', 'V', 'other')");
  w.exec("INSERT INTO race_events (id, race_id, event_type, subject_user_id, move_log_id) VALUES ('ev-u', 'solo', 'progress_accepted', 'U', 'm-u')");
  w.exec("INSERT INTO xp_events (id, user_id, source_type, source_id, race_id, xp_amount) VALUES ('xp1', 'U', 'progress_accepted', 'ev-u', 'solo', 10)");
  w.exec("INSERT INTO user_unlocks (id, user_id, unlock_id, source) VALUES ('uu1', 'U', 'ach-first-move', 'achievement')");

  // Shared race W created; U submitted photo proof there (move_logs → media_objects FK).
  const shared = w.race('shared', 'W');
  w.member(shared, 'U');
  const sharedKey = w.photo(shared, 'U');
  w.exec("INSERT INTO move_logs (id, race_id, user_id, source, value, status, media_object_key) VALUES ('m-shared', 'shared', 'U', 'manual', 30, 'verified', ?)", sharedKey);

  // Identity + social residue.
  w.exec("INSERT INTO auth_identities (id, user_id, provider, email) VALUES ('ai1', 'U', 'email', 'U@example.com')");
  w.exec("INSERT INTO sessions (id, user_id, refresh_token_hash, expires_at) VALUES ('s1', 'U', 'h', '2999-01-01')");
  w.exec("INSERT INTO device_tokens (id, user_id, token, platform) VALUES ('d1', 'U', 'tok', 'ios')");
  w.exec("INSERT INTO crew_connections (id, user_id, crew_user_id, status) VALUES ('cc1', 'U', 'W', 'active')");
  w.fkClean();

  const res = await w.req('U', 'DELETE', '/auth/account');
  assert.equal(res.status, 200, `first attempt must succeed: ${res.text}`);
  w.fkClean();

  assert.equal(w.one("SELECT status FROM users WHERE id = 'U'").status, 'deleted');
  assert.equal(w.one("SELECT primary_email FROM users WHERE id = 'U'").primary_email, null);
  for (const [table, where] of [
    ['move_logs', "race_id = 'solo'"], ['race_attempts', "race_id = 'solo'"], ['personal_bests', "race_id = 'solo'"],
    ['proof_votes', "race_id = 'solo'"], ['race_events', "race_id = 'solo'"], ['race_members', "race_id = 'solo'"],
    ['auth_identities', "user_id = 'U'"], ['sessions', "user_id = 'U'"], ['device_tokens', "user_id = 'U'"],
    ['crew_connections', "user_id = 'U' OR crew_user_id = 'U'"], ['xp_events', "user_id = 'U'"],
    ['user_unlocks', "user_id = 'U'"], ['media_objects', "owner_user_id = 'U'"], ['profiles', "user_id = 'U'"],
  ]) {
    assert.equal(w.one(`SELECT COUNT(*) AS n FROM ${table} WHERE ${where}`).n, 0, `${table} ${where}`);
  }
  assert.ok(w.one("SELECT deleted_at FROM races WHERE id = 'solo'").deleted_at, 'solo race soft-deleted');
  const kept = w.one("SELECT user_id, value, media_object_key FROM move_logs WHERE id = 'm-shared'");
  assert.deepEqual(kept, { user_id: 'U', value: 30, media_object_key: null }, 'shared race truth kept, evidence link cleared');
  assert.equal(w.one("SELECT cached_display_name FROM race_members WHERE race_id = 'shared' AND user_id = 'U'").cached_display_name, 'Deleted User');
  assert.equal(w.one("SELECT COUNT(*) AS n FROM move_logs m LEFT JOIN races r ON r.id = m.race_id WHERE r.id IS NULL OR r.deleted_at IS NOT NULL").n, 0, 'no orphan move logs');
  for (const key of [soloKey, vKey, sharedKey]) assert.equal(w.r2.objects.has(key), false, `R2 ${key} deleted`);
});

// ── P0-6: avatar ownership ───────────────────────────────────────────────────

test('P0-6: another user’s avatar URL never becomes a deletable owned key', async () => {
  const w = world();
  w.user('A'); w.user('B');
  const upload = async (sub) => {
    const res = await w.req(sub, 'POST', '/profile/photo/upload-url', { fileName: 'me.jpg', contentType: 'image/jpeg' });
    assert.equal(res.status, 200, res.text);
    const u = new URL(res.json.uploadUrl);
    const put = await app.request(u.pathname + u.search, { method: 'PUT', body: 'jpg-bytes' }, w.env, { waitUntil() {} });
    assert.equal(put.status, 200);
    return res.json;
  };
  const a = await upload('A');
  assert.ok(w.r2.objects.has(a.key));

  const steal = await w.req('B', 'POST', '/profile', { avatarUrl: a.publicUrl });
  assert.equal(steal.status, 200, steal.text);
  assert.equal(w.one("SELECT avatar_object_key FROM profiles WHERE user_id = 'B'").avatar_object_key, null, 'no ownership from a URL');
  await w.req('B', 'POST', '/profile', { avatarUrl: null });
  assert.ok(w.r2.objects.has(a.key), 'A’s object survives B changing avatar');

  // Even a directly-planted foreign key is unlinked, never deleted.
  w.exec("UPDATE profiles SET avatar_object_key = ? WHERE user_id = 'B'", a.key);
  await w.req('B', 'POST', '/profile', { avatarUrl: null });
  assert.ok(w.r2.objects.has(a.key));

  const b1 = await upload('B');
  assert.equal(w.one("SELECT avatar_object_key FROM profiles WHERE user_id = 'B'").avatar_object_key, b1.key);
  await w.req('B', 'POST', '/profile', { avatarUrl: b1.publicUrl });
  assert.ok(w.r2.objects.has(b1.key), 'setting the same owned photo keeps it');
  await w.req('B', 'POST', '/profile', { avatarUrl: null });
  assert.equal(w.r2.objects.has(b1.key), false, 'B’s own old object is deleted');
  assert.ok(w.r2.objects.has(a.key));
  w.fkClean();
});

// ── Expiry semantics: ISO-written expiry columns vs a same-format SQL now ──
// expires_at columns are written via toISOString(); comparing them to
// CURRENT_TIMESTAMP ('YYYY-MM-DD HH:MM:SS') silently disabled expiry — ' '
// sorts before 'T'. These tests pin ISO-now comparisons on real SQLite.

test('expiry: email code expires at its ISO instant, not UTC rollover', async () => {
  const w = world();
  const email = 'expiry-check@example.com';
  const hash = createHash('sha256').update('123456').digest('hex');
  const pastIso = new Date(Date.now() - 60_000).toISOString();
  w.exec(
    "INSERT INTO email_codes (id, email, code_hash, attempts, expires_at, created_at) VALUES ('expired', ?, ?, 0, ?, CURRENT_TIMESTAMP)",
    email, hash, pastIso,
  );
  const dead = await w.req(null, 'POST', '/auth/email/verify', { email, code: '123456' });
  assert.equal(dead.status, 401, 'a code one minute past expiry must not verify');
  assert.equal(w.one('SELECT id FROM users WHERE primary_email = ?', email), undefined);

  // A code that is still valid same-day still works — ISO vs ISO compares
  // correctly inside the same calendar date.
  const freshIso = new Date(Date.now() + 60_000).toISOString();
  w.exec(
    "INSERT INTO email_codes (id, email, code_hash, attempts, expires_at, created_at) VALUES ('fresh', ?, ?, 0, ?, CURRENT_TIMESTAMP)",
    email, hash, freshIso,
  );
  const fresh = await w.req(null, 'POST', '/auth/email/verify', { email, code: '123456' });
  assert.equal(fresh.status, 200, fresh.text);
  assert.ok(fresh.json.accessToken);
  await w.flush();
  w.fkClean();
});

test('expiry: refresh sessions honor ISO expires_at', async () => {
  const w = world();
  w.user('A');
  const deadToken = 'rt-dead';
  const deadHash = createHash('sha256').update(deadToken).digest('hex');
  w.exec(
    "INSERT INTO sessions (id, user_id, refresh_token_hash, expires_at, created_at) VALUES ('s-dead', 'A', ?, ?, CURRENT_TIMESTAMP)",
    deadHash, new Date(Date.now() - 60_000).toISOString(),
  );
  const dead = await w.req(null, 'POST', '/auth/refresh', { refreshToken: deadToken });
  assert.equal(dead.status, 401, 'expired session must not refresh');

  const liveToken = 'rt-live';
  const liveHash = createHash('sha256').update(liveToken).digest('hex');
  w.exec(
    "INSERT INTO sessions (id, user_id, refresh_token_hash, expires_at, created_at) VALUES ('s-live', 'A', ?, ?, CURRENT_TIMESTAMP)",
    liveHash, new Date(Date.now() + 60_000).toISOString(),
  );
  const live = await w.req(null, 'POST', '/auth/refresh', { refreshToken: liveToken });
  assert.equal(live.status, 200, live.text);
  assert.ok(live.json.accessToken);
  await w.flush();
  w.fkClean();
});

test('expiry: expired invite is not reused and cannot be accepted', async () => {
  const w = world();
  w.user('A'); w.user('B');
  const r = w.race('r1', 'A');
  const pastIso = new Date(Date.now() - 60_000).toISOString();
  const deadToken = 'deadtokdeadtokdeadtokdeadtokdead'; // 30 url-safe chars
  w.exec(
    "INSERT INTO invites (id, token, kind, actor_user_id, target_type, target_id, max_uses, use_count, expires_at, created_at) VALUES ('i-dead', ?, 'race_join', 'A', 'race', ?, NULL, 0, ?, CURRENT_TIMESTAMP)",
    deadToken, r, pastIso,
  );
  // Share again: must mint a fresh token, not return the expired one.
  const res = await w.req('A', 'POST', '/invites', { kind: 'race_join', targetId: r });
  assert.equal(res.status, 200, res.text);
  assert.notEqual(res.json.token, deadToken, 'expired invite must not be reused');
  // Accepting the dead token still fails.
  const accept = await w.req('B', 'POST', `/invites/${deadToken}/accept`, {});
  assert.equal(accept.status, 410);
  assert.equal(accept.json.status, 'expired');
  await w.flush();
  w.fkClean();
});

// ── Rename must pass through the same safety gate as creation ──────────────

test('safety: race rename cannot bypass the creation-time safety gate', async () => {
  const w = world();
  w.user('A'); w.user('B');
  const r = w.race('r1', 'A', { title: 'Morning Pages' });
  const unsafe = await w.req('A', 'PATCH', `/races/${r}`, { title: 'casino night all-in poker' });
  assert.equal(unsafe.status, 400, 'unsafe rename rejected');
  assert.equal(w.one('SELECT title FROM races WHERE id = ?', r).title, 'Morning Pages',
    'rejected rename leaves the title unchanged');
  const safe = await w.req('A', 'PATCH', `/races/${r}`, { title: 'Evening Reading Sprint' });
  assert.equal(safe.status, 200, safe.text);
  assert.equal(w.one('SELECT title FROM races WHERE id = ?', r).title, 'Evening Reading Sprint');
  // Non-creators still cannot rename at all.
  const foreign = await w.req('B', 'PATCH', `/races/${r}`, { title: 'Harmless Title' });
  assert.equal(foreign.status, 403);
  await w.flush();
  w.fkClean();
});

// ── AI proof must carry the verification session id ────────────────────────

test('P0-3b: AI proof without a verification session is rejected', async () => {
  const { w, ai } = motionWorld();
  const res = await ai('A', { value: 20, clientSubmissionId: 'n1' });
  assert.equal(res.status, 400, 'ai_motion proof without verificationSessionId is rejected');
  assert.equal(w.one("SELECT COUNT(*) AS n FROM move_logs WHERE user_id = 'A'").n, 0);
  await w.flush();
  w.fkClean();
});

// ── Custom-verifier (Teach Nuvo) sessions ──────────────────────────────────

test('P0-3c: custom-verifier races mint and require verification sessions', async () => {
  const w = world();
  w.user('A'); w.user('B');
  const r = w.race('cr1', 'A', {
    title: 'Overhead Knee Touch', verification_type: 'movecheck',
    verifier_type: 'custom_pose_sequence', activity_id: null, movement_type: null,
    target_unit: 'reps', metric: 'reps', target_value: 10,
  });
  w.exec("UPDATE races SET verifier_version = 1, custom_activity_name = 'Overhead Knee Touch' WHERE id = ?", r);
  w.member(r, 'B');
  const ai = (sub, extra) => w.req(sub, 'POST', `/races/${r}/proof`, {
    proofType: 'ai_motion', metric: 'reps', verificationStatus: 'custom_verified',
    verifierType: 'custom_pose_sequence', verifierVersion: 1,
    activityType: 'Overhead Knee Touch', measurementType: 'count',
    detectedValue: extra?.value ?? 5, ...extra,
  });
  const caps = { runtimeCapabilities: ['pose_landmarks_v1', 'derived_features_v1', 'sequence_match_v1'] };

  // No session → rejected before anything is written.
  assert.equal((await ai('A', { value: 5, clientSubmissionId: 'c0' })).status, 400,
    'custom ai_motion without session is rejected');
  assert.equal((await ai('A', { value: 5, clientSubmissionId: 'c1', verificationSessionId: 'vs-fabricated' })).status, 400);
  assert.equal(w.one("SELECT COUNT(*) AS n FROM move_logs WHERE race_id = ?", r).n, 0);

  // Members mint a session bound to the seeded custom release.
  const mint = await w.req('A', 'POST', `/races/${r}/verification-sessions`, caps);
  assert.equal(mint.status, 201, mint.text);
  const vs = mint.json.session;
  assert.equal(vs.activityId, 'custom_pose_sequence');
  assert.equal(vs.releaseId, 'custom_pose_sequence-native-2026.09.0');

  // Unfinished session cannot back a proof; completion binds it.
  assert.equal((await ai('A', { value: 5, clientSubmissionId: 'c2', verificationSessionId: vs.id })).status, 400);
  const done = await w.req('A', 'POST', `/verification-sessions/${vs.id}/complete`, {
    releaseId: vs.releaseId, releaseChecksum: vs.releaseChecksum,
    status: 'completed', resultValue: 5,
  });
  assert.equal(done.status, 200, done.text);

  assert.equal((await ai('A', { value: 9, clientSubmissionId: 'c3', verificationSessionId: vs.id })).status, 400,
    'claims more than verified');
  const ok = await ai('A', { value: 5, clientSubmissionId: 'c4', verificationSessionId: vs.id });
  assert.equal(ok.status, 200, ok.text);
  assert.equal((await ai('A', { value: 5, clientSubmissionId: 'c5', verificationSessionId: vs.id })).status, 409,
    'one session backs one proof');
  assert.equal((await ai('A', { value: 5, clientSubmissionId: 'c4', verificationSessionId: vs.id })).status, 200,
    'same clientSubmissionId replays idempotently');

  // Another member's session on the same race cannot back A's proof.
  const mintB = await w.req('B', 'POST', `/races/${r}/verification-sessions`, caps);
  assert.equal(mintB.status, 201, mintB.text);
  const vsB = mintB.json.session;
  assert.equal((await ai('A', { value: 5, clientSubmissionId: 'c6', verificationSessionId: vsB.id })).status, 400,
    'another user’s session');
  await w.flush();
  w.fkClean();
});

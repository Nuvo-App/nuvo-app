// reviewer_replay_reset.test.mjs — the App Review "true first-time user"
// reset. Every /auth/reviewer sign-in must return testing@getnuvo.net to a
// just-created account state while preserving the stable user row and the
// seeded review world, idempotently, forever.
//
// Real-SQLite harness, same as release_p0_sql.test.mjs.
// Run: npm test   (tsc builds src/ to .tmp-test-dist first)

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
];

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
  const reviewer = (pw = REVIEWER_PASSWORD) =>
    req(null, 'POST', '/auth/reviewer', { email: 'testing@getnuvo.net', password: pw });

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
  const fkClean = () => assert.deepEqual(q('PRAGMA foreign_key_check'), [], 'foreign_key_check must be clean');
  const flush = async () => { await Promise.all(pending.splice(0)); };
  const scalar = (sql, ...a) => Object.values(q(sql, ...a)[0] ?? { c: 0 })[0];

  return { sqlite, db, r2, env, req, reviewer, q, one, exec, user, race, member, fkClean, flush, scalar };
}

// The seeded review world, minimally reproduced: three crew accounts, the
// reviewer's seeded person row, and the four review-race-* fixtures.
function seedReviewWorld(w, reviewerId) {
  for (const id of ['review-crew-riley', 'review-crew-maya', 'review-crew-jules']) {
    w.user(id);
  }
  w.exec(
    `INSERT INTO people (id, person_key, user_id, display_name, is_demo)
     VALUES ('review-person-google', 'review-person-google', ?, 'Nuvo Review', 0)`,
    reviewerId,
  );
  for (const [id, creator] of [
    ['review-race-pushups', 'review-crew-riley'],
    ['review-race-squats', 'review-crew-riley'],
    ['review-race-plank', 'review-crew-maya'],
    ['review-race-lunges', 'review-crew-jules'],
  ]) {
    w.race(id, creator);
  }
}

// ─── fresh-account shape on every sign-in ──────────────────────────────────

test('reviewer sign-in returns a fresh-account user every time', async () => {
  const w = world();
  const ok = await w.reviewer();
  assert.equal(ok.status, 200, ok.text);
  const u = ok.json.user;
  assert.equal(u.email, 'testing@getnuvo.net');
  assert.equal(u.onboardingComplete, false, 'account must owe the real setup path');
  assert.equal(u.termsAccepted, false);
  assert.equal(u.ageAttested, false);
  assert.equal(u.motionTrainingConsent, false);
  assert.equal(u.fullName, null);
  assert.equal(u.username, null);
  assert.equal(u.isDemo, false, 'reviewer sees the real data world, not presentation fixtures');
  w.fkClean();
});

test('wrong password and foreign emails are rejected without creating users', async () => {
  const w = world();
  const wrong = await w.reviewer('anything');
  assert.equal(wrong.status, 401);
  const retired = await w.req(null, 'POST', '/auth/reviewer', { email: 'team@getnuvo.net', password: REVIEWER_PASSWORD });
  assert.equal(retired.status, 401);
  const other = await w.req(null, 'POST', '/auth/reviewer', { email: 'person@getnuvo.net', password: REVIEWER_PASSWORD });
  assert.equal(other.status, 401);
  const missing = await w.req(null, 'POST', '/auth/reviewer', { email: 'testing@getnuvo.net' });
  assert.equal(missing.status, 401); // missing password → invalid credentials
  assert.equal(
    w.scalar("SELECT COUNT(*) c FROM users WHERE primary_email LIKE '%@getnuvo.net'"),
    0,
  );
});

// ─── idempotence ────────────────────────────────────────────────────────────

test('repeated sign-ins keep one user, one session, and a fresh-account shape', async () => {
  const w = world();
  const r1 = await w.reviewer();
  const u1 = r1.json.user;

  // Simulate a fully completed run between launches.
  w.exec(
    `UPDATE users SET terms_accepted_at = CURRENT_TIMESTAMP, terms_version = 'v1',
       age_attested_at = CURRENT_TIMESTAMP, motion_training_consent = 1,
       motion_consent_version = 'v1', motion_consented_at = CURRENT_TIMESTAMP
     WHERE id = ?`, u1.id,
  );
  w.exec(
    `UPDATE profiles SET full_name = 'Nuvo Review', username = 'nuvoreview',
       onboarding_complete = 1, avatar_url = 'https://x/a.png' WHERE user_id = ?`, u1.id,
  );

  const r2 = await w.reviewer();
  const u2 = r2.json.user;
  const r3 = await w.reviewer();
  const u3 = r3.json.user;

  assert.equal(u2.id, u1.id, 'stable backend identity — never a new user row');
  assert.equal(u3.id, u1.id);
  assert.equal(
    w.scalar("SELECT COUNT(*) c FROM users WHERE primary_email = 'testing@getnuvo.net'"), 1,
  );
  // One live session per run — the previous sign-in's session is cleaned.
  assert.equal(w.scalar('SELECT COUNT(*) c FROM sessions WHERE user_id = ?', u1.id), 1);
  // Fresh-account shape again after every sign-in.
  for (const u of [u2, u3]) {
    assert.equal(u.onboardingComplete, false);
    assert.equal(u.termsAccepted, false);
    assert.equal(u.fullName, null);
  }
  w.fkClean();
});

// ─── replay artifacts purged; seeded world re-normalized ────────────────────

test('prior replay artifacts are purged; the seeded review world is re-asserted', async () => {
  const w = world();
  const r1 = await w.reviewer();
  const u1 = r1.json.user;
  seedReviewWorld(w, u1.id);

  // Prior-run artifacts the reviewer would have created. people.user_id is
  // UNIQUE, so the reviewer's seeded person (review-person-google) carries
  // the replay race's membership row.
  w.exec(
    `INSERT INTO races (id, creator_id, title, race_type, format, verification_type, status, visibility, scoring_rule,
       score_direction, target_value, target_unit, metric, activity_id, movement_type, verifier_type, proof_review_mode,
       end_at, created_at, updated_at)
     VALUES ('r-replay-1', ?, 'Replay race', 'most_in_window', 'most_in_window', 'manual', 'active', 'crew_only',
       'cumulative_sum', 'higher', 10, 'reps', 'reps', 'push_ups', 'push_ups', 'manual_log', 'auto_accept', NULL,
       CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)`,
    u1.id,
  );
  w.exec(
    `INSERT INTO race_members (id, race_id, person_id, user_id, role, status, joined_at)
     VALUES ('rm-replay-1', 'r-replay-1', 'review-person-google', ?, 'creator', 'active', CURRENT_TIMESTAMP)`,
    u1.id,
  );
  w.exec(
    `INSERT INTO move_logs (id, race_id, user_id, source, movement_type, activity_id, metric, value, unit, status, created_at)
     VALUES ('ml-x', 'r-replay-1', ?, 'movecheck', 'push_ups', 'push_ups', 'reps', 5, 'reps', 'verified', CURRENT_TIMESTAMP)`,
    u1.id,
  );
  w.exec(
    `INSERT INTO xp_events (id, user_id, source_type, source_id, xp_amount, created_at)
     VALUES ('xp-x', ?, 'race', 'r-replay-1', 100, CURRENT_TIMESTAMP)`,
    u1.id,
  );
  w.exec(
    `INSERT INTO notifications (id, user_id, category, actor_user_id, title, body, created_at)
     VALUES ('n-x', ?, 'race', 'review-crew-riley', 'Race update', 'x', CURRENT_TIMESTAMP)`,
    u1.id,
  );
  w.exec(
    `INSERT INTO crew_connections (id, user_id, crew_user_id, status, created_at)
     VALUES ('cc-x', ?, 'review-crew-riley', 'active', CURRENT_TIMESTAMP)`,
    u1.id,
  );
  w.exec(
    `INSERT INTO media_objects (id, owner_user_id, bucket, object_key, media_type, purpose, status)
     VALUES ('mo-x', ?, 'nuvor2', 'avatars/x.png', 'image', 'avatar', 'active')`,
    u1.id,
  );
  // Drift a seeded-world row to prove re-normalization to seed values.
  w.exec(
    `INSERT INTO race_progress (id, race_id, user_id, progress_value, progress_percent, rank_cache, updated_at)
     VALUES ('rp-drift', 'review-race-pushups', ?, 999, 999, 99, CURRENT_TIMESTAMP)`,
    u1.id,
  );

  const r2 = await w.reviewer();
  assert.equal(r2.status, 200, r2.text);
  assert.equal(r2.json.user.id, u1.id);

  // Replay artifacts are gone.
  assert.equal(w.scalar("SELECT COUNT(*) c FROM races WHERE id = 'r-replay-1'"), 0);
  assert.equal(w.scalar("SELECT COUNT(*) c FROM race_progress WHERE race_id = 'r-replay-1'"), 0);
  assert.equal(w.scalar("SELECT COUNT(*) c FROM race_members WHERE race_id = 'r-replay-1'"), 0);
  assert.equal(w.scalar("SELECT COUNT(*) c FROM move_logs WHERE id = 'ml-x'"), 0);
  assert.equal(w.scalar("SELECT COUNT(*) c FROM xp_events WHERE id = 'xp-x'"), 0);
  assert.equal(w.scalar("SELECT COUNT(*) c FROM notifications WHERE id = 'n-x'"), 0);
  assert.equal(w.scalar("SELECT COUNT(*) c FROM crew_connections WHERE id = 'cc-x'"), 0);
  assert.equal(w.scalar("SELECT COUNT(*) c FROM media_objects WHERE owner_user_id = ?", u1.id), 0);
  assert.equal(w.scalar("SELECT COUNT(*) c FROM race_progress WHERE id = 'rp-drift'"), 0);

  // The seeded world survived and reviewer-owned seeded rows are back at
  // their seed values.
  assert.equal(w.scalar("SELECT COUNT(*) c FROM races WHERE id LIKE 'review-race-%'"), 4);
  const seeded = w.one("SELECT progress_value, rank_cache FROM race_progress WHERE id = 'review-rp-001'");
  assert.equal(seeded.progress_value, 68);
  assert.equal(seeded.rank_cache, 2);
  assert.equal(
    w.scalar("SELECT COUNT(*) c FROM crew_connections WHERE id LIKE 'review-crew-link-%'"), 6,
  );
  assert.equal(w.scalar('SELECT COUNT(*) c FROM race_members WHERE user_id = ?', u1.id), 4);
  w.fkClean();
});

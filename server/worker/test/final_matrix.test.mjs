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

const JWT_SECRET = 'test-secret';
// Test-only credential for /auth/reviewer — never a real review password.
const REVIEWER_PASSWORD = 'test-review-pass';
const root = new URL('..', import.meta.url);
const SCHEMA = [
  readFileSync(new URL('test/fixtures/prod_schema_2026-09-28.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0042_achievements.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0043_proof_votes.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0044_custom_verifier_seed.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0046_squads.sql', root), 'utf8'),
  // The prod-schema snapshot predates the reports table (reconciled in 0047).
  readFileSync(new URL('migrations/0047_reconcile_prod.sql', root), 'utf8'),
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


const iso = (ms) => new Date(Date.now() + ms).toISOString();
const HOUR = 3600_000;
const FORMATS = ['first_to_goal', 'most_in_window', 'best_attempt', 'timed_attempt'];
const CAPS = { runtimeCapabilities: ['pose_landmarks_v1', 'derived_features_v1', 'sequence_match_v1'] };

// Seeds the registry rows a preset race needs (same shape as release_p0_sql).
function seedPreset(w, activityId = 'push_ups') {
  w.exec(
    `INSERT INTO motion_activities (id, display_name, category, proof_label, measurement_type, metric,
       suggested_targets_json, supported_formats_json, icon_key, availability)
     VALUES (?, 'Pushups', 'upper_body', 'pushups', 'repetitions', 'reps', '[10]', '["first_to_goal"]', 'x', 'supported')`,
    activityId,
  );
  const cols = w.q("SELECT name FROM pragma_table_info('verifier_releases')").map((c) => c.name);
  // Reuse the seeded (valid) native spec, retargeted at this activity.
  const seeded = w.one("SELECT spec_json FROM verifier_releases WHERE activity_id = 'custom_pose_sequence' LIMIT 1");
  const spec = { ...JSON.parse(seeded.spec_json), releaseId: 'rel1', activityId };
  const values = { id: 'rel1', activity_id: activityId, semver: '2026.09.0', change_class: 'minor', engine_type: 'native_v1', spec_schema_version: 1, spec_json: JSON.stringify(spec), checksum: 'sum1', required_capabilities_json: '[]', minimum_app_build: 'legacy', compatibility_group: 'g1', status: 'stable' };
  const use = cols.filter((c) => values[c] !== undefined);
  w.exec(`INSERT INTO verifier_releases (${use.join(', ')}) VALUES (${use.map(() => '?').join(', ')})`, ...use.map((c) => values[c]));
  w.exec("INSERT INTO activity_channel_releases (activity_id, channel, release_id, rollout_percent) VALUES (?, 'stable', 'rel1', 100)", activityId);
}

const MOTION_V2_SPEC = {
  schema: 2, verifier: 'motion_v2', version: 1, name: 'Knee Touch', encoder_id: 'test-encoder',
  references: [
    { proto: [0.1, 0.2, 0.3], traj: [[0.1, 0.2]], length: 90 },
    { proto: [0.1, 0.3, 0.2], traj: [[0.2, 0.1]], length: 88 },
  ],
};

// Minimal bodies, mirroring race_composer_screen / race_api.dart.
function bodyFor(path, format) {
  const goal = format === 'first_to_goal';
  const common = { title: `Matrix ${path} ${format}`, goalType: format };
  const window = goal ? {} : { format, finishLineAt: iso(48 * HOUR) };
  const shape = goal ? { targetValue: 5 } : {};
  if (format === 'timed_attempt') window.attemptDurationSeconds = 60;
  if (path === 'preset') {
    return { ...common, ...shape, ...window, activityId: 'push_ups', aiActivityType: 'push_ups', metric: 'reps', unit: 'reps', targetUnit: 'reps', proofRequirement: 'ai_check', proofMode: 'ai_check', proofReviewMode: 'auto_accept' };
  }
  if (path === 'manual') {
    return { ...common, ...shape, ...window, unit: 'pages', targetUnit: 'pages', metric: 'reps', format, recurrence: 'none', proofRequirement: 'manual', proofMode: 'manual', visibility: 'private' };
  }
  return {
    ...common, ...shape, ...window, format: goal ? undefined : format, unit: 'reps', targetUnit: 'reps', metric: 'reps',
    proofRequirement: 'ai_check', proofReviewMode: 'auto_accept', proofMode: 'ai_check', verificationMethod: 'ai',
    verifierType: 'motion_v2', verifierVersion: 1, customActivityName: 'Knee Touch', verifierSpec: MOTION_V2_SPEC,
  };
}

let subN = 0;
// Submits one proof the way the client does for the race's path.
async function submit(w, raceId, userId, path, value) {
  if (path === 'manual') {
    return w.req(userId, 'POST', `/races/${raceId}/proof`, { proofType: 'manual', value, mediaObjectKey: w.photo(raceId, userId) });
  }
  const mint = await w.req(userId, 'POST', `/races/${raceId}/verification-sessions`, CAPS);
  assert.equal(mint.status, 201, `mint session: ${mint.text}`);
  const vs = mint.json.session;
  const done = await w.req(userId, 'POST', `/verification-sessions/${vs.id}/complete`, {
    releaseId: vs.releaseId, releaseChecksum: vs.releaseChecksum, status: 'completed', resultValue: value,
  });
  assert.equal(done.status, 200, `complete session: ${done.text}`);
  const custom = path === 'custom';
  return w.req(userId, 'POST', `/races/${raceId}/proof`, {
    proofType: 'ai_motion', metric: 'reps', value, clientSubmissionId: `cs-${++subN}`, verificationSessionId: vs.id,
    ...(custom
      ? { verificationStatus: 'custom_verified', verifierType: 'motion_v2', verifierVersion: 1, activityType: 'Knee Touch', measurementType: 'count', detectedValue: value }
      : { verificationStatus: 'ai_verified', activityType: 'push_ups' }),
  });
}

const rows = (j) => j.leaderboard ?? j.race?.leaderboard ?? j.participants ?? j.race?.participants ?? [];

for (const path of ['preset', 'manual', 'custom']) {
  for (const format of FORMATS) {
    for (const context of ['solo', 'crew']) {
      test(`matrix: ${path} x ${format} x ${context}`, async () => {
        const w = world();
        w.user('A', { name: 'Alice' }); w.user('B', { name: 'Bob' });
        if (path === 'preset') seedPreset(w);

        let squad = null;
        if (context === 'crew') {
          squad = (await w.req('A', 'POST', '/squads', { name: 'Matrix Crew' })).json.squad;
          assert.ok(squad?.id);
          assert.equal((await w.req('B', 'POST', '/squads/join', { code: squad.joinCode })).status, 200);
        }

        const created = await w.req('A', 'POST', '/races', bodyFor(path, format));
        assert.equal(created.status, 201, created.text);
        const raceId = created.json.race.id;
        assert.equal(created.json.race.format ?? format, format);

        if (context === 'crew') {
          const add = await w.req('A', 'POST', `/squads/${squad.id}/races`, { raceId });
          assert.equal(add.status, 200, add.text);
          assert.equal(add.json.memberCount, 2);
          assert.equal(add.json.added, 1, 'B (creator already in) is added to the race');
        } else {
          assert.equal((await w.req('A', 'POST', '/crew/add', { userId: 'B' })).status, 200);
          assert.equal((await w.req('B', 'POST', '/crew/requests/A/accept')).status, 200);
          const join = await w.req('B', 'POST', `/races/${raceId}/join`, {});
          assert.ok([200, 201].includes(join.status), `join: ${join.status} ${join.text}`);
        }
        assert.equal(w.one("SELECT COUNT(*) AS n FROM race_members WHERE race_id = ? AND status = 'active'", raceId).n, 2);

        // Attempt formats open an attempt first, as the client does.
        if (format === 'timed_attempt' || format === 'best_attempt') {
          const at = await w.req('B', 'POST', `/races/${raceId}/attempts`, { clientAttemptId: 'att-1' });
          assert.equal(at.status, 200, `attempt: ${at.status} ${at.text}`);
        }

        const target = format === 'first_to_goal' ? 5 : 7;
        const proof = await submit(w, raceId, 'B', path, target);
        assert.equal(proof.status, 200, `proof: ${proof.text}`);

        const detail = await w.req('A', 'GET', `/races/${raceId}`);
        assert.equal(detail.status, 200, detail.text);
        const board = rows(detail.json);
        assert.ok(board.length >= 2, `leaderboard has both racers: ${JSON.stringify(Object.keys(detail.json.race ?? detail.json))}`);
        assert.equal(w.progress(raceId, 'B'), target);

        if (format === 'first_to_goal') {
          const row = w.one('SELECT status, winner_user_id FROM races WHERE id = ?', raceId);
          assert.equal(row.status, 'completed');
          assert.equal(row.winner_user_id, 'B');
        } else {
          assert.equal(w.one('SELECT status FROM races WHERE id = ?', raceId).status, 'active');
          w.exec('UPDATE races SET end_at = ? WHERE id = ?', iso(-1000), raceId);
          const fin = await finalizeRaceIfEnded(w.db, w.one('SELECT * FROM races WHERE id = ?', raceId));
          assert.equal(fin.finalized, true);
          assert.equal(fin.winnerUserId, 'B');
          const row = w.one('SELECT status, winner_user_id FROM races WHERE id = ?', raceId);
          assert.equal(row.status, 'completed');
          assert.equal(row.winner_user_id, 'B');
        }
        // A finished race reads back through the route and a second finalize is a no-op.
        const after = await w.req('A', 'GET', `/races/${raceId}`);
        assert.equal(after.status, 200, after.text);
        if (format !== 'first_to_goal') {
          const again = await finalizeRaceIfEnded(w.db, w.one('SELECT * FROM races WHERE id = ?', raceId));
          assert.equal(again.finalized, false);
        }
        await w.flush();
        w.fkClean();
      });
    }
  }
}

test('crew flow: create, join by code, add existing race, late joiner, leave, rename, delete', async () => {
  const w = world();
  for (const id of ['A', 'B', 'C', 'D']) w.user(id, { name: id });
  const sq = (await w.req('A', 'POST', '/squads', { name: 'Flow Crew' }));
  assert.equal(sq.status, 201, sq.text);
  const squad = sq.json.squad;
  for (const u of ['B', 'C']) assert.equal((await w.req(u, 'POST', '/squads/join', { code: squad.joinCode })).status, 200);
  assert.equal(w.q("SELECT 1 FROM squad_members WHERE squad_id = ? AND status = 'active'", squad.id).length, 3);

  // An existing race (created before the crew link) pulls every member in.
  const created = await w.req('A', 'POST', '/races', bodyFor('manual', 'most_in_window'));
  const raceId = created.json.race.id;
  const add = await w.req('A', 'POST', `/squads/${squad.id}/races`, { raceId });
  assert.equal(add.status, 200, add.text);
  assert.equal(add.json.added, 2);
  assert.equal(add.json.memberCount, 3);
  for (const u of ['A', 'B', 'C']) {
    assert.equal(w.one("SELECT status FROM race_members WHERE race_id = ? AND user_id = ?", raceId, u).status, 'active');
  }
  // Re-adding is idempotent; non-creator and non-member cannot add.
  assert.equal((await w.req('A', 'POST', `/squads/${squad.id}/races`, { raceId })).json.added, 0);
  assert.equal((await w.req('B', 'POST', `/squads/${squad.id}/races`, { raceId })).status, 403);
  assert.equal((await w.req('D', 'POST', `/squads/${squad.id}/races`, { raceId })).status, 404);

  // Late joiner is brought into the crew's race.
  assert.equal((await w.req('D', 'POST', '/squads/join', { code: squad.joinCode })).status, 200);
  assert.equal(w.q("SELECT 1 FROM race_members WHERE race_id = ? AND user_id = 'D' AND status = 'active'", raceId).length, 1);

  const list = await w.req('B', 'GET', '/squads');
  assert.equal(list.status, 200, list.text);
  assert.equal((await w.req('B', 'GET', `/squads/${squad.id}`)).status, 200);

  assert.equal((await w.req('B', 'POST', `/squads/${squad.id}/leave`)).status, 200);
  assert.equal((await w.req('B', 'GET', `/squads/${squad.id}`)).status, 404);
  assert.equal((await w.req('B', 'PATCH', `/squads/${squad.id}`, { name: 'Nope' })).status, 404);

  assert.equal((await w.req('C', 'PATCH', `/squads/${squad.id}`, { name: 'Nope' })).status, 403);
  const ren = await w.req('A', 'PATCH', `/squads/${squad.id}`, { name: 'Renamed Crew' });
  assert.equal(ren.status, 200, ren.text);
  assert.equal(w.one('SELECT name FROM squads WHERE id = ?', squad.id).name, 'Renamed Crew');
  assert.equal((await w.req('A', 'PATCH', `/squads/${squad.id}`, { name: 'x' })).status, 400);

  assert.equal((await w.req('C', 'DELETE', `/squads/${squad.id}`)).status, 403);
  assert.equal((await w.req('A', 'DELETE', `/squads/${squad.id}`)).status, 200);
  assert.equal((await w.req('A', 'GET', `/squads/${squad.id}`)).status, 404);
  assert.equal((await w.req('C', 'POST', '/squads/join', { code: squad.joinCode })).status, 404);
  // Races survive the crew.
  assert.equal(w.one('SELECT status FROM races WHERE id = ?', raceId).status, 'active');
  await w.flush();
  w.fkClean();
});

// ── Route coverage gaps ──────────────────────────────────────────────────────
// Every route in src/routes/*.ts (and the public ones in index.ts) gets at
// least one real hit. Statuses are asserted against the set the contract allows.
const expectStatus = (r, ...allowed) => {
  assert.ok(allowed.includes(r.status), `expected ${allowed.join('|')} got ${r.status}: ${r.text}`);
  return r;
};

test('gaps: public + auth routes', async () => {
  const w = world();
  w.user('A');
  for (const p of ['/.well-known/apple-app-site-association', '/apple-app-site-association', '/.well-known/assetlinks.json']) {
    expectStatus(await w.req(null, 'GET', p), 200);
  }
  const html = await w.req(null, 'GET', '/j/not-a-real-token');
  expectStatus(html, 200, 404);
  expectStatus(await w.req(null, 'GET', '/motion/releases/nope'), 404);
  expectStatus(await w.req(null, 'GET', '/motion/releases/nope/assets/nope'), 404);
  // Social sign-in rejects a missing token before any network call.
  expectStatus(await w.req(null, 'POST', '/auth/google', {}), 400);
  expectStatus(await w.req(null, 'POST', '/auth/apple', {}), 400);
  expectStatus(await w.req('A', 'POST', '/auth/logout'), 200);
  expectStatus(await w.req('A', 'GET', '/pass/me'), 200, 404);
  await w.flush();
});

test('gaps: profile, progression, users, notifications, devices, reactions, reports', async () => {
  const w = world();
  w.user('A', { name: 'Alice' }); w.user('B', { name: 'Bobby' });
  expectStatus(await w.req(null, 'GET', '/profile/photo/object/profile-photos/none.jpg'), 404);
  expectStatus(await w.req('A', 'GET', '/profile/activity?days=30&tz=-300'), 200);
  expectStatus(await w.req('A', 'POST', '/profile/username/check', { username: 'fresh_name' }), 200);
  expectStatus(await w.req('A', 'GET', '/progression'), 200);
  expectStatus(await w.req('A', 'GET', '/progression/badges'), 200);
  expectStatus(await w.req('A', 'PUT', '/progression/featured', { unlockIds: [] }), 200);
  expectStatus(await w.req('A', 'GET', '/progression/race/none'), 200);
  expectStatus(await w.req('A', 'POST', '/progression/level-seen'), 200);
  expectStatus(await w.req('A', 'GET', '/users/search?q=bob'), 200);

  // friends: request, list, decline, remove
  expectStatus(await w.req('A', 'POST', '/crew/add', { userId: 'B' }), 200);
  expectStatus(await w.req('B', 'GET', '/crew/requests'), 200);
  expectStatus(await w.req('B', 'POST', '/crew/requests/A/decline'), 200);
  expectStatus(await w.req('A', 'POST', '/crew/add', { userId: 'B' }), 200);
  expectStatus(await w.req('B', 'POST', '/crew/requests/A/accept'), 200);
  expectStatus(await w.req('A', 'GET', '/crew/feed'), 200);
  expectStatus(await w.req('A', 'DELETE', '/crew/B'), 200);

  // notifications
  w.exec("INSERT INTO notifications (id, user_id, category, title, body) VALUES ('n1', 'A', 'system', 't', 'b')");
  expectStatus(await w.req('A', 'POST', '/notifications/n1/read'), 200);
  expectStatus(await w.req('A', 'GET', '/notifications/preferences'), 200);
  expectStatus(await w.req('A', 'PATCH', '/notifications/preferences', {}), 200, 400);

  // devices
  expectStatus(await w.req('A', 'POST', '/devices', { token: 'tok-1', platform: 'ios' }), 200);
  expectStatus(await w.req('A', 'DELETE', '/devices/tok-1'), 200);

  // reactions on a race, then reports + blocks
  const r = w.race('rx', 'A');
  w.member(r, 'B');
  expectStatus(await w.req('B', 'POST', '/reactions', { entityType: 'race', entityId: r, emoji: '🔥' }), 200, 400);
  expectStatus(await w.req('B', 'DELETE', '/reactions', { entityType: 'race', entityId: r }), 200);
  expectStatus(await w.req('B', 'POST', '/reports/users/A', { reason: 'spam' }), 200);
  expectStatus(await w.req('B', 'POST', '/reports/races/rx', { reason: 'spam' }), 200);
  expectStatus(await w.req('B', 'POST', '/reports/content/some-proof', { reason: 'spam' }), 200, 404);
  expectStatus(await w.req('B', 'POST', '/reports/blocks/A'), 200);
  assert.equal(expectStatus(await w.req('B', 'GET', '/reports/blocks'), 200).json.ok, true);
  expectStatus(await w.req('B', 'DELETE', '/reports/blocks/A'), 200);
  await w.flush();
});

test('gaps: race routes (list, participants, invite-code, archive, cancel, delete, rematch, logs, media)', async () => {
  const w = world();
  w.user('A'); w.user('B');
  assert.equal(expectStatus(await w.req('A', 'GET', '/races'), 200).status, 200);

  const mk = async (title) => (await w.req('A', 'POST', '/races', { ...bodyFor('manual', 'first_to_goal'), title })).json.race.id;
  const r = await mk('Gap one');
  expectStatus(await w.req('A', 'GET', '/races'), 200);
  expectStatus(await w.req('A', 'POST', `/races/${r}/participants`, { userId: 'B' }), 200, 201, 403);
  expectStatus(await w.req('A', 'POST', `/races/${r}/invite-code`, {}), 200);
  expectStatus(await w.req('A', 'GET', `/races/${r}/events`), 200);
  expectStatus(await w.req('A', 'GET', `/races/${r}/live`), 200);
  expectStatus(await w.req('A', 'GET', `/races/${r}/move-logs`), 200);
  expectStatus(await w.req('A', 'POST', `/races/${r}/move-log`, {}), 410);
  expectStatus(await w.req('A', 'PATCH', `/races/${r}/progress/A`, {}), 403, 404, 410, 400);
  const up = expectStatus(await w.req('A', 'POST', `/races/${r}/proof-media/upload-url`, { fileName: 'p.jpg', contentType: 'image/jpeg' }), 200);
  const token = new URL(up.json.uploadUrl).search;
  const put = await app.request(`/races/${r}/proof-media/upload${token}`, { method: 'PUT', headers: { 'Content-Type': 'image/jpeg' }, body: 'jpgbytes' }, w.env, { waitUntil() {}, passThroughOnException() {} });
  assert.ok(put.status < 500, `upload PUT ${put.status}`);
  const key = w.photo(r, 'A');
  expectStatus(await w.req('A', 'GET', `/races/${r}/proof-media/object/${key}`), 200, 404);
  expectStatus(await w.req('A', 'POST', `/races/${r}/rematch`, {}), 200, 201);

  const toArchive = await mk('Gap archive');
  expectStatus(await w.req('A', 'POST', `/races/${toArchive}/archive`, {}), 200);
  const toCancel = await mk('Gap cancel');
  expectStatus(await w.req('A', 'POST', `/races/${toCancel}/cancel`, {}), 200);
  const toDelete = await mk('Gap delete');
  expectStatus(await w.req('A', 'DELETE', `/races/${toDelete}`), 200);
  expectStatus(await w.req('A', 'GET', `/races/${toDelete}`), 404);
  await w.flush();
});

test('gaps: motion routes', async () => {
  const w = world();
  w.env.MOTION_DATA_MASTER_KEY = 'test-motion-master-key';
  w.user('A');
  expectStatus(await w.req('A', 'POST', '/motion/analyze', {}), 400);
  expectStatus(await w.req('A', 'GET', '/motion/jobs/none'), 404);
  expectStatus(await w.req('A', 'POST', '/motion/training/examples', {}), 400, 403);
  expectStatus(await w.req('A', 'POST', '/motion-sessions/none/feedback', { label: 'worked' }), 404);
  await w.flush();
});

test('gaps: internal operator routes', async () => {
  const w = world();
  w.env.INTERNAL_API_KEY = 'internal-key';
  w.env.MOTION_DATA_MASTER_KEY = 'test-motion-master-key';
  w.user('A');
  const ctx = { waitUntil() {}, passThroughOnException() {} };
  const call = async (method, path, body) => {
    const res = await app.request(path, {
      method, headers: { 'Content-Type': 'application/json', 'X-Internal-Key': 'internal-key' },
      body: body == null ? undefined : JSON.stringify(body),
    }, w.env, ctx);
    return { status: res.status, text: await res.text() };
  };
  assert.equal((await w.req(null, 'GET', '/internal/motion/catalog')).status, 403, 'key required');
  expectStatus(await call('GET', '/internal/motion/catalog'), 200);
  expectStatus(await call('GET', '/internal/motion/releases/none'), 404);
  expectStatus(await call('GET', '/internal/motion/adaptation/signals'), 200);
  expectStatus(await call('GET', '/internal/motion/activities/push_ups/releases'), 200, 404);
  expectStatus(await call('GET', '/internal/motion/models'), 200);
  expectStatus(await call('GET', '/internal/motion/audit'), 200);
  expectStatus(await call('GET', '/internal/users/resolve?id=A'), 200);
  expectStatus(await call('GET', '/internal/users/A/motion-sessions'), 200);
  expectStatus(await call('GET', '/internal/activities/push_ups/motion-sessions/latest'), 200, 404);
  expectStatus(await call('POST', '/internal/reports/none', { status: 'reviewed' }), 200);
  expectStatus(await call('POST', '/internal/motion/releases/none/disable', {}), 400, 404);
  expectStatus(await call('POST', '/internal/motion/models/none/disable', {}), 400, 404);
  expectStatus(await call('POST', '/internal/motion/releases/none/assets/none', {}), 400, 404);
  await w.flush();
});

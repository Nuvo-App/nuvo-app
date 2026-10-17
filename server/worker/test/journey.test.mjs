// End-to-end journey on the prod-schema SQLite harness: friends, races (goal
// and most-total), invites, crews, arena, notifications, profile, blocking.
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
  readFileSync(new URL('migrations/0046_squads.sql', root), 'utf8'),
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
const jsonOk = (r, status = 200) => {
  assert.equal(r.status, status, `${r.status} ${r.text}`);
  assert.ok(r.json, `JSON body expected: ${r.text}`);
  return r.json;
};

test('journey: friends -> goal race via invite -> most-total race -> crew -> arena -> inbox -> profile -> block', async () => {
  const w = world();
  w.user('A', { name: 'Alice' });
  w.user('B', { name: 'Bob' });

  // friends
  const add = jsonOk(await w.req('A', 'POST', '/crew/add', { userId: 'B' }));
  assert.equal(add.status, 'pending');
  const acc = jsonOk(await w.req('B', 'POST', '/crew/requests/A/accept'));
  assert.equal(acc.status, 'active');
  assert.equal(jsonOk(await w.req('A', 'GET', '/crew')).crew.length, 1);

  // first_to_goal race, B joins by invite token
  const created = await w.req('A', 'POST', '/races', {
    title: 'Pushup dash', activityId: 'push_ups', metric: 'reps', format: 'first_to_goal', targetValue: 20,
  });
  const raceId = jsonOk(created, 201).race?.id ?? created.json.id ?? created.json.raceId;
  assert.ok(raceId, created.text);
  const mint = jsonOk(await w.req('A', 'POST', '/invites', { kind: 'race_join', targetId: raceId }));
  const prev = jsonOk(await w.req('B', 'GET', `/invites/${mint.token}`));
  assert.equal(prev.status, 'active');
  const accept = jsonOk(await w.req('B', 'POST', `/invites/${mint.token}/accept`));
  assert.equal(accept.alreadyJoined, false);
  assert.equal(jsonOk(await w.req('B', 'POST', `/invites/${mint.token}/accept`)).alreadyJoined, true);

  // most_in_window race: several submissions add up
  const mw = w.race('mw', 'A', { end_at: iso(HOUR) });
  w.member('mw', 'B');
  const sub = (u, rid, v) => w.req(u, 'POST', `/races/${rid}/proof`, { proofType: 'manual', value: v, mediaObjectKey: w.photo(rid, u) });
  for (const v of [10, 15]) assert.equal((await sub('A', mw, v)).status, 200);
  assert.equal((await sub('B', mw, 30)).status, 200);
  assert.equal(w.progress(mw, 'A'), 25);
  w.exec('UPDATE races SET end_at = ? WHERE id = ?', iso(-1000), mw);
  const fin = await finalizeRaceIfEnded(w.db, w.one('SELECT * FROM races WHERE id = ?', mw));
  assert.equal(fin.winnerUserId, 'B');

  // crew lifecycle
  const sq = jsonOk(await w.req('A', 'POST', '/squads', { name: 'Night Crew' }), 201).squad;
  const join = jsonOk(await w.req('B', 'POST', '/squads/join', { code: sq.joinCode }));
  assert.equal(join.alreadyJoined, false);
  jsonOk(await w.req('A', 'POST', `/squads/${sq.id}/members/B/role`, { role: 'admin' }));
  jsonOk(await w.req('A', 'POST', `/squads/${sq.id}/races`, { raceId }));
  jsonOk(await w.req('A', 'GET', `/squads/${sq.id}`));
  jsonOk(await w.req('B', 'POST', `/squads/${sq.id}/leave`));
  jsonOk(await w.req('B', 'POST', '/squads/join', { code: sq.joinCode }));
  jsonOk(await w.req('A', 'DELETE', `/squads/${sq.id}/members/B`));
  assert.equal((await w.req('B', 'POST', '/squads/join', { code: sq.joinCode })).status, 403);
  jsonOk(await w.req('A', 'DELETE', `/squads/${sq.id}`));
  assert.equal((await w.req('A', 'GET', `/squads/${sq.id}`)).status, 404);

  // arena, inbox, profile
  await w.flush();
  jsonOk(await w.req('A', 'GET', '/arena'));
  jsonOk(await w.req('B', 'GET', '/arena'));
  const inbox = jsonOk(await w.req('A', 'GET', '/notifications'));
  assert.ok(Array.isArray(inbox.notifications));
  assert.ok(jsonOk(await w.req('B', 'GET', '/notifications')).notifications.length > 0);
  jsonOk(await w.req('A', 'POST', '/notifications/read-all'));
  assert.equal(jsonOk(await w.req('A', 'GET', '/notifications?limit=abc')).ok, true);
  jsonOk(await w.req('A', 'GET', '/profile/me'));
  jsonOk(await w.req('A', 'POST', '/profile', { fullName: 'Alice A' }));

  // blocking
  w.exec("INSERT INTO blocked_users (id, user_id, blocked_user_id) VALUES ('bl1', 'A', 'B')");
  assert.equal((await w.req('B', 'POST', '/crew/add', { userId: 'A' })).status, 403);
  assert.equal((await w.req('B', 'GET', '/users/A')).status, 403);
  assert.equal((await w.req('B', 'POST', '/squads/join', { code: 'ZZZZZZ' })).status, 404);
  w.fkClean();
});

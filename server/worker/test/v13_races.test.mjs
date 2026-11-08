// v13 worker races additions (docs/redesign/FEASIBILITY.md §4 row W3):
//   GET /races/open, racesTogether on GET /crew, GET /leaderboard,
//   racerCount on GET /races/activities, viewerContext.previousRank,
//   friends-of-a-participant join/read on crew_only races.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';

const require = createRequire(import.meta.url);
const app = require('../.tmp-test-dist/index.js').default;
const { signJwt } = require('../.tmp-test-dist/lib/jwt.js');

const JWT_SECRET = 'test-secret';
const root = new URL('..', import.meta.url);
const SCHEMA = [
  readFileSync(new URL('test/fixtures/prod_schema_2026-09-28.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0042_achievements.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0043_proof_votes.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0044_custom_verifier_seed.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0050_race_rules_version.sql', root), 'utf8'),
];

// ── D1 adapter over node:sqlite (same shape as race_membership.test.mjs) ─────
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

function world() {
  const sqlite = new DatabaseSync(':memory:');
  for (const sql of SCHEMA) sqlite.exec(sql);
  sqlite.exec('PRAGMA foreign_keys = ON');
  const db = d1(sqlite);
  const pending = [];
  const env = { DB: db, JWT_SECRET };
  const ctx = { waitUntil: (p) => pending.push(p), passThroughOnException() {} };
  const q = (sql, ...a) => sqlite.prepare(sql).all(...a).map((r) => ({ ...r }));
  const one = (sql, ...a) => q(sql, ...a)[0];
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
    exec('INSERT INTO profiles (user_id, full_name) VALUES (?, ?)', id, `name-${id}`);
    exec('INSERT INTO people (id, person_key, user_id, display_name) VALUES (?, ?, ?, ?)', `p-${id}`, `user-${id}`, id, `name-${id}`);
  };
  // Dual-write the pair like transitionCrew does in production.
  const friends = (a, b) => {
    exec("INSERT INTO crew_connections (id, user_id, crew_user_id, status) VALUES (?, ?, ?, 'active')", `cc-${a}-${b}`, a, b);
    exec("INSERT INTO crew_connections (id, user_id, crew_user_id, status) VALUES (?, ?, ?, 'active')", `cc-${b}-${a}`, b, a);
  };
  const block = (a, b) =>
    exec('INSERT INTO blocked_users (id, user_id, blocked_user_id) VALUES (?, ?, ?)', `bu-${a}-${b}`, a, b);
  let memberN = 0;
  const member = (raceId, userId, role = 'racer', status = 'active', value = 0, joinedExpr = "datetime('now')") => {
    exec(
      `INSERT INTO race_members (id, race_id, person_id, user_id, role, status, joined_at) VALUES (?, ?, ?, ?, ?, ?, ${joinedExpr})`,
      `rm-${raceId}-${userId}-${++memberN}`, raceId, `p-${userId}`, userId, role, status,
    );
    exec('INSERT OR IGNORE INTO race_progress (id, race_id, user_id, progress_value, progress_percent) VALUES (?, ?, ?, ?, 0)', `rp-${raceId}-${userId}`, raceId, userId, value);
  };
  const race = (id, creator, over = {}) => {
    const r = {
      format: 'most_in_window', race_type: 'most_in_window', status: 'active', visibility: 'crew_only',
      target_value: null, start_at: null, end_at: null, activity_id: null, public_join_enabled: 1,
      created_expr: "datetime('now')", deleted: false, ...over,
    };
    exec(
      `INSERT INTO races (id, creator_id, title, race_type, format, verification_type, status, visibility, public_join_enabled,
         scoring_rule, score_direction, target_value, target_unit, metric, activity_id, verifier_type, proof_review_mode,
         start_at, end_at, deleted_at, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, 'manual', ?, ?, ?, 'cumulative_sum', 'higher', ?, 'reps', 'reps', ?,
         'manual_log', 'auto_accept', ?, ?, ?, ${r.created_expr}, CURRENT_TIMESTAMP)`,
      id, creator, `Race ${id}`, r.race_type, r.format, r.status, r.visibility, r.public_join_enabled,
      r.target_value, r.activity_id, r.start_at, r.end_at, r.deleted ? '2026-01-01T00:00:00.000Z' : null,
    );
    if (over.creatorMember !== false) member(id, creator, 'creator');
    return id;
  };
  let moveN = 0;
  const move = (raceId, userId, { value, status = 'verified', createdExpr = "datetime('now')", previousRank = null, newRank = null } = {}) =>
    exec(
      `INSERT INTO move_logs (id, race_id, user_id, source, value, status, created_at, previous_rank, new_rank)
       VALUES (?, ?, ?, 'manual', ?, ?, ${createdExpr}, ?, ?)`,
      `ml-${++moveN}`, raceId, userId, value, status, previousRank, newRank,
    );
  const flush = async () => { await Promise.all(pending.splice(0)); };
  return { sqlite, env, req, q, one, exec, user, friends, block, race, member, move, flush };
}

// Seed one registry activity so /races/activities has a row to count against.
function seedActivity(w, id, availability = 'supported') {
  w.exec(
    `INSERT INTO motion_activities
       (id, display_name, category, proof_label, measurement_type, metric,
        suggested_targets_json, supported_formats_json, icon_key, sort_priority,
        featured, availability, metadata_json)
     VALUES (?, ?, 'full_body', ?, 'repetitions', 'reps', '[10]', '["first_to_goal"]', 'fitness_center', 100, 0, ?, '{}')`,
    id, id, id, availability,
  );
}

// ── GET /races/open ──────────────────────────────────────────────────────────

test('open: a friend-created crew_only race is listed for the friend, not for a stranger', async () => {
  const w = world();
  w.user('A'); w.user('B'); w.user('S');
  w.friends('A', 'B');
  w.race('r1', 'B', { visibility: 'crew_only' });

  const mine = await w.req('A', 'GET', '/races/open');
  assert.equal(mine.status, 200, mine.text);
  assert.deepEqual(mine.json.races.map((r) => r.id), ['r1']);
  const row = mine.json.races[0];
  assert.equal(row.title, 'Race r1');
  assert.equal(row.creatorId, 'B');
  assert.ok(Array.isArray(row.participants), 'same row shape as GET /races');
  assert.equal(row.viewerContext.isMember, false);
  // The invite code is insider data — a not-yet-joined viewer never gets it.
  assert.equal(row.inviteCode, null);

  const theirs = await w.req('S', 'GET', '/races/open');
  assert.equal(theirs.status, 200);
  assert.deepEqual(theirs.json.races, []);
});

test('open: a race merely containing a friend is listed, readable and joinable', async () => {
  const w = world();
  w.user('A'); w.user('B'); w.user('S');
  w.friends('A', 'B');
  // S is a stranger to A; A's friend B races in S's crew_only race.
  w.race('r2', 'S', { visibility: 'crew_only' });
  w.member('r2', 'B');

  const res = await w.req('A', 'GET', '/races/open');
  assert.equal(res.status, 200, res.text);
  assert.deepEqual(res.json.races.map((r) => r.id), ['r2']);

  // Friends-of-a-participant get crew-level read — the card must not 404.
  const read = await w.req('A', 'GET', '/races/r2');
  assert.equal(read.status, 200, read.text);

  // …and POST /races/:id/join must actually let them in.
  const join = await w.req('A', 'POST', '/races/r2/join');
  assert.equal(join.status, 200, join.text);
  assert.equal(join.json.race.viewerContext.isMember, true);
  assert.equal(w.one("SELECT status FROM race_members WHERE race_id = 'r2' AND user_id = 'A'").status, 'active');
});

test('open: non-friend-of-anyone cannot read or join a crew_only race', async () => {
  const w = world();
  w.user('A'); w.user('B'); w.user('S'); w.user('X');
  w.friends('A', 'B');
  w.race('r3', 'S', { visibility: 'crew_only' });
  w.member('r3', 'B');

  assert.equal((await w.req('X', 'GET', '/races/r3')).status, 404);
  const join = await w.req('X', 'POST', '/races/r3/join');
  assert.equal(join.status, 403);
  assert.equal((await w.req('X', 'GET', '/races/open')).json.races.length, 0);
});

test('open: excludes own races, joined/left/removed races, finished races and unfriendable scopes', async () => {
  const w = world();
  w.user('A'); w.user('B'); w.user('S');
  w.friends('A', 'B');

  w.race('own', 'A');                                          // creator
  w.race('joined', 'B'); w.member('joined', 'A');              // already in
  w.race('left', 'B'); w.member('left', 'A', 'racer', 'left'); // left once
  w.race('removed', 'B'); w.member('removed', 'A', 'racer', 'removed');
  w.race('done', 'B', { status: 'completed' });
  w.race('cancelled', 'B', { status: 'cancelled' });
  w.race('ended', 'B', { end_at: '2000-01-01T00:00:00.000Z' });
  w.race('deleted', 'B', { deleted: true });
  w.race('private', 'B', { visibility: 'private' });
  w.race('invite', 'B', { visibility: 'invite_code' });
  w.race('pub-closed', 'S', { visibility: 'public_demo', public_join_enabled: 0 });
  w.member('pub-closed', 'B');
  w.race('empty-crew', 'S');                                   // no friend inside

  const res = await w.req('A', 'GET', '/races/open');
  assert.equal(res.status, 200, res.text);
  assert.deepEqual(res.json.races, []);
});

test('open: scheduled and public_demo races still surface when joinable; ordering is newest-first', async () => {
  const w = world();
  w.user('A'); w.user('B'); w.user('S');
  w.friends('A', 'B');

  w.race('old', 'B', { created_expr: "datetime('now', '-60 seconds')" });
  w.race('scheduled', 'B', { start_at: '2999-01-01T00:00:00.000Z', created_expr: "datetime('now', '-30 seconds')" });
  w.race('pub', 'S', { visibility: 'public_demo', public_join_enabled: 1, created_expr: "datetime('now', '-1 seconds')" });
  w.member('pub', 'B');

  const res = await w.req('A', 'GET', '/races/open');
  assert.equal(res.status, 200, res.text);
  assert.deepEqual(res.json.races.map((r) => r.id), ['pub', 'scheduled', 'old']);
});

test('open: blocked links and blocked creators hide the race', async () => {
  const w = world();
  w.user('A'); w.user('B'); w.user('C'); w.user('S');
  w.friends('A', 'B'); w.friends('A', 'C');

  // The only friend inside is blocked by the viewer.
  w.race('bf', 'S', { visibility: 'crew_only' });
  w.member('bf', 'B');
  w.block('A', 'B');

  // The creator blocked the viewer even though an unblocked friend is inside.
  w.race('bc', 'S', { visibility: 'crew_only' });
  w.member('bc', 'C');
  w.block('S', 'A');

  const res = await w.req('A', 'GET', '/races/open');
  assert.equal(res.status, 200, res.text);
  assert.deepEqual(res.json.races, []);
  // Blocks still win on the join path too.
  assert.equal((await w.req('A', 'POST', '/races/bf/join')).status, 403);
  assert.equal((await w.req('A', 'POST', '/races/bc/join')).status, 403);
});

test('open: a creator-removed member cannot rejoin through it', async () => {
  const w = world();
  w.user('A'); w.user('B'); w.user('S');
  w.friends('A', 'B');
  w.race('rx', 'S', { visibility: 'crew_only' });
  w.member('rx', 'B');
  w.member('rx', 'A', 'racer', 'removed');

  assert.equal((await w.req('A', 'GET', '/races/open')).json.races.length, 0);
  const join = await w.req('A', 'POST', '/races/rx/join');
  assert.equal(join.status, 403);
  assert.equal(join.json.error, 'You were removed from this race');
});

// ── GET /crew racesTogether ──────────────────────────────────────────────────

test('crew: racesTogether counts shared non-deleted races, ignoring removed memberships', async () => {
  const w = world();
  w.user('A'); w.user('B'); w.user('C'); w.user('D'); w.user('S');
  w.friends('A', 'B'); w.friends('A', 'C'); w.friends('A', 'D');

  w.race('s1', 'A'); w.member('s1', 'B');                        // A+B
  w.race('s2', 'C'); w.member('s2', 'A'); w.member('s2', 'B');   // A+B, A+C
  w.race('s3', 'S'); w.member('s3', 'A'); w.member('s3', 'B');   // A+B
  w.race('s4', 'A'); w.member('s4', 'B', 'racer', 'removed');    // kicked — not counted
  w.race('s5', 'B'); w.member('s5', 'A', 'racer', 'left');       // left still counts
  w.race('s6', 'B', { deleted: true }); w.member('s6', 'A');     // deleted — not counted

  const res = await w.req('A', 'GET', '/crew');
  assert.equal(res.status, 200, res.text);
  const byId = Object.fromEntries(res.json.crew.map((r) => [r.id, r]));
  assert.equal(byId.B.racesTogether, 4, 's1+s2+s3+s5');
  assert.equal(byId.C.racesTogether, 1, 's2');
  assert.equal(byId.D.racesTogether, 0);
});

// ── GET /leaderboard ─────────────────────────────────────────────────────────

test('leaderboard: friends scope ranks verified 7-day proof value, viewer included', async () => {
  const w = world();
  w.user('A'); w.user('B'); w.user('C'); w.user('X'); w.user('Y');
  w.friends('A', 'B'); w.friends('A', 'C'); w.friends('A', 'Y');
  w.race('r1', 'A');
  w.member('r1', 'B'); w.member('r1', 'C'); w.member('r1', 'X'); w.member('r1', 'Y');
  w.block('A', 'Y');

  w.move('r1', 'B', { value: 30 });
  w.move('r1', 'B', { value: 50, status: 'pending' });                       // pending — not counted
  w.move('r1', 'A', { value: 10 });
  w.move('r1', 'A', { value: 5, createdExpr: "datetime('now', '-8 days')" }); // >7d — not counted
  w.move('r1', 'C', { value: 10 });
  w.move('r1', 'X', { value: 999 });                                         // stranger — out of scope
  w.move('r1', 'Y', { value: 7 });                                           // blocked — excluded

  const res = await w.req('A', 'GET', '/leaderboard');
  assert.equal(res.status, 200, res.text);
  assert.equal(res.json.scope, 'friends');
  assert.deepEqual(
    res.json.rows.map((r) => [r.userId, r.points, r.rank]),
    [['B', 30, 1], ['A', 10, 2], ['C', 10, 2]],
  );
  assert.equal(res.json.rows.find((r) => r.isMe).userId, 'A');
  assert.equal(res.json.rows.every((r) => r.userId !== 'Y'), true);
  assert.equal(res.json.rows[0].displayName, 'name-B');
});

test('leaderboard: ties share a rank and the viewer is present even on zero', async () => {
  const w = world();
  w.user('A'); w.user('B');
  w.friends('A', 'B');
  w.race('r1', 'B');
  w.member('r1', 'A');
  w.move('r1', 'B', { value: 42 });
  // A has no proofs at all.

  const res = await w.req('A', 'GET', '/leaderboard?scope=friends');
  assert.equal(res.status, 200, res.text);
  const me = res.json.rows.find((r) => r.isMe);
  assert.equal(me.points, 0);
  assert.equal(me.rank, 2);
});

test('leaderboard: moves on deleted races do not count; unknown scope falls back to friends', async () => {
  const w = world();
  w.user('A'); w.user('B');
  w.friends('A', 'B');
  w.race('r1', 'B'); w.member('r1', 'A');
  w.race('r2', 'B', { deleted: true }); w.member('r2', 'A');
  w.move('r1', 'B', { value: 10 });
  w.move('r2', 'B', { value: 500 });

  const res = await w.req('A', 'GET', '/leaderboard?scope=bogus');
  assert.equal(res.status, 200, res.text);
  assert.equal(res.json.scope, 'friends');
  assert.equal(res.json.rows.find((r) => r.userId === 'B').points, 10);
});

test('leaderboard: global scope ranks every active user but still hides blocks', async () => {
  const w = world();
  w.user('A'); w.user('B'); w.user('X'); w.user('Y');
  w.friends('A', 'B');
  w.race('r1', 'X');
  w.member('r1', 'A'); w.member('r1', 'B'); w.member('r1', 'Y');
  w.move('r1', 'X', { value: 999 });
  w.move('r1', 'B', { value: 10 });
  w.move('r1', 'Y', { value: 5 });
  w.block('A', 'Y');

  const res = await w.req('A', 'GET', '/leaderboard?scope=global');
  assert.equal(res.status, 200, res.text);
  assert.equal(res.json.scope, 'global');
  assert.deepEqual(
    res.json.rows.map((r) => [r.userId, r.points, r.rank]),
    [['X', 999, 1], ['B', 10, 2], ['A', 0, 3]],
  );
});

// ── GET /races/activities racerCount ─────────────────────────────────────────

test('activities: racerCount is distinct users who joined live races of the activity in the last 7 days', async () => {
  const w = world();
  w.user('A'); w.user('B'); w.user('C'); w.user('D');
  seedActivity(w, 'push_ups');
  seedActivity(w, 'squats');

  w.race('p1', 'A', { activity_id: 'push_ups' });          // creator joins count too (member row)
  w.member('p1', 'B');
  w.member('p1', 'C');
  w.race('p2', 'B', { activity_id: 'push_ups' });
  w.member('p2', 'A');                                   // A counted once across both races
  w.race('done', 'A', { activity_id: 'push_ups', status: 'completed' });
  w.member('done', 'D');
  w.race('oldjoin', 'B', { activity_id: 'push_ups' });
  w.member('oldjoin', 'D', 'racer', 'active', 0, "datetime('now', '-8 days')");
  w.race('s1', 'A', { activity_id: 'squats' });
  w.member('s1', 'D');

  const res = await w.req(null, 'GET', '/races/activities');
  assert.equal(res.status, 200, res.text);
  const byId = Object.fromEntries(res.json.activities.map((a) => [a.id, a]));
  // p1: A,B,C — p2: B,A — distinct = {A,B,C} = 3 (D's join is too old / race done).
  assert.equal(byId.push_ups.racerCount, 3);
  assert.equal(byId.squats.racerCount, 2); // A + D
});

// ── viewerContext.previousRank + finalStandings on list rows ─────────────────

test('races rows: viewerContext.previousRank comes from the latest move_log previous_rank', async () => {
  const w = world();
  w.user('A'); w.user('B');
  w.race('r1', 'B');
  w.member('r1', 'A');
  w.move('r1', 'A', { value: 5, previousRank: 9, newRank: 5, createdExpr: "datetime('now', '-10 seconds')" });
  w.move('r1', 'A', { value: 5, previousRank: 3, newRank: 2, createdExpr: "datetime('now', '-1 seconds')" });
  w.race('r2', 'B');
  w.member('r2', 'A'); // no moves here

  const list = await w.req('A', 'GET', '/races');
  assert.equal(list.status, 200, list.text);
  const rows = Object.fromEntries(list.json.races.map((r) => [r.id, r]));
  assert.equal(rows.r1.viewerContext.previousRank, 3);
  assert.equal(rows.r2.viewerContext.previousRank, null);

  const detail = await w.req('A', 'GET', '/races/r1');
  assert.equal(detail.status, 200, detail.text);
  assert.equal(detail.json.race.viewerContext.previousRank, 3);
});

test('races rows: finished races carry finalStandings with the viewer place (trophy shelf)', async () => {
  const w = world();
  w.user('A'); w.user('B');
  w.race('r1', 'B', { status: 'completed', completed_at: '2026-01-01T00:00:00.000Z' });
  w.member('r1', 'A');
  w.exec(
    `INSERT INTO race_final_standings (id, race_id, user_id, rank_position, score_value, completed_at, created_at)
     VALUES ('fs1', 'r1', 'B', 1, 100, '2026-01-01T00:00:00.000Z', CURRENT_TIMESTAMP)`,
  );
  w.exec(
    `INSERT INTO race_final_standings (id, race_id, user_id, rank_position, score_value, completed_at, created_at)
     VALUES ('fs2', 'r1', 'A', 2, 60, '2026-01-01T00:00:00.000Z', CURRENT_TIMESTAMP)`,
  );

  const res = await w.req('A', 'GET', '/races');
  assert.equal(res.status, 200, res.text);
  const row = res.json.races.find((r) => r.id === 'r1');
  const me = row.finalStandings.find((s) => s.userId === 'A');
  assert.equal(me.rank, 2);
  assert.equal(me.scoreValue, 60);
  assert.equal(row.finalStandings[0].rank, 1);
});

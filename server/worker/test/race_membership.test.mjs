// Race membership / invite integrity, against the captured PROD schema
// (race_members is UNIQUE(race_id, person_id) there, NOT (race_id, user_id)).
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';

const require = createRequire(import.meta.url);
const app = require('../.tmp-test-dist/index.js').default;
const { signJwt } = require('../.tmp-test-dist/lib/jwt.js');
const { ensureMember } = require('../.tmp-test-dist/domain/raceMembership.js');
const { configFromBody, manualConfigFromBody } = require('../.tmp-test-dist/domain/raceValidation.js');

const JWT_SECRET = 'test-secret';
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
    exec('INSERT INTO profiles (user_id, full_name) VALUES (?, ?)', id, id);
    exec('INSERT INTO people (id, person_key, user_id, display_name) VALUES (?, ?, ?, ?)', `p-${id}`, `user-${id}`, id, id);
  };
  let joinN = 0;
  const member = (raceId, userId, role = 'racer', status = 'active', value = 0) => {
    exec(
      "INSERT INTO race_members (id, race_id, person_id, user_id, role, status, joined_at) VALUES (?, ?, ?, ?, ?, ?, datetime('now', ?))",
      `rm-${raceId}-${userId}`, raceId, `p-${userId}`, userId, role, status, `-${1000 - ++joinN} seconds`,
    );
    exec('INSERT INTO race_progress (id, race_id, user_id, progress_value, progress_percent) VALUES (?, ?, ?, ?, 0)', `rp-${raceId}-${userId}`, raceId, userId, value);
  };
  const race = (id, creator, over = {}) => {
    const r = {
      format: 'most_in_window', race_type: 'most_in_window', status: 'active', visibility: 'public_demo',
      target_value: null, start_at: null, end_at: null, ...over,
    };
    exec(
      `INSERT INTO races (id, creator_id, title, race_type, format, verification_type, status, visibility, public_join_enabled,
         scoring_rule, score_direction, target_value, target_unit, metric, verifier_type, proof_review_mode, start_at, end_at,
         created_at, updated_at)
       VALUES (?, ?, 'Race', ?, ?, 'manual', ?, ?, 1, 'cumulative_sum', 'higher', ?, 'pages', 'reps', 'manual_log', 'auto_accept', ?, ?,
         CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)`,
      id, creator, r.race_type, r.format, r.status, r.visibility, r.target_value, r.start_at, r.end_at,
    );
    member(id, creator, 'creator');
    return id;
  };
  const status = (raceId, userId) => one('SELECT status FROM race_members WHERE race_id = ? AND user_id = ?', raceId, userId)?.status;
  const rank = (raceId, userId) => one('SELECT rank_cache FROM race_progress WHERE race_id = ? AND user_id = ?', raceId, userId)?.rank_cache;
  const mint = async (creator, raceId, extra = {}) => {
    const res = await req(creator, 'POST', '/invites', { kind: 'race_join', targetId: raceId, ...extra });
    assert.equal(res.status, 200, res.text);
    return res.json;
  };
  const flush = async () => { await Promise.all(pending.splice(0)); };
  return { sqlite, env, req, q, one, exec, user, race, member, status, rank, mint, flush };
}

function removedWorld() {
  const w = world();
  w.user('A'); w.user('B'); w.user('C');
  w.race('r1', 'A');
  w.member('r1', 'B', 'racer', 'removed');
  return w;
}

test('A: a creator-removed member cannot rejoin by invite token, join code or direct join', async () => {
  const w = removedWorld();
  const inv = await w.mint('A', 'r1');
  const viaToken = await w.req('B', 'POST', `/invites/${inv.token}/accept`);
  assert.equal(viaToken.status, 403);
  assert.equal(viaToken.json.error, 'You were removed from this race');
  const viaCode = await w.req('B', 'POST', '/races/join-code', { code: inv.code });
  assert.equal(viaCode.status, 403);
  assert.equal(viaCode.json.error, 'You were removed from this race');
  const viaJoin = await w.req('B', 'POST', '/races/r1/join');
  assert.equal(viaJoin.status, 403);
  assert.equal(viaJoin.json.error, 'You were removed from this race');
  assert.equal(w.status('r1', 'B'), 'removed');
  // A refused accept must not burn an invite seat.
  assert.equal(w.one('SELECT use_count FROM invites WHERE token = ?', inv.token).use_count, 0);
});

test('A: leave cannot turn removed into left; explicit creator add may bring a removed member back', async () => {
  const w = removedWorld();
  assert.equal((await w.req('B', 'POST', '/races/r1/leave')).status, 200);
  assert.equal(w.status('r1', 'B'), 'removed');
  const add = await w.req('A', 'POST', '/races/r1/members', { userId: 'B' });
  assert.equal(add.status, 200, add.text);
  assert.equal(w.status('r1', 'B'), 'active');
  // A member who simply left may rejoin on their own.
  w.user('D');
  w.member('r1', 'D', 'racer', 'left');
  assert.equal((await w.req('D', 'POST', '/races/r1/join')).status, 200);
  assert.equal(w.status('r1', 'D'), 'active');
});

test('A: ensureMember reports blocked for removed and never writes', async () => {
  const w = removedWorld();
  const r = await ensureMember(w.env.DB, 'r1', 'B');
  assert.deepEqual(r, { created: false, reactivated: false, blocked: true });
  assert.equal(w.status('r1', 'B'), 'removed');
  const forced = await ensureMember(w.env.DB, 'r1', 'B', 'racer', { allowRemoved: true });
  assert.deepEqual(forced, { created: false, reactivated: true, blocked: false });
});

test('B: capped invite counts once per person, never double-counts, never 410s an existing member', async () => {
  const w = world();
  w.user('A'); w.user('X'); w.user('Y');
  w.race('r1', 'A');
  const inv = await w.mint('A', 'r1', { maxUses: 1 });
  const first = await w.req('X', 'POST', `/invites/${inv.token}/accept`);
  assert.equal(first.status, 200, first.text);
  assert.equal(first.json.alreadyJoined, false);
  const again = await w.req('X', 'POST', `/invites/${inv.token}/accept`);
  assert.equal(again.status, 200, again.text);
  assert.equal(again.json.alreadyJoined, true);
  assert.equal(w.one('SELECT use_count FROM invites WHERE token = ?', inv.token).use_count, 1);
  const late = await w.req('Y', 'POST', `/invites/${inv.token}/accept`);
  assert.equal(late.status, 410);
  assert.equal(late.json.status, 'used');
  assert.equal(w.status('r1', 'Y'), undefined);
  assert.equal(w.one('SELECT COUNT(*) AS n FROM invite_uses').n, 1);
});

test('B: concurrent accepts of the last seat admit exactly one person', async () => {
  const w = world();
  w.user('A'); w.user('X'); w.user('Y');
  w.race('r1', 'A');
  const inv = await w.mint('A', 'r1', { maxUses: 1 });
  const [rx, ry] = await Promise.all([
    w.req('X', 'POST', `/invites/${inv.token}/accept`),
    w.req('Y', 'POST', `/invites/${inv.token}/accept`),
  ]);
  assert.deepEqual([rx.status, ry.status].sort(), [200, 410]);
  assert.equal(w.one('SELECT use_count FROM invites WHERE token = ?', inv.token).use_count, 1);
  assert.equal(w.one("SELECT COUNT(*) AS n FROM race_members WHERE race_id = 'r1' AND role != 'creator'").n, 1);
});

test('C: revoking the link also kills the short code; a later mint issues a fresh code', async () => {
  const w = world();
  w.user('A'); w.user('X'); w.user('Y');
  w.race('r1', 'A');
  const inv = await w.mint('A', 'r1');
  assert.equal((await w.req('A', 'DELETE', `/invites/${inv.token}`)).status, 200);
  assert.equal(w.one('SELECT status FROM race_invites WHERE invite_code = ?', inv.code).status, 'revoked');
  assert.equal((await w.req('X', 'POST', '/races/join-code', { code: inv.code })).status, 404);
  assert.equal((await w.req('X', 'POST', `/invites/${inv.token}/accept`)).status, 410);
  const fresh = await w.mint('A', 'r1');
  assert.notEqual(fresh.token, inv.token);
  assert.notEqual(fresh.code, inv.code);
  assert.equal((await w.req('Y', 'POST', '/races/join-code', { code: fresh.code })).status, 200);
});

test('D: rank_cache is recomputed after join, leave and remove', async () => {
  const w = world();
  w.user('A'); w.user('B'); w.user('C'); w.user('N');
  w.race('r1', 'A');
  w.exec("UPDATE race_progress SET progress_value = 10 WHERE user_id = 'A'");
  w.member('r1', 'B', 'racer', 'active', 5);
  w.member('r1', 'C', 'racer', 'active', 3);
  const inv = await w.mint('A', 'r1');
  assert.equal((await w.req('N', 'POST', `/invites/${inv.token}/accept`)).status, 200);
  assert.equal(w.rank('r1', 'N'), 4, 'newcomer is ranked immediately');
  assert.equal(w.rank('r1', 'A'), 1);
  assert.equal((await w.req('B', 'POST', '/races/r1/leave')).status, 200);
  assert.equal(w.rank('r1', 'C'), 2);
  assert.equal(w.rank('r1', 'N'), 3);
  assert.equal((await w.req('A', 'DELETE', '/races/r1/members/C')).status, 200);
  assert.equal(w.rank('r1', 'N'), 2);
});

test('E: a closed or past-end race has a dead invite preview and cannot be joined', async () => {
  const w = world();
  w.user('A'); w.user('X');
  w.race('open', 'A');
  w.race('future', 'A', { start_at: '2999-01-01T00:00:00.000Z' });
  w.race('ended', 'A', { end_at: '2000-01-01T00:00:00.000Z' });
  w.race('done', 'A', { status: 'completed' });
  const tokens = {};
  for (const id of ['open', 'future', 'ended', 'done']) tokens[id] = await w.mint('A', id);
  assert.equal((await w.req('X', 'GET', `/invites/${tokens.open.token}`)).status, 200);
  assert.equal((await w.req('X', 'GET', `/invites/${tokens.future.token}`)).status, 200, 'not yet started is still joinable');
  for (const id of ['ended', 'done']) {
    const prev = await w.req('X', 'GET', `/invites/${tokens[id].token}`);
    assert.equal(prev.status, 410, id);
    assert.equal(prev.json.status, 'closed');
    assert.equal((await w.req('X', 'POST', `/invites/${tokens[id].token}/accept`)).status, 409, id);
    assert.equal((await w.req('X', 'POST', '/races/join-code', { code: tokens[id].code })).status, 400, id);
    assert.equal((await w.req('X', 'POST', `/races/${id}/join`)).status, 400, id);
    assert.equal(w.status(id, 'X'), undefined);
  }
  assert.equal((await w.req('X', 'POST', '/races/future/join')).status, 200);
});

test('F: double-tap joins never 500 and produce one membership, one event, one notification', async () => {
  const w = world();
  w.user('A'); w.user('X'); w.user('Z');
  w.race('r1', 'A');
  const inv = await w.mint('A', 'r1');
  const taps = await Promise.all([
    w.req('X', 'POST', `/invites/${inv.token}/accept`),
    w.req('X', 'POST', `/invites/${inv.token}/accept`),
    w.req('X', 'POST', `/invites/${inv.token}/accept`),
  ]);
  assert.deepEqual(taps.map((t) => t.status), [200, 200, 200]);
  assert.equal(taps.filter((t) => t.json.alreadyJoined === false).length, 1);
  assert.equal(w.one("SELECT COUNT(*) AS n FROM race_members WHERE user_id = 'X'").n, 1);
  assert.equal(w.one("SELECT COUNT(*) AS n FROM race_progress WHERE user_id = 'X'").n, 1);
  assert.equal(w.one("SELECT COUNT(*) AS n FROM race_events WHERE event_type = 'race_joined' AND subject_user_id = 'X'").n, 1);
  const codeTaps = await Promise.all([
    w.req('Z', 'POST', '/races/join-code', { code: inv.code }),
    w.req('Z', 'POST', '/races/join-code', { code: inv.code }),
  ]);
  assert.deepEqual(codeTaps.map((t) => t.status), [200, 200]);
  assert.equal(w.one("SELECT COUNT(*) AS n FROM race_members WHERE user_id = 'Z'").n, 1);
  await w.flush();
  // A leave + rejoin is a real (re)join and is reported as such.
  await w.req('X', 'POST', '/races/r1/leave');
  const back = await w.req('X', 'POST', `/invites/${inv.token}/accept`);
  assert.equal(back.status, 200);
  assert.equal(back.json.alreadyJoined, false);
  assert.equal(w.status('r1', 'X'), 'active');
});

test('G: window / attempt races never keep a placeholder target', async () => {
  const preset = configFromBody({ activityId: 'push_ups', metric: 'reps', format: 'most_in_window', targetValue: 100, finishLineAt: '2999-01-01T00:00:00Z' });
  assert.equal(preset.error, undefined);
  assert.equal(preset.targetValue, null);
  const goal = configFromBody({ activityId: 'push_ups', metric: 'reps', format: 'first_to_goal', targetValue: 25 });
  assert.equal(goal.targetValue, 25);
  assert.equal(manualConfigFromBody({ proofRequirement: 'manual', format: 'first_to_goal' }).error, 'A goal amount is required.');
  const manualWindow = manualConfigFromBody({ proofRequirement: 'manual', format: 'most_in_window', targetValue: 100 });
  assert.equal(manualWindow.targetValue, null);
  assert.equal(manualConfigFromBody({ proofRequirement: 'manual', format: 'most_in_window' }).targetValue, null);
});

test('G: PATCH on a window race stores no target; a goal race keeps it; arena hides legacy placeholder', async () => {
  const w = world();
  w.user('A');
  w.race('win', 'A', { target_value: 100 });
  w.race('goal', 'A', { format: 'first_to_goal', race_type: 'first_to_goal', target_value: 10 });
  assert.equal((await w.req('A', 'PATCH', '/races/win', { targetValue: 50 })).status, 200);
  assert.equal(w.one("SELECT target_value AS t FROM races WHERE id = 'win'").t, null);
  assert.equal((await w.req('A', 'PATCH', '/races/goal', { targetValue: 20 })).status, 200);
  assert.equal(w.one("SELECT target_value AS t FROM races WHERE id = 'goal'").t, 20);
  // Legacy row that already holds a placeholder target.
  w.race('legacy', 'A', { target_value: 77 });
  const arena = await w.req('A', 'GET', '/arena');
  assert.equal(arena.status, 200, arena.text);
  assert.ok(/0 \/ 20 /.test(arena.text), 'goal race keeps its finish line');
  assert.ok(!/\/ 77 /.test(arena.text) && !/\/ 100 /.test(arena.text), 'placeholder target must not surface in the arena');
});

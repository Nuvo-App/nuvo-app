// v13 crew additions (migration 0049): crew identity fields (bio/color/icon)
// on PATCH + reads, additive list/detail fields (ownerName, memberPreviews,
// myRankWeek, nextRecurring, stats, joinRequests, muted, battle), points
// standings, crew board (discover), non-member preview, join requests with
// admin approval + race pull-in, crew mutes, recurring race CRUD + the
// idempotent cron sweep, squad reports, request mutuals, and the
// badge_earned feed item. Prod-schema SQLite harness like v13_profile.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';

const require = createRequire(import.meta.url);
const app = require('../.tmp-test-dist/index.js').default;
const { signJwt } = require('../.tmp-test-dist/lib/jwt.js');
const { reconcileProgression } = require('../.tmp-test-dist/domain/progression.js');
const { sweepRecurringSquadRaces } = require('../.tmp-test-dist/domain/squadRecurring.js');

const JWT_SECRET = 'test-secret';
const REVIEWER_PASSWORD = 'test-review-pass';
const root = new URL('..', import.meta.url);
const SCHEMA = [
  readFileSync(new URL('test/fixtures/prod_schema_2026-09-28.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0042_achievements.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0043_proof_votes.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0044_custom_verifier_seed.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0045_teach_sessions.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0046_squads.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0047_reconcile_prod.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0048_v13_profile.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0049_v13_crews.sql', root), 'utf8'),
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

  const race = (id, creator, over = {}) => {
    const r = {
      title: 'Race', race_type: 'most_in_window', format: 'most_in_window', verification_type: 'manual',
      status: 'active', visibility: 'crew_only', scoring_rule: 'cumulative_sum', score_direction: 'higher',
      target_value: 100, target_unit: 'reps', metric: 'reps', activity_id: null, movement_type: null,
      verifier_type: 'manual_log', proof_review_mode: 'auto_accept', end_at: null, ...over,
    };
    exec(
      `INSERT INTO races (id, creator_id, title, race_type, format, verification_type, status, visibility, scoring_rule,
         score_direction, target_value, target_unit, metric, activity_id, movement_type, verifier_type, proof_review_mode,
         end_at, completed_at, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)`,
      id, creator, r.title, r.race_type, r.format, r.verification_type, r.status, r.visibility, r.scoring_rule,
      r.score_direction, r.target_value, r.target_unit, r.metric, r.activity_id, r.movement_type, r.verifier_type,
      r.proof_review_mode, r.end_at, r.status === 'completed' ? r.completed_at ?? new Date().toISOString() : null,
    );
    member(id, creator, 'creator');
    return id;
  };

  let joinN = 0;
  const member = (raceId, userId, role = 'racer', status = 'active') => {
    exec(
      "INSERT INTO race_members (id, race_id, person_id, user_id, role, status, joined_at) VALUES (?, ?, ?, ?, ?, ?, datetime('now', ?))",
      `rm-${raceId}-${userId}-${++joinN}`, raceId, `p-${userId}`, userId, role, status, `-${1000 - joinN} seconds`,
    );
    exec('INSERT INTO race_progress (id, race_id, user_id, progress_value, progress_percent) VALUES (?, ?, ?, 0, 0)', `rp-${raceId}-${userId}`, raceId, userId);
  };

  /** A crew with the owner + extra members; owner is 'owner' role. */
  const squad = async (id, ownerId, name = 'Crew', memberIds = []) => {
    exec('INSERT INTO squads (id, name, join_code, owner_id, created_at) VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)', id, name, `CODE-${id}`, ownerId);
    exec("INSERT INTO squad_members (id, squad_id, user_id, role, status, joined_at) VALUES (?, ?, ?, 'owner', 'active', datetime('now','-10 days'))", `sm-${id}-${ownerId}`, id, ownerId);
    for (const [i, m] of memberIds.entries()) {
      exec("INSERT INTO squad_members (id, squad_id, user_id, role, status, joined_at) VALUES (?, ?, ?, 'member', 'active', datetime('now', ?))", `sm-${id}-${m}`, id, m, `-${9 - i} days`);
    }
    return id;
  };

  const squadMember = (squadId, userId, role = 'member', status = 'active', days = '-5 days') => {
    exec('INSERT INTO squad_members (id, squad_id, user_id, role, status, joined_at) VALUES (?, ?, ?, ?, ?, datetime(\'now\', ?))', `sm-${squadId}-${userId}-${status}-${role}`, squadId, userId, role, status, days);
  };

  const linkRace = (squadId, raceId, by = 'A') =>
    exec('INSERT INTO squad_races (id, squad_id, race_id, created_by, created_at) VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)', `sr-${squadId}-${raceId}`, squadId, raceId, by);

  /** Active friend link both directions — what transitionCrew's mirror writes. */
  const friend = (a, b, daysAgo = 0) => {
    for (const [u, v] of [[a, b], [b, a]]) {
      exec(
        `INSERT INTO crew_connections (id, user_id, crew_user_id, status, requested_by, created_at, updated_at)
         VALUES (?, ?, ?, 'active', ?, datetime('now', ?), datetime('now', ?))`,
        `cc-${u}-${v}`, u, v, a, `-${daysAgo} days`, `-${daysAgo} days`,
      );
    }
  };

  /** A move_log row — verified proof of `value` by default, `daysAgo` back. */
  let moveN = 0;
  const proof = (userId, raceId, { daysAgo = 0, value = 1, status = 'verified' } = {}) => {
    const id = `ml-${++moveN}`;
    exec(
      `INSERT INTO move_logs (id, race_id, user_id, source, value, unit, status, created_at)
       VALUES (?, ?, ?, 'manual', ?, 'reps', ?, datetime('now', ?))`,
      id, raceId, userId, value, status, `-${daysAgo} days`,
    );
    return id;
  };

  const raceEvent = (raceId, actorId, type = 'participant_finished', subjectId = null) => {
    const id = `ev-${raceId}-${actorId}-${Math.random().toString(36).slice(2, 8)}`;
    exec(
      'INSERT INTO race_events (id, race_id, event_type, actor_user_id, subject_user_id, created_at) VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)',
      id, raceId, type, actorId, subjectId ?? actorId,
    );
    return id;
  };

  const flush = async () => { await Promise.all(pending.splice(0)); };

  return { sqlite, db, r2, env, ctx, pending, req, q, one, exec, user, race, member, squad, squadMember, linkRace, friend, proof, raceEvent, flush };
}

const jsonOk = (r, status = 200) => {
  assert.equal(r.status, status, `${r.status} ${r.text}`);
  assert.ok(r.json, `JSON body expected: ${r.text}`);
  return r.json;
};

const todayUtc = () => new Date().getUTCDay();

// ── Schema ──────────────────────────────────────────────────────────────────

test('0049: squad columns + recurring/opt-out/activity tables exist', async () => {
  const w = world();
  const sqCols = w.q('PRAGMA table_info(squads)').map((c) => c.name);
  for (const c of ['bio', 'color_key', 'icon_key']) assert.ok(sqCols.includes(c), `squads.${c} missing`);
  const smCols = w.q('PRAGMA table_info(squad_members)').map((c) => c.name);
  assert.ok(smCols.includes('muted_at'), 'squad_members.muted_at missing');
  const tables = w.q("SELECT name FROM sqlite_master WHERE type='table'").map((t) => t.name);
  for (const t of ['squad_recurring_races', 'squad_recurring_optouts', 'crew_activity']) {
    assert.ok(tables.includes(t), `${t} missing`);
  }
});

// ── PATCH metadata ──────────────────────────────────────────────────────────

test('PATCH crew identity: bio/colorKey/iconKey write, validate, and read back', async () => {
  const w = world();
  w.user('A', { name: 'Alice' }); w.user('B', { name: 'Bob' }); w.user('X', { name: 'X' });
  await w.squad('s1', 'A', 'Morning Crew', ['B']);

  assert.equal((await w.req('B', 'PATCH', '/squads/s1', { bio: 'hi' })).status, 403);
  assert.equal((await w.req('X', 'PATCH', '/squads/s1', { bio: 'hi' })).status, 404);
  assert.equal((await w.req('A', 'PATCH', '/squads/s1', {})).status, 400);
  assert.equal((await w.req('A', 'PATCH', '/squads/s1', { bio: 'x'.repeat(121) })).status, 400);
  assert.equal((await w.req('A', 'PATCH', '/squads/s1', { colorKey: 'purple' })).status, 400);
  assert.equal((await w.req('A', 'PATCH', '/squads/s1', { iconKey: 'i'.repeat(33) })).status, 400);

  const ok = jsonOk(await w.req('A', 'PATCH', '/squads/s1', {
    bio: '  Dawn racers only.  ', colorKey: 'coral', iconKey: 'bolt',
  }));
  assert.equal(ok.bio, 'Dawn racers only.');
  assert.equal(ok.colorKey, 'coral');
  assert.equal(ok.iconKey, 'bolt');

  const detail = jsonOk(await w.req('B', 'GET', '/squads/s1'));
  assert.equal(detail.squad.bio, 'Dawn racers only.');
  assert.equal(detail.squad.colorKey, 'coral');
  assert.equal(detail.squad.iconKey, 'bolt');
  assert.ok(detail.squad.createdAt);
  assert.equal(detail.squad.battle, null);

  // Clearable with null; name still renames alongside.
  const cleared = jsonOk(await w.req('A', 'PATCH', '/squads/s1', { bio: null, colorKey: null, iconKey: null, name: 'Renamed' }));
  assert.equal(cleared.bio, null);
  assert.equal(cleared.name, 'Renamed');
});

// ── GET /squads additive card fields ─────────────────────────────────────────

test('GET /squads: ownerName, memberPreviews, myRankWeek, color/icon, nextRecurring', async () => {
  const w = world();
  for (const u of ['A', 'B', 'C']) w.user(u, { name: `Name ${u}` });
  await w.squad('s1', 'A', 'Crew One', ['B', 'C']);
  jsonOk(await w.req('A', 'PATCH', '/squads/s1', { colorKey: 'mint', iconKey: 'leaf' }));
  w.exec("INSERT INTO squad_recurring_races (id, squad_id, title, weekday, created_by) VALUES ('rr1', 's1', 'Weekly', ?, 'A')", todayUtc());

  const list = jsonOk(await w.req('B', 'GET', '/squads'));
  const row = list.squads.find((s) => s.id === 's1');
  assert.equal(row.ownerName, 'Name A');
  assert.equal(row.colorKey, 'mint');
  assert.equal(row.iconKey, 'leaf');
  assert.equal(row.memberCount, 3);
  assert.ok(row.memberPreviews.length <= 5);
  assert.equal(row.memberPreviews.length, 3);
  assert.deepEqual(row.memberPreviews[0], { id: 'A', displayName: 'Name A', profilePhotoUrl: null });
  assert.equal(row.myRankWeek, null, 'no linked races yet → no rank');
  assert.equal(row.nextRecurring.id, 'rr1');
  assert.equal(row.nextRecurring.title, 'Weekly');
  assert.equal(row.nextRecurring.weekday, todayUtc());
  assert.ok(row.nextRecurring.nextAt);

  // A proof in a linked crew race ranks the scorer first this week.
  w.race('r1', 'A');
  w.linkRace('s1', 'r1');
  w.proof('B', 'r1', { value: 7 });
  const ranked = jsonOk(await w.req('B', 'GET', '/squads'));
  assert.equal(ranked.squads.find((s) => s.id === 's1').myRankWeek, 1);
  const rankedA = jsonOk(await w.req('A', 'GET', '/squads'));
  assert.equal(rankedA.squads.find((s) => s.id === 's1').myRankWeek, 2);
});

// ── GET /squads/:id detail additions ─────────────────────────────────────────

test('GET /squads/:id: stats (wins/races/streakDays), recurring, muted, joinRequests hidden from members', async () => {
  const w = world();
  for (const u of ['A', 'B', 'C', 'R']) w.user(u, { name: u });
  await w.squad('s1', 'A', 'Crew', ['B', 'C']);
  w.exec("INSERT INTO squad_members (id, squad_id, user_id, role, status, joined_at) VALUES ('smreq', 's1', 'R', 'member', 'requested', CURRENT_TIMESTAMP)");

  // A finished linked race won by a member → wins=1. Two proofs on
  // consecutive days → streakDays 2. One more on a different day still 2.
  w.race('r1', 'A', { status: 'completed', });
  w.exec("UPDATE races SET winner_user_id = 'B' WHERE id = 'r1'");
  w.linkRace('s1', 'r1');
  w.proof('B', 'r1', { value: 3, daysAgo: 1 });
  w.proof('C', 'r1', { value: 2, daysAgo: 0 });
  w.exec("INSERT INTO squad_recurring_races (id, squad_id, title, weekday, created_by) VALUES ('rr1', 's1', 'Weekly', ?, 'A')", todayUtc());

  const detail = jsonOk(await w.req('B', 'GET', '/squads/s1'));
  assert.equal(detail.squad.stats.races, 1);
  assert.equal(detail.squad.stats.wins, 1);
  assert.equal(detail.squad.stats.streakDays, 2);
  assert.equal(detail.squad.muted, false);
  assert.equal(detail.recurring.length, 1);
  assert.equal(detail.recurring[0].title, 'Weekly');
  assert.equal(detail.recurring[0].autoJoin, true);
  assert.deepEqual(detail.joinRequests, [], 'plain member never sees pending requests');

  const ownerView = jsonOk(await w.req('A', 'GET', '/squads/s1'));
  assert.equal(ownerView.joinRequests.length, 1);
  assert.equal(ownerView.joinRequests[0].userId, 'R');
  assert.equal(ownerView.joinRequests[0].displayName, 'R');
});

// ── Standings ───────────────────────────────────────────────────────────────

test('standings: week window vs all; points = verified proof inside crew races', async () => {
  const w = world();
  for (const u of ['A', 'B', 'C', 'X']) w.user(u, { name: u });
  await w.squad('s1', 'A', 'Crew', ['B', 'C']);
  w.race('r1', 'A');
  w.linkRace('s1', 'r1');
  // This week: B=10, C=5. All-time adds B's +40 ten days back.
  w.proof('B', 'r1', { value: 10 });
  w.proof('C', 'r1', { value: 5 });
  w.proof('B', 'r1', { value: 40, daysAgo: 10 });
  w.proof('B', 'r1', { value: 99, status: 'pending' }); // unverified never counts
  w.race('rX', 'X'); // outside the crew: B's proof there must not leak in
  w.member('rX', 'B');
  w.proof('B', 'rX', { value: 77 });

  assert.equal((await w.req('X', 'GET', '/squads/s1/standings')).status, 403);

  const week = jsonOk(await w.req('C', 'GET', '/squads/s1/standings?period=week'));
  assert.equal(week.period, 'week');
  assert.equal(week.standings.length, 3);
  const [b, c, a] = week.standings;
  assert.deepEqual(
    { userId: b.userId, points: b.points, rank: b.rank },
    { userId: 'B', points: 10, rank: 1 },
  );
  assert.deepEqual(
    { userId: c.userId, points: c.points, rank: c.rank },
    { userId: 'C', points: 5, rank: 2 },
  );
  assert.deepEqual(
    { userId: a.userId, points: a.points, rank: a.rank },
    { userId: 'A', points: 0, rank: 3 },
  );
  assert.equal(c.isMe, true);
  assert.equal(b.isMe, false);
  assert.equal(b.role, 'member');
  assert.ok(b.displayName);

  const all = jsonOk(await w.req('C', 'GET', '/squads/s1/standings?period=all'));
  assert.equal(all.standings.find((s) => s.userId === 'B').points, 50);

  const weekB = jsonOk(await w.req('B', 'GET', '/squads/s1/standings'));
  assert.equal(weekB.standings.find((s) => s.userId === 'B').isMe, true);
});

// ── Discover ────────────────────────────────────────────────────────────────

test('discover: crews with a friend inside; own/pending/blocked crews hidden', async () => {
  const w = world();
  for (const u of ['A', 'B', 'C', 'D', 'E', 'F']) w.user(u, { name: u });
  // B and C are A's friends. B is inside s2 (owner D), C inside s3 (owner E).
  w.friend('A', 'B'); w.friend('A', 'C');
  await w.squad('s2', 'D', 'B Crew', ['B']);
  await w.squad('s3', 'E', 'C Crew', ['C']);
  // s4: no friend inside → never surfaces. s5: A already a member.
  await w.squad('s4', 'F', 'Nobody I Know', ['D']);
  await w.squad('s5', 'D', 'My Crew', ['A', 'B']);

  const found = jsonOk(await w.req('A', 'GET', '/squads/discover'));
  const ids = found.squads.map((s) => s.id);
  assert.deepEqual(ids.sort(), ['s2', 's3']);
  const s2 = found.squads.find((s) => s.id === 's2');
  assert.equal(s2.name, 'B Crew');
  assert.equal(s2.memberCount, 2);
  assert.equal(s2.ownerName, 'D');
  assert.ok(s2.memberPreviews.length <= 5);

  // A pending request hides the crew from the board.
  jsonOk(await w.req('A', 'POST', '/squads/s3/join-request'));
  const after = jsonOk(await w.req('A', 'GET', '/squads/discover'));
  assert.deepEqual(after.squads.map((s) => s.id), ['s2']);

  // Blocking the only friend inside hides the crew (either direction).
  w.exec("INSERT INTO blocked_users (id, user_id, blocked_user_id, created_at) VALUES ('bl1', 'A', 'B', CURRENT_TIMESTAMP)");
  const blocked = jsonOk(await w.req('A', 'GET', '/squads/discover'));
  assert.deepEqual(blocked.squads, []);
});

// ── Preview ──────────────────────────────────────────────────────────────────

test('preview: non-member card + viewerStatus transitions', async () => {
  const w = world();
  for (const u of ['A', 'B', 'C']) w.user(u, { name: u });
  await w.squad('s1', 'A', 'Sneaky Crew', ['B']);
  jsonOk(await w.req('A', 'PATCH', '/squads/s1', { colorKey: 'sky', iconKey: 'wave' }));

  const none = jsonOk(await w.req('C', 'GET', '/squads/s1/preview'));
  assert.equal(none.squad.name, 'Sneaky Crew');
  assert.equal(none.squad.colorKey, 'sky');
  assert.equal(none.squad.iconKey, 'wave');
  assert.equal(none.squad.memberCount, 2);
  assert.equal(none.squad.ownerName, 'A');
  assert.equal(none.squad.memberPreviews.length, 2);
  assert.equal(none.squad.viewerStatus, 'none');

  jsonOk(await w.req('C', 'POST', '/squads/s1/join-request'));
  const requested = jsonOk(await w.req('C', 'GET', '/squads/s1/preview'));
  assert.equal(requested.squad.viewerStatus, 'requested');

  jsonOk(await w.req('A', 'POST', '/squads/s1/join-requests/C/approve'));
  const memberView = jsonOk(await w.req('C', 'GET', '/squads/s1/preview'));
  assert.equal(memberView.squad.viewerStatus, 'member');
});

// ── Join requests ────────────────────────────────────────────────────────────

test('join requests: request → admin notified → approve pulls into open races; decline', async () => {
  const w = world();
  for (const u of ['A', 'B', 'C', 'D']) w.user(u, { name: u });
  await w.squad('s1', 'A', 'Crew', ['B']);
  w.race('r1', 'A');
  w.linkRace('s1', 'r1');
  w.member('r1', 'B'); // an existing member is already inside the crew race

  // Requester asks; owner gets a squad_join_request inbox row.
  const reqd = jsonOk(await w.req('C', 'POST', '/squads/s1/join-request'));
  assert.equal(reqd.status, 'requested');
  assert.equal(w.one("SELECT status FROM squad_members WHERE squad_id = 's1' AND user_id = 'C'").status, 'requested');
  const note = w.one("SELECT category, title FROM notifications WHERE user_id = 'A' AND category = 'squad_join_request'");
  assert.ok(note, 'owner notified of the request');
  assert.match(note.title, /wants to join Crew/);
  // Idempotent re-request.
  const again = jsonOk(await w.req('C', 'POST', '/squads/s1/join-request'));
  assert.equal(again.status, 'requested');
  assert.equal(w.one("SELECT COUNT(*) AS n FROM notifications WHERE user_id = 'A' AND category = 'squad_join_request'").n, 1, 'deduped');

  // A plain member and an outsider cannot approve.
  assert.equal((await w.req('B', 'POST', '/squads/s1/join-requests/C/approve')).status, 403);
  assert.equal((await w.req('D', 'POST', '/squads/s1/join-requests/C/approve')).status, 403);

  // Approve → active member + pulled into the open crew race.
  jsonOk(await w.req('A', 'POST', '/squads/s1/join-requests/C/approve'));
  assert.equal(w.one("SELECT status FROM squad_members WHERE squad_id = 's1' AND user_id = 'C'").status, 'active');
  assert.equal(
    w.one("SELECT status FROM race_members WHERE race_id = 'r1' AND user_id = 'C'").status,
    'active',
    'approved member lands in the crew race like a code-join',
  );
  assert.ok(w.one("SELECT 1 AS one FROM notifications WHERE user_id = 'C' AND category = 'squad_join_approved'").one);

  // A second approval is a no-op.
  jsonOk(await w.req('A', 'POST', '/squads/s1/join-requests/C/approve'));
});

test('join requests: decline drops the request; re-request works; removed stays out', async () => {
  const w = world();
  for (const u of ['A', 'B', 'C']) w.user(u, { name: u });
  await w.squad('s1', 'A', 'Crew', ['B']);

  assert.equal((await w.req('A', 'POST', '/squads/s1/join-requests/C/decline')).status, 404);
  jsonOk(await w.req('C', 'POST', '/squads/s1/join-request'));
  jsonOk(await w.req('A', 'POST', '/squads/s1/join-requests/C/decline'));
  assert.equal(w.one("SELECT status FROM squad_members WHERE squad_id = 's1' AND user_id = 'C'").status, 'left');
  // Can ask again after a decline.
  jsonOk(await w.req('C', 'POST', '/squads/s1/join-request'));
  assert.equal(w.one("SELECT status FROM squad_members WHERE squad_id = 's1' AND user_id = 'C'").status, 'requested');

  // A removed member cannot request their way back.
  await w.req('A', 'DELETE', '/squads/s1/members/B');
  assert.equal((await w.req('B', 'POST', '/squads/s1/join-request')).status, 403);
});

// ── Relaxed race linking ────────────────────────────────────────────────────

test('any active member can link their own race; other races stay creator-gated', async () => {
  const w = world();
  for (const u of ['A', 'B', 'C', 'X']) w.user(u, { name: u });
  await w.squad('s1', 'A', 'Crew', ['B', 'C']);
  w.race('r1', 'B'); // B created this race before linking
  const add = jsonOk(await w.req('B', 'POST', '/squads/s1/races', { raceId: 'r1' }));
  assert.equal(add.raceId, 'r1');
  assert.equal(w.one("SELECT 1 AS one FROM squad_races WHERE race_id = 'r1'").one, 1);
  // The crew was pulled in.
  for (const u of ['A', 'C']) {
    assert.equal(w.one("SELECT status FROM race_members WHERE race_id = 'r1' AND user_id = ?", u).status, 'active');
  }
  // C cannot link B's race — it is not theirs.
  w.race('r2', 'B');
  assert.equal((await w.req('C', 'POST', '/squads/s1/races', { raceId: 'r2' })).status, 403);
  // An outsider cannot link at all.
  assert.equal((await w.req('X', 'POST', '/squads/s1/races', { raceId: 'r2' })).status, 404);
});

// ── Crew mute ────────────────────────────────────────────────────────────────

test('crew mute: suppresses notifications for that member only; seats still land', async () => {
  const w = world();
  for (const u of ['A', 'B', 'C', 'D']) w.user(u, { name: u });
  await w.squad('s1', 'A', 'Crew', ['B', 'C']);

  jsonOk(await w.req('B', 'POST', '/squads/s1/mute', { on: true }));
  assert.equal(w.one("SELECT muted_at IS NOT NULL AS m FROM squad_members WHERE squad_id = 's1' AND user_id = 'B'").m, 1);
  const detail = jsonOk(await w.req('B', 'GET', '/squads/s1'));
  assert.equal(detail.squad.muted, true);
  assert.equal(jsonOk(await w.req('C', 'GET', '/squads/s1')).squad.muted, false);

  // A links a race: muted B still joins the race but gets no race_invite row;
  // C is told normally.
  w.race('r1', 'A');
  jsonOk(await w.req('A', 'POST', '/squads/s1/races', { raceId: 'r1' }));
  assert.equal(w.one("SELECT status FROM race_members WHERE race_id = 'r1' AND user_id = 'B'").status, 'active');
  assert.equal(w.one("SELECT COUNT(*) AS n FROM notifications WHERE user_id = 'B' AND category = 'race_invite'").n, 0);
  assert.equal(w.one("SELECT COUNT(*) AS n FROM notifications WHERE user_id = 'C' AND category = 'race_invite'").n, 1);

  // Muted admins don't get join-request pings either — D is an outsider here.
  jsonOk(await w.req('A', 'POST', '/squads/s1/mute', { on: true }));
  jsonOk(await w.req('D', 'POST', '/squads/s1/join-request'));
  assert.equal(w.one("SELECT COUNT(*) AS n FROM notifications WHERE user_id = 'A' AND category = 'squad_join_request'").n, 0);

  // Unmute restores delivery.
  jsonOk(await w.req('B', 'POST', '/squads/s1/mute', { on: false }));
  assert.equal(w.one("SELECT muted_at FROM squad_members WHERE squad_id = 's1' AND user_id = 'B'").muted_at, null);
});

// ── Recurring CRUD ───────────────────────────────────────────────────────────

test('recurring CRUD: admin only, validates, detail exposes per-viewer autoJoin', async () => {
  const w = world();
  for (const u of ['A', 'B', 'C']) w.user(u, { name: u });
  await w.squad('s1', 'A', 'Crew', ['B', 'C']);

  assert.equal((await w.req('B', 'POST', '/squads/s1/recurring', { title: 'Pushup Monday', weekday: 1 })).status, 403);
  assert.equal((await w.req('A', 'POST', '/squads/s1/recurring', { title: 'x', weekday: 1 })).status, 400);
  assert.equal((await w.req('A', 'POST', '/squads/s1/recurring', { title: 'Pushup Monday', weekday: 7 })).status, 400);
  const created = jsonOk(await w.req('A', 'POST', '/squads/s1/recurring', {
    title: 'Pushup Monday', activityId: 'push_ups', raceType: 'most_in_window',
    targetValue: 100, targetUnit: 'reps', weekday: 1,
  }), 201);
  const rid = created.recurring.id;
  assert.equal(created.recurring.weekday, 1);
  assert.equal(created.recurring.autoJoin, true);

  const detail = jsonOk(await w.req('B', 'GET', '/squads/s1'));
  assert.equal(detail.recurring.length, 1);
  assert.equal(detail.recurring[0].id, rid);
  assert.ok(Array.isArray(detail.recurring[0].autoJoinPreviews));

  // Member opts out → their serialized row flips.
  jsonOk(await w.req('B', 'POST', `/squads/s1/recurring/${rid}/auto-join`, { on: false }));
  const optedOut = jsonOk(await w.req('B', 'GET', '/squads/s1'));
  assert.equal(optedOut.recurring[0].autoJoin, false);
  const stillIn = jsonOk(await w.req('C', 'GET', '/squads/s1'));
  assert.equal(stillIn.recurring[0].autoJoin, true);
  assert.equal(w.one('SELECT COUNT(*) AS n FROM squad_recurring_optouts WHERE recurring_id = ?', rid).n, 1);
  jsonOk(await w.req('B', 'POST', `/squads/s1/recurring/${rid}/auto-join`, { on: true }));
  assert.equal(jsonOk(await w.req('B', 'GET', '/squads/s1')).recurring[0].autoJoin, true);

  // PATCH: owner edits; member cannot.
  assert.equal((await w.req('B', 'PATCH', `/squads/s1/recurring/${rid}`, { weekday: 3 })).status, 403);
  const patched = jsonOk(await w.req('A', 'PATCH', `/squads/s1/recurring/${rid}`, { title: 'Squat Tuesday', weekday: 2, active: false }));
  assert.equal(patched.recurring.title, 'Squat Tuesday');
  assert.equal(patched.recurring.weekday, 2);
  assert.equal(patched.recurring.active, false);

  // DELETE: owner only.
  assert.equal((await w.req('B', 'DELETE', `/squads/s1/recurring/${rid}`)).status, 403);
  jsonOk(await w.req('A', 'DELETE', `/squads/s1/recurring/${rid}`));
  assert.equal(w.one('SELECT COUNT(*) AS n FROM squad_recurring_races WHERE id = ?', rid).n, 0);
  assert.equal(jsonOk(await w.req('A', 'GET', '/squads/s1')).recurring.length, 0);
});

// ── Cron sweep ───────────────────────────────────────────────────────────────

async function sweep(w) {
  const hold = [];
  const n = await sweepRecurringSquadRaces(w.env, (p) => hold.push(p));
  await Promise.all(hold);
  return n;
}

test('cron sweep: spawns due recurring race, auto-joins members, idempotent', async () => {
  const w = world();
  for (const u of ['A', 'B', 'C']) w.user(u, { name: u });
  await w.squad('s1', 'A', 'Crew', ['B', 'C']);
  w.exec(
    "INSERT INTO squad_recurring_races (id, squad_id, title, activity_id, race_type, target_value, target_unit, weekday, created_by) VALUES ('rr1', 's1', 'Daily Grind', 'push_ups', 'most_in_window', 100, 'reps', ?, 'A')",
    todayUtc(),
  );
  // Not due today — different weekday.
  w.exec(
    "INSERT INTO squad_recurring_races (id, squad_id, title, weekday, created_by) VALUES ('rr-later', 's1', 'Tomorrow', ?, 'A')",
    (todayUtc() + 1) % 7,
  );

  assert.equal(await sweep(w), 1, 'one due definition spawns');

  const raceRow = w.one("SELECT r.*, sr.squad_id FROM races r JOIN squad_races sr ON sr.race_id = r.id WHERE sr.squad_id = 's1'");
  assert.ok(raceRow, 'race created and linked to the crew');
  assert.equal(raceRow.title, 'Daily Grind');
  assert.equal(raceRow.creator_id, 'A');
  assert.equal(raceRow.status, 'active');
  assert.equal(raceRow.activity_id, 'push_ups');
  assert.equal(raceRow.recurrence, 'weekly');
  // Every active member was auto-joined.
  for (const u of ['A', 'B', 'C']) {
    assert.equal(
      w.one("SELECT status FROM race_members WHERE race_id = ? AND user_id = ?", raceRow.id, u).status,
      'active',
      `${u} auto-joined`,
    );
  }
  assert.ok(w.one("SELECT last_spawned_at FROM squad_recurring_races WHERE id = 'rr1'").last_spawned_at);
  assert.equal(w.one("SELECT last_spawned_at FROM squad_recurring_races WHERE id = 'rr-later'").last_spawned_at, null);
  // The spawn invites land as notifications (in-app; push is dormant in tests).
  assert.ok(w.one("SELECT COUNT(*) AS n FROM notifications WHERE category = 'race_invite' AND user_id = 'B'").n >= 1);

  // Idempotent: a second sweep the same UTC day is a no-op.
  assert.equal(await sweep(w), 0);
  assert.equal(w.one("SELECT COUNT(*) AS n FROM races r JOIN squad_races sr ON sr.race_id = r.id WHERE sr.squad_id = 's1'").n, 1);
});

test('cron sweep: opt-outs and muted members behave; creator fallback when template author left', async () => {
  const w = world();
  for (const u of ['A', 'B', 'C', 'D']) w.user(u, { name: u });
  await w.squad('s1', 'A', 'Crew', ['B', 'C', 'D']);
  w.exec(
    "INSERT INTO squad_recurring_races (id, squad_id, title, weekday, created_by) VALUES ('rr1', 's1', 'Daily', ?, 'B')",
    todayUtc(),
  );
  // B (the template creator) left → race ownership falls back to crew owner A.
  w.exec("UPDATE squad_members SET status = 'left' WHERE squad_id = 's1' AND user_id = 'B'");
  // C opted out; D muted the crew.
  w.exec("INSERT INTO squad_recurring_optouts (recurring_id, user_id) VALUES ('rr1', 'C')");
  w.exec("UPDATE squad_members SET muted_at = CURRENT_TIMESTAMP WHERE squad_id = 's1' AND user_id = 'D'");

  assert.equal(await sweep(w), 1);
  const raceRow = w.one("SELECT r.* FROM races r JOIN squad_races sr ON sr.race_id = r.id WHERE sr.squad_id = 's1'");
  assert.equal(raceRow.creator_id, 'A', 'left template creator → owner stands in');
  assert.equal(w.one("SELECT 1 AS one FROM race_members WHERE race_id = ? AND user_id = 'C'", raceRow.id), undefined, 'opted-out skipped');
  assert.equal(w.one("SELECT status FROM race_members WHERE race_id = ? AND user_id = 'D'", raceRow.id).status, 'active', 'muted still races');
  assert.equal(w.one("SELECT COUNT(*) AS n FROM notifications WHERE user_id = 'D' AND category = 'race_invite'").n, 0, 'muted invite suppressed');
});

test('cron sweep: paused definition and deleted crew spawn nothing', async () => {
  const w = world();
  for (const u of ['A', 'B']) w.user(u, { name: u });
  await w.squad('s1', 'A', 'Crew', ['B']);
  w.exec("INSERT INTO squad_recurring_races (id, squad_id, title, weekday, active, created_by) VALUES ('rr1', 's1', 'Paused', ?, 0, 'A')", todayUtc());
  await w.squad('s2', 'A', 'Gone Crew', ['B']);
  w.exec('UPDATE squads SET deleted_at = CURRENT_TIMESTAMP WHERE id = \'s2\'');
  w.exec("INSERT INTO squad_recurring_races (id, squad_id, title, weekday, created_by) VALUES ('rr2', 's2', 'Ghost', ?, 'A')", todayUtc());
  assert.equal(await sweep(w), 0);
  assert.equal(w.one('SELECT COUNT(*) AS n FROM races').n, 0);
});

// ── Reports ──────────────────────────────────────────────────────────────────

test('report a crew: reason capped at 500, target must exist', async () => {
  const w = world();
  for (const u of ['A', 'B']) w.user(u, { name: u });
  await w.squad('s1', 'A', 'Crew', ['B']);

  assert.equal((await w.req('B', 'POST', '/reports/squads/s1', { reason: 'x'.repeat(501) })).status, 400);
  jsonOk(await w.req('B', 'POST', '/reports/squads/s1', { reason: 'The crew bio is spam' }));
  const row = w.one("SELECT target_type, target_id, reason, status FROM reports WHERE reporter_user_id = 'B'");
  assert.deepEqual(row, { target_type: 'squad', target_id: 's1', reason: 'The crew bio is spam', status: 'pending' });
  assert.equal((await w.req('B', 'POST', '/reports/squads/ghost', { reason: 'x' })).status, 404);
});

// ── /crew/requests mutuals ───────────────────────────────────────────────────

test('crew requests: mutualCount + mutualNames (≤2) on incoming rows', async () => {
  const w = world();
  for (const u of ['A', 'B', 'C', 'D']) w.user(u, { name: `Name ${u}` });
  // B and D are mutual friends of A and C; C asks to add A.
  w.friend('A', 'B'); w.friend('B', 'C'); w.friend('A', 'D'); w.friend('D', 'C');
  w.exec(
    `INSERT INTO crew_connections (id, user_id, crew_user_id, status, requested_by, created_at, updated_at)
     VALUES ('req-c-a', 'A', 'C', 'pending', 'C', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)`,
  );

  const reqs = jsonOk(await w.req('A', 'GET', '/crew/requests'));
  const incoming = reqs.requests.find((r) => r.id === 'C');
  assert.ok(incoming, 'C request is incoming for A');
  assert.equal(incoming.mutualCount, 2);
  assert.equal(incoming.mutualNames.length, 2);
  assert.ok(incoming.mutualNames.includes('Name B') || incoming.mutualNames.includes('Name D'));
});

// ── badge_earned feed item ──────────────────────────────────────────────────

test('feed: friend earning an achievement lands a badge_earned item; mute hides it', async () => {
  const w = world();
  for (const u of ['A', 'B', 'C']) w.user(u, { name: u });
  w.friend('A', 'B'); // A follows B; C is not A's friend
  w.race('r1', 'B');
  // B's first accepted progress grants ach-first-move → crew_activity row.
  w.raceEvent('r1', 'B', 'progress_accepted', 'B');
  await reconcileProgression(w.db, 'B');
  const act = w.one("SELECT * FROM crew_activity WHERE actor_user_id = 'B' AND kind = 'badge_earned'");
  assert.ok(act, 'reconcile wrote the feed row');
  assert.equal(JSON.parse(act.payload_json).name, 'First Move');

  // A sees it; a different friend's feed does not.
  const feed = jsonOk(await w.req('A', 'GET', '/crew/feed'));
  const badge = feed.items.find((i) => i.type === 'badge_earned');
  assert.ok(badge, 'badge_earned item present');
  assert.equal(badge.actor.id, 'B');
  assert.equal(badge.payload.name, 'First Move');
  assert.equal(badge.payload.key, 'first_move');
  assert.equal(badge.entityType, 'crew_activity');

  // C's achievement never reaches A (not friends).
  w.race('r2', 'C');
  w.raceEvent('r2', 'C', 'progress_accepted', 'C');
  await reconcileProgression(w.db, 'C');
  const feed2 = jsonOk(await w.req('A', 'GET', '/crew/feed'));
  assert.equal(feed2.items.filter((i) => i.type === 'badge_earned').length, 1);

  // Muting B removes their badge items too (actor-mute feeds the exclusion).
  jsonOk(await w.req('A', 'POST', '/mutes/users/B'));
  const feed3 = jsonOk(await w.req('A', 'GET', '/crew/feed'));
  assert.equal(feed3.items.filter((i) => i.type === 'badge_earned').length, 0);
});

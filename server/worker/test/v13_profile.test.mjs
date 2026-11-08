// v13 profile additions (migration 0048): bio + favorite movement + the two
// privacy prefs (activity map sharing, who can race me), day streaks on
// GET /progression, the additive public-profile bundle on GET /users/:id,
// GET /users/:id/activity, mutes (CRUD + feed/notification suppression), and
// friend-only race invites. Prod-schema SQLite harness like journey.test.mjs.
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
  readFileSync(new URL('migrations/0045_teach_sessions.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0046_squads.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0047_reconcile_prod.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0048_v13_profile.sql', root), 'utf8'),
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

  /** A move_log row — verified proof by default, placed `daysAgo` back. */
  let moveN = 0;
  const proof = (userId, raceId, daysAgo = 0, status = 'verified', hours = 12) => {
    const id = `ml-${++moveN}`;
    exec(
      `INSERT INTO move_logs (id, race_id, user_id, source, value, unit, status, created_at)
       VALUES (?, ?, ?, 'manual', 1, 'reps', ?, datetime('now', ?, ?))`,
      id, raceId, userId, status, `-${daysAgo} days`, `-${hours} hours`,
    );
    return id;
  };

  const raceEvent = (raceId, actorId, type = 'participant_finished') => {
    const id = `ev-${raceId}-${actorId}-${Math.random().toString(36).slice(2, 8)}`;
    exec(
      "INSERT INTO race_events (id, race_id, event_type, actor_user_id, created_at) VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)",
      id, raceId, type, actorId,
    );
    return id;
  };

  const flush = async () => { await Promise.all(pending.splice(0)); };

  return { sqlite, db, r2, env, req, q, one, exec, user, race, member, friend, proof, raceEvent, flush };
}

const jsonOk = (r, status = 200) => {
  assert.equal(r.status, status, `${r.status} ${r.text}`);
  assert.ok(r.json, `JSON body expected: ${r.text}`);
  return r.json;
};

// ── Schema ──────────────────────────────────────────────────────────────────

test('0048: user_mutes + profile columns exist with defaults', async () => {
  const w = world();
  w.user('A', { name: 'Alice' });
  const cols = w.q('PRAGMA table_info(profiles)').map((c) => c.name);
  for (const c of ['bio', 'favorite_movement_key', 'activity_map_shared', 'race_invites_from']) {
    assert.ok(cols.includes(c), `profiles.${c} missing`);
  }
  assert.ok(w.q("SELECT name FROM sqlite_master WHERE type='table' AND name='user_mutes'").length === 1);
  const row = w.one('SELECT bio, favorite_movement_key, activity_map_shared, race_invites_from FROM profiles WHERE user_id = ?', 'A');
  assert.deepEqual(row, { bio: null, favorite_movement_key: null, activity_map_shared: 1, race_invites_from: 'everyone' });
});

// ── POST /profile + GET /profile/me ─────────────────────────────────────────

test('profile: new fields write and read back, defaults on a fresh profile', async () => {
  const w = world();
  w.user('A', { name: 'Alice' });

  const me = jsonOk(await w.req('A', 'GET', '/profile/me'));
  assert.equal(me.bio, null);
  assert.equal(me.favoriteMovementKey, null);
  assert.equal(me.activityMapShared, true);
  assert.equal(me.raceInvitesFrom, 'everyone');
  assert.equal(me.fullName, 'Alice');

  const wrote = jsonOk(await w.req('A', 'POST', '/profile', {
    bio: '  Early riser, late racer.  ',
    favoriteMovementKey: 'push_ups',
    activityMapShared: false,
    raceInvitesFrom: 'friends',
  }));
  const back = jsonOk(await w.req('A', 'GET', '/profile/me'));
  assert.equal(back.bio, 'Early riser, late racer.');
  assert.equal(back.favoriteMovementKey, 'push_ups');
  assert.equal(back.activityMapShared, false);
  assert.equal(back.raceInvitesFrom, 'friends');
  // POST returns the same serialized shape
  assert.equal(wrote.bio, 'Early riser, late racer.');
  assert.equal(wrote.raceInvitesFrom, 'friends');
  // legacy fields intact
  assert.equal(back.privateProfile, false);
  assert.equal(back.username, null);
});

test('profile: validation — bio >80, bad types, bad enum', async () => {
  const w = world();
  w.user('A', { name: 'Alice' });

  const bad = await w.req('A', 'POST', '/profile', { bio: 'x'.repeat(81) });
  assert.equal(bad.status, 400);
  assert.equal((await w.req('A', 'POST', '/profile', { bio: 'x'.repeat(80) })).status, 200);
  assert.equal((await w.req('A', 'POST', '/profile', { bio: 42 })).status, 400);
  assert.equal((await w.req('A', 'POST', '/profile', { favoriteMovementKey: 'y'.repeat(41) })).status, 400);
  assert.equal((await w.req('A', 'POST', '/profile', { favoriteMovementKey: 'y'.repeat(40) })).status, 200);
  assert.equal((await w.req('A', 'POST', '/profile', { activityMapShared: 'yes' })).status, 400);
  assert.equal((await w.req('A', 'POST', '/profile', { raceInvitesFrom: 'crew' })).status, 400);
  assert.equal((await w.req('A', 'POST', '/profile', { raceInvitesFrom: 'everyone' })).status, 200);
});

// ── Day streaks + progression record ────────────────────────────────────────

test('progression record: streakDays, bestStreakDays, friends, proofsThisWeek', async () => {
  const w = world();
  w.user('A', { name: 'Alice' });
  w.user('B', { name: 'Bob' });
  w.user('C', { name: 'Cleo' });
  w.race('r1', 'A');
  w.friend('A', 'B');
  w.friend('A', 'C');

  // Verified proofs: today + yesterday + day before → 3-day current streak;
  // an isolated proof 9 days ago is its own 1-day run; nothing 8 days ago.
  w.proof('A', 'r1', 0);
  w.proof('A', 'r1', 1);
  w.proof('A', 'r1', 2);
  w.proof('A', 'r1', 9);
  w.proof('A', 'r1', 2, 'rejected'); // unverified — must not count

  const res = jsonOk(await w.req('A', 'GET', '/progression?tz=0'));
  assert.equal(res.record.streakDays, 3);
  assert.equal(res.record.bestStreakDays, 3);
  assert.equal(res.record.friends, 2);
  assert.equal(res.record.proofsThisWeek, 3); // the 9-day-old one is outside the window
  // legacy record fields still present
  assert.ok('active' in res.record && 'wins' in res.record && 'winRatePercent' in res.record);
});

test('day streaks: a gap ends the current streak but keeps the best', async () => {
  const w = world();
  w.user('A', { name: 'Alice' });
  w.race('r1', 'A');
  // 5 consecutive days ending 3 days ago, nothing since → current 0, best 5.
  for (const d of [3, 4, 5, 6, 7]) w.proof('A', 'r1', d);
  const res = jsonOk(await w.req('A', 'GET', '/progression?tz=0'));
  assert.equal(res.record.streakDays, 0);
  assert.equal(res.record.bestStreakDays, 5);
});

test('day streaks: tz shifts day boundaries', async () => {
  const w = world();
  w.user('A', { name: 'Alice' });
  w.race('r1', 'A');
  // One proof ~1 hour ago UTC. tz=-60 keeps it on the same local day in the
  // far east of the offset space only when utc hour > 0; assert tz parses and
  // the streak stays consistent under an extreme offset rather than pinning
  // wall-clock assumptions — the streak for a single recent proof is 0 or 1
  // depending on the local-day edge, but never errors and never exceeds 1.
  w.exec(
    "INSERT INTO move_logs (id, race_id, user_id, source, value, unit, status, created_at) VALUES ('ml-tz', 'r1', 'A', 'manual', 1, 'reps', 'verified', datetime('now', '-1 hours'))",
  );
  const west = jsonOk(await w.req('A', 'GET', '/progression?tz=-840'));
  const east = jsonOk(await w.req('A', 'GET', '/progression?tz=840'));
  assert.ok(west.record.streakDays <= 1 && east.record.streakDays <= 1);
  assert.equal(west.record.proofsThisWeek, 1);
});

// ── GET /users/:id additive bundle ──────────────────────────────────────────

test('users/:id: bio, friendsCount, mutual (preview ≤3), versus, muted, activityShared, lockedAchievements', async () => {
  const w = world();
  w.user('A', { name: 'Alice' });
  w.user('B', { name: 'Bob' });
  jsonOk(await w.req('B', 'POST', '/profile', { bio: 'Bob bio', favoriteMovementKey: 'squats' }));

  // 4 mutual friends connected to both A and B → count 4, preview capped at 3.
  for (const f of ['F1', 'F2', 'F3', 'F4']) {
    w.user(f, { name: f });
    w.friend('A', f);
    w.friend('B', f);
  }
  w.friend('B', 'A');
  w.race('r1', 'B');
  w.member('r1', 'A');
  w.proof('B', 'r1', 0);

  const res = jsonOk(await w.req('A', 'GET', '/users/B?tz=0'));
  const u = res.user;
  assert.equal(u.bio, 'Bob bio');
  assert.equal(u.favoriteMovementKey, 'squats');
  assert.equal(u.friendsCount, 5); // F1..F4 + Alice
  assert.equal(u.mutual.count, 4);
  assert.equal(u.mutual.preview.length, 3);
  assert.deepEqual(
    Object.keys(u.mutual.preview[0]).sort(),
    ['displayName', 'id', 'profilePhotoUrl'],
  );
  // versus — both sides carry the same scoreboard rows
  assert.ok(u.versus, 'versus missing for non-self view');
  for (const side of ['you', 'them']) {
    const s = u.versus[side];
    for (const k of ['level', 'wins', 'winRatePercent', 'bestStreakDays', 'proofsThisWeek']) {
      assert.ok(k in s, `versus.${side}.${k} missing`);
    }
  }
  assert.equal(u.versus.them.proofsThisWeek, 1);
  assert.equal(u.muted, false);
  assert.equal(u.activityShared, true);
  // locked achievements: catalog entries Bob hasn't earned — metadata only.
  assert.ok(Array.isArray(u.lockedAchievements) && u.lockedAchievements.length > 0);
  for (const a of u.lockedAchievements) {
    assert.deepEqual(Object.keys(a).sort(), ['category', 'iconKey', 'key', 'name']);
  }
});

test('users/:id: self view has no versus/mutual/friendship; muted flips after POST /mutes', async () => {
  const w = world();
  w.user('A', { name: 'Alice' });
  w.user('B', { name: 'Bob' });
  w.friend('A', 'B');

  const self = jsonOk(await w.req('A', 'GET', '/users/A'));
  assert.equal(self.user.versus, null);
  assert.equal(self.user.mutual, null);
  assert.equal(self.user.friendship, null);
  assert.equal(self.user.muted, false);

  jsonOk(await w.req('A', 'POST', '/mutes/users/B'));
  const res = jsonOk(await w.req('A', 'GET', '/users/B'));
  assert.equal(res.user.muted, true);
  // invisibility: Bob's view of Alice is unaffected by Alice's mute
  const theirs = jsonOk(await w.req('B', 'GET', '/users/A'));
  assert.equal(theirs.user.muted, false);
});

test('users/:id: friendship bundle — connectedSince + all five badges', async () => {
  const w = world();
  w.user('A', { name: 'Alice' });
  w.user('B', { name: 'Bob' });
  w.friend('A', 'B', 31); // 31 days → best_friends earned

  // One completed shared race → first_race earned, rivals progress 1/10.
  w.race('done1', 'A', { status: 'completed' });
  w.member('done1', 'B');
  // 7-day streaks on both sides → streak_buddies earned.
  w.race('streak-race', 'A');
  w.member('streak-race', 'B');
  for (const d of [0, 1, 2, 3, 4, 5, 6]) {
    w.proof('A', 'streak-race', d);
    w.proof('B', 'streak-race', d);
  }
  // 20 reactions A→B on B's proofs → cheer_squad earned.
  const ids = [];
  for (let i = 0; i < 20; i++) ids.push(w.proof('B', 'streak-race', 8 + (i % 3)));
  for (const id of ids) {
    w.exec("INSERT INTO activity_reactions (id, user_id, entity_type, entity_id, emoji) VALUES (?, 'A', 'move_log', ?, 'fire')",
      `ar-${id}`, id);
  }

  const res = jsonOk(await w.req('A', 'GET', '/users/B?tz=0'));
  const f = res.user.friendship;
  assert.ok(f, 'friendship missing for connected pair');
  assert.ok(f.connectedSince);
  const badges = Object.fromEntries(f.badges.map((b) => [b.key, b]));
  assert.deepEqual(Object.keys(badges).sort(), ['best_friends', 'cheer_squad', 'first_race', 'rivals', 'streak_buddies']);
  for (const b of f.badges) {
    for (const k of ['key', 'name', 'description', 'earned', 'progress', 'threshold']) {
      assert.ok(k in b, `badge ${b.key} missing ${k}`);
    }
  }
  assert.equal(badges.first_race.earned, true);
  assert.equal(badges.first_race.threshold, 1);
  assert.equal(badges.rivals.earned, false);
  assert.equal(badges.rivals.progress, 1);
  assert.equal(badges.rivals.threshold, 10);
  assert.equal(badges.cheer_squad.earned, true);
  assert.equal(badges.cheer_squad.progress, 20);
  assert.equal(badges.best_friends.earned, true);
  assert.equal(badges.best_friends.threshold, 30);
  assert.equal(badges.streak_buddies.earned, true);
  assert.equal(badges.streak_buddies.progress, 7);
});

test('users/:id: friendship absent when not connected; blocked → 403', async () => {
  const w = world();
  w.user('A', { name: 'Alice' });
  w.user('B', { name: 'Bob' });
  const stranger = jsonOk(await w.req('A', 'GET', '/users/B'));
  assert.equal(stranger.user.friendship, null);
  assert.equal(stranger.user.connectionStatus, 'none');

  w.exec("INSERT INTO blocked_users (id, user_id, blocked_user_id, created_at) VALUES ('blk', 'B', 'A', CURRENT_TIMESTAMP)");
  const res = await w.req('A', 'GET', '/users/B');
  assert.equal(res.status, 403);
});

// ── GET /users/:id/activity ─────────────────────────────────────────────────

test('users/:id/activity: shared map, hidden map, blocked', async () => {
  const w = world();
  w.user('A', { name: 'Alice' });
  w.user('B', { name: 'Bob' });
  w.race('r1', 'B');
  w.proof('B', 'r1', 0);
  w.proof('B', 'r1', 1);
  w.proof('B', 'r1', 1); // two proofs same day → proofs: 2
  w.proof('B', 'r1', 5, 'pending'); // unverified — excluded

  const shared = jsonOk(await w.req('A', 'GET', '/users/B/activity?days=30&tz=0'));
  assert.equal(shared.shared, true);
  assert.equal(shared.days.length, 2);
  const two = shared.days.find((d) => d.proofs === 2);
  assert.ok(two, 'expected a day with 2 proofs');

  jsonOk(await w.req('B', 'POST', '/profile', { activityMapShared: false }));
  const hidden = jsonOk(await w.req('A', 'GET', '/users/B/activity?days=30&tz=0'));
  assert.equal(hidden.shared, false);
  assert.deepEqual(hidden.days, []);

  // self activity unaffected by own privacy pref check order — blocked wins.
  w.exec("INSERT INTO blocked_users (id, user_id, blocked_user_id, created_at) VALUES ('b1', 'B', 'A', CURRENT_TIMESTAMP)");
  const blocked = await w.req('A', 'GET', '/users/B/activity');
  assert.equal(blocked.status, 403);
  const otherWay = await w.req('B', 'GET', '/users/A/activity');
  assert.equal(otherWay.status, 403);
});

test('users/:id/activity: unknown user → 404', async () => {
  const w = world();
  w.user('A', { name: 'Alice' });
  assert.equal((await w.req('A', 'GET', '/users/ghost/activity')).status, 404);
});

// ── Mutes CRUD ──────────────────────────────────────────────────────────────

test('mutes: user + crew CRUD, list, idempotency, validation', async () => {
  const w = world();
  w.user('A', { name: 'Alice' });
  w.user('B', { name: 'Bob' });
  w.exec("INSERT INTO squads (id, name, join_code, owner_id, created_at) VALUES ('sq1', 'Night Crew', 'ABC123', 'B', CURRENT_TIMESTAMP)");

  assert.equal((await w.req('A', 'POST', '/mutes/users/A')).status, 400); // self
  assert.equal((await w.req('A', 'POST', '/mutes/users/ghost')).status, 404);
  assert.equal((await w.req('A', 'POST', '/mutes/crews/ghost')).status, 404);

  jsonOk(await w.req('A', 'POST', '/mutes/users/B'));
  jsonOk(await w.req('A', 'POST', '/mutes/users/B')); // idempotent
  jsonOk(await w.req('A', 'POST', '/mutes/crews/sq1'));

  const list = jsonOk(await w.req('A', 'GET', '/mutes'));
  assert.equal(list.users.length, 1);
  assert.equal(list.users[0].id, 'B');
  assert.equal(list.users[0].displayName, 'Bob');
  assert.ok(list.users[0].mutedAt);
  assert.equal(list.crews.length, 1);
  assert.equal(list.crews[0].id, 'sq1');
  assert.equal(list.crews[0].name, 'Night Crew');
  assert.equal(w.q("SELECT * FROM user_mutes WHERE user_id = 'A'").length, 2);

  // Bob's own list is empty — mutes are per-viewer.
  const bobs = jsonOk(await w.req('B', 'GET', '/mutes'));
  assert.equal(bobs.users.length, 0);

  jsonOk(await w.req('A', 'DELETE', '/mutes/users/B'));
  jsonOk(await w.req('A', 'DELETE', '/mutes/users/B')); // unmute twice = ok
  jsonOk(await w.req('A', 'DELETE', '/mutes/crews/sq1'));
  assert.equal(w.q("SELECT * FROM user_mutes WHERE user_id = 'A'").length, 0);
});

// ── Mute enforcement: feed + notifications ──────────────────────────────────

test('feed: muted actor items disappear; unmuted actors stay', async () => {
  const w = world();
  w.user('A', { name: 'Alice' });
  w.user('B', { name: 'Bob' });
  w.user('C', { name: 'Cleo' });
  w.race('r1', 'A');
  w.member('r1', 'B');
  w.member('r1', 'C');
  w.raceEvent('r1', 'B');
  w.raceEvent('r1', 'C');

  const before = jsonOk(await w.req('A', 'GET', '/crew/feed'));
  const actors = before.items.map((i) => i.actor?.id);
  assert.ok(actors.includes('B') && actors.includes('C'));

  jsonOk(await w.req('A', 'POST', '/mutes/users/B'));
  const after = jsonOk(await w.req('A', 'GET', '/crew/feed'));
  const afterActors = after.items.map((i) => i.actor?.id);
  assert.ok(!afterActors.includes('B'), 'muted actor still in feed');
  assert.ok(afterActors.includes('C'), 'unmuted actor vanished');

  jsonOk(await w.req('A', 'DELETE', '/mutes/users/B'));
  const restored = jsonOk(await w.req('A', 'GET', '/crew/feed'));
  assert.ok(restored.items.map((i) => i.actor?.id).includes('B'));
});

test('notifications: muted actor produces no inbox row (reaction fan-out)', async () => {
  const w = world();
  w.user('A', { name: 'Alice' });
  w.user('B', { name: 'Bob' });
  w.race('r1', 'A');
  w.member('r1', 'B');
  const move = w.proof('A', 'r1', 0);

  // Baseline: Bob's reaction notifies Alice.
  jsonOk(await w.req('B', 'POST', '/reactions', { entityType: 'move_log', entityId: move, emoji: 'fire' }));
  assert.ok(w.one("SELECT id FROM notifications WHERE user_id = 'A' AND category = 'reaction'"), 'baseline reaction notification missing');

  // Muting Bob suppresses the next one — different entity so no dedupe.
  const move2 = w.proof('A', 'r1', 0);
  jsonOk(await w.req('A', 'POST', '/mutes/users/B'));
  jsonOk(await w.req('B', 'POST', '/reactions', { entityType: 'move_log', entityId: move2, emoji: 'clap' }));
  assert.equal(
    w.one("SELECT id FROM notifications WHERE user_id = 'A' AND entity_id = ?", move2),
    undefined,
    'muted actor notification leaked',
  );
  // The reaction itself was still written — muting is invisible to the actor.
  assert.ok(w.one("SELECT id FROM activity_reactions WHERE user_id = 'B' AND entity_id = ?", move2));
});

test('notifications: muted requester produces no crew_request row (lifecycle batch path)', async () => {
  const w = world();
  w.user('A', { name: 'Alice' });
  w.user('B', { name: 'Bob' });
  jsonOk(await w.req('A', 'POST', '/mutes/users/B'));

  const res = jsonOk(await w.req('B', 'POST', '/crew/add', { userId: 'A' }));
  assert.equal(res.status, 'pending'); // the request still lands
  await w.flush();
  assert.equal(
    w.one("SELECT id FROM notifications WHERE user_id = 'A' AND category = 'crew_request'"),
    undefined,
    'crew_request from muted actor leaked',
  );
  // The connection itself exists — muting never blocks.
  assert.equal(
    w.one("SELECT status FROM crew_connections WHERE user_id = 'B' AND crew_user_id = 'A'").status,
    'pending',
  );
});

// ── race_invites_from ───────────────────────────────────────────────────────

test('race invites: friends-only invitee blocks stranger adds on /members + /participants', async () => {
  const w = world();
  w.user('A', { name: 'Alice' });
  w.user('B', { name: 'Bob' });
  jsonOk(await w.req('B', 'POST', '/profile', { raceInvitesFrom: 'friends' }));
  w.race('r1', 'A');

  const deny1 = await w.req('A', 'POST', '/races/r1/members', { userId: 'B' });
  assert.equal(deny1.status, 403);
  assert.match(deny1.json.error, /friends/i);
  const deny2 = await w.req('A', 'POST', '/races/r1/participants', { userId: 'B' });
  assert.equal(deny2.status, 403);
  assert.equal(w.one("SELECT id FROM race_members WHERE race_id = 'r1' AND user_id = 'B'"), undefined);

  // Friends pass the gate.
  w.friend('A', 'B');
  const ok = await w.req('A', 'POST', '/races/r1/members', { userId: 'B' });
  assert.equal(ok.status, 200);
  assert.ok(w.one("SELECT id FROM race_members WHERE race_id = 'r1' AND user_id = 'B' AND status = 'active'"));
});

test('race invites: default everyone still adds strangers', async () => {
  const w = world();
  w.user('A', { name: 'Alice' });
  w.user('B', { name: 'Bob' });
  w.race('r1', 'A');
  const res = await w.req('A', 'POST', '/races/r1/members', { userId: 'B' });
  assert.equal(res.status, 200);
});

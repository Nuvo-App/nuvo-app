// GET /squads/:id — real names/photos for everyone, blocked pairs anonymized.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';

const require = createRequire(import.meta.url);
const app = require('../.tmp-test-dist/index.js').default;
const { signJwt } = require('../.tmp-test-dist/lib/jwt.js');

const JWT_SECRET = 'test-secret';

function makeDb() {
  const sql = new DatabaseSync(':memory:');
  sql.exec(`
    CREATE TABLE users (id TEXT PRIMARY KEY, terms_accepted_at TEXT);
    CREATE TABLE blocked_users (id TEXT, user_id TEXT, blocked_user_id TEXT);
    CREATE TABLE profiles (user_id TEXT, full_name TEXT, username TEXT, avatar_url TEXT);
    CREATE TABLE squads (id TEXT PRIMARY KEY, name TEXT, join_code TEXT, owner_id TEXT, created_at TEXT, deleted_at TEXT);
    CREATE TABLE squad_members (id TEXT, squad_id TEXT, user_id TEXT, role TEXT, status TEXT, joined_at TEXT);
    CREATE TABLE squad_races (id TEXT, squad_id TEXT, race_id TEXT, created_by TEXT, created_at TEXT);
    CREATE TABLE races (id TEXT, title TEXT, status TEXT, creator_id TEXT, target_value REAL, target_unit TEXT,
      score_direction TEXT, activity_id TEXT, format TEXT, race_type TEXT, version INTEGER, updated_at TEXT, deleted_at TEXT);
    CREATE TABLE race_members (race_id TEXT, user_id TEXT, status TEXT, joined_at TEXT);
    CREATE TABLE race_progress (race_id TEXT, user_id TEXT, progress_value REAL, completed_at TEXT, updated_at TEXT);
  `);
  const wrap = (stmt, args) => ({
    bind: (...a) => wrap(stmt, a),
    first: async () => stmt.get(...args) ?? null,
    all: async () => ({ results: stmt.all(...args) }),
    run: async () => { stmt.run(...args); return { success: true }; },
  });
  return {
    sql,
    prepare: (q) => wrap(sql.prepare(q), []),
    batch: async (list) => { const out = []; for (const s of list) out.push(await s.all()); return out; },
  };
}

function seed() {
  const db = makeDb();
  const { sql } = db;
  for (const u of ['me', 'friend', 'blockedByMe', 'blocksMe', 'nameless']) {
    sql.prepare('INSERT INTO users VALUES (?, ?)').run(u, '2024-01-01');
  }
  const prof = (u, name, username, photo) => sql.prepare('INSERT INTO profiles VALUES (?,?,?,?)').run(u, name, username, photo);
  prof('me', 'Me Myself', 'me', 'https://img/me.png');
  prof('friend', 'Fran Friend', 'fran', 'https://img/fran.png');
  prof('blockedByMe', 'Bo Blocked', 'bo', 'https://img/bo.png');
  prof('blocksMe', 'Bea Blocker', 'bea', 'https://img/bea.png');
  sql.prepare("INSERT INTO squads VALUES ('s1','Crew','JOINME','me','2024-01-01',NULL)").run();
  let i = 0;
  for (const u of ['me', 'friend', 'blockedByMe', 'blocksMe', 'nameless']) {
    sql.prepare('INSERT INTO squad_members VALUES (?,?,?,?,?,?)').run(`m-${u}`, 's1', u, u === 'me' ? 'owner' : 'member', 'active', `2024-01-01 00:00:0${i++}`);
  }
  sql.prepare("INSERT INTO blocked_users VALUES ('b1','me','blockedByMe')").run();
  sql.prepare("INSERT INTO blocked_users VALUES ('b2','blocksMe','me')").run();
  return db;
}

async function get(db, user, path) {
  const token = await signJwt({ sub: user, iat: 0, exp: 9999999999 }, JWT_SECRET);
  const res = await app.fetch(
    new Request(`https://x.test${path}`, { headers: { authorization: `Bearer ${token}` } }),
    { DB: db, JWT_SECRET },
    { waitUntil() {}, passThroughOnException() {} },
  );
  return { status: res.status, json: await res.json() };
}

test('GET /squads/:id shows real names/photos, anonymizes blocked pairs, keeps Nuvo member fallback', async () => {
  const db = seed();
  const { status, json } = await get(db, 'me', '/squads/s1');
  assert.equal(status, 200);
  const m = Object.fromEntries(json.members.map((x) => [x.userId, x]));
  assert.equal(m.me.displayName, 'Me Myself');
  assert.equal(m.friend.displayName, 'Fran Friend');
  assert.equal(m.friend.profilePhotoUrl, 'https://img/fran.png');
  assert.equal(m.nameless.displayName, 'Nuvo member');
  for (const u of ['blockedByMe', 'blocksMe']) {
    assert.equal(m[u].displayName, 'Private User');
    assert.equal(m[u].profilePhotoUrl, null);
    assert.equal(m[u].username, null);
  }
  const s = Object.fromEntries(json.standings.map((x) => [x.userId, x]));
  assert.equal(s.friend.displayName, 'Fran Friend');
  assert.equal(s.friend.profilePhotoUrl, 'https://img/fran.png');
  assert.equal(s.nameless.displayName, 'Nuvo member');
  assert.equal(s.blockedByMe.displayName, 'Private User');
  assert.equal(s.blocksMe.profilePhotoUrl, null);
});

test('GET /squads/:id — a non-blocked viewer still sees everyone', async () => {
  const db = seed();
  const { json } = await get(db, 'friend', '/squads/s1');
  const m = Object.fromEntries(json.members.map((x) => [x.userId, x]));
  assert.equal(m.blockedByMe.displayName, 'Bo Blocked');
  assert.equal(m.blocksMe.displayName, 'Bea Blocker');
  assert.equal(m.me.profilePhotoUrl, 'https://img/me.png');
});

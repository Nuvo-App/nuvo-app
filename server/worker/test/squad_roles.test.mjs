import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';

const require = createRequire(import.meta.url);
const app = require('../.tmp-test-dist/index.js').default;
const { signJwt } = require('../.tmp-test-dist/lib/jwt.js');

const JWT_SECRET = 'test-secret';
const token = (sub) => signJwt({ sub, iat: 0, exp: 9999999999 }, JWT_SECRET);

// Minimal real-SQLite D1 shim: only the tables the crew routes read or write.
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
    run: async () => {
      stmt.run(...args);
      return { success: true };
    },
  });
  const db = {
    sql,
    prepare: (q) => wrap(sql.prepare(q), []),
    batch: async (list) => {
      const out = [];
      for (const s of list) out.push(await s.all());
      return out;
    },
  };
  return db;
}

function seed() {
  const db = makeDb();
  const { sql } = db;
  for (const u of ['owner', 'admin', 'mem', 'mem2', 'outsider']) {
    sql.prepare('INSERT INTO users VALUES (?, ?)').run(u, '2024-01-01');
  }
  sql.prepare("INSERT INTO squads VALUES ('s1','Crew','JOINME','owner','2024-01-01',NULL)").run();
  const m = (u, role, status = 'active', at = '2024-01-01 00:00:00') =>
    sql.prepare('INSERT INTO squad_members VALUES (?,?,?,?,?,?)').run(`m-${u}`, 's1', u, role, status, at);
  m('owner', 'owner');
  m('admin', 'admin');
  m('mem', 'member');
  m('mem2', 'member');
  sql.prepare("INSERT INTO squad_races VALUES ('sr1','s1','r1','owner','2024-01-01')").run();
  return db;
}

async function call(db, user, method, path, body, headers = {}) {
  const req = new Request(`https://x.test${path}`, {
    method,
    headers: {
      authorization: `Bearer ${await token(user)}`,
      'content-type': 'application/json',
      ...headers,
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const res = await app.fetch(req, { DB: db, JWT_SECRET }, { waitUntil() {}, passThroughOnException() {} });
  let json = null;
  try {
    json = await res.clone().json();
  } catch {}
  return { res, status: res.status, json };
}

const statusOf = (db, u) => db.sql.prepare('SELECT status, role FROM squad_members WHERE user_id = ?').get(u);

test('role change: owner only, admin|member only, owner role immutable', async () => {
  const db = seed();
  assert.equal((await call(db, 'owner', 'POST', '/squads/s1/members/mem/role', { role: 'admin' })).status, 200);
  assert.equal(statusOf(db, 'mem').role, 'admin');
  assert.equal((await call(db, 'owner', 'POST', '/squads/s1/members/mem/role', { role: 'member' })).status, 200);
  assert.equal(statusOf(db, 'mem').role, 'member');
  assert.equal((await call(db, 'admin', 'POST', '/squads/s1/members/mem/role', { role: 'admin' })).status, 403);
  assert.equal((await call(db, 'mem', 'POST', '/squads/s1/members/mem2/role', { role: 'admin' })).status, 403);
  assert.equal((await call(db, 'outsider', 'POST', '/squads/s1/members/mem/role', { role: 'admin' })).status, 404);
  assert.equal((await call(db, 'owner', 'POST', '/squads/s1/members/mem/role', { role: 'owner' })).status, 400);
  assert.equal((await call(db, 'owner', 'POST', '/squads/s1/members/owner/role', { role: 'member' })).status, 400);
  assert.equal((await call(db, 'owner', 'POST', '/squads/s1/members/nobody/role', { role: 'admin' })).status, 404);
});

test('remove member: owner anyone but owner; admin only plain members; never self', async () => {
  const db = seed();
  assert.equal((await call(db, 'admin', 'DELETE', '/squads/s1/members/owner')).status, 403);
  assert.equal((await call(db, 'owner', 'DELETE', '/squads/s1/members/owner')).status, 400);
  assert.equal((await call(db, 'admin', 'DELETE', '/squads/s1/members/admin')).status, 400);
  assert.equal((await call(db, 'mem', 'DELETE', '/squads/s1/members/mem2')).status, 403);
  assert.equal((await call(db, 'admin', 'DELETE', '/squads/s1/members/mem')).status, 200);
  assert.equal(statusOf(db, 'mem').status, 'removed');
  // owner removes an admin; role is reset to member
  assert.equal((await call(db, 'owner', 'DELETE', '/squads/s1/members/admin')).status, 200);
  assert.deepEqual({ ...statusOf(db, 'admin') }, { status: 'removed', role: 'member' });
  assert.equal((await call(db, 'owner', 'DELETE', '/squads/s1/members/mem')).status, 404);
  assert.equal((await call(db, 'outsider', 'DELETE', '/squads/s1/members/mem2')).status, 404);
});

test('admins cannot remove other admins', async () => {
  const db = seed();
  await call(db, 'owner', 'POST', '/squads/s1/members/mem/role', { role: 'admin' });
  assert.equal((await call(db, 'admin', 'DELETE', '/squads/s1/members/mem')).status, 403);
  assert.equal(statusOf(db, 'mem').status, 'active');
});

test('remove race: owner/admin ok, member 403', async () => {
  const db = seed();
  const count = () => db.sql.prepare('SELECT COUNT(*) AS n FROM squad_races').get().n;
  assert.equal((await call(db, 'mem', 'DELETE', '/squads/s1/races/r1')).status, 403);
  assert.equal(count(), 1);
  assert.equal((await call(db, 'outsider', 'DELETE', '/squads/s1/races/r1')).status, 404);
  assert.equal((await call(db, 'admin', 'DELETE', '/squads/s1/races/r1')).status, 200);
  assert.equal(count(), 0);
});

test('add race: plain member gets 403; admin passes the role gate', async () => {
  const db = seed();
  const denied = await call(db, 'mem', 'POST', '/squads/s1/races', { raceId: 'r9' });
  assert.equal(denied.status, 403);
  assert.equal(denied.json.error, 'Only crew admins can add races');
  // Admin gets past the gate (race r9 does not exist -> 404, not 403).
  // Full add-race success needs the whole race/notification schema; skipped.
  assert.equal((await call(db, 'admin', 'POST', '/squads/s1/races', { raceId: 'r9' })).status, 404);
});

test('join rejects a previously removed member', async () => {
  const db = seed();
  await call(db, 'owner', 'DELETE', '/squads/s1/members/mem');
  const r = await call(db, 'mem', 'POST', '/squads/join', { code: 'joinme' });
  assert.equal(r.status, 403);
  assert.equal(statusOf(db, 'mem').status, 'removed');
  // a fresh user can still join
  assert.equal((await call(db, 'outsider', 'POST', '/squads/join', { code: 'JOINME' })).status, 200);
});

test('GET /squads/:id returns roles, myRole, and ETag changes with a role change', async () => {
  const db = seed();
  const a = await call(db, 'mem', 'GET', '/squads/s1');
  assert.equal(a.status, 200);
  assert.equal(a.json.squad.myRole, 'member');
  const roles = Object.fromEntries(a.json.members.map((m) => [m.userId, m.role]));
  assert.deepEqual(roles, { owner: 'owner', admin: 'admin', mem: 'member', mem2: 'member' });
  const etag = a.res.headers.get('etag');
  assert.ok(etag);
  assert.equal((await call(db, 'mem', 'GET', '/squads/s1', null, { 'if-none-match': etag })).status, 304);

  await call(db, 'owner', 'POST', '/squads/s1/members/mem/role', { role: 'admin' });
  const b = await call(db, 'mem', 'GET', '/squads/s1', null, { 'if-none-match': etag });
  assert.equal(b.status, 200);
  assert.notEqual(b.res.headers.get('etag'), etag);
  assert.equal(b.json.squad.myRole, 'admin');
});

const rowOf = (db, u, squad = 's1') =>
  ({ ...db.sql.prepare('SELECT status, role FROM squad_members WHERE squad_id = ? AND user_id = ?').get(squad, u) });

test('leave resets role to member; rejoin does not restore owner/admin', async () => {
  const db = seed();
  assert.equal((await call(db, 'admin', 'POST', '/squads/s1/leave')).status, 200);
  assert.deepEqual(rowOf(db, 'admin'), { status: 'left', role: 'member' });
  assert.equal((await call(db, 'admin', 'POST', '/squads/join', { code: 'JOINME' })).status, 200);
  assert.deepEqual(rowOf(db, 'admin'), { status: 'active', role: 'member' });
  assert.equal((await call(db, 'admin', 'POST', '/squads/s1/races', { raceId: 'r9' })).status, 403);

  // Former owner leaves (handoff), then rejoins as a plain member.
  assert.equal((await call(db, 'owner', 'POST', '/squads/s1/leave')).status, 200);
  assert.equal((await call(db, 'owner', 'POST', '/squads/join', { code: 'JOINME' })).status, 200);
  assert.deepEqual(rowOf(db, 'owner'), { status: 'active', role: 'member' });
  const detail = await call(db, 'owner', 'GET', '/squads/s1');
  assert.equal(detail.json.squad.myRole, 'member');
  assert.equal(detail.json.squad.isOwner, false);
  assert.equal((await call(db, 'owner', 'POST', '/squads/s1/members/mem/role', { role: 'admin' })).status, 403);
});

test('stored owner role on a non-owner does not grant ownership', async () => {
  const db = seed();
  db.sql.prepare("UPDATE squad_members SET role = 'owner' WHERE user_id = 'mem'").run();
  assert.equal((await call(db, 'mem', 'POST', '/squads/s1/members/mem2/role', { role: 'admin' })).status, 403);
  assert.equal((await call(db, 'mem', 'DELETE', '/squads/s1/members/mem2')).status, 403);
  const detail = await call(db, 'mem', 'GET', '/squads/s1');
  assert.equal(detail.json.squad.myRole, 'member');
  assert.equal(detail.json.members.find((m) => m.userId === 'mem').role, 'member');
});

test('owner leave: prefers admin, hands over atomically', async () => {
  const db = seed();
  assert.equal((await call(db, 'owner', 'POST', '/squads/s1/leave')).status, 200);
  assert.equal(db.sql.prepare("SELECT owner_id FROM squads WHERE id = 's1'").get().owner_id, 'admin');
  assert.deepEqual(rowOf(db, 'admin'), { status: 'active', role: 'owner' });
  assert.deepEqual(rowOf(db, 'owner'), { status: 'left', role: 'member' });
  assert.equal(db.sql.prepare("SELECT deleted_at FROM squads WHERE id = 's1'").get().deleted_at, null);
  assert.equal((await call(db, 'admin', 'GET', '/squads/s1')).json.squad.myRole, 'owner');
});

test('owner leave: falls back to longest-standing member, then retires an empty crew', async () => {
  const db = seed();
  db.sql.prepare("DELETE FROM squad_members WHERE user_id = 'admin'").run();
  db.sql.prepare("UPDATE squad_members SET joined_at = '2024-02-01 00:00:00' WHERE user_id = 'mem2'").run();
  assert.equal((await call(db, 'owner', 'POST', '/squads/s1/leave')).status, 200);
  assert.equal(db.sql.prepare("SELECT owner_id FROM squads WHERE id = 's1'").get().owner_id, 'mem');
  assert.equal(rowOf(db, 'mem').role, 'owner');
  assert.equal(rowOf(db, 'mem2').role, 'member');

  assert.equal((await call(db, 'mem2', 'POST', '/squads/s1/leave')).status, 200);
  assert.equal(db.sql.prepare("SELECT deleted_at FROM squads WHERE id = 's1'").get().deleted_at, null);
  assert.equal(db.sql.prepare("SELECT owner_id FROM squads WHERE id = 's1'").get().owner_id, 'mem');
  assert.equal((await call(db, 'mem', 'POST', '/squads/s1/leave')).status, 200);
  assert.notEqual(db.sql.prepare("SELECT deleted_at FROM squads WHERE id = 's1'").get().deleted_at, null);
  assert.equal((await call(db, 'mem', 'GET', '/squads/s1')).status, 404);
});

test('join enforces the per-user crew cap; reactivation counts, already-active does not', async () => {
  const db = seed();
  const sql = db.sql;
  for (let i = 0; i < 10; i++) {
    sql.prepare('INSERT INTO squads VALUES (?,?,?,?,?,NULL)').run(`x${i}`, `X${i}`, `CODE${i}`, 'owner', '2024-01-01');
    sql.prepare('INSERT INTO squad_members VALUES (?,?,?,?,?,?)').run(`mx${i}`, `x${i}`, 'outsider', 'member', 'active', '2024-01-01');
  }
  const capped = await call(db, 'outsider', 'POST', '/squads/join', { code: 'JOINME' });
  assert.equal(capped.status, 409);
  assert.equal(capped.json.error, 'You are in the maximum number of crews');
  assert.equal(sql.prepare("SELECT COUNT(*) AS n FROM squad_members WHERE user_id = 'outsider' AND squad_id = 's1'").get().n, 0);

  // Already an active member of a crew at the cap: not blocked, no change.
  const again = await call(db, 'outsider', 'POST', '/squads/join', { code: 'CODE3' });
  assert.equal(again.status, 200);
  assert.equal(again.json.alreadyJoined, true);

  // Leaving one frees a slot.
  assert.equal((await call(db, 'outsider', 'POST', '/squads/x0/leave')).status, 200);
  assert.equal((await call(db, 'outsider', 'POST', '/squads/join', { code: 'JOINME' })).status, 200);

  // A user who left s1 earlier cannot reactivate while at the cap.
  assert.equal((await call(db, 'outsider', 'POST', '/squads/s1/leave')).status, 200);
  assert.equal((await call(db, 'outsider', 'POST', '/squads/join', { code: 'CODE0' })).status, 200);
  assert.equal((await call(db, 'outsider', 'POST', '/squads/join', { code: 'JOINME' })).status, 409);
});

test('rename: owner/admin ok, member 403, outsider 404, name validated, ETags change', async () => {
  const db = seed();
  const list0 = await call(db, 'mem', 'GET', '/squads');
  const listTag = list0.res.headers.get('etag');
  const det0 = await call(db, 'mem', 'GET', '/squads/s1');
  const detTag = det0.res.headers.get('etag');

  assert.equal((await call(db, 'mem', 'PATCH', '/squads/s1', { name: 'Nope' })).status, 403);
  assert.equal((await call(db, 'outsider', 'PATCH', '/squads/s1', { name: 'Nope' })).status, 404);
  assert.equal((await call(db, 'owner', 'PATCH', '/squads/s1', { name: 'A' })).status, 400);
  assert.equal((await call(db, 'owner', 'PATCH', '/squads/s1', { name: 'x'.repeat(41) })).status, 400);

  const ok = await call(db, 'admin', 'PATCH', '/squads/s1', { name: '  Sunrise   Crew ' });
  assert.equal(ok.status, 200);
  assert.equal(ok.json.name, 'Sunrise Crew');

  const det1 = await call(db, 'mem', 'GET', '/squads/s1', null, { 'if-none-match': detTag });
  assert.equal(det1.status, 200);
  assert.equal(det1.json.squad.name, 'Sunrise Crew');
  const list1 = await call(db, 'mem', 'GET', '/squads', null, { 'if-none-match': listTag });
  assert.equal(list1.status, 200);
  assert.equal(list1.json.squads[0].name, 'Sunrise Crew');
});

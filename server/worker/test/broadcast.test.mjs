import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';

const require = createRequire(import.meta.url);
const app = require('../.tmp-test-dist/index.js').default;

const KEY = 'internal-key';

// Real-SQLite D1 shim with the prod columns/index the broadcast touches.
function makeDb() {
  const sql = new DatabaseSync(':memory:');
  sql.exec(`
    CREATE TABLE users (id TEXT PRIMARY KEY, status TEXT NOT NULL DEFAULT 'active');
    CREATE TABLE device_tokens (id TEXT PRIMARY KEY, user_id TEXT NOT NULL, token TEXT NOT NULL,
      platform TEXT NOT NULL, disabled_at TEXT, UNIQUE(user_id, token));
    CREATE TABLE notification_preferences (user_id TEXT NOT NULL, category TEXT NOT NULL,
      in_app INTEGER NOT NULL DEFAULT 1, push INTEGER NOT NULL DEFAULT 1, PRIMARY KEY(user_id, category));
    CREATE TABLE notifications (
      id TEXT PRIMARY KEY, user_id TEXT NOT NULL, category TEXT NOT NULL, actor_user_id TEXT,
      title TEXT NOT NULL, body TEXT, dest_type TEXT, dest_id TEXT, dest_context TEXT,
      entity_type TEXT, entity_id TEXT, dedupe_key TEXT, read_at TEXT,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      priority TEXT NOT NULL DEFAULT 'medium', aggregate_count INTEGER NOT NULL DEFAULT 1);
    CREATE UNIQUE INDEX idx_notifications_dedupe ON notifications(user_id, dedupe_key);
  `);
  const wrap = (stmt, args) => ({
    bind: (...a) => wrap(stmt, a),
    first: async () => stmt.get(...args) ?? null,
    all: async () => ({ results: stmt.all(...args) }),
    run: async () => {
      const r = stmt.run(...args);
      return { success: true, meta: { changes: Number(r.changes) } };
    },
  });
  return {
    sql,
    prepare: (q) => wrap(sql.prepare(q), []),
    batch: async (list) => {
      const out = [];
      for (const s of list) out.push(await s.run());
      return out;
    },
  };
}

function seed(n = 5) {
  const db = makeDb();
  for (let i = 1; i <= n; i++) db.sql.prepare('INSERT INTO users (id) VALUES (?)').run(`u${String(i).padStart(3, '0')}`);
  db.sql.prepare("INSERT INTO users (id, status) VALUES ('zdeleted', 'deleted')").run();
  db.sql.prepare("INSERT INTO users (id, status) VALUES ('zsuspended', 'suspended')").run();
  return db;
}

const env = (db, extra = {}) => ({ DB: db, JWT_SECRET: 'x', INTERNAL_API_KEY: KEY, ...extra });
async function post(db, body, extra = {}, key = KEY) {
  const res = await app.fetch(
    new Request('http://x/internal/notifications/broadcast', {
      method: 'POST',
      headers: { 'X-Internal-Key': key, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    }),
    env(db, extra),
    { waitUntil() {}, passThroughOnException() {} },
  );
  return { status: res.status, json: await res.json() };
}
const base = { title: 'Welcome to Nuvo Capitol Hackers', body: "Let's get moving" };
const count = (db) => db.sql.prepare('SELECT COUNT(*) AS n FROM notifications').get().n;

test('broadcast needs the internal key', async () => {
  const db = seed();
  const r = await post(db, base, {}, 'wrong');
  assert.equal(r.status, 403);
  assert.equal(count(db), 0);
});

test('dry run is the default: writes nothing and returns counts', async () => {
  const db = seed(5);
  db.sql.prepare("INSERT INTO device_tokens VALUES ('d1','u001','t1','ios',NULL)").run();
  db.sql.prepare("INSERT INTO device_tokens VALUES ('d2','u001','t2','ios',NULL)").run();
  db.sql.prepare("INSERT INTO device_tokens VALUES ('d3','u002','t3','ios','2024-01-01')").run();
  db.sql.prepare("INSERT INTO device_tokens VALUES ('d4','zdeleted','t4','ios',NULL)").run();
  const r = await post(db, base); // no dryRun field
  assert.equal(r.status, 200);
  assert.equal(r.json.dryRun, true);
  assert.equal(r.json.recipients, 5);
  assert.equal(r.json.withDeviceTokens, 1);
  assert.equal(r.json.pushConfigured, false);
  assert.equal(r.json.sample.length, 3);
  assert.equal(r.json.sample[0].title, base.title);
  assert.equal(count(db), 0);
});

test('real send without a matching expectedCount or a broadcastId is refused', async () => {
  const db = seed(5);
  assert.equal((await post(db, { ...base, dryRun: false, broadcastId: 'b-1' })).status, 400);
  assert.equal((await post(db, { ...base, dryRun: false, expectedCount: 5 })).status, 400);
  assert.equal((await post(db, { ...base, dryRun: false, broadcastId: 'b-1', expectedCount: 4 })).status, 400);
  assert.equal((await post(db, { ...base, dryRun: false, broadcastId: 'b-1', expectedCount: 5, dest: { type: 'race' } })).status, 400);
  assert.equal(count(db), 0);
});

test('real send writes exactly one row per active user and skips inactive users', async () => {
  const db = seed(5);
  const r = await post(db, { ...base, dryRun: false, broadcastId: 'b-1', expectedCount: 5 });
  assert.equal(r.status, 200);
  assert.equal(r.json.inboxRows, 5);
  assert.equal(r.json.nextCursor, null);
  const rows = db.sql.prepare('SELECT * FROM notifications ORDER BY user_id').all();
  assert.equal(rows.length, 5);
  assert.deepEqual(rows.map((x) => x.user_id), ['u001', 'u002', 'u003', 'u004', 'u005']);
  assert.equal(rows[0].title, base.title);
  assert.equal(rows[0].body, base.body);
  assert.equal(rows[0].category, 'announcement');
  assert.equal(rows[0].dest_type, null);
  assert.equal(rows[0].dedupe_key, 'broadcast:b-1');
});

test('a second run with the same broadcastId writes nothing new; a different id sends again', async () => {
  const db = seed(5);
  const body = { ...base, dryRun: false, broadcastId: 'b-1', expectedCount: 5 };
  await post(db, body);
  const again = await post(db, body);
  assert.equal(again.json.inboxRows, 0);
  assert.equal(again.json.alreadyHad, 5);
  assert.equal(count(db), 5);
  await post(db, { ...body, broadcastId: 'b-2' });
  assert.equal(count(db), 10);
});

test('a partial run is completed by re-running the same broadcastId', async () => {
  const db = seed(5);
  const body = { ...base, dryRun: false, broadcastId: 'b-1', expectedCount: 5 };
  const first = await post(db, { ...body, batchSize: 2 }); // only the first batch lands
  assert.equal(first.json.inboxRows, 2);
  const full = await post(db, body);
  assert.equal(full.json.inboxRows, 3);
  assert.equal(count(db), 5);
});

test('batching with a cursor covers everyone exactly once', async () => {
  const db = seed(5);
  let cursor;
  let batches = 0;
  let inserted = 0;
  do {
    const r = await post(db, { ...base, dryRun: false, broadcastId: 'b-1', expectedCount: 5, batchSize: 2, ...(cursor ? { cursor } : {}) });
    assert.equal(r.status, 200);
    inserted += r.json.inboxRows;
    cursor = r.json.nextCursor;
    batches += 1;
    assert.ok(batches < 10);
  } while (cursor);
  assert.equal(inserted, 5);
  assert.equal(batches, 3);
  const perUser = db.sql.prepare('SELECT user_id, COUNT(*) AS n FROM notifications GROUP BY user_id').all();
  assert.equal(perUser.length, 5);
  assert.ok(perUser.every((x) => x.n === 1));
});

test('push unconfigured: inbox rows land, pushSent is 0, and nothing fails', async () => {
  const db = seed(3);
  db.sql.prepare("INSERT INTO device_tokens VALUES ('d1','u001','t1','ios',NULL)").run();
  const r = await post(db, { ...base, dryRun: false, broadcastId: 'b-1', expectedCount: 3 });
  assert.equal(r.status, 200);
  assert.equal(r.json.inboxRows, 3);
  assert.equal(r.json.pushConfigured, false);
  assert.equal(r.json.pushTargets, 1);
  assert.equal(r.json.pushSent, 0);
  assert.equal(r.json.pushFailed, 0);
});

test('push honours a disabled announcement preference but still writes the inbox row', async () => {
  const db = seed(2);
  db.sql.prepare("INSERT INTO device_tokens VALUES ('d1','u001','t1','ios',NULL)").run();
  db.sql.prepare("INSERT INTO device_tokens VALUES ('d2','u002','t2','ios',NULL)").run();
  db.sql.prepare("INSERT INTO notification_preferences (user_id, category, in_app, push) VALUES ('u001','announcement',1,0)").run();
  const r = await post(db, { ...base, dryRun: false, broadcastId: 'b-1', expectedCount: 2 });
  assert.equal(r.json.inboxRows, 2);
  assert.equal(r.json.pushTargets, 1);
});

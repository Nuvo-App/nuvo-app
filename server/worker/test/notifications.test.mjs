import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test from 'node:test';

const require = createRequire(import.meta.url);
const { NOTIFICATION_CATEGORIES, CATEGORY_DEFAULTS, emitNotification, safeEmit } = require(
  '../.tmp-test-dist/domain/notifications.js',
);

// Minimal in-memory D1 double: enough for emitNotification's two statements
// (preference lookup + INSERT OR IGNORE with a UNIQUE(user_id, dedupe_key)).
function fakeDb() {
  const prefs = new Map(); // `${user}|${cat}` -> {in_app, push}
  const rows = []; // notifications
  const seen = new Set(); // `${user}|${dedupe}`
  return {
    prefs,
    rows,
    prepare(sql) {
      return {
        _sql: sql,
        _args: [],
        bind(...args) {
          this._args = args;
          return this;
        },
        async first() {
          if (this._sql.includes('FROM notification_preferences')) {
            const [user, cat] = this._args;
            return prefs.get(`${user}|${cat}`) ?? null;
          }
          return null;
        },
        async all() {
          return { results: [] };
        },
        async run() {
          if (this._sql.includes('INSERT OR IGNORE INTO notifications')) {
            const [id, user, category, actor, title, body, dt, di, dc, et, ei, dedupe] = this._args;
            const key = `${user}|${dedupe}`;
            if (seen.has(key)) return { meta: { changes: 0 } };
            seen.add(key);
            rows.push({ id, user, category, actor, title, body, dt, di, dc, et, ei, dedupe });
            return { meta: { changes: 1 } };
          }
          return { meta: { changes: 0 } };
        },
      };
    },
  };
}

test('every category has a default', () => {
  for (const cat of NOTIFICATION_CATEGORIES) {
    assert.ok(CATEGORY_DEFAULTS[cat], `missing default for ${cat}`);
  }
});

test('emitNotification writes one row and returns its id', async () => {
  const db = fakeDb();
  const id = await emitNotification(db, {
    userId: 'u1',
    category: 'race_joined',
    title: 'Ada joined Squat Sprint',
    actorUserId: 'u2',
    dest: { type: 'race', id: 'r1' },
    dedupeKey: 'race_joined:r1:u2',
  });
  assert.ok(id);
  assert.equal(db.rows.length, 1);
  assert.equal(db.rows[0].dt, 'race');
  assert.equal(db.rows[0].di, 'r1');
});

test('a repeat emit with the same dedupe key is a no-op', async () => {
  const db = fakeDb();
  const opts = {
    userId: 'u1',
    category: 'crew_request',
    title: 'Ada wants to connect',
    dedupeKey: 'crew_request:u2',
  };
  const first = await emitNotification(db, opts);
  const second = await emitNotification(db, opts);
  assert.ok(first);
  assert.equal(second, null);
  assert.equal(db.rows.length, 1);
});

test('a category turned off in preferences suppresses the row', async () => {
  const db = fakeDb();
  db.prefs.set('u1|crew_request_accepted', { in_app: 0, push: 0 });
  const id = await emitNotification(db, {
    userId: 'u1',
    category: 'crew_request_accepted',
    title: 'x',
  });
  assert.equal(id, null);
  assert.equal(db.rows.length, 0);
});

test('safeEmit never throws (db failure is swallowed)', async () => {
  const brokenDb = {
    prepare() {
      return {
        bind() {
          return this;
        },
        first() {
          throw new Error('db down');
        },
        run() {
          throw new Error('db down');
        },
      };
    },
  };
  // safeEmit takes a Hono-style context: { env: { DB }, executionCtx }.
  await safeEmit(
    { env: { DB: brokenDb }, executionCtx: { waitUntil() {} } },
    { userId: 'u1', category: 'race_joined', title: 'x' },
  );
});

test('safeEmit with a working db + push dormant writes the row, no throw', async () => {
  const db = fakeDb();
  await safeEmit(
    { env: { DB: db }, executionCtx: { waitUntil: (p) => p } },
    {
      userId: 'u1',
      category: 'race_joined',
      title: 'Ada joined',
      dedupeKey: 'x',
    },
  );
  assert.equal(db.rows.length, 1);
});

// No private profiles: the legacy profiles.private_profile column is unused.
// Real SQLite semantics (prod schema snapshot) driving the compiled app.
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
const REVIEWER_PASSWORD = 'unused-in-this-suite';
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
      // SELECT / RETURNING statements inside a batch yield rows, like D1.
      if (/^\s*SELECT\b/i.test(sql) || /\bRETURNING\b/i.test(sql)) {
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

  const user = (id, { name = id, username = null, flagPrivate = false } = {}) => {
    exec("INSERT INTO users (id, primary_email, status, terms_accepted_at, created_at, updated_at) VALUES (?, ?, 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)", id, `${id}@example.com`);
    exec('INSERT INTO profiles (user_id, full_name, username, avatar_url, private_profile) VALUES (?, ?, ?, ?, ?)', id, name, username, `https://x/${id}.jpg`, flagPrivate ? 1 : 0);
    exec('INSERT INTO people (id, person_key, user_id, display_name) VALUES (?, ?, ?, ?)', `p-${id}`, `user-${id}`, id, name);
  };
  const raceWith = (id, creator, others) => {
    exec(
      `INSERT INTO races (id, creator_id, title, race_type, format, verification_type, status, visibility, scoring_rule,
         score_direction, target_value, target_unit, metric, verifier_type, proof_review_mode, created_at, updated_at)
       VALUES (?, ?, 'Race', 'most_in_window', 'most_in_window', 'manual', 'active', 'crew_only', 'cumulative_sum',
         'higher', 100, 'pages', 'reps', 'manual_log', 'auto_accept', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)`,
      id, creator,
    );
    [[creator, 'creator'], ...others.map((u) => [u, 'racer'])].forEach(([u, role], i) => {
      exec(
        "INSERT INTO race_members (id, race_id, person_id, user_id, role, status, joined_at) VALUES (?, ?, ?, ?, 'racer', 'active', datetime('now', ?))",
        `rm-${id}-${u}`, id, `p-${u}`, u, `-${1000 - i} seconds`,
      );
      exec('INSERT INTO race_progress (id, race_id, user_id, progress_value, progress_percent) VALUES (?, ?, ?, 0, 0)', `rp-${id}-${u}`, id, u);
    });
  };
  return { sqlite, db, env, req, q, one, exec, user, raceWith, flush: async () => { await Promise.all(pending.splice(0)); } };
}

const crewRows = (w, a, b) =>
  w.q('SELECT user_id, crew_user_id, status, requested_by FROM crew_connections WHERE (user_id = ? AND crew_user_id = ?) OR (user_id = ? AND crew_user_id = ?) ORDER BY user_id', a, b, b, a);

test('a user flagged private_profile=1 in the DB is fully visible to strangers in race identity', async () => {
  const w = world();
  w.user('priv', { name: 'Riley Chen', username: 'riley', flagPrivate: true });
  w.user('viewer', { name: 'Vee Viewer' });
  w.raceWith('r1', 'viewer', ['priv']); // not crew with each other
  const res = await w.req('viewer', 'GET', '/races/r1');
  assert.equal(res.status, 200, res.text);
  const p = res.json.race.participants.find((x) => x.userId === 'priv');
  assert.equal(p.displayName, 'Riley Chen');
  assert.equal(p.profilePhotoUrl, 'https://x/priv.jpg');
  assert.equal(w.q("SELECT 1 FROM crew_connections").length, 0);

  // Invite preview to a stranger shows the real card, isPrivate always false.
  const minted = await w.req('priv', 'POST', '/invites', { kind: 'crew_connect' });
  assert.equal(minted.status, 200, minted.text);
  const prev = await w.req('viewer', 'GET', `/invites/${minted.json.token}`);
  assert.equal(prev.status, 200, prev.text);
  assert.equal(prev.json.preview.person.displayName, 'Riley Chen');
  assert.equal(prev.json.preview.person.profilePhotoUrl, 'https://x/priv.jpg');
  assert.equal(prev.json.preview.person.isPrivate, false);

  // User lookup: real identity, legacy key false.
  const u = await w.req('viewer', 'GET', '/users/priv');
  assert.equal(u.status, 200, u.text);
  assert.equal(u.json.user.displayName, 'Riley Chen');
  assert.equal(u.json.user.isPrivate, false);
});

test('blocked users are still anonymized in race identity, both ways', async () => {
  const w = world();
  w.user('a', { name: 'Ann A' });
  w.user('b', { name: 'Bo B' });
  w.user('c', { name: 'Cy C' });
  w.raceWith('r1', 'a', ['b', 'c']);
  w.exec("INSERT INTO blocked_users (id, user_id, blocked_user_id) VALUES ('bl1', 'a', 'b')");
  const seenByA = await w.req('a', 'GET', '/races/r1');
  assert.equal(seenByA.status, 200, seenByA.text);
  const nameFor = (res, id) => res.json.race.participants.find((x) => x.userId === id).displayName;
  assert.equal(nameFor(seenByA, 'b'), 'Private User'); // blocked by viewer
  assert.equal(nameFor(seenByA, 'c'), 'Cy C');
  const seenByB = await w.req('b', 'GET', '/races/r1');
  assert.equal(seenByB.status, 200, seenByB.text);
  assert.equal(nameFor(seenByB, 'a'), 'Private User'); // viewer blocked by them
  assert.equal(nameFor(seenByB, 'c'), 'Cy C');
});

test('crew connect on any user yields pending; a mutual pending heals to active', async () => {
  const w = world();
  w.user('me');
  w.user('open');
  w.user('priv', { flagPrivate: true });
  for (const target of ['open', 'priv']) {
    const res = await w.req('me', 'POST', '/crew/add', { userId: target });
    assert.equal(res.status, 200, res.text);
    assert.equal(res.json.status, 'pending');
    const rows = crewRows(w, 'me', target);
    assert.equal(rows.length, 2);
    for (const r of rows) {
      assert.equal(r.status, 'pending');
      assert.equal(r.requested_by, 'me');
    }
    // Re-adding my own pending request stays pending.
    const again = await w.req('me', 'POST', '/crew/add', { userId: target });
    assert.equal(again.json.status, 'pending');
  }
  // The other side adding me back = accepting their incoming request.
  const back = await w.req('open', 'POST', '/crew/add', { userId: 'me' });
  assert.equal(back.status, 200, back.text);
  assert.equal(back.json.status, 'active');
  for (const r of crewRows(w, 'me', 'open')) assert.equal(r.status, 'active');
  // Active stays active.
  const stay = await w.req('me', 'POST', '/crew/add', { userId: 'open' });
  assert.equal(stay.json.status, 'active');
  // The still-pending private-flagged target accepts explicitly.
  const acc = await w.req('priv', 'POST', '/crew/requests/me/accept');
  assert.equal(acc.json.status, 'active');
});

test('POST /profile with only privateProfile:true succeeds and changes nothing', async () => {
  const w = world();
  w.user('u1', { name: 'Una U', username: 'una' });
  const before = w.one('SELECT * FROM profiles WHERE user_id = ?', 'u1');
  const res = await w.req('u1', 'POST', '/profile', { privateProfile: true });
  assert.equal(res.status, 200, res.text);
  assert.equal(res.json.privateProfile, false);
  assert.equal(res.json.fullName, 'Una U');
  assert.deepEqual(w.one('SELECT * FROM profiles WHERE user_id = ?', 'u1'), before);
  const me = await w.req('u1', 'GET', '/profile/me');
  assert.equal(me.json.privateProfile, false);
  // Combined with a real field, only the real field is applied.
  const both = await w.req('u1', 'POST', '/profile', { privateProfile: true, fullName: 'Una Two' });
  assert.equal(both.status, 200, both.text);
  assert.equal(both.json.fullName, 'Una Two');
  assert.equal(both.json.privateProfile, false);
  assert.equal(w.one('SELECT private_profile FROM profiles WHERE user_id = ?', 'u1').private_profile, 0);
});

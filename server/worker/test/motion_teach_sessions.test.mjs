// Teach Nuvo session telemetry — end to end on the REAL schema.
//
// The learned-motion observability loop: a consenting app's teach artifact
// (demos + V1 race spec + V2 spec + live-test trace) lands encrypted in R2 and
// indexed in D1; internal tooling lists it, then pulls the decrypted artifact
// for offline replay (tools/motion_v2/replay_session.py). A non-consenting
// account stores nothing — not even an index row.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { DatabaseSync } from 'node:sqlite';
import { gunzipSync, gzipSync } from 'node:zlib';
import test from 'node:test';

const require = createRequire(import.meta.url);
const app = require('../.tmp-test-dist/index.js').default;
const { signJwt } = require('../.tmp-test-dist/lib/jwt.js');

const JWT_SECRET = 'test-secret';
const INTERNAL_KEY = 'internal-test-key';
const MASTER_KEY = 'test-motion-master-key';
const root = new URL('..', import.meta.url);
const SCHEMA = [
  readFileSync(new URL('test/fixtures/prod_schema_2026-09-28.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0042_achievements.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0043_proof_votes.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0044_custom_verifier_seed.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0045_teach_sessions.sql', root), 'utf8'),
];

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
      const info = sqlite.prepare(sql).run(...norm(args));
      return { success: true, meta: { changes: Number(info.changes), last_row_id: Number(info.lastInsertRowid) } };
    },
  });
  return { prepare: (sql) => stmt(sql) };
}

function world() {
  const sqlite = new DatabaseSync(':memory:');
  for (const sql of SCHEMA) sqlite.exec(sql);
  const db = d1(sqlite);
  const objects = new Map();
  const env = {
    DB: db,
    JWT_SECRET,
    INTERNAL_API_KEY: INTERNAL_KEY,
    MOTION_DATA_MASTER_KEY: MASTER_KEY,
    PROFILE_PHOTOS: {
      async put(key, body) { objects.set(key, body instanceof ArrayBuffer ? body : body.buffer.slice(body.byteOffset, body.byteOffset + body.byteLength)); },
      async get(key) {
        if (!objects.has(key)) return null;
        const buf = objects.get(key);
        return { body: buf, writeHttpMetadata() {}, async arrayBuffer() { return buf; } };
      },
    },
  };
  const exec = (sql, ...a) => sqlite.prepare(sql).run(...a);
  const one = (sql, ...a) => sqlite.prepare(sql).get(...a);
  const user = (id, { consent = 1 } = {}) => {
    exec(
      `INSERT INTO users (id, primary_email, status, terms_accepted_at, age_attested_at,
         motion_training_consent, motion_consent_version, motion_consented_at, created_at, updated_at)
       VALUES (?, ?, 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, ?, 'motion-training-v1', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)`,
      id, `${id}@example.com`, consent,
    );
  };
  const jwt = (sub) => signJwt({ sub, iat: 0, exp: 9999999999 }, JWT_SECRET);
  const internal = async (path) => {
    const res = await app.request(`/internal${path}`, { headers: { 'X-Internal-Key': INTERNAL_KEY } }, env);
    return { status: res.status, json: await res.json() };
  };
  const teach = async (sub, meta, artifactObj) => {
    const headers = {
      'Content-Type': 'application/gzip',
      'X-Teach-Session': Buffer.from(JSON.stringify(meta), 'utf8').toString('base64'),
    };
    if (sub) headers.Authorization = `Bearer ${await jwt(sub)}`;
    const res = await app.request('/teach-sessions', {
      method: 'POST',
      headers,
      body: gzipSync(JSON.stringify(artifactObj)),
    }, env);
    return { status: res.status, json: await res.json() };
  };
  return { env, objects, one, exec, user, internal, teach };
}

const ARTIFACT = {
  schema: 2,
  sessionId: 'MV2-20261014-ABCDEF',
  timestamp: '2026-10-14T12:00:00.000Z',
  meta: { platform: 'ios', appVersion: '1.4.0' },
  teaching: [{ index: 1, frames: [{ t: 0, raw: { leftWrist: [0.1, 0.2, 0, 0.9] } }] }],
  spec: { schema: 4, references: [1, 2, 3] },
  v1: { spec: { kind: 'custom_pose_sequence', canonicalSequence: [] } },
  liveTest: { finalCount: 3, matchTrace: [{ t: 10, decision: 'match' }] },
};

const META = {
  sessionId: 'MV2-20261014-ABCDEF',
  movementName: 'pull ups',
  outcome: 'used',
  engine: 'v2',
  demoCount: 3,
  frameCount: 420,
  durationMs: 31000,
  learned: true,
  v2Available: true,
  v2Learned: true,
  selfValidationPassed: true,
  liveTestMatched: true,
  usedForRace: true,
  schemaVersion: 2,
  appVersion: '1.4.0',
  gitCommit: 'abc123',
  modelVersion: 'mb-encoder-2026.10.0',
  matcherVersion: 'multi_reference/schema4',
};

test('teach session uploads, indexes, and decrypts for internal replay', async () => {
  const w = world();
  w.user('u1');

  const up = await w.teach('u1', META, ARTIFACT);
  assert.equal(up.status, 200, JSON.stringify(up.json));
  assert.equal(up.json.stored, true);
  assert.equal(up.json.sessionId, META.sessionId);

  // The stored R2 object is the encryption envelope, never plaintext landmarks.
  const row = w.one('SELECT * FROM motion_teach_sessions WHERE session_id = ?', META.sessionId);
  assert.ok(row, 'index row written');
  assert.equal(row.movement_name, 'pull ups');
  assert.equal(row.outcome, 'used');
  assert.equal(row.learned, 1);
  assert.equal(row.v2_learned, 1);
  assert.equal(row.self_validation_passed, 1);
  const stored = Buffer.from(w.objects.get(row.object_key));
  assert.ok(!stored.toString('utf8').includes('leftWrist'), 'artifact must be encrypted at rest');

  // Internal list: the triage view the CLI renders.
  const list = await w.internal('/teach-sessions?outcome=used');
  assert.equal(list.status, 200);
  assert.equal(list.json.count, 1);
  assert.equal(list.json.sessions[0].sessionId, META.sessionId);
  assert.equal(list.json.sessions[0].learned, true);
  assert.equal(list.json.sessions[0].liveTestMatched, true);

  const byMovement = await w.internal('/teach-sessions?movement=pull%20ups');
  assert.equal(byMovement.json.count, 1);
  const noMatch = await w.internal('/teach-sessions?movement=dips');
  assert.equal(noMatch.json.count, 0);

  // Internal get: the decrypted artifact replays offline byte-for-byte.
  const full = await w.internal(`/teach-sessions/${META.sessionId}`);
  assert.equal(full.status, 200);
  assert.equal(full.json.session.movementName, 'pull ups');
  assert.deepEqual(full.json.artifact, ARTIFACT);
  assert.equal(full.json.metadata.movementName, 'pull ups');

  // Replay tool contract: the artifact gunzips to the same JSON.
  const roundTrip = JSON.parse(gunzipSync(gzipSync(JSON.stringify(full.json.artifact))).toString());
  assert.equal(roundTrip.sessionId, META.sessionId);
});

test('a non-consenting account stores no artifact and no index row', async () => {
  const w = world();
  w.user('u2', { consent: 0 });
  const res = await w.teach('u2', { ...META, sessionId: 'MV2-20261014-BBBBBB' }, ARTIFACT);
  assert.equal(res.status, 200);
  assert.equal(res.json.stored, false);
  assert.equal(res.json.reason, 'motion_consent_off');
  assert.equal(w.one('SELECT COUNT(*) AS n FROM motion_teach_sessions').n, 0);
  assert.equal(w.objects.size, 0, 'no R2 object for a non-consenting user');
});

test('teach upload requires auth, valid session id, and an internal key to read', async () => {
  const w = world();
  w.user('u1');

  const anon = await w.teach(null, { ...META, sessionId: 'MV2-20261014-CCCCCC' }, ARTIFACT);
  assert.equal(anon.status, 401);

  const badId = await w.teach('u1', { ...META, sessionId: 'bad id!' }, ARTIFACT);
  assert.equal(badId.status, 400);

  const missing = await w.internal('/teach-sessions/MV2-00000000-XXXXXX');
  assert.equal(missing.status, 404);

  const noKey = await app.request('/internal/teach-sessions', {}, w.env);
  assert.equal(noKey.status, 403);
});

test('a failed teach is indexed with its failure stage — the triage signal', async () => {
  const w = world();
  w.user('u1');
  await w.teach('u1', {
    ...META,
    sessionId: 'MV2-20261014-DDDDDD',
    outcome: 'failed',
    learned: false,
    v2Learned: false,
    selfValidationPassed: false,
    liveTestMatched: null,
    usedForRace: false,
    failureStage: 'v2_learn',
    failureReason: 'self_validation:demos_too_different',
  }, { ...ARTIFACT, sessionId: 'MV2-20261014-DDDDDD', liveTest: undefined });

  const failed = await w.internal('/teach-sessions?outcome=failed');
  assert.equal(failed.json.count, 1);
  const s = failed.json.sessions[0];
  assert.equal(s.failureStage, 'v2_learn');
  assert.equal(s.failureReason, 'self_validation:demos_too_different');
  assert.equal(s.learned, false);
  assert.equal(s.liveTestMatched, null);

  const perUser = await w.internal('/users/u1/teach-sessions');
  assert.equal(perUser.json.count, 1);
});

test('re-uploading the same session id updates the index row in place', async () => {
  const w = world();
  w.user('u1');
  await w.teach('u1', { ...META, outcome: 'learned', usedForRace: false }, ARTIFACT);
  await w.teach('u1', META, ARTIFACT); // later state: the user tapped "Use this movement"
  assert.equal(w.one('SELECT COUNT(*) AS n FROM motion_teach_sessions').n, 1);
  const row = w.one('SELECT outcome, used_for_race FROM motion_teach_sessions');
  assert.equal(row.outcome, 'used');
  assert.equal(row.used_for_race, 1);
});

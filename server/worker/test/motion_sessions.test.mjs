import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { gzipSync } from 'node:zlib';
import test from 'node:test';

const require = createRequire(import.meta.url);

const app = require('../.tmp-test-dist/index.js').default;
const { signJwt } = require('../.tmp-test-dist/lib/jwt.js');

const JWT_SECRET = 'test-secret';
const INTERNAL_KEY = 'internal-test-key';

// ── Minimal fakes for D1 + R2 ─────────────────────────────────────────────────
function makeEnv({ withInternalKey = true } = {}) {
  const sessions = [];
  const objects = new Map();

  const DB = {
    prepare(sql) {
      const q = sql.replace(/\s+/g, ' ').trim();
      let args = [];
      return {
        bind(...a) { args = a; return this; },
        async run() {
          if (q.startsWith('INSERT INTO motion_sessions')) {
            const [, session_id, user_id, race_id, activity_id, kind, outcome,
              detected_value, goal_value, confidence, failed_rule_reason,
              started_at, ended_at, duration_ms, frame_count, schema_version,
              app_version, git_commit, verifier_version, model_version,
              object_key, metadata_json] = args;
            const existing = sessions.find((s) => s.session_id === session_id);
            const row = {
              session_id, user_id, race_id, activity_id, kind, outcome,
              detected_value, goal_value, confidence, failed_rule_reason,
              started_at, ended_at, duration_ms, frame_count, schema_version,
              app_version, git_commit, verifier_version, model_version,
              object_key, metadata_json,
              created_at: new Date().toISOString(),
            };
            if (existing) Object.assign(existing, row);
            else sessions.push(row);
          }
          return { success: true };
        },
        async first() {
          let rows = sessions.slice().reverse();
          if (q.includes('FROM users')) {
            return { id: args[0], primary_email: 'a@b.com', status: 'active', full_name: 'A', username: 'aaa' };
          }
          if (q.includes('session_id = ?')) rows = rows.filter((r) => r.session_id === args[0]);
          if (q.includes('user_id = ?')) rows = rows.filter((r) => r.user_id === args[0]);
          return rows[0] ?? null;
        },
        async all() {
          let rows = sessions.slice().reverse();
          if (q.includes("outcome IN ('failed', 'incomplete')")) {
            rows = rows.filter((r) => r.outcome === 'failed' || r.outcome === 'incomplete');
          }
          if (q.includes('user_id = ?')) rows = rows.filter((r) => r.user_id === args[0]);
          return { results: rows };
        },
      };
    },
  };

  const PROFILE_PHOTOS = {
    async put(key, body) { objects.set(key, body instanceof ArrayBuffer ? body : Buffer.from(body)); },
    async get(key) {
      if (!objects.has(key)) return null;
      const buf = objects.get(key);
      return { async arrayBuffer() { return buf; } };
    },
  };

  return {
    DB,
    PROFILE_PHOTOS,
    JWT_SECRET,
    INTERNAL_API_KEY: withInternalKey ? INTERNAL_KEY : undefined,
    GOOGLE_IOS_CLIENT_ID: '', APPLE_BUNDLE_ID: '', RESEND_API_KEY: '',
    RESEND_FROM_EMAIL: '', API_BASE_URL: '',
  };
}

function metaHeader(meta) {
  return Buffer.from(JSON.stringify(meta)).toString('base64');
}

test('POST /motion-sessions rejects unauthenticated', async () => {
  const res = await app.request('/motion-sessions', { method: 'POST', body: 'x' }, makeEnv());
  assert.equal(res.status, 401);
});

test('POST /motion-sessions rejects a missing metadata header', async () => {
  const token = await signJwt({ sub: 'u1', iat: 0, exp: 9999999999 }, JWT_SECRET);
  const res = await app.request('/motion-sessions', {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}` },
    body: gzipSync(Buffer.from('{}')),
  }, makeEnv());
  assert.equal(res.status, 400);
});

test('internal routes are 503 when INTERNAL_API_KEY is unset', async () => {
  const res = await app.request('/internal/motion-sessions/ms_abc', {}, makeEnv({ withInternalKey: false }));
  assert.equal(res.status, 503);
});

test('internal routes are 403 without the key', async () => {
  const res = await app.request('/internal/motion-sessions/ms_abc', {}, makeEnv());
  assert.equal(res.status, 403);
});

test('round-trip: upload a session, then fetch the full artifact internally', async () => {
  const env = makeEnv();
  const token = await signJwt({ sub: 'user-42', iat: 0, exp: 9999999999 }, JWT_SECRET);

  const artifact = {
    schemaVersion: 1,
    sessionId: 'ms_deadbeef',
    result: { outcome: 'failed', detectedValue: 3, failedRuleReason: 'depth_not_reached' },
    events: [{ t: 1200, type: 'rejection', detail: 'shallow rep' }],
    frames: [],
  };
  const meta = {
    sessionId: 'ms_deadbeef', kind: 'preset', activityId: 'squats', raceId: 'race-9',
    outcome: 'failed', detectedValue: 3, goalValue: 10, confidence: 0.4,
    failedRuleReason: 'depth_not_reached', startedAt: '2026-09-07T00:00:00Z',
    endedAt: '2026-09-07T00:00:20Z', durationMs: 20000, frameCount: 0,
    schemaVersion: 1, appVersion: 'dev', gitCommit: 'abc123',
    verifierVersion: 'nuvo-ai-motion-v2', modelVersion: 'mlkit-pose-base',
  };

  const up = await app.request('/motion-sessions', {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'X-Motion-Session': metaHeader(meta) },
    body: gzipSync(Buffer.from(JSON.stringify(artifact))),
  }, env);
  assert.equal(up.status, 200);
  assert.equal((await up.json()).sessionId, 'ms_deadbeef');

  const byId = await app.request('/internal/motion-sessions/ms_deadbeef', {
    headers: { 'X-Internal-Key': INTERNAL_KEY },
  }, env);
  assert.equal(byId.status, 200);
  const payload = await byId.json();
  assert.equal(payload.session.activityId, 'squats');
  assert.equal(payload.session.outcome, 'failed');
  assert.equal(payload.artifact.sessionId, 'ms_deadbeef');
  assert.equal(payload.artifact.result.failedRuleReason, 'depth_not_reached');

  const latest = await app.request('/internal/users/user-42/motion-sessions/latest', {
    headers: { 'X-Internal-Key': INTERNAL_KEY },
  }, env);
  assert.equal(latest.status, 200);
  assert.equal((await latest.json()).artifact.sessionId, 'ms_deadbeef');

  const failed = await app.request('/internal/motion-sessions/failed', {
    headers: { 'X-Internal-Key': INTERNAL_KEY },
  }, env);
  assert.equal(failed.status, 200);
  assert.equal((await failed.json()).count, 1);
});

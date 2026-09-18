import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test from 'node:test';

const require = createRequire(import.meta.url);
const app = require('../.tmp-test-dist/index.js').default;
const { signJwt } = require('../.tmp-test-dist/lib/jwt.js');

const JWT_SECRET = 'verification-test-secret';
const releaseRow = {
  id: 'push_ups-release-1',
  activity_id: 'push_ups',
  semver: '1.0.0',
  change_class: 'minor',
  engine_type: 'native_v1',
  spec_schema_version: 1,
  spec_json: '{"activityId":"push_ups","measurementType":"repetitions"}',
  checksum: 'sha256:pushups-release-1',
  required_capabilities_json: '["pose_landmarks_v1"]',
  minimum_app_build: 'legacy-native-runtime',
  compatibility_group: 'pushups-native-v1',
  status: 'stable',
  release_notes: 'test release',
  created_at: '2026-09-17T00:00:00Z',
  published_at: '2026-09-17T00:00:00Z',
  parent_release_id: null,
};

function makeEnv() {
  const sessions = new Map();
  const DB = {
    prepare(sql) {
      const q = sql.replace(/\s+/g, ' ').trim();
      let args = [];
      return {
        bind(...values) { args = values; return this; },
        async first() {
          if (q.includes('FROM races')) return { id: args[0], activity_id: 'push_ups', status: 'active' };
          if (q.includes('FROM race_members')) return { id: 'member-1' };
          if (q.includes('FROM race_verifier_assignments')) {
            return {
              race_id: 'race-1', activity_id: 'push_ups', release_id: releaseRow.id,
              release_checksum: releaseRow.checksum, assignment_policy: 'follow_compatible_patch',
              compatibility_group: releaseRow.compatibility_group, assignment_reason: 'race_created',
            };
          }
          if (q.includes('FROM verifier_releases')) return releaseRow;
          if (q.includes('FROM activity_channel_releases')) {
            return {
              release_id: releaseRow.id, checksum: releaseRow.checksum,
              compatibility_group: releaseRow.compatibility_group, change_class: releaseRow.change_class,
              status: releaseRow.status,
            };
          }
          if (q.includes('FROM verification_sessions')) {
            if (q.includes('status IN')) return null;
            const row = sessions.get(args[0]);
            return row && row.user_id === args[1] ? row : null;
          }
          return null;
        },
        async run() {
          if (q.startsWith('INSERT INTO verification_sessions')) {
            const [id, raceId, userId, activityId, releaseId, checksum, schema, engine, appVersion, appBuild, caps] = args;
            sessions.set(id, {
              id, race_id: raceId, user_id: userId, activity_id: activityId,
              release_id: releaseId, release_checksum: checksum, spec_schema_version: schema,
              engine_type: engine, app_version: appVersion, app_build: appBuild,
              runtime_capabilities_json: caps, status: 'created', result_value: null,
              confidence: null, failure_reason: null, started_at: null, completed_at: null,
              motion_session_id: null, created_at: '2026-09-17T00:00:00Z',
            });
          } else if (q.startsWith('UPDATE verification_sessions')) {
            const id = args[q.includes("status = 'running'") ? 0 : 5];
            const row = sessions.get(id);
            if (row && q.includes("status = 'running'")) {
              row.status = 'running';
              row.started_at = '2026-09-17T00:01:00Z';
            } else if (row) {
              row.status = args[0];
              row.result_value = args[1];
              row.confidence = args[2];
              row.failure_reason = args[3];
              row.motion_session_id = args[4];
              row.completed_at = '2026-09-17T00:02:00Z';
              row.started_at ??= '2026-09-17T00:01:00Z';
            }
          }
          return { success: true };
        },
      };
    },
  };
  return {
    DB,
    JWT_SECRET,
    GOOGLE_IOS_CLIENT_ID: '', APPLE_BUNDLE_ID: '', RESEND_API_KEY: '',
    RESEND_FROM_EMAIL: '', API_BASE_URL: '', PROFILE_PHOTOS: {},
  };
}

test('verification session freezes a release and rejects a mismatched completion', async () => {
  const env = makeEnv();
  const token = await signJwt({ sub: 'user-1', iat: 0, exp: 9999999999 }, JWT_SECRET);
  const headers = { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
  const createdResponse = await app.request('/races/race-1/verification-sessions', {
    method: 'POST', headers,
    body: JSON.stringify({ appVersion: '0.1.0', appBuild: '42', runtimeCapabilities: ['pose_landmarks_v1'] }),
  }, env);
  assert.equal(createdResponse.status, 201);
  const created = await createdResponse.json();
  assert.equal(created.session.releaseId, releaseRow.id);
  assert.equal(created.verifier.checksum, releaseRow.checksum);
  const sessionId = created.session.id;

  const startedResponse = await app.request(`/verification-sessions/${sessionId}/start`, { method: 'POST', headers }, env);
  assert.equal(startedResponse.status, 200);
  assert.equal((await startedResponse.json()).session.status, 'running');

  const mismatchResponse = await app.request(`/verification-sessions/${sessionId}/complete`, {
    method: 'POST', headers,
    body: JSON.stringify({ releaseId: releaseRow.id, releaseChecksum: 'sha256:wrong', resultValue: 6 }),
  }, env);
  assert.equal(mismatchResponse.status, 409);
  assert.equal((await mismatchResponse.json()).code, 'release_mismatch');
});

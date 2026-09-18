import test from 'node:test';
import assert from 'node:assert/strict';

const { assignmentForNextSession } = await import(
  '../.tmp-test-dist/domain/motionAssignments.js'
);

function fakeDb({ openSession = false } = {}) {
  const updates = [];
  const oldRelease = {
    id: 'push_ups-release-1',
    activity_id: 'push_ups',
    semver: '1.0.0',
    change_class: 'minor',
    engine_type: 'native_v1',
    spec_schema_version: 1,
    spec_json: '{"activityId":"push_ups"}',
    checksum: 'sha256:old',
    required_capabilities_json: '[]',
    minimum_app_build: 'legacy',
    compatibility_group: 'pushups-v1',
    status: 'stable',
    release_notes: '',
    created_at: '2026-09-17T00:00:00Z',
    published_at: '2026-09-17T00:00:00Z',
    parent_release_id: null,
  };
  const newRelease = {
    ...oldRelease,
    id: 'push_ups-release-2',
    semver: '1.0.1',
    change_class: 'patch',
    checksum: 'sha256:new',
  };
  return {
    updates,
    prepare(sql) {
      return {
        bind(...args) {
          return {
            async first() {
              if (sql.includes('FROM race_verifier_assignments')) {
                return {
                  race_id: 'race-1',
                  activity_id: 'push_ups',
                  release_id: 'push_ups-release-1',
                  release_checksum: 'sha256:old',
                  assignment_policy: 'follow_compatible_patch',
                  compatibility_group: 'pushups-v1',
                  assignment_reason: 'race_created',
                };
              }
              if (sql.includes('FROM verifier_releases')) {
                return args[0] === 'push_ups-release-2' ? newRelease : oldRelease;
              }
              if (sql.includes('FROM activity_channel_releases')) {
                return {
                  release_id: 'push_ups-release-2',
                  checksum: 'sha256:new',
                  compatibility_group: 'pushups-v1',
                  change_class: 'patch',
                  status: 'stable',
                };
              }
              if (sql.includes('FROM verification_sessions')) {
                return openSession ? { id: 'session-1' } : null;
              }
              return null;
            },
            async run() {
              updates.push({ sql, args });
              return { success: true };
            },
          };
        },
      };
    },
  };
}

test('compatible patch is adopted only between verification sessions', async () => {
  const db = fakeDb();
  const result = await assignmentForNextSession(db, 'race-1');
  assert.equal(result?.release.id, 'push_ups-release-2');
  assert.equal(result?.assignment.assignmentReason, 'compatible_patch');
  assert.equal(db.updates.length, 1);
});

test('open verification session keeps the race pinned to its current release', async () => {
  const db = fakeDb({ openSession: true });
  const result = await assignmentForNextSession(db, 'race-1');
  assert.equal(result?.release.id, 'push_ups-release-1');
  assert.equal(result?.assignment.releaseId, 'push_ups-release-1');
  assert.equal(db.updates.length, 0);
});

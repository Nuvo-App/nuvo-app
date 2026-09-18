import test from 'node:test';
import assert from 'node:assert/strict';

const { readMotionCatalog, readMotionRelease } = await import(
  '../.tmp-test-dist/domain/motionRegistry.js'
);

test('registry catalog maps a channel release without changing legacy activity identity', async () => {
  const db = {
    prepare(sql) {
      return {
        bind() {
          return {
            async all() {
              if (sql.includes('FROM motion_activities')) {
                return {
                  results: [{
                    id: 'arm_raises',
                    display_name: 'Arm Raises',
                    category: 'upper_body',
                    proof_label: 'arm raises',
                    measurement_type: 'repetitions',
                    metric: 'reps',
                    suggested_targets_json: '[10,20]',
                    supported_formats_json: '["first_to_goal"]',
                    icon_key: 'sports_gymnastics',
                    sort_priority: 2,
                    featured: 0,
                    availability: 'supported',
                    metadata_json: '{}',
                    release_id: 'arm_raises-2026.09.0',
                    release_checksum: 'abc123',
                    engine_type: 'native_v1',
                    required_capabilities_json: '["pose_landmarks_v1","state_machine_v1"]',
                    minimum_app_build: 'remote-runtime-1',
                  }],
                };
              }
              return { results: [] };
            },
            async first() {
              return { version: '2026-09-17T00:00:00Z' };
            },
          };
        },
        async first() {
          return { version: '2026-09-17T00:00:00Z' };
        },
      };
    },
  };

  const catalog = await readMotionCatalog(db, 'stable');
  assert.equal(catalog.activities.length, 1);
  assert.equal(catalog.activities[0].id, 'arm_raises');
  assert.equal(catalog.activities[0].legacy?.validatorKey, 'arm_raises_v1');
  assert.equal(catalog.activities[0].releaseId, 'arm_raises-2026.09.0');
  assert.deepEqual(catalog.activities[0].requiredCapabilities, [
    'pose_landmarks_v1',
    'state_machine_v1',
  ]);
});

test('release reader parses the immutable spec and preserves checksum', async () => {
  const db = {
    prepare() {
      return {
        bind() {
          return {
            async first() {
              return {
                id: 'arm_raises-2026.09.0',
                activity_id: 'arm_raises',
                semver: '2026.09.0',
                change_class: 'minor',
                engine_type: 'native_v1',
                spec_schema_version: 1,
                spec_json: '{"specSchemaVersion":1,"releaseId":"arm_raises-2026.09.0","activityId":"arm_raises","engineType":"native_v1","nativeValidatorKey":"arm_raises_v1"}',
                checksum: 'sha256:fixture',
                required_capabilities_json: '["pose_landmarks_v1"]',
                minimum_app_build: 'remote-runtime-1',
                compatibility_group: 'arm_raises-native-v1',
                status: 'stable',
                release_notes: 'baseline',
                created_at: '2026-09-17T00:00:00Z',
                published_at: '2026-09-17T00:00:00Z',
                parent_release_id: null,
              };
            },
          };
        },
      };
    },
  };

  const release = await readMotionRelease(db, 'arm_raises-2026.09.0');
  assert.equal(release?.id, 'arm_raises-2026.09.0');
  assert.equal(release?.spec.activityId, 'arm_raises');
  assert.equal(release?.checksum, 'sha256:fixture');
});

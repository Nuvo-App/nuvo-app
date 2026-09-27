import test from 'node:test';
import assert from 'node:assert/strict';

const { normalizeActivityIdLoose, normalizeActivityId } = await import(
  '../.tmp-test-dist/domain/raceActivities.js'
);
const {
  registryConfigFromBody,
  assertSubmissionCompatible,
} = await import('../.tmp-test-dist/domain/raceValidation.js');
const {
  rolloutBucketForUser,
  stableReleaseForActivity,
} = await import('../.tmp-test-dist/domain/motionAssignments.js');
const { validateMotionVerifierSpec } = await import(
  '../.tmp-test-dist/domain/motionSpec.js'
);

// The same fixture published by migration 0033 — a motion that exists ONLY
// as control-plane data, unknown to every compiled identity list.
const REMOTE_TEST_SPEC = {
  specSchemaVersion: 1,
  releaseId: 'remote_test_motion-2026.10.0',
  activityId: 'remote_test_motion',
  engineType: 'alternating_rep_v1',
  measurementType: 'repetitions',
  requiredCapabilities: [
    'pose_landmarks_v1',
    'derived_features_v1',
    'alternating_rep_v1',
  ],
  requiredLandmarks: [
    'leftShoulder',
    'rightShoulder',
    'leftWrist',
    'rightWrist',
  ],
  stableFrames: 2,
  leftRules: [
    { point: 'leftWrist', axis: 'y', operator: 'lt', threshold: 0.35 },
  ],
  rightRules: [
    { point: 'rightWrist', axis: 'y', operator: 'lt', threshold: 0.35 },
  ],
  activity: {
    displayName: 'Reach Taps',
    measurementType: 'repetitions',
    defaultTarget: 10,
    preferredCameraView: 'front',
    instructions: [
      'Stand facing the camera with your full body in frame.',
      'Raise one hand overhead, then the other.',
      'Alternate hands cleanly to count each rep.',
    ],
    unit: 'reach taps',
    coachingTextActive: 'Reach up with one hand, then the other',
    coachingTextIncomplete: 'Keep both arms visible',
  },
};

const REGISTRY_ACTIVITY = {
  id: 'remote_test_motion',
  displayName: 'Reach Taps',
  category: 'upper_body',
  proofLabel: 'reach taps',
  measurementType: 'repetitions',
  metric: 'reps',
  suggestedTargets: [5, 10, 20, 40],
  supportedFormats: ['first_to_goal', 'most_in_window', 'best_attempt'],
  iconKey: 'sports_gymnastics',
  sortPriority: 90,
  featured: false,
  availability: 'supported',
  releaseId: 'remote_test_motion-2026.10.0',
  releaseChecksum: 'sha256:fixture',
  engineType: 'alternating_rep_v1',
  requiredCapabilities: [],
  minimumAppBuild: null,
  legacy: null,
  metadata: {},
};

test('normalizeActivityIdLoose preserves remote IDs without remapping', () => {
  // Registry-only IDs survive verbatim — never coerced to another motion.
  assert.equal(
    normalizeActivityIdLoose('remote_test_motion'),
    'remote_test_motion',
  );
  // Strict normalizer still returns undefined for the same input, proving
  // the loose path is what carries remote identity.
  assert.equal(normalizeActivityId('remote_test_motion'), undefined);
  // Known IDs canonicalize exactly like the strict path.
  assert.equal(normalizeActivityIdLoose('Push Ups'), 'push_ups');
  assert.equal(normalizeActivityIdLoose('plank'), 'plank_hold');
  // Unsafe input is rejected, not normalized into something else.
  assert.equal(normalizeActivityIdLoose("x'; DROP TABLE races;--"), undefined);
  assert.equal(normalizeActivityIdLoose(''), undefined);
  assert.equal(normalizeActivityIdLoose(null), undefined);
  // Hyphens/spaces normalize to the snake_case registry shape.
  assert.equal(
    normalizeActivityIdLoose('Future Motion 42'),
    'future_motion_42',
  );
});

test('registryConfigFromBody builds a config from registry bounds', () => {
  const config = registryConfigFromBody(
    { activityId: 'remote_test_motion', targetValue: 10, format: 'first_to_goal' },
    REGISTRY_ACTIVITY,
  );
  assert.deepEqual(config.error, undefined);
  assert.equal(config.activityId, 'remote_test_motion');
  assert.equal(config.metric, 'reps');
  assert.equal(config.format, 'first_to_goal');
  assert.equal(config.verificationMethod, 'camera_pose');

  const badFormat = registryConfigFromBody(
    { targetValue: 10, format: 'timed_attempt' },
    REGISTRY_ACTIVITY,
  );
  assert.ok('error' in badFormat);

  const badMetric = registryConfigFromBody(
    { targetValue: 10, metric: 'seconds' },
    REGISTRY_ACTIVITY,
  );
  assert.ok('error' in badMetric);
});

test('assertSubmissionCompatible accepts the raw remote activity ID', () => {
  const config = {
    activityId: 'remote_test_motion',
    metric: 'reps',
    format: 'first_to_goal',
    scoringRule: 'cumulative_sum',
    targetValue: 10,
    attemptDurationSeconds: null,
    attemptLimit: null,
    verificationMethod: 'camera_pose',
    timezone: 'America/New_York',
    startsAt: null,
    endsAt: null,
    recurrence: 'none',
  };
  // A proof payload carrying the server-owned ID is compatible.
  assert.equal(
    assertSubmissionCompatible(config, 'remote_test_motion', 'reps'),
    null,
  );
  // A proof claiming a different motion is still rejected.
  assert.equal(
    assertSubmissionCompatible(config, 'push_ups', 'reps'),
    'Verified movement does not match this race.',
  );
  // Compiled activities behave exactly as before.
  const pushups = { ...config, activityId: 'push_ups' };
  assert.equal(assertSubmissionCompatible(pushups, 'push_ups', 'reps'), null);
  assert.equal(
    assertSubmissionCompatible(pushups, 'pushups', 'reps'),
    null,
  );
});

test('motion spec validation accepts the fixture activity/package blocks', () => {
  const validated = validateMotionVerifierSpec(REMOTE_TEST_SPEC, {
    releaseId: 'remote_test_motion-2026.10.0',
    activityId: 'remote_test_motion',
  });
  assert.equal(validated.activityId, 'remote_test_motion');
  assert.equal(validated.activity.displayName, 'Reach Taps');

  const withPackage = {
    ...REMOTE_TEST_SPEC,
    package: {
      packageSchemaVersion: 1,
      assets: [
        {
          id: 'preview',
          type: 'preview_v1',
          sha256:
            'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2',
          url: 'https://assets.example/preview.json',
          bytes: 4096,
          required: false,
        },
      ],
    },
  };
  assert.doesNotThrow(() => validateMotionVerifierSpec(withPackage));

  assert.throws(
    () =>
      validateMotionVerifierSpec({
        ...REMOTE_TEST_SPEC,
        package: { packageSchemaVersion: 99, assets: [] },
      }),
    /package_schema_unsupported/,
  );
  assert.throws(
    () =>
      validateMotionVerifierSpec({
        ...REMOTE_TEST_SPEC,
        activity: { displayName: 'X', measurementType: 'repetitions', evil: true },
      }),
    /activity_unknown_key/,
  );
});

test('rollout bucket is deterministic per user+release', async () => {
  const a = await rolloutBucketForUser('user-1', 'release-1');
  const b = await rolloutBucketForUser('user-1', 'release-1');
  assert.equal(a, b);
  assert.ok(a >= 0 && a < 100);
  const other = await rolloutBucketForUser('user-2', 'release-1');
  assert.ok(other >= 0 && other < 100);
});

test('partial rollout serves pointer to in-bucket users, previous stable to out', async () => {
  const current = {
    id: 'remote_test_motion-2026.10.0',
    activity_id: 'remote_test_motion',
    semver: '2026.10.0',
    change_class: 'minor',
    engine_type: 'alternating_rep_v1',
    spec_schema_version: 1,
    spec_json: JSON.stringify(REMOTE_TEST_SPEC),
    checksum: 'sha256:current',
    required_capabilities_json: '[]',
    minimum_app_build: 'remote-runtime-v1',
    compatibility_group: 'remote_test_motion-remote-v1',
    status: 'stable',
    release_notes: '',
    created_at: '2026-10-01T00:00:00Z',
    published_at: '2026-10-01T00:00:00Z',
    parent_release_id: 'remote_test_motion-2026.09.0',
  };
  const previous = {
    ...current,
    id: 'remote_test_motion-2026.09.0',
    checksum: 'sha256:previous',
    spec_json: JSON.stringify({
      ...REMOTE_TEST_SPEC,
      releaseId: 'remote_test_motion-2026.09.0',
    }),
    published_at: '2026-09-01T00:00:00Z',
    parent_release_id: null,
  };
  const db = {
    prepare(sql) {
      return {
        bind(...args) {
          return {
            async first() {
              if (sql.includes('FROM activity_channel_releases')) {
                return { id: current.id, rollout_percent: 30 };
              }
              if (sql.includes('FROM verifier_releases') && sql.includes('id <>')) {
                return { id: previous.id };
              }
              if (sql.includes('FROM verifier_releases')) {
                return args[0] === previous.id ? previous : current;
              }
              return null;
            },
            async run() {
              return { success: true };
            },
          };
        },
      };
    },
  };

  // Find one user inside the 30% bucket and one outside — deterministic, so
  // these identities hold for every run.
  let inUser = null;
  let outUser = null;
  for (let i = 0; i < 500 && (!inUser || !outUser); i++) {
    const candidate = `user-${i}`;
    const bucket = await rolloutBucketForUser(candidate, current.id);
    if (bucket < 30 && !inUser) inUser = candidate;
    if (bucket >= 30 && !outUser) outUser = candidate;
  }
  assert.ok(inUser && outUser, 'fixture needs both bucket cohorts');

  const inRelease = await stableReleaseForActivity(db, 'remote_test_motion', inUser);
  assert.equal(inRelease?.id, current.id);

  const outRelease = await stableReleaseForActivity(db, 'remote_test_motion', outUser);
  assert.equal(outRelease?.id, previous.id);

  // Anonymous reads keep the pointer behavior.
  const anonRelease = await stableReleaseForActivity(db, 'remote_test_motion');
  assert.equal(anonRelease?.id, current.id);
});

import test from 'node:test';
import assert from 'node:assert/strict';

const { validateMotionVerifierSpec } = await import(
  '../.tmp-test-dist/domain/motionSpec.js'
);

// A canonical sequence_match_v1 spec — the shape the jump-squat fixture will
// publish (standing → crouch → extension → rep).
const SEQUENCE_SPEC = {
  specSchemaVersion: 1,
  releaseId: 'seq_test-2026.10.0',
  activityId: 'seq_test_motion',
  engineType: 'sequence_match_v1',
  measurementType: 'repetitions',
  requiredCapabilities: [
    'pose_landmarks_v1',
    'derived_features_v1',
    'sequence_match_v1',
  ],
  requiredLandmarks: ['leftHip', 'leftKnee', 'leftAnkle', 'leftWrist'],
  stableFrames: 2,
  repTimeoutMs: 8000,
  lostPoseMs: 1500,
  phases: [
    {
      id: 'standing',
      predicates: [
        {
          kind: 'angle',
          a: 'leftHip',
          b: 'leftKnee',
          c: 'leftAnkle',
          operator: 'gte',
          degrees: 160,
        },
      ],
      next: 'crouch',
    },
    {
      id: 'crouch',
      predicates: [
        {
          kind: 'angle',
          a: 'leftHip',
          b: 'leftKnee',
          c: 'leftAnkle',
          operator: 'lte',
          degrees: 110,
        },
      ],
      minDwellFrames: 2,
      breakToleranceFrames: 1,
      next: 'extension',
    },
    {
      id: 'extension',
      predicates: [
        {
          kind: 'angle',
          a: 'leftHip',
          b: 'leftKnee',
          c: 'leftAnkle',
          operator: 'gte',
          degrees: 160,
        },
        {
          kind: 'landmark_axis',
          point: 'leftWrist',
          axis: 'y',
          operator: 'lt',
          threshold: 0.45,
        },
      ],
      next: 'complete',
    },
  ],
};

const angleRule = { kind: 'angle', a: 'leftHip', b: 'leftKnee', c: 'leftAnkle', operator: 'gte', degrees: 160 };

function withPhases(phases) {
  return { ...SEQUENCE_SPEC, phases };
}

function withOverrides(overrides) {
  return { ...SEQUENCE_SPEC, ...overrides };
}

test('a valid sequence_match_v1 spec passes validation', () => {
  assert.doesNotThrow(() =>
    validateMotionVerifierSpec(SEQUENCE_SPEC, {
      releaseId: SEQUENCE_SPEC.releaseId,
      activityId: SEQUENCE_SPEC.activityId,
    }),
  );
});

test('all four predicate kinds validate', () => {
  const spec = withPhases([
    { id: 'a', predicates: [
      angleRule,
      { kind: 'landmark_axis', point: 'nose', axis: 'y', operator: 'lt', threshold: 0.5 },
      { kind: 'axis_delta', a: 'leftHip', b: 'leftKnee', axis: 'y', operator: 'lt', delta: -0.1 },
      { kind: 'segment_ratio', a: 'leftWrist', b: 'rightWrist', refA: 'leftShoulder', refB: 'rightShoulder', operator: 'gt', ratio: 1.2 },
    ], next: 'b' },
    { id: 'b', predicates: [angleRule], next: 'complete' },
  ]);
  assert.doesNotThrow(() => validateMotionVerifierSpec(spec));
});

test('unknown predicate kind or smuggled field is rejected', () => {
  for (const predicate of [
    { kind: 'velocity_expr', a: 'leftHip', operator: 'gt', threshold: 1 },
    { ...angleRule, expression: 'a + b' },
    { kind: 'angle', a: 'leftHip', b: 'leftKnee', c: 'leftAnkle', operator: 'gte' }, // missing degrees
    { kind: 'angle', a: 'leftHip', b: 'leftKnee', c: 'leftAnkle', operator: 'gte', degrees: 200 },
    { kind: 'segment_ratio', a: 'leftWrist', b: 'rightWrist', refA: 'leftShoulder', refB: 'rightShoulder', operator: 'gt', ratio: 9 },
    { kind: 'axis_delta', a: 'leftHip', b: 'leftKnee', axis: 'z', operator: 'lt', delta: 0.1 },
    { kind: 'landmark_axis', point: 'leftPinky', axis: 'y', operator: 'lt', threshold: 0.5 },
  ]) {
    assert.throws(() =>
      validateMotionVerifierSpec(withPhases([
        { id: 'a', predicates: [predicate], next: 'b' },
        { id: 'b', predicates: [angleRule], next: 'complete' },
      ])), undefined, JSON.stringify(predicate));
  }
});

test('non-linear chains are rejected (skips, backward edges, missing complete)', () => {
  for (const phases of [
    // skip-ahead link
    [
      { id: 'a', predicates: [angleRule], next: 'c' },
      { id: 'b', predicates: [angleRule], next: 'c' },
      { id: 'c', predicates: [angleRule], next: 'complete' },
    ],
    // backward edge
    [
      { id: 'a', predicates: [angleRule], next: 'b' },
      { id: 'b', predicates: [angleRule], next: 'a' },
    ],
    // self loop
    [
      { id: 'a', predicates: [angleRule], next: 'b' },
      { id: 'b', predicates: [angleRule], next: 'b' },
    ],
    // missing complete edge
    [
      { id: 'a', predicates: [angleRule], next: 'b' },
      { id: 'b', predicates: [angleRule], next: 'a' },
    ],
    // unknown next target
    [
      { id: 'a', predicates: [angleRule], next: 'b' },
      { id: 'b', predicates: [angleRule], next: 'nowhere' },
    ],
    // duplicate ids
    [
      { id: 'a', predicates: [angleRule], next: 'a' },
      { id: 'a', predicates: [angleRule], next: 'complete' },
    ],
  ]) {
    assert.throws(() => validateMotionVerifierSpec(withPhases(phases)));
  }
});

test('phase count and predicate bounds are enforced', () => {
  assert.throws(() => validateMotionVerifierSpec(withPhases([
    { id: 'a', predicates: [angleRule], next: 'complete' },
  ]))); // too few phases
  assert.throws(() => validateMotionVerifierSpec(withPhases(
    Array.from({ length: 9 }, (_, i) => ({
      id: `p${i}`, predicates: [angleRule], next: i === 8 ? 'complete' : `p${i + 1}`,
    })),
  ))); // too many phases
  assert.throws(() => validateMotionVerifierSpec(withPhases([
    { id: 'a', predicates: [], next: 'b' },
    { id: 'b', predicates: [angleRule], next: 'complete' },
  ]))); // empty predicates
  assert.throws(() => validateMotionVerifierSpec(withPhases([
    { id: 'a', predicates: Array(7).fill(angleRule), next: 'b' },
    { id: 'b', predicates: [angleRule], next: 'complete' },
  ]))); // too many predicates
  assert.throws(() => validateMotionVerifierSpec(withPhases([
    { id: 'a', predicates: [angleRule], minDwellFrames: 31, next: 'b' },
    { id: 'b', predicates: [angleRule], next: 'complete' },
  ]))); // dwell out of range
  assert.throws(() => validateMotionVerifierSpec(withPhases([
    { id: 'BadId', predicates: [angleRule], next: 'b' },
    { id: 'b', predicates: [angleRule], next: 'complete' },
  ]))); // invalid id shape
});

test('sequence fields are engine-scoped and repetitions-only', () => {
  // phases on another engine → reject
  assert.throws(() => validateMotionVerifierSpec({
    ...withOverrides({ engineType: 'alternating_rep_v1' }),
    leftRules: [{ point: 'nose', axis: 'y', operator: 'lt', threshold: 0.5 }],
    rightRules: [{ point: 'nose', axis: 'y', operator: 'lt', threshold: 0.5 }],
  }));
  // repTimeoutMs on hold engine → reject
  assert.throws(() => validateMotionVerifierSpec({
    specSchemaVersion: 1,
    releaseId: 'x-1.0.0',
    activityId: 'x',
    engineType: 'hold_v1',
    requiredLandmarks: ['nose'],
    holdRules: [{ point: 'nose', axis: 'y', operator: 'lt', threshold: 0.5 }],
    repTimeoutMs: 5000,
  }));
  // duration measurement → reject for sequence engine
  assert.throws(() => validateMotionVerifierSpec(
    withOverrides({ measurementType: 'duration' }),
  ));
  // out-of-range timing → reject
  assert.throws(() => validateMotionVerifierSpec(
    withOverrides({ repTimeoutMs: 100 }),
  ));
  assert.throws(() => validateMotionVerifierSpec(
    withOverrides({ lostPoseMs: 50 }),
  ));
  // missing phases on sequence engine → reject
  assert.throws(() => validateMotionVerifierSpec(
    withOverrides({ phases: undefined }),
  ));
});

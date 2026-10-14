import test from 'node:test';
import assert from 'node:assert/strict';

const { validateMotionVerifierSpec, MotionSpecValidationError } = await import(
  '../.tmp-test-dist/domain/motionSpec.js'
);

const valid = {
  specSchemaVersion: 1,
  releaseId: 'arm_raises-remote-2026.09.1',
  activityId: 'arm_raises',
  engineType: 'state_machine_v1',
  measurementType: 'repetitions',
  requiredCapabilities: ['pose_landmarks_v1', 'state_machine_v1'],
  requiredLandmarks: ['leftWrist', 'rightWrist'],
  stableFrames: 2,
  startRules: [
    { point: 'leftWrist', axis: 'y', operator: 'gte', threshold: 0.58 },
  ],
  activeRules: [
    { point: 'leftWrist', axis: 'y', operator: 'lte', threshold: 0.42 },
  ],
};

test('Worker accepts the same bounded declarative release shape as Dart', () => {
  const result = validateMotionVerifierSpec(valid, {
    releaseId: valid.releaseId,
    activityId: valid.activityId,
  });
  assert.equal(result.engineType, 'state_machine_v1');
});

test('Worker rejects unknown executable fields and unsafe thresholds', () => {
  assert.throws(
    () => validateMotionVerifierSpec({ ...valid, execute: 'code' }),
    (error) => error instanceof MotionSpecValidationError && error.message === 'unknown_spec_key',
  );
  assert.throws(
    () => validateMotionVerifierSpec({
      ...valid,
      activeRules: [{ ...valid.activeRules[0], threshold: 1.5 }],
    }),
    (error) => error instanceof MotionSpecValidationError && error.message === 'active_rules_threshold_invalid',
  );
});

test('Worker preserves native releases as an explicit rollback family', () => {
  const native = validateMotionVerifierSpec({
    specSchemaVersion: 1,
    releaseId: 'arm_raises-legacy-2026.09.0',
    activityId: 'arm_raises',
    engineType: 'native_v1',
    nativeValidatorKey: 'arm_raises_v1',
  });
  assert.equal(native.engineType, 'native_v1');
});

test('Worker accepts the dot-only basketball composition contract', () => {
  const basketball = {
    specSchemaVersion: 1,
    releaseId: 'basketball_shot-composition-2026.09.1',
    activityId: 'basketball_shot',
    engineType: 'object_composition_v1',
    measurementType: 'repetitions',
    requiredCapabilities: ['pose_landmarks_v1', 'object_dots_v1', 'object_composition_v1'],
    requiredLandmarks: ['leftWrist', 'rightWrist'],
    requiredObjects: [
      { id: 'ball', kind: 'ball', minLikelihood: 0.45 },
      { id: 'hoop', kind: 'hoop', minLikelihood: 0.55 },
    ],
    model: {
      modelVersion: 'basketball-yolox-s-800',
      inputSchemaVersion: 1,
      artifactSha256: 'dc5a5afe11ac75ba9c80f1975cb1f7dc8bc738a6a37a8a4ecfb78fa196b3b425',
      inputSize: 800,
    },
    composition: {
      states: ['ready', 'released', 'ascending', 'descending', 'made', 'missed'],
      transitions: [
        { from: 'ready', to: 'released', event: 'ball_released' },
        { from: 'released', to: 'ascending', event: 'ball_ascending' },
        { from: 'ascending', to: 'descending', event: 'ball_descending' },
        { from: 'descending', to: 'made', event: 'ball_through_hoop' },
        { from: 'ascending', to: 'missed', event: 'shot_timeout' },
        { from: 'descending', to: 'missed', event: 'shot_timeout' },
      ],
      startState: 'ready',
      terminalStates: ['made', 'missed'],
      ballObjectId: 'ball',
      hoopObjectId: 'hoop',
      stableFrames: 2,
      maxShotMs: 8000,
      controlDistance: 0.22,
      releaseDistance: 0.16,
      minUpwardVelocity: 0.06,
      minDownwardVelocity: 0.04,
      hoopPlaneTolerance: 0.08,
      madeRadius: 0.18,
    },
  };
  const result = validateMotionVerifierSpec(basketball, {
    releaseId: basketball.releaseId,
    activityId: basketball.activityId,
  });
  assert.equal(result.engineType, 'object_composition_v1');
});

test('Worker rejects an object composition with an unknown transition event', () => {
  const invalid = {
    specSchemaVersion: 1,
    releaseId: 'basketball_shot-composition-2026.09.1',
    activityId: 'basketball_shot',
    engineType: 'object_composition_v1',
    requiredLandmarks: ['leftWrist', 'rightWrist'],
    requiredObjects: [
      { id: 'ball', kind: 'ball', minLikelihood: 0.45 },
      { id: 'hoop', kind: 'hoop', minLikelihood: 0.55 },
    ],
    model: {
      modelVersion: 'basketball-yolox-s-800',
      inputSchemaVersion: 1,
      artifactSha256: 'dc5a5afe11ac75ba9c80f1975cb1f7dc8bc738a6a37a8a4ecfb78fa196b3b425',
      inputSize: 800,
    },
    model: {
      modelVersion: 'basketball-yolox-s-800',
      inputSchemaVersion: 1,
      artifactSha256: 'dc5a5afe11ac75ba9c80f1975cb1f7dc8bc738a6a37a8a4ecfb78fa196b3b425',
      inputSize: 800,
    },
    composition: {
      states: ['ready', 'made'],
      transitions: [{ from: 'ready', to: 'made', event: 'teleport' }],
      startState: 'ready',
      terminalStates: ['made'],
      ballObjectId: 'ball',
      hoopObjectId: 'hoop',
      stableFrames: 2,
      maxShotMs: 8000,
      controlDistance: 0.22,
      releaseDistance: 0.16,
      minUpwardVelocity: 0.06,
      minDownwardVelocity: 0.04,
      hoopPlaneTolerance: 0.08,
      madeRadius: 0.18,
    },
  };
  assert.throws(
    () => validateMotionVerifierSpec(invalid),
    (error) => error instanceof MotionSpecValidationError && error.message === 'composition_transition_reference_invalid',
  );
});

test('Worker accepts a motion_v2 learned-spec release envelope', () => {
  const v2 = {
    specSchemaVersion: 1,
    releaseId: 'pull_ups-mv2-2026.10.1',
    activityId: 'pull_ups',
    engineType: 'motion_v2',
    requiredCapabilities: ['pose_landmarks_v1', 'motion_v2'],
    activity: {
      displayName: 'Pull Ups',
      measurementType: 'repetitions',
      defaultTarget: 10,
      preferredCameraView: 'front_or_angle',
      instructions: ['Keep your whole body in frame.'],
    },
    motionV2Spec: {
      schema: 2,
      verifier: 'motion_v2',
      version: 1,
      name: 'Pull Ups',
      references: [
        { proto: [0.1, 0.2], traj: [[0.1, 0.2]], length: 90 },
      ],
    },
  };
  const result = validateMotionVerifierSpec(v2, {
    releaseId: v2.releaseId,
    activityId: v2.activityId,
  });
  assert.equal(result.engineType, 'motion_v2');
});

test('Worker rejects a motion_v2 release missing capability or refs', () => {
  const base = {
    specSchemaVersion: 1,
    releaseId: 'r1',
    activityId: 'pull_ups',
    engineType: 'motion_v2',
    requiredCapabilities: ['motion_v2'],
    motionV2Spec: {
      verifier: 'motion_v2',
      references: [{ proto: [0.1], traj: [[0.1]], length: 90 }],
    },
  };
  assert.throws(
    () => validateMotionVerifierSpec({ ...base, requiredCapabilities: [] }),
    (error) => error instanceof MotionSpecValidationError && error.message === 'motion_v2_capability_missing',
  );
  assert.throws(
    () => validateMotionVerifierSpec({ ...base, motionV2Spec: { verifier: 'motion_v2', references: [] } }),
    (error) => error instanceof MotionSpecValidationError && error.message === 'motion_v2_spec_invalid',
  );
  assert.throws(
    () => validateMotionVerifierSpec({ ...base, motionV2Spec: { verifier: 'custom_pose_sequence', references: [{ proto: [0.1], traj: [[0.1]] }] } }),
    (error) => error instanceof MotionSpecValidationError && error.message === 'motion_v2_spec_invalid',
  );
});

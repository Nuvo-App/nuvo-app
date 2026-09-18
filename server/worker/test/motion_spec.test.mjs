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

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const { validateMotionVerifierSpec, MotionSpecValidationError, NATIVE_TUNABLES } =
  await import('../.tmp-test-dist/domain/motionSpec.js');

const fixture = JSON.parse(readFileSync(new URL('./fixtures/native_tunables.json', import.meta.url)));

const spec = (activityId = 'high_knees', params = { raiseLift: -0.4 }) => ({
  specSchemaVersion: 1,
  releaseId: `${activityId}-tuned-test`,
  activityId,
  engineType: 'native_tuned_v1',
  measurementType: 'repetitions',
  requiredCapabilities: ['pose_landmarks_v1', 'native_tuned_v1'],
  requiredLandmarks: ['leftShoulder', 'rightShoulder', 'leftHip', 'rightHip', 'leftKnee', 'rightKnee'],
  stableFrames: 3,
  params,
});

const reason = (s) => {
  try { validateMotionVerifierSpec(s); return null; }
  catch (e) { assert.ok(e instanceof MotionSpecValidationError); return e.message; }
};

test('tunable table matches the shared fixture (Dart asserts the same file)', () => {
  assert.deepEqual(NATIVE_TUNABLES, fixture.tunables);
});

test('accepts in-range params and rejects the rest', () => {
  assert.equal(reason(spec()), null);
  assert.equal(reason(spec('high_knees', {})), null);
  assert.equal(reason(spec('high_knees', { nope: 1 })), 'native_param_unknown');
  assert.equal(reason(spec('high_knees', { raiseLift: 9 })), 'native_param_out_of_range');
  assert.equal(reason(spec('high_knees', { raiseLift: '1' })), 'native_param_out_of_range');
  assert.equal(reason(spec('high_knees', [1])), 'native_params_invalid');
  assert.equal(reason(spec('squats', { raiseLift: 0 })), 'native_tuned_activity_invalid');
});

test('params are required by, and only valid for, native_tuned_v1', () => {
  const noParams = spec();
  delete noParams.params;
  assert.equal(reason(noParams), 'native_params_field_mismatch');
  const other = { ...spec(), engineType: 'state_machine_v1' };
  assert.equal(reason(other), 'native_params_field_mismatch');
});

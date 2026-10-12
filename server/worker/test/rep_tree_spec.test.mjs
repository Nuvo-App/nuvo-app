import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';

const { validateMotionVerifierSpec, MotionSpecValidationError, REP_TREE_SIGNALS, REP_TREE_FLAGS } =
  await import('../.tmp-test-dist/domain/motionSpec.js');

const fixture = JSON.parse(readFileSync(new URL('./fixtures/rep_tree_signals.json', import.meta.url)));

const base = () => ({
  specSchemaVersion: 1,
  releaseId: 'squats-tree-test',
  activityId: 'squats',
  engineType: 'rep_tree_v1',
  measurementType: 'repetitions',
  requiredCapabilities: ['pose_landmarks_v1', 'rep_tree_v1'],
  requiredLandmarks: fixture.signals.hipToKneeRatio.landmarks,
  stableFrames: 3,
  repTree: {
    start: { signal: 'hipToKneeRatio', gt: 0.72 },
    active: { signal: 'hipToKneeRatio', lt: 0.5 },
  },
});

const reason = (spec) => {
  try { validateMotionVerifierSpec(spec); return null; }
  catch (e) { assert.ok(e instanceof MotionSpecValidationError); return e.message; }
};

test('signal table matches the shared fixture (Dart asserts the same file)', () => {
  assert.deepEqual(Object.keys(REP_TREE_SIGNALS).sort(), Object.keys(fixture.signals).sort());
  for (const [name, def] of Object.entries(fixture.signals)) {
    assert.deepEqual(REP_TREE_SIGNALS[name], def, name);
  }
  assert.deepEqual(Object.keys(REP_TREE_FLAGS).sort(), Object.keys(fixture.flags).sort());
  for (const [name, landmarks] of Object.entries(fixture.flags)) {
    assert.deepEqual(REP_TREE_FLAGS[name].landmarks, landmarks, name);
  }
});

test('every published motion_specs file passes the server validator', () => {
  const dir = new URL('../motion_specs/', import.meta.url);
  const files = readdirSync(dir).filter((f) => f.endsWith('.json'));
  assert.ok(files.length >= 7);
  for (const file of files) {
    const spec = JSON.parse(readFileSync(new URL(file, dir)));
    assert.doesNotThrow(() => validateMotionVerifierSpec(spec), file);
  }
});

test('rep_tree_v1 fails closed on malformed trees', () => {
  assert.equal(reason(base()), null);
  const bad = (mutate) => { const s = base(); mutate(s); return reason(s); };
  assert.equal(bad((s) => { delete s.repTree; }), 'rep_tree_field_mismatch');
  assert.equal(bad((s) => { s.engineType = 'state_machine_v1'; }) !== null, true);
  assert.equal(bad((s) => { s.repTree.extra = 1; }), 'rep_tree_unknown_key');
  assert.equal(bad((s) => { s.repTree.start = { signal: 'nope', gt: 1 }; }), 'rep_tree_signal_invalid');
  assert.equal(bad((s) => { s.repTree.start = { signal: 'hipToKneeRatio', gt: 9 }; }), 'rep_tree_threshold_out_of_range');
  assert.equal(bad((s) => { s.repTree.start = { flag: 'wristsNearBody' }; }), 'rep_tree_landmarks_missing');
  assert.equal(bad((s) => { s.repTree.start = { signal: 'hipToKneeRatio', gt: 1, lt: 2 }; }), 'rep_tree_condition_invalid');
  assert.equal(bad((s) => { s.repTree.start = { all: [] }; }), 'rep_tree_group_invalid');
  assert.equal(bad((s) => { s.measurementType = 'duration'; }), 'rep_tree_measurement_invalid');
  // Depth limit: five nested groups.
  let deep = { signal: 'hipToKneeRatio', gt: 0.7 };
  for (let i = 0; i < 5; i++) deep = { all: [deep] };
  assert.equal(bad((s) => { s.repTree.start = deep; }), 'rep_tree_condition_invalid');
  // repTree under another engine is rejected.
  const other = base(); other.engineType = 'hold_v1'; other.holdRules = [{ point: 'leftHip', axis: 'y', operator: 'gt', threshold: 0.5 }];
  assert.equal(reason(other), 'rep_tree_field_mismatch');
});

test('sequence_match_v1 accepts midpoints and axis_ratio', () => {
  const spec = {
    specSchemaVersion: 1, releaseId: 'seq-v2', activityId: 'seq', engineType: 'sequence_match_v1',
    measurementType: 'repetitions', requiredCapabilities: ['pose_landmarks_v1', 'sequence_match_v1', 'sequence_features_v2'],
    requiredLandmarks: ['leftShoulder', 'rightShoulder', 'leftHip', 'rightHip', 'leftKnee', 'rightKnee'], stableFrames: 2,
    phases: [
      { id: 'up', next: 'down', predicates: [{ kind: 'axis_ratio', a: 'midKnee', b: 'midHip', axis: 'y', refA: 'midHip', refB: 'midShoulder', refAxis: 'y', operator: 'gt', ratio: 0.72 }] },
      { id: 'down', next: 'complete', predicates: [{ kind: 'axis_ratio', a: 'midKnee', b: 'midHip', axis: 'y', refA: 'midHip', refB: 'midShoulder', operator: 'lt', ratio: 0.5 }] },
    ],
  };
  assert.equal(reason(spec), null);
  spec.phases[0].predicates[0].a = 'midNose';
  assert.match(reason(spec), /landmark_invalid/);
});

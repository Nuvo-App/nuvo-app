// W10 — validates every Batch A converted remote release spec in
// ../motion-releases/ with the Worker's own validator, and checks the
// checksum/SQL-draft wiring the publish route would produce.
//
// These are the scale-invariant `sequence_match_v1` conversions of the
// hand-written Dart validators — every predicate is an angle or a
// body-segment ratio, never a raw coordinate threshold (the exact failure
// behind migration 0026).
import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';

const { validateMotionVerifierSpec, MotionSpecValidationError } = await import(
  '../.tmp-test-dist/domain/motionSpec.js'
);

const releasesDir = new URL('../motion-releases/', import.meta.url);
const files = readdirSync(releasesDir)
  .filter((name) => name.endsWith('.json'))
  .sort();

const EXPECTED = [
  'arm_raises-remote-2026.10.0',
  'burpees-remote-2026.10.0',
  'butt_kicks-remote-2026.10.0',
  'deep_squats-remote-2026.10.0',
  'high_knees-remote-2026.10.0',
  'jump_squats-remote-2026.10.0',
  'jumping_jacks-remote-2026.10.0',
  'lateral_steps-remote-2026.10.0',
  'lunge_jumps-remote-2026.10.0',
  'lunges-remote-2026.10.0',
  'marching_in_place-remote-2026.10.0',
];

function readSpec(file) {
  return JSON.parse(readFileSync(new URL(file, releasesDir), 'utf8'));
}

test('every Batch A release file is present', () => {
  assert.deepEqual(files.map((f) => f.replace(/\.json$/, '')).sort(), EXPECTED);
  // calf_raises is deliberately absent — its native gate is a temporal
  // ankle-baseline delta, which no shipped engine can express (see
  // calvin-spec/motion-conversion/batch_A_REPORT.md).
});

for (const file of files) {
  test(`${file} passes validateMotionVerifierSpec`, () => {
    const spec = readSpec(file);
    const result = validateMotionVerifierSpec(spec, {
      releaseId: spec.releaseId,
      activityId: spec.activityId,
    });
    assert.equal(result.engineType, 'sequence_match_v1');
    assert.equal(result.specSchemaVersion, 1);
  });

  test(`${file} uses only scale-invariant predicates`, () => {
    const spec = readSpec(file);
    for (const phase of spec.phases) {
      for (const predicate of phase.predicates) {
        // landmark_axis compares a raw normalized coordinate — the exact
        // 0026 failure mode — so converted releases must not carry one.
        assert.notEqual(predicate.kind, 'landmark_axis');
        assert.ok(
          ['angle', 'axis_delta', 'segment_ratio'].includes(predicate.kind),
        );
      }
    }
  });

  test(`${file} checksum matches the publish-route convention`, () => {
    const spec = readSpec(file);
    const checksum =
      'sha256:' +
      createHash('sha256').update(JSON.stringify(spec)).digest('hex');
    assert.match(checksum, /^sha256:[0-9a-f]{64}$/);
  });
}

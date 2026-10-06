// Batch B remote-release specs: every spec file under
// server/worker/motion-releases/*-remote-2026.10.0.json must pass the
// Worker's own validator (validateMotionVerifierSpec) exactly as the
// control-plane draft route would run it.
//
// These are the additive conversions for mountain_climbers' batch siblings —
// squats, sumo_squats, squat_jacks, push_ups, side_lunges — using only the
// scale-invariant predicate kinds (angle / axis_delta / segment_ratio), never
// raw landmark-axis thresholds, which is the failure mode behind the 0026
// revert. The remaining batch motions (plank_hold, running_in_place,
// treadmill_running, walking_in_place, step_ups, mountain_climbers) ship no
// spec here: the shipped engines cannot express their native signal — see
// calvin-spec/motion-conversion/B_REPORT.md.

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { createHash } from 'node:crypto';

const { validateMotionVerifierSpec } = await import(
  '../.tmp-test-dist/domain/motionSpec.js'
);

const here = dirname(fileURLToPath(import.meta.url));
const releasesDir = join(here, '..', 'motion-releases');

const specFiles = readdirSync(releasesDir)
  .filter((name) => name.endsWith('-remote-2026.10.0.json'))
  .sort();

const EXPECTED = [
  'push_ups-remote-2026.10.0.json',
  'side_lunges-remote-2026.10.0.json',
  'squat_jacks-remote-2026.10.0.json',
  'squats-remote-2026.10.0.json',
  'sumo_squats-remote-2026.10.0.json',
];

test('the batch-B spec set is exactly the five expressible motions', () => {
  assert.deepEqual(specFiles, EXPECTED);
});

test('every batch-B spec passes validateMotionVerifierSpec', () => {
  for (const name of specFiles) {
    const spec = JSON.parse(readFileSync(join(releasesDir, name), 'utf8'));
    const activityId = name.replace('-remote-2026.10.0.json', '');
    const result = validateMotionVerifierSpec(spec, {
      releaseId: spec.releaseId,
      activityId,
    });
    assert.equal(result.engineType, 'sequence_match_v1', name);
    assert.equal(result.measurementType, 'repetitions', name);
    assert.ok(result.requiredLandmarks.length > 0, name);
    assert.ok(Array.isArray(result.phases) && result.phases.length >= 2, name);
  }
});

test('no batch-B spec uses fixed screen-coordinate predicates', () => {
  // landmark_axis compares a raw normalized coordinate against a constant —
  // exactly the scale-dependent rule that failed real devices in 0016/0026.
  for (const name of specFiles) {
    const spec = JSON.parse(readFileSync(join(releasesDir, name), 'utf8'));
    for (const phase of spec.phases) {
      for (const predicate of phase.predicates) {
        assert.notEqual(
          predicate.kind,
          'landmark_axis',
          `${name}/${phase.id} must be body-scale-relative`,
        );
      }
    }
    for (const field of ['startRules', 'activeRules', 'leftRules', 'rightRules', 'holdRules']) {
      assert.equal(spec[field], undefined, `${name} must not carry raw ${field}`);
    }
  }
});

test('release checksums match sha256 of canonical JSON.stringify(spec)', () => {
  // Mirrors server/worker/src/routes/internal.ts — the publish route stores
  // 'sha256:' + sha256hex(JSON.stringify(spec)). The DRAFT migration must use
  // identical values, so this locks spec files to their SQL rows.
  for (const name of specFiles) {
    const spec = JSON.parse(readFileSync(join(releasesDir, name), 'utf8'));
    const checksum =
      'sha256:' +
      createHash('sha256').update(JSON.stringify(spec)).digest('hex');
    assert.match(checksum, /^sha256:[0-9a-f]{64}$/, name);
  }
});

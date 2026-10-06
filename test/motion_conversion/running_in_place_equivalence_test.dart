// Batch B capability-gap test — running_in_place. (NO conversion)
//
// Native validator: CadenceMotionValidator(runningInPlaceDefinition) —
// AlternatingGaitSignal(liftFraction 0.18): swing = (Δx − centreDx) + Δy of
// the knee pair, normalized by torso height, with a stateful adaptive centre
// seeded from the first frame (alpha 0.04) and a slow vertical-tilt trim
// (alpha 0.01); CadenceDetector(stableFrames 2) counts each confirmed
// left<->right alternation.
//
// Why NO spec exists: alternating_rep_v1 leftRules/rightRules accept only
// raw {point, axis, operator, threshold 0..1} rules — the migration-0016
// fixed-normalized-coordinate format. There is no predicate for
// "knee-pair swing relative to a stateful baseline, normalized by torso
// height". This file quantifies that gap instead of shipping a spec.
//
// Pose source: parametric gaitPose / gaitSequence generators.

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/remote_verifier_spec.dart';

import 'conversion_poses.dart';
import 'conversion_support.dart';

/// The strongest spec the shipped grammar allows: fixed normalized thresholds
/// on knee height — the same rule shape migration 0016 used and 0026 reverted.
final naiveSpec = <String, dynamic>{
  'specSchemaVersion': 1,
  'releaseId': 'running_in_place-naive-gapprobe',
  'activityId': 'running_in_place',
  'engineType': 'alternating_rep_v1',
  'measurementType': 'repetitions',
  'requiredLandmarks': ['leftKnee', 'rightKnee'],
  'stableFrames': 2,
  'leftRules': [
    {'point': 'leftKnee', 'axis': 'y', 'operator': 'lt', 'threshold': 0.56},
  ],
  'rightRules': [
    {'point': 'rightKnee', 'axis': 'y', 'operator': 'lt', 'threshold': 0.56},
  ],
  
};

void main() {
  group('running_in_place: native cadence vs best-effort naive spec (NO)', () {
    test('native counts alternating steps', () {
      final native = runNative(
        AiMotionActivity.runningInPlace,
        gaitSequence(cycles: 6),
      );
      // 6 cycles = 12 side-confirmations; the first seeds the baseline.
      expect(native, greaterThanOrEqualTo(10));
    });

    test('native ignores one-sided and idle motion', () {
      expect(
        runNative(AiMotionActivity.runningInPlace, gaitOneSided()),
        0,
      );
      expect(
        runNative(
          AiMotionActivity.runningInPlace,
          holdPose(gaitNeutral(), 40),
        ),
        0,
      );
    });

    test('naive spec cannot express the gait signal — fixed coords diverge', () {
      // Sanity at nominal scale: the fixed threshold fires on the raised knee.
      final nominalNative = runNative(
        AiMotionActivity.runningInPlace,
        gaitSequence(cycles: 6),
      );
      // Nominal-scale remote count is positive — the naive rule does fire
      // when the runner happens to sit in frame where it assumed.
      expect(
        runRemote(naiveSpec, gaitSequence(cycles: 6)),
        greaterThan(0),
      );
      // Quantified divergence under translation — the exact 0026 failure:
      // shifting the runner 0.08 down in frame moves every knee below the
      // fixed threshold, so the remote engine sees zero reps while the
      // torso-normalized native signal is unaffected.
      final shifted = [
        for (final pose in gaitSequence(cycles: 6)) translatePose(pose, 0, 0.08),
      ];
      final shiftedNative = runNative(AiMotionActivity.runningInPlace, shifted);
      final shiftedRemote = runRemote(naiveSpec, shifted);
      expect(shiftedNative, nominalNative);
      expect(shiftedRemote, 0);
      // And shifting UP makes the resting knee satisfy the rule too — the
      // alternator chatters instead of counting steps.
      final raised = [
        for (final pose in gaitSequence(cycles: 6)) translatePose(pose, 0, -0.08),
      ];
      final raisedRemote = runRemote(naiveSpec, raised);
      expect(raisedRemote, greaterThan(nominalNative));
    });

    test('the missing capability fails closed in the parser', () {
      // A rule carrying a baseline-relative / torso-normalized predicate kind
      // cannot even parse — the rule grammar has no 'kind' field at all.
      final gapSpec = Map<String, dynamic>.from(naiveSpec)
        ..['leftRules'] = [
          {
            'kind': 'axis_delta',
            'a': 'leftKnee',
            'b': 'rightKnee',
            'axis': 'y',
            'operator': 'gt',
            'delta': 0.18, // of torso height — unexpressible
          },
        ];
      expect(
        () => RemoteVerifierSpec.fromJson(gapSpec),
        throwsA(isA<RemoteVerifierSpecException>()),
      );
    });
  });
}

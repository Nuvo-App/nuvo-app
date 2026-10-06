// Batch B capability-gap test — walking_in_place. (NO conversion)
//
// Native validator: CadenceMotionValidator(walkingInPlaceDefinition) —
// AlternatingGaitSignal with liftFraction 0.12 (the shallowest lift in the
// cadence family): combined (Δx−centre)+Δy knee swing vs torso height with a
// stateful adaptive baseline; CadenceDetector(stableFrames 2) counts each
// confirmed alternation.
//
// Why NO spec exists: identical missing capability to running_in_place —
// a stateful, torso-normalized alternating-gait feature. The fixed
// normalized-coordinate rule grammar of alternating_rep_v1 cannot express
// it (migration 0016/0026 failure mode).
//
// Pose source: parametric gaitPose / gaitSequence generators.

import 'package:flutter_test/flutter_test.dart';

import 'conversion_poses.dart';
import 'conversion_support.dart';
import 'running_in_place_equivalence_test.dart' show naiveSpec;

void main() {
  group('walking_in_place: native cadence vs best-effort naive spec (NO)', () {
    test('native counts alternating steps', () {
      final native = runNative(
        AiMotionActivity.walkingInPlace,
        gaitSequence(cycles: 6),
      );
      expect(native, greaterThanOrEqualTo(10));
    });

    test('native ignores idle standing', () {
      expect(
        runNative(AiMotionActivity.walkingInPlace, holdPose(gaitNeutral(), 40)),
        0,
      );
    });

    test('naive spec diverges under translation', () {
      final shifted = [
        for (final pose in gaitSequence(cycles: 6)) translatePose(pose, 0, 0.08),
      ];
      final shiftedNative = runNative(AiMotionActivity.walkingInPlace, shifted);
      final shiftedRemote = runRemote(naiveSpec, shifted);
      expect(shiftedNative, greaterThanOrEqualTo(10));
      expect(shiftedRemote, 0);
    });
  });
}

// Batch B capability-gap test — step_ups. (NO conversion)
//
// Native validator: CadenceMotionValidator(stepUpsDefinition) — the marching
// signal (AlternatingGaitSignal liftFraction 0.30): a deliberate high knee
// lift vs torso height with the same stateful adaptive baseline. Pose alone
// cannot see the physical step — a documented native approximation already.
//
// Why NO spec exists: same missing capability as the whole cadence family —
// no stateful torso-normalized alternating-gait predicate in the shipped
// grammar. A fixed normalized-coordinate rule is the 0026 failure.
//
// Pose source: parametric gaitPose / gaitSequence generators (lift=1.0 gives
// swing ~0.27 torso — above the 0.30*fraction? measured empirically below).

import 'package:flutter_test/flutter_test.dart';

import 'conversion_poses.dart';
import 'conversion_support.dart';
import 'running_in_place_equivalence_test.dart' show naiveSpec;

void main() {
  group('step_ups: native cadence vs best-effort naive spec (NO)', () {
    test('native counts alternating high steps', () {
      // Step-ups needs the deliberate march lift (0.30 torso fraction) — the
      // generator's swing of ~0.11 normalized vs ~0.22 torso ≈ 0.50 torso, so
      // it clears the higher bar.
      final native = runNative(
        AiMotionActivity.stepUps,
        gaitSequence(cycles: 6),
      );
      expect(native, greaterThanOrEqualTo(10));
    });

    test('native ignores idle standing', () {
      expect(
        runNative(AiMotionActivity.stepUps, holdPose(gaitNeutral(), 40)),
        0,
      );
    });

    test('naive spec diverges under translation', () {
      final shifted = [
        for (final pose in gaitSequence(cycles: 6)) translatePose(pose, 0, 0.08),
      ];
      final shiftedNative = runNative(AiMotionActivity.stepUps, shifted);
      final shiftedRemote = runRemote(naiveSpec, shifted);
      expect(shiftedNative, greaterThanOrEqualTo(10));
      expect(shiftedRemote, 0);
    });
  });
}

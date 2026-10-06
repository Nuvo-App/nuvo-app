// Batch B capability-gap test — treadmill_running. (NO conversion)
//
// Native validator: CadenceMotionValidator(treadmillRunningDefinition) —
// the same AlternatingGaitSignal(liftFraction 0.18) + CadenceDetector as
// running_in_place, PLUS VirtualDistanceEstimator: currentValue is metres
// run, not a rep count.
//
// Why NO spec exists: two missing capabilities —
//   1. the stateful torso-normalized gait swing (same gap as running),
//   2. a `measurementType`/runtime that integrates cadence into estimated
//      distance — the remote grammar can only count repetitions.
//
// Pose source: parametric gaitPose / gaitSequence generators.

import 'package:flutter_test/flutter_test.dart';

import 'conversion_poses.dart';
import 'conversion_support.dart';
import 'running_in_place_equivalence_test.dart' show naiveSpec;

void main() {
  group('treadmill_running: native distance vs best-effort naive spec (NO)', () {
    test('native measures virtual distance in metres', () {
      final metres = runNative(
        AiMotionActivity.treadmillRunning,
        gaitSequence(cycles: 8),
      );
      // VirtualDistanceEstimator integrates each confirmed step — the value
      // is metres, not alternation count, and grows with the run.
      expect(metres, greaterThanOrEqualTo(3));
    });

    test('same fixed-coordinate divergence as running_in_place', () {
      final shifted = [
        for (final pose in gaitSequence(cycles: 6)) translatePose(pose, 0, 0.08),
      ];
      final shiftedNative = runNative(AiMotionActivity.treadmillRunning, shifted);
      final shiftedRemote = runRemote(naiveSpec, shifted);
      expect(shiftedNative, greaterThanOrEqualTo(2));
      expect(shiftedRemote, 0);
    });
  });
}

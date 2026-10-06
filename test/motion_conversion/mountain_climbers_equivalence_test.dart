// Batch B capability-gap test — mountain_climbers. (NO conversion)
//
// Native validator: MountainClimbersValidator — plank context from torso
// orientation (|shoulder->hip| off-vertical), hands-near-shoulders gate,
// then alternating knee DRIVE projected onto the torso axis (normalized by
// torso length, drive gap >= 0.26 between the two knees), counted by
// CadenceDetector(stableFrames 2).
//
// Why NO spec exists: the drive signal is a projection onto a derived body
// axis with a stateful left-vs-right comparison — the grammar has neither a
// projection feature nor an inter-landmark differential predicate of that
// kind. alternating_rep_v1 rules are fixed normalized coordinates only.
//
// Pose source: parametric mountainClimberPose generator (diagonal plank
// geometry modelled on the repo's own replay fixtures).

import 'package:flutter_test/flutter_test.dart';

import 'conversion_poses.dart';
import 'conversion_support.dart';

/// Best-effort spec: fixed y-threshold on each knee — a driven knee reads
/// higher in frame (smaller y) than the extended one at this fixture's
/// geometry.
final naiveClimberSpec = <String, dynamic>{
  'specSchemaVersion': 1,
  'releaseId': 'mountain_climbers-naive-gapprobe',
  'activityId': 'mountain_climbers',
  'engineType': 'alternating_rep_v1',
  'measurementType': 'repetitions',
  'requiredLandmarks': ['leftKnee', 'rightKnee'],
  'stableFrames': 2,
  'leftRules': [
    {'point': 'leftKnee', 'axis': 'y', 'operator': 'lt', 'threshold': 0.55},
  ],
  'rightRules': [
    {'point': 'rightKnee', 'axis': 'y', 'operator': 'lt', 'threshold': 0.55},
  ],
  
};

List<CleanPose> climberReps({int reps = 6, int framesPerSide = 4}) {
  final out = <CleanPose>[
    for (var i = 0; i < 6; i++) mountainClimberPose('left', drive: 0.0),
  ];
  var side = 'left';
  for (var r = 0; r < reps * 2; r++) {
    for (var i = 0; i < framesPerSide; i++) {
      out.add(mountainClimberPose(side));
    }
    for (var i = 0; i < 2; i++) {
      out.add(mountainClimberPose(side, drive: 0.0));
    }
    side = side == 'left' ? 'right' : 'left';
  }
  return out;
}

void main() {
  group('mountain_climbers: native vs best-effort naive spec (NO)', () {
    test('native counts alternating knee drives', () {
      final native = runNative(
        AiMotionActivity.mountainClimbers,
        climberReps(),
      );
      expect(native, greaterThanOrEqualTo(10));
    });

    test('native ignores idle plank', () {
      expect(
        runNative(
          AiMotionActivity.mountainClimbers,
          holdPose(mountainClimberPose('left', drive: 0.0), 40),
        ),
        0,
      );
    });

    test('naive fixed-coordinate spec diverges under translation', () {
      final shifted = [
        for (final pose in climberReps()) translatePose(pose, 0, 0.08),
      ];
      final shiftedNative = runNative(
        AiMotionActivity.mountainClimbers,
        shifted,
      );
      final shiftedRemote = runRemote(naiveClimberSpec, shifted);
      expect(shiftedNative, greaterThanOrEqualTo(10));
      expect(shiftedRemote, 0);
    });
  });
}

import '../motion_validators.dart';
import '../multi_phase_sequence_tracker.dart';

const _burpeeLandmarks = [
  'leftShoulder',
  'rightShoulder',
  'leftHip',
  'rightHip',
  'leftKnee',
  'rightKnee',
  'leftAnkle',
  'rightAnkle',
  'leftWrist',
  'rightWrist',
];

/// True when both wrists are clearly above hip height — arms are not
/// reaching toward the floor. Computed directly from the frame (not via a
/// shared [PoseSignal]) so this file adds zero surface area to the signal
/// enum every other preset — including the locked three — evaluates against.
class _HandsUpCondition extends PoseCondition {
  const _HandsUpCondition(this.marginTorso);

  final double marginTorso;

  @override
  bool evaluate(PoseFeatureExtractor f) {
    final leftWrist = f.frame.point('leftWrist')!;
    final rightWrist = f.frame.point('rightWrist')!;
    final hipY = f.hipY;
    final margin = f.torsoHeight * marginTorso;
    return leftWrist.y < hipY - margin && rightWrist.y < hipY - margin;
  }
}

/// True when both wrists are at or below hip height — hands reaching toward
/// the floor, the burpee's crouch-and-plant moment.
class _HandsDownCondition extends PoseCondition {
  const _HandsDownCondition(this.marginTorso);

  final double marginTorso;

  @override
  bool evaluate(PoseFeatureExtractor f) {
    final leftWrist = f.frame.point('leftWrist')!;
    final rightWrist = f.frame.point('rightWrist')!;
    final hipY = f.hipY;
    final margin = f.torsoHeight * marginTorso;
    return leftWrist.y > hipY - margin && rightWrist.y > hipY - margin;
  }
}

/// Builds the production Burpee sequence definition.
///
/// Phases: STANDING -> DOWN -> STANDING (+1)
///
/// This is a deliberately common-form definition, not a strict athletic
/// standard: DOWN requires squat-depth hips AND hands reaching toward the
/// floor (the crouch-and-plant moment), rather than a distinct plank/pushup
/// extension — a front-facing camera cannot reliably see a full horizontal
/// plank the way a side view could, and requiring one would reject a large
/// share of real, valid burpees. No airborne jump is required to complete a
/// rep, matching the product decision to not mandate athletic form. This is
/// a documented simplification, not a claim of stricter-form detection.
///
/// - STANDING: hipToKneeRatio > 0.72 (reuses the squat family's calibrated
///   standing gate — see squatRepDefinition) AND hands up.
/// - DOWN: hipToKneeRatio < 0.50 (squat-depth) AND hands down/reaching.
/// - STANDING again: same condition as phase 0 -> completes the rep.
MultiPhaseSequenceDefinition buildBurpeeDefinition({
  MotionTuning tuning = MotionTuning.empty,
}) {
  final standing = AndCondition([
    ComparisonCondition(
      PoseSignal.hipToKneeRatio,
      tuning.value('standingRatio', 0.72),
      greaterThan: true,
    ),
    _HandsUpCondition(tuning.value('handsUpMargin', 0.15)),
  ]);
  final down = AndCondition([
    ComparisonCondition(
      PoseSignal.hipToKneeRatio,
      tuning.value('downRatio', 0.50),
      greaterThan: false,
    ),
    _HandsDownCondition(tuning.value('handsDownMargin', 0.05)),
  ]);

  return MultiPhaseSequenceDefinition(
    phases: [
      SequencePhaseDefinition(
        id: 'STANDING',
        condition: standing,
        stableFrames: 2,
      ),
      SequencePhaseDefinition(id: 'DOWN', condition: down, stableFrames: 2),
      SequencePhaseDefinition(
        id: 'STANDING_FINISH',
        condition: standing,
        stableFrames: 2,
      ),
    ],
    resetCondition: standing,
    requiredLandmarks: _burpeeLandmarks,
    cooldownFrames: 2,
  );
}

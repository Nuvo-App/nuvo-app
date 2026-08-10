import '../airborne_state_tracker.dart';
import '../motion_validators.dart';
import '../multi_phase_sequence_tracker.dart';

/// Core landmarks required for jump squat and lunge jump phase evaluation.
/// Ankles are NOT required here — they are frequently lost during airborne
/// phases. The [AirborneStateTracker] has its own internal ankle landmark
/// checks and handles missing ankles gracefully. Phase conditions
/// (hipToKneeRatio, kneeAngle) only need shoulders, hips, and knees.
const _coreLandmarks = [
  'leftShoulder',
  'rightShoulder',
  'leftHip',
  'rightHip',
  'leftKnee',
  'rightKnee',
];

/// Builds the Jump Squat production sequence definition.
///
/// Phases: STANDING → SQUAT → AIRBORNE → LANDING
/// Reset: standing + grounded (not airborne)
///
/// Derived directly from the passing test-only proof fixture in
/// `test/jump_squat_lunge_jump_proof_test.dart`. The thresholds and
/// stable-frame counts are identical — this is the production promotion
/// of that proof.
///
/// - STANDING: hipToKneeRatio > 0.86 (standing tall), 3 stable frames
/// - SQUAT: hipToKneeRatio < 0.58 (squat depth), 3 stable frames
/// - AIRBORNE: AirborneStateTracker.isAirborne, 2 stable frames (flight is brief)
/// - LANDING: standing AND grounded (distinguishes landing from standing
///   while airborne), 3 stable frames
///
/// The LANDING condition uses GroundedCondition to prevent the airborne
/// body (which has standing-like hipToKneeRatio) from matching LANDING
/// during the AIRBORNE phase.
MultiPhaseSequenceDefinition buildJumpSquatDefinition(
  AirborneStateTracker airborne,
) {
  // Lowered from 0.86 to 0.70 — real-world jump squatters stay in an
  // athletic stance between reps (hipToKneeRatio ~0.70-0.85), rarely
  // reaching fully standing (0.86+). Evidence: real video QA shows 0/3
  // clips detected because STANDING phase never matches.
  final standingCondition = const ComparisonCondition(
    PoseSignal.hipToKneeRatio,
    0.70,
    greaterThan: true,
  );

  // STANDING only counts when grounded — prevents matching during
  // airborne when legs are straight (high ratio) but person is in flight.
  final groundedStandingCondition = AndCondition([
    standingCondition,
    GroundedCondition(airborne),
  ]);

  final squatCondition = const ComparisonCondition(
    PoseSignal.hipToKneeRatio,
    0.58,
    greaterThan: false,
  );

  final airborneCondition = AirborneCondition(airborne);

  final landingCondition = AndCondition([
    standingCondition,
    GroundedCondition(airborne),
  ]);

  return MultiPhaseSequenceDefinition(
    phases: [
      SequencePhaseDefinition(
        id: 'STANDING',
        condition: groundedStandingCondition,
        stableFrames: 2,
      ),
      SequencePhaseDefinition(
        id: 'SQUAT',
        condition: squatCondition,
        stableFrames: 1,
      ),
      SequencePhaseDefinition(
        id: 'AIRBORNE',
        condition: airborneCondition,
        stableFrames: 1,
      ),
      SequencePhaseDefinition(
        id: 'LANDING',
        condition: landingCondition,
        stableFrames: 2,
      ),
    ],
    resetCondition: AndCondition([
      standingCondition,
      GroundedCondition(airborne),
    ]),
    requiredLandmarks: _coreLandmarks,
    cooldownFrames: 3,
    noiseGraceFrames: 1,
  );
}

/// Builds both Lunge Jump production sequence definitions (right-start
/// and left-start), enabling the movement to be counted regardless of
/// which leg leads.
///
/// Right-start: RIGHT_LUNGE → AIRBORNE → LEFT_LUNGE
/// Left-start:  LEFT_LUNGE  → AIRBORNE → RIGHT_LUNGE
/// Reset: standing (hipToKneeRatio > 0.86)
///
/// Derived directly from the passing test-only proof fixtures in
/// `test/jump_squat_lunge_jump_proof_test.dart`. The thresholds and
/// stable-frame counts are identical.
///
/// Side identity:
/// - Right lunge: rightKneeAngle < 120° (front bent),
///   leftKneeAngle > 160° (back straight)
/// - Left lunge: leftKneeAngle < 120° (front bent),
///   rightKneeAngle > 160° (back straight)
///
/// Both trackers run in parallel on the same frame stream. Only one
/// can progress at a time — when the user is in a right lunge, the
/// right-start tracker advances while the left-start tracker sees
/// a wrong-phase and resets to idle. This ensures:
/// - valid side switch (right→air→left) = 1 completion (from right-start)
/// - same-side return (right→air→right) = 0 (wrong-phase reset)
/// - alternating reps (right→air→left→air→right) = 2 (one from each)
List<MultiPhaseSequenceDefinition> buildLungeJumpDefinitions(
  AirborneStateTracker airborne,
) {
  final rightLungeCondition = const AndCondition([
    ComparisonCondition(PoseSignal.rightKneeAngle, 120, greaterThan: false),
    ComparisonCondition(PoseSignal.leftKneeAngle, 160, greaterThan: true),
  ]);

  final leftLungeCondition = const AndCondition([
    ComparisonCondition(PoseSignal.leftKneeAngle, 120, greaterThan: false),
    ComparisonCondition(PoseSignal.rightKneeAngle, 160, greaterThan: true),
  ]);

  final airborneCondition = AirborneCondition(airborne);

  final standingCondition = const ComparisonCondition(
    PoseSignal.hipToKneeRatio,
    0.86,
    greaterThan: true,
  );

  return [
    // Right-start: RIGHT_LUNGE → AIRBORNE → LEFT_LUNGE
    MultiPhaseSequenceDefinition(
      phases: [
        SequencePhaseDefinition(
          id: 'RIGHT_LUNGE',
          condition: rightLungeCondition,
          stableFrames: 3,
        ),
        SequencePhaseDefinition(
          id: 'AIRBORNE',
          condition: airborneCondition,
          stableFrames: 1,
        ),
        SequencePhaseDefinition(
          id: 'LEFT_LUNGE',
          condition: leftLungeCondition,
          stableFrames: 3,
        ),
      ],
      resetCondition: standingCondition,
      requiredLandmarks: _coreLandmarks,
      cooldownFrames: 3,
      noiseGraceFrames: 1,
    ),
    // Left-start: LEFT_LUNGE → AIRBORNE → RIGHT_LUNGE
    MultiPhaseSequenceDefinition(
      phases: [
        SequencePhaseDefinition(
          id: 'LEFT_LUNGE',
          condition: leftLungeCondition,
          stableFrames: 3,
        ),
        SequencePhaseDefinition(
          id: 'AIRBORNE',
          condition: airborneCondition,
          stableFrames: 1,
        ),
        SequencePhaseDefinition(
          id: 'RIGHT_LUNGE',
          condition: rightLungeCondition,
          stableFrames: 3,
        ),
      ],
      resetCondition: standingCondition,
      requiredLandmarks: _coreLandmarks,
      cooldownFrames: 3,
      noiseGraceFrames: 1,
    ),
  ];
}

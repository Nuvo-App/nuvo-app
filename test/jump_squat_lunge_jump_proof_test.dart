import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/airborne_state_tracker.dart';
import 'package:nuvo/features/races/ai/motion_validators.dart';
import 'package:nuvo/features/races/ai/multi_phase_sequence_tracker.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

// ── Pose fixtures ───────────────────────────────────────────────────────────
//
// All fixtures use the same body scale:
//   shoulderY = 0.30, hipY = 0.50 (standing) → torsoHeight = 0.20
//   flightThreshold = max(0.025, 0.20 * 0.18) = 0.036
//   groundedTolerance = max(0.015, 0.20 * 0.10) = 0.020
//
// hipToKneeRatio = (kneeY - hipY) / torsoHeight
//   STANDING: kneeY=0.72, hipY=0.50 → (0.72-0.50)/0.20 = 1.10 > 0.86 ✅
//   SQUAT:    kneeY=0.60, hipY=0.60 → (0.60-0.60)/0.30 = 0.00 < 0.58 ✅
//     (squat drops hipY to 0.60, kneeY stays at 0.60 → torsoHeight=0.30)

NuvoPosePoint _p(double x, double y, {double likelihood = 0.95}) =>
    NuvoPosePoint(x: x, y: y, z: 0, likelihood: likelihood);

NuvoPoseFrame _frame(Map<String, NuvoPosePoint> points) => NuvoPoseFrame(
  points: points,
  imageWidth: 1080,
  imageHeight: 1920,
  createdAt: DateTime.now(),
);

const _landmarks = [
  'leftShoulder',
  'rightShoulder',
  'leftHip',
  'rightHip',
  'leftKnee',
  'rightKnee',
  'leftAnkle',
  'rightAnkle',
];

/// Standing pose — hipToKneeRatio = 1.10 > 0.86, ankles at 0.90.
NuvoPoseFrame _standing({double ankleY = 0.90}) => _frame({
  'leftShoulder': _p(0.40, 0.30),
  'rightShoulder': _p(0.60, 0.30),
  'leftHip': _p(0.42, 0.50),
  'rightHip': _p(0.58, 0.50),
  'leftKnee': _p(0.43, 0.72),
  'rightKnee': _p(0.57, 0.72),
  'leftAnkle': _p(0.47, ankleY),
  'rightAnkle': _p(0.53, ankleY),
});

/// Squat pose — hipToKneeRatio = 0.00 < 0.58, ankles stay at 0.90.
/// Hip drops to 0.60, knee at 0.60 → torsoHeight = 0.30, ratio = 0.00.
NuvoPoseFrame _squat({double ankleY = 0.90}) => _frame({
  'leftShoulder': _p(0.40, 0.30),
  'rightShoulder': _p(0.60, 0.30),
  'leftHip': _p(0.42, 0.60),
  'rightHip': _p(0.58, 0.60),
  'leftKnee': _p(0.43, 0.60),
  'rightKnee': _p(0.57, 0.60),
  'leftAnkle': _p(0.47, ankleY),
  'rightAnkle': _p(0.53, ankleY),
});

/// Jump (airborne) — both ankles rise 0.06 from baseline 0.90 → 0.84.
/// 0.06 > 0.036 → AIRBORNE. Body stays in standing posture (not squat).
NuvoPoseFrame _jump() => _frame({
  'leftShoulder': _p(0.40, 0.30),
  'rightShoulder': _p(0.60, 0.30),
  'leftHip': _p(0.42, 0.50),
  'rightHip': _p(0.58, 0.50),
  'leftKnee': _p(0.43, 0.72),
  'rightKnee': _p(0.57, 0.72),
  'leftAnkle': _p(0.47, 0.84),
  'rightAnkle': _p(0.53, 0.84),
});

/// Jumping jack open — feet wide, arms up, but ankles stay on ground.
/// hipToKneeRatio = 1.10 (standing), ankles at 0.90 (no flight).
NuvoPoseFrame _jumpingJackOpen() => _frame({
  'leftShoulder': _p(0.40, 0.30),
  'rightShoulder': _p(0.60, 0.30),
  'leftHip': _p(0.42, 0.50),
  'rightHip': _p(0.58, 0.50),
  'leftKnee': _p(0.43, 0.72),
  'rightKnee': _p(0.57, 0.72),
  'leftAnkle': _p(0.25, 0.90),
  'rightAnkle': _p(0.75, 0.90),
  'leftWrist': _p(0.30, 0.20),
  'rightWrist': _p(0.70, 0.20),
});

/// Lunge — right leg forward, left leg back.
/// Right knee angle = 113° < 120° (bent), left knee angle = 170° > 160° (straight).
/// hipToKneeRatio = 0.80 (not standing).
/// Right lunge: rightKnee bent, leftKnee straight.
NuvoPoseFrame _rightLunge() => _frame({
  'leftShoulder': _p(0.40, 0.30),
  'rightShoulder': _p(0.60, 0.30),
  'leftHip': _p(0.48, 0.50),
  'rightHip': _p(0.52, 0.50),
  'leftKnee': _p(0.35, 0.70), // back leg, straight
  'rightKnee': _p(0.78, 0.62), // front leg, bent (113°)
  'leftAnkle': _p(0.25, 0.90),
  'rightAnkle': _p(0.78, 0.90),
});

/// Left lunge — left leg forward, right leg back.
/// Left knee angle = 113° < 120° (bent), right knee angle = 170° > 160° (straight).
NuvoPoseFrame _leftLunge() => _frame({
  'leftShoulder': _p(0.40, 0.30),
  'rightShoulder': _p(0.60, 0.30),
  'leftHip': _p(0.48, 0.50),
  'rightHip': _p(0.52, 0.50),
  'leftKnee': _p(0.22, 0.62), // front leg, bent (113°)
  'rightKnee': _p(0.65, 0.70), // back leg, straight
  'leftAnkle': _p(0.22, 0.90),
  'rightAnkle': _p(0.75, 0.90),
});

// ── Test-only sequence definitions ──────────────────────────────────────────

/// Jump Squat sequence: STANDING → SQUAT → AIRBORNE → LANDING.
/// Reset condition: standing (hipToKneeRatio > 0.86).
///
/// The AIRBORNE phase uses AirborneCondition which reads from a shared
/// AirborneStateTracker. The tracker is updated once per frame via the
/// temporalUpdaters parameter.
({
  MultiPhaseSequenceTracker tracker,
  AirborneStateTracker airborne,
  MultiPhaseSequenceDefinition definition,
})
_buildJumpSquatSequence() {
  final airborne = AirborneStateTracker();

  // Standing condition: hipToKneeRatio > 0.86 (standing tall).
  final standingCondition = const ComparisonCondition(
    PoseSignal.hipToKneeRatio,
    0.86,
    greaterThan: true,
  );

  // Squat condition: hipToKneeRatio < 0.58 (squat depth).
  final squatCondition = const ComparisonCondition(
    PoseSignal.hipToKneeRatio,
    0.58,
    greaterThan: false,
  );

  // Airborne condition: AirborneStateTracker.isAirborne.
  final airborneCondition = AirborneCondition(airborne);

  // Landing condition: standing AND grounded (not airborne).
  // This distinguishes "landing after jump" from "standing while airborne".
  final landingCondition = AndCondition([
    standingCondition,
    GroundedCondition(airborne),
  ]);

  final definition = MultiPhaseSequenceDefinition(
    phases: [
      SequencePhaseDefinition(
        id: 'STANDING',
        condition: standingCondition,
        stableFrames: 3,
      ),
      SequencePhaseDefinition(
        id: 'SQUAT',
        condition: squatCondition,
        stableFrames: 3,
      ),
      SequencePhaseDefinition(
        id: 'AIRBORNE',
        condition: airborneCondition,
        stableFrames: 2, // Flight is brief — fewer frames needed.
      ),
      SequencePhaseDefinition(
        id: 'LANDING',
        condition: landingCondition,
        stableFrames: 3,
      ),
    ],
    resetCondition: AndCondition([
      standingCondition,
      GroundedCondition(airborne),
    ]),
    requiredLandmarks: _landmarks,
    cooldownFrames: 3,
  );

  return (
    tracker: MultiPhaseSequenceTracker(definition: definition),
    airborne: airborne,
    definition: definition,
  );
}

/// Lunge Jump sequence: RIGHT_LUNGE → AIRBORNE → LEFT_LUNGE.
/// Reset condition: standing feet together (hipToKneeRatio > 0.86).
///
/// Right lunge: rightKneeAngle < 120° (front bent), leftKneeAngle > 160° (back straight).
/// Left lunge: leftKneeAngle < 120° (front bent), rightKneeAngle > 160° (back straight).
({
  MultiPhaseSequenceTracker tracker,
  AirborneStateTracker airborne,
  MultiPhaseSequenceDefinition definition,
})
_buildLungeJumpSequence() {
  final airborne = AirborneStateTracker();

  // Right lunge: right knee bent (< 120°), left knee straight (> 160°).
  final rightLungeCondition = const AndCondition([
    ComparisonCondition(PoseSignal.rightKneeAngle, 120, greaterThan: false),
    ComparisonCondition(PoseSignal.leftKneeAngle, 160, greaterThan: true),
  ]);

  // Left lunge: left knee bent (< 120°), right knee straight (> 160°).
  final leftLungeCondition = const AndCondition([
    ComparisonCondition(PoseSignal.leftKneeAngle, 120, greaterThan: false),
    ComparisonCondition(PoseSignal.rightKneeAngle, 160, greaterThan: true),
  ]);

  // Airborne condition.
  final airborneCondition = AirborneCondition(airborne);

  // Standing/neutral condition: hipToKneeRatio > 0.86.
  final standingCondition = const ComparisonCondition(
    PoseSignal.hipToKneeRatio,
    0.86,
    greaterThan: true,
  );

  final definition = MultiPhaseSequenceDefinition(
    phases: [
      SequencePhaseDefinition(
        id: 'RIGHT_LUNGE',
        condition: rightLungeCondition,
        stableFrames: 3,
      ),
      SequencePhaseDefinition(
        id: 'AIRBORNE',
        condition: airborneCondition,
        stableFrames: 2,
      ),
      SequencePhaseDefinition(
        id: 'LEFT_LUNGE',
        condition: leftLungeCondition,
        stableFrames: 3,
      ),
    ],
    resetCondition: standingCondition,
    requiredLandmarks: _landmarks,
    cooldownFrames: 3,
  );

  return (
    tracker: MultiPhaseSequenceTracker(definition: definition),
    airborne: airborne,
    definition: definition,
  );
}

/// Helper: feed N frames of the same pose, updating airborne tracker too.
void _feed(
  MultiPhaseSequenceTracker tracker,
  AirborneStateTracker airborne,
  NuvoPoseFrame frame,
  int count,
) {
  for (var i = 0; i < count; i++) {
    tracker.update(frame, temporalUpdaters: [airborne.update]);
  }
}

void main() {
  group('Jump Squat proof (test-only)', () {
    test('VALID: standing → squat → jump → land → stand = 1 completion', () {
      final ctx = _buildJumpSquatSequence();
      final tracker = ctx.tracker;
      final airborne = ctx.airborne;

      // STANDING: 8 frames (5 for airborne baseline + 3 for phase stability)
      _feed(tracker, airborne, _standing(), 8);
      expect(tracker.currentPhaseId, 'STANDING');
      expect(
        airborne.baselineEstablished,
        isTrue,
        reason: 'Airborne baseline should be established',
      );

      // SQUAT: 3 frames
      _feed(tracker, airborne, _squat(), 3);
      expect(tracker.currentPhaseId, 'SQUAT');

      // AIRBORNE (jump): 2 frames
      _feed(tracker, airborne, _jump(), 2);
      expect(tracker.currentPhaseId, 'AIRBORNE');

      // LANDING (standing again): 3 frames → completion
      _feed(tracker, airborne, _standing(), 3);
      expect(
        tracker.completionCount,
        1,
        reason: 'Full jump squat cycle should complete',
      );
    });

    test('INVALID: ordinary squat (no jump) = 0 completions', () {
      final ctx = _buildJumpSquatSequence();
      final tracker = ctx.tracker;
      final airborne = ctx.airborne;

      // Standing → Squat → Standing (no airborne phase)
      _feed(tracker, airborne, _standing(), 8);
      _feed(tracker, airborne, _squat(), 3);
      // Return to standing — this is wrong-phase (expected AIRBORNE, got STANDING)
      _feed(tracker, airborne, _standing(), 3);

      expect(
        tracker.completionCount,
        0,
        reason: 'Squat without jump should not complete',
      );
    });

    test('INVALID: ordinary two-foot jump without squat = 0 completions', () {
      final ctx = _buildJumpSquatSequence();
      final tracker = ctx.tracker;
      final airborne = ctx.airborne;

      // Standing (establishes baseline)
      _feed(tracker, airborne, _standing(), 8);
      expect(tracker.currentPhaseId, 'STANDING');

      // Jump directly (skip squat) → wrong-phase reset
      _feed(tracker, airborne, _jump(), 3);

      expect(
        tracker.completionCount,
        0,
        reason: 'Jump without squat should not complete',
      );
    });

    test('INVALID: jumping jack = 0 completions', () {
      final ctx = _buildJumpSquatSequence();
      final tracker = ctx.tracker;
      final airborne = ctx.airborne;

      // Standing (establishes baseline)
      _feed(tracker, airborne, _standing(), 8);

      // Jumping jack open — standing posture, feet wide, no flight
      _feed(tracker, airborne, _jumpingJackOpen(), 5);

      expect(
        tracker.completionCount,
        0,
        reason: 'Jumping jacks should not count as jump squats',
      );
    });

    test('INVALID: standing → squat → stand (incomplete) = 0', () {
      final ctx = _buildJumpSquatSequence();
      final tracker = ctx.tracker;
      final airborne = ctx.airborne;

      _feed(tracker, airborne, _standing(), 8);
      _feed(tracker, airborne, _squat(), 3);
      // Only 2 standing frames (not enough for landing stability)
      _feed(tracker, airborne, _standing(), 2);

      expect(
        tracker.completionCount,
        0,
        reason: 'Incomplete sequence should not complete',
      );
    });

    test('INVALID: standing → airborne without squat = 0', () {
      final ctx = _buildJumpSquatSequence();
      final tracker = ctx.tracker;
      final airborne = ctx.airborne;

      // Standing (establishes baseline)
      _feed(tracker, airborne, _standing(), 8);
      expect(tracker.currentPhaseId, 'STANDING');

      // Jump (airborne) without squat first → wrong-phase reset
      _feed(tracker, airborne, _jump(), 3);

      expect(
        tracker.completionCount,
        0,
        reason: 'Jump without prior squat should not complete',
      );
    });

    test(
      'INVALID: squat → airborne but never lands/resets = 0 completed cycle',
      () {
        final ctx = _buildJumpSquatSequence();
        final tracker = ctx.tracker;
        final airborne = ctx.airborne;

        // Standing → Squat → Airborne, then stay airborne
        _feed(tracker, airborne, _standing(), 8);
        _feed(tracker, airborne, _squat(), 3);
        _feed(tracker, airborne, _jump(), 10);

        expect(
          tracker.completionCount,
          0,
          reason: 'Airborne without landing should not complete',
        );
      },
    );

    test('repeated jump squats = 2 completions', () {
      final ctx = _buildJumpSquatSequence();
      final tracker = ctx.tracker;
      final airborne = ctx.airborne;

      // First cycle
      _feed(tracker, airborne, _standing(), 8);
      _feed(tracker, airborne, _squat(), 3);
      _feed(tracker, airborne, _jump(), 2);
      _feed(tracker, airborne, _standing(), 3);
      expect(tracker.completionCount, 1);

      // Cooldown (3 frames) + reset (1 frame) + STANDING re-establishment.
      // After 8 standing frames: 3 cooldown, 1 reset→idle, 4 start new
      // STANDING phase (tracking). The second cycle continues from there.
      _feed(tracker, airborne, _standing(), 8);
      expect(
        tracker.currentPhaseId,
        'STANDING',
        reason: 'Should be tracking STANDING for second cycle',
      );

      // Second cycle: squat → jump → land
      _feed(tracker, airborne, _squat(), 3);
      _feed(tracker, airborne, _jump(), 2);
      _feed(tracker, airborne, _standing(), 3);
      expect(tracker.completionCount, 2);
    });
  });

  group('Lunge Jump proof (test-only)', () {
    test('VALID: right lunge → air → left lunge = 1 completion', () {
      final ctx = _buildLungeJumpSequence();
      final tracker = ctx.tracker;
      final airborne = ctx.airborne;

      // RIGHT_LUNGE: 5 frames (also establishes airborne baseline)
      _feed(tracker, airborne, _rightLunge(), 8);
      expect(tracker.currentPhaseId, 'RIGHT_LUNGE');

      // AIRBORNE: 2 frames (jump with both ankles rising)
      // Need to jump from lunge position — ankles rise from 0.90
      _feed(tracker, airborne, _jump(), 2);
      expect(tracker.currentPhaseId, 'AIRBORNE');

      // LEFT_LUNGE: 3 frames → completion
      _feed(tracker, airborne, _leftLunge(), 3);
      expect(
        tracker.completionCount,
        1,
        reason: 'Right→air→left lunge jump should complete',
      );
    });

    test('VALID: left lunge → air → right lunge = 1 completion', () {
      // Build a left-start lunge jump sequence (mirror of the right-start).
      final airborne = AirborneStateTracker();

      final leftLungeCondition = const AndCondition([
        ComparisonCondition(PoseSignal.leftKneeAngle, 120, greaterThan: false),
        ComparisonCondition(PoseSignal.rightKneeAngle, 160, greaterThan: true),
      ]);
      final rightLungeCondition = const AndCondition([
        ComparisonCondition(PoseSignal.rightKneeAngle, 120, greaterThan: false),
        ComparisonCondition(PoseSignal.leftKneeAngle, 160, greaterThan: true),
      ]);
      final airborneCondition = AirborneCondition(airborne);
      final standingCondition = const ComparisonCondition(
        PoseSignal.hipToKneeRatio,
        0.86,
        greaterThan: true,
      );

      final definition = MultiPhaseSequenceDefinition(
        phases: [
          SequencePhaseDefinition(
            id: 'LEFT_LUNGE',
            condition: leftLungeCondition,
            stableFrames: 3,
          ),
          SequencePhaseDefinition(
            id: 'AIRBORNE',
            condition: airborneCondition,
            stableFrames: 2,
          ),
          SequencePhaseDefinition(
            id: 'RIGHT_LUNGE',
            condition: rightLungeCondition,
            stableFrames: 3,
          ),
        ],
        resetCondition: standingCondition,
        requiredLandmarks: _landmarks,
        cooldownFrames: 3,
      );

      final tracker = MultiPhaseSequenceTracker(definition: definition);

      // LEFT_LUNGE: 8 frames (baseline + stability)
      _feed(tracker, airborne, _leftLunge(), 8);
      expect(tracker.currentPhaseId, 'LEFT_LUNGE');

      // AIRBORNE: 2 frames
      _feed(tracker, airborne, _jump(), 2);
      expect(tracker.currentPhaseId, 'AIRBORNE');

      // RIGHT_LUNGE: 3 frames → completion
      _feed(tracker, airborne, _rightLunge(), 3);
      expect(
        tracker.completionCount,
        1,
        reason: 'Left→air→right lunge jump should complete',
      );
    });

    test('INVALID: same-side lunge → air → same-side lunge = 0', () {
      final ctx = _buildLungeJumpSequence();
      final tracker = ctx.tracker;
      final airborne = ctx.airborne;

      // RIGHT_LUNGE → AIRBORNE → RIGHT_LUNGE (same side, expected LEFT)
      _feed(tracker, airborne, _rightLunge(), 8);
      expect(tracker.currentPhaseId, 'RIGHT_LUNGE');

      _feed(tracker, airborne, _jump(), 2);
      expect(tracker.currentPhaseId, 'AIRBORNE');

      // Right lunge again (expected LEFT_LUNGE) → wrong-phase reset
      _feed(tracker, airborne, _rightLunge(), 3);

      expect(
        tracker.completionCount,
        0,
        reason: 'Same-side return should not complete',
      );
    });

    test('INVALID: ordinary alternating lunges without air = 0', () {
      final ctx = _buildLungeJumpSequence();
      final tracker = ctx.tracker;
      final airborne = ctx.airborne;

      // Right lunge → left lunge (no airborne phase)
      _feed(tracker, airborne, _rightLunge(), 8);
      expect(tracker.currentPhaseId, 'RIGHT_LUNGE');

      // Left lunge directly (expected AIRBORNE) → wrong-phase reset
      _feed(tracker, airborne, _leftLunge(), 3);

      expect(
        tracker.completionCount,
        0,
        reason: 'Alternating lunges without jump should not complete',
      );
    });

    test('INVALID: ordinary jump without lunge geometry = 0', () {
      final ctx = _buildLungeJumpSequence();
      final tracker = ctx.tracker;
      final airborne = ctx.airborne;

      // Standing (not a lunge) → jump
      _feed(tracker, airborne, _standing(), 8);
      _feed(tracker, airborne, _jump(), 5);

      expect(
        tracker.completionCount,
        0,
        reason: 'Jump without lunge start should not complete',
      );
    });

    test('INVALID: partial sequence (right lunge only) = 0', () {
      final ctx = _buildLungeJumpSequence();
      final tracker = ctx.tracker;
      final airborne = ctx.airborne;

      _feed(tracker, airborne, _rightLunge(), 10);

      expect(
        tracker.completionCount,
        0,
        reason: 'Partial sequence should not complete',
      );
    });
  });
}

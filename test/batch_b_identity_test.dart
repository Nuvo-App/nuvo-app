import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/motion_validators.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';
import 'package:nuvo/features/races/domain/motion_activity.dart';
import 'package:nuvo/features/races/domain/motion_activity_catalog.dart';
import 'package:nuvo/features/races/presentation/widgets/preset_movement_demos.dart';

// ── Pose fixtures ───────────────────────────────────────────────────────────
//
// All fixtures use the same body scale as the proof tests:
//   shoulderY = 0.30, hipY = 0.50 (standing) → torsoHeight = 0.20
//   flightThreshold = max(0.025, 0.20 * 0.18) = 0.036
//   groundedTolerance = max(0.015, 0.20 * 0.10) = 0.020
//
// These are the SAME fixtures used in the test-only proof
// (test/jump_squat_lunge_jump_proof_test.dart). The production validator
// must produce the same identity results.

NuvoPosePoint _p(double x, double y, {double likelihood = 0.95}) =>
    NuvoPosePoint(x: x, y: y, z: 0, likelihood: likelihood);

NuvoPoseFrame _frame(Map<String, NuvoPosePoint> points) => NuvoPoseFrame(
      points: points,
      imageWidth: 1080,
      imageHeight: 1920,
      createdAt: DateTime.now(),
    );

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

/// Right lunge — right leg forward, left leg back.
/// Right knee angle = 113° < 120° (bent), left knee angle = 170° > 160° (straight).
NuvoPoseFrame _rightLunge() => _frame({
      'leftShoulder': _p(0.40, 0.30),
      'rightShoulder': _p(0.60, 0.30),
      'leftHip': _p(0.48, 0.50),
      'rightHip': _p(0.52, 0.50),
      'leftKnee': _p(0.35, 0.70),
      'rightKnee': _p(0.78, 0.62),
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
      'leftKnee': _p(0.22, 0.62),
      'rightKnee': _p(0.65, 0.70),
      'leftAnkle': _p(0.22, 0.90),
      'rightAnkle': _p(0.75, 0.90),
    });

/// Helper: feed N frames of the same pose to a validator.
void _feed(MotionValidator validator, NuvoPoseFrame frame, int count) {
  for (var i = 0; i < count; i++) {
    validator.update(frame);
  }
}

void main() {
  // ── Catalog + registration tests ──────────────────────────────────────────

  group('Jump Squats catalog registration', () {
    test('Jump Squats is in the catalog', () {
      expect(
        motionActivityDefinitions.any(
            (d) => d.type == MotionActivityType.jumpSquats),
        isTrue,
        reason: 'Jump Squats should be in the catalog',
      );
    });

    test('Jump Squats is in supportedMotionActivityTypes', () {
      expect(
        supportedMotionActivityTypes.contains(MotionActivityType.jumpSquats),
        isTrue,
      );
    });

    test('Jump Squats catalog entry has correct metadata', () {
      final def = motionActivityForType(MotionActivityType.jumpSquats)!;
      expect(def.title, 'Jump Squats');
      expect(def.metric, RaceMetric.reps);
      expect(def.isHold, isFalse);
      expect(def.category, MovementCategory.lowerBody);
      expect(def.preferredCameraView, PreferredCameraView.frontPreferred);
      expect(def.aliases, contains('jump squats'));
      expect(def.aliases, contains('jump squat'));
    });

    test('Jump Squats has a pre-verify demo', () {
      final demo = movementDemoForType(MotionActivityType.jumpSquats);
      expect(demo, isNotNull, reason: 'Jump Squats must have a demo');
      expect(demo!.poses.length, greaterThan(1));
    });

    test('createMotionValidator returns MultiPhaseSequenceValidator for jump squats', () {
      final validator = createMotionValidator(AiMotionActivity.jumpSquats, 15);
      expect(validator, isA<MultiPhaseSequenceValidator>());
      expect(validator.activity, AiMotionActivity.jumpSquats);
      expect(validator.targetValue, 15);
    });
  });

  group('Lunge Jumps catalog registration', () {
    test('Lunge Jumps is in the catalog', () {
      expect(
        motionActivityDefinitions.any(
            (d) => d.type == MotionActivityType.lungeJumps),
        isTrue,
        reason: 'Lunge Jumps should be in the catalog',
      );
    });

    test('Lunge Jumps is in supportedMotionActivityTypes', () {
      expect(
        supportedMotionActivityTypes.contains(MotionActivityType.lungeJumps),
        isTrue,
      );
    });

    test('Lunge Jumps catalog entry has correct metadata', () {
      final def = motionActivityForType(MotionActivityType.lungeJumps)!;
      expect(def.title, 'Lunge Jumps');
      expect(def.metric, RaceMetric.reps);
      expect(def.isHold, isFalse);
      expect(def.category, MovementCategory.lowerBody);
      expect(def.preferredCameraView, PreferredCameraView.frontOrSlightAngle);
      expect(def.aliases, contains('lunge jumps'));
      expect(def.aliases, contains('lunge jump'));
    });

    test('Lunge Jumps has a pre-verify demo', () {
      final demo = movementDemoForType(MotionActivityType.lungeJumps);
      expect(demo, isNotNull, reason: 'Lunge Jumps must have a demo');
      expect(demo!.poses.length, greaterThan(1));
    });

    test('createMotionValidator returns MultiPhaseSequenceValidator for lunge jumps', () {
      final validator = createMotionValidator(AiMotionActivity.lungeJumps, 15);
      expect(validator, isA<MultiPhaseSequenceValidator>());
      expect(validator.activity, AiMotionActivity.lungeJumps);
      expect(validator.targetValue, 15);
    });
  });

  // ── Jump Squat identity tests ─────────────────────────────────────────────

  group('Jump Squat identity (production validator)', () {
    MotionValidator _buildValidator({int target = 15}) =>
        createMotionValidator(AiMotionActivity.jumpSquats, target);

    test('VALID: standing → squat → jump → land → stand = 1 rep', () {
      final v = _buildValidator()..start();
      // STANDING: 8 frames (5 for airborne baseline + 3 for phase stability)
      _feed(v, _standing(), 8);
      // SQUAT: 3 frames
      _feed(v, _squat(), 3);
      // AIRBORNE: 2 frames
      _feed(v, _jump(), 2);
      // LANDING (standing): 3 frames → completion
      _feed(v, _standing(), 3);
      expect(v.currentValue, 1, reason: 'Full jump squat cycle = 1 rep');
    });

    test('INVALID: ordinary squat (no jump) = 0 reps', () {
      final v = _buildValidator()..start();
      _feed(v, _standing(), 8);
      _feed(v, _squat(), 3);
      // Return to standing — wrong-phase (expected AIRBORNE, got STANDING)
      _feed(v, _standing(), 3);
      expect(v.currentValue, 0, reason: 'Squat without jump = 0');
    });

    test('INVALID: ordinary two-foot jump without squat = 0 reps', () {
      final v = _buildValidator()..start();
      _feed(v, _standing(), 8);
      // Jump without squat — wrong-phase (expected SQUAT, got AIRBORNE)
      _feed(v, _jump(), 3);
      expect(v.currentValue, 0, reason: 'Jump without squat = 0');
    });

    test('INVALID: jumping jack = 0 reps', () {
      final v = _buildValidator()..start();
      _feed(v, _standing(), 8);
      _feed(v, _jumpingJackOpen(), 5);
      expect(v.currentValue, 0, reason: 'Jumping jack = 0');
    });

    test('INVALID: incomplete squat+jump sequence = 0 reps', () {
      final v = _buildValidator()..start();
      _feed(v, _standing(), 8);
      _feed(v, _squat(), 3);
      // Only 1 airborne frame (needs 2 for stability)
      _feed(v, _jump(), 1);
      // Back to standing — wrong-phase
      _feed(v, _standing(), 3);
      expect(v.currentValue, 0, reason: 'Incomplete sequence = 0');
    });

    test('repeated valid jump squats = 2 reps', () {
      final v = _buildValidator()..start();
      // First rep
      _feed(v, _standing(), 8);
      _feed(v, _squat(), 3);
      _feed(v, _jump(), 2);
      _feed(v, _standing(), 3);
      expect(v.currentValue, 1);
      // Second rep — need standing frames for cooldown (3) + reset rearm (1)
      // + STANDING phase stability (3) = 7 minimum. Use 8 for safety.
      _feed(v, _standing(), 8);
      _feed(v, _squat(), 3);
      _feed(v, _jump(), 2);
      _feed(v, _standing(), 3);
      expect(v.currentValue, 2, reason: 'Two full cycles = 2 reps');
    });

    test('target cap works', () {
      final v = _buildValidator(target: 1)..start();
      _feed(v, _standing(), 8);
      _feed(v, _squat(), 3);
      _feed(v, _jump(), 2);
      _feed(v, _standing(), 3);
      expect(v.currentValue, 1, reason: 'Capped at target');
      // Second rep — tracker rearms but cap holds at 1
      _feed(v, _standing(), 8);
      _feed(v, _squat(), 3);
      _feed(v, _jump(), 2);
      _feed(v, _standing(), 3);
      expect(v.currentValue, 1, reason: 'Still capped at target');
    });

    test('reset/rearm works', () {
      final v = _buildValidator()..start();
      _feed(v, _standing(), 8);
      _feed(v, _squat(), 3);
      _feed(v, _jump(), 2);
      _feed(v, _standing(), 3);
      expect(v.currentValue, 1);
      // Reset
      v.reset();
      expect(v.currentValue, 0, reason: 'Reset clears count');
      // Can count again after reset
      _feed(v, _standing(), 8);
      _feed(v, _squat(), 3);
      _feed(v, _jump(), 2);
      _feed(v, _standing(), 3);
      expect(v.currentValue, 1, reason: 'Counts again after reset');
    });
  });

  // ── Lunge Jump identity tests ─────────────────────────────────────────────

  group('Lunge Jump identity (production validator)', () {
    MotionValidator _buildValidator({int target = 15}) =>
        createMotionValidator(AiMotionActivity.lungeJumps, target);

    test('VALID: right lunge → air → left lunge = 1 rep', () {
      final v = _buildValidator()..start();
      // RIGHT_LUNGE: 8 frames (baseline + stability)
      _feed(v, _rightLunge(), 8);
      // AIRBORNE: 2 frames
      _feed(v, _jump(), 2);
      // LEFT_LUNGE: 3 frames → completion
      _feed(v, _leftLunge(), 3);
      expect(v.currentValue, 1, reason: 'Right→air→left = 1 rep');
    });

    test('VALID: left lunge → air → right lunge = 1 rep', () {
      final v = _buildValidator()..start();
      // LEFT_LUNGE: 8 frames (baseline + stability)
      _feed(v, _leftLunge(), 8);
      // AIRBORNE: 2 frames
      _feed(v, _jump(), 2);
      // RIGHT_LUNGE: 3 frames → completion
      _feed(v, _rightLunge(), 3);
      expect(v.currentValue, 1, reason: 'Left→air→right = 1 rep');
    });

    test('repeated alternating reps = 2 reps', () {
      final v = _buildValidator()..start();
      // First rep: right → air → left
      _feed(v, _rightLunge(), 8);
      _feed(v, _jump(), 2);
      _feed(v, _leftLunge(), 3);
      expect(v.currentValue, 1);
      // Second rep: left → air → right
      // After first completion, the left-start tracker is in awaitingReset.
      // Feeding leftLunge frames: cooldown (3) + reset check (standing).
      // But leftLunge is not standing, so the right-start tracker's reset
      // condition (standing) won't be met. We need standing frames to rearm.
      _feed(v, _standing(), 5);
      // Now both trackers are rearmed. Left-start tracker can begin with
      // leftLunge.
      _feed(v, _leftLunge(), 8);
      _feed(v, _jump(), 2);
      _feed(v, _rightLunge(), 3);
      expect(v.currentValue, 2, reason: 'Two alternating reps = 2');
    });

    test('INVALID: same-side return (right→air→right) = 0 reps', () {
      final v = _buildValidator()..start();
      _feed(v, _rightLunge(), 8);
      _feed(v, _jump(), 2);
      // Same-side return — wrong-phase for the right-start tracker
      // (expected LEFT_LUNGE, got RIGHT_LUNGE)
      _feed(v, _rightLunge(), 3);
      expect(v.currentValue, 0, reason: 'Same-side return = 0');
    });

    test('INVALID: left→air→left = 0 reps', () {
      final v = _buildValidator()..start();
      _feed(v, _leftLunge(), 8);
      _feed(v, _jump(), 2);
      // Same-side return — wrong-phase for the left-start tracker
      _feed(v, _leftLunge(), 3);
      expect(v.currentValue, 0, reason: 'Same-side return = 0');
    });

    test('INVALID: ordinary lunges without air = 0 reps', () {
      final v = _buildValidator()..start();
      _feed(v, _rightLunge(), 8);
      // No jump — go directly to left lunge (wrong-phase, expected AIRBORNE)
      _feed(v, _leftLunge(), 3);
      expect(v.currentValue, 0, reason: 'Lunges without jump = 0');
    });

    test('INVALID: ordinary jump without lunge geometry = 0 reps', () {
      final v = _buildValidator()..start();
      // Standing (not a lunge) — no tracker progresses
      _feed(v, _standing(), 8);
      _feed(v, _jump(), 3);
      expect(v.currentValue, 0, reason: 'Jump without lunge = 0');
    });

    test('INVALID: partial sequence (right lunge only) = 0 reps', () {
      final v = _buildValidator()..start();
      _feed(v, _rightLunge(), 8);
      expect(v.currentValue, 0, reason: 'Partial sequence = 0');
    });

    test('target cap works', () {
      final v = _buildValidator(target: 1)..start();
      _feed(v, _rightLunge(), 8);
      _feed(v, _jump(), 2);
      _feed(v, _leftLunge(), 3);
      expect(v.currentValue, 1, reason: 'Capped at target');
      // Second rep attempt
      _feed(v, _standing(), 5);
      _feed(v, _leftLunge(), 8);
      _feed(v, _jump(), 2);
      _feed(v, _rightLunge(), 3);
      expect(v.currentValue, 1, reason: 'Still capped at target');
    });

    test('reset/rearm works', () {
      final v = _buildValidator()..start();
      _feed(v, _rightLunge(), 8);
      _feed(v, _jump(), 2);
      _feed(v, _leftLunge(), 3);
      expect(v.currentValue, 1);
      v.reset();
      expect(v.currentValue, 0, reason: 'Reset clears count');
      // Can count again after reset
      _feed(v, _rightLunge(), 8);
      _feed(v, _jump(), 2);
      _feed(v, _leftLunge(), 3);
      expect(v.currentValue, 1, reason: 'Counts again after reset');
    });
  });
}

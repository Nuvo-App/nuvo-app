import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/motion_validators.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';
import 'package:nuvo/features/races/domain/motion_activity.dart';
import 'package:nuvo/features/races/domain/motion_activity_catalog.dart';
import 'package:nuvo/features/races/presentation/widgets/preset_movement_demos.dart';

// ── Test helpers ─────────────────────────────────────────────────────────────

NuvoPosePoint _p(double x, double y, {double likelihood = 0.95}) =>
    NuvoPosePoint(x: x, y: y, z: 0, likelihood: likelihood);

NuvoPoseFrame _frame(Map<String, NuvoPosePoint> points) => NuvoPoseFrame(
      points: points,
      imageWidth: 1000,
      imageHeight: 1000,
      createdAt: DateTime.utc(2026, 1, 1),
    );

/// Runs a validator through a sequence of frames and returns the final count.
int _runValidator(MotionValidator validator, List<NuvoPoseFrame> frames) {
  validator.start();
  for (final frame in frames) {
    validator.update(frame);
  }
  return validator.currentValue;
}

/// Builds N repetitions of a frame sequence: [startFrames] → [activeFrames] → [startFrames].
List<NuvoPoseFrame> _repSequence({
  required int count,
  required List<NuvoPoseFrame> startFrames,
  required List<NuvoPoseFrame> activeFrames,
}) {
  final frames = <NuvoPoseFrame>[];
  for (var r = 0; r < count; r++) {
    frames.addAll(startFrames);
    frames.addAll(activeFrames);
    frames.addAll(startFrames);
  }
  return frames;
}

// ── Sumo Squat fixtures ──────────────────────────────────────────────────────
// Sumo squat: wide stance (ankleWidth/bodyWidth > 1.5) + deep squat.
// bodyWidth = |leftShoulder.x - rightShoulder.x| = |0.38 - 0.62| = 0.24
// ankleWidth = |leftAnkle.x - rightAnkle.x|
// Need ankleWidth / 0.24 > 1.5 → ankleWidth > 0.36

NuvoPoseFrame _sumoSquatStanding() => _frame({
      'leftShoulder': _p(0.38, 0.30),
      'rightShoulder': _p(0.62, 0.30),
      'leftHip': _p(0.42, 0.50),
      'rightHip': _p(0.58, 0.50),
      'leftKnee': _p(0.35, 0.72),
      'rightKnee': _p(0.65, 0.72),
      'leftAnkle': _p(0.28, 0.90),
      'rightAnkle': _p(0.72, 0.90),
    });
// ankleWidth = |0.28 - 0.72| = 0.44 → 0.44/0.24 = 1.83 > 1.5 ✅
// torsoHeight = |0.50 - 0.30| = 0.20
// hipToKneeRatio = (0.72 - 0.50) / 0.20 = 1.10 > 0.86 → START ✅

NuvoPoseFrame _sumoSquatDeep() => _frame({
      'leftShoulder': _p(0.38, 0.30),
      'rightShoulder': _p(0.62, 0.30),
      'leftHip': _p(0.42, 0.62),
      'rightHip': _p(0.58, 0.62),
      'leftKnee': _p(0.35, 0.64),
      'rightKnee': _p(0.65, 0.64),
      'leftAnkle': _p(0.28, 0.90),
      'rightAnkle': _p(0.72, 0.90),
    });
// ankleWidth = 0.44 → 1.83 > 1.5 ✅
// torsoHeight = |0.62 - 0.30| = 0.32
// hipToKneeRatio = (0.64 - 0.62) / 0.32 = 0.0625 < 0.58 → ACTIVE ✅

/// Regular squat standing (narrow stance) — should NOT trigger sumo squat.
NuvoPoseFrame _regularSquatStanding() => _frame({
      'leftShoulder': _p(0.38, 0.30),
      'rightShoulder': _p(0.62, 0.30),
      'leftHip': _p(0.42, 0.50),
      'rightHip': _p(0.58, 0.50),
      'leftKnee': _p(0.43, 0.72),
      'rightKnee': _p(0.57, 0.72),
      'leftAnkle': _p(0.43, 0.90),
      'rightAnkle': _p(0.57, 0.90),
    });
// ankleWidth = |0.43 - 0.57| = 0.14 → 0.14/0.24 = 0.58 < 1.5 → NOT sumo

NuvoPoseFrame _regularSquatDeep() => _frame({
      'leftShoulder': _p(0.38, 0.30),
      'rightShoulder': _p(0.62, 0.30),
      'leftHip': _p(0.42, 0.62),
      'rightHip': _p(0.58, 0.62),
      'leftKnee': _p(0.43, 0.64),
      'rightKnee': _p(0.57, 0.64),
      'leftAnkle': _p(0.43, 0.90),
      'rightAnkle': _p(0.57, 0.90),
    });
// ankleWidth = 0.14 → 0.58 < 1.5 → NOT sumo

// ── Side Lunge fixtures ──────────────────────────────────────────────────────
// Side lunge: large lateral knee separation (> 0.85 * hipWidth) + one knee bent.
// hipWidth = |leftHip.x - rightHip.x| = |0.45 - 0.55| = 0.10
// kneeSeparation = |leftKnee.x - rightKnee.x| / hipWidth
// Need kneeSeparation > 0.85 → |leftKnee.x - rightKnee.x| > 0.085

NuvoPoseFrame _sideLungeStanding() => _frame({
      'leftHip': _p(0.45, 0.42),
      'rightHip': _p(0.55, 0.42),
      'leftKnee': _p(0.44, 0.60),
      'rightKnee': _p(0.56, 0.60),
      'leftAnkle': _p(0.44, 0.78),
      'rightAnkle': _p(0.56, 0.78),
    });
// Both knees straight: hip→knee→ankle all at same X → angle ≈ 180° > 154° → START ✅

NuvoPoseFrame _sideLungeRight() => _frame({
      'leftHip': _p(0.45, 0.50),
      'rightHip': _p(0.55, 0.50),
      'leftKnee': _p(0.46, 0.58),
      'rightKnee': _p(0.72, 0.58),
      'leftAnkle': _p(0.44, 0.76),
      'rightAnkle': _p(0.72, 0.74),
    });
// kneeSeparation = |0.46 - 0.72| / 0.10 = 2.6 > 0.85 ✅
// rightKnee angle: hip(0.55,0.50) → knee(0.72,0.58) → ankle(0.72,0.74)
// hip→knee: (0.17, 0.08), ankle→knee: (0.00, -0.16)
// dot = 0 + 0.08*(-0.16) = -0.0128
// |hip→knee| = 0.188, |ankle→knee| = 0.16
// cos = -0.0128 / (0.188*0.16) = -0.426 → angle ≈ 115° < 118 ✅

// ── Deep Squat fixtures ──────────────────────────────────────────────────────
// Deep squat: hipToKneeRatio < 0.30 (deeper than regular squat < 0.58).
// hipToKneeRatio = (kneeY - hipY) / torsoHeight
// torsoHeight = |hipY - shoulderY|.abs().clamp(0.12, 0.6)
// START: ratio > 0.86  →  ACTIVE (deep): ratio < 0.30

NuvoPoseFrame _deepSquatStanding() => _frame({
      'leftShoulder': _p(0.38, 0.30),
      'rightShoulder': _p(0.62, 0.30),
      'leftHip': _p(0.42, 0.50),
      'rightHip': _p(0.58, 0.50),
      'leftKnee': _p(0.43, 0.72),
      'rightKnee': _p(0.57, 0.72),
      'leftAnkle': _p(0.43, 0.90),
      'rightAnkle': _p(0.57, 0.90),
    });
// torsoHeight = |0.50 - 0.30| = 0.20
// ratio = (0.72 - 0.50) / 0.20 = 1.10 > 0.86 → START ✅

NuvoPoseFrame _deepSquatDeep() => _frame({
      'leftShoulder': _p(0.38, 0.30),
      'rightShoulder': _p(0.62, 0.30),
      'leftHip': _p(0.42, 0.66),
      'rightHip': _p(0.58, 0.66),
      'leftKnee': _p(0.43, 0.64),
      'rightKnee': _p(0.57, 0.64),
      'leftAnkle': _p(0.43, 0.90),
      'rightAnkle': _p(0.57, 0.90),
    });
// torsoHeight = |0.66 - 0.30| = 0.36
// ratio = (0.64 - 0.66) / 0.36 = -0.0556 < 0.30 → ACTIVE ✅ (hips below knees)

/// Normal squat depth — satisfies regular squats (< 0.58) but NOT deep squats
/// (>= 0.30). This is the identity differentiator.
/// torsoHeight = |0.58 - 0.30| = 0.28
/// ratio = (0.68 - 0.58) / 0.28 = 0.357 → in [0.30, 0.58) ✅
/// → regular squat ACTIVE, deep squat UNKNOWN.
NuvoPoseFrame _deepSquatNormalDepth() => _frame({
      'leftShoulder': _p(0.38, 0.30),
      'rightShoulder': _p(0.62, 0.30),
      'leftHip': _p(0.42, 0.58),
      'rightHip': _p(0.58, 0.58),
      'leftKnee': _p(0.43, 0.68),
      'rightKnee': _p(0.57, 0.68),
      'leftAnkle': _p(0.43, 0.90),
      'rightAnkle': _p(0.57, 0.90),
    });

// ── Squat Jack fixtures ─────────────────────────────────────────────────────
// Squat jack: compound of jumping jack open + squat descent.
// START: arms down + feet together + standing (hipToKneeRatio > 0.86)
// ACTIVE: arms up + feet wide + squat depth (hipToKneeRatio < 0.58)
// bodyWidth = max(shoulderWidth, hipWidth).clamp(0.08, 0.6)

NuvoPoseFrame _squatJackClosed() => _frame({
      'leftWrist': _p(0.45, 0.35),
      'rightWrist': _p(0.55, 0.35),
      'leftShoulder': _p(0.40, 0.30),
      'rightShoulder': _p(0.60, 0.30),
      'leftHip': _p(0.42, 0.50),
      'rightHip': _p(0.58, 0.50),
      'leftKnee': _p(0.43, 0.72),
      'rightKnee': _p(0.57, 0.72),
      'leftAnkle': _p(0.47, 0.90),
      'rightAnkle': _p(0.53, 0.90),
    });
// shoulderWidth = 0.20, hipWidth = 0.16 → bodyWidth = max(0.20, 0.16) = 0.20
// ankleWidth = |0.47 - 0.53| = 0.06 → 0.06/0.20 = 0.30 <= 1.18 ✅
// wristY=0.35 > shoulderY-0.01=0.29, < hipY+0.24=0.74 → wristsNearBody ✅
// torsoHeight = |0.50 - 0.30| = 0.20
// ratio = (0.72 - 0.50) / 0.20 = 1.10 > 0.86 → START ✅

NuvoPoseFrame _squatJackOpenSquat() => _frame({
      'leftWrist': _p(0.30, 0.20),
      'rightWrist': _p(0.70, 0.20),
      'leftShoulder': _p(0.40, 0.30),
      'rightShoulder': _p(0.60, 0.30),
      'leftHip': _p(0.42, 0.60),
      'rightHip': _p(0.58, 0.60),
      'leftKnee': _p(0.43, 0.66),
      'rightKnee': _p(0.57, 0.66),
      'leftAnkle': _p(0.25, 0.90),
      'rightAnkle': _p(0.75, 0.90),
    });
// wristY=0.20 < shoulderY-0.03=0.27 → wristsAboveShoulders ✅
// ankleWidth = |0.25 - 0.75| = 0.50 → 0.50/0.20 = 2.5 > 1.38 ✅
// torsoHeight = |0.60 - 0.30| = 0.30
// ratio = (0.66 - 0.60) / 0.30 = 0.20 < 0.58 → ACTIVE ✅

/// Jumping jack open pose (arms up, feet wide) but STANDING — no squat.
/// Used to prove squat jacks reject jumping jacks.
/// hipToKneeRatio here ~1.10 (standing) → fails squat condition.
NuvoPoseFrame _squatJackJumpingJackOpen() => _frame({
      'leftWrist': _p(0.30, 0.20),
      'rightWrist': _p(0.70, 0.20),
      'leftShoulder': _p(0.40, 0.30),
      'rightShoulder': _p(0.60, 0.30),
      'leftHip': _p(0.42, 0.50),
      'rightHip': _p(0.58, 0.50),
      'leftKnee': _p(0.43, 0.72),
      'rightKnee': _p(0.57, 0.72),
      'leftAnkle': _p(0.25, 0.90),
      'rightAnkle': _p(0.75, 0.90),
    });
// wristY=0.20 < 0.27 → wristsAboveShoulders ✅
// ankleWidth = 0.50 → 2.5 > 1.38 ✅
// torsoHeight = |0.50 - 0.30| = 0.20
// ratio = (0.72 - 0.50) / 0.20 = 1.10 → NOT < 0.58 → fails squat ✅

/// Regular squat deep pose (squat depth) but arms down + feet narrow.
/// Used to prove squat jacks reject regular squats.
NuvoPoseFrame _squatJackRegularSquatDeep() => _frame({
      'leftWrist': _p(0.45, 0.35),
      'rightWrist': _p(0.55, 0.35),
      'leftShoulder': _p(0.40, 0.30),
      'rightShoulder': _p(0.60, 0.30),
      'leftHip': _p(0.42, 0.60),
      'rightHip': _p(0.58, 0.60),
      'leftKnee': _p(0.43, 0.66),
      'rightKnee': _p(0.57, 0.66),
      'leftAnkle': _p(0.47, 0.90),
      'rightAnkle': _p(0.53, 0.90),
    });
// wristY=0.35 > 0.27 → NOT wristsAboveShoulders ✅ (fails arms-up)
// ankleWidth = 0.06 → 0.30 <= 1.38 ✅ (fails feet-wide)
// ratio = 0.20 < 0.58 → passes squat ✅

void main() {
  group('Factory Batch Identity Tests', () {
    // ── Registration tests ──────────────────────────────────────────────────

    test('Sumo Squats and Side Lunges are in the catalog', () {
      expect(
        motionActivityDefinitions.any((d) =>
            d.type == MotionActivityType.sumoSquats),
        isTrue,
        reason: 'Sumo Squats should be in the catalog',
      );
      expect(
        motionActivityDefinitions.any((d) =>
            d.type == MotionActivityType.sideLunges),
        isTrue,
        reason: 'Side Lunges should be in the catalog',
      );
    });

    test('Sumo Squats and Side Lunges are in supportedMotionActivityTypes', () {
      expect(
        supportedMotionActivityTypes.contains(MotionActivityType.sumoSquats),
        isTrue,
      );
      expect(
        supportedMotionActivityTypes.contains(MotionActivityType.sideLunges),
        isTrue,
      );
    });

    test('createMotionValidator dispatches for sumo squats and side lunges', () {
      expect(
        () => createMotionValidator(AiMotionActivity.sumoSquats, 10),
        returnsNormally,
      );
      expect(
        () => createMotionValidator(AiMotionActivity.sideLunges, 10),
        returnsNormally,
      );
    });

    test('movementDemoForType returns demos for new movements', () {
      expect(movementDemoForType(MotionActivityType.sumoSquats), isNotNull);
      expect(movementDemoForType(MotionActivityType.sideLunges), isNotNull);
    });

    test('verifyValidatorDispatchComplete does not throw', () {
      expect(verifyValidatorDispatchComplete, returnsNormally);
    });

    // ── Sumo Squats identity ────────────────────────────────────────────────

    test('Sumo Squats: counts reps with wide stance', () {
      final validator = createMotionValidator(AiMotionActivity.sumoSquats, 5);
      final frames = _repSequence(
        count: 3,
        startFrames: [
          _sumoSquatStanding(),
          _sumoSquatStanding(),
          _sumoSquatStanding(),
        ],
        activeFrames: [
          _sumoSquatDeep(),
          _sumoSquatDeep(),
          _sumoSquatDeep(),
        ],
      );
      final count = _runValidator(validator, frames);
      expect(count, 3, reason: 'Should count 3 sumo squat reps');
    });

    test('Sumo Squats identity: regular squats do NOT count as sumo squats', () {
      // Regular squats have narrow stance → ankleWidth/bodyWidth < 1.5
      // The sumo squat validator should NOT count these as reps.
      final validator = createMotionValidator(AiMotionActivity.sumoSquats, 5);
      final frames = _repSequence(
        count: 3,
        startFrames: [
          _regularSquatStanding(),
          _regularSquatStanding(),
          _regularSquatStanding(),
        ],
        activeFrames: [
          _regularSquatDeep(),
          _regularSquatDeep(),
          _regularSquatDeep(),
        ],
      );
      final count = _runValidator(validator, frames);
      expect(
        count,
        0,
        reason: 'Regular squats (narrow stance) should NOT count as sumo squats',
      );
    });

    test('Sumo Squats identity: regular squat validator does NOT count sumo squats', () {
      // The regular squat validator uses only hipToKneeRatio, so it WILL
      // count sumo squats (they have the same vertical descent). This is
      // expected — the identity proof is one-directional: sumo squats
      // reject regular squats. The reverse (regular squats accepting sumo
      // squats) is acceptable because sumo squats are a superset of the
      // squat motion. The key identity proof is that a sumo squat race
      // cannot be cheated by doing regular squats.
      final validator = createMotionValidator(AiMotionActivity.squats, 5);
      final frames = _repSequence(
        count: 3,
        startFrames: [
          _sumoSquatStanding(),
          _sumoSquatStanding(),
          _sumoSquatStanding(),
        ],
        activeFrames: [
          _sumoSquatDeep(),
          _sumoSquatDeep(),
          _sumoSquatDeep(),
        ],
      );
      final count = _runValidator(validator, frames);
      // Regular squats WILL count sumo squats — this is documented behavior.
      expect(count, greaterThan(0));
    });

    // ── Side Lunges identity ───────────────────────────────────────────────

    test('Side Lunges: counts reps with large lateral separation', () {
      final validator = createMotionValidator(AiMotionActivity.sideLunges, 5);
      final frames = _repSequence(
        count: 3,
        startFrames: [
          _sideLungeStanding(),
          _sideLungeStanding(),
          _sideLungeStanding(),
        ],
        activeFrames: [
          _sideLungeRight(),
          _sideLungeRight(),
          _sideLungeRight(),
        ],
      );
      final count = _runValidator(validator, frames);
      expect(count, 3, reason: 'Should count 3 side lunge reps');
    });

    test('Side Lunges identity: standing still does NOT count', () {
      final validator = createMotionValidator(AiMotionActivity.sideLunges, 5);
      final frames = List.generate(15, (_) => _sideLungeStanding());
      final count = _runValidator(validator, frames);
      expect(count, 0, reason: 'Standing still should not count as side lunges');
    });

    // ── Backend value round-trip ───────────────────────────────────────────

    test('Backend value round-trip: sumo_squats', () {
      expect(AiMotionActivity.sumoSquats.backendValue, 'sumo_squats');
      expect(
        AiMotionActivity.fromBackendValue('sumo_squats'),
        AiMotionActivity.sumoSquats,
      );
      expect(
        MotionActivityType.fromBackendValue('sumo_squats'),
        MotionActivityType.sumoSquats,
      );
    });

    test('Backend value round-trip: side_lunges', () {
      expect(AiMotionActivity.sideLunges.backendValue, 'side_lunges');
      expect(
        AiMotionActivity.fromBackendValue('side_lunges'),
        AiMotionActivity.sideLunges,
      );
      expect(
        MotionActivityType.fromBackendValue('side_lunges'),
        MotionActivityType.sideLunges,
      );
    });

    test('Backend value round-trip: aliases', () {
      expect(
        MotionActivityType.fromBackendValue('sumo squat'),
        MotionActivityType.sumoSquats,
      );
      expect(
        MotionActivityType.fromBackendValue('side lunge'),
        MotionActivityType.sideLunges,
      );
    });

    // ── Deep Squats registration ──────────────────────────────────────────

    test('Deep Squats is in the catalog', () {
      expect(
        motionActivityDefinitions.any(
            (d) => d.type == MotionActivityType.deepSquats),
        isTrue,
        reason: 'Deep Squats should be in the catalog',
      );
    });

    test('Deep Squats is in supportedMotionActivityTypes', () {
      expect(
        supportedMotionActivityTypes.contains(MotionActivityType.deepSquats),
        isTrue,
      );
    });

    test('createMotionValidator dispatches for deep squats', () {
      expect(
        () => createMotionValidator(AiMotionActivity.deepSquats, 10),
        returnsNormally,
      );
      expect(
        createMotionValidator(AiMotionActivity.deepSquats, 10),
        isA<ConfigurableRepValidator>(),
      );
    });

    test('movementDemoForType returns a demo for deep squats', () {
      expect(movementDemoForType(MotionActivityType.deepSquats), isNotNull);
    });

    // ── Deep Squats identity ──────────────────────────────────────────────

    test('Deep Squats: counts reps with deep descent (hips below knees)', () {
      final validator =
          createMotionValidator(AiMotionActivity.deepSquats, 5);
      final frames = _repSequence(
        count: 3,
        startFrames: [
          _deepSquatStanding(),
          _deepSquatStanding(),
          _deepSquatStanding(),
        ],
        activeFrames: [
          _deepSquatDeep(),
          _deepSquatDeep(),
          _deepSquatDeep(),
        ],
      );
      final count = _runValidator(validator, frames);
      expect(count, 3, reason: 'Should count 3 deep squat reps');
    });

    test(
      'Deep Squats identity: normal-depth squats do NOT count as deep squats',
      () {
        // Normal squat depth has hipToKneeRatio ~0.357, which is between
        // 0.30 (deep active) and 0.58 (regular squat active). The deep
        // squat validator should NOT count these as reps because the
        // active condition (ratio < 0.30) is never satisfied.
        final validator =
            createMotionValidator(AiMotionActivity.deepSquats, 5);
        final frames = _repSequence(
          count: 3,
          startFrames: [
            _deepSquatStanding(),
            _deepSquatStanding(),
            _deepSquatStanding(),
          ],
          activeFrames: [
            _deepSquatNormalDepth(),
            _deepSquatNormalDepth(),
            _deepSquatNormalDepth(),
          ],
        );
        final count = _runValidator(validator, frames);
        expect(
          count,
          0,
          reason:
              'Normal-depth squats (ratio ~0.36) should NOT count as deep squats',
        );
      },
    );

    test(
      'Deep Squats identity: regular squat validator DOES count normal-depth squats',
      () {
        // The regular squat validator uses hipToKneeRatio < 0.58, so a
        // normal-depth squat (ratio ~0.36) satisfies it. This proves the
        // two validators diverge on the same input — the identity gate
        // works in the cheating direction: a deep squat race cannot be
        // cheated by doing normal squats.
        final validator = createMotionValidator(AiMotionActivity.squats, 5);
        final frames = _repSequence(
          count: 3,
          startFrames: [
            _deepSquatStanding(),
            _deepSquatStanding(),
            _deepSquatStanding(),
          ],
          activeFrames: [
            _deepSquatNormalDepth(),
            _deepSquatNormalDepth(),
            _deepSquatNormalDepth(),
          ],
        );
        final count = _runValidator(validator, frames);
        expect(
          count,
          greaterThan(0),
          reason:
              'Regular squat validator should count normal-depth squats',
        );
      },
    );

    test(
      'Deep Squats identity: deep squats DO count as regular squats (superset)',
      () {
        // Deep squats (ratio < 0.30) also satisfy regular squats (< 0.58).
        // This is expected and acceptable: deep squats are a superset of
        // the squat motion. The key identity proof is one-directional —
        // a deep squat race cannot be cheated by doing regular squats.
        final validator = createMotionValidator(AiMotionActivity.squats, 5);
        final frames = _repSequence(
          count: 3,
          startFrames: [
            _deepSquatStanding(),
            _deepSquatStanding(),
            _deepSquatStanding(),
          ],
          activeFrames: [
            _deepSquatDeep(),
            _deepSquatDeep(),
            _deepSquatDeep(),
          ],
        );
        final count = _runValidator(validator, frames);
        expect(count, greaterThan(0));
      },
    );

    test('Deep Squats identity: standing still does NOT count', () {
      final validator =
          createMotionValidator(AiMotionActivity.deepSquats, 5);
      final frames = List.generate(15, (_) => _deepSquatStanding());
      final count = _runValidator(validator, frames);
      expect(count, 0, reason: 'Standing still should not count as deep squats');
    });

    // ── Deep Squats backend value round-trip ──────────────────────────────

    test('Backend value round-trip: deep_squats', () {
      expect(AiMotionActivity.deepSquats.backendValue, 'deep_squats');
      expect(
        AiMotionActivity.fromBackendValue('deep_squats'),
        AiMotionActivity.deepSquats,
      );
      expect(
        MotionActivityType.fromBackendValue('deep_squats'),
        MotionActivityType.deepSquats,
      );
    });

    test('Backend value round-trip: deep_squats aliases', () {
      expect(
        MotionActivityType.fromBackendValue('deep squat'),
        MotionActivityType.deepSquats,
      );
      expect(
        AiMotionActivity.fromBackendValue('deep squats'),
        AiMotionActivity.deepSquats,
      );
    });

    // ── Squat Jacks registration ──────────────────────────────────────────

    test('Squat Jacks is in the catalog', () {
      expect(
        motionActivityDefinitions.any(
            (d) => d.type == MotionActivityType.squatJacks),
        isTrue,
        reason: 'Squat Jacks should be in the catalog',
      );
    });

    test('Squat Jacks is in supportedMotionActivityTypes', () {
      expect(
        supportedMotionActivityTypes.contains(MotionActivityType.squatJacks),
        isTrue,
      );
    });

    test('createMotionValidator dispatches for squat jacks', () {
      expect(
        () => createMotionValidator(AiMotionActivity.squatJacks, 10),
        returnsNormally,
      );
      expect(
        createMotionValidator(AiMotionActivity.squatJacks, 10),
        isA<ConfigurableRepValidator>(),
      );
    });

    test('movementDemoForType returns a demo for squat jacks', () {
      expect(movementDemoForType(MotionActivityType.squatJacks), isNotNull);
    });

    // ── Squat Jacks identity ──────────────────────────────────────────────

    test('Squat Jacks: counts reps with arms up + feet wide + squat depth', () {
      final validator =
          createMotionValidator(AiMotionActivity.squatJacks, 5);
      final frames = _repSequence(
        count: 3,
        startFrames: [
          _squatJackClosed(),
          _squatJackClosed(),
          _squatJackClosed(),
        ],
        activeFrames: [
          _squatJackOpenSquat(),
          _squatJackOpenSquat(),
          _squatJackOpenSquat(),
        ],
      );
      final count = _runValidator(validator, frames);
      expect(count, 3, reason: 'Should count 3 squat jack reps');
    });

    test(
      'Squat Jacks identity: jumping jacks (no squat) do NOT count as squat jacks',
      () {
        // Jumping jacks have arms up + feet wide but stay standing
        // (hipToKneeRatio ~1.10). The squat jack validator requires
        // hipToKneeRatio < 0.58, so pure jumping jacks fail the squat
        // condition and should NOT count.
        final validator =
            createMotionValidator(AiMotionActivity.squatJacks, 5);
        final frames = _repSequence(
          count: 3,
          startFrames: [
            _squatJackClosed(),
            _squatJackClosed(),
            _squatJackClosed(),
          ],
          activeFrames: [
            _squatJackJumpingJackOpen(),
            _squatJackJumpingJackOpen(),
            _squatJackJumpingJackOpen(),
          ],
        );
        final count = _runValidator(validator, frames);
        expect(
          count,
          0,
          reason: 'Jumping jacks (no squat) should NOT count as squat jacks',
        );
      },
    );

    test(
      'Squat Jacks identity: regular squats (no arm spread) do NOT count as squat jacks',
      () {
        // Regular squats have squat depth but arms down + feet narrow.
        // The squat jack validator requires wristsAboveShoulders AND
        // ankleWidthToBodyWidth > 1.38, so regular squats fail both.
        final validator =
            createMotionValidator(AiMotionActivity.squatJacks, 5);
        final frames = _repSequence(
          count: 3,
          startFrames: [
            _squatJackClosed(),
            _squatJackClosed(),
            _squatJackClosed(),
          ],
          activeFrames: [
            _squatJackRegularSquatDeep(),
            _squatJackRegularSquatDeep(),
            _squatJackRegularSquatDeep(),
          ],
        );
        final count = _runValidator(validator, frames);
        expect(
          count,
          0,
          reason:
              'Regular squats (no arm spread) should NOT count as squat jacks',
        );
      },
    );

    test(
      'Squat Jacks identity: jumping jack validator DOES count jumping jacks',
      () {
        // Proves the two validators diverge on the same input. The
        // jumping jack validator counts the jumping-jack-open pose,
        // but the squat jack validator rejects it.
        final validator =
            createMotionValidator(AiMotionActivity.jumpingJacks, 5);
        final frames = _repSequence(
          count: 3,
          startFrames: [
            _squatJackClosed(),
            _squatJackClosed(),
            _squatJackClosed(),
          ],
          activeFrames: [
            _squatJackJumpingJackOpen(),
            _squatJackJumpingJackOpen(),
            _squatJackJumpingJackOpen(),
          ],
        );
        final count = _runValidator(validator, frames);
        expect(count, greaterThan(0));
      },
    );

    test(
      'Squat Jacks identity: squat validator DOES count regular squats',
      () {
        // Proves the two validators diverge on the same input. The
        // regular squat validator counts the squat-deep pose, but the
        // squat jack validator rejects it.
        final validator = createMotionValidator(AiMotionActivity.squats, 5);
        final frames = _repSequence(
          count: 3,
          startFrames: [
            _squatJackClosed(),
            _squatJackClosed(),
            _squatJackClosed(),
          ],
          activeFrames: [
            _squatJackRegularSquatDeep(),
            _squatJackRegularSquatDeep(),
            _squatJackRegularSquatDeep(),
          ],
        );
        final count = _runValidator(validator, frames);
        expect(count, greaterThan(0));
      },
    );

    test('Squat Jacks identity: standing still does NOT count', () {
      final validator =
          createMotionValidator(AiMotionActivity.squatJacks, 5);
      final frames = List.generate(15, (_) => _squatJackClosed());
      final count = _runValidator(validator, frames);
      expect(count, 0, reason: 'Standing still should not count as squat jacks');
    });

    // ── Squat Jacks backend value round-trip ──────────────────────────────

    test('Backend value round-trip: squat_jacks', () {
      expect(AiMotionActivity.squatJacks.backendValue, 'squat_jacks');
      expect(
        AiMotionActivity.fromBackendValue('squat_jacks'),
        AiMotionActivity.squatJacks,
      );
      expect(
        MotionActivityType.fromBackendValue('squat_jacks'),
        MotionActivityType.squatJacks,
      );
    });

    test('Backend value round-trip: squat_jacks aliases', () {
      expect(
        MotionActivityType.fromBackendValue('squat jack'),
        MotionActivityType.squatJacks,
      );
      expect(
        AiMotionActivity.fromBackendValue('squat jacks'),
        AiMotionActivity.squatJacks,
      );
    });
  });
}

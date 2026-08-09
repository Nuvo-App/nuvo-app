import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/motion_validators.dart';
import 'package:nuvo/features/races/ai/verifier_runtime.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/domain/camera_verification_resolver.dart';
import 'package:nuvo/features/races/domain/motion_activity.dart';
import 'package:nuvo/features/races/domain/motion_activity_catalog.dart';
import 'package:nuvo/features/races/domain/race_draft.dart';

// ── helpers ───────────────────────────────────────────────────────────────────

/// The seven preset movements that must round-trip through every Flutter layer.
const _presetCases = <(String, MotionActivityType, AiMotionActivity)>[
  ('push_ups', MotionActivityType.pushUps, AiMotionActivity.pushUps),
  ('squats', MotionActivityType.squats, AiMotionActivity.squats),
  ('jumping_jacks', MotionActivityType.jumpingJacks, AiMotionActivity.jumpingJacks),
  ('lunges', MotionActivityType.lunges, AiMotionActivity.lunges),
  ('plank_hold', MotionActivityType.plankHold, AiMotionActivity.plankHold),
  ('high_knees', MotionActivityType.highKnees, AiMotionActivity.highKnees),
  ('arm_raises', MotionActivityType.armRaises, AiMotionActivity.armRaises),
];

/// Builds a backend JSON payload for a preset race, mirroring what the
/// Cloudflare Worker returns for a race created with [activityId].
Map<String, dynamic> _raceJson({
  required String activityId,
  String title = 'First to 15 Reps',
  String unit = 'reps',
}) {
  return {
    'id': 'race-1',
    'creatorId': 'user-1',
    'title': title,
    'goalType': 'first_to_goal',
    'targetValue': 15,
    'unit': unit,
    'targetUnit': unit,
    'activityId': activityId,
    'aiActivityType': activityId,
    'metric': unit,
    'format': 'first_to_goal',
    'proofRequirement': 'ai_check',
    'proofMode': 'ai_check',
    'verificationMethod': 'camera_pose',
    'verifierType': 'preset_pose',
    'status': 'active',
    'visibility': 'invite_code',
    'createdAt': '2026-01-01T00:00:00Z',
    'updatedAt': '2026-01-01T00:00:00Z',
  };
}

Race _raceFromBackend(String activityId) => Race.fromJson(
  _raceJson(activityId: activityId),
);

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  const resolver = VerifierRuntimeResolver();

  group('preset activity round-trip', () {
    test('MotionActivityType.fromBackendValue maps every preset id', () {
      for (final (id, expectedType, _) in _presetCases) {
        expect(
          MotionActivityType.fromBackendValue(id),
          expectedType,
          reason: id,
        );
      }
    });

    test('every preset type is in supportedMotionActivityTypes', () {
      for (final (_, type, _) in _presetCases) {
        expect(
          supportedMotionActivityTypes.contains(type),
          isTrue,
          reason: type.name,
        );
      }
    });

    test('RaceDraft.toCreatePayload emits the correct activityId and aiActivityType', () {
      for (final (id, type, _) in _presetCases) {
        final definition = motionActivityForType(type)!;
        final draft = draftForActivity(definition).copyWith(targetValue: 15);
        final payload = draft.toCreatePayload();

        expect(payload['activityId'], id, reason: id);
        expect(payload['aiActivityType'], id, reason: id);
      }
    });

    test('Race.fromJson + resolveCameraVerification marks every preset verifiable', () {
      for (final (id, expectedType, _) in _presetCases) {
        final race = _raceFromBackend(id);
        final eligibility = resolveCameraVerification(race);

        expect(eligibility.isCameraVerifiable, isTrue, reason: id);
        expect(eligibility.movementType, expectedType, reason: id);
        expect(
          eligibility.source,
          CameraVerificationSource.explicitField,
          reason: id,
        );
      }
    });

    test('VerifierRuntimeResolver.resolve returns presetPose for every preset', () {
      for (final (id, _, expectedActivity) in _presetCases) {
        final race = _raceFromBackend(id);
        final eligibility = resolveCameraVerification(race);
        final resolution = resolver.resolve(eligibility: eligibility);

        expect(resolution.type, VerifierType.presetPose, reason: id);
        expect(resolution.canCreateRuntime, isTrue, reason: id);
        expect(resolution.presetMovement?.activity, expectedActivity, reason: id);
      }
    });

    test('createMotionValidator returns the correct validator activity for every preset', () {
      for (final (id, _, expectedActivity) in _presetCases) {
        final validator = createMotionValidator(expectedActivity, 15);

        expect(validator.activity, expectedActivity, reason: id);
        expect(validator.targetValue, 15, reason: id);
      }
    });

    test('runtime movement matches the direct validator for every preset', () {
      for (final (id, _, expectedActivity) in _presetCases) {
        final race = _raceFromBackend(id);
        final eligibility = resolveCameraVerification(race);
        final runtime = resolver
            .resolve(eligibility: eligibility)
            .createRuntime(target: 15);
        final directValidator = createMotionValidator(expectedActivity, 15);

        expect(runtime.type, VerifierType.presetPose, reason: id);
        expect(runtime.movement.activity, directValidator.activity, reason: id);
        expect(runtime.targetValue, directValidator.targetValue, reason: id);
      }
    });
  });

  // ── Focused round-trip: arm_raises ──────────────────────────────────────────
  group('arm_raises full round-trip', () {
    test('resolves through every Flutter layer', () {
      const id = 'arm_raises';
      final race = _raceFromBackend(id);

      // 1. Backend value -> Flutter type.
      expect(
        MotionActivityType.fromBackendValue(id),
        MotionActivityType.armRaises,
      );

      // 2. Supported catalog membership.
      expect(
        supportedMotionActivityTypes.contains(MotionActivityType.armRaises),
        isTrue,
      );

      // 3. Draft payload carries the correct activityId / aiActivityType.
      final definition = motionActivityForType(MotionActivityType.armRaises)!;
      final draft = draftForActivity(definition).copyWith(targetValue: 15);
      final payload = draft.toCreatePayload();
      expect(payload['activityId'], id);
      expect(payload['aiActivityType'], id);

      // 4. Race.fromJson resolves as camera-verifiable with the right movement.
      final eligibility = resolveCameraVerification(race);
      expect(eligibility.isCameraVerifiable, isTrue);
      expect(eligibility.movementType, MotionActivityType.armRaises);
      expect(eligibility.source, CameraVerificationSource.explicitField);

      // 5. VerifierRuntimeResolver returns a presetPose runtime.
      final resolution = resolver.resolve(eligibility: eligibility);
      expect(resolution.type, VerifierType.presetPose);
      expect(resolution.canCreateRuntime, isTrue);
      expect(resolution.presetMovement?.activity, AiMotionActivity.armRaises);

      // 6. createMotionValidator returns the arm raises validator.
      final validator = createMotionValidator(AiMotionActivity.armRaises, 15);
      expect(validator.activity, AiMotionActivity.armRaises);
      expect(validator.targetValue, 15);
    });
  });

  // ── Focused round-trip: high_knees ──────────────────────────────────────────
  group('high_knees full round-trip', () {
    test('resolves through every Flutter layer', () {
      const id = 'high_knees';
      final race = _raceFromBackend(id);

      // 1. Backend value -> Flutter type.
      expect(
        MotionActivityType.fromBackendValue(id),
        MotionActivityType.highKnees,
      );

      // 2. Supported catalog membership.
      expect(
        supportedMotionActivityTypes.contains(MotionActivityType.highKnees),
        isTrue,
      );

      // 3. Draft payload carries the correct activityId / aiActivityType.
      final definition = motionActivityForType(MotionActivityType.highKnees)!;
      final draft = draftForActivity(definition).copyWith(targetValue: 15);
      final payload = draft.toCreatePayload();
      expect(payload['activityId'], id);
      expect(payload['aiActivityType'], id);

      // 4. Race.fromJson resolves as camera-verifiable with the right movement.
      final eligibility = resolveCameraVerification(race);
      expect(eligibility.isCameraVerifiable, isTrue);
      expect(eligibility.movementType, MotionActivityType.highKnees);
      expect(eligibility.source, CameraVerificationSource.explicitField);

      // 5. VerifierRuntimeResolver returns a presetPose runtime.
      final resolution = resolver.resolve(eligibility: eligibility);
      expect(resolution.type, VerifierType.presetPose);
      expect(resolution.canCreateRuntime, isTrue);
      expect(resolution.presetMovement?.activity, AiMotionActivity.highKnees);

      // 6. createMotionValidator returns the high knees validator.
      final validator = createMotionValidator(AiMotionActivity.highKnees, 15);
      expect(validator.activity, AiMotionActivity.highKnees);
      expect(validator.targetValue, 15);
    });
  });
}

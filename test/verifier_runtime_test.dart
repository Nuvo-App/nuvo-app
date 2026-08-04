import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/motion_validators.dart';
import 'package:nuvo/features/races/ai/verifier_runtime.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/domain/camera_verification_resolver.dart';

Race _race({
  String title = 'First to 15 Pushups',
  String? activityId = 'push_ups',
  String? aiActivityType,
  String? unit = 'reps',
  String? targetUnit = 'reps',
}) {
  return Race(
    id: 'race-1',
    creatorId: 'user-1',
    title: title,
    goalType: 'first_to_goal',
    targetValue: 15,
    unit: unit,
    aiActivityType: aiActivityType,
    targetUnit: targetUnit,
    activityId: activityId,
    metric: targetUnit ?? unit,
    format: 'first_to_goal',
    proofRequirement: 'ai_check',
    proofMode: 'ai_check',
    verificationMethod: 'camera_pose',
    status: 'active',
    createdAt: '2026-01-01T00:00:00Z',
    updatedAt: '2026-01-01T00:00:00Z',
  );
}

void main() {
  const resolver = VerifierRuntimeResolver();

  group('VerifierType', () {
    test('recognizes stable verifier identifiers', () {
      expect(VerifierType.fromId('preset_pose'), VerifierType.presetPose);
      expect(
        VerifierType.fromId('custom_pose_sequence'),
        VerifierType.customPoseSequence,
      );
      expect(VerifierType.fromId('unknown'), isNull);
    });
  });

  group('VerifierRuntimeResolver preset routing', () {
    final cases = {
      'push_ups': AiMotionActivity.pushUps,
      'jumping_jacks': AiMotionActivity.jumpingJacks,
      'squats': AiMotionActivity.squats,
      'lunges': AiMotionActivity.lunges,
      'plank_hold': AiMotionActivity.plankHold,
    };

    for (final entry in cases.entries) {
      test('${entry.key} resolves to preset_pose', () {
        final eligibility = resolveCameraVerification(
          _race(activityId: entry.key),
        );
        final resolution = resolver.resolve(eligibility: eligibility);

        expect(resolution.type, VerifierType.presetPose);
        expect(resolution.canCreateRuntime, isTrue);
        expect(resolution.presetMovement?.activity, entry.value);
      });
    }

    test('every active preset reaches the existing validator activity', () {
      for (final entry in cases.entries) {
        final eligibility = resolveCameraVerification(
          _race(activityId: entry.key),
        );
        final runtime = resolver
            .resolve(eligibility: eligibility)
            .createRuntime(target: 15);
        final directValidator = createMotionValidator(entry.value, 15);

        expect(runtime.type, VerifierType.presetPose);
        expect(runtime.movement.activity, directValidator.activity);
        expect(runtime.targetValue, directValidator.targetValue);
      }
    });

    test('legacy aiActivityType routing still resolves to preset_pose', () {
      final eligibility = resolveCameraVerification(
        _race(activityId: null, aiActivityType: 'squats'),
      );
      final resolution = resolver.resolve(eligibility: eligibility);

      expect(resolution.type, VerifierType.presetPose);
      expect(resolution.presetMovement?.activity, AiMotionActivity.squats);
    });

    test('legacy title and unit inference remains limited to presets', () {
      final eligibility = resolveCameraVerification(
        _race(
          title: 'First to 60 Plank Seconds',
          activityId: null,
          aiActivityType: null,
          unit: 'seconds',
          targetUnit: 'seconds',
        ),
      );
      final resolution = resolver.resolve(eligibility: eligibility);

      expect(eligibility.source, CameraVerificationSource.titleInference);
      expect(resolution.type, VerifierType.presetPose);
      expect(resolution.presetMovement?.activity, AiMotionActivity.plankHold);
    });

    test('unsupported activity does not fall back to a preset', () {
      final eligibility = resolveCameraVerification(
        _race(title: 'First to 10 Burpees', activityId: 'burpees'),
      );
      final resolution = resolver.resolve(eligibility: eligibility);

      expect(eligibility.isCameraVerifiable, isFalse);
      expect(resolution.type, VerifierType.presetPose);
      expect(resolution.canCreateRuntime, isFalse);
      expect(resolution.presetMovement, isNull);
    });
  });

  group('custom verifier routing', () {
    test('custom_pose_sequence resolves as known and requires a spec', () {
      final eligibility = resolveCameraVerification(_race());
      final resolution = resolver.resolve(
        eligibility: eligibility,
        explicitVerifierType: 'custom_pose_sequence',
      );

      expect(resolution.type, VerifierType.customPoseSequence);
      expect(resolution.canCreateRuntime, isFalse);
      expect(resolution.reason, 'custom_runtime_requires_spec');
      expect(
        () => resolution.createRuntime(target: 15),
        throwsA(isA<VerifierRuntimeException>()),
      );
    });

    test('unknown verifier type fails clearly', () {
      final eligibility = resolveCameraVerification(_race());

      expect(
        () => resolver.resolve(
          eligibility: eligibility,
          explicitVerifierType: 'made_up_type',
        ),
        throwsA(isA<VerifierRuntimeException>()),
      );
    });
  });

  group('proof result compatibility', () {
    test('preset proof result conversion remains unchanged', () {
      final eligibility = resolveCameraVerification(_race());
      final runtime = resolver
          .resolve(eligibility: eligibility)
          .createRuntime(target: 15);

      final result = runtime.finish().aiMotionResult!;
      final payload = result.toProofPayload(
        clientSubmissionId: 'submission-1',
        metric: 'reps',
      );

      expect(payload['proofType'], 'ai_motion');
      expect(payload['clientSubmissionId'], 'submission-1');
      expect(payload['activityType'], 'push_ups');
      expect(payload['metric'], 'reps');
      expect(payload['value'], result.detectedReps);
      expect(payload['detectedValue'], result.detectedReps);
      expect(payload['targetValue'], result.targetReps);
      expect(payload['confidence'], result.confidence);
      expect(payload['verificationStatus'], result.verificationStatus);
      expect(payload['validatorVersion'], result.validatorVersion);
    });
  });
}

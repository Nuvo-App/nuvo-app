import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/domain/camera_verification_resolver.dart';
import 'package:nuvo/features/races/domain/motion_activity.dart';
import 'package:nuvo/features/races/domain/motion_activity_catalog.dart';

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
  group('camera verification resolver', () {
    test(
      'active preset catalog is exactly the five camera-verified activities',
      () {
        expect(motionActivityDefinitions.map((d) => d.type).toSet(), {
          MotionActivityType.pushUps,
          MotionActivityType.jumpingJacks,
          MotionActivityType.squats,
          MotionActivityType.lunges,
          MotionActivityType.plankHold,
        });
        expect(supportedMotionActivityTypes, {
          MotionActivityType.pushUps,
          MotionActivityType.jumpingJacks,
          MotionActivityType.squats,
          MotionActivityType.lunges,
          MotionActivityType.plankHold,
        });
      },
    );

    test('explicit activity fields resolve every active preset', () {
      final cases = {
        'push_ups': MotionActivityType.pushUps,
        'jumping_jacks': MotionActivityType.jumpingJacks,
        'squats': MotionActivityType.squats,
        'lunges': MotionActivityType.lunges,
        'plank_hold': MotionActivityType.plankHold,
      };

      for (final entry in cases.entries) {
        final eligibility = resolveCameraVerification(
          _race(activityId: entry.key),
        );

        expect(eligibility.isCameraVerifiable, isTrue, reason: entry.key);
        expect(eligibility.movementType, entry.value, reason: entry.key);
        expect(
          eligibility.source,
          CameraVerificationSource.explicitField,
          reason: entry.key,
        );
      }
    });

    test('legacy aiActivityType resolves when activityId is absent', () {
      final eligibility = resolveCameraVerification(
        _race(activityId: null, aiActivityType: 'squats'),
      );

      expect(eligibility.isCameraVerifiable, isTrue);
      expect(eligibility.movementType, MotionActivityType.squats);
      expect(eligibility.source, CameraVerificationSource.explicitField);
    });

    test('legacy aiActivityType aliases resolve when activityId is absent', () {
      final eligibility = resolveCameraVerification(
        _race(activityId: null, aiActivityType: 'pushups'),
      );

      expect(eligibility.isCameraVerifiable, isTrue);
      expect(eligibility.movementType, MotionActivityType.pushUps);
      expect(eligibility.source, CameraVerificationSource.explicitField);
    });

    test(
      'safe title inference resolves a legacy race with no activity field',
      () {
        final eligibility = resolveCameraVerification(
          _race(
            title: 'First to 60 Plank Seconds',
            activityId: null,
            aiActivityType: null,
            unit: 'seconds',
            targetUnit: 'seconds',
          ),
        );

        expect(eligibility.isCameraVerifiable, isTrue);
        expect(eligibility.movementType, MotionActivityType.plankHold);
        expect(eligibility.source, CameraVerificationSource.titleInference);
        expect(
          eligibility.preferredCameraView,
          PreferredCameraView.sideOrDiagonalRequired,
        );
      },
    );

    test('unsupported movements do not fall back to a preset', () {
      final eligibility = resolveCameraVerification(
        _race(title: 'First to 10 Burpees', activityId: 'burpees'),
      );

      expect(eligibility.isCameraVerifiable, isFalse);
      expect(eligibility.movementType, isNull);
      expect(eligibility.source, CameraVerificationSource.unresolved);
      expect(eligibility.reason, 'unsupported_explicit_activity');
    });

    test('explicit unsupported activity blocks legacy title inference', () {
      final eligibility = resolveCameraVerification(
        _race(title: 'First to 10 Pushups', activityId: 'burpees'),
      );

      expect(eligibility.isCameraVerifiable, isFalse);
      expect(eligibility.movementType, isNull);
      expect(eligibility.source, CameraVerificationSource.unresolved);
      expect(eligibility.reason, 'unsupported_explicit_activity');
    });

    test('custom verifier races do not route to preset proof', () {
      final eligibility = resolveCameraVerification(
        const Race(
          id: 'race-custom',
          creatorId: 'user-1',
          title: 'First to 10 Pushups',
          goalType: 'first_to_goal',
          targetValue: 10,
          unit: 'reps',
          metric: 'reps',
          proofRequirement: 'ai_check',
          proofMode: 'ai_check',
          verificationMethod: 'ai',
          verifierType: 'custom_pose_sequence',
          customActivityName: 'Overhead knee touch',
          status: 'active',
          createdAt: '2026-01-01T00:00:00Z',
          updatedAt: '2026-01-01T00:00:00Z',
        ),
      );

      expect(eligibility.isCameraVerifiable, isFalse);
      expect(eligibility.movementType, isNull);
      expect(eligibility.reason, 'custom_verifier_proof_not_enabled');
    });
  });
}

import 'package:flutter/material.dart' show Icons;
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
      'active preset catalog is exactly the twenty-three camera-verified activities',
      () {
        const expected = {
          MotionActivityType.pushUps,
          MotionActivityType.jumpingJacks,
          MotionActivityType.squats,
          MotionActivityType.lunges,
          MotionActivityType.plankHold,
          MotionActivityType.highKnees,
          MotionActivityType.armRaises,
          MotionActivityType.sumoSquats,
          MotionActivityType.sideLunges,
          MotionActivityType.deepSquats,
          MotionActivityType.squatJacks,
          MotionActivityType.jumpSquats,
          MotionActivityType.lungeJumps,
          // preset-motion-expansion
          MotionActivityType.runningInPlace,
          MotionActivityType.treadmillRunning,
          MotionActivityType.walkingInPlace,
          MotionActivityType.marchingInPlace,
          MotionActivityType.buttKicks,
          MotionActivityType.mountainClimbers,
          MotionActivityType.burpees,
          MotionActivityType.stepUps,
          MotionActivityType.calfRaises,
          MotionActivityType.lateralSteps,
          MotionActivityType.basketballShot,
        };
        expect(motionActivityDefinitions.map((d) => d.type).toSet(), expected);
        expect(supportedMotionActivityTypes, expected);
      },
    );

    test('explicit activity fields resolve every active preset', () {
      final cases = {
        'push_ups': MotionActivityType.pushUps,
        'jumping_jacks': MotionActivityType.jumpingJacks,
        'squats': MotionActivityType.squats,
        'lunges': MotionActivityType.lunges,
        'plank_hold': MotionActivityType.plankHold,
        'high_knees': MotionActivityType.highKnees,
        'arm_raises': MotionActivityType.armRaises,
        'jump_squats': MotionActivityType.jumpSquats,
        'lunge_jumps': MotionActivityType.lungeJumps,
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
        _race(title: 'First to 10 Cartwheels', activityId: 'cartwheels'),
      );

      expect(eligibility.isCameraVerifiable, isFalse);
      expect(eligibility.movementType, isNull);
      expect(eligibility.source, CameraVerificationSource.unresolved);
      expect(eligibility.reason, 'unsupported_explicit_activity');
    });

    test('explicit unsupported activity blocks legacy title inference', () {
      final eligibility = resolveCameraVerification(
        _race(title: 'First to 10 Pushups', activityId: 'cartwheels'),
      );

      expect(eligibility.isCameraVerifiable, isFalse);
      expect(eligibility.movementType, isNull);
      expect(eligibility.source, CameraVerificationSource.unresolved);
      expect(eligibility.reason, 'unsupported_explicit_activity');
    });

    test('custom verifier with missing spec is not verifiable', () {
      final eligibility = resolveCameraVerification(
        const Race(
          id: 'race-custom',
          creatorId: 'user-1',
          title: 'First to 10 Overhead knee touch',
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
      expect(eligibility.source, CameraVerificationSource.unresolved);
      expect(eligibility.reason, 'unsupported_custom_verifier_version');
    });

    test('custom verifier with unsupported version is not verifiable', () {
      final eligibility = resolveCameraVerification(
        const Race(
          id: 'race-custom',
          creatorId: 'user-1',
          title: 'First to 10 Overhead knee touch',
          goalType: 'first_to_goal',
          targetValue: 10,
          unit: 'reps',
          metric: 'reps',
          proofRequirement: 'ai_check',
          proofMode: 'ai_check',
          verificationMethod: 'ai',
          verifierType: 'custom_pose_sequence',
          verifierVersion: 99,
          customActivityName: 'Overhead knee touch',
          status: 'active',
          createdAt: '2026-01-01T00:00:00Z',
          updatedAt: '2026-01-01T00:00:00Z',
        ),
      );

      expect(eligibility.isCameraVerifiable, isFalse);
      expect(eligibility.reason, 'unsupported_custom_verifier_version');
    });

    test('custom verifier with invalid stored spec is not verifiable', () {
      final eligibility = resolveCameraVerification(
        const Race(
          id: 'race-custom',
          creatorId: 'user-1',
          title: 'First to 10 Overhead knee touch',
          goalType: 'first_to_goal',
          targetValue: 10,
          unit: 'reps',
          metric: 'reps',
          proofRequirement: 'ai_check',
          proofMode: 'ai_check',
          verificationMethod: 'ai',
          verifierType: 'custom_pose_sequence',
          verifierVersion: 1,
          customActivityName: 'Overhead knee touch',
          verifierInvalidReason: 'Custom verifier spec is invalid.',
          status: 'active',
          createdAt: '2026-01-01T00:00:00Z',
          updatedAt: '2026-01-01T00:00:00Z',
        ),
      );

      expect(eligibility.isCameraVerifiable, isFalse);
      expect(eligibility.reason, 'invalid_custom_verifier_spec');
    });

    test('custom verifier does not fall back to preset activity inference', () {
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
          verifierVersion: 1,
          customActivityName: 'Pushup-like custom',
          status: 'active',
          createdAt: '2026-01-01T00:00:00Z',
          updatedAt: '2026-01-01T00:00:00Z',
        ),
      );

      expect(eligibility.isCameraVerifiable, isFalse);
      expect(eligibility.movementType, isNull);
      expect(eligibility.reason, 'missing_custom_verifier_spec');
    });

    test('high knees title inference resolves with front camera view', () {
      final eligibility = resolveCameraVerification(
        _race(
          title: 'First to 20 High Knees',
          activityId: null,
          aiActivityType: null,
        ),
      );

      expect(eligibility.isCameraVerifiable, isTrue);
      expect(eligibility.movementType, MotionActivityType.highKnees);
      expect(eligibility.source, CameraVerificationSource.titleInference);
      expect(
        eligibility.preferredCameraView,
        PreferredCameraView.frontPreferred,
      );
    });

    test('arm raises title inference resolves with front camera view', () {
      final eligibility = resolveCameraVerification(
        _race(
          title: 'First to 20 Arm Raises',
          activityId: null,
          aiActivityType: null,
        ),
      );

      expect(eligibility.isCameraVerifiable, isTrue);
      expect(eligibility.movementType, MotionActivityType.armRaises);
      expect(eligibility.source, CameraVerificationSource.titleInference);
      expect(
        eligibility.preferredCameraView,
        PreferredCameraView.frontPreferred,
      );
    });

    test('high-knees and arm_raises backend values resolve explicitly', () {
      final hk = resolveCameraVerification(
        _race(activityId: 'high_knees', title: 'High Knees'),
      );
      expect(hk.isCameraVerifiable, isTrue);
      expect(hk.movementType, MotionActivityType.highKnees);
      expect(hk.source, CameraVerificationSource.explicitField);

      final ar = resolveCameraVerification(
        _race(activityId: 'arm_raises', title: 'Arm Raises'),
      );
      expect(ar.isCameraVerifiable, isTrue);
      expect(ar.movementType, MotionActivityType.armRaises);
      expect(ar.source, CameraVerificationSource.explicitField);
    });

    test(
      'test_gap10_registry_motion_offers_server_supported_formats',
      () {
        // A registry-published motion resolved from its release spec must
        // offer the server's real format contract — rep motions get every
        // mode (timed battles included), a hold never a timed rep battle.
        const rule = {
          'point': 'leftWrist',
          'axis': 'y',
          'operator': 'lt',
          'threshold': 0.4,
        };
        Race remote(String engine, String measurement) => Race(
          id: 'race-remote',
          creatorId: 'user-1',
          title: 'Reach Taps',
          goalType: 'first_to_goal',
          unit: 'reps',
          activityId: 'reach_taps',
          metric: 'reps',
          proofRequirement: 'ai_check',
          proofMode: 'ai_check',
          verificationMethod: 'camera_pose',
          verifierType: 'remote_release',
          verifierReleaseId: 'rel-1',
          verifierSpec: {
            'specSchemaVersion': 1,
            'releaseId': 'rel-1',
            'activityId': 'reach_taps',
            'engineType': engine,
            'measurementType': measurement,
            'requiredLandmarks': ['leftWrist'],
            'startRules': [rule],
            'activeRules': [rule],
            'holdRules': [rule],
            'activity': {
              'displayName': 'Reach Taps',
              'measurementType': measurement,
              'defaultTarget': 30,
              'preferredCameraView': 'front',
              'instructions': ['Reach up and tap.'],
            },
          },
          status: 'active',
          createdAt: '2026-01-01T00:00:00Z',
          updatedAt: '2026-01-01T00:00:00Z',
        );

        final rep = resolveCameraVerification(
          remote('state_machine_v1', 'repetitions'),
        );
        expect(rep.isCameraVerifiable, isTrue);
        expect(rep.remoteActivityDefinition?.supportedFormats, [
          RaceFormat.firstToGoal,
          RaceFormat.mostInWindow,
          RaceFormat.bestAttempt,
          RaceFormat.timedAttempt,
        ]);

        final hold = resolveCameraVerification(remote('hold_v1', 'duration'));
        expect(hold.isCameraVerifiable, isTrue);
        expect(
          hold.remoteActivityDefinition?.supportedFormats,
          isNot(contains(RaceFormat.timedAttempt)),
        );
        expect(
          hold.remoteActivityDefinition?.supportedFormats,
          containsAll([
            RaceFormat.firstToGoal,
            RaceFormat.mostInWindow,
            RaceFormat.bestAttempt,
          ]),
        );

        // When the live catalog knows the motion, its published formats pass
        // through verbatim instead of a hardcoded list.
        const catalogDef = MotionActivityDefinition(
          type: MotionActivityType.remote,
          backendId: 'reach_taps',
          title: 'Reach Taps',
          metric: RaceMetric.reps,
          suggestedTargets: [30],
          supportedFormats: [RaceFormat.mostInWindow, RaceFormat.bestAttempt],
          aliases: [],
          proofLabel: 'Reach Taps',
          cameraInstruction: 'Reach.',
          instructions: ['Reach.'],
          icon: Icons.fitness_center_rounded,
          framingLabel: '',
          preferredCameraView: PreferredCameraView.frontPreferred,
          category: MovementCategory.fullBody,
        );
        final viaCatalog = resolveCameraVerification(
          remote('state_machine_v1', 'repetitions'),
          remoteDefinitions: const [catalogDef],
        );
        expect(viaCatalog.remoteActivityDefinition?.supportedFormats, [
          RaceFormat.mostInWindow,
          RaceFormat.bestAttempt,
        ]);
      },
    );
  });
}

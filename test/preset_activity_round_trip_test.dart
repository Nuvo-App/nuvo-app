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

/// The preset movements that must round-trip through every Flutter layer.
const _presetCases = <(String, MotionActivityType, AiMotionActivity)>[
  ('push_ups', MotionActivityType.pushUps, AiMotionActivity.pushUps),
  ('squats', MotionActivityType.squats, AiMotionActivity.squats),
  (
    'jumping_jacks',
    MotionActivityType.jumpingJacks,
    AiMotionActivity.jumpingJacks,
  ),
  ('lunges', MotionActivityType.lunges, AiMotionActivity.lunges),
  ('plank_hold', MotionActivityType.plankHold, AiMotionActivity.plankHold),
  ('high_knees', MotionActivityType.highKnees, AiMotionActivity.highKnees),
  ('arm_raises', MotionActivityType.armRaises, AiMotionActivity.armRaises),
  ('sumo_squats', MotionActivityType.sumoSquats, AiMotionActivity.sumoSquats),
  ('side_lunges', MotionActivityType.sideLunges, AiMotionActivity.sideLunges),
  ('deep_squats', MotionActivityType.deepSquats, AiMotionActivity.deepSquats),
  ('squat_jacks', MotionActivityType.squatJacks, AiMotionActivity.squatJacks),
  ('jump_squats', MotionActivityType.jumpSquats, AiMotionActivity.jumpSquats),
  ('lunge_jumps', MotionActivityType.lungeJumps, AiMotionActivity.lungeJumps),
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

Race _raceFromBackend(String activityId) =>
    Race.fromJson(_raceJson(activityId: activityId));

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

    test(
      'RaceDraft.toCreatePayload emits the correct activityId and aiActivityType',
      () {
        for (final (id, type, _) in _presetCases) {
          final definition = motionActivityForType(type)!;
          final draft = draftForActivity(definition).copyWith(targetValue: 15);
          final payload = draft.toCreatePayload();

          expect(payload['activityId'], id, reason: id);
          expect(payload['aiActivityType'], id, reason: id);
        }
      },
    );

    test(
      'Race.fromJson + resolveCameraVerification marks every preset verifiable',
      () {
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
      },
    );

    test(
      'VerifierRuntimeResolver.resolve returns presetPose for every preset',
      () {
        for (final (id, _, expectedActivity) in _presetCases) {
          final race = _raceFromBackend(id);
          final eligibility = resolveCameraVerification(race);
          final resolution = resolver.resolve(eligibility: eligibility);

          expect(resolution.type, VerifierType.presetPose, reason: id);
          expect(resolution.canCreateRuntime, isTrue, reason: id);
          expect(
            resolution.presetMovement?.activity,
            expectedActivity,
            reason: id,
          );
        }
      },
    );

    test(
      'createMotionValidator returns the correct validator activity for every preset',
      () {
        for (final (id, _, expectedActivity) in _presetCases) {
          final validator = createMotionValidator(expectedActivity, 15);

          expect(validator.activity, expectedActivity, reason: id);
          expect(validator.targetValue, 15, reason: id);
        }
      },
    );

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

  // ── Backend contract: Flutter catalog matches raceActivities.ts ─────────────
  // These values are transcribed from server/worker/src/domain/raceActivities.ts
  // RACE_ACTIVITY_CATALOG. If the backend catalog changes, update these
  // expectations. If the Flutter catalog changes, the test fails and forces
  // a conscious decision about whether the two should diverge.
  group('backend contract', () {
    /// Mirror of the backend RACE_ACTIVITY_CATALOG entries, encoded as
    /// (id, displayName, defaultMetric, cameraOrientation, sessionBehavior).
    /// Source: server/worker/src/domain/raceActivities.ts
    const backendCatalog = <(String, String, String, String, String)>[
      ('push_ups', 'Pushups', 'reps', 'front', 'count_reps'),
      ('jumping_jacks', 'Jumping Jacks', 'reps', 'front', 'count_reps'),
      ('squats', 'Squats', 'reps', 'front', 'count_reps'),
      ('lunges', 'Lunges', 'reps', 'front_or_angle', 'count_reps'),
      ('plank_hold', 'Plank', 'seconds', 'side', 'validated_timer'),
      ('high_knees', 'High Knees', 'reps', 'front', 'count_reps'),
      ('arm_raises', 'Arm Raises', 'reps', 'front', 'count_reps'),
      ('sumo_squats', 'Sumo Squats', 'reps', 'front', 'count_reps'),
      ('side_lunges', 'Side Lunges', 'reps', 'front', 'count_reps'),
      ('deep_squats', 'Deep Squats', 'reps', 'front', 'count_reps'),
      ('squat_jacks', 'Squat Jacks', 'reps', 'front', 'count_reps'),
      ('jump_squats', 'Jump Squats', 'reps', 'front', 'count_reps'),
      ('lunge_jumps', 'Lunge Jumps', 'reps', 'front_or_angle', 'count_reps'),
      ('running_in_place', 'Running in Place', 'reps', 'front', 'count_reps'),
      ('treadmill_running', 'Treadmill Running', 'reps', 'front', 'count_reps'),
      ('walking_in_place', 'Walking in Place', 'reps', 'front', 'count_reps'),
      ('marching_in_place', 'Marching in Place', 'reps', 'front', 'count_reps'),
      ('butt_kicks', 'Butt Kicks', 'reps', 'front', 'count_reps'),
      ('mountain_climbers', 'Mountain Climbers', 'reps', 'front', 'count_reps'),
      ('burpees', 'Burpees', 'reps', 'front', 'count_reps'),
      ('step_ups', 'Step-Ups', 'reps', 'front', 'count_reps'),
      ('calf_raises', 'Calf Raises', 'reps', 'front', 'count_reps'),
      ('lateral_steps', 'Lateral Steps', 'reps', 'front', 'count_reps'),
    ];

    test('Flutter catalog has exactly the same preset IDs as backend', () {
      final flutterIds = motionActivityDefinitions
          .map((d) => d.type.backendValue)
          .toSet();
      final backendIds = backendCatalog.map((e) => e.$1).toSet();
      expect(flutterIds, equals(backendIds));
    });

    test('Flutter catalog titles match backend displayNames', () {
      for (final (id, displayName, _, _, _) in backendCatalog) {
        final flutter = motionActivityForBackendValue(id);
        expect(flutter, isNotNull, reason: 'Missing in Flutter: $id');
        expect(flutter!.title, displayName, reason: id);
      }
    });

    test('Flutter catalog metrics match backend defaultMetrics', () {
      for (final (id, _, metric, _, _) in backendCatalog) {
        final flutter = motionActivityForBackendValue(id)!;
        expect(flutter.metric.backendValue, metric, reason: id);
      }
    });

    test(
      'Flutter catalog preferredCameraView matches backend cameraOrientation',
      () {
        const cameraViewMap = {
          'front': PreferredCameraView.frontPreferred,
          'front_or_angle': PreferredCameraView.frontOrSlightAngle,
          'side': PreferredCameraView.sideOrDiagonalRequired,
        };
        for (final (id, _, _, camera, _) in backendCatalog) {
          final flutter = motionActivityForBackendValue(id)!;
          final expected = cameraViewMap[camera];
          expect(
            expected,
            isNotNull,
            reason: 'Unknown backend camera: $camera',
          );
          expect(flutter.preferredCameraView, expected, reason: id);
        }
      },
    );

    test('Flutter isHold matches backend sessionBehavior', () {
      for (final (id, _, _, _, session) in backendCatalog) {
        final flutter = motionActivityForBackendValue(id)!;
        final backendIsHold = session == 'validated_timer';
        expect(flutter.isHold, backendIsHold, reason: id);
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

  // ── Focused round-trip: deep_squats ─────────────────────────────────────────
  group('deep_squats full round-trip', () {
    test('resolves through every Flutter layer', () {
      const id = 'deep_squats';
      final race = _raceFromBackend(id);

      // 1. Backend value -> Flutter type.
      expect(
        MotionActivityType.fromBackendValue(id),
        MotionActivityType.deepSquats,
      );

      // 2. Supported catalog membership.
      expect(
        supportedMotionActivityTypes.contains(MotionActivityType.deepSquats),
        isTrue,
      );

      // 3. Draft payload carries the correct activityId / aiActivityType.
      final definition = motionActivityForType(MotionActivityType.deepSquats)!;
      final draft = draftForActivity(definition).copyWith(targetValue: 15);
      final payload = draft.toCreatePayload();
      expect(payload['activityId'], id);
      expect(payload['aiActivityType'], id);

      // 4. Race.fromJson resolves as camera-verifiable with the right movement.
      final eligibility = resolveCameraVerification(race);
      expect(eligibility.isCameraVerifiable, isTrue);
      expect(eligibility.movementType, MotionActivityType.deepSquats);
      expect(eligibility.source, CameraVerificationSource.explicitField);

      // 5. VerifierRuntimeResolver returns a presetPose runtime.
      final resolution = resolver.resolve(eligibility: eligibility);
      expect(resolution.type, VerifierType.presetPose);
      expect(resolution.canCreateRuntime, isTrue);
      expect(resolution.presetMovement?.activity, AiMotionActivity.deepSquats);

      // 6. createMotionValidator returns a ConfigurableRepValidator.
      final validator = createMotionValidator(AiMotionActivity.deepSquats, 15);
      expect(validator.activity, AiMotionActivity.deepSquats);
      expect(validator.targetValue, 15);
      expect(validator, isA<ConfigurableRepValidator>());
    });
  });

  // ── Focused round-trip: squat_jacks ─────────────────────────────────────────
  group('squat_jacks full round-trip', () {
    test('resolves through every Flutter layer', () {
      const id = 'squat_jacks';
      final race = _raceFromBackend(id);

      // 1. Backend value -> Flutter type.
      expect(
        MotionActivityType.fromBackendValue(id),
        MotionActivityType.squatJacks,
      );

      // 2. Supported catalog membership.
      expect(
        supportedMotionActivityTypes.contains(MotionActivityType.squatJacks),
        isTrue,
      );

      // 3. Draft payload carries the correct activityId / aiActivityType.
      final definition = motionActivityForType(MotionActivityType.squatJacks)!;
      final draft = draftForActivity(definition).copyWith(targetValue: 15);
      final payload = draft.toCreatePayload();
      expect(payload['activityId'], id);
      expect(payload['aiActivityType'], id);

      // 4. Race.fromJson resolves as camera-verifiable with the right movement.
      final eligibility = resolveCameraVerification(race);
      expect(eligibility.isCameraVerifiable, isTrue);
      expect(eligibility.movementType, MotionActivityType.squatJacks);
      expect(eligibility.source, CameraVerificationSource.explicitField);

      // 5. VerifierRuntimeResolver returns a presetPose runtime.
      final resolution = resolver.resolve(eligibility: eligibility);
      expect(resolution.type, VerifierType.presetPose);
      expect(resolution.canCreateRuntime, isTrue);
      expect(resolution.presetMovement?.activity, AiMotionActivity.squatJacks);

      // 6. createMotionValidator returns a ConfigurableRepValidator.
      final validator = createMotionValidator(AiMotionActivity.squatJacks, 15);
      expect(validator.activity, AiMotionActivity.squatJacks);
      expect(validator.targetValue, 15);
      expect(validator, isA<ConfigurableRepValidator>());
    });
  });
}

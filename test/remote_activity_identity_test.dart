import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/remote_verifier_spec.dart';
import 'package:nuvo/features/races/ai/verifier_runtime.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';
import 'package:nuvo/features/races/data/motion_catalog.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/domain/camera_verification_resolver.dart';
import 'package:nuvo/features/races/domain/motion_activity.dart';

/// Acceptance fixture for the universal competition engine slice.
///
/// `remote_test_motion` exists ONLY here and in server migration 0033 — it is
/// deliberately not a Dart enum member, not in the bundled activity catalog,
/// and not in any switch. The tests below prove the full client path treats
/// an unknown activity ID as data: catalog -> spec -> resolver -> runtime ->
/// proof, with the raw stable ID preserved end to end.
const remoteTestSpec = <String, dynamic>{
  'specSchemaVersion': 1,
  'releaseId': 'remote_test_motion-2026.10.0',
  'activityId': 'remote_test_motion',
  'engineType': 'alternating_rep_v1',
  'measurementType': 'repetitions',
  'requiredCapabilities': [
    'pose_landmarks_v1',
    'derived_features_v1',
    'alternating_rep_v1',
  ],
  'requiredLandmarks': [
    'leftShoulder',
    'rightShoulder',
    'leftWrist',
    'rightWrist',
  ],
  'stableFrames': 2,
  'leftRules': [
    {'point': 'leftWrist', 'axis': 'y', 'operator': 'lt', 'threshold': 0.35},
  ],
  'rightRules': [
    {'point': 'rightWrist', 'axis': 'y', 'operator': 'lt', 'threshold': 0.35},
  ],
  'activity': {
    'displayName': 'Reach Taps',
    'measurementType': 'repetitions',
    'defaultTarget': 10,
    'preferredCameraView': 'front',
    'instructions': [
      'Stand facing the camera with your full body in frame.',
      'Raise one hand overhead, then the other.',
      'Alternate hands cleanly to count each rep.',
    ],
    'unit': 'reach taps',
    'coachingTextActive': 'Reach up with one hand, then the other',
    'coachingTextIncomplete': 'Keep both arms visible',
  },
};

Race _remoteRace({Map<String, dynamic>? spec}) => Race.fromJson({
  'id': 'race-remote-test',
  'creatorId': 'user-1',
  'title': 'First to 10 reach taps',
  'goalType': 'first_to_goal',
  'targetValue': 1,
  'unit': 'reps',
  'activityId': 'remote_test_motion',
  'aiActivityType': 'remote_test_motion',
  'metric': 'reps',
  'proofMode': 'ai_check',
  'verifierType': 'preset_pose',
  'verifierReleaseId': 'remote_test_motion-2026.10.0',
  'verifierSpec': spec ?? remoteTestSpec,
  'status': 'active',
  'createdAt': '2026-10-01T00:00:00Z',
  'updatedAt': '2026-10-01T00:00:00Z',
});

void main() {
  group('remote activity identity', () {
    test('unknown backend IDs never become another motion', () {
      // The old fallback silently mapped unknown IDs to push-ups — the exact
      // hazard this architecture exists to kill.
      expect(
        AiMotionActivity.fromBackendValue('remote_test_motion'),
        AiMotionActivity.remote,
      );
      expect(
        AiMotionActivity.fromBackendValue('some_future_motion'),
        AiMotionActivity.remote,
      );
      // Known IDs still resolve to their compiled identity.
      expect(
        AiMotionActivity.fromBackendValue('push_ups'),
        AiMotionActivity.pushUps,
      );
    });

    test('release spec parses the remote-only activity envelope', () {
      final spec = RemoteVerifierSpec.fromJson(remoteTestSpec);
      expect(spec.activityId, 'remote_test_motion');
      expect(spec.engine, RemoteEngineType.alternatingRepV1);
      expect(spec.measurementType, 'repetitions');
      expect(spec.activity?.displayName, 'Reach Taps');
      expect(spec.activity?.unit, 'reach taps');
      expect(spec.activity?.preferredCameraView, 'front');
      expect(spec.activity?.instructions, hasLength(3));
      expect(spec.package, isNull);
    });

    test('resolver accepts a remote-only activity from its spec metadata', () {
      final eligibility = resolveCameraVerification(_remoteRace());
      expect(eligibility.isCameraVerifiable, isTrue);
      expect(eligibility.isRemoteVerifier, isTrue);
      expect(eligibility.movementType, MotionActivityType.remote);
      expect(eligibility.reason, 'remote_activity_resolved');
      // Display metadata comes from the spec's activity block — never from
      // another motion's compiled identity.
      expect(eligibility.remoteActivityDefinition?.title, 'Reach Taps');
      expect(
        eligibility.remoteActivityDefinition?.activityId,
        'remote_test_motion',
      );
      expect(
        eligibility.remoteActivityDefinition?.backendId,
        'remote_test_motion',
      );
      expect(
        eligibility.preferredCameraView,
        PreferredCameraView.frontPreferred,
      );
      expect(eligibility.instructions, isNotEmpty);
      expect(
        eligibility.movementDefinition?.title,
        'Reach Taps',
      );
    });

    test('resolver uses catalog metadata for a remote-only activity', () {
      final catalogActivity = MotionCatalogActivity.fromJson({
        'id': 'remote_test_motion',
        'displayName': 'Reach Taps',
        'category': 'upper_body',
        'proofLabel': 'reach taps',
        'measurementType': 'repetitions',
        'metric': 'reps',
        'suggestedTargets': [5, 10, 20],
        'supportedFormats': ['first_to_goal'],
        'iconKey': 'sports_gymnastics',
        'availability': 'supported',
        'featured': false,
        'sortPriority': 90,
        'currentReleaseId': 'remote_test_motion-2026.10.0',
        'currentReleaseChecksum': 'sha256:fixture',
        'engineType': 'alternating_rep_v1',
        'requiredCapabilities': [],
        'instructions': ['Registry instruction one.'],
        'cameraOrientation': 'side',
        'aliases': ['overhead reach taps'],
      });
      final definition = catalogActivity.toDefinition(const {});
      expect(definition, isNotNull);
      expect(definition!.backendId, 'remote_test_motion');
      expect(definition.title, 'Reach Taps');
      expect(definition.instructions, ['Registry instruction one.']);
      expect(
        definition.preferredCameraView,
        PreferredCameraView.sideOrDiagonalRequired,
      );
      expect(definition.aliases, contains('overhead reach taps'));

      final eligibility = resolveCameraVerification(
        _remoteRace(),
        remoteDefinitions: [definition],
      );
      expect(eligibility.isCameraVerifiable, isTrue);
      expect(
        eligibility.remoteActivityDefinition?.instructions,
        ['Registry instruction one.'],
      );
      expect(
        eligibility.preferredCameraView,
        PreferredCameraView.sideOrDiagonalRequired,
      );
    });

    test('a remote spec with no usable identity is ineligible, not wrong', () {
      final bareSpec = Map<String, dynamic>.from(remoteTestSpec)
        ..remove('activity');
      final eligibility = resolveCameraVerification(_remoteRace(spec: bareSpec));
      expect(eligibility.isCameraVerifiable, isFalse);
      expect(eligibility.reason, 'remote_activity_metadata_missing');
      // Critical: it must NOT resolve as push-ups or any other compiled type.
      expect(eligibility.movementType, isNull);
    });

    test(
      'runtime runs the fixture end to end and proof preserves the raw ID',
      () {
        final eligibility = resolveCameraVerification(_remoteRace());
        final resolution = const VerifierRuntimeResolver().resolve(
          eligibility: eligibility,
        );
        expect(resolution.canCreateRuntime, isTrue);
        expect(resolution.reason, 'remote_release_runtime_resolved');

        final runtime = resolution.createRuntime(target: 1);
        runtime.start();
        expect(runtime.movement.effectiveActivityId, 'remote_test_motion');
        expect(runtime.movement.title, 'Reach Taps');

        // alternating_rep_v1: left wrist raised for stableFrames, then right.
        for (var i = 0; i < 2; i++) {
          runtime.update(_frame(leftWristUp: true, second: i));
        }
        expect(runtime.currentValue, 1);
        for (var i = 2; i < 4; i++) {
          runtime.update(_frame(rightWristUp: true, second: i));
        }
        expect(runtime.currentValue, 2);

        final result = runtime.finish().aiMotionResult!;
        expect(result.activity, AiMotionActivity.remote);
        expect(result.remoteActivityId, 'remote_test_motion');
        expect(result.remoteActivityLabel, 'Reach Taps');
        expect(result.remoteMeasurementType, 'repetitions');
        expect(result.effectiveActivityId, 'remote_test_motion');
        expect(result.isVerified, isTrue);
        expect(
          result.validatorVersion,
          contains('remote_test_motion-2026.10.0'),
        );

        final payload = result.toProofPayload(
          clientSubmissionId: 'test-submission',
          metric: 'reps',
        );
        // The proof contract carries the server-owned ID verbatim — the
        // backend's loose normalizer accepts it without knowing the motion.
        expect(payload['activityType'], 'remote_test_motion');
      },
    );

    test('isSupportedAiMotionRace is release-backed, not enum-backed', () {
      expect(_remoteRace().isSupportedAiMotionRace, isTrue);
      // A bare unknown activity with no release remains unsupported.
      final bare = Race.fromJson({
        'id': 'race-bare',
        'creatorId': 'user-1',
        'title': 'Race',
        'activityId': 'remote_test_motion',
        'aiActivityType': 'remote_test_motion',
        'proofMode': 'ai_check',
        'status': 'active',
        'createdAt': '',
        'updatedAt': '',
      });
      expect(bare.isSupportedAiMotionRace, isFalse);
    });

    test('restart path: spec re-parses identically from cached JSON', () {
      // The release cache stores the raw spec map; a restarted client parses
      // the same immutable payload into the same identity — nothing about the
      // resolution requires an in-memory catalog snapshot.
      final first = RemoteVerifierSpec.fromJson(remoteTestSpec);
      final second = RemoteVerifierSpec.fromJson(
        Map<String, dynamic>.from(remoteTestSpec),
      );
      expect(second.activityId, first.activityId);
      expect(second.releaseId, first.releaseId);
      expect(second.engine, first.engine);
      final eligibility = resolveCameraVerification(_remoteRace());
      expect(eligibility.isCameraVerifiable, isTrue);
      expect(
        const VerifierRuntimeResolver()
            .resolve(eligibility: eligibility)
            .canCreateRuntime,
        isTrue,
      );
    });
  });
}

NuvoPoseFrame _frame({required int second, bool leftWristUp = false, bool rightWristUp = false}) {
  NuvoPosePoint point(double x, double y) =>
      NuvoPosePoint(x: x, y: y, z: 0, likelihood: 0.95);
  return NuvoPoseFrame(
    points: {
      'leftShoulder': point(0.42, 0.5),
      'rightShoulder': point(0.58, 0.5),
      'leftWrist': point(0.35, leftWristUp ? 0.2 : 0.7),
      'rightWrist': point(0.65, rightWristUp ? 0.2 : 0.7),
      'leftHip': point(0.43, 0.55),
      'rightHip': point(0.57, 0.55),
      'leftKnee': point(0.43, 0.85),
      'rightKnee': point(0.57, 0.85),
    },
    imageWidth: 1,
    imageHeight: 1,
    createdAt: DateTime.utc(2026, 10, 1, 0, 0, second),
  );
}

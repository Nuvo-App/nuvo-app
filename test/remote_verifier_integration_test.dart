import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/verifier_runtime.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/domain/camera_verification_resolver.dart';

void main() {
  const spec = <String, dynamic>{
    'specSchemaVersion': 1,
    'releaseId': 'arm_raises-remote-2026.09.1',
    'activityId': 'arm_raises',
    'engineType': 'state_machine_v1',
    'requiredLandmarks': [
      'leftShoulder',
      'rightShoulder',
      'leftWrist',
      'rightWrist',
    ],
    'stableFrames': 2,
    'startRules': [
      {'point': 'leftWrist', 'axis': 'y', 'operator': 'gte', 'threshold': 0.58},
      {
        'point': 'rightWrist',
        'axis': 'y',
        'operator': 'gte',
        'threshold': 0.58,
      },
    ],
    'activeRules': [
      {'point': 'leftWrist', 'axis': 'y', 'operator': 'lte', 'threshold': 0.42},
      {
        'point': 'rightWrist',
        'axis': 'y',
        'operator': 'lte',
        'threshold': 0.42,
      },
    ],
  };

  test(
    'remote release resolves from a race and completes through the proof runtime',
    () {
      final race = Race.fromJson({
        'id': 'race-remote',
        'creatorId': 'user-1',
        'title': 'First to 1 arm raise',
        'goalType': 'first_to_goal',
        'targetValue': 1,
        'unit': 'reps',
        'activityId': 'arm_raises',
        'aiActivityType': 'arm_raises',
        'proofMode': 'ai_check',
        'verifierType': 'preset_pose',
        'verifierReleaseId': 'arm_raises-remote-2026.09.1',
        'verifierSpec': spec,
        'status': 'active',
        'createdAt': '2026-09-17T00:00:00Z',
        'updatedAt': '2026-09-17T00:00:00Z',
      });

      final eligibility = resolveCameraVerification(race);
      expect(eligibility.isRemoteVerifier, isTrue);
      expect(eligibility.remoteVerifierSpec?.releaseId, spec['releaseId']);

      final resolution = const VerifierRuntimeResolver().resolve(
        eligibility: eligibility,
      );
      expect(resolution.reason, 'remote_release_runtime_resolved');
      final runtime = resolution.createRuntime(target: 1);
      runtime.start();

      for (var i = 0; i < 2; i++) {
        runtime.update(_frame(wristY: 0.7, kneeY: 0.6, second: i));
      }
      for (var i = 2; i < 4; i++) {
        runtime.update(_frame(wristY: 0.3, kneeY: 0.85, second: i));
      }
      for (var i = 4; i < 6; i++) {
        runtime.update(_frame(wristY: 0.7, kneeY: 0.6, second: i));
      }

      expect(runtime.currentValue, 1);
      final result = runtime.finish().aiMotionResult!;
      expect(result.isVerified, isTrue);
      expect(result.activity.backendValue, 'arm_raises');
      expect(result.validatorVersion, contains('arm_raises-remote-2026.09.1'));
    },
  );

  test('a mismatched immutable release is rejected instead of inferred', () {
    final race = Race.fromJson({
      'id': 'race-mismatch',
      'creatorId': 'user-1',
      'title': 'First to 1 arm raise',
      'goalType': 'first_to_goal',
      'activityId': 'arm_raises',
      'aiActivityType': 'arm_raises',
      'proofMode': 'ai_check',
      'verifierReleaseId': 'different-release',
      'verifierSpec': spec,
      'status': 'active',
      'createdAt': '',
      'updatedAt': '',
    });

    final eligibility = resolveCameraVerification(race);
    expect(eligibility.isCameraVerifiable, isFalse);
    expect(eligibility.reason, 'remote_release_identity_mismatch');
  });

  test(
    'the representative remote activity set completes the same app path',
    () {
      for (final entry in [
        (
          activity: 'arm_raises',
          release: 'arm_raises-remote-2026.09.1',
          start: 0.7,
          active: 0.3,
        ),
        (
          activity: 'squats',
          release: 'squats-remote-2026.09.1',
          start: 0.6,
          active: 0.85,
        ),
        (
          activity: 'jumping_jacks',
          release: 'jumping_jacks-remote-2026.09.1',
          start: 0.7,
          active: 0.3,
        ),
      ]) {
        final activitySpec = Map<String, dynamic>.from(spec)
          ..['activityId'] = entry.activity
          ..['releaseId'] = entry.release
          ..['requiredLandmarks'] = entry.activity == 'squats'
              ? ['leftHip', 'rightHip', 'leftKnee', 'rightKnee']
              : spec['requiredLandmarks']
          ..['startRules'] = entry.activity == 'squats'
              ? [
                  {
                    'point': 'leftKnee',
                    'axis': 'y',
                    'operator': 'lte',
                    'threshold': 0.68,
                  },
                  {
                    'point': 'rightKnee',
                    'axis': 'y',
                    'operator': 'lte',
                    'threshold': 0.68,
                  },
                ]
              : spec['startRules']
          ..['activeRules'] = entry.activity == 'squats'
              ? [
                  {
                    'point': 'leftKnee',
                    'axis': 'y',
                    'operator': 'gte',
                    'threshold': 0.78,
                  },
                  {
                    'point': 'rightKnee',
                    'axis': 'y',
                    'operator': 'gte',
                    'threshold': 0.78,
                  },
                ]
              : spec['activeRules'];
        final race = Race.fromJson({
          'id': 'race-${entry.activity}',
          'creatorId': 'user-1',
          'title': 'First to 1 ${entry.activity}',
          'goalType': 'first_to_goal',
          'targetValue': 1,
          'unit': 'reps',
          'activityId': entry.activity,
          'aiActivityType': entry.activity,
          'proofMode': 'ai_check',
          'verifierReleaseId': entry.release,
          'verifierSpec': activitySpec,
          'status': 'active',
          'createdAt': '',
          'updatedAt': '',
        });
        final resolution = const VerifierRuntimeResolver().resolve(
          eligibility: resolveCameraVerification(race),
        );
        final runtime = resolution.createRuntime(target: 1);
        for (var i = 0; i < 2; i++) {
          runtime.update(
            _frame(
              wristY: entry.activity == 'squats' ? 0.7 : entry.start,
              kneeY: entry.start,
              second: i,
            ),
          );
        }
        for (var i = 2; i < 4; i++) {
          runtime.update(
            _frame(
              wristY: entry.activity == 'squats' ? 0.7 : entry.active,
              kneeY: entry.active,
              second: i,
            ),
          );
        }
        for (var i = 4; i < 6; i++) {
          runtime.update(
            _frame(
              wristY: entry.activity == 'squats' ? 0.7 : entry.start,
              kneeY: entry.start,
              second: i,
            ),
          );
        }
        expect(runtime.currentValue, 1, reason: entry.activity);
        expect(
          runtime.finish().aiMotionResult?.isVerified,
          isTrue,
          reason: entry.activity,
        );
      }
    },
  );
}

NuvoPoseFrame _frame({
  required double wristY,
  required double kneeY,
  required int second,
}) {
  NuvoPosePoint point(double x, double y) =>
      NuvoPosePoint(x: x, y: y, z: 0, likelihood: 0.95);
  return NuvoPoseFrame(
    points: {
      'leftShoulder': point(0.42, 0.5),
      'rightShoulder': point(0.58, 0.5),
      'leftWrist': point(0.35, wristY),
      'rightWrist': point(0.65, wristY),
      'leftHip': point(0.43, 0.55),
      'rightHip': point(0.57, 0.55),
      'leftKnee': point(0.43, kneeY),
      'rightKnee': point(0.57, kneeY),
    },
    imageWidth: 1,
    imageHeight: 1,
    createdAt: DateTime.utc(2026, 9, 17, 0, 0, second),
  );
}

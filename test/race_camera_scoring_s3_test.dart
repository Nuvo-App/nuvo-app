import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/motion_validators.dart';
import 'package:nuvo/features/races/ai/remote_verifier_spec.dart';
import 'package:nuvo/features/races/ai/verifier_runtime.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

NuvoPosePoint _pt(double x, double y) =>
    NuvoPosePoint(x: x, y: y, z: 0, likelihood: 1);

// Jumping-jack frames proven against JumpingJacksValidator /
// ConfigurableRepValidator in configurable_rep_validator_test.dart.
NuvoPoseFrame _jjClosed() => NuvoPoseFrame(
  points: {
    'leftWrist': _pt(0.45, 0.35),
    'rightWrist': _pt(0.55, 0.35),
    'leftShoulder': _pt(0.40, 0.30),
    'rightShoulder': _pt(0.60, 0.30),
    'leftHip': _pt(0.42, 0.50),
    'rightHip': _pt(0.58, 0.50),
    'leftAnkle': _pt(0.47, 0.90),
    'rightAnkle': _pt(0.53, 0.90),
  },
  imageWidth: 100,
  imageHeight: 100,
  createdAt: DateTime.now(),
);

NuvoPoseFrame _jjOpen() => NuvoPoseFrame(
  points: {
    'leftWrist': _pt(0.35, 0.20),
    'rightWrist': _pt(0.65, 0.20),
    'leftShoulder': _pt(0.40, 0.30),
    'rightShoulder': _pt(0.60, 0.30),
    'leftHip': _pt(0.42, 0.50),
    'rightHip': _pt(0.58, 0.50),
    'leftAnkle': _pt(0.20, 0.90),
    'rightAnkle': _pt(0.80, 0.90),
  },
  imageWidth: 100,
  imageHeight: 100,
  createdAt: DateTime.now(),
);

void _feedJumpingJackReps(MotionValidator validator, int reps) {
  for (var rep = 0; rep < reps; rep++) {
    for (var i = 0; i < 3; i++) {
      validator.update(_jjClosed());
    }
    for (var i = 0; i < 3; i++) {
      validator.update(_jjOpen());
    }
    for (var i = 0; i < 3; i++) {
      validator.update(_jjClosed());
    }
  }
}

void _feedJumpingJackRepsToRuntime(VerifierRuntime runtime, int reps) {
  for (var rep = 0; rep < reps; rep++) {
    for (var i = 0; i < 3; i++) {
      runtime.update(_jjClosed());
    }
    for (var i = 0; i < 3; i++) {
      runtime.update(_jjOpen());
    }
    for (var i = 0; i < 3; i++) {
      runtime.update(_jjClosed());
    }
  }
}

Map<String, dynamic> _stateMachineSpec() => {
  'specSchemaVersion': 1,
  'releaseId': 'push_ups-remote-1',
  'activityId': 'push_ups',
  'engineType': 'state_machine_v1',
  'requiredLandmarks': ['leftHip', 'rightHip', 'leftWrist', 'rightWrist'],
  'stableFrames': 1,
  'startRules': [
    {'point': 'leftHip', 'axis': 'y', 'operator': 'lte', 'threshold': 0.4},
  ],
  'activeRules': [
    {'point': 'leftHip', 'axis': 'y', 'operator': 'gte', 'threshold': 0.6},
  ],
};

NuvoPoseFrame _remoteFrame({required DateTime at, double hipY = 0.35}) {
  final points = <String, NuvoPosePoint>{};
  for (final point in const [
    'leftHip',
    'rightHip',
    'leftShoulder',
    'rightShoulder',
    'leftWrist',
    'rightWrist',
  ]) {
    points[point] = NuvoPosePoint(
      x: point.startsWith('left') ? 0.35 : 0.65,
      y: point == 'leftHip' || point == 'rightHip' ? hipY : 0.45,
      z: 0,
      likelihood: 0.95,
    );
  }
  return NuvoPoseFrame(
    points: points,
    imageWidth: 100,
    imageHeight: 100,
    createdAt: at,
  );
}

/// One rep for the state_machine_v1 spec: start pose -> active pose ->
/// start pose (stableFrames: 1 flips the machine on each).
VerifierUpdate _feedRemoteRep(RemotePoseVerifierRuntime runtime, DateTime at) {
  runtime.update(_remoteFrame(at: at));
  runtime.update(
    _remoteFrame(at: at.add(const Duration(milliseconds: 30)), hipY: 0.7),
  );
  return runtime.update(
    _remoteFrame(at: at.add(const Duration(milliseconds: 60))),
  );
}

void main() {
  group('gap 2 — no-goal camera sessions', () {
    test('test_gap2_most_in_window_proof_reports_full_count', () {
      // A most-in-window session carries no finish line: the validator must
      // count everything it sees instead of clamping at a fabricated cap.
      final validator = createMotionValidator(
        AiMotionActivity.jumpingJacks,
        null,
      );
      validator.start();

      _feedJumpingJackReps(validator, 7);

      expect(validator.targetValue, isNull);
      expect(validator.currentValue, 7);

      final update = validator.snapshot();
      expect(update.currentValue, 7);
      expect(update.targetValue, isNull);

      final result = validator.finish();
      // Verified on real evidence: a positive count over valid pose frames —
      // never gated on a fake target.
      expect(result.verificationStatus, 'ai_verified');
      expect(result.detectedReps, 7);
      expect(result.targetReps, isNull);

      final payload = result.toProofPayload(
        clientSubmissionId: 'session-1',
        metric: 'reps',
      );
      expect(payload['value'], 7);
      expect(payload['detectedValue'], 7);
      expect(payload['targetValue'], isNull);
    });

    test('test_gap2_best_attempt_score_not_capped_at_default', () {
      // The jumping-jacks definition defaults to 10; a best-attempt session
      // must score every rep it verified, not stop at the default.
      final movement = supportedMovementDefinitions.firstWhere(
        (d) => d.activity == AiMotionActivity.jumpingJacks,
      );
      expect(movement.defaultTarget, 10);

      final runtime = PresetPoseVerifierRuntime(
        movement: movement,
        target: null,
      );
      runtime.start();

      _feedJumpingJackRepsToRuntime(runtime, 12);

      expect(runtime.targetValue, isNull);
      expect(runtime.currentValue, 12);

      final result = runtime.finish().aiMotionResult!;
      expect(result.verificationStatus, 'ai_verified');
      expect(result.detectedReps, 12);
      expect(result.targetReps, isNull);
    });

    test('test_gap2_remote_engine_session_has_no_fake_target', () {
      final runtime = RemotePoseVerifierRuntime(
        spec: RemoteVerifierSpec.fromJson(_stateMachineSpec()),
        movement: supportedMovementDefinitions.first,
        target: null,
      );
      runtime.start();

      final t = DateTime(2026, 9, 17);
      late VerifierUpdate last;
      for (var rep = 0; rep < 4; rep++) {
        last = _feedRemoteRep(runtime, t.add(Duration(milliseconds: rep * 100)));
      }

      // No fake target: count keeps growing, the machine never reports a
      // finish line it does not have.
      expect(runtime.targetValue, isNull);
      expect(runtime.currentValue, 4);
      expect(last.completed, isFalse);
      expect(last.count, 4);
      expect(last.target, isNull);

      final result = runtime.finish().aiMotionResult!;
      expect(result.verificationStatus, 'ai_verified');
      expect(result.detectedReps, 4);
      expect(result.targetReps, isNull);
      final payload = result.toProofPayload(
        clientSubmissionId: 'session-remote',
        metric: 'reps',
      );
      expect(payload['value'], 4);
      expect(payload['targetValue'], isNull);
    });
  });
}

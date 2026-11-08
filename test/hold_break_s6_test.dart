import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/motion_validators.dart';
import 'package:nuvo/features/races/ai/remote_verifier_runtime.dart';
import 'package:nuvo/features/races/ai/remote_verifier_spec.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

/// S6 gap 15 — a hold is ONE unbroken attempt. Continuous time out of
/// position past ~1 s ends it (terminal, no resume) in both the local
/// [HoldTimerStateMachine]/plank validator and the remote `hold_v1`
/// runtime; jitter under a second still survives.
NuvoPosePoint _p(double x, double y) =>
    NuvoPosePoint(x: x, y: y, z: 0, likelihood: 0.95);

NuvoPoseFrame _f(Map<String, NuvoPosePoint> pts, DateTime at) => NuvoPoseFrame(
  points: pts,
  imageWidth: 1000,
  imageHeight: 1000,
  createdAt: at,
);

/// Side-on plank — passes the validator's horizontal-alignment checks.
Map<String, NuvoPosePoint> _plank() => {
  'nose': _p(0.20, 0.52),
  'leftShoulder': _p(0.30, 0.50),
  'rightShoulder': _p(0.30, 0.54),
  'leftElbow': _p(0.30, 0.62),
  'rightElbow': _p(0.30, 0.66),
  'leftWrist': _p(0.30, 0.70),
  'rightWrist': _p(0.30, 0.74),
  'leftHip': _p(0.55, 0.50),
  'rightHip': _p(0.55, 0.54),
  'leftKnee': _p(0.72, 0.50),
  'rightKnee': _p(0.72, 0.54),
  'leftAnkle': _p(0.88, 0.50),
  'rightAnkle': _p(0.88, 0.54),
};

/// Standing upright — fails the plank's horizontal-torso check, i.e. out
/// of position with the body still fully in frame.
Map<String, NuvoPosePoint> _stand() => {
  'nose': _p(0.50, 0.18),
  'leftShoulder': _p(0.38, 0.30),
  'rightShoulder': _p(0.62, 0.30),
  'leftElbow': _p(0.37, 0.42),
  'rightElbow': _p(0.63, 0.42),
  'leftWrist': _p(0.36, 0.55),
  'rightWrist': _p(0.64, 0.55),
  'leftHip': _p(0.41, 0.55),
  'rightHip': _p(0.59, 0.55),
  'leftKnee': _p(0.42, 0.78),
  'rightKnee': _p(0.58, 0.78),
  'leftAnkle': _p(0.43, 0.95),
  'rightAnkle': _p(0.57, 0.95),
};

Map<String, dynamic> _holdSpec() => {
  'specSchemaVersion': 1,
  'releaseId': 'plank_hold-remote-1',
  'activityId': 'plank_hold',
  'engineType': 'hold_v1',
  'requiredLandmarks': ['leftHip', 'rightHip', 'leftShoulder', 'rightShoulder'],
  'stableFrames': 1,
  'measurementType': 'duration',
  'holdRules': [
    {'point': 'leftHip', 'axis': 'y', 'operator': 'lte', 'threshold': 0.5},
  ],
};

NuvoPoseFrame _remoteFrame(DateTime at, {double hipY = 0.35}) {
  final points = <String, NuvoPosePoint>{};
  for (final point in const [
    'leftHip',
    'rightHip',
    'leftShoulder',
    'rightShoulder',
  ]) {
    points[point] = NuvoPosePoint(
      x: point.startsWith('left') ? 0.35 : 0.65,
      y: point.endsWith('Hip') ? hipY : 0.45,
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

void main() {
  group('S6 gap 15 — unbroken hold', () {
    test('test_gap15_plank_break_over_one_second_ends_attempt', () {
      final v = createMotionValidator(AiMotionActivity.plankHold, 20);
      v.start();
      var t = DateTime.utc(2026, 1, 1);
      const step = Duration(milliseconds: 40);

      // Bank ~2 s of clean hold (4 stable frames arm the timer, the rest
      // accumulate).
      for (var i = 0; i < 55; i++) {
        v.update(_f(_plank(), t));
        t = t.add(step);
      }
      final banked = v.currentValue;
      expect(banked, greaterThanOrEqualTo(1));
      expect(v.holdBroken, isFalse);

      // Out of position for more than a second — the attempt ends.
      for (var i = 0; i < 30; i++) {
        v.update(_f(_stand(), t));
        t = t.add(step);
      }
      expect(v.holdBroken, isTrue);
      expect(v.stateLabel, 'hold_broken');
      expect(v.failedRuleReason, 'hold_broken');
      expect(v.currentValue, banked);

      // Back in a clean plank — a broken hold never resumes.
      for (var i = 0; i < 60; i++) {
        v.update(_f(_plank(), t));
        t = t.add(step);
      }
      expect(v.holdBroken, isTrue);
      expect(v.stateLabel, 'hold_broken');
      expect(v.currentValue, banked);
    });

    test('test_gap15_plank_short_jitter_under_one_second_survives', () {
      final v = createMotionValidator(AiMotionActivity.plankHold, 20);
      v.start();
      var t = DateTime.utc(2026, 1, 1);
      const step = Duration(milliseconds: 40);

      for (var i = 0; i < 40; i++) {
        v.update(_f(_plank(), t));
        t = t.add(step);
      }
      final banked = v.currentValue;
      expect(banked, greaterThanOrEqualTo(1));

      // ~0.5 s out of position — jitter, not a break.
      for (var i = 0; i < 12; i++) {
        v.update(_f(_stand(), t));
        t = t.add(step);
      }
      expect(v.holdBroken, isFalse);

      // The same hold keeps banking.
      for (var i = 0; i < 60; i++) {
        v.update(_f(_plank(), t));
        t = t.add(step);
      }
      expect(v.holdBroken, isFalse);
      expect(v.stateLabel, 'hold_valid');
      expect(v.currentValue, greaterThan(banked));
    });

    test('test_gap15_remote_hold_runtime_break_does_not_accumulate', () {
      final runtime = createRemoteVerifierRuntime(
        spec: RemoteVerifierSpec.fromJson(_holdSpec()),
        target: 30,
      );
      runtime.start();
      final t = DateTime(2026, 9, 17);

      // Hold ~2.9 s in position.
      for (var i = 0; i < 30; i++) {
        runtime.update(_remoteFrame(t.add(Duration(milliseconds: 100 * i))));
      }
      final banked = runtime.count;
      expect(banked, greaterThanOrEqualTo(2));

      // Out of position for 0.5 s — under tolerance, the clock keeps
      // running but nothing new banks.
      runtime.update(
        _remoteFrame(t.add(const Duration(seconds: 3)), hipY: 0.9),
      );
      var resume = runtime.update(
        _remoteFrame(t.add(const Duration(milliseconds: 3500))),
      );
      expect(resume.state, RemoteRuntimeState.holdProgress);

      // Out of position again — this time past a second, the attempt is
      // over and banked time stops moving.
      runtime.update(
        _remoteFrame(t.add(const Duration(seconds: 5)), hipY: 0.9),
      );
      final broken = runtime.update(
        _remoteFrame(t.add(const Duration(seconds: 6, milliseconds: 200)), hipY: 0.9),
      );
      expect(broken.state, RemoteRuntimeState.holdBroken);
      final bankedAtBreak = broken.count;
      expect(bankedAtBreak, greaterThanOrEqualTo(banked));

      // Back in position — terminal: still broken, heldMs cannot grow.
      final resumed = runtime.update(
        _remoteFrame(t.add(const Duration(seconds: 8))),
      );
      expect(resumed.state, RemoteRuntimeState.holdBroken);
      expect(resumed.count, bankedAtBreak);
      expect(resumed.elapsedMs, broken.elapsedMs);
    });
  });
}

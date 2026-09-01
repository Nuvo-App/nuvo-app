import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/motion_v2/engine/nuvo_to_h36m.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

import 'fixtures/pose_fixtures.dart';

/// A short "raise arms overhead" motion, built at an arbitrary camera
/// position/distance ([dx], [dy] shift the person in frame; [scale] simulates
/// standing closer (>1) or farther (<1) from the camera — see
/// `test/fixtures/pose_fixtures.dart`'s `_frame`). Real articulation (arms
/// going up) is identical across every transform.
List<NuvoPoseFrame> _armsUpMotion({double dx = 0, double dy = 0, double scale = 1}) {
  final start = DateTime.utc(2026, 1, 1);
  final frames = <NuvoPoseFrame>[];
  var t = 0;
  void add(NuvoPoseFrame Function({double dx, double dy, double scale, DateTime? createdAt}) f) {
    frames.add(f(dx: dx, dy: dy, scale: scale, createdAt: start.add(Duration(milliseconds: t))));
    t += 66;
  }

  for (var i = 0; i < 4; i++) {
    add(neutralStandingPose);
  }
  for (var i = 0; i < 8; i++) {
    add(armsOverheadPose);
  }
  for (var i = 0; i < 4; i++) {
    add(neutralStandingPose);
  }
  return frames;
}

/// A DIFFERENT motion (stays low, hands toward knees) — used as the negative
/// control: normalization must NOT make different articulation look the same.
List<NuvoPoseFrame> _differentMotion() {
  final frames = <NuvoPoseFrame>[];
  for (var i = 0; i < 12; i++) {
    frames.add(handsNearKneesPose());
  }
  return frames;
}

double _maxAbsDiff(List<double> a, List<double> b) {
  var m = 0.0;
  for (var i = 0; i < a.length; i++) {
    final d = (a[i] - b[i]).abs();
    if (d > m) m = d;
  }
  return m;
}

/// Only compares channels with confidence > 0 in BOTH sequences (a joint that
/// dropped out at the image edge after a large shift is a detector artifact,
/// not something the normalizer is responsible for).
double _maxJointDiff(List<double> a, List<double> b, {required int j}) {
  final ax = a[j * 3], ay = a[j * 3 + 1], ac = a[j * 3 + 2];
  final bx = b[j * 3], by = b[j * 3 + 1], bc = b[j * 3 + 2];
  if (ac == 0 || bc == 0) return 0;
  return _maxAbsDiff([ax, ay], [bx, by]);
}

void main() {
  group('Motion V2 input is camera-translation / camera-distance invariant', () {
    test('shifted in-frame (same distance) -> ~identical normalized skeleton', () {
      final base = framesToH36m(_armsUpMotion());
      final shifted = framesToH36m(_armsUpMotion(dx: 0.12, dy: -0.05));

      expect(base.length, shifted.length);
      var worst = 0.0;
      for (var t = 0; t < base.length; t++) {
        for (var j = 0; j < kNumJoints; j++) {
          final d = _maxJointDiff(
            base[t].toList(), shifted[t].toList(), j: j,
          );
          if (d > worst) worst = d;
        }
      }
      // Root-relative + anatomically-scaled coords should be within noise —
      // camera translation must not leak into the taught representation.
      expect(worst, lessThan(0.03), reason: 'max per-joint diff after shift');
    });

    test('closer to camera (scaled up) -> ~identical normalized skeleton', () {
      final base = framesToH36m(_armsUpMotion());
      final closer = framesToH36m(_armsUpMotion(scale: 1.35)); // stepped closer

      var worst = 0.0;
      for (var t = 0; t < base.length; t++) {
        for (var j = 0; j < kNumJoints; j++) {
          final d = _maxJointDiff(base[t].toList(), closer[t].toList(), j: j);
          if (d > worst) worst = d;
        }
      }
      expect(worst, lessThan(0.03), reason: 'max per-joint diff after scale');
    });

    test('farther from camera (scaled down) -> ~identical normalized skeleton', () {
      final base = framesToH36m(_armsUpMotion());
      final farther = framesToH36m(_armsUpMotion(scale: 0.7)); // stepped back

      var worst = 0.0;
      for (var t = 0; t < base.length; t++) {
        for (var j = 0; j < kNumJoints; j++) {
          final d = _maxJointDiff(base[t].toList(), farther[t].toList(), j: j);
          if (d > worst) worst = d;
        }
      }
      expect(worst, lessThan(0.03), reason: 'max per-joint diff after scale');
    });

    test('combined shift + closer + farther all stay close to baseline', () {
      final base = framesToH36m(_armsUpMotion());
      for (final variant in [
        _armsUpMotion(dx: 0.08, dy: 0.06, scale: 1.2),
        _armsUpMotion(dx: -0.1, dy: -0.04, scale: 0.8),
      ]) {
        final h = framesToH36m(variant);
        var worst = 0.0;
        for (var t = 0; t < base.length; t++) {
          for (var j = 0; j < kNumJoints; j++) {
            final d = _maxJointDiff(base[t].toList(), h[t].toList(), j: j);
            if (d > worst) worst = d;
          }
        }
        expect(worst, lessThan(0.04));
      }
    });

    test('a genuinely different motion is NOT normalized into looking the '
        'same (sanity: the invariance above is not vacuous)', () {
      final armsUp = framesToH36m(_armsUpMotion());
      final different = framesToH36m(_differentMotion());
      // Compare the mid-motion frame (arms fully overhead) against the
      // different motion's held pose — real articulation differs a lot.
      final a = armsUp[armsUp.length ~/ 2].toList();
      final b = different[different.length ~/ 2].toList();
      // Wrist joints (13 left, 16 right) should be far apart in normalized
      // space: overhead vs near-knees is a large articulation difference.
      final leftWrist = _maxJointDiff(a, b, j: 13);
      final rightWrist = _maxJointDiff(a, b, j: 16);
      expect(leftWrist + rightWrist, greaterThan(0.2));
    });

    test('diagnostics report within-sequence camera drift; a steady camera '
        'reports none', () {
      // Simulate the person walking sideways / the phone drifting DURING the
      // recording — root position changes frame to frame, not just once.
      final start = DateTime.utc(2026, 1, 1);
      final drifting = <NuvoPoseFrame>[];
      for (var i = 0; i < 12; i++) {
        drifting.add(neutralStandingPose(
          dx: 0.01 * i, // walks right over the clip
          createdAt: start.add(Duration(milliseconds: 66 * i)),
        ));
      }
      final driftDiag = framesToH36mDiag(drifting).diag;
      expect(driftDiag.rootTranslationMagnitude, greaterThan(0));

      final steadyDiag = framesToH36mDiag(_armsUpMotion()).diag;
      expect(steadyDiag.rootTranslationMagnitude, equals(0));
      expect(steadyDiag.anatomicalScale, greaterThan(0));
    });
  });
}

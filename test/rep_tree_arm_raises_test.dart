import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/motion_validators.dart';
import 'package:nuvo/features/races/ai/remote_verifier_runtime.dart';
import 'package:nuvo/features/races/ai/remote_verifier_spec.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

/// arm_raises has bespoke compiled state, so parity is checked on realistic
/// raise/lower cycles (arms start down, a few mid-height transition frames,
/// jitter) rather than on random poses.
NuvoPoseFrame _frame(double wristY, int ms, {double hipY = 0.6}) {
  NuvoPosePoint p(double x, double y) =>
      NuvoPosePoint(x: x, y: y, z: 0, likelihood: 0.95);
  return NuvoPoseFrame(
    points: {
      'leftShoulder': p(0.4, 0.3),
      'rightShoulder': p(0.6, 0.3),
      'leftHip': p(0.42, hipY),
      'rightHip': p(0.58, hipY),
      'leftWrist': p(0.35, wristY),
      'rightWrist': p(0.65, wristY),
      'leftKnee': p(0.42, 0.8),
      'rightKnee': p(0.58, 0.8),
      'leftAnkle': p(0.42, 0.95),
      'rightAnkle': p(0.58, 0.95),
    },
    imageWidth: 640,
    imageHeight: 480,
    createdAt: DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
  );
}

void main() {
  test('arm_raises rep_tree_v1 counts like the compiled validator', () {
    final spec = RemoteVerifierSpec.fromJson(
      jsonDecode(
            File('server/worker/motion_specs/arm_raises.json').readAsStringSync(),
          )
          as Map<String, dynamic>,
    );
    final remote = createRemoteVerifierRuntime(spec: spec, target: 1000);
    final compiled = ArmRaisesValidator(targetValue: 1000)..start();

    // Wrist heights: down (0.45), rising through the dead band, up (0.1).
    const cycle = [0.45, 0.45, 0.45, 0.36, 0.28, 0.1, 0.1, 0.1, 0.28, 0.36];
    var ms = 0;
    for (var rep = 0; rep < 12; rep++) {
      for (final y in cycle) {
        for (var k = 0; k < 3; k++) {
          final f = _frame(y, ms);
          ms += 33;
          final a = remote.update(f).count;
          final b = compiled.update(f).currentValue;
          expect(a, b, reason: 'diverged at $ms ms (rep $rep, y=$y)');
        }
      }
    }
    expect(compiled.update(_frame(0.45, ms + 33)).currentValue, greaterThan(8));
  });
}

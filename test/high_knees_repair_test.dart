import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/motion_validators.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

import 'support/realistic_pose.dart';

/// High Knees, rebuilt around a torso-normalized knee-lift signal instead of
/// the old `knee.y < hip.y + hipWidth * 0.11` gate (which needed the knee at
/// hip level and collapsed with hipWidth on a straight-on camera). Acceptance
/// bar: counts realistic alternating raises through the noisy phone harness at
/// slow / normal / fast tempo and at low FPS, does not count an idle stand or
/// a small nervous bounce, and one physical raise stays exactly one count.

CleanPose _stand({double leftKnee = 0, double rightKnee = 0}) {
  // leftKnee/rightKnee in [0,1] = how far that knee is driven up toward hip
  // height. Resting knee y ≈ 0.80 (0.30 torso below the 0.50 hip); a full
  // drive brings it to hip height (y ≈ 0.50).
  Point<double> knee(double x, double driven) =>
      Point(x, 0.80 - 0.30 * driven.clamp(0.0, 1.0));
  return {
    'leftShoulder': const Point(0.44, 0.20),
    'rightShoulder': const Point(0.56, 0.20),
    'leftHip': const Point(0.45, 0.50),
    'rightHip': const Point(0.55, 0.50),
    'leftKnee': knee(0.45, leftKnee),
    'rightKnee': knee(0.55, rightKnee),
    'leftAnkle': const Point(0.45, 0.95),
    'rightAnkle': const Point(0.55, 0.95),
  };
}

int _run(MotionValidator v, List<NuvoPoseFrame> frames) {
  v.start();
  for (final f in frames) {
    v.update(f);
  }
  return v.currentValue;
}

MotionValidator _hk() => createMotionValidator(AiMotionActivity.highKnees, 60);

List<({CleanPose pose, int holds})> _raises(int count, {required int hold}) => [
      (pose: _stand(), holds: 4),
      for (var i = 0; i < count; i++) ...[
        (pose: _stand(leftKnee: 1), holds: hold),
        (pose: _stand(), holds: hold),
        (pose: _stand(rightKnee: 1), holds: hold),
        (pose: _stand(), holds: hold),
      ],
    ];

void main() {
  group('High Knees — realistic replay (10 alternations → 20 raises)', () {
    for (final (label, noise, hold, lo, hi) in [
      ('normal, phone noise, 3 frames/phase', PoseNoise.phone, 3, 17, 21),
      ('deliberate, 6 frames/phase', PoseNoise.phone, 6, 17, 21),
      ('fast, 2 frames/phase (the floor)', PoseNoise.phone, 2, 15, 21),
      ('harsh phone noise (stretch tier)', PoseNoise.harsh, 3, 8, 21),
    ]) {
      test(label, () {
        final frames = RealisticReplay(noise, seed: 3).stream(_raises(10, hold: hold));
        expect(_run(_hk(), frames), inInclusiveRange(lo, hi), reason: label);
      });
    }

    test('low FPS (10–16) still tracks the raises', () {
      const slowFps = PoseNoise(fpsMin: 10, fpsMax: 16);
      final frames = RealisticReplay(slowFps, seed: 5).stream(_raises(10, hold: 3));
      expect(_run(_hk(), frames), greaterThanOrEqualTo(15));
    });

    test('idle stand (noisy) → 0', () {
      final frames = RealisticReplay(PoseNoise.phone, seed: 1)
          .stream([(pose: _stand(), holds: 90)]);
      expect(_run(_hk(), frames), 0);
    });

    test('small nervous knee bounce (never past halfway) → 0', () {
      final rng = Random(9);
      final frames = <NuvoPoseFrame>[];
      final replay = RealisticReplay(PoseNoise.phone, seed: 2);
      for (var i = 0; i < 40; i++) {
        frames.addAll(replay.stream([
          (pose: _stand(leftKnee: rng.nextDouble() * 0.3), holds: 1),
          (pose: _stand(rightKnee: rng.nextDouble() * 0.3), holds: 1),
        ]));
      }
      expect(_run(_hk(), frames), lessThanOrEqualTo(2));
    });

    test('one physical raise + noisy landing stays exactly 1', () {
      final frames = RealisticReplay(PoseNoise.phone, seed: 4).stream([
        (pose: _stand(), holds: 4),
        (pose: _stand(leftKnee: 1), holds: 4),
        (pose: _stand(leftKnee: 0.55), holds: 1),
        (pose: _stand(leftKnee: 0.9), holds: 1),
        (pose: _stand(leftKnee: 0.5), holds: 1),
        (pose: _stand(), holds: 8),
      ]);
      expect(_run(_hk(), frames), 1);
    });
  });

  test('debug values explain a non-count', () {
    final v = _hk()..start();
    for (final f in RealisticReplay(PoseNoise.phone).stream([(pose: _stand(), holds: 5)])) {
      v.update(f);
    }
    expect(v.debugValues.keys, containsAll(<String>[
      'leftLift',
      'rightLift',
      'lastTorsoHeight',
      'leftReady',
      'rightReady',
      'count',
    ]));
  });
}

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/motion_validators.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

import 'support/realistic_pose.dart';

/// Mountain Climbers, rebuilt around body-relative torso orientation +
/// alternating knee drive. Acceptance bar: counts realistic reps through the
/// noisy phone harness at slow / normal / fast tempo and at low FPS, and does
/// NOT count standing High Knees or an idle plank.

// ── Clean poses (a 3/4-camera plank — the common phone setup) ────────────────
CleanPose _plank({double leftKnee = 0, double rightKnee = 0}) {
  // leftKnee/rightKnee in [0,1] = how far that knee is driven toward the chest.
  Point<double> knee(double base, double driven) {
    // extended: near (0.63, 0.61); fully driven: near (0.47, 0.49)
    final t = driven.clamp(0.0, 1.0);
    return Point(0.63 - 0.16 * t + base, 0.61 - 0.12 * t);
  }

  return {
    'leftShoulder': const Point(0.36, 0.44),
    'rightShoulder': const Point(0.46, 0.47),
    'leftHip': const Point(0.52, 0.51),
    'rightHip': const Point(0.60, 0.54),
    'leftKnee': knee(-0.02, leftKnee),
    'rightKnee': knee(0.04, rightKnee),
    'leftAnkle': const Point(0.72, 0.66),
    'rightAnkle': const Point(0.78, 0.69),
    'leftWrist': const Point(0.24, 0.42),
    'rightWrist': const Point(0.30, 0.45),
  };
}

CleanPose _standTall({double leftKnee = 0, double rightKnee = 0}) {
  // Standing high knees — torso is vertical, so this must NOT count as MC.
  return {
    'leftShoulder': const Point(0.42, 0.20),
    'rightShoulder': const Point(0.58, 0.20),
    'leftHip': const Point(0.44, 0.50),
    'rightHip': const Point(0.56, 0.50),
    'leftKnee': Point(0.44, 0.72 - 0.22 * leftKnee.clamp(0.0, 1.0)),
    'rightKnee': Point(0.56, 0.72 - 0.22 * rightKnee.clamp(0.0, 1.0)),
    'leftAnkle': const Point(0.44, 0.93),
    'rightAnkle': const Point(0.56, 0.93),
    'leftWrist': const Point(0.40, 0.50),
    'rightWrist': const Point(0.60, 0.50),
  };
}

int _run(MotionValidator v, List<NuvoPoseFrame> frames) {
  v.start();
  for (final f in frames) {
    v.update(f);
  }
  return v.currentValue;
}

MotionValidator _mc() => createMotionValidator(AiMotionActivity.mountainClimbers, 40);

List<({CleanPose pose, int holds})> _mcCycles(int cycles, {required int hold}) => [
      (pose: _plank(), holds: 4),
      for (var i = 0; i < cycles; i++) ...[
        (pose: _plank(leftKnee: 1), holds: hold),
        (pose: _plank(), holds: 1),
        (pose: _plank(rightKnee: 1), holds: hold),
        (pose: _plank(), holds: 1),
      ],
    ];

void main() {
  group('Mountain Climbers — realistic replay (10 cycles → ~19 alternations)', () {
    for (final (label, noise, hold, lo, hi) in [
      ('normal, phone noise, 3 frames/phase', PoseNoise.phone, 3, 14, 20),
      ('deliberate, 6 frames/phase', PoseNoise.phone, 6, 14, 20),
      ('fast, 2 frames/phase (the floor)', PoseNoise.phone, 2, 12, 20),
      ('harsh phone noise (stretch tier)', PoseNoise.harsh, 3, 5, 20),
    ]) {
      test(label, () {
        final frames = RealisticReplay(noise, seed: 3).stream(_mcCycles(10, hold: hold));
        final n = _run(_mc(), frames);
        expect(n, inInclusiveRange(lo, hi), reason: label);
      });
    }

    test('low FPS (10–16) still tracks the cadence', () {
      const slowFps = PoseNoise(fpsMin: 10, fpsMax: 16);
      final frames = RealisticReplay(slowFps, seed: 5).stream(_mcCycles(10, hold: 3));
      expect(_run(_mc(), frames), greaterThanOrEqualTo(12));
    });

    test('idle plank (noisy) → 0', () {
      final frames = RealisticReplay(PoseNoise.phone, seed: 1)
          .stream([(pose: _plank(), holds: 90)]);
      expect(_run(_mc(), frames), 0);
    });

    test('plank + random knee jitter (no real drive) → 0', () {
      final rng = Random(9);
      final frames = <NuvoPoseFrame>[];
      final replay = RealisticReplay(PoseNoise.phone, seed: 2);
      for (var i = 0; i < 30; i++) {
        frames.addAll(replay.stream([
          (pose: _plank(leftKnee: rng.nextDouble() * 0.25), holds: 1),
          (pose: _plank(rightKnee: rng.nextDouble() * 0.25), holds: 1),
        ]));
      }
      expect(_run(_mc(), frames), lessThanOrEqualTo(2));
    });

    test('one-sided knee drive (left only) → 0', () {
      final frames = RealisticReplay(PoseNoise.phone, seed: 4).stream([
        (pose: _plank(), holds: 4),
        for (var i = 0; i < 12; i++) ...[
          (pose: _plank(leftKnee: 1), holds: 3),
          (pose: _plank(), holds: 2),
        ],
      ]);
      expect(_run(_mc(), frames), 0);
    });
  });

  group('Mountain Climbers — cross-motion negatives', () {
    test('standing High Knees does NOT count as Mountain Climbers', () {
      final frames = RealisticReplay(PoseNoise.phone, seed: 7).stream([
        (pose: _standTall(), holds: 4),
        for (var i = 0; i < 12; i++) ...[
          (pose: _standTall(leftKnee: 1), holds: 3),
          (pose: _standTall(), holds: 1),
          (pose: _standTall(rightKnee: 1), holds: 3),
          (pose: _standTall(), holds: 1),
        ],
      ]);
      expect(_run(_mc(), frames), lessThanOrEqualTo(1));
    });

    test('High Knees verifier still counts High Knees (not broken by MC work)', () {
      final v = createMotionValidator(AiMotionActivity.highKnees, 30);
      final frames = RealisticReplay(PoseNoise.phone, seed: 8).stream([
        (pose: _standTall(), holds: 4),
        for (var i = 0; i < 10; i++) ...[
          (pose: _standTall(leftKnee: 1), holds: 3),
          (pose: _standTall(), holds: 1),
          (pose: _standTall(rightKnee: 1), holds: 3),
          (pose: _standTall(), holds: 1),
        ],
      ]);
      expect(_run(v, frames), greaterThan(0));
    });
  });

  test('debug values explain a non-count', () {
    final v = _mc()..start();
    for (final f in RealisticReplay(PoseNoise.phone).stream([(pose: _plank(), holds: 5)])) {
      v.update(f);
    }
    final d = v.debugValues;
    expect(d.keys, containsAll(<String>[
      'torsoAngle',
      'plankContext',
      'leftKneeDrive',
      'rightKneeDrive',
      'currentSide',
      'count',
      'repIntervalFrames',
    ]));
    expect(d['plankContext'], 1, reason: 'a plank pose should read as plank context');
  });
}

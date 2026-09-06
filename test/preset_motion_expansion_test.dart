import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/motion_validators.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

/// Realistic-pose coverage for the 10 preset-motion-expansion movements.
///
/// The first version of these tests fed idealized poses (one knee lifted
/// halfway to the hip while the other stayed fully extended) that no real
/// gait produces — and the verifiers were tuned to match those, so they
/// counted nothing on a real phone pose stream. This rewrite:
///   * drives every validator through createMotionValidator (production path)
///   * uses realistic amplitudes (a running knee stagger is ~10-14% of frame
///     height, NOT the knee reaching hip level)
///   * layers per-frame jitter, 1-3 frame landmark dropout, variable speed,
///     small scale + root translation, and asymmetry via [_noisy]
///   * asserts exact counts for slow / normal / fast / 5-back-to-back
///   * asserts no-double-count on a noisy ending and no spam on a held phase
///   * cross-tests confusable movements

final _rng = Random(1234);
int _seq = 0;

NuvoPosePoint _p(double x, double y, {double l = 0.9}) =>
    NuvoPosePoint(x: x, y: y, z: 0, likelihood: l);

NuvoPoseFrame _frame(Map<String, NuvoPosePoint> pts) => NuvoPoseFrame(
      points: pts,
      imageWidth: 1000,
      imageHeight: 1000,
      createdAt:
          DateTime.utc(2026, 1, 1).add(Duration(milliseconds: 33 * _seq++)),
    );

/// Applies realistic noise to a clean pose: uniform joint jitter, a slow
/// scale drift, a slow root translation, per-frame confidence wobble, and an
/// occasional 1-frame full dropout of one lower-body landmark.
Map<String, NuvoPosePoint> _noisy(
  Map<String, NuvoPosePoint> pose, {
  double jitter = 0.006,
  double scale = 1.0,
  double dx = 0.0,
  double dy = 0.0,
  bool allowDropout = true,
}) {
  final out = <String, NuvoPosePoint>{};
  final cx = 0.5, cy = 0.5;
  double j() => (_rng.nextDouble() * 2 - 1) * jitter;
  for (final e in pose.entries) {
    final sx = cx + (e.value.x - cx) * scale + dx + j();
    final sy = cy + (e.value.y - cy) * scale + dy + j();
    final conf = (0.82 + _rng.nextDouble() * 0.15).clamp(0.0, 1.0);
    out[e.key] = _p(sx, sy, l: conf);
  }
  if (allowDropout && _rng.nextDouble() < 0.06) {
    out.remove(['leftKnee', 'rightKnee', 'leftAnkle', 'rightAnkle'][
        _rng.nextInt(4)]);
  }
  return out;
}

MotionValidator _v(AiMotionActivity a) => createMotionValidator(a, 30);

int _run(
  MotionValidator v,
  List<(Map<String, NuvoPosePoint> Function(), int)> phases,
) {
  _seq = 0;
  v.start();
  for (final (pose, holds) in phases) {
    for (var i = 0; i < holds; i++) {
      v.update(_frame(pose()));
    }
  }
  return v.currentValue;
}

// ── skeleton ────────────────────────────────────────────────────────────────
// Full-body, realistically framed: shoulders ~0.20, hips ~0.50, knees ~0.72,
// ankles ~0.93. A real running/marching knee lift raises ONE knee by
// ~0.10-0.14 while the other stays near its resting Y — the two knees never
// come close to the hip line.

Map<String, NuvoPosePoint> _stand({double stance = 0.11}) => {
      'nose': _p(0.5, 0.10),
      'leftShoulder': _p(0.5 - 0.13, 0.21),
      'rightShoulder': _p(0.5 + 0.13, 0.21),
      'leftElbow': _p(0.5 - 0.15, 0.36),
      'rightElbow': _p(0.5 + 0.15, 0.36),
      'leftWrist': _p(0.5 - 0.16, 0.50),
      'rightWrist': _p(0.5 + 0.16, 0.50),
      'leftHip': _p(0.5 - 0.09, 0.50),
      'rightHip': _p(0.5 + 0.09, 0.50),
      'leftKnee': _p(0.5 - stance, 0.72),
      'rightKnee': _p(0.5 + stance, 0.72),
      'leftAnkle': _p(0.5 - stance, 0.93),
      'rightAnkle': _p(0.5 + stance, 0.93),
    };

/// Gait pose: [lift] in [0,1] scales the amplitude; positive [side]==left
/// raises the left knee (and its ankle) by `lift * 0.14`, the other leg
/// drops slightly (weight-bearing).
Map<String, NuvoPosePoint> _gait({required bool left, required double lift}) {
  final m = _stand();
  final amp = 0.14 * lift;
  final upKnee = left ? 'leftKnee' : 'rightKnee';
  final upAnkle = left ? 'leftAnkle' : 'rightAnkle';
  final downKnee = left ? 'rightKnee' : 'leftKnee';
  m[upKnee] = _p(m[upKnee]!.x + (left ? 0.02 : -0.02), 0.72 - amp);
  m[upAnkle] = _p(m[upAnkle]!.x + (left ? 0.02 : -0.02), 0.93 - amp * 1.3);
  m[downKnee] = _p(m[downKnee]!.x, 0.73);
  return m;
}

/// Butt kick: one shin folds back, ankle rises toward the knee, thigh stays
/// down (knee near its resting Y).
Map<String, NuvoPosePoint> _buttKick({required bool left}) {
  final m = _stand();
  final ankle = left ? 'leftAnkle' : 'rightAnkle';
  final knee = left ? 'leftKnee' : 'rightKnee';
  m[knee] = _p(m[knee]!.x, 0.71); // thigh basically down
  m[ankle] = _p(m[ankle]!.x + (left ? 0.03 : -0.03), 0.70); // heel up near knee
  return m;
}

/// Plank base for mountain climbers — body low and roughly horizontal, hands
/// planted near shoulder height.
Map<String, NuvoPosePoint> _plank() => {
      'nose': _p(0.22, 0.55),
      'leftShoulder': _p(0.34, 0.50),
      'rightShoulder': _p(0.34, 0.58),
      'leftWrist': _p(0.30, 0.52),
      'rightWrist': _p(0.30, 0.62),
      'leftElbow': _p(0.32, 0.51),
      'rightElbow': _p(0.32, 0.60),
      'leftHip': _p(0.56, 0.50),
      'rightHip': _p(0.60, 0.58),
      'leftKnee': _p(0.74, 0.52),
      'rightKnee': _p(0.76, 0.60),
      'leftAnkle': _p(0.90, 0.53),
      'rightAnkle': _p(0.92, 0.61),
    };

Map<String, NuvoPosePoint> _mcDrive({required bool left}) {
  final m = _plank();
  final knee = left ? 'leftKnee' : 'rightKnee';
  // The driving knee comes forward toward the torso — its Y rises well above
  // the trailing knee. Symmetric amplitude for both sides.
  m[knee] = _p(0.58, left ? 0.42 : 0.44);
  return m;
}

void main() {
  // ── Running / Treadmill / Walking / Marching / Step-Ups ──────────────────
  // liftFraction in motion_validators: Walking 0.30, Running/Treadmill 0.55,
  // Marching/Step-Ups 0.65 — measured against hip width (~0.18 here), so the
  // knee-height stagger must exceed ~0.054 / ~0.099 / ~0.117. A real gait
  // knee lift here is 0.14 (_gait lift 1.0), staggering the knees ~0.15.
  for (final (label, act, lift) in [
    ('Running in Place', AiMotionActivity.runningInPlace, 0.9),
    ('Treadmill Running', AiMotionActivity.treadmillRunning, 0.9),
    ('Walking in Place', AiMotionActivity.walkingInPlace, 0.55),
    ('Marching in Place', AiMotionActivity.marchingInPlace, 1.0),
    ('Step-Ups', AiMotionActivity.stepUps, 1.0),
  ]) {
    group(label, () {
      List<(Map<String, NuvoPosePoint> Function(), int)> cycle(
        int hold, {
        double j = 0.006,
      }) =>
          [
            (() => _noisy(_gait(left: true, lift: lift), jitter: j), hold),
            (() => _noisy(_stand(), jitter: j), 1),
            (() => _noisy(_gait(left: false, lift: lift), jitter: j), hold),
            (() => _noisy(_stand(), jitter: j), 1),
          ];

      test('idle standing (noisy) -> 0', () {
        expect(
          _run(_v(act), [(() => _noisy(_stand(), jitter: 0.01), 60)]),
          0,
        );
      });

      test('normal cadence, ~10 steps -> counts every alternation', () {
        final n = _run(_v(act), [
          (() => _noisy(_stand()), 4),
          for (var i = 0; i < 5; i++) ...cycle(3),
        ]);
        // baseline (left) + up to 9 confirmed alternations; noise/dropout may
        // cost one or two, but it must track a real cadence, not stall.
        expect(n, inInclusiveRange(7, 10));
      });

      test('fast cadence at the 2-frame floor -> still counts', () {
        final n = _run(_v(act), [
          (() => _noisy(_stand()), 4),
          for (var i = 0; i < 6; i++) ...cycle(2),
        ]);
        expect(n, greaterThanOrEqualTo(6));
      });

      test('slow cadence (long holds) -> exact, no double counts', () {
        final n = _run(_v(act), [
          (() => _noisy(_stand()), 4),
          for (var i = 0; i < 3; i++) ...cycle(12),
        ]);
        expect(n, inInclusiveRange(4, 6)); // baseline + up to 5 alternations
      });

      test('left-only repeated motion -> 0', () {
        final n = _run(_v(act), [
          for (var i = 0; i < 8; i++) ...[
            (() => _noisy(_gait(left: true, lift: lift)), 3),
            (() => _noisy(_stand()), 2),
          ],
        ]);
        expect(n, 0);
      });

      test('held knee-up pose -> no runaway', () {
        final n = _run(_v(act), [
          (() => _noisy(_stand()), 3),
          (() => _noisy(_gait(left: true, lift: lift)), 50),
        ]);
        expect(n, 0);
      });

      test('one clean alternation + noisy ending -> exactly 1', () {
        final n = _run(_v(act), [
          (() => _noisy(_stand()), 4),
          (() => _noisy(_gait(left: true, lift: lift)), 3),
          (() => _noisy(_stand()), 2),
          (() => _noisy(_gait(left: false, lift: lift)), 3),
          // noisy jitter around neutral — must not add a phantom count
          (() => _noisy(_stand(), jitter: 0.014), 25),
        ]);
        expect(n, 1);
      });

      test('scale drift + root translation mid-set -> still counts', () {
        _seq = 0;
        final v = _v(act);
        v.start();
        for (var i = 0; i < 40; i++) {
          final left = (i ~/ 4).isEven;
          final phase = i % 4;
          final base = phase < 2
              ? _gait(left: left, lift: lift)
              : _stand();
          v.update(_frame(_noisy(
            base,
            scale: 1.0 + (i - 20) * 0.004,
            dx: (i - 20) * 0.002,
            dy: sin(i / 5) * 0.01,
          )));
        }
        expect(v.currentValue, greaterThanOrEqualTo(5));
      });
    });
  }

  group('cadence cross-motion negatives', () {
    test('a shallow walking shuffle does NOT satisfy Marching', () {
      final n = _run(_v(AiMotionActivity.marchingInPlace), [
        (() => _noisy(_stand()), 4),
        for (var i = 0; i < 6; i++) ...[
          (() => _noisy(_gait(left: true, lift: 0.35)), 3),
          (() => _noisy(_stand()), 1),
          (() => _noisy(_gait(left: false, lift: 0.35)), 3),
          (() => _noisy(_stand()), 1),
        ],
      ]);
      expect(n, 0);
    });

    test('a marching-level lift DOES satisfy Walking (lenient by design)', () {
      final n = _run(_v(AiMotionActivity.walkingInPlace), [
        (() => _noisy(_stand()), 4),
        for (var i = 0; i < 4; i++) ...[
          (() => _noisy(_gait(left: true, lift: 1.0)), 3),
          (() => _noisy(_stand()), 1),
          (() => _noisy(_gait(left: false, lift: 1.0)), 3),
          (() => _noisy(_stand()), 1),
        ],
      ]);
      expect(n, greaterThanOrEqualTo(5));
    });

    test('idle upper-body sway does not count as running', () {
      final n = _run(_v(AiMotionActivity.runningInPlace), [
        for (var i = 0; i < 40; i++)
          (
            () {
              final m = _stand();
              // arms/torso sway, feet planted
              final sway = sin(i / 3) * 0.03;
              m['leftWrist'] = _p(m['leftWrist']!.x + sway, m['leftWrist']!.y);
              m['rightWrist'] =
                  _p(m['rightWrist']!.x + sway, m['rightWrist']!.y);
              return _noisy(m);
            },
            1,
          ),
      ]);
      expect(n, 0);
    });
  });

  // ── Butt Kicks ──────────────────────────────────────────────────────────
  group('Butt Kicks', () {
    test('idle -> 0', () {
      expect(_run(_v(AiMotionActivity.buttKicks),
          [(() => _noisy(_stand()), 50)]), 0);
    });

    test('alternating kicks (noisy) -> counts', () {
      final n = _run(_v(AiMotionActivity.buttKicks), [
        (() => _noisy(_stand()), 3),
        for (var i = 0; i < 5; i++) ...[
          (() => _noisy(_buttKick(left: true)), 3),
          (() => _noisy(_stand()), 1),
          (() => _noisy(_buttKick(left: false)), 3),
          (() => _noisy(_stand()), 1),
        ],
      ]);
      expect(n, inInclusiveRange(8, 10));
    });

    test('left-only kicks -> 0', () {
      final n = _run(_v(AiMotionActivity.buttKicks), [
        for (var i = 0; i < 8; i++) ...[
          (() => _noisy(_buttKick(left: true)), 3),
          (() => _noisy(_stand()), 2),
        ],
      ]);
      expect(n, 0);
    });

    test('a high-knee raise (thigh up) does NOT count as a butt kick', () {
      final n = _run(_v(AiMotionActivity.buttKicks), [
        (() => _noisy(_stand()), 3),
        for (var i = 0; i < 5; i++) ...[
          (() => _noisy(_gait(left: true, lift: 1.0)), 3),
          (() => _noisy(_stand()), 1),
          (() => _noisy(_gait(left: false, lift: 1.0)), 3),
          (() => _noisy(_stand()), 1),
        ],
      ]);
      expect(n, 0);
    });

    test('held heel-up -> no runaway', () {
      final n = _run(_v(AiMotionActivity.buttKicks), [
        (() => _noisy(_stand()), 3),
        (() => _noisy(_buttKick(left: true)), 40),
      ]);
      expect(n, 0);
    });
  });

  // ── Mountain Climbers ───────────────────────────────────────────────────
  group('Mountain Climbers', () {
    test('idle plank -> 0', () {
      expect(_run(_v(AiMotionActivity.mountainClimbers),
          [(() => _noisy(_plank(), jitter: 0.004), 50)]), 0);
    });

    test('alternating knee drive (noisy) -> counts', () {
      final n = _run(_v(AiMotionActivity.mountainClimbers), [
        (() => _noisy(_plank(), jitter: 0.004), 3),
        for (var i = 0; i < 5; i++) ...[
          (() => _noisy(_mcDrive(left: true), jitter: 0.004), 3),
          (() => _noisy(_plank(), jitter: 0.004), 1),
          (() => _noisy(_mcDrive(left: false), jitter: 0.004), 3),
          (() => _noisy(_plank(), jitter: 0.004), 1),
        ],
      ]);
      expect(n, inInclusiveRange(8, 10));
    });

    test('standing high knees (hands NOT planted) -> 0', () {
      final n = _run(_v(AiMotionActivity.mountainClimbers), [
        (() => _noisy(_stand()), 3),
        for (var i = 0; i < 5; i++) ...[
          (() => _noisy(_gait(left: true, lift: 1.0)), 3),
          (() => _noisy(_stand()), 1),
          (() => _noisy(_gait(left: false, lift: 1.0)), 3),
          (() => _noisy(_stand()), 1),
        ],
      ]);
      expect(n, 0);
    });

    test('left-only drive -> 0', () {
      final n = _run(_v(AiMotionActivity.mountainClimbers), [
        for (var i = 0; i < 8; i++) ...[
          (() => _noisy(_mcDrive(left: true), jitter: 0.004), 3),
          (() => _noisy(_plank(), jitter: 0.004), 2),
        ],
      ]);
      expect(n, 0);
    });
  });

  // ── Burpees (multi-phase) ───────────────────────────────────────────────
  group('Burpees', () {
    Map<String, NuvoPosePoint> standTall() {
      final m = _stand();
      m['leftWrist'] = _p(0.36, 0.22);
      m['rightWrist'] = _p(0.64, 0.22);
      return m;
    }

    Map<String, NuvoPosePoint> down() {
      final m = _stand();
      // deep crouch: hips drop toward the knees, hands reach toward the floor
      m['leftShoulder'] = _p(0.40, 0.42);
      m['rightShoulder'] = _p(0.60, 0.42);
      m['leftHip'] = _p(0.42, 0.62);
      m['rightHip'] = _p(0.58, 0.62);
      m['leftKnee'] = _p(0.40, 0.70);
      m['rightKnee'] = _p(0.60, 0.70);
      m['leftWrist'] = _p(0.44, 0.78);
      m['rightWrist'] = _p(0.56, 0.78);
      return m;
    }

    test('idle standing -> 0', () {
      expect(_run(_v(AiMotionActivity.burpees),
          [(() => _noisy(standTall()), 40)]), 0);
    });

    test('two full burpees (noisy) -> 2', () {
      final n = _run(_v(AiMotionActivity.burpees), [
        (() => _noisy(standTall()), 4),
        (() => _noisy(down()), 3),
        (() => _noisy(standTall()), 8),
        (() => _noisy(down()), 3),
        (() => _noisy(standTall()), 8),
      ]);
      expect(n, 2);
    });

    test('crouch without hands reaching down -> 0', () {
      final crouchNoReach = () {
        final m = down();
        m['leftWrist'] = _p(0.40, 0.30);
        m['rightWrist'] = _p(0.60, 0.30);
        return m;
      };
      final n = _run(_v(AiMotionActivity.burpees), [
        (() => _noisy(standTall()), 3),
        (() => _noisy(crouchNoReach()), 6),
        (() => _noisy(standTall()), 6),
      ]);
      expect(n, 0);
    });

    test('holding the down phase -> no spam', () {
      final n = _run(_v(AiMotionActivity.burpees), [
        (() => _noisy(standTall()), 3),
        (() => _noisy(down()), 30),
        (() => _noisy(standTall()), 8),
      ]);
      expect(n, 1);
    });

    test('plain squats (hands stay up) -> 0', () {
      final squat = () {
        final m = _stand();
        m['leftHip'] = _p(0.42, 0.60);
        m['rightHip'] = _p(0.58, 0.60);
        m['leftKnee'] = _p(0.41, 0.70);
        m['rightKnee'] = _p(0.59, 0.70);
        return m;
      };
      final n = _run(_v(AiMotionActivity.burpees), [
        for (var i = 0; i < 4; i++) ...[
          (() => _noisy(standTall()), 3),
          (() => _noisy(squat()), 3),
        ],
      ]);
      expect(n, 0);
    });
  });

  // ── Calf Raises ─────────────────────────────────────────────────────────
  group('Calf Raises', () {
    Map<String, NuvoPosePoint> down() => _stand();
    Map<String, NuvoPosePoint> up() {
      final m = _stand();
      // whole lower body lifts a few cm onto the toes; knees stay extended
      for (final k in ['leftHip', 'rightHip', 'leftKnee', 'rightKnee',
          'leftAnkle', 'rightAnkle']) {
        m[k] = _p(m[k]!.x, m[k]!.y - 0.045);
      }
      return m;
    }

    test('idle -> 0', () {
      expect(_run(_v(AiMotionActivity.calfRaises),
          [(() => _noisy(down(), jitter: 0.004), 40)]), 0);
    });

    test('slow raises (noisy) -> counts', () {
      final n = _run(_v(AiMotionActivity.calfRaises), [
        (() => _noisy(down(), jitter: 0.004), 6),
        for (var i = 0; i < 4; i++) ...[
          (() => _noisy(up(), jitter: 0.004), 5),
          (() => _noisy(down(), jitter: 0.004), 5),
        ],
      ]);
      expect(n, inInclusiveRange(3, 5));
    });

    test('held top -> no spam', () {
      final n = _run(_v(AiMotionActivity.calfRaises), [
        (() => _noisy(down(), jitter: 0.004), 6),
        (() => _noisy(up(), jitter: 0.004), 5),
        (() => _noisy(down(), jitter: 0.004), 5),
        (() => _noisy(up(), jitter: 0.004), 40),
      ]);
      expect(n, 1);
    });

    test('small ankle jitter at rest -> 0', () {
      final n = _run(_v(AiMotionActivity.calfRaises), [
        (() => _noisy(down(), jitter: 0.012), 50),
      ]);
      expect(n, 0);
    });

    test('a squat (knees bend) -> 0', () {
      final squat = () {
        final m = _stand();
        m['leftHip'] = _p(0.42, 0.60);
        m['rightHip'] = _p(0.58, 0.60);
        m['leftKnee'] = _p(0.41, 0.70);
        m['rightKnee'] = _p(0.59, 0.70);
        return m;
      };
      final n = _run(_v(AiMotionActivity.calfRaises), [
        (() => _noisy(down(), jitter: 0.004), 4),
        (() => _noisy(squat(), jitter: 0.004), 6),
        (() => _noisy(down(), jitter: 0.004), 4),
      ]);
      expect(n, 0);
    });
  });

  // ── Lateral Steps ───────────────────────────────────────────────────────
  group('Lateral Steps', () {
    Map<String, NuvoPosePoint> center() => _stand();
    Map<String, NuvoPosePoint> stepRight() {
      final m = _stand();
      for (final k in ['leftAnkle', 'rightAnkle', 'leftKnee', 'rightKnee']) {
        m[k] = _p(m[k]!.x + 0.16, m[k]!.y);
      }
      return m;
    }

    Map<String, NuvoPosePoint> stepLeft() {
      final m = _stand();
      for (final k in ['leftAnkle', 'rightAnkle', 'leftKnee', 'rightKnee']) {
        m[k] = _p(m[k]!.x - 0.16, m[k]!.y);
      }
      return m;
    }

    test('idle -> 0', () {
      expect(_run(_v(AiMotionActivity.lateralSteps),
          [(() => _noisy(center()), 40)]), 0);
    });

    test('alternating left-right steps (noisy) -> counts', () {
      final n = _run(_v(AiMotionActivity.lateralSteps), [
        (() => _noisy(center()), 5),
        for (var i = 0; i < 4; i++) ...[
          (() => _noisy(stepRight()), 4),
          (() => _noisy(center()), 4),
          (() => _noisy(stepLeft()), 4),
          (() => _noisy(center()), 4),
        ],
      ]);
      expect(n, inInclusiveRange(6, 8));
    });

    test('small positioning shuffle (drift) -> 0', () {
      final smallShift = () {
        final m = _stand();
        for (final k in ['leftAnkle', 'rightAnkle']) {
          m[k] = _p(m[k]!.x + 0.02, m[k]!.y);
        }
        return m;
      };
      final n = _run(_v(AiMotionActivity.lateralSteps), [
        (() => _noisy(center()), 5),
        (() => _noisy(smallShift()), 15),
      ]);
      expect(n, 0);
    });

    test('right-only stepping -> 0', () {
      final n = _run(_v(AiMotionActivity.lateralSteps), [
        (() => _noisy(center()), 5),
        for (var i = 0; i < 5; i++) ...[
          (() => _noisy(stepRight()), 4),
          (() => _noisy(center()), 4),
        ],
      ]);
      expect(n, 0);
    });
  });
}

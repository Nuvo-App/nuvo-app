import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/motion_validators.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

/// Coverage for the 10 preset-motion-expansion movements: idle / valid /
/// partial / hold / wrong-motion, plus the alternating-cadence matrix
/// (left-only, right-only, alternation, rapid alternation, same-side jitter)
/// the PRD calls for. Every validator here is exercised through the real
/// production factory (createMotionValidator), never a bespoke test-only path.

int _seq = 0;
NuvoPosePoint _p(double x, double y, {double l = 0.94}) =>
    NuvoPosePoint(x: x, y: y, z: 0, likelihood: l);
NuvoPoseFrame _f(Map<String, NuvoPosePoint> pts) => NuvoPoseFrame(
      points: pts,
      imageWidth: 1000,
      imageHeight: 1000,
      createdAt:
          DateTime.utc(2026, 1, 1).add(Duration(milliseconds: 40 * _seq++)),
    );

int _drive(
  MotionValidator v,
  List<(Map<String, NuvoPosePoint> Function(), int)> phases,
) {
  _seq = 0;
  v.start();
  for (final (pose, holds) in phases) {
    for (var i = 0; i < holds; i++) {
      v.update(_f(pose()));
    }
  }
  return v.currentValue;
}

// ── shared skeleton ──────────────────────────────────────────────────────────

Map<String, NuvoPosePoint> _standing({
  double shY = 0.28,
  double hipY = 0.52,
  double kneeY = 0.75,
  double stance = 0.16,
  double wristY = 0.55,
}) =>
    {
      'leftShoulder': _p(0.50 - 0.12, shY),
      'rightShoulder': _p(0.50 + 0.12, shY),
      'leftWrist': _p(0.50 - 0.14, wristY),
      'rightWrist': _p(0.50 + 0.14, wristY),
      'leftHip': _p(0.50 - 0.08, hipY),
      'rightHip': _p(0.50 + 0.08, hipY),
      'leftKnee': _p(0.50 - stance, kneeY),
      'rightKnee': _p(0.50 + stance, kneeY),
      'leftAnkle': _p(0.50 - stance, 0.95),
      'rightAnkle': _p(0.50 + stance, 0.95),
    };

/// A leg-lift tier expressed as a fraction of hip width below hip level —
/// matches the raiseFraction gates in motion_validators.dart:
/// marching/stepUps=0.05, running/treadmill/mountainClimbers=0.20, walking=0.35.
Map<String, NuvoPosePoint> _lift({required bool left, required double tierFraction}) {
  final base = _standing();
  const hipWidth = 0.16; // matches _standing()'s stance*2
  final hipY = 0.52;
  final gap = hipWidth * tierFraction;
  final key = left ? 'leftKnee' : 'rightKnee';
  base[key] = _p(base[key]!.x, hipY + gap * 0.4); // comfortably inside the tier
  return base;
}

const _deepTier = 0.05; // marching / step-ups
const _mediumTier = 0.20; // running / treadmill / mountain climbers
const _shallowTier = 0.35; // walking

MotionValidator _v(AiMotionActivity a) => createMotionValidator(a, 20);

void main() {
  // ── Running / Treadmill / Walking / Marching / Step-Ups — shared matrix ──
  for (final (label, activity, tier) in [
    ('Running in Place', AiMotionActivity.runningInPlace, _mediumTier),
    ('Treadmill Running', AiMotionActivity.treadmillRunning, _mediumTier),
    ('Walking in Place', AiMotionActivity.walkingInPlace, _shallowTier),
    ('Marching in Place', AiMotionActivity.marchingInPlace, _deepTier),
    ('Step-Ups', AiMotionActivity.stepUps, _deepTier),
  ]) {
    group(label, () {
      test('idle standing -> 0', () {
        expect(_drive(_v(activity), [(() => _standing(), 20)]), 0);
      });

      test('valid alternation -> counts, second alternation -> next count',
          () {
        final v = _v(activity);
        final n = _drive(v, [
          (() => _standing(), 4),
          (() => _lift(left: true, tierFraction: tier), 3),
          (() => _standing(), 3),
          (() => _lift(left: false, tierFraction: tier), 3),
          (() => _standing(), 3),
          (() => _lift(left: true, tierFraction: tier), 3),
        ]);
        expect(n, 2); // L(baseline,0) -> R(+1) -> L(+1) = 2
      });

      test('left-only repeated motion never counts', () {
        final v = _v(activity);
        final n = _drive(v, [
          for (var i = 0; i < 6; i++)
            (() => _lift(left: true, tierFraction: tier), 3),
        ]);
        expect(n, 0);
      });

      test('right-only repeated motion never counts', () {
        final v = _v(activity);
        final n = _drive(v, [
          for (var i = 0; i < 6; i++)
            (() => _lift(left: false, tierFraction: tier), 3),
        ]);
        expect(n, 0);
      });

      test('rapid alternation at the frame floor -> exactly 5', () {
        final v = _v(activity);
        final phases = <(Map<String, NuvoPosePoint> Function(), int)>[
          (() => _lift(left: true, tierFraction: tier), 2),
        ];
        for (var i = 0; i < 5; i++) {
          phases.add((() => _lift(left: i.isEven ? false : true, tierFraction: tier), 2));
        }
        expect(_drive(v, phases), 5);
      });

      test('same-side jitter (never 2 consecutive) confirms nothing', () {
        final v = _v(activity);
        final phases = <(Map<String, NuvoPosePoint> Function(), int)>[
          for (var i = 0; i < 10; i++)
            (() => _lift(left: i.isEven, tierFraction: tier), 1),
        ];
        expect(_drive(v, phases), 0);
      });

      test('held raised pose -> no runaway count', () {
        final v = _v(activity);
        final n = _drive(v, [
          (() => _standing(), 3),
          (() => _lift(left: true, tierFraction: tier), 40),
        ]);
        expect(n, 0); // baseline only — never switches side
      });
    });
  }

  // Cross-tier negatives — documents the real, measured ambiguity rather than
  // claiming perfect separation (per PRD).
  group('cadence cross-tier negatives', () {
    test('a shallow walking-level lift does NOT satisfy Marching', () {
      final v = _v(AiMotionActivity.marchingInPlace);
      final n = _drive(v, [
        (() => _standing(), 3),
        (() => _lift(left: true, tierFraction: _shallowTier), 4),
        (() => _standing(), 3),
        (() => _lift(left: false, tierFraction: _shallowTier), 4),
      ]);
      expect(n, 0);
    });

    test(
      'KNOWN LIMITATION: a deliberate marching-level lift DOES satisfy '
      'Walking in Place (walking\'s threshold is intentionally lenient) — '
      'documented, not hidden',
      () {
        final v = _v(AiMotionActivity.walkingInPlace);
        final n = _drive(v, [
          (() => _standing(), 3),
          (() => _lift(left: true, tierFraction: _deepTier), 3),
          (() => _standing(), 3),
          (() => _lift(left: false, tierFraction: _deepTier), 3),
        ]);
        expect(n, 1);
      },
    );

    test(
      'KNOWN LIMITATION: Step-Ups and Marching in Place use the same knee-lift '
      'signal — a Step-Up performance registers on the Marching validator '
      'and vice versa. Pose-only tracking cannot see the physical step.',
      () {
        final steps = _v(AiMotionActivity.stepUps);
        final marching = _v(AiMotionActivity.marchingInPlace);
        final phases = [
          (() => _standing(), 3),
          (() => _lift(left: true, tierFraction: _deepTier), 3),
          (() => _standing(), 3),
          (() => _lift(left: false, tierFraction: _deepTier), 3),
        ];
        expect(_drive(steps, phases), 1);
        expect(_drive(marching, phases), 1);
      },
    );

    test('High Knees vs Marching: High Knees also registers a marching-level lift '
        '(both use hip-relative knee elevation) — not a false positive, the two '
        'movements are genuinely similar from a front camera', () {
      final hk = _v(AiMotionActivity.highKnees);
      final n = _drive(hk, [
        (() => _standing(), 3),
        (() => _lift(left: true, tierFraction: _deepTier), 3),
        (() => _standing(), 6),
        (() => _lift(left: false, tierFraction: _deepTier), 3),
        (() => _standing(), 6),
      ]);
      expect(n, greaterThan(0));
    });
  });

  // ── Butt Kicks ─────────────────────────────────────────────────────────────
  group('Butt Kicks', () {
    Map<String, NuvoPosePoint> kick({required bool left}) {
      final base = _standing();
      // Sharp knee flexion, heel toward glute — thigh stays down.
      final hipKey = left ? 'leftHip' : 'rightHip';
      final kneeKey = left ? 'leftKnee' : 'rightKnee';
      final ankleKey = left ? 'leftAnkle' : 'rightAnkle';
      final hip = base[hipKey]!;
      base[kneeKey] = _p(hip.x + (left ? 0.01 : -0.01), hip.y + 0.23);
      base[ankleKey] = _p(hip.x + (left ? 0.08 : -0.08), hip.y + 0.08);
      return base;
    }

    test('idle standing -> 0', () {
      expect(_drive(_v(AiMotionActivity.buttKicks), [(() => _standing(), 20)]), 0);
    });

    test('valid alternating kicks -> counts', () {
      final v = _v(AiMotionActivity.buttKicks);
      final n = _drive(v, [
        (() => _standing(), 3),
        (() => kick(left: true), 3),
        (() => _standing(), 3),
        (() => kick(left: false), 3),
        (() => _standing(), 3),
      ]);
      expect(n, 1); // left(baseline,0) -> right(+1)
    });

    test('left-only repeated kicks never count', () {
      final v = _v(AiMotionActivity.buttKicks);
      final n = _drive(v, [
        for (var i = 0; i < 6; i++) (() => kick(left: true), 3),
      ]);
      expect(n, 0);
    });

    test('a knee raise (thigh up, not a heel kick) does not count as a butt kick',
        () {
      final v = _v(AiMotionActivity.buttKicks);
      final n = _drive(v, [
        (() => _standing(), 3),
        (() => _lift(left: true, tierFraction: _deepTier), 4),
        (() => _standing(), 3),
        (() => _lift(left: false, tierFraction: _deepTier), 4),
      ]);
      expect(n, 0);
    });

    test('tiny knee flexion / standing jitter does not count', () {
      final v = _v(AiMotionActivity.buttKicks);
      final n = _drive(v, [
        for (var i = 0; i < 20; i++) (() => _standing(kneeY: 0.75 + (i.isEven ? 0.005 : -0.005)), 1),
      ]);
      expect(n, 0);
    });
  });

  // ── Mountain Climbers ────────────────────────────────────────────────────────
  group('Mountain Climbers', () {
    Map<String, NuvoPosePoint> plankBase() {
      final base = _standing(shY: 0.30);
      base['leftWrist'] = _p(0.38, 0.30);
      base['rightWrist'] = _p(0.62, 0.30);
      return base;
    }

    Map<String, NuvoPosePoint> drive({required bool left}) {
      final base = plankBase();
      final key = left ? 'leftKnee' : 'rightKnee';
      final hipY = base[left ? 'leftHip' : 'rightHip']!.y;
      base[key] = _p(base[key]!.x, hipY + 0.02);
      return base;
    }

    test('idle plank base -> 0', () {
      expect(_drive(_v(AiMotionActivity.mountainClimbers), [(() => plankBase(), 20)]), 0);
    });

    test('valid alternating knee drive -> counts', () {
      final v = _v(AiMotionActivity.mountainClimbers);
      final n = _drive(v, [
        (() => plankBase(), 3),
        (() => drive(left: true), 3),
        (() => plankBase(), 3),
        (() => drive(left: false), 3),
        (() => plankBase(), 3),
      ]);
      expect(n, 1); // left(baseline,0) -> right(+1)
    });

    test('standing High Knees (hands NOT planted) is rejected — the hands-down '
        'context gate is the discriminator', () {
      final v = _v(AiMotionActivity.mountainClimbers);
      final n = _drive(v, [
        (() => _standing(), 3), // wrists at hip level, not planted down
        (() => _lift(left: true, tierFraction: _mediumTier), 4),
        (() => _standing(), 3),
        (() => _lift(left: false, tierFraction: _mediumTier), 4),
      ]);
      expect(n, 0);
    });

    test('left-only repeated drive never counts', () {
      final v = _v(AiMotionActivity.mountainClimbers);
      final n = _drive(v, [
        for (var i = 0; i < 6; i++) (() => drive(left: true), 3),
      ]);
      expect(n, 0);
    });
  });

  // ── Lateral Steps ─────────────────────────────────────────────────────────────
  group('Lateral Steps', () {
    Map<String, NuvoPosePoint> neutral() => _standing();
    Map<String, NuvoPosePoint> stepRight() {
      final base = _standing();
      base['leftAnkle'] = _p(0.66, 0.95);
      base['rightAnkle'] = _p(0.82, 0.95);
      return base;
    }

    Map<String, NuvoPosePoint> stepLeft() {
      final base = _standing();
      base['leftAnkle'] = _p(0.18, 0.95);
      base['rightAnkle'] = _p(0.34, 0.95);
      return base;
    }

    Map<String, NuvoPosePoint> smallCorrection() {
      final base = _standing();
      base['leftAnkle'] = _p(0.335, 0.95);
      base['rightAnkle'] = _p(0.495, 0.95);
      return base;
    }

    test('idle centered -> 0', () {
      expect(_drive(_v(AiMotionActivity.lateralSteps), [(() => neutral(), 20)]), 0);
    });

    test('valid left-right stepping -> counts', () {
      final v = _v(AiMotionActivity.lateralSteps);
      final n = _drive(v, [
        (() => neutral(), 5),
        (() => stepRight(), 4),
        (() => neutral(), 5),
        (() => stepLeft(), 4),
        (() => neutral(), 5),
      ]);
      expect(n, 1); // right(baseline,0) -> left(+1)
    });

    test('a small positioning correction (drift, not a step) does not count', () {
      final v = _v(AiMotionActivity.lateralSteps);
      final n = _drive(v, [
        (() => neutral(), 5),
        (() => smallCorrection(), 10),
      ]);
      expect(n, 0);
    });

    test('right-only repeated stepping never counts', () {
      final v = _v(AiMotionActivity.lateralSteps);
      final n = _drive(v, [
        (() => neutral(), 5),
        for (var i = 0; i < 5; i++) ...[
          (() => stepRight(), 4),
          (() => neutral(), 4),
        ],
      ]);
      expect(n, 0);
    });
  });

  // ── Burpees (multi-phase) ─────────────────────────────────────────────────────
  group('Burpees', () {
    Map<String, NuvoPosePoint> standing() => _standing(wristY: 0.30);
    Map<String, NuvoPosePoint> down() => _standing(
          shY: 0.40,
          hipY: 0.62,
          kneeY: 0.69,
          wristY: 0.62,
        );

    test('idle standing -> 0', () {
      expect(_drive(_v(AiMotionActivity.burpees), [(() => standing(), 20)]), 0);
    });

    test('one valid burpee -> 1, second -> 2', () {
      final v = _v(AiMotionActivity.burpees);
      // Each lap needs: 2 standing frames to (re)confirm STANDING, 2 down
      // frames to confirm DOWN, 2 more standing frames to confirm
      // STANDING_FINISH (completes the rep), then cooldownFrames=2 to drain,
      // then 1 more standing frame to satisfy resetCondition and return to
      // idle before the next lap's STANDING can start reconfirming.
      final n = _drive(v, [
        (() => standing(), 3),
        (() => down(), 3),
        (() => standing(), 8),
        (() => down(), 3),
        (() => standing(), 8),
      ]);
      expect(n, 2);
    });

    test('partial (crouch, no hands down) does not complete a rep', () {
      final v = _v(AiMotionActivity.burpees);
      final crouchNoHands =
          () => _standing(shY: 0.40, hipY: 0.62, kneeY: 0.69, wristY: 0.30);
      final n = _drive(v, [
        (() => standing(), 3),
        (crouchNoHands, 6),
        (() => standing(), 3),
      ]);
      expect(n, 0);
    });

    test('holding the down phase does not spam completions', () {
      final v = _v(AiMotionActivity.burpees);
      final n = _drive(v, [
        (() => standing(), 3),
        (() => down(), 30),
        (() => standing(), 4),
      ]);
      expect(n, 1);
    });

    test('squats (never reach down/hands-down) do not count as burpees', () {
      final v = _v(AiMotionActivity.burpees);
      final squatDeep = () => _standing(shY: 0.34, hipY: 0.60, kneeY: 0.69);
      final n = _drive(v, [
        for (var i = 0; i < 4; i++) ...[
          (() => standing(), 3),
          (squatDeep, 3),
        ],
      ]);
      expect(n, 0);
    });
  });

  // ── Calf Raises ────────────────────────────────────────────────────────────
  group('Calf Raises', () {
    Map<String, NuvoPosePoint> down() => _standing();
    Map<String, NuvoPosePoint> raised() {
      final base = _standing();
      base['leftAnkle'] = _p(base['leftAnkle']!.x, 0.885);
      base['rightAnkle'] = _p(base['rightAnkle']!.x, 0.885);
      return base;
    }

    test('idle -> 0', () {
      expect(_drive(_v(AiMotionActivity.calfRaises), [(() => down(), 20)]), 0);
    });

    test('one valid raise -> 1, second -> 2', () {
      final v = _v(AiMotionActivity.calfRaises);
      final n = _drive(v, [
        (() => down(), 6),
        (() => raised(), 4),
        (() => down(), 5),
        (() => raised(), 4),
        (() => down(), 5),
      ]);
      expect(n, 2);
    });

    test('holding the top does not spam counts', () {
      final v = _v(AiMotionActivity.calfRaises);
      // A count only fires on the full down->up->down cycle (matches
      // RepCounterStateMachine everywhere else) — one full cycle, then a
      // long hold at the top must not add a second count.
      final n = _drive(v, [
        (() => down(), 6),
        (() => raised(), 4),
        (() => down(), 5),
        (() => raised(), 40),
      ]);
      expect(n, 1);
    });

    test('jitter protection: small ankle-Y noise near baseline does not count', () {
      final v = _v(AiMotionActivity.calfRaises);
      final n = _drive(v, [
        for (var i = 0; i < 20; i++)
          (
            () {
              final base = _standing();
              final j = i.isEven ? 0.003 : -0.003;
              base['leftAnkle'] = _p(base['leftAnkle']!.x, 0.95 + j);
              base['rightAnkle'] = _p(base['rightAnkle']!.x, 0.95 + j);
              return base;
            },
            1,
          ),
      ]);
      expect(n, 0);
    });

    test('a squat (knees bend) does not count as a calf raise', () {
      final v = _v(AiMotionActivity.calfRaises);
      final squatDeep = () => _standing(shY: 0.34, hipY: 0.60, kneeY: 0.69);
      final n = _drive(v, [
        (() => down(), 4),
        (squatDeep, 6),
        (() => down(), 4),
      ]);
      expect(n, 0);
    });
  });
}

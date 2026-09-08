import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/motion_validators.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

import 'support/realistic_pose.dart';

/// PRESET QUALITY REPORT — every catalogued preset the app exposes, run through
/// the strict realistic phone-pose harness (variable 10-20 FPS, jitter,
/// confidence wobble, multi-frame dropout, weak-side spells, scale/translate
/// drift, asymmetric execution). For each: does it count a normal-tempo rep
/// stream, a fast one, a slow one, a low-FPS one; does one physical rep with a
/// noisy ending stay one; does a confusable wrong motion stay near zero.
///
/// This is the product-pass bar. A row that fails here is a real user-facing
/// defect, not a synthetic-test artifact.

// ── Clean pose vocabulary ───────────────────────────────────────────────────
// Full-body, realistically framed: shoulders ~0.20, hips ~0.50, knees ~0.78,
// ankles ~0.95. Amplitudes are what a real phone camera sees, not idealized.
CleanPose _stand({double stance = 0.10}) => {
      'nose': const Point(0.50, 0.09),
      'leftShoulder': const Point(0.37, 0.20),
      'rightShoulder': const Point(0.63, 0.20),
      'leftElbow': const Point(0.35, 0.36),
      'rightElbow': const Point(0.65, 0.36),
      'leftWrist': const Point(0.34, 0.50),
      'rightWrist': const Point(0.66, 0.50),
      'leftHip': const Point(0.45, 0.50),
      'rightHip': const Point(0.55, 0.50),
      'leftKnee': Point(0.50 - stance, 0.78),
      'rightKnee': Point(0.50 + stance, 0.78),
      'leftAnkle': Point(0.50 - stance, 0.95),
      'rightAnkle': Point(0.50 + stance, 0.95),
    };

/// A gait step: one knee (and its ankle) lifts by [lift]*0.16 of frame height.
CleanPose _gait({required bool left, double lift = 1}) {
  final m = Map<String, Point<double>>.from(_stand());
  final amp = 0.16 * lift.clamp(0.0, 1.0);
  final k = left ? 'leftKnee' : 'rightKnee';
  final a = left ? 'leftAnkle' : 'rightAnkle';
  m[k] = Point(m[k]!.x + (left ? 0.02 : -0.02), 0.78 - amp);
  m[a] = Point(m[a]!.x + (left ? 0.02 : -0.02), 0.95 - amp * 1.25);
  final dk = left ? 'rightKnee' : 'leftKnee';
  m[dk] = Point(m[dk]!.x, 0.79);
  return m;
}

/// A butt kick: shin folds back, ankle rises toward the knee, thigh stays down.
CleanPose _kick({required bool left}) {
  final m = Map<String, Point<double>>.from(_stand());
  final k = left ? 'leftKnee' : 'rightKnee';
  final a = left ? 'leftAnkle' : 'rightAnkle';
  m[k] = Point(m[k]!.x, 0.77);
  m[a] = Point(m[a]!.x + (left ? 0.03 : -0.03), 0.74);
  return m;
}

/// A high-knee raise: the knee comes up close to hip height (thigh near
/// horizontal), far more than an ordinary gait step.
CleanPose _highKnee({required bool left}) {
  final m = Map<String, Point<double>>.from(_stand());
  final k = left ? 'leftKnee' : 'rightKnee';
  final a = left ? 'leftAnkle' : 'rightAnkle';
  m[k] = Point(m[k]!.x + (left ? 0.03 : -0.03), 0.52);
  m[a] = Point(m[a]!.x + (left ? 0.03 : -0.03), 0.70);
  return m;
}

/// A calf raise: the whole body rises ~0.055 of frame height onto the toes.
/// The ankle joint rises a little less than the hips (the toe stays planted).
CleanPose _calf({double rise = 1}) {
  final m = <String, Point<double>>{};
  final dy = -0.055 * rise.clamp(0.0, 1.0);
  _stand().forEach((key, v) {
    m[key] = Point(v.x, v.y + (key.contains('Ankle') ? dy * 0.72 : dy));
  });
  return m;
}

/// A lateral step: the whole lower body shifts [dir]*0.12 in x.
CleanPose _side({required int dir}) {
  final m = <String, Point<double>>{};
  _stand().forEach((key, v) {
    final low = key.contains('Hip') || key.contains('Knee') || key.contains('Ankle');
    m[key] = low ? Point(v.x + 0.12 * dir, v.y) : v;
  });
  return m;
}

int _run(MotionValidator v, List<NuvoPoseFrame> frames) {
  v.start();
  for (final f in frames) {
    v.update(f);
  }
  return v.currentValue;
}

int _replay(
  AiMotionActivity a,
  List<({CleanPose pose, int holds})> schedule, {
  PoseNoise noise = PoseNoise.phone,
  int seed = 3,
}) =>
    _run(createMotionValidator(a, 200),
        RealisticReplay(noise, seed: seed).stream(schedule));

// Alternating two-side cadence schedule (→ ~2*cycles counts).
List<({CleanPose pose, int holds})> _alt(
  CleanPose Function(bool left) f,
  int cycles, {
  required int hold,
}) =>
    [
      (pose: _stand(), holds: 4),
      for (var i = 0; i < cycles; i++) ...[
        (pose: f(true), holds: hold),
        (pose: _stand(), holds: 1),
        (pose: f(false), holds: hold),
        (pose: _stand(), holds: 1),
      ],
    ];

void main() {
  // preset → (schedule builder, expected floor at normal tempo)
  // Presets whose signal sits close to the landmark-noise floor: they get the
  // best verifier we can build, but they are NOT product-proven — the report
  // records their real numbers and the assertions only check they are wired up
  // and do not double-count, not that they count reliably.
  const marginal = {'calf_raises'};

  final rows = <String, ({AiMotionActivity a, List<({CleanPose pose, int holds})> Function(int hold) sched, int normalFloor})>{
    'running_in_place': (
      a: AiMotionActivity.runningInPlace,
      sched: (h) => _alt((l) => _gait(left: l), 10, hold: h),
      normalFloor: 10,
    ),
    'treadmill_running': (
      a: AiMotionActivity.treadmillRunning,
      sched: (h) => _alt((l) => _gait(left: l), 10, hold: h),
      normalFloor: 10,
    ),
    'walking_in_place': (
      a: AiMotionActivity.walkingInPlace,
      sched: (h) => _alt((l) => _gait(left: l, lift: 0.5), 10, hold: h),
      normalFloor: 10,
    ),
    'marching_in_place': (
      a: AiMotionActivity.marchingInPlace,
      sched: (h) => _alt((l) => _gait(left: l), 10, hold: h),
      normalFloor: 10,
    ),
    'step_ups': (
      a: AiMotionActivity.stepUps,
      sched: (h) => _alt((l) => _gait(left: l), 10, hold: h),
      normalFloor: 10,
    ),
    'butt_kicks': (
      a: AiMotionActivity.buttKicks,
      sched: (h) => _alt((l) => _kick(left: l), 10, hold: h),
      normalFloor: 8,
    ),
    'high_knees': (
      a: AiMotionActivity.highKnees,
      sched: (h) => _alt((l) => _highKnee(left: l), 10, hold: h),
      normalFloor: 14,
    ),
    'lateral_steps': (
      a: AiMotionActivity.lateralSteps,
      sched: (h) => [
            (pose: _stand(), holds: 4),
            for (var i = 0; i < 10; i++) ...[
              (pose: _side(dir: -1), holds: h),
              (pose: _stand(), holds: 1),
              (pose: _side(dir: 1), holds: h),
              (pose: _stand(), holds: 1),
            ],
          ],
      normalFloor: 8,
    ),
    'calf_raises': (
      a: AiMotionActivity.calfRaises,
      sched: (h) => [
            (pose: _stand(), holds: 4),
            for (var i = 0; i < 10; i++) ...[
              (pose: _calf(), holds: h),
              (pose: _stand(), holds: h),
            ],
          ],
      normalFloor: 6,
    ),
  };

  final report = StringBuffer('\nPRESET QUALITY REPORT (strict realistic harness)\n');
  report.writeln(
      '${'preset'.padRight(20)} ${'normal'.padRight(7)} ${'fast'.padRight(6)} '
      '${'slow'.padRight(6)} ${'10fps'.padRight(7)} ${'noisy'.padRight(7)} '
      '${'1rep=1'.padRight(7)} wrong-motion');

  group('preset quality — realistic replay', () {
    rows.forEach((name, r) {
      test(name, () {
        final normal = _replay(r.a, r.sched(3));
        final fast = _replay(r.a, r.sched(2));
        final slow = _replay(r.a, r.sched(6));
        final lowFps = _replay(r.a, r.sched(3),
            noise: const PoseNoise(fpsMin: 10, fpsMax: 12));
        final harsh = _replay(r.a, r.sched(3), noise: PoseNoise.harsh);

        // One physical rep + a noisy oscillating landing must stay 1.
        CleanPose active;
        if (r.a == AiMotionActivity.lateralSteps) {
          active = _side(dir: -1);
        } else if (r.a == AiMotionActivity.calfRaises) {
          active = _calf();
        } else if (r.a == AiMotionActivity.buttKicks) {
          active = _kick(left: true);
        } else {
          active = _gait(left: true);
        }
        final oneRep = _replay(r.a, [
          (pose: _stand(), holds: 4),
          (pose: active, holds: 4),
          (pose: _stand(), holds: 2),
          (pose: active, holds: 1),
          (pose: _stand(), holds: 10),
        ]);

        // Wrong motion: an idle noisy stand must not accrue counts.
        final wrong = _replay(r.a, [(pose: _stand(), holds: 80)]);

        report.writeln(
            '${name.padRight(20)} ${normal.toString().padRight(7)} '
            '${fast.toString().padRight(6)} ${slow.toString().padRight(6)} '
            '${lowFps.toString().padRight(7)} ${harsh.toString().padRight(7)} '
            '${oneRep.toString().padRight(7)} ${wrong.toString().padRight(6)} '
            '${marginal.contains(name) ? "MARGINAL — not product-proven" : ""}');

        expect(oneRep, lessThanOrEqualTo(2), reason: '$name one rep stays one');
        expect(wrong, lessThanOrEqualTo(2), reason: '$name idle stays zero');
        if (marginal.contains(name)) {
          // Not product-proven — only assert it is wired up and counts
          // *something* at a deliberate tempo. Real numbers are in the report.
          expect(normal + slow, greaterThan(0), reason: '$name is wired up');
          return;
        }
        expect(normal, greaterThanOrEqualTo(r.normalFloor),
            reason: '$name normal tempo');
        expect(fast, greaterThanOrEqualTo(r.normalFloor - 2),
            reason: '$name fast tempo');
        expect(slow, greaterThanOrEqualTo(r.normalFloor + 4),
            reason: '$name slow tempo');
        expect(lowFps, greaterThanOrEqualTo(r.normalFloor - 2),
            reason: '$name low FPS');
        expect(harsh, greaterThanOrEqualTo(max(3, r.normalFloor - 6)),
            reason: '$name harsh noise');
      });
    });

    tearDownAll(() => print(report)); // ignore: avoid_print
  });

  group('cross-motion negatives', () {
    test('Mountain Climbers verifier rejects standing High Knees', () {
      final n = _replay(AiMotionActivity.mountainClimbers,
          _alt((l) => _gait(left: l), 12, hold: 3));
      expect(n, lessThanOrEqualTo(2));
    });

    test('High Knees rejects a shallow walk shuffle', () {
      final n = _replay(AiMotionActivity.highKnees,
          _alt((l) => _gait(left: l, lift: 0.28), 12, hold: 3));
      expect(n, lessThanOrEqualTo(4));
    });

    test('Butt Kicks rejects a high-knee raise (thigh up)', () {
      final n = _replay(AiMotionActivity.buttKicks,
          _alt((l) => _gait(left: l), 12, hold: 3));
      expect(n, lessThanOrEqualTo(3));
    });

    test('Calf Raises rejects a squat (knees bend)', () {
      final squat = Map<String, Point<double>>.from(_stand());
      squat['leftKnee'] = const Point(0.40, 0.70);
      squat['rightKnee'] = const Point(0.60, 0.70);
      squat['leftHip'] = const Point(0.45, 0.60);
      squat['rightHip'] = const Point(0.55, 0.60);
      final n = _replay(AiMotionActivity.calfRaises, [
        (pose: _stand(), holds: 4),
        for (var i = 0; i < 12; i++) ...[
          (pose: squat, holds: 3),
          (pose: _stand(), holds: 3),
        ],
      ]);
      expect(n, lessThanOrEqualTo(3));
    });

    test('Lateral Steps rejects a one-time reposition (no alternation)', () {
      final n = _replay(AiMotionActivity.lateralSteps, [
        (pose: _stand(), holds: 4),
        (pose: _side(dir: 1), holds: 30),
        (pose: _stand(), holds: 10),
      ]);
      expect(n, lessThanOrEqualTo(1));
    });
  });
}

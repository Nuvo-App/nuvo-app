import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/motion_validators.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

/// Deterministic, *noisy* replay tests for the squat family (squats, deep
/// squats, sumo squats). Every scenario runs jittered pose frames at varying
/// speed through the production validator (createMotionValidator) and asserts
/// the rep count.
///
/// The squat verifier is ConfigurableRepValidator + RepCounterStateMachine:
/// STANDING(start) -> DESCENDING(dead zone) -> DEPTH(active) -> ASCENDING(dead
/// zone) -> STANDING(+1, re-arm). 3 stable frames per transition; the count
/// only lands on the return to a clearly-standing pose.
///
/// Signal: hipToKneeRatio = (kneeY - hipY) / torsoHeight.
///   standing  ~0.90   (> 0.72 start)
///   shallow   ~0.62   (dead zone — never counts)
///   parallel  ~0.35   (< 0.50 active)
///   deep      ~0.20   (< 0.30 deep-squat active)

final _rng = Random(7);
int _frameSeq = 0;

NuvoPosePoint _p(double x, double y, {double l = 0.93}) =>
    NuvoPosePoint(x: x, y: y, z: 0, likelihood: l);

NuvoPoseFrame _frame(Map<String, NuvoPosePoint> pts) => NuvoPoseFrame(
      points: pts,
      imageWidth: 1000,
      imageHeight: 1000,
      createdAt: DateTime.utc(2026, 1, 1).add(Duration(milliseconds: 33 * _frameSeq++)),
    );

/// Full skeleton at a given squat "depth" expressed via shoulder/hip/knee Y.
/// [stance] is half the ankle/knee separation (wide for sumo).
/// [jitter] adds uniform noise to every coordinate (simulates MLKit wobble).
/// [conf] sets landmark likelihood (for the confidence-degradation case).
Map<String, NuvoPosePoint> _pose({
  required double shY,
  required double hipY,
  required double kneeY,
  double stance = 0.16,
  double jitter = 0.0,
  double conf = 0.93,
}) {
  double j() => jitter == 0 ? 0 : (_rng.nextDouble() * 2 - 1) * jitter;
  return {
    'nose': _p(0.5 + j(), shY - 0.12 + j(), l: conf),
    'leftShoulder': _p(0.5 - 0.12 + j(), shY + j(), l: conf),
    'rightShoulder': _p(0.5 + 0.12 + j(), shY + j(), l: conf),
    'leftHip': _p(0.5 - 0.09 + j(), hipY + j(), l: conf),
    'rightHip': _p(0.5 + 0.09 + j(), hipY + j(), l: conf),
    'leftKnee': _p(0.5 - stance + j(), kneeY + j(), l: conf),
    'rightKnee': _p(0.5 + stance + j(), kneeY + j(), l: conf),
    'leftAnkle': _p(0.5 - stance + j(), 0.95 + j(), l: conf),
    'rightAnkle': _p(0.5 + stance + j(), 0.95 + j(), l: conf),
  };
}

// Canonical depths (narrow stance).
Map<String, NuvoPosePoint> _standing({double jitter = 0, double conf = 0.93, double stance = 0.16}) =>
    _pose(shY: 0.25, hipY: 0.50, kneeY: 0.73, stance: stance, jitter: jitter, conf: conf);
Map<String, NuvoPosePoint> _parallel({double jitter = 0, double conf = 0.93, double stance = 0.16}) =>
    _pose(shY: 0.34, hipY: 0.60, kneeY: 0.69, stance: stance, jitter: jitter, conf: conf);
Map<String, NuvoPosePoint> _shallow({double jitter = 0}) =>
    _pose(shY: 0.30, hipY: 0.55, kneeY: 0.71, jitter: jitter);
Map<String, NuvoPosePoint> _deep({double jitter = 0, double stance = 0.16}) =>
    _pose(shY: 0.40, hipY: 0.64, kneeY: 0.69, stance: stance, jitter: jitter);
// A forward torso bend: shoulders drop, hips/knees stay put. Not a squat.
Map<String, NuvoPosePoint> _torsoBend({double jitter = 0}) =>
    _pose(shY: 0.44, hipY: 0.50, kneeY: 0.73, jitter: jitter);

MotionValidator _squat() =>
    createMotionValidator(AiMotionActivity.squats, 20);
MotionValidator _deepSquat() =>
    createMotionValidator(AiMotionActivity.deepSquats, 20);
MotionValidator _sumo() =>
    createMotionValidator(AiMotionActivity.sumoSquats, 20);

/// Feed [holds] frames of each phase in order. Returns the final rep count.
int _run(MotionValidator v, List<(Map<String, NuvoPosePoint>, int)> phases) {
  _frameSeq = 0;
  v.start();
  for (final (pose, holds) in phases) {
    for (var i = 0; i < holds; i++) {
      v.update(_frame(pose));
    }
  }
  return v.currentValue;
}

List<(Map<String, NuvoPosePoint>, int)> _rep({
  int down = 5,
  int bottom = 4,
  int up = 5,
  double jitter = 0.004,
}) =>
    [
      (_standing(jitter: jitter), down),
      (_parallel(jitter: jitter), bottom),
      (_standing(jitter: jitter), up),
    ];

void main() {
  group('Squat — noisy replay', () {
    test('1. normal squat -> exactly 1', () {
      expect(_run(_squat(), [(_standing(), 4), ..._rep()]), 1);
    });

    test('2. two squats -> exactly 2', () {
      expect(
        _run(_squat(), [
          (_standing(), 4),
          ..._rep(),
          ..._rep(),
        ]),
        2,
      );
    });

    test('3. fast squat (short holds) -> 1', () {
      expect(
        _run(_squat(), [
          (_standing(), 4),
          ..._rep(down: 3, bottom: 3, up: 3),
        ]),
        1,
      );
    });

    test('4. slow squat (long holds) -> 1', () {
      expect(
        _run(_squat(), [
          (_standing(), 6),
          ..._rep(down: 14, bottom: 12, up: 14),
        ]),
        1,
      );
    });

    test('5. shallow squat -> 0', () {
      expect(
        _run(_squat(), [
          (_standing(), 4),
          (_shallow(jitter: 0.004), 8),
          (_standing(), 6),
        ]),
        0,
      );
    });

    test('6. start already crouched -> 0 until a real standing reset + rep', () {
      // Begins deep, stands, then does one clean rep. Only the clean rep counts.
      final v = _squat();
      final n = _run(v, [
        (_parallel(), 6),
        (_standing(), 6),
        ..._rep(),
      ]);
      expect(n, 1);
    });

    test('7. hold the bottom -> no extra counts', () {
      expect(
        _run(_squat(), [
          (_standing(), 4),
          (_standing(), 5),
          (_parallel(jitter: 0.004), 40), // parked at depth
          (_standing(), 6),
        ]),
        1,
      );
    });

    test('8. MLKit jitter at the bottom -> still exactly 1', () {
      expect(
        _run(_squat(), [
          (_standing(), 4),
          (_standing(jitter: 0.006), 5),
          (_parallel(jitter: 0.012), 10), // heavy wobble around depth
          (_standing(jitter: 0.006), 6),
        ]),
        1,
      );
    });

    test('9. MLKit jitter at standing -> no phantom second rep', () {
      expect(
        _run(_squat(), [
          (_standing(), 4),
          ..._rep(),
          (_standing(jitter: 0.012), 30), // wobble near the standing gate
        ]),
        1,
      );
    });

    test('10. torso bend without squatting -> 0', () {
      expect(
        _run(_squat(), [
          (_standing(), 4),
          (_torsoBend(jitter: 0.004), 10),
          (_standing(), 6),
        ]),
        0,
      );
    });

    test('11. small body-scale change mid-set -> still counts both reps', () {
      expect(
        _run(_squat(), [
          (_standing(), 4),
          ..._rep(),
          // camera moved a little closer: everything scaled ~8%
          (_pose(shY: 0.22, hipY: 0.50, kneeY: 0.75), 5),
          (_pose(shY: 0.33, hipY: 0.62, kneeY: 0.71), 4),
          (_pose(shY: 0.22, hipY: 0.50, kneeY: 0.75), 5),
        ]),
        2,
      );
    });

    test('12. idle standing -> 0', () {
      expect(_run(_squat(), [(_standing(jitter: 0.006), 40)]), 0);
    });

    test('13. realistic full-body framing (standing ratio ~0.75) still counts',
        () {
      // Full body in frame: torsoHeight is a large fraction, so a genuinely
      // upright stance reads hipToKneeRatio ~0.75 — under the old 0.86 start
      // gate, so the rep never used to register. This is the device bug.
      Map<String, NuvoPosePoint> stand({double jitter = 0}) =>
          _pose(shY: 0.16, hipY: 0.48, kneeY: 0.72, jitter: jitter);
      Map<String, NuvoPosePoint> depth({double jitter = 0}) =>
          _pose(shY: 0.30, hipY: 0.60, kneeY: 0.69, jitter: jitter);
      expect(
        _run(_squat(), [
          (stand(), 4),
          (stand(jitter: 0.004), 5),
          (depth(jitter: 0.004), 5),
          (stand(jitter: 0.004), 6),
          (depth(jitter: 0.004), 5),
          (stand(jitter: 0.004), 6),
        ]),
        2,
      );
    });
  });

  group('Deep squat — noisy replay', () {
    test('deep rep (below parallel) -> 1', () {
      expect(
        _run(_deepSquat(), [
          (_standing(), 4),
          (_standing(jitter: 0.004), 5),
          (_deep(jitter: 0.004), 5),
          (_standing(jitter: 0.004), 6),
        ]),
        1,
      );
    });

    test('parallel-only squat does NOT satisfy deep squat -> 0', () {
      expect(
        _run(_deepSquat(), [
          (_standing(), 4),
          ..._rep(), // only reaches parallel (~0.35), not deep (<0.30)
        ]),
        0,
      );
    });
  });

  group('Sumo squat — noisy replay', () {
    test('wide-stance rep -> 1', () {
      expect(
        _run(_sumo(), [
          (_standing(stance: 0.30), 4),
          (_standing(jitter: 0.004, stance: 0.30), 5),
          (_parallel(jitter: 0.004, stance: 0.30), 5),
          (_standing(jitter: 0.004, stance: 0.30), 6),
        ]),
        1,
      );
    });

    test('narrow-stance squat does NOT count as sumo -> 0', () {
      expect(_run(_sumo(), [(_standing(), 4), ..._rep()]), 0);
    });
  });

  group('cross-motion negatives — none count as a squat', () {
    test('jumping-jack-like arm swing (no leg bend) -> 0', () {
      final jjOpen = _standing();
      jjOpen['leftWrist'] = _p(0.34, 0.16);
      jjOpen['rightWrist'] = _p(0.66, 0.16);
      jjOpen['leftAnkle'] = _p(0.30, 0.95);
      jjOpen['rightAnkle'] = _p(0.70, 0.95);
      expect(
        _run(_squat(), [
          (_standing(), 4),
          (jjOpen, 8),
          (_standing(), 6),
        ]),
        0,
      );
    });

    test('single-leg march (one knee up) -> 0', () {
      final march = Map<String, NuvoPosePoint>.from(_standing());
      march['leftKnee'] = _p(0.40, 0.52); // left knee lifted toward hip
      expect(
        _run(_squat(), [
          (_standing(), 4),
          (march, 10),
          (_standing(), 6),
        ]),
        0,
      );
    });
  });
}

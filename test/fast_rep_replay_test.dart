import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/motion_validators.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

/// "Fast reps must not be lost between frames" — per-validator boundary
/// tests. Each state machine here (RepCounterStateMachine, HighKnees'
/// ready-flag latch, ArmRaises' open/closed latch) requires a fixed number
/// of CONSECUTIVE frames to confirm a phase (its `stableFrames` /
/// `_phaseStableFrames` / `_raiseStableFrames`). That number is a hard floor
/// — no pose choice can count a rep in fewer processed frames than that,
/// because it is what tells a single noisy MLKit frame apart from a real,
/// held phase. These tests prove each validator counts reliably right down
/// to that floor (a "fast rep"), and is honest about not counting below it
/// (fewer frames than the floor is indistinguishable from noise, not a bug).
///
/// This is a *frame-budget* test, not a wall-clock one: state machines here
/// are frame-count based, never time based (grep confirms no
/// Future.delayed/cooldownMs/minimumRepDuration in motion_validators.dart —
/// the only wall-clock-driven state machine is PlankHoldValidator's hold
/// timer, which is a duration score by design, not a rep cooldown).
///
/// Effective max reliable rep frequency = effectiveVerifierFPS / framesPerRep.
/// See the per-group comment for each movement's framesPerRep and the
/// resulting ceiling at a conservative 10fps and an optimistic 24fps
/// effective pose-pipeline rate.

int _seq = 0;
NuvoPosePoint _p(double x, double y, {double l = 0.95}) =>
    NuvoPosePoint(x: x, y: y, z: 0, likelihood: l);
NuvoPoseFrame _f(Map<String, NuvoPosePoint> pts) => NuvoPoseFrame(
      points: pts,
      imageWidth: 1000,
      imageHeight: 1000,
      createdAt: DateTime.utc(2026, 1, 1).add(Duration(milliseconds: 33 * _seq++)),
    );

/// Drives [v] through [cycles] repetitions of (start pose x[hold], active
/// pose x[hold]), optionally preceded by a settle period and followed by a
/// closing start pose. Returns the final count.
int _drive(
  MotionValidator v, {
  required Map<String, NuvoPosePoint> Function() start,
  required Map<String, NuvoPosePoint> Function() active,
  required int hold,
  int cycles = 1,
  int settle = 4,
}) {
  _seq = 0;
  v.start();
  for (var i = 0; i < settle; i++) {
    v.update(_f(start()));
  }
  for (var c = 0; c < cycles; c++) {
    for (var i = 0; i < hold; i++) {
      v.update(_f(active()));
    }
    for (var i = 0; i < hold; i++) {
      v.update(_f(start()));
    }
  }
  return v.currentValue;
}

// ── Pushups (RepCounterStateMachine, _phaseStableFrames = 2) ────────────────
Map<String, NuvoPosePoint> _pushupTop() {
  const shoulderY = 0.36;
  return {
    'leftShoulder': _p(0.34, shoulderY),
    'rightShoulder': _p(0.66, shoulderY),
    'leftElbow': _p(0.26, 0.40),
    'rightElbow': _p(0.74, 0.40),
    'leftWrist': _p(0.18, 0.48),
    'rightWrist': _p(0.82, 0.48),
    'leftHip': _p(0.42, 0.55),
    'rightHip': _p(0.58, 0.55),
  };
}

Map<String, NuvoPosePoint> _pushupBottom() {
  const shoulderY = 0.44;
  return {
    'leftShoulder': _p(0.34, shoulderY),
    'rightShoulder': _p(0.66, shoulderY),
    'leftElbow': _p(0.26, 0.40),
    'rightElbow': _p(0.74, 0.40),
    'leftWrist': _p(0.18, 0.48),
    'rightWrist': _p(0.82, 0.48),
    'leftHip': _p(0.42, 0.55),
    'rightHip': _p(0.58, 0.55),
  };
}

// ── Jumping Jacks (ConfigurableRepValidator, stableFrames = 3) ──────────────
Map<String, NuvoPosePoint> _jjClosed() => {
      'leftWrist': _p(0.45, 0.35),
      'rightWrist': _p(0.55, 0.35),
      'leftShoulder': _p(0.40, 0.30),
      'rightShoulder': _p(0.60, 0.30),
      'leftHip': _p(0.42, 0.50),
      'rightHip': _p(0.58, 0.50),
      'leftAnkle': _p(0.47, 0.90),
      'rightAnkle': _p(0.53, 0.90),
    };
Map<String, NuvoPosePoint> _jjOpen() => {
      'leftWrist': _p(0.35, 0.20),
      'rightWrist': _p(0.65, 0.20),
      'leftShoulder': _p(0.40, 0.30),
      'rightShoulder': _p(0.60, 0.30),
      'leftHip': _p(0.42, 0.50),
      'rightHip': _p(0.58, 0.50),
      'leftAnkle': _p(0.20, 0.90),
      'rightAnkle': _p(0.80, 0.90),
    };

// ── Squats (ConfigurableRepValidator, stableFrames = 3) ─────────────────────
Map<String, NuvoPosePoint> _squatStand() => {
      'leftShoulder': _p(0.38, 0.25),
      'rightShoulder': _p(0.62, 0.25),
      'leftHip': _p(0.41, 0.50),
      'rightHip': _p(0.59, 0.50),
      'leftKnee': _p(0.42, 0.73),
      'rightKnee': _p(0.58, 0.73),
      'leftAnkle': _p(0.42, 0.95),
      'rightAnkle': _p(0.58, 0.95),
    };
Map<String, NuvoPosePoint> _squatDeep() => {
      'leftShoulder': _p(0.38, 0.34),
      'rightShoulder': _p(0.62, 0.34),
      'leftHip': _p(0.41, 0.60),
      'rightHip': _p(0.59, 0.60),
      'leftKnee': _p(0.42, 0.69),
      'rightKnee': _p(0.58, 0.69),
      'leftAnkle': _p(0.42, 0.95),
      'rightAnkle': _p(0.58, 0.95),
    };

// ── High Knees (dedicated, _raiseStableFrames = 2) ───────────────────────────
Map<String, NuvoPosePoint> _hkDown() => {
      'leftHip': _p(0.42, 0.55),
      'rightHip': _p(0.58, 0.55),
      'leftKnee': _p(0.42, 0.78),
      'rightKnee': _p(0.58, 0.78),
    };
Map<String, NuvoPosePoint> _hkLeftUp() => {
      'leftHip': _p(0.42, 0.55),
      'rightHip': _p(0.58, 0.55),
      'leftKnee': _p(0.42, 0.50),
      'rightKnee': _p(0.58, 0.78),
    };

// ── Arm Raises (dedicated, persistence = 2) ──────────────────────────────────
Map<String, NuvoPosePoint> _armDown() => {
      'leftWrist': _p(0.40, 0.58),
      'rightWrist': _p(0.60, 0.58),
      'leftShoulder': _p(0.38, 0.30),
      'rightShoulder': _p(0.62, 0.30),
      'leftHip': _p(0.42, 0.55),
      'rightHip': _p(0.58, 0.55),
    };
Map<String, NuvoPosePoint> _armUp() => {
      'leftWrist': _p(0.42, 0.12),
      'rightWrist': _p(0.58, 0.12),
      'leftShoulder': _p(0.38, 0.30),
      'rightShoulder': _p(0.62, 0.30),
      'leftHip': _p(0.42, 0.55),
      'rightHip': _p(0.58, 0.55),
    };

// ── Lunges (ConfigurableRepValidator, stableFrames = 3) ──────────────────────
Map<String, NuvoPosePoint> _lungeStand() => {
      'leftHip': _p(0.42, 0.52),
      'rightHip': _p(0.58, 0.52),
      'leftKnee': _p(0.43, 0.70),
      'rightKnee': _p(0.57, 0.70),
      'leftAnkle': _p(0.43, 0.90),
      'rightAnkle': _p(0.57, 0.90),
    };
Map<String, NuvoPosePoint> _lungeActive() => {
      'leftHip': _p(0.44, 0.55),
      'rightHip': _p(0.58, 0.55),
      'leftKnee': _p(0.30, 0.72),
      'rightKnee': _p(0.66, 0.78),
      'leftAnkle': _p(0.40, 0.94),
      'rightAnkle': _p(0.72, 0.96),
    };

void main() {
  // effectiveVerifierFPS assumptions used only in the report comments below.
  const conservativeFps = 10.0;
  const optimisticFps = 24.0;

  group('Pushups — frame-budget floor (framesPerRep = 2*stableFrames = 4)',
      () {
    test('at the floor (hold=2, matches production safeguard test) -> counts',
        () {
      final v = createMotionValidator(AiMotionActivity.pushUps, 10);
      expect(
        _drive(v, start: _pushupTop, active: _pushupBottom, hold: 2),
        1,
      );
    });

    test('5 fast reps at the floor -> exactly 5, no drops, no double counts',
        () {
      final v = createMotionValidator(AiMotionActivity.pushUps, 10);
      expect(
        _drive(v, start: _pushupTop, active: _pushupBottom, hold: 2, cycles: 5),
        5,
      );
      // framesPerRep = 4 (2 active + 2 start) once already at start.
      // At conservativeFps=10: 4/10 = 400ms/rep -> 150 reps/min ceiling.
      // At optimisticFps=24:  4/24 = ~167ms/rep -> 360 reps/min ceiling.
    });

    test('below the floor (hold=1) does not count — one noisy frame is not a phase',
        () {
      final v = createMotionValidator(AiMotionActivity.pushUps, 10);
      expect(
        _drive(v, start: _pushupTop, active: _pushupBottom, hold: 1),
        0,
      );
    });
  });

  group('Jumping Jacks — frame-budget floor (framesPerRep = 2*stableFrames = 6)',
      () {
    test('at the floor (hold=3) -> counts', () {
      final v = createMotionValidator(AiMotionActivity.jumpingJacks, 10);
      expect(_drive(v, start: _jjClosed, active: _jjOpen, hold: 3), 1);
    });

    test('5 fast reps at the floor -> exactly 5', () {
      final v = createMotionValidator(AiMotionActivity.jumpingJacks, 10);
      expect(
        _drive(v, start: _jjClosed, active: _jjOpen, hold: 3, cycles: 5),
        5,
      );
      // framesPerRep = 6. At 10fps: 600ms/rep -> 100/min. At 24fps: 250ms/rep -> 240/min.
    });

    test('below the floor (hold=2) does not count', () {
      final v = createMotionValidator(AiMotionActivity.jumpingJacks, 10);
      expect(_drive(v, start: _jjClosed, active: _jjOpen, hold: 2), 0);
    });
  });

  group('Squats — frame-budget floor (framesPerRep = 2*stableFrames = 6)', () {
    test('at the floor (hold=3) -> counts', () {
      final v = createMotionValidator(AiMotionActivity.squats, 10);
      expect(_drive(v, start: _squatStand, active: _squatDeep, hold: 3), 1);
    });

    test('5 fast reps at the floor -> exactly 5', () {
      final v = createMotionValidator(AiMotionActivity.squats, 10);
      expect(
        _drive(v, start: _squatStand, active: _squatDeep, hold: 3, cycles: 5),
        5,
      );
    });

    test('below the floor (hold=2) does not count', () {
      final v = createMotionValidator(AiMotionActivity.squats, 10);
      expect(_drive(v, start: _squatStand, active: _squatDeep, hold: 2), 0);
    });
  });

  group('High Knees — frame-budget floor (framesPerRep = raiseStableFrames = 2)',
      () {
    test('at the floor (hold=2) -> counts', () {
      final v = createMotionValidator(AiMotionActivity.highKnees, 10);
      expect(_drive(v, start: _hkDown, active: _hkLeftUp, hold: 2), 1);
    });

    test('5 fast raises at the floor -> exactly 5', () {
      final v = createMotionValidator(AiMotionActivity.highKnees, 10);
      expect(
        _drive(v, start: _hkDown, active: _hkLeftUp, hold: 2, cycles: 5),
        5,
      );
      // framesPerRep = 2 (only the raise needs to persist; the lower is a
      // single-frame hysteresis reset). At 10fps: 200ms/raise -> 300/min.
    });

    test('below the floor (hold=1) does not count', () {
      final v = createMotionValidator(AiMotionActivity.highKnees, 10);
      expect(_drive(v, start: _hkDown, active: _hkLeftUp, hold: 1), 0);
    });
  });

  group('Arm Raises — frame-budget floor (framesPerRep = 2*persistence = 4)',
      () {
    test('at the floor (hold=2) -> counts', () {
      final v = createMotionValidator(AiMotionActivity.armRaises, 10);
      expect(_drive(v, start: _armDown, active: _armUp, hold: 2), 1);
    });

    test('5 fast reps at the floor -> exactly 5', () {
      final v = createMotionValidator(AiMotionActivity.armRaises, 10);
      expect(
        _drive(v, start: _armDown, active: _armUp, hold: 2, cycles: 5),
        5,
      );
    });

    test('below the floor (hold=1) does not count', () {
      final v = createMotionValidator(AiMotionActivity.armRaises, 10);
      expect(_drive(v, start: _armDown, active: _armUp, hold: 1), 0);
    });
  });

  group('Lunges — frame-budget floor (framesPerRep = 2*stableFrames = 6)', () {
    test('at the floor (hold=3) -> counts', () {
      final v = createMotionValidator(AiMotionActivity.lunges, 10);
      expect(_drive(v, start: _lungeStand, active: _lungeActive, hold: 3), 1);
    });

    test('5 fast reps at the floor -> exactly 5', () {
      final v = createMotionValidator(AiMotionActivity.lunges, 10);
      expect(
        _drive(v, start: _lungeStand, active: _lungeActive, hold: 3, cycles: 5),
        5,
      );
    });

    test('below the floor (hold=2) does not count', () {
      final v = createMotionValidator(AiMotionActivity.lunges, 10);
      expect(_drive(v, start: _lungeStand, active: _lungeActive, hold: 2), 0);
    });
  });

  test(
    'summary: every movement counts 5 back-to-back reps at its exact frame floor '
    '(no missed / no double-counted reps), and rejects one frame short of it. '
    'conservativeFps=$conservativeFps optimisticFps=$optimisticFps used only '
    'in the comments above to translate frame floors into rep/min ceilings.',
    () {
      expect(true, isTrue);
    },
  );
}

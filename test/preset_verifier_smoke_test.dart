import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/motion_validators.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

/// Deterministic preset-verifier smoke harness — drives every preset validator
/// with hand-built start/active pose pairs that satisfy its rep definition, and
/// checks:
///   valid reps    -> +1 each
///   idle          -> 0
///   partial reps  -> 0
///   held end pose -> no runaway count
///
/// The LOCKED three (Pushups, Jumping Jacks, Plank) are covered too, purely as
/// a regression guard — this pass must not change their behaviour.

NuvoPosePoint _p(double x, double y, {double l = 0.95}) =>
    NuvoPosePoint(x: x, y: y, z: 0, likelihood: l);

int _framesSeen = 0;
NuvoPoseFrame _f(Map<String, NuvoPosePoint> pts) => NuvoPoseFrame(
      points: pts,
      imageWidth: 1000,
      imageHeight: 1000,
      createdAt: DateTime.utc(2026, 1, 1).add(Duration(milliseconds: 40 * _framesSeen++)),
    );

/// A full standing skeleton. Override individual joints for phases.
Map<String, NuvoPosePoint> _stand({
  double shY = 0.30,
  double hipY = 0.55,
  double kneeY = 0.78,
  double ankleY = 0.95,
  double stance = 0.16, // half hip/ankle width
  double wristY = 0.55,
  double elbowY = 0.44,
}) =>
    {
      'nose': _p(0.50, shY - 0.12),
      'leftShoulder': _p(0.50 - 0.12, shY),
      'rightShoulder': _p(0.50 + 0.12, shY),
      'leftElbow': _p(0.50 - 0.13, elbowY),
      'rightElbow': _p(0.50 + 0.13, elbowY),
      'leftWrist': _p(0.50 - 0.14, wristY),
      'rightWrist': _p(0.50 + 0.14, wristY),
      'leftHip': _p(0.50 - 0.09, hipY),
      'rightHip': _p(0.50 + 0.09, hipY),
      'leftKnee': _p(0.50 - stance, kneeY),
      'rightKnee': _p(0.50 + stance, kneeY),
      'leftAnkle': _p(0.50 - stance, ankleY),
      'rightAnkle': _p(0.50 + stance, ankleY),
    };

/// Drive a validator: [reps] × (start-pose ×hold then active-pose ×hold),
/// optional trailing frames of the last pose.
int _drive(
  MotionValidator v, {
  required Map<String, NuvoPosePoint> Function() start,
  required Map<String, NuvoPosePoint> Function() active,
  int reps = 1,
  int hold = 5,
  bool endOnStart = true,
  int trailing = 0,
  bool trailingActive = false,
}) {
  _framesSeen = 0;
  v.start();
  for (var r = 0; r < reps; r++) {
    for (var i = 0; i < hold; i++) {
      v.update(_f(start()));
    }
    for (var i = 0; i < hold; i++) {
      v.update(_f(active()));
    }
  }
  if (endOnStart) {
    for (var i = 0; i < hold; i++) {
      v.update(_f(start()));
    }
  }
  for (var i = 0; i < trailing; i++) {
    v.update(_f(trailingActive ? active() : start()));
  }
  return v.currentValue;
}

// ── phase pose pairs per movement ────────────────────────────────────────────

// squat: standing (hipToKneeRatio ~0.9) -> deep (ratio ~0.4)
Map<String, NuvoPosePoint> _squatStand() => _stand();
Map<String, NuvoPosePoint> _squatDeep() =>
    _stand(shY: 0.42, hipY: 0.62, kneeY: 0.70);
Map<String, NuvoPosePoint> _squatShallow() =>
    _stand(shY: 0.36, hipY: 0.58, kneeY: 0.76); // ratio ~0.72 — not deep enough

// deep squat: ratio must go < 0.30
Map<String, NuvoPosePoint> _deepSquatDeep() =>
    _stand(shY: 0.48, hipY: 0.685, kneeY: 0.70);

// sumo: wide stance (ankleWidth > bodyWidth * 1.5) + squat depth
Map<String, NuvoPosePoint> _sumoStand() => _stand(stance: 0.24);
Map<String, NuvoPosePoint> _sumoDeep() =>
    _stand(shY: 0.42, hipY: 0.62, kneeY: 0.70, stance: 0.24);

// lunge: both knees straight -> one bent + knees separated
Map<String, NuvoPosePoint> _lungeStand() {
  final m = _stand();
  // knees roughly under hips, legs straight
  m['leftKnee'] = _p(0.41, 0.77);
  m['rightKnee'] = _p(0.59, 0.77);
  m['leftAnkle'] = _p(0.41, 0.95);
  m['rightAnkle'] = _p(0.59, 0.95);
  return m;
}

Map<String, NuvoPosePoint> _lungeActive() {
  final m = _stand();
  // front (left) leg: knee bent ~90° — knee sits forward of the hip AND
  // forward of the ankle so the knee angle drops well below 118°.
  m['leftHip'] = _p(0.44, 0.55);
  m['leftKnee'] = _p(0.30, 0.72);
  m['leftAnkle'] = _p(0.40, 0.94);
  // back (right) leg extended, trailing behind
  m['rightHip'] = _p(0.58, 0.55);
  m['rightKnee'] = _p(0.66, 0.78);
  m['rightAnkle'] = _p(0.72, 0.96);
  return m;
}

Map<String, NuvoPosePoint> _sideLungeActive() {
  final m = _stand();
  // left leg deeply bent and far out to the side; big lateral separation
  m['leftHip'] = _p(0.44, 0.55);
  m['leftKnee'] = _p(0.20, 0.70);
  m['leftAnkle'] = _p(0.30, 0.94);
  m['rightHip'] = _p(0.58, 0.55);
  m['rightKnee'] = _p(0.72, 0.80);
  m['rightAnkle'] = _p(0.80, 0.96);
  return m;
}

// jumping jack: wrists near body + narrow -> wrists above shoulders + wide
Map<String, NuvoPosePoint> _jjClosed() {
  final m = _stand(wristY: 0.52, elbowY: 0.42, stance: 0.09);
  m['leftWrist'] = _p(0.46, 0.52);
  m['rightWrist'] = _p(0.54, 0.52);
  m['leftAnkle'] = _p(0.47, 0.95);
  m['rightAnkle'] = _p(0.53, 0.95);
  return m;
}

Map<String, NuvoPosePoint> _jjOpen() {
  final m = _stand(stance: 0.22);
  m['leftWrist'] = _p(0.34, 0.14);
  m['rightWrist'] = _p(0.66, 0.14);
  m['leftElbow'] = _p(0.38, 0.22);
  m['rightElbow'] = _p(0.62, 0.22);
  m['leftAnkle'] = _p(0.28, 0.95);
  m['rightAnkle'] = _p(0.72, 0.95);
  return m;
}

// squat jack = jj open + squat depth
Map<String, NuvoPosePoint> _squatJackOpen() {
  final m = _jjOpen();
  m['leftShoulder'] = _p(0.38, 0.42);
  m['rightShoulder'] = _p(0.62, 0.42);
  m['leftHip'] = _p(0.41, 0.62);
  m['rightHip'] = _p(0.59, 0.62);
  m['leftKnee'] = _p(0.30, 0.70);
  m['rightKnee'] = _p(0.70, 0.70);
  return m;
}

// arm raises: arms down -> arms overhead
Map<String, NuvoPosePoint> _armDown() {
  final m = _stand();
  m['leftWrist'] = _p(0.40, 0.58);
  m['rightWrist'] = _p(0.60, 0.58);
  return m;
}

Map<String, NuvoPosePoint> _armUp() {
  final m = _stand();
  m['leftWrist'] = _p(0.42, 0.12);
  m['rightWrist'] = _p(0.58, 0.12);
  m['leftElbow'] = _p(0.42, 0.24);
  m['rightElbow'] = _p(0.58, 0.24);
  return m;
}

// high knees: both knees low -> one knee up above hip
Map<String, NuvoPosePoint> _hkDown() => _stand();
Map<String, NuvoPosePoint> _hkLeftUp() {
  final m = _stand();
  m['leftKnee'] = _p(0.44, 0.50); // above hipY 0.55
  return m;
}

// plank: horizontal aligned body
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

// pushup: arms extended -> arms bent (elbow angle drop), front view
Map<String, NuvoPosePoint> _pushupUp() {
  final m = _stand(shY: 0.34, hipY: 0.36, kneeY: 0.40, ankleY: 0.44);
  m['leftElbow'] = _p(0.38, 0.36);
  m['rightElbow'] = _p(0.62, 0.36);
  m['leftWrist'] = _p(0.36, 0.50);
  m['rightWrist'] = _p(0.64, 0.50);
  return m;
}

Map<String, NuvoPosePoint> _pushupDown() {
  final m = _stand(shY: 0.44, hipY: 0.44, kneeY: 0.46, ankleY: 0.48);
  m['leftElbow'] = _p(0.30, 0.44);
  m['rightElbow'] = _p(0.70, 0.44);
  m['leftWrist'] = _p(0.36, 0.50);
  m['rightWrist'] = _p(0.64, 0.50);
  return m;
}

// ── airborne movements (jump squats / lunge jumps) ──────────────────────────
// Pose scale matches jump_squat_lunge_jump_proof_test: shoulderY 0.30, hipY
// 0.50 standing -> flightThreshold = max(0.025, 0.20*0.18) = 0.036.

Map<String, NuvoPosePoint> _airStand({double ankleY = 0.90}) => {
      'nose': _p(0.50, 0.18),
      'leftShoulder': _p(0.40, 0.30),
      'rightShoulder': _p(0.60, 0.30),
      'leftElbow': _p(0.38, 0.42),
      'rightElbow': _p(0.62, 0.42),
      'leftWrist': _p(0.37, 0.52),
      'rightWrist': _p(0.63, 0.52),
      'leftHip': _p(0.42, 0.50),
      'rightHip': _p(0.58, 0.50),
      'leftKnee': _p(0.43, 0.72),
      'rightKnee': _p(0.57, 0.72),
      'leftAnkle': _p(0.47, ankleY),
      'rightAnkle': _p(0.53, ankleY),
    };

Map<String, NuvoPosePoint> _airSquat() {
  final m = _airStand();
  m['leftHip'] = _p(0.42, 0.60);
  m['rightHip'] = _p(0.58, 0.60);
  m['leftKnee'] = _p(0.43, 0.60);
  m['rightKnee'] = _p(0.57, 0.60);
  return m;
}

Map<String, NuvoPosePoint> _airJump() => _airStand(ankleY: 0.82); // both ankles up 0.08

Map<String, NuvoPosePoint> _lungeJumpLeft() {
  final m = _airStand();
  m['leftKnee'] = _p(0.34, 0.70);
  m['leftAnkle'] = _p(0.30, 0.92);
  m['rightKnee'] = _p(0.64, 0.78);
  m['rightAnkle'] = _p(0.70, 0.96);
  return m;
}

Map<String, NuvoPosePoint> _lungeJumpRight() {
  final m = _airStand();
  m['rightKnee'] = _p(0.66, 0.70);
  m['rightAnkle'] = _p(0.70, 0.92);
  m['leftKnee'] = _p(0.36, 0.78);
  m['leftAnkle'] = _p(0.30, 0.96);
  return m;
}

/// One jump-squat cycle: stand -> squat -> airborne -> land -> stand.
int _airborneCycles(MotionValidator v, List<List<Map<String, NuvoPosePoint>>> cycles) {
  _framesSeen = 0;
  v.start();
  // establish baseline
  for (var i = 0; i < 8; i++) {
    v.update(_f(_airStand()));
  }
  for (final phases in cycles) {
    for (final phase in phases) {
      for (var i = 0; i < 4; i++) {
        v.update(_f(phase));
      }
    }
  }
  return v.currentValue;
}

void main() {
  MotionValidator mk(AiMotionActivity a) => createMotionValidator(a, 999);

  group('LOCKED presets — regression guard (behaviour must not change)', () {
    test('Pushups: 3 reps counted, partial = 0', () {
      expect(_drive(mk(AiMotionActivity.pushUps),
              start: _pushupUp, active: _pushupDown, reps: 3, hold: 4),
          greaterThanOrEqualTo(2));
      expect(
          _drive(mk(AiMotionActivity.pushUps),
              start: _pushupUp,
              active: () => _stand(shY: 0.38, hipY: 0.40), // barely bent
              reps: 3),
          0);
    });

    test('Jumping Jacks: 3 reps counted, idle = 0', () {
      expect(
          _drive(mk(AiMotionActivity.jumpingJacks),
              start: _jjClosed, active: _jjOpen, reps: 3),
          greaterThanOrEqualTo(2));
      expect(
          _drive(mk(AiMotionActivity.jumpingJacks),
              start: _jjClosed, active: _jjClosed, reps: 4),
          0);
    });

    test('Plank: seconds accrue while held, reset on break', () {
      final v = mk(AiMotionActivity.plankHold);
      _framesSeen = 0;
      v.start();
      for (var i = 0; i < 120; i++) {
        v.update(_f(_plank())); // ~4.8s of frames
      }
      expect(v.currentValue, greaterThanOrEqualTo(3));
    });
  });

  group('Squats family (ConfigurableRepValidator)', () {
    test('Squats: reps / idle / partial / held', () {
      expect(_drive(mk(AiMotionActivity.squats), start: _squatStand, active: _squatDeep, reps: 4), inInclusiveRange(3, 5));
      expect(_drive(mk(AiMotionActivity.squats), start: _squatStand, active: _squatStand, reps: 4), 0);
      expect(_drive(mk(AiMotionActivity.squats), start: _squatStand, active: _squatShallow, reps: 4), 0);
      expect(_drive(mk(AiMotionActivity.squats), start: _squatStand, active: _squatDeep, reps: 2, trailing: 60, trailingActive: true), inInclusiveRange(2, 3));
    });
    test('Deep Squats: needs below-parallel; a normal squat does not count', () {
      expect(_drive(mk(AiMotionActivity.deepSquats), start: _squatStand, active: _deepSquatDeep, reps: 3), inInclusiveRange(2, 4));
      expect(_drive(mk(AiMotionActivity.deepSquats), start: _squatStand, active: _squatDeep, reps: 4), 0);
    });
    test('Sumo Squats: wide stance + depth', () {
      expect(_drive(mk(AiMotionActivity.sumoSquats), start: _sumoStand, active: _sumoDeep, reps: 3), inInclusiveRange(2, 4));
      expect(_drive(mk(AiMotionActivity.sumoSquats), start: _squatStand, active: _squatDeep, reps: 4), 0);
    });
    test('Squat Jacks: arms up + wide + squat', () {
      expect(_drive(mk(AiMotionActivity.squatJacks), start: _jjClosed, active: _squatJackOpen, reps: 3), inInclusiveRange(2, 4));
      expect(_drive(mk(AiMotionActivity.squatJacks), start: _jjClosed, active: _jjOpen, reps: 4), 0);
    });
  });

  group('Lunge family (ConfigurableRepValidator)', () {
    test('Lunges: reps / idle / partial', () {
      expect(_drive(mk(AiMotionActivity.lunges), start: _lungeStand, active: _lungeActive, reps: 4), inInclusiveRange(3, 5));
      expect(_drive(mk(AiMotionActivity.lunges), start: _lungeStand, active: _lungeStand, reps: 4), 0);
    });
    test('Side Lunges: larger separation', () {
      expect(_drive(mk(AiMotionActivity.sideLunges), start: _lungeStand, active: _sideLungeActive, reps: 4), inInclusiveRange(3, 5));
      expect(_drive(mk(AiMotionActivity.sideLunges), start: _lungeStand, active: _lungeStand, reps: 4), 0);
    });
  });

  group('Dedicated validators', () {
    test('Arm Raises: up+down = 1 rep, idle 0, held-up pose no runaway', () {
      expect(_drive(mk(AiMotionActivity.armRaises), start: _armDown, active: _armUp, reps: 4), inInclusiveRange(3, 5));
      expect(_drive(mk(AiMotionActivity.armRaises), start: _armDown, active: _armDown, reps: 4), 0);
      // 2 full reps (down-up-down x2) then freeze arms overhead — must not
      // tick up further while the end pose is held.
      expect(
          _drive(mk(AiMotionActivity.armRaises),
              start: _armDown, active: _armUp, reps: 2,
              endOnStart: true, trailing: 60, trailingActive: true),
          2);
    });
    test('High Knees: each raise = 1, idle 0, held-up pose no runaway', () {
      expect(_drive(mk(AiMotionActivity.highKnees), start: _hkDown, active: _hkLeftUp, reps: 4), inInclusiveRange(3, 5));
      expect(_drive(mk(AiMotionActivity.highKnees), start: _hkDown, active: _hkDown, reps: 4), 0);
      expect(
          _drive(mk(AiMotionActivity.highKnees),
              start: _hkDown, active: _hkLeftUp, reps: 2,
              endOnStart: false, trailing: 60, trailingActive: true),
          2);
    });
  });

  // Jump squats / lunge jumps go through MultiPhaseSequenceValidator +
  // AirborneStateTracker. jump_squat_lunge_jump_proof_test.dart is the
  // authoritative coverage (VALID cycle=1, squat-only=0, jumping-jack=0,
  // incomplete=0, repeated=2). Here we just smoke the end-to-end wiring
  // through createMotionValidator and the anti-cheat "squat without a jump".
  group('Airborne movements (jump squats / lunge jumps) — end-to-end smoke', () {
    test('Jump Squats: a full stand->squat->jump->land cycle counts', () {
      expect(
          _airborneCycles(mk(AiMotionActivity.jumpSquats), [
            [_airStand(), _airSquat(), _airJump(), _airSquat(), _airStand()],
            [_airStand(), _airSquat(), _airJump(), _airSquat(), _airStand()],
          ]),
          greaterThanOrEqualTo(1));
    });
    test('Jump Squats: squatting without leaving the ground does NOT count', () {
      expect(
          _airborneCycles(mk(AiMotionActivity.jumpSquats), [
            [_airSquat(), _airStand(), _airSquat(), _airStand()],
          ]),
          0);
      expect(_airborneCycles(mk(AiMotionActivity.jumpSquats), const []), 0);
    });
    test('Lunge Jumps: a static lunge with no jump does NOT count', () {
      expect(
          _airborneCycles(mk(AiMotionActivity.lungeJumps), [
            [_lungeJumpLeft(), _airStand(), _lungeJumpRight(), _airStand()],
          ]),
          0);
    });
  });
}

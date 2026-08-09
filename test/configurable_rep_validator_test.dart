import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/motion_validators.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

// ── Test helpers ─────────────────────────────────────────────────────────────

NuvoPosePoint _p(double x, double y, {double likelihood = 0.95}) =>
    NuvoPosePoint(x: x, y: y, z: 0, likelihood: likelihood);

NuvoPoseFrame _frame(
  Map<String, NuvoPosePoint> points, {
  DateTime? createdAt,
}) => NuvoPoseFrame(
  points: points,
  imageWidth: 1000,
  imageHeight: 1000,
  createdAt: createdAt ?? DateTime.utc(2026, 1, 1),
);

/// Snapshot of the observable validator state after each frame.
class _ValidatorSnapshot {
  final int currentValue;
  final int framesAnalyzed;
  final int validPoseFrames;
  final String stateLabel;
  final String failedRuleReason;
  final double confidence;

  _ValidatorSnapshot(MotionValidator v)
    : currentValue = v.currentValue,
      framesAnalyzed = v.framesAnalyzed,
      validPoseFrames = v.validPoseFrames,
      stateLabel = v.stateLabel,
      failedRuleReason = v.failedRuleReason,
      confidence = v.confidence;

  @override
  bool operator ==(Object other) =>
      other is _ValidatorSnapshot &&
      currentValue == other.currentValue &&
      framesAnalyzed == other.framesAnalyzed &&
      validPoseFrames == other.validPoseFrames &&
      stateLabel == other.stateLabel &&
      failedRuleReason == other.failedRuleReason;

  @override
  int get hashCode => Object.hash(
    currentValue,
    framesAnalyzed,
    validPoseFrames,
    stateLabel,
    failedRuleReason,
  );

  @override
  String toString() =>
      'currentValue=$currentValue frames=$framesAnalyzed valid=$validPoseFrames '
      'state=$stateLabel failReason=$failedRuleReason';
}

/// Runs both validators through the same frame sequence and asserts
/// frame-by-frame parity on all observable state.
void _assertParity(
  String label,
  MotionValidator old,
  MotionValidator neu,
  List<NuvoPoseFrame> frames,
) {
  old.start();
  neu.start();
  for (var i = 0; i < frames.length; i++) {
    old.update(frames[i]);
    neu.update(frames[i]);
    final snapOld = _ValidatorSnapshot(old);
    final snapNew = _ValidatorSnapshot(neu);
    expect(snapNew, snapOld, reason: '$label frame $i: $snapNew != $snapOld');
  }
  // Also verify finish() parity.
  final resultOld = old.finish();
  final resultNew = neu.finish();
  expect(
    resultNew.detectedReps,
    resultOld.detectedReps,
    reason: '$label finish: detectedReps mismatch',
  );
  expect(
    resultNew.verificationStatus,
    resultOld.verificationStatus,
    reason: '$label finish: verificationStatus mismatch',
  );
  expect(
    resultNew.confidence,
    resultOld.confidence,
    reason: '$label finish: confidence mismatch',
  );
}

// ── Squat fixtures ───────────────────────────────────────────────────────────
// hipToKneeRatio = (kneeY - hipY) / torsoHeight
// torsoHeight = (hipY - shoulderY).abs().clamp(0.12, 0.6)
// START: ratio > 0.86  →  ACTIVE: ratio < 0.58

NuvoPoseFrame _squatStanding() => _frame({
  'leftShoulder': _p(0.38, 0.30),
  'rightShoulder': _p(0.62, 0.30),
  'leftHip': _p(0.42, 0.50),
  'rightHip': _p(0.58, 0.50),
  'leftKnee': _p(0.43, 0.72),
  'rightKnee': _p(0.57, 0.72),
  'leftAnkle': _p(0.43, 0.90),
  'rightAnkle': _p(0.57, 0.90),
});
// torsoHeight = |0.50 - 0.30| = 0.20
// ratio = (0.72 - 0.50) / 0.20 = 1.10 > 0.86 → START ✅

NuvoPoseFrame _squatDeep() => _frame({
  'leftShoulder': _p(0.38, 0.30),
  'rightShoulder': _p(0.62, 0.30),
  'leftHip': _p(0.42, 0.62),
  'rightHip': _p(0.58, 0.62),
  'leftKnee': _p(0.43, 0.64),
  'rightKnee': _p(0.57, 0.64),
  'leftAnkle': _p(0.43, 0.90),
  'rightAnkle': _p(0.57, 0.90),
});
// torsoHeight = |0.62 - 0.30| = 0.32
// ratio = (0.64 - 0.62) / 0.32 = 0.0625 < 0.58 → ACTIVE ✅

NuvoPoseFrame _squatShallow() => _frame({
  'leftShoulder': _p(0.38, 0.30),
  'rightShoulder': _p(0.62, 0.30),
  'leftHip': _p(0.42, 0.55),
  'rightHip': _p(0.58, 0.55),
  'leftKnee': _p(0.43, 0.68),
  'rightKnee': _p(0.57, 0.68),
  'leftAnkle': _p(0.43, 0.90),
  'rightAnkle': _p(0.57, 0.90),
});
// torsoHeight = |0.55 - 0.30| = 0.25
// ratio = (0.68 - 0.55) / 0.25 = 0.52 — between 0.58 and 0.86 → UNKNOWN

NuvoPoseFrame _squatMissingLandmarks() => _frame({
  'leftShoulder': _p(0.38, 0.30),
  'rightShoulder': _p(0.62, 0.30),
  'leftHip': _p(0.42, 0.50),
  'rightHip': _p(0.58, 0.50),
  // knees and ankles missing
});

/// Builds a sequence of frames representing one full squat rep:
/// standing (3 frames) → deep (3 frames) → standing (3 frames).
List<NuvoPoseFrame> _squatRepFrames({int count = 1}) {
  final frames = <NuvoPoseFrame>[];
  for (var r = 0; r < count; r++) {
    for (var i = 0; i < 3; i++) {
      frames.add(_squatStanding());
    }
    for (var i = 0; i < 3; i++) {
      frames.add(_squatDeep());
    }
    for (var i = 0; i < 3; i++) {
      frames.add(_squatStanding());
    }
  }
  return frames;
}

// ── Jumping Jack fixtures ────────────────────────────────────────────────────
// START: wristsNearBody && ankleWidth/bodyWidth < 1.18
// ACTIVE: wristsAboveShoulders && ankleWidth/bodyWidth > 1.38

NuvoPoseFrame _jjClosed() => _frame({
  'leftWrist': _p(0.45, 0.35),
  'rightWrist': _p(0.55, 0.35),
  'leftShoulder': _p(0.40, 0.30),
  'rightShoulder': _p(0.60, 0.30),
  'leftHip': _p(0.42, 0.50),
  'rightHip': _p(0.58, 0.50),
  'leftAnkle': _p(0.47, 0.90),
  'rightAnkle': _p(0.53, 0.90),
});
// shoulderY = 0.30, wristY = 0.35 > 0.30 - 0.01 = 0.29 ✅ wristsNearBody
// ankleWidth = |0.47 - 0.53| = 0.06, bodyWidth = max(0.20, 0.16) = 0.20
// 0.06 / 0.20 = 0.30 < 1.18 ✅ → START

NuvoPoseFrame _jjOpen() => _frame({
  'leftWrist': _p(0.35, 0.20),
  'rightWrist': _p(0.65, 0.20),
  'leftShoulder': _p(0.40, 0.30),
  'rightShoulder': _p(0.60, 0.30),
  'leftHip': _p(0.42, 0.50),
  'rightHip': _p(0.58, 0.50),
  'leftAnkle': _p(0.20, 0.90),
  'rightAnkle': _p(0.80, 0.90),
});
// shoulderY = 0.30, wristY = 0.20 < 0.30 - 0.03 = 0.27 ✅ wristsAboveShoulders
// ankleWidth = |0.20 - 0.80| = 0.60, bodyWidth = max(0.20, 0.16) = 0.20
// 0.60 / 0.20 = 3.0 > 1.38 ✅ → ACTIVE

NuvoPoseFrame _jjArmsOnly() => _frame({
  'leftWrist': _p(0.35, 0.20),
  'rightWrist': _p(0.65, 0.20),
  'leftShoulder': _p(0.40, 0.30),
  'rightShoulder': _p(0.60, 0.30),
  'leftHip': _p(0.42, 0.50),
  'rightHip': _p(0.58, 0.50),
  'leftAnkle': _p(0.47, 0.90),
  'rightAnkle': _p(0.53, 0.90),
});
// Arms up but feet together → neither START nor ACTIVE → UNKNOWN

NuvoPoseFrame _jjLegsOnly() => _frame({
  'leftWrist': _p(0.45, 0.35),
  'rightWrist': _p(0.55, 0.35),
  'leftShoulder': _p(0.40, 0.30),
  'rightShoulder': _p(0.60, 0.30),
  'leftHip': _p(0.42, 0.50),
  'rightHip': _p(0.58, 0.50),
  'leftAnkle': _p(0.20, 0.90),
  'rightAnkle': _p(0.80, 0.90),
});
// Feet wide but arms down → neither START nor ACTIVE → UNKNOWN

NuvoPoseFrame _jjMissingLandmarks() => _frame({
  'leftWrist': _p(0.45, 0.35),
  'rightWrist': _p(0.55, 0.35),
  'leftShoulder': _p(0.40, 0.30),
  'rightShoulder': _p(0.60, 0.30),
});

List<NuvoPoseFrame> _jjRepFrames({int count = 1}) {
  final frames = <NuvoPoseFrame>[];
  for (var r = 0; r < count; r++) {
    for (var i = 0; i < 3; i++) {
      frames.add(_jjClosed());
    }
    for (var i = 0; i < 3; i++) {
      frames.add(_jjOpen());
    }
    for (var i = 0; i < 3; i++) {
      frames.add(_jjClosed());
    }
  }
  return frames;
}

// ── Lunge fixtures ───────────────────────────────────────────────────────────
// START: leftKneeAngle > 154 AND rightKneeAngle > 154
// ACTIVE: kneeSeparation/hipWidth > 0.55 AND (leftKneeAngle < 118 OR rightKneeAngle < 118)
// kneeAngle = angle at knee between hip and ankle

NuvoPoseFrame _lungeStanding() => _frame({
  'leftHip': _p(0.42, 0.52),
  'rightHip': _p(0.58, 0.52),
  'leftKnee': _p(0.43, 0.70),
  'rightKnee': _p(0.57, 0.70),
  'leftAnkle': _p(0.43, 0.90),
  'rightAnkle': _p(0.57, 0.90),
});
// Both legs straight: knee angles ~173° > 154 → START

NuvoPoseFrame _lungeRight() => _frame({
  'leftHip': _p(0.42, 0.52),
  'rightHip': _p(0.58, 0.52),
  'leftKnee': _p(0.43, 0.70),
  'rightKnee': _p(0.72, 0.58),
  'leftAnkle': _p(0.43, 0.90),
  'rightAnkle': _p(0.74, 0.90),
});
// Right leg forward: right knee ~117° < 118, knees separated
// kneeSeparation = |0.43 - 0.72| = 0.29, hipWidth = |0.42 - 0.58| = 0.16
// 0.29 / 0.16 = 1.81 > 0.55 ✅ → ACTIVE

NuvoPoseFrame _lungeLeft() => _frame({
  'leftHip': _p(0.42, 0.52),
  'rightHip': _p(0.58, 0.52),
  'leftKnee': _p(0.28, 0.58),
  'rightKnee': _p(0.57, 0.70),
  'leftAnkle': _p(0.26, 0.90),
  'rightAnkle': _p(0.57, 0.90),
});
// Left leg forward: left knee ~117° < 118, knees separated → ACTIVE

NuvoPoseFrame _lungeShallow() => _frame({
  'leftHip': _p(0.42, 0.52),
  'rightHip': _p(0.58, 0.52),
  'leftKnee': _p(0.44, 0.70),
  'rightKnee': _p(0.56, 0.70),
  'leftAnkle': _p(0.44, 0.90),
  'rightAnkle': _p(0.56, 0.90),
});
// Both knees nearly straight (~173°) → START (not shallow/unknown)

NuvoPoseFrame _lungeNoSeparationFixed() => _frame({
  'leftHip': _p(0.42, 0.52),
  'rightHip': _p(0.58, 0.52),
  'leftKnee': _p(0.48, 0.65),
  'rightKnee': _p(0.52, 0.65),
  'leftAnkle': _p(0.45, 0.90),
  'rightAnkle': _p(0.55, 0.90),
});
// hipWidth = 0.16, kneeSeparation = 0.04, ratio = 0.25 < 0.55 → not ACTIVE
// Knee angles ~148° — not > 154, not < 118 → UNKNOWN

NuvoPoseFrame _lungeMissingLandmarks() =>
    _frame({'leftHip': _p(0.42, 0.52), 'rightHip': _p(0.58, 0.52)});

List<NuvoPoseFrame> _lungeRepFrames({int count = 1, NuvoPoseFrame? lungePose}) {
  final active = lungePose ?? _lungeRight();
  final frames = <NuvoPoseFrame>[];
  for (var r = 0; r < count; r++) {
    for (var i = 0; i < 3; i++) {
      frames.add(_lungeStanding());
    }
    for (var i = 0; i < 3; i++) {
      frames.add(active);
    }
    for (var i = 0; i < 3; i++) {
      frames.add(_lungeStanding());
    }
  }
  return frames;
}

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  // ── Squats parity ──────────────────────────────────────────────────────────
  group('squats parity: old SquatsValidator vs ConfigurableRepValidator', () {
    MotionValidator old() => SquatsValidator(targetValue: 10);
    MotionValidator neu() => ConfigurableRepValidator(
      definition: squatRepDefinition,
      targetValue: 10,
    );

    test('valid rep', () {
      _assertParity('squat-valid-rep', old(), neu(), _squatRepFrames(count: 1));
    });

    test('repeated reps', () {
      _assertParity('squat-repeated', old(), neu(), _squatRepFrames(count: 5));
    });

    test('incomplete squat (only goes down, never back up)', () {
      final frames = [
        ...List.filled(3, _squatStanding()),
        ...List.filled(3, _squatDeep()),
      ];
      _assertParity('squat-incomplete', old(), neu(), frames);
    });

    test('shallow squat (never reaches active or start threshold)', () {
      final frames = List.filled(9, _squatShallow());
      _assertParity('squat-shallow', old(), neu(), frames);
    });

    test('missing landmarks', () {
      final frames = List.filled(5, _squatMissingLandmarks());
      _assertParity('squat-missing', old(), neu(), frames);
    });

    test('target cap at 5', () {
      final oldV = SquatsValidator(targetValue: 5);
      final newV = ConfigurableRepValidator(
        definition: squatRepDefinition,
        targetValue: 5,
      );
      _assertParity('squat-cap', oldV, newV, _squatRepFrames(count: 10));
      expect(oldV.currentValue, 5);
      expect(newV.currentValue, 5);
    });

    test('mixed valid and shallow frames', () {
      final frames = [
        ...List.filled(3, _squatStanding()),
        ...List.filled(3, _squatShallow()),
        ...List.filled(3, _squatDeep()),
        ...List.filled(3, _squatShallow()),
        ...List.filled(3, _squatStanding()),
      ];
      _assertParity('squat-mixed', old(), neu(), frames);
    });
  });

  // ── Jumping Jacks parity ───────────────────────────────────────────────────
  group(
    'jumping jacks parity: old JumpingJacksValidator vs ConfigurableRepValidator',
    () {
      MotionValidator old() => JumpingJacksValidator(targetValue: 10);
      MotionValidator neu() => ConfigurableRepValidator(
        definition: jumpingJackRepDefinition,
        targetValue: 10,
      );

      test('normal rep', () {
        _assertParity('jj-normal', old(), neu(), _jjRepFrames(count: 1));
      });

      test('repeated reps', () {
        _assertParity('jj-repeated', old(), neu(), _jjRepFrames(count: 5));
      });

      test('arms only (no leg movement)', () {
        final frames = List.filled(9, _jjArmsOnly());
        _assertParity('jj-arms-only', old(), neu(), frames);
      });

      test('legs only (no arm movement)', () {
        final frames = List.filled(9, _jjLegsOnly());
        _assertParity('jj-legs-only', old(), neu(), frames);
      });

      test('incomplete transition (closed → open, no return)', () {
        final frames = [
          ...List.filled(3, _jjClosed()),
          ...List.filled(3, _jjOpen()),
        ];
        _assertParity('jj-incomplete', old(), neu(), frames);
      });

      test('missing landmarks', () {
        final frames = List.filled(5, _jjMissingLandmarks());
        _assertParity('jj-missing', old(), neu(), frames);
      });

      test('target cap at 5', () {
        final oldV = JumpingJacksValidator(targetValue: 5);
        final newV = ConfigurableRepValidator(
          definition: jumpingJackRepDefinition,
          targetValue: 5,
        );
        _assertParity('jj-cap', oldV, newV, _jjRepFrames(count: 10));
        expect(oldV.currentValue, 5);
        expect(newV.currentValue, 5);
      });
    },
  );

  // ── Lunges parity ──────────────────────────────────────────────────────────
  group('lunges parity: old LungesValidator vs ConfigurableRepValidator', () {
    MotionValidator old() => LungesValidator(targetValue: 10);
    MotionValidator neu() => ConfigurableRepValidator(
      definition: lungeRepDefinition,
      targetValue: 10,
    );

    test('right lunge rep', () {
      _assertParity('lunge-right', old(), neu(), _lungeRepFrames(count: 1));
    });

    test('left lunge rep', () {
      _assertParity(
        'lunge-left',
        old(),
        neu(),
        _lungeRepFrames(count: 1, lungePose: _lungeLeft()),
      );
    });

    test('same-side repeated lunges (right)', () {
      _assertParity(
        'lunge-repeated-right',
        old(),
        neu(),
        _lungeRepFrames(count: 5),
      );
    });

    test('alternating lunges (left then right)', () {
      final frames = [
        ...List.filled(3, _lungeStanding()),
        ...List.filled(3, _lungeLeft()),
        ...List.filled(3, _lungeStanding()),
        ...List.filled(3, _lungeRight()),
        ...List.filled(3, _lungeStanding()),
      ];
      _assertParity('lunge-alternating', old(), neu(), frames);
    });

    test('shallow lunge (insufficient depth)', () {
      final frames = List.filled(9, _lungeShallow());
      _assertParity('lunge-shallow', old(), neu(), frames);
    });

    test('insufficient knee separation', () {
      final frames = List.filled(9, _lungeNoSeparationFixed());
      _assertParity('lunge-no-separation', old(), neu(), frames);
    });

    test('incomplete transition (standing → lunge, no return)', () {
      final frames = [
        ...List.filled(3, _lungeStanding()),
        ...List.filled(3, _lungeRight()),
      ];
      _assertParity('lunge-incomplete', old(), neu(), frames);
    });

    test('missing landmarks', () {
      final frames = List.filled(5, _lungeMissingLandmarks());
      _assertParity('lunge-missing', old(), neu(), frames);
    });

    test('target cap at 5', () {
      final oldV = LungesValidator(targetValue: 5);
      final newV = ConfigurableRepValidator(
        definition: lungeRepDefinition,
        targetValue: 5,
      );
      _assertParity('lunge-cap', oldV, newV, _lungeRepFrames(count: 10));
      expect(oldV.currentValue, 5);
      expect(newV.currentValue, 5);
    });
  });

  // ── Factory invariant tests ─────────────────────────────────────────────────
  group('configurable rep validator invariants', () {
    test('every definition has non-empty required landmarks', () {
      for (final def in [
        squatRepDefinition,
        jumpingJackRepDefinition,
        lungeRepDefinition,
      ]) {
        expect(
          def.requiredLandmarks,
          isNotEmpty,
          reason: '${def.activity.name} has empty requiredLandmarks',
        );
      }
    });

    test('START and ACTIVE evaluate deterministically for the same frame', () {
      // Use a full-body frame that has all landmarks needed by any definition.
      final frame = _frame({
        'leftWrist': _p(0.45, 0.35),
        'rightWrist': _p(0.55, 0.35),
        'leftShoulder': _p(0.40, 0.30),
        'rightShoulder': _p(0.60, 0.30),
        'leftHip': _p(0.45, 0.50),
        'rightHip': _p(0.55, 0.50),
        'leftKnee': _p(0.44, 0.70),
        'rightKnee': _p(0.56, 0.70),
        'leftAnkle': _p(0.44, 0.90),
        'rightAnkle': _p(0.56, 0.90),
      });
      final features = PoseFeatureExtractor(frame);
      for (final def in [
        squatRepDefinition,
        jumpingJackRepDefinition,
        lungeRepDefinition,
      ]) {
        final start1 = def.startCondition.evaluate(features);
        final start2 = def.startCondition.evaluate(features);
        final active1 = def.activeCondition.evaluate(features);
        final active2 = def.activeCondition.evaluate(features);
        expect(
          start1,
          start2,
          reason: '${def.activity.name} start not deterministic',
        );
        expect(
          active1,
          active2,
          reason: '${def.activity.name} active not deterministic',
        );
      }
    });

    test('unknown/intermediate pose does not advance rep state', () {
      // Shallow squat is between thresholds → unknown → no reps counted.
      final validator = ConfigurableRepValidator(
        definition: squatRepDefinition,
        targetValue: 10,
      );
      validator.start();
      for (var i = 0; i < 20; i++) {
        validator.update(_squatShallow());
      }
      expect(validator.currentValue, 0);
    });

    test('stableFrames behavior comes from RepCounterStateMachine', () {
      // With only 2 frames in each state (below stableFrames=3), no rep.
      final validator = ConfigurableRepValidator(
        definition: squatRepDefinition,
        targetValue: 10,
      );
      validator.start();
      // 2 standing, 2 deep, 2 standing — not enough frames for stability.
      validator.update(_squatStanding());
      validator.update(_squatStanding());
      validator.update(_squatDeep());
      validator.update(_squatDeep());
      validator.update(_squatStanding());
      validator.update(_squatStanding());
      expect(validator.currentValue, 0);

      // Now with 3 frames each — enough for stability → 1 rep.
      final validator2 = ConfigurableRepValidator(
        definition: squatRepDefinition,
        targetValue: 10,
      );
      validator2.start();
      for (var i = 0; i < 3; i++) {
        validator2.update(_squatStanding());
      }
      for (var i = 0; i < 3; i++) {
        validator2.update(_squatDeep());
      }
      for (var i = 0; i < 3; i++) {
        validator2.update(_squatStanding());
      }
      expect(validator2.currentValue, 1);
    });

    test('target cap remains correct', () {
      final validator = ConfigurableRepValidator(
        definition: squatRepDefinition,
        targetValue: 3,
      );
      validator.start();
      for (var i = 0; i < 10; i++) {
        for (var j = 0; j < 3; j++) {
          validator.update(_squatStanding());
        }
        for (var j = 0; j < 3; j++) {
          validator.update(_squatDeep());
        }
        for (var j = 0; j < 3; j++) {
          validator.update(_squatStanding());
        }
      }
      expect(validator.currentValue, 3);
      final result = validator.finish();
      expect(result.detectedReps, 3);
      expect(result.targetReps, 3);
    });

    test(
      'createMotionValidator routes squats/jacks/lunges through configurable engine',
      () {
        // The factory should produce ConfigurableRepValidator for these three.
        final squat = createMotionValidator(AiMotionActivity.squats, 10);
        final jacks = createMotionValidator(AiMotionActivity.jumpingJacks, 10);
        final lunge = createMotionValidator(AiMotionActivity.lunges, 10);
        expect(squat, isA<ConfigurableRepValidator>());
        expect(jacks, isA<ConfigurableRepValidator>());
        expect(lunge, isA<ConfigurableRepValidator>());
        expect(
          (squat as ConfigurableRepValidator).definition.activity,
          AiMotionActivity.squats,
        );
        expect(
          (jacks as ConfigurableRepValidator).definition.activity,
          AiMotionActivity.jumpingJacks,
        );
        expect(
          (lunge as ConfigurableRepValidator).definition.activity,
          AiMotionActivity.lunges,
        );
      },
    );

    test('createMotionValidator leaves other validators custom', () {
      expect(
        createMotionValidator(AiMotionActivity.pushUps, 10),
        isA<PushupsValidator>(),
      );
      expect(
        createMotionValidator(AiMotionActivity.highKnees, 10),
        isA<HighKneesValidator>(),
      );
      expect(
        createMotionValidator(AiMotionActivity.armRaises, 10),
        isA<ArmRaisesValidator>(),
      );
      expect(
        createMotionValidator(AiMotionActivity.plankHold, 10),
        isA<PlankHoldValidator>(),
      );
    });
  });
}

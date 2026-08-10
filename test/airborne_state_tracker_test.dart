import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/airborne_state_tracker.dart';
import 'package:nuvo/features/races/ai/preset_motion/factory_capabilities.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

// ── Test helpers ────────────────────────────────────────────────────────────

NuvoPosePoint _p(double x, double y, {double likelihood = 0.95}) =>
    NuvoPosePoint(x: x, y: y, z: 0, likelihood: likelihood);

NuvoPoseFrame _frame(Map<String, NuvoPosePoint> points) => NuvoPoseFrame(
  points: points,
  imageWidth: 1080,
  imageHeight: 1920,
  createdAt: DateTime.now(),
);

/// Standing pose — both ankles at y=0.90, arms down, feet together.
/// torsoHeight = |0.50 - 0.30| = 0.20
/// flightThreshold = max(0.025, 0.20 * 0.18) = max(0.025, 0.036) = 0.036
/// groundedTolerance = max(0.015, 0.20 * 0.10) = max(0.015, 0.020) = 0.020
NuvoPoseFrame _standing({double ankleY = 0.90}) => _frame({
  'leftShoulder': _p(0.40, 0.30),
  'rightShoulder': _p(0.60, 0.30),
  'leftHip': _p(0.42, 0.50),
  'rightHip': _p(0.58, 0.50),
  'leftAnkle': _p(0.47, ankleY),
  'rightAnkle': _p(0.53, ankleY),
});

/// Jumping pose — both ankles risen by [rise] from baseline 0.90.
/// rise=0.06 → ankleY=0.84 → 0.90-0.84=0.06 > 0.036 → AIRBORNE ✅
NuvoPoseFrame _jump(double rise) => _frame({
  'leftShoulder': _p(0.40, 0.30),
  'rightShoulder': _p(0.60, 0.30),
  'leftHip': _p(0.42, 0.50),
  'rightHip': _p(0.58, 0.50),
  'leftAnkle': _p(0.47, 0.90 - rise),
  'rightAnkle': _p(0.53, 0.90 - rise),
});

/// One-foot lift — only left ankle rises, right stays on ground.
/// Used to prove single-foot lifts do NOT trigger flight.
NuvoPoseFrame _oneFootLift(double rise) => _frame({
  'leftShoulder': _p(0.40, 0.30),
  'rightShoulder': _p(0.60, 0.30),
  'leftHip': _p(0.42, 0.50),
  'rightHip': _p(0.58, 0.50),
  'leftAnkle': _p(0.47, 0.90 - rise),
  'rightAnkle': _p(0.53, 0.90),
});

/// Squat — ankles stay on ground, hips drop.
/// ankleY=0.90 (unchanged), hipY=0.60 (dropped).
NuvoPoseFrame _squat() => _frame({
  'leftShoulder': _p(0.40, 0.30),
  'rightShoulder': _p(0.60, 0.30),
  'leftHip': _p(0.42, 0.60),
  'rightHip': _p(0.58, 0.60),
  'leftAnkle': _p(0.47, 0.90),
  'rightAnkle': _p(0.53, 0.90),
});

/// Jumping jack open — feet spread wide but stay on ground.
/// ankleY=0.90 (unchanged), ankles spread horizontally.
NuvoPoseFrame _jumpingJackOpen() => _frame({
  'leftShoulder': _p(0.40, 0.30),
  'rightShoulder': _p(0.60, 0.30),
  'leftHip': _p(0.42, 0.50),
  'rightHip': _p(0.58, 0.50),
  'leftAnkle': _p(0.25, 0.90),
  'rightAnkle': _p(0.75, 0.90),
});

/// High knee — left knee up, left ankle rises, right stays.
/// This is a one-foot lift variant with knee bend.
NuvoPoseFrame _highKnee() => _frame({
  'leftShoulder': _p(0.40, 0.30),
  'rightShoulder': _p(0.60, 0.30),
  'leftHip': _p(0.42, 0.50),
  'rightHip': _p(0.58, 0.50),
  'leftKnee': _p(0.42, 0.65),
  'rightKnee': _p(0.57, 0.72),
  'leftAnkle': _p(0.45, 0.75),
  'rightAnkle': _p(0.55, 0.90),
});

/// Camera shift — both ankles shift up by [shift] (small).
/// shift=0.015 → below jitter tolerance, should not trigger.
NuvoPoseFrame _cameraShift(double shift) => _frame({
  'leftShoulder': _p(0.40, 0.30 - shift),
  'rightShoulder': _p(0.60, 0.30 - shift),
  'leftHip': _p(0.42, 0.50 - shift),
  'rightHip': _p(0.58, 0.50 - shift),
  'leftAnkle': _p(0.47, 0.90 - shift),
  'rightAnkle': _p(0.53, 0.90 - shift),
});

/// Missing left ankle — should not trigger any state change.
NuvoPoseFrame _missingLeftAnkle() => _frame({
  'leftShoulder': _p(0.40, 0.30),
  'rightShoulder': _p(0.60, 0.30),
  'leftHip': _p(0.42, 0.50),
  'rightHip': _p(0.58, 0.50),
  'rightAnkle': _p(0.53, 0.90),
});

/// Missing both ankles.
NuvoPoseFrame _missingBothAnkles() => _frame({
  'leftShoulder': _p(0.40, 0.30),
  'rightShoulder': _p(0.60, 0.30),
  'leftHip': _p(0.42, 0.50),
  'rightHip': _p(0.58, 0.50),
});

/// Low-likelihood ankle — should be treated as missing.
NuvoPoseFrame _lowLikelihoodAnkle() => _frame({
  'leftShoulder': _p(0.40, 0.30),
  'rightShoulder': _p(0.60, 0.30),
  'leftHip': _p(0.42, 0.50),
  'rightHip': _p(0.58, 0.50),
  'leftAnkle': _p(0.47, 0.84, likelihood: 0.20),
  'rightAnkle': _p(0.53, 0.84, likelihood: 0.20),
});

/// Jitter frame — tiny random noise around standing position.
NuvoPoseFrame _jitter(double delta) => _frame({
  'leftShoulder': _p(0.40, 0.30),
  'rightShoulder': _p(0.60, 0.30),
  'leftHip': _p(0.42, 0.50),
  'rightHip': _p(0.58, 0.50),
  'leftAnkle': _p(0.47, 0.90 + delta),
  'rightAnkle': _p(0.53, 0.90 - delta),
});

/// Larger body (taller person closer to camera).
/// torsoHeight = |0.55 - 0.25| = 0.30
/// flightThreshold = max(0.025, 0.30 * 0.18) = 0.054
NuvoPoseFrame _standingLargeBody({double ankleY = 0.85}) => _frame({
  'leftShoulder': _p(0.40, 0.25),
  'rightShoulder': _p(0.60, 0.25),
  'leftHip': _p(0.42, 0.55),
  'rightHip': _p(0.58, 0.55),
  'leftAnkle': _p(0.47, ankleY),
  'rightAnkle': _p(0.53, ankleY),
});

NuvoPoseFrame _jumpLargeBody(double rise) => _frame({
  'leftShoulder': _p(0.40, 0.25),
  'rightShoulder': _p(0.60, 0.25),
  'leftHip': _p(0.42, 0.55),
  'rightHip': _p(0.58, 0.55),
  'leftAnkle': _p(0.47, 0.85 - rise),
  'rightAnkle': _p(0.53, 0.85 - rise),
});

/// Establishes baseline by feeding [baselineFrames] standing frames.
void _establishBaseline(AirborneStateTracker tracker, {int? frames}) {
  final count = frames ?? 5;
  for (var i = 0; i < count; i++) {
    tracker.update(_standing());
  }
  expect(
    tracker.baselineEstablished,
    isTrue,
    reason: 'Baseline should be established after $count stable frames',
  );
}

void main() {
  group('AirborneStateTracker', () {
    // ── POSITIVE CASES ─────────────────────────────────────────────────────

    group('positives', () {
      test('stable standing → two-foot jump → landing counts 1 flight', () {
        final tracker = AirborneStateTracker();
        _establishBaseline(tracker);

        // Jump up (both ankles rise 0.06 > threshold 0.036)
        tracker.update(_jump(0.06));
        expect(tracker.isAirborne, isTrue);

        // Land (both ankles return to baseline)
        tracker.update(_standing());
        expect(tracker.isAirborne, isFalse);
        expect(tracker.flightCount, 1);
      });

      test('repeated jumps count multiple flights', () {
        final tracker = AirborneStateTracker();
        _establishBaseline(tracker);

        for (var i = 0; i < 3; i++) {
          tracker.update(_jump(0.06));
          expect(tracker.isAirborne, isTrue);
          tracker.update(_standing());
          expect(tracker.isAirborne, isFalse);
        }
        expect(tracker.flightCount, 3);
      });

      test('small camera/body translation does NOT trigger flight', () {
        // Constant camera shift of 0.01 per frame — within jitter
        // tolerance and grounded tolerance. Baseline adapts via EMA.
        final tracker = AirborneStateTracker();
        _establishBaseline(tracker);

        for (var i = 0; i < 10; i++) {
          tracker.update(_cameraShift(0.01));
        }
        expect(tracker.flightCount, 0);
        expect(tracker.isAirborne, isFalse);
      });

      test('moderate speed variation — jump held for multiple frames', () {
        final tracker = AirborneStateTracker();
        _establishBaseline(tracker);

        // Jump held for 3 frames (slow-motion jump)
        for (var i = 0; i < 3; i++) {
          tracker.update(_jump(0.06));
        }
        expect(tracker.isAirborne, isTrue);

        // Land
        tracker.update(_standing());
        expect(tracker.isAirborne, isFalse);
        expect(tracker.flightCount, 1);
      });

      test('larger body scale — threshold adapts via torsoHeight', () {
        final tracker = AirborneStateTracker();
        // Establish baseline with larger body (torsoHeight=0.30)
        for (var i = 0; i < 5; i++) {
          tracker.update(_standingLargeBody());
        }
        expect(tracker.baselineEstablished, isTrue);

        // Jump with rise=0.06 — for large body, threshold=0.054
        // 0.06 > 0.054 → should detect
        tracker.update(_jumpLargeBody(0.06));
        expect(tracker.isAirborne, isTrue);

        tracker.update(_standingLargeBody());
        expect(tracker.flightCount, 1);
      });

      test(
        'larger body scale — small rise below scaled threshold rejected',
        () {
          final tracker = AirborneStateTracker();
          for (var i = 0; i < 5; i++) {
            tracker.update(_standingLargeBody());
          }

          // Rise=0.04 < threshold 0.054 → should NOT trigger
          tracker.update(_jumpLargeBody(0.04));
          expect(tracker.isAirborne, isFalse);
          expect(tracker.flightCount, 0);
        },
      );
    });

    // ── NEGATIVE CASES ─────────────────────────────────────────────────────

    group('negatives', () {
      test('high knees do NOT trigger flight (one foot lifts)', () {
        final tracker = AirborneStateTracker();
        _establishBaseline(tracker);

        // High knee — left ankle rises 0.15, right stays at 0.90
        tracker.update(_highKnee());
        expect(
          tracker.isAirborne,
          isFalse,
          reason: 'One-foot lift should not trigger flight',
        );
        expect(tracker.flightCount, 0);
      });

      test('marching (alternating one-foot lifts) does NOT trigger', () {
        final tracker = AirborneStateTracker();
        _establishBaseline(tracker);

        // Left foot up
        tracker.update(_oneFootLift(0.10));
        expect(tracker.isAirborne, isFalse);
        // Left down, right up
        tracker.update(_oneFootLift(-0.10));
        expect(tracker.isAirborne, isFalse);
        expect(tracker.flightCount, 0);
      });

      test('one-foot calf raise does NOT trigger flight', () {
        final tracker = AirborneStateTracker();
        _establishBaseline(tracker);

        tracker.update(_oneFootLift(0.08));
        expect(tracker.isAirborne, isFalse);
        expect(tracker.flightCount, 0);
      });

      test('squat without leaving ground does NOT trigger', () {
        final tracker = AirborneStateTracker();
        _establishBaseline(tracker);

        tracker.update(_squat());
        expect(
          tracker.isAirborne,
          isFalse,
          reason: 'Squat keeps ankles on ground',
        );
        expect(tracker.flightCount, 0);
      });

      test('jumping jack leg spread without flight does NOT trigger', () {
        final tracker = AirborneStateTracker();
        _establishBaseline(tracker);

        tracker.update(_jumpingJackOpen());
        expect(
          tracker.isAirborne,
          isFalse,
          reason: 'Jumping jacks spread horizontally, no vertical rise',
        );
        expect(tracker.flightCount, 0);
      });

      test('missing one ankle does NOT trigger flight', () {
        final tracker = AirborneStateTracker();
        _establishBaseline(tracker);

        tracker.update(_missingLeftAnkle());
        expect(tracker.isAirborne, isFalse);
        expect(tracker.flightCount, 0);
      });

      test('missing both ankles does NOT trigger flight', () {
        final tracker = AirborneStateTracker();
        _establishBaseline(tracker);

        tracker.update(_missingBothAnkles());
        expect(tracker.isAirborne, isFalse);
        expect(tracker.flightCount, 0);
      });

      test('low-likelihood ankles are treated as missing', () {
        final tracker = AirborneStateTracker();
        _establishBaseline(tracker);

        // Ankles at jump height but likelihood=0.20 < 0.35 threshold
        tracker.update(_lowLikelihoodAnkle());
        expect(tracker.isAirborne, isFalse);
        expect(tracker.flightCount, 0);
      });

      test('pose jitter near threshold does NOT trigger', () {
        final tracker = AirborneStateTracker();
        _establishBaseline(tracker);

        // Jitter of ±0.01 — well below flight threshold 0.036
        for (var i = 0; i < 10; i++) {
          tracker.update(_jitter(i.isEven ? 0.01 : -0.01));
        }
        expect(tracker.isAirborne, isFalse);
        expect(tracker.flightCount, 0);
      });
    });

    // ── STATE / RESET CASES ────────────────────────────────────────────────

    group('state and reset', () {
      test('no flight before baseline established', () {
        final tracker = AirborneStateTracker();

        // Jump before baseline — should not count
        tracker.update(_jump(0.06));
        expect(tracker.baselineEstablished, isFalse);
        expect(tracker.isAirborne, isFalse);
        expect(tracker.flightCount, 0);
      });

      test('flight starts only after both ankles rise above threshold', () {
        final tracker = AirborneStateTracker();
        _establishBaseline(tracker);

        // Small rise (0.02) — below threshold 0.036
        tracker.update(_jump(0.02));
        expect(tracker.isAirborne, isFalse);

        // Rise above threshold
        tracker.update(_jump(0.06));
        expect(tracker.isAirborne, isTrue);
      });

      test('landing resets to grounded and increments count', () {
        final tracker = AirborneStateTracker();
        _establishBaseline(tracker);

        tracker.update(_jump(0.06));
        expect(tracker.phase, AirbornePhase.airborne);

        tracker.update(_standing());
        expect(tracker.phase, AirbornePhase.grounded);
        expect(tracker.flightCount, 1);
      });

      test('repeated jumps can be detected without count explosion', () {
        final tracker = AirborneStateTracker();
        _establishBaseline(tracker);

        // Jump held for 5 frames — should NOT count multiple flights
        for (var i = 0; i < 5; i++) {
          tracker.update(_jump(0.06));
        }
        expect(
          tracker.flightCount,
          0,
          reason: 'Airborne frames should not increment count',
        );

        // Land — single increment
        tracker.update(_standing());
        expect(tracker.flightCount, 1);
      });

      test('reset() clears all state', () {
        final tracker = AirborneStateTracker();
        _establishBaseline(tracker);

        tracker.update(_jump(0.06));
        tracker.update(_standing());
        expect(tracker.flightCount, 1);

        tracker.reset();
        expect(tracker.phase, AirbornePhase.awaitingBaseline);
        expect(tracker.baselineEstablished, isFalse);
        expect(tracker.flightCount, 0);
        expect(tracker.isAirborne, isFalse);
      });

      test('baseline does not drift rapidly upward during a jump', () {
        final tracker = AirborneStateTracker();
        _establishBaseline(tracker);
        final baselineBefore = tracker.baselineAnkleY;

        // Jump for several frames
        for (var i = 0; i < 5; i++) {
          tracker.update(_jump(0.06));
        }

        // Baseline should be frozen during airborne
        expect(
          tracker.baselineAnkleY,
          baselineBefore,
          reason: 'Baseline must not drift during airborne phase',
        );

        // Land — baseline should still be near original
        tracker.update(_standing());
        expect(
          (tracker.baselineAnkleY - baselineBefore).abs(),
          lessThan(0.01),
          reason: 'Baseline should remain stable after landing',
        );
      });

      test('baseline adapts to slow camera movement when grounded', () {
        final tracker = AirborneStateTracker();
        _establishBaseline(tracker);
        final baselineBefore = tracker.baselineAnkleY;

        // Slow camera shift over 10 frames (0.005 per frame)
        for (var i = 0; i < 10; i++) {
          tracker.update(_cameraShift(0.005 * (i + 1)));
        }

        // Baseline should have adapted (EMA with alpha=0.20)
        expect(
          tracker.baselineAnkleY,
          isNot(baselineBefore),
          reason: 'Baseline should adapt to slow camera movement',
        );
        expect(tracker.flightCount, 0);
      });
    });

    // ── THRESHOLD VERIFICATION ─────────────────────────────────────────────

    group('thresholds', () {
      test(
        'flight threshold = max(0.025, torsoHeight * 0.18) for standard body',
        () {
          // Standard body: torsoHeight = 0.20
          // threshold = max(0.025, 0.036) = 0.036
          final tracker = AirborneStateTracker();
          _establishBaseline(tracker);

          // Rise = 0.035 < 0.036 → no flight
          tracker.update(_jump(0.035));
          expect(tracker.isAirborne, isFalse);

          // Rise = 0.037 > 0.036 → flight
          tracker.update(_jump(0.037));
          expect(tracker.isAirborne, isTrue);
        },
      );

      test('min flight threshold floor applies for small torsoHeight', () {
        // Small body: torsoHeight clamped to 0.12
        // threshold = max(0.025, 0.12 * 0.18) = max(0.025, 0.0216) = 0.025
        final smallBodyStanding = _frame({
          'leftShoulder': _p(0.45, 0.40),
          'rightShoulder': _p(0.55, 0.40),
          'leftHip': _p(0.46, 0.52),
          'rightHip': _p(0.54, 0.52),
          'leftAnkle': _p(0.47, 0.90),
          'rightAnkle': _p(0.53, 0.90),
        });
        final tracker = AirborneStateTracker();
        for (var i = 0; i < 5; i++) {
          tracker.update(smallBodyStanding);
        }

        // Rise = 0.024 < floor threshold 0.025 → no flight
        // (using 0.876 to avoid floating point edge at exactly 0.025)
        final smallBodyJumpBelow = _frame({
          'leftShoulder': _p(0.45, 0.40),
          'rightShoulder': _p(0.55, 0.40),
          'leftHip': _p(0.46, 0.52),
          'rightHip': _p(0.54, 0.52),
          'leftAnkle': _p(0.47, 0.876),
          'rightAnkle': _p(0.53, 0.876),
        });

        // Rise = 0.027 > floor threshold 0.025 → flight
        final smallBodyJumpAbove = _frame({
          'leftShoulder': _p(0.45, 0.40),
          'rightShoulder': _p(0.55, 0.40),
          'leftHip': _p(0.46, 0.52),
          'rightHip': _p(0.54, 0.52),
          'leftAnkle': _p(0.47, 0.873),
          'rightAnkle': _p(0.53, 0.873),
        });

        tracker.update(smallBodyJumpBelow);
        expect(
          tracker.isAirborne,
          isFalse,
          reason: 'Rise 0.024 < threshold 0.025',
        );

        tracker.update(smallBodyJumpAbove);
        expect(
          tracker.isAirborne,
          isTrue,
          reason: 'Rise 0.027 > threshold 0.025',
        );
      });
    });
  });

  // ── FACTORY CAPABILITY INVENTORY TESTS ───────────────────────────────────

  group('FactoryPrimitive inventory', () {
    test('airDetection is registered as a factory primitive', () {
      expect(FactoryPrimitive.values, contains(FactoryPrimitive.airDetection));
    });

    test('factoryPrimitives includes airDetection', () {
      expect(factoryPrimitives, contains(FactoryPrimitive.airDetection));
    });

    test('all existing PoseSignal primitives are in the inventory', () {
      // These mirror the PoseSignal enum values from motion_validators.dart
      expect(factoryPrimitives, contains(FactoryPrimitive.hipToKneeRatio));
      expect(
        factoryPrimitives,
        contains(FactoryPrimitive.ankleWidthToBodyWidth),
      );
      expect(
        factoryPrimitives,
        contains(FactoryPrimitive.kneeSeparationToHipWidth),
      );
      expect(factoryPrimitives, contains(FactoryPrimitive.leftKneeAngle));
      expect(factoryPrimitives, contains(FactoryPrimitive.rightKneeAngle));
    });

    test('all existing BooleanPoseSignal primitives are in the inventory', () {
      expect(
        factoryPrimitives,
        contains(FactoryPrimitive.wristsAboveShoulders),
      );
      expect(factoryPrimitives, contains(FactoryPrimitive.wristsNearBody));
    });

    test('airDetection is the only temporal primitive', () {
      // airDetection is the first stateful/temporal primitive
      final temporal = factoryPrimitives.where(
        (p) => p == FactoryPrimitive.airDetection,
      );
      expect(temporal.length, 1);
    });
  });
}

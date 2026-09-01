import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/motion_v2/engine/motion_v2_math.dart';
import 'package:nuvo/features/races/ai/motion_v2/engine/nuvo_to_h36m.dart';
import 'package:nuvo/features/races/ai/motion_v2/engine/taught_motion_v2.dart';
import 'package:nuvo/features/races/ai/motion_v2/motion_v2_native_runtime.dart';
import 'package:nuvo/features/races/ai/motion_v2/pose_quality.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

import 'fixtures/pose_fixtures.dart';

/// Deterministic stand-in encoder: projects each normalized h36m frame to a
/// small embedding that reflects the skeleton's shape, so similar motions
/// produce similar embedding paths (and dissimilar ones don't). Enough to
/// exercise learn / self-validation / attempt plumbing without ONNX.
class _ShapeEncoder implements MotionEncoderV2 {
  @override
  int get dimRep => 16;

  @override
  Future<List<List<Float32List>>> encode(List<Float32List> h36mSeq) async {
    return [
      for (final row in h36mSeq)
        [
          for (var j = 0; j < kNumJoints; j++)
            Float32List.fromList(List<double>.generate(
              16,
              (k) => row[j * 3 + (k % 3)] * (1 + (k ~/ 3) * 0.3),
            )),
        ],
    ];
  }
}

typedef _Pose = NuvoPoseFrame Function();

List<NuvoPoseFrame> _seq(_Pose start, _Pose mid) {
  final t = DateTime.utc(2026, 1, 1);
  final out = <NuvoPoseFrame>[];
  var ms = 0;
  void add(_Pose p) {
    final f = p();
    out.add(NuvoPoseFrame(
      points: f.points,
      imageWidth: f.imageWidth,
      imageHeight: f.imageHeight,
      createdAt: t.add(Duration(milliseconds: ms)),
    ));
    ms += 66;
  }

  for (var i = 0; i < 5; i++) {
    add(start);
  }
  for (var i = 0; i < 8; i++) {
    add(mid);
  }
  for (var i = 0; i < 5; i++) {
    add(start);
  }
  return out;
}

void main() {
  group('PoseQuality — shared camera readiness', () {
    test('no frame -> step into frame', () {
      final q = evaluatePoseQuality(null);
      expect(q.readiness, PoseReadiness.noPerson);
      expect(q.trackable, isFalse);
      expect(q.guidance, 'Step into frame');
    });

    test('normal standing pose -> ready + trackable', () {
      final q = evaluatePoseQuality(neutralStandingPose());
      expect(q.readiness, PoseReadiness.ready);
      expect(q.trackable, isTrue);
      expect(q.missingRegions, isEmpty);
    });

    test('person fills the frame -> move back', () {
      final q = evaluatePoseQuality(neutralStandingPose(scale: 2.4));
      expect(
        q.readiness,
        anyOf(PoseReadiness.tooClose, PoseReadiness.partiallyOutOfFrame),
      );
      expect(q.guidance, anyOf('Move back', 'Move into frame'));
    });

    test('tiny distant person -> step closer', () {
      final q = evaluatePoseQuality(neutralStandingPose(scale: 0.25));
      expect(q.readiness, PoseReadiness.tooFar);
      expect(q.guidance, 'Step closer');
    });
  });

  group('Self-validation after learning', () {
    test('three consistent demos learn a spec that recognizes them', () async {
      final runtime = MotionV2NativeRuntime(encoder: _ShapeEncoder());
      final demos = [
        for (var i = 0; i < 3; i++)
          _seq(() => neutralStandingPose(), () => armsOverheadPose()),
      ];
      final spec = await runtime.learn(movementName: 'arms up', demos: demos);
      expect(spec.verifierType, 'motion_v2');
      expect(runtime.lastSelfValidation, isNotNull);
      expect(runtime.lastSelfValidation!.passed, isTrue);
      expect(runtime.lastSelfValidation!.perDemo, everyElement(isTrue));
    });

    test('self-validation report has one entry per demo', () async {
      final runtime = MotionV2NativeRuntime(encoder: _ShapeEncoder());
      final demos = [
        _seq(() => neutralStandingPose(), () => armsOverheadPose()),
        _seq(() => neutralStandingPose(), () => wavePose()),
        _seq(() => neutralStandingPose(), () => handsNearKneesPose()),
      ];
      // Whether it throws depends on the encoder's discrimination; the contract
      // under test here is that self-validation actually ran on every demo.
      // (A real-encoder inconsistency case is in tools/motion_v2/tests.)
      try {
        await runtime.learn(movementName: 'x', demos: demos);
      } on MotionV2LearnException {
        // expected for a poorly-consistent set
      }
      expect(runtime.lastSelfValidation, isNotNull);
      expect(runtime.lastSelfValidation!.perDemo, hasLength(3));
    });
  });

  group('regionActivity — generic per-region motion', () {
    test('an arm-only motion has more arm activity than leg activity', () {
      final h = framesToH36m(
        _seq(() => neutralStandingPose(), () => armsOverheadPose()),
      );
      final ra = regionActivity(h);
      expect(ra['left arm']! + ra['right arm']!,
          greaterThan(ra['left leg']! + ra['right leg']! + 1e-6));
    });
  });
}

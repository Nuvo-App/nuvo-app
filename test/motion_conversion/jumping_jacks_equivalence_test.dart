// W10 differential-equivalence test — jumping_jacks.
//
// Native: ConfigurableRepValidator(jumpingJackRepDefinition) — START when
// wrists near the body AND ankleWidth/bodyWidth < 1.18; ACTIVE when both
// wrists above shoulders AND ankleWidth/bodyWidth > 1.38; 3 stable frames
// per transition; rep = start→active→start.
//
// Remote: jumping_jacks-remote-2026.10.0.json — sequence_match_v1,
// closed (arm-elevation angle ≤80° both sides AND ankle spread ≤1.0
// shoulder widths) → open (arm angle ≥115° both AND ankle spread ≥1.35)
// → closed → complete. All predicates scale-invariant.
//
// Pose sources: parametric rig (armsUp + wide-stance override) + the app's
// own preview keyframes (jumpingJacksDemo via movementDemoForType).
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

import 'conversion_pose_kit.dart';

const _spec = 'jumping_jacks-remote-2026.10.0.json';
const _activity = AiMotionActivity.jumpingJacks;

PoseMap _open(PoseMap base) => {
      ...armsUp(base, 0.95),
      'leftAnkle': const Offset(0.30, 0.95),
      'rightAnkle': const Offset(0.70, 0.95),
      'leftKnee': const Offset(0.36, 0.77),
      'rightKnee': const Offset(0.64, 0.77),
    };

List<NuvoPoseFrame> _reps({
  required int reps,
  PoseMap Function(PoseMap)? transform,
}) {
  final closed = skeleton();
  final open = _open(closed);
  var oneRep = <(PoseMap, int)>[(closed, 4), (open, 4), (closed, 4)];
  if (transform != null) {
    oneRep = oneRep.map((e) => (transform(e.$1), e.$2)).toList();
  }
  return repCycleFrames(oneRep, reps: reps, idle: transform?.call(skeleton()));
}

void main() {
  group('jumping_jacks native vs remote', () {
    test('three clean reps count identically (parametric rig)', () {
      final r = runBoth(
        activity: _activity,
        frames: _reps(reps: 3),
        specFile: _spec,
      );
      expect(r.nativeCount, 3);
      expect(r.remoteCount, 3);
    });

    test('arms up without jumping feet wide counts nothing on either', () {
      final closed = skeleton();
      final half = armsUp(closed, 0.95);
      final frames = repCycleFrames([(closed, 4), (half, 4), (closed, 4)]);
      final r = runBoth(
        activity: _activity,
        frames: frames,
        specFile: _spec,
      );
      expect(r.nativeCount, 0);
      expect(r.remoteCount, 0);
    });

    test('feet wide without raising arms counts nothing on either', () {
      final closed = skeleton();
      final wide = {
        ...closed,
        'leftAnkle': const Offset(0.30, 0.95),
        'rightAnkle': const Offset(0.70, 0.95),
        'leftKnee': const Offset(0.36, 0.77),
        'rightKnee': const Offset(0.64, 0.77),
      };
      final frames = repCycleFrames([(closed, 4), (wide, 4), (closed, 4)]);
      final r = runBoth(
        activity: _activity,
        frames: frames,
        specFile: _spec,
      );
      expect(r.nativeCount, 0);
      expect(r.remoteCount, 0);
    });

    test('idle standing counts nothing', () {
      final r = runBoth(
        activity: _activity,
        frames: repCycleFrames([(skeleton(), 40)], reps: 1),
        specFile: _spec,
      );
      expect(r.nativeCount, 0);
      expect(r.remoteCount, 0);
    });

    test('jittered reps still count identically', () {
      final r = runBoth(
        activity: _activity,
        frames: jitterFrames(_reps(reps: 3), Random(11), 0.012),
        specFile: _spec,
      );
      expect(r.nativeCount, r.remoteCount);
      expect(r.nativeCount, 3);
    });

    for (final scale in [0.6, 1.0, 1.4]) {
      test('reps survive camera-distance scale $scale', () {
        final r = runBoth(
          activity: _activity,
          frames: _reps(
            reps: 3,
            transform: (p) => transformPose(p, scale: scale),
          ),
          specFile: _spec,
        );
        expect(r.nativeCount, 3, reason: 'native at $scale');
        expect(r.remoteCount, 3, reason: 'remote at $scale');
      });
    }

    test('reps survive a shifted frame and ±15% proportions', () {
      for (final warp in [
        (PoseMap p) => transformPose(p, dx: 0.12, dy: -0.08),
        (PoseMap p) => warpProportions(p, torso: 0.85, arms: 0.85, legs: 0.85),
        (PoseMap p) => warpProportions(p, torso: 1.15, arms: 1.15, legs: 1.15),
      ]) {
        final r = runBoth(
          activity: _activity,
          frames: _reps(reps: 3, transform: warp),
          specFile: _spec,
        );
        expect(r.remoteCount, r.nativeCount);
        expect(r.nativeCount, 3);
      }
    });

    test('preview demo keyframes agree (jumpingJacksDemo)', () {
      final keys = demoPoseMapsFor(_activity)!;
      final poses = interpolatePoses(keys, framesPerSegment: 6);
      final r = runBoth(
        activity: _activity,
        frames: framesFromPoses(poses),
        specFile: _spec,
      );
      // The differential contract is equality, whatever the demo reads —
      // the preview is a visualization aid, not a calibrated rep stream.
      expect(r.remoteCount, r.nativeCount);
    });
  });
}

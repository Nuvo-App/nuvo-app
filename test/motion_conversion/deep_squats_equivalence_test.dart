// W10 differential-equivalence test — deep_squats.
//
// Native: ConfigurableRepValidator(deepSquatRepDefinition) — START when
// hipToKneeRatio > 0.72 (standing), ACTIVE when < 0.30 (hips below the
// regular-squat band), 3 stable frames, rep = start→active→start.
//
// Remote: deep_squats-remote-2026.10.0.json — sequence_match_v1,
// standing (|knee−hip| / |shoulder−hip| ≥ 0.70 both legs) → deep (≤0.30)
// → standing → complete. The unsigned segment ratio tracks the signed
// hipToKneeRatio over the whole relevant range (the knee only passes the
// hip in Y well below the 0.30 gate).
//
// Pose sources: parametric rig (squatDepth generator) + the app's own
// preview keyframes (deepSquatsDemo via movementDemoForType).
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

import 'conversion_pose_kit.dart';

const _spec = 'deep_squats-remote-2026.10.0.json';
const _activity = AiMotionActivity.deepSquats;

List<NuvoPoseFrame> _reps({
  required int reps,
  double depth = 0.9,
  PoseMap Function(PoseMap)? transform,
}) {
  final stand = skeleton();
  final deep = squatDepth(stand, depth);
  var oneRep = <(PoseMap, int)>[(stand, 4), (deep, 4), (stand, 4)];
  if (transform != null) {
    oneRep = oneRep.map((e) => (transform(e.$1), e.$2)).toList();
  }
  return repCycleFrames(oneRep, reps: reps, idle: transform?.call(skeleton()));
}

void main() {
  group('deep_squats native vs remote', () {
    test('three clean reps count identically (parametric rig)', () {
      final r = runBoth(
        activity: _activity,
        frames: _reps(reps: 3),
        specFile: _spec,
      );
      expect(r.nativeCount, 3);
      expect(r.remoteCount, 3);
    });

    test('regular-squat depth (above the deep gate) counts nothing', () {
      // depth 0.5 → hipToKneeRatio ≈ 0.41 — a valid *regular* squat but
      // above both engines' 0.30 deep gate. This is the identity proof
      // that separates deep_squats from squats.
      final r = runBoth(
        activity: _activity,
        frames: _reps(reps: 2, depth: 0.5),
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
        frames: jitterFrames(_reps(reps: 3), Random(13), 0.012),
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
        (PoseMap p) => warpProportions(p, torso: 0.85, legs: 0.85),
        (PoseMap p) => warpProportions(p, torso: 1.15, legs: 1.15),
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

    test('preview demo keyframes agree (deepSquatsDemo)', () {
      final keys = demoPoseMapsFor(_activity)!;
      final poses = interpolatePoses(keys, framesPerSegment: 6);
      final r = runBoth(
        activity: _activity,
        frames: framesFromPoses(poses),
        specFile: _spec,
      );
      expect(r.remoteCount, r.nativeCount);
    });
  });
}

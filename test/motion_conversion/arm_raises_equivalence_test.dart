// W10 differential-equivalence test — arm_raises.
//
// Native: ArmRaisesValidator — both wrists above shoulder−0.16·torso = up,
// both wrists below shoulder+0.12·torso = down, 2 stable frames per
// transition, rep = down→up→down.
//
// Remote: arm_raises-remote-2026.10.0.json — sequence_match_v1, arm
// elevation angle (wrist→shoulder→hip) instead of raw wrist Y: down ≤85°,
// up ≥100°. Angles are translation- and scale-invariant, so the spec holds
// at any camera distance (the 0026 failure mode cannot recur).
//
// Pose sources: parametric rig (armsUp generator) + the app's own preview
// keyframes (armRaisesDemo via movementDemoForType).
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

import 'conversion_pose_kit.dart';

const _spec = 'arm_raises-remote-2026.10.0.json';
const _activity = AiMotionActivity.armRaises;

// Each rep is [start, action, start] with 4-frame holds: dwell (2) fires
// early in each block, and the ≤2 leftover frames stay inside every phase's
// break tolerance, so consecutive reps chain seamlessly — the trailing
// start pose re-arms phase 0 exactly like the native re-arm state.
List<NuvoPoseFrame> _reps({
  required int reps,
  PoseMap Function(PoseMap)? transform,
}) {
  final stand = skeleton();
  final up = armsUp(stand, 0.95);
  var oneRep = <(PoseMap, int)>[(stand, 4), (up, 4), (stand, 4)];
  if (transform != null) {
    oneRep = oneRep.map((e) => (transform(e.$1), e.$2)).toList();
  }
  return repCycleFrames(oneRep, reps: reps);
}

void main() {
  group('arm_raises native vs remote', () {
    test('three clean reps count identically (parametric rig)', () {
      final r = runBoth(
        activity: _activity,
        frames: _reps(reps: 3),
        specFile: _spec,
      );
      expect(r.nativeCount, 3);
      expect(r.remoteCount, 3);
    });

    test('half-raise (below up threshold) counts nothing on either', () {
      final stand = skeleton();
      final half = armsUp(stand, 0.5);
      // lift 0.5 → arm elevation ~92°: above remote's 85° down cap, below
      // its 110° up floor; also below native's wrist-rise gate (≈0.543 lift).
      final frames = repCycleFrames([(stand, 4), (half, 4), (stand, 4)]);
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
        frames: jitterFrames(_reps(reps: 3), Random(7), 0.012),
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
        (PoseMap p) => warpProportions(p, torso: 0.85, arms: 0.85),
        (PoseMap p) => warpProportions(p, torso: 1.15, arms: 1.15),
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

    test('preview demo keyframes agree (armRaisesDemo)', () {
      final keys = demoPoseMapsFor(_activity)!;
      final poses = interpolatePoses(keys, framesPerSegment: 6);
      final r = runBoth(
        activity: _activity,
        frames: framesFromPoses(poses),
        specFile: _spec,
      );
      // Finding: the preview relaxes to wrist≈0.22 — above the native
      // "down" gate (shoulder + 0.12·torso ≈ 0.236). The preview is a
      // visualization aid, not a validator-calibrated rep: NEITHER engine
      // counts it, which is itself a correct differential result.
      expect(r.nativeCount, r.remoteCount);
      expect(r.nativeCount, 0);
    });
  });
}

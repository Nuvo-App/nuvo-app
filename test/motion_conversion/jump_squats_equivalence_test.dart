// W10 differential-equivalence test — jump_squats.
//
// Native: MultiPhaseSequenceValidator(buildJumpSquatDefinition) —
// STANDING (hipToKneeRatio > 0.60 AND grounded) → SQUAT (< 0.58) →
// AIRBORNE (AirborneStateTracker: both ankles > 0.18·torso above a
// 4-frame seeded baseline) → LANDING (standing AND grounded); cooldown 3,
// noise grace 1.
//
// Remote: jump_squats-remote-2026.10.0.json — sequence_match_v1,
// ready (knee-hip ratio ≥0.55 AND knee angle ≥150°) → crouch (ratio ≤0.55)
// → flight (|ankle−hip|/|knee−hip| ≤1.62 — a tuck/airborne signature —
//   AND knee-hip ratio ≥0.55) → landed (ratio ≥0.60) → complete.
//
// MISSING CAPABILITY (documented): the native flight gate is a STATEFUL
// baseline delta (ankle rise vs a seeded standing baseline); the remote
// uses an instantaneous ankle-hip/knee-hip geometry ratio instead —
// scale-invariant, but a different detector. Equivalent on squat-jump
// streams; an airborne rep with knees kept very deep could read "flight"
// remotely where the native's geometry also holds — flagged for device
// validation.
//
// Pose sources: parametric rig (squatDepth + flightTuck generators) +
// the app's own preview keyframes (jumpSquatsDemo via movementDemoForType).
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

import 'conversion_pose_kit.dart';

const _spec = 'jump_squats-remote-2026.10.0.json';
const _activity = AiMotionActivity.jumpSquats;

/// One rep = crouch → flight (ankles tucked, body extended) → stand.
/// The 8-frame standing tail covers the native's full re-arm chain:
/// post-completion cooldown (3) + awaitingReset + the STANDING phase's
/// own 2-frame dwell — and the remote's finish(2)+phase0(2) re-arm.
/// The initial standing comes from repCycleFrames' idle block, which
/// also seeds the airborne baseline (4 stable frames).
List<NuvoPoseFrame> _reps({
  required int reps,
  PoseMap Function(PoseMap)? transform,
}) {
  final stand = skeleton();
  var oneRep = <(PoseMap, int)>[
    (stand, 4),
    (squatDepth(stand, 0.7), 3),
    (flightTuck(stand, 0.10), 3),
    (stand, 8),
  ];
  if (transform != null) {
    oneRep = oneRep.map((e) => (transform(e.$1), e.$2)).toList();
  }
  return repCycleFrames(oneRep, reps: reps, idle: transform?.call(skeleton()));
}

void main() {
  group('jump_squats native vs remote', () {
    test('three clean jump squats count identically (parametric rig)', () {
      final r = runBoth(
        activity: _activity,
        frames: _reps(reps: 3),
        specFile: _spec,
      );
      expect(r.nativeCount, 3);
      expect(r.remoteCount, 3);
    });

    test('squat without leaving the ground counts nothing on either', () {
      final stand = skeleton();
      final frames = repCycleFrames([
        (stand, 4),
        (squatDepth(stand, 0.7), 3),
        (stand, 8),
      ], reps: 3);
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
        frames: jitterFrames(_reps(reps: 3), Random(37), 0.010),
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

    test('preview demo keyframes: remote undercounts the demo flight', () {
      final keys = demoPoseMapsFor(_activity)!;
      final poses = interpolatePoses(keys, framesPerSegment: 6);
      final r = runBoth(
        activity: _activity,
        frames: framesFromPoses(poses),
        specFile: _spec,
      );
      // Measured on this demo: native 1, remote 0 — the keyframed "jump"
      // doesn't tuck the ankles enough for the remote's instantaneous
      // flight gate (the native's baseline-relative airborne detector
      // sees the rise). Documented in the report as the cost of losing
      // the stateful baseline feature.
      expect(r.nativeCount, 1);
      expect(r.remoteCount, lessThanOrEqualTo(r.nativeCount));
    });
  });
}

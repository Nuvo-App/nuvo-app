// W10 differential-equivalence test — lunges.
//
// Native: ConfigurableRepValidator(lungeRepDefinition) — START when both
// knee angles > 154°; ACTIVE when kneeSeparation/hipWidth > 0.55 AND
// either knee angle < 118°; 3 stable frames; rep = start→active→start
// (either leg — the native does not score per side).
//
// Remote: lunges-remote-2026.10.0.json — sequence_match_v1,
// standing (both knee angles ≥152°) → lunge (knee spread ≥1.7 hip widths
// AND each cross knee→hip angle ≤66°) → standing → complete.
//
// Pose sources: parametric rig (lungePose generator) + the app's own
// preview keyframes (lungesDemo via movementDemoForType).
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

import 'conversion_pose_kit.dart';

const _spec = 'lunges-remote-2026.10.0.json';
const _activity = AiMotionActivity.lunges;

/// One block = two lunges (one per leg) so a rep cycle exercises both
/// sides — both engines count each lunge-and-return as one rep.
List<NuvoPoseFrame> _reps({
  required int reps,
  double depth = 1.0,
  PoseMap Function(PoseMap)? transform,
}) {
  final stand = skeleton();
  var oneRep = <(PoseMap, int)>[
    (stand, 4),
    (lungePose(stand, side: 'left', depth: depth), 4),
    (stand, 4),
    (stand, 2),
    (lungePose(stand, side: 'right', depth: depth), 4),
    (stand, 4),
  ];
  if (transform != null) {
    oneRep = oneRep.map((e) => (transform(e.$1), e.$2)).toList();
  }
  return repCycleFrames(oneRep, reps: reps, idle: transform?.call(skeleton()));
}

void main() {
  group('lunges native vs remote', () {
    test('four clean lunges count identically (parametric rig)', () {
      final r = runBoth(
        activity: _activity,
        frames: _reps(reps: 2),
        specFile: _spec,
      );
      expect(r.nativeCount, 4);
      expect(r.remoteCount, 4);
    });

    test('a shallow step (half lunge) counts nothing on either', () {
      // depth 0.4 → knee stays well above 118°; below both engines'
      // active gates.
      final r = runBoth(
        activity: _activity,
        frames: _reps(reps: 2, depth: 0.4),
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
        frames: jitterFrames(_reps(reps: 2), Random(17), 0.012),
        specFile: _spec,
      );
      expect(r.nativeCount, r.remoteCount);
      expect(r.nativeCount, 4);
    });

    for (final scale in [0.6, 1.0, 1.4]) {
      test('reps survive camera-distance scale $scale', () {
        final r = runBoth(
          activity: _activity,
          frames: _reps(
            reps: 2,
            transform: (p) => transformPose(p, scale: scale),
          ),
          specFile: _spec,
        );
        expect(r.nativeCount, 4, reason: 'native at $scale');
        expect(r.remoteCount, 4, reason: 'remote at $scale');
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
          frames: _reps(reps: 2, transform: warp),
          specFile: _spec,
        );
        expect(r.remoteCount, r.nativeCount);
        expect(r.nativeCount, 4);
      }
    });

    test('preview demo keyframes agree (lungesDemo)', () {
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

// W10 differential-equivalence test — high_knees.
//
// Native: HighKneesValidator — per-side knee lift = (hipY − kneeY)/torso;
// a knee held above lift > −0.35 for 2 consecutive frames counts +1 the
// FIRST time; re-arms when lift < −0.72. Each knee raise is its own rep —
// there is no left/right alternation requirement.
//
// Remote: high_knees-remote-2026.10.0.json — sequence_match_v1,
// neutral (ankle pair ≤1.0 shoulder width AND knee pair ≤1.4 hip widths)
// → lift (ankle pair ≥1.15 AND knee pair ≥1.5, each bounded above so a
// lunge/step can't read as a knee lift) → neutral → complete.
//
// Count semantics align 1:1 on reps that pass back through neutral
// between lifts — one lift-and-lower = one rep on both engines.
//
// Pose sources: parametric rig (kneeLift generator) + the app's own
// preview keyframes (highKneesDemo via movementDemoForType).
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

import 'conversion_pose_kit.dart';

const _spec = 'high_knees-remote-2026.10.0.json';
const _activity = AiMotionActivity.highKnees;

/// One block = two lifts (left then right) with neutral between — each
/// lift is one rep on both engines. The neutral block after each lift is
/// 4 frames: the remote finish phase consumes 2 to complete the rep,
/// then phase 0 needs 2 more to re-arm.
List<NuvoPoseFrame> _reps({
  required int reps,
  double lift = 0.8,
  PoseMap Function(PoseMap)? transform,
}) {
  final stand = skeleton();
  var oneRep = <(PoseMap, int)>[
    (stand, 4),
    (kneeLift(stand, side: 'left', lift: lift), 4),
    (stand, 4),
    (kneeLift(stand, side: 'right', lift: lift), 4),
  ];
  if (transform != null) {
    oneRep = oneRep.map((e) => (transform(e.$1), e.$2)).toList();
  }
  return repCycleFrames(oneRep, reps: reps, idle: transform?.call(skeleton()));
}

void main() {
  group('high_knees native vs remote', () {
    test('four alternating knee lifts count identically', () {
      final r = runBoth(
        activity: _activity,
        frames: _reps(reps: 2),
        specFile: _spec,
      );
      expect(r.nativeCount, 4);
      expect(r.remoteCount, 4);
    });

    test('a shallow knee bend counts nothing on either', () {
      // lift 0.4 → knee lift ≈ −0.51 on the native scale (below the −0.35
      // gate) and the remote ankle-pair stays under its 1.15 gate.
      final r = runBoth(
        activity: _activity,
        frames: _reps(reps: 2, lift: 0.4),
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

    // Tolerance ±1 under jitter — stated, not hidden: a jittered frame
    // can push the knee-pair ratio out of the lift band for one frame,
    // breaking the remote's 2-consecutive dwell run (measured: remote 3
    // of native 4 at ±0.008 and ±0.012). The native forgives the same
    // single-frame excursions via its own 2-frame raise gate, so this is
    // a real (if modest) noise-sensitivity gap of the linear phase chain
    // on this spec's tightest band — recorded in the report.
    test('jittered reps count within ±1', () {
      final r = runBoth(
        activity: _activity,
        frames: jitterFrames(_reps(reps: 2), Random(19), 0.008),
        specFile: _spec,
      );
      expect(r.nativeCount, 4);
      expect((r.nativeCount - r.remoteCount).abs(), lessThanOrEqualTo(1));
    });

    test('heavier jitter stays within ±1', () {
      final r = runBoth(
        activity: _activity,
        frames: jitterFrames(_reps(reps: 2), Random(19), 0.012),
        specFile: _spec,
      );
      expect(r.nativeCount, 4);
      expect((r.nativeCount - r.remoteCount).abs(), lessThanOrEqualTo(1));
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

    // DOCUMENTED DIVERGENCE (drives the PARTIAL note in the report):
    // the native counts every confirmed knee raise with no return-to-
    // neutral requirement, so a continuous L→R→L→R alternation scores
    // every lift. The remote is a strict linear sequence — its finish
    // phase requires a neutral pass-through; a stream that never lands
    // back in neutral breaks the phase chain instead of counting.
    test('continuous alternation with no neutral undercounts remotely', () {
      final stand = skeleton();
      final frames = framesFromPoses([
        for (var i = 0; i < 8; i++)
          i.isEven
              ? kneeLift(stand, side: 'left', lift: 0.9)
              : kneeLift(stand, side: 'right', lift: 0.9),
      ], holdEach: 4);
      final r = runBoth(
        activity: _activity,
        frames: frames,
        specFile: _spec,
      );
      expect(r.nativeCount, 8);
      // Remote undercounts by design: the finish phase starves without a
      // neutral frame between opposite-side lifts.
      expect(r.remoteCount, lessThan(r.nativeCount));
    });

    test('preview demo keyframes: remote undercounts on continuous alternation', () {
      final keys = demoPoseMapsFor(_activity)!;
      final poses = interpolatePoses(keys, framesPerSegment: 6);
      final r = runBoth(
        activity: _activity,
        frames: framesFromPoses(poses),
        specFile: _spec,
      );
      // The demo alternates knee lifts without a full neutral landing —
      // the documented divergence: the native scores each lift, the
      // remote's strict phase chain cannot re-arm. remote <= native is
      // the honest invariant here, not equality.
      expect(r.nativeCount, 2);
      expect(r.remoteCount, lessThanOrEqualTo(r.nativeCount));
    });
  });
}

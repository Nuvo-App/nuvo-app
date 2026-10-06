// W10 differential-equivalence test — marching_in_place.
//
// Native: CadenceMotionValidator(marchingInPlaceDefinition) — stateful
// AlternatingGaitSignal(liftFraction 0.30): per-frame side = the knee
// pair's combined (Δx-deviation + Δy) swing past 0.30·torso;
// CadenceDetector(2) counts +1 per confirmed alternation after the
// first establishes the baseline.
//
// Remote: marching_in_place-remote-2026.10.0.json — sequence_match_v1,
// neutral (ankle pair ≤0.95 shoulder widths AND knee pair ≤1.3 hip
// widths) → lift (ankle pair ≥1.05 AND knee pair ≥1.35, bounded ≤3.0 so
// a full high-knee drive does not over-read) → neutral → complete.
//
// COUNT MAPPING: remote counts each lift-and-return cycle; native counts
// each alternation after the first → remote == native + 1 on an
// alternating stream.
//
// MISSING CAPABILITY (documented, not shipped): the native gait signal is
// *stateful* — it seeds a horizontal centre from the stream and trims a
// vertical tilt, so a static wide stance or camera lean is absorbed. The
// remote grammar has no baseline-relative feature; the spec instead gates
// on instantaneous pair ratios. Equivalent on centered streams; a user
// holding a persistently wide stance could read as "lift" remotely where
// the native baseline absorbs it — flagged for device validation.
//
// Pose sources: parametric rig only (no app preview demo) — kneeLift
// generator at 0.7 (the deliberate-lift band).
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

import 'conversion_pose_kit.dart';

const _spec = 'marching_in_place-remote-2026.10.0.json';
const _activity = AiMotionActivity.marchingInPlace;

/// One block = two deliberate knee lifts with neutral between. The
/// neutral block after each lift is 4 frames: the remote finish phase
/// consumes 2 to complete the rep, then phase 0 needs 2 more to re-arm —
/// a documented sequence_match_v1 dwell requirement.
List<NuvoPoseFrame> _reps({
  required int reps,
  double lift = 0.7,
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
  group('marching_in_place native vs remote', () {
    test('four alternating lifts: remote == native + 1', () {
      final r = runBoth(
        activity: _activity,
        frames: _reps(reps: 2),
        specFile: _spec,
      );
      expect(r.nativeCount, 3);
      expect(r.remoteCount, 4);
    });

    test('a shallow step-in-place counts nothing on either', () {
      // lift 0.25 → knee stagger ~0.07 < the native 0.09 gait gate and
      // the remote knee pair stays under its 1.35 floor.
      final r = runBoth(
        activity: _activity,
        frames: _reps(reps: 2, lift: 0.25),
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

    test('jittered reps keep the +1 mapping', () {
      final r = runBoth(
        activity: _activity,
        frames: jitterFrames(_reps(reps: 2), Random(29), 0.012),
        specFile: _spec,
      );
      expect(r.remoteCount, r.nativeCount + 1);
      expect(r.nativeCount, 3);
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
        expect(r.nativeCount, 3, reason: 'native at $scale');
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
        expect(r.remoteCount, r.nativeCount + 1);
        expect(r.nativeCount, 3);
      }
    });
  });
}

// W10 differential-equivalence test — lunge_jumps.
//
// Native: MultiPhaseSequenceValidator(buildLungeJumpDefinitions) — TWO
// parallel trackers: RIGHT_LUNGE → AIRBORNE → LEFT_LUNGE and
// LEFT_LUNGE → AIRBORNE → RIGHT_LUNGE. A rep requires the lead leg to
// SWITCH through flight; a same-side return is a wrong-phase reset.
// Lunge side identity: front knee angle < 120° + back knee angle > 160°.
//
// Remote: lunge_jumps-remote-2026.10.0.json — sequence_match_v1,
// lunge (knee spread ≥1.7 hip widths AND cross knee→hip angles ≤66°) →
// flight (|ankle−hip|/|knee−hip| ≤1.62 both legs) → landed (same lunge
// shape) → complete.
//
// MISSING CAPABILITY (the PARTIAL): the remote lunge predicates are
// side-SYMMETRIC — the grammar has no normalized way to say "the OTHER
// leg now leads" (axis_delta is raw normalized units, not body-scale
// relative, so a side gate would reintroduce the 0026 failure). A
// same-side jump therefore completes remotely but resets natively —
// quantified below. What is missing: a scale-normalized signed
// side-difference feature (e.g. axis_delta divided by a reference
// segment, or a dedicated side-identity predicate).
//
// Pose sources: parametric rig (lungePose + flightTuck generators) +
// the app's own preview keyframes (lungeJumpsDemo via movementDemoForType).
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

import 'conversion_pose_kit.dart';

const _spec = 'lunge_jumps-remote-2026.10.0.json';
const _activity = AiMotionActivity.lungeJumps;

/// Two real reps: lunge L → fly → lunge R, stand, then R → fly → L.
/// The flight pose is a legs-together mid-air tuck (feet swap at the
/// apex) — tucking in lunge shape keeps |ankle−hip|/|knee−hip| ≈ 1.9,
/// above the remote's 1.62 flight gate, while a legs-together tuck reads
/// ≈1.3 on both engines. The standing block covers the native cooldown
/// (3) + awaitingReset + the remote finish(2)/phase0(2) re-arm.
List<NuvoPoseFrame> _reps({
  PoseMap Function(PoseMap)? transform,
}) {
  final stand = skeleton();
  var blocks = <(PoseMap, int)>[
    (lungePose(stand, side: 'left'), 4),
    (flightTuck(stand, 0.10), 3),
    (lungePose(stand, side: 'right'), 4),
    (stand, 6),
    (lungePose(stand, side: 'right'), 4),
    (flightTuck(stand, 0.10), 3),
    (lungePose(stand, side: 'left'), 4),
    (stand, 6),
  ];
  if (transform != null) {
    blocks = blocks.map((e) => (transform(e.$1), e.$2)).toList();
  }
  return repCycleFrames(blocks, reps: 1, idle: transform?.call(skeleton()));
}

void main() {
  group('lunge_jumps native vs remote', () {
    test('two alternating lunge jumps count identically', () {
      final r = runBoth(
        activity: _activity,
        frames: _reps(),
        specFile: _spec,
      );
      expect(r.nativeCount, 2);
      expect(r.remoteCount, 2);
    });

    // DOCUMENTED DIVERGENCE (the PARTIAL): a same-side jump-and-land is a
    // full remote rep but a native wrong-phase reset — the side-switch is
    // what the parallel native trackers enforce and the linear remote
    // chain cannot see.
    test('same-side jump lands remotely but not natively', () {
      final stand = skeleton();
      final frames = repCycleFrames([
        (lungePose(stand, side: 'left'), 4),
        (flightTuck(stand, 0.10), 3),
        (lungePose(stand, side: 'left'), 4),
        (stand, 6),
      ], reps: 1);
      final r = runBoth(
        activity: _activity,
        frames: frames,
        specFile: _spec,
      );
      expect(r.nativeCount, 0);
      expect(r.remoteCount, 1);
    });

    test('stepping into a lunge without flight counts nothing', () {
      final stand = skeleton();
      final frames = repCycleFrames([
        (lungePose(stand, side: 'left'), 4),
        (lungePose(stand, side: 'right'), 4),
        (stand, 6),
      ], reps: 2);
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
        frames: jitterFrames(_reps(), Random(41), 0.010),
        specFile: _spec,
      );
      expect(r.nativeCount, r.remoteCount);
      expect(r.nativeCount, 2);
    });

    for (final scale in [0.6, 1.0, 1.4]) {
      test('reps survive camera-distance scale $scale', () {
        final r = runBoth(
          activity: _activity,
          frames: _reps(transform: (p) => transformPose(p, scale: scale)),
          specFile: _spec,
        );
        expect(r.nativeCount, 2, reason: 'native at $scale');
        expect(r.remoteCount, 2, reason: 'remote at $scale');
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
          frames: _reps(transform: warp),
          specFile: _spec,
        );
        expect(r.remoteCount, r.nativeCount);
        expect(r.nativeCount, 2);
      }
    });

    test('preview demo keyframes agree (lungeJumpsDemo)', () {
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

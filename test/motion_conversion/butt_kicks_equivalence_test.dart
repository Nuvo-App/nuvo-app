// W10 differential-equivalence test — butt_kicks.
//
// Native: CadenceMotionValidator(buttKicksDefinition) — per-frame side =
// the ankle that is at least 0.20·torso higher than the other while that
// side's knee stays down (thigh-down gate rejects high knees);
// CadenceDetector(2) then counts +1 per confirmed ALTERNATION — the first
// side only establishes the baseline.
//
// Remote: butt_kicks-remote-2026.10.0.json — sequence_match_v1,
// neutral (ankle pair ≤1.15 shoulder widths) → kick (ankle pair ≥1.5 AND
// knee pair ≤2.0 hip widths AND each knee still well below the hip — the
// same thigh-down gate as the native) → neutral → complete.
//
// COUNT MAPPING: remote counts each kick-and-return cycle; native counts
// each alternation after the first, so on an alternating stream
// remote == native + 1 exactly. Same-side repeats never count natively
// (no alternation) — a documented semantic, tested below.
//
// Pose sources: parametric rig only (the app ships no preview demo for
// butt kicks) — heelKick generator.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

import 'conversion_pose_kit.dart';

const _spec = 'butt_kicks-remote-2026.10.0.json';
const _activity = AiMotionActivity.buttKicks;

/// One block = two kicks (left then right) with neutral between. The
/// neutral block after each kick is 4 frames: the remote finish phase
/// consumes 2 to complete the rep, then phase 0 needs 2 more to re-arm —
/// a documented sequence_match_v1 dwell requirement.
List<NuvoPoseFrame> _reps({
  required int reps,
  double kick = 1.0,
  PoseMap Function(PoseMap)? transform,
}) {
  final stand = skeleton();
  var oneRep = <(PoseMap, int)>[
    (stand, 4),
    (heelKick(stand, side: 'left', kick: kick), 4),
    (stand, 4),
    (heelKick(stand, side: 'right', kick: kick), 4),
  ];
  if (transform != null) {
    oneRep = oneRep.map((e) => (transform(e.$1), e.$2)).toList();
  }
  return repCycleFrames(oneRep, reps: reps, idle: transform?.call(skeleton()));
}

void main() {
  group('butt_kicks native vs remote', () {
    test('four alternating heel kicks: remote == native + 1', () {
      final r = runBoth(
        activity: _activity,
        frames: _reps(reps: 2),
        specFile: _spec,
      );
      // Native alternation counter: first confirmed side is the baseline
      // and does not count → 3 of 4 kicks. Remote: 4 completed cycles.
      expect(r.nativeCount, 3);
      expect(r.remoteCount, 4);
    });

    test('a barely-lifted heel counts nothing on either', () {
      // kick 0.1 → ankle stagger ~0.03 < native 0.06 gate; remote ankle
      // pair ~1.0 < 1.5 gate.
      final r = runBoth(
        activity: _activity,
        frames: _reps(reps: 2, kick: 0.1),
        specFile: _spec,
      );
      expect(r.nativeCount, 0);
      expect(r.remoteCount, 0);
    });

    test('a high knee (thigh up) counts nothing on either', () {
      // The native's thigh-down gate and the remote's knee-below-hip
      // predicates both reject a knee raise misread as a heel kick.
      final stand = skeleton();
      final frames = repCycleFrames([
        (stand, 3),
        (kneeLift(stand, side: 'left', lift: 1.0), 4),
        (stand, 3),
        (kneeLift(stand, side: 'right', lift: 1.0), 4),
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

    test('jittered reps keep the +1 mapping', () {
      final r = runBoth(
        activity: _activity,
        frames: jitterFrames(_reps(reps: 2), Random(23), 0.012),
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

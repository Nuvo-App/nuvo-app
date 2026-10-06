// W10 differential-equivalence test — lateral_steps.
//
// Native: LateralStepsValidator — tracks the ankle-pair centre against a
// slowly-adapting EMA baseline; a centre offset beyond 0.55·hipWidth reads
// as a side, CadenceDetector(2) counts +1 per confirmed ALTERNATION after
// the first. The baseline only re-centres while near-neutral.
//
// Remote: lateral_steps-remote-2026.10.0.json — sequence_match_v1,
// neutral (ankle pair ≤1.2 shoulder widths) → wide (ankle pair ≥1.6,
// bounded ≤4.0 so a stance-width misread can't hold the phase forever)
// → neutral → complete.
//
// COUNT MAPPING: remote counts each step-out-and-back; native counts
// each direction change after the first → remote == native + 1 on an
// alternating stream. Same-direction repeats do not count natively (no
// alternation) — tested below.
//
// MISSING CAPABILITY (documented): the native keys on ankle-CENTRE
// displacement vs a rolling baseline — a stateful reference the remote
// grammar cannot express. The spec uses ankle SEPARATION instead: it
// detects the out-and-back shape of the step, equivalent while the user
// steps out and returns, but it cannot see a drift-and-hold (step right,
// stay wide) the way the baseline tracker can — flagged for device
// validation.
//
// Pose sources: parametric rig only (no app preview demo) — lateralStep
// generator.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

import 'conversion_pose_kit.dart';

const _spec = 'lateral_steps-remote-2026.10.0.json';
const _activity = AiMotionActivity.lateralSteps;

/// One block = a step out left then a step out right, each returning to
/// neutral.
List<NuvoPoseFrame> _reps({
  required int reps,
  double out = 0.22,
  PoseMap Function(PoseMap)? transform,
}) {
  final stand = skeleton();
  var oneRep = <(PoseMap, int)>[
    (stand, 3),
    (lateralStep(stand, side: 'left', out: out), 4),
    (stand, 4),
    (lateralStep(stand, side: 'right', out: out), 4),
    (stand, 3),
  ];
  if (transform != null) {
    oneRep = oneRep.map((e) => (transform(e.$1), e.$2)).toList();
  }
  return repCycleFrames(oneRep, reps: reps, idle: transform?.call(skeleton()));
}

void main() {
  group('lateral_steps native vs remote', () {
    test('four alternating side steps: remote == native + 1', () {
      final r = runBoth(
        activity: _activity,
        frames: _reps(reps: 2),
        specFile: _spec,
      );
      expect(r.nativeCount, 3);
      expect(r.remoteCount, 4);
    });

    test('a half-weight shuffle counts nothing on either', () {
      // out 0.06 → ankle centre offset ~0.03 < native 0.055 gate; remote
      // ankle pair ~1.33 < 1.6 gate.
      final r = runBoth(
        activity: _activity,
        frames: _reps(reps: 2, out: 0.06),
        specFile: _spec,
      );
      expect(r.nativeCount, 0);
      expect(r.remoteCount, 0);
    });

    test('same-direction repeats never count natively', () {
      // Stepping right, back, right, back: the remote sees two complete
      // cycles; the native alternation counter sees one side only.
      final stand = skeleton();
      final frames = repCycleFrames([
        (stand, 3),
        (lateralStep(stand, side: 'right'), 4),
        (stand, 4),
      ], reps: 2);
      final r = runBoth(
        activity: _activity,
        frames: frames,
        specFile: _spec,
      );
      expect(r.nativeCount, 0);
      expect(r.remoteCount, 2);
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
        frames: jitterFrames(_reps(reps: 2), Random(31), 0.012),
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

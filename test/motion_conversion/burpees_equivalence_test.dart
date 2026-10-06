// W10 differential-equivalence test — burpees.
//
// Native: MultiPhaseSequenceValidator(buildBurpeeDefinition) —
// STANDING (hipToKneeRatio > 0.72 AND both wrists above hip − 0.15·torso,
// i.e. hands clearly up) → DOWN (hipToKneeRatio < 0.50 AND both wrists at
// or below hip height — the crouch-and-plant) → STANDING again → +1;
// cooldown 2. Deliberately common-form: no plank or jump required.
//
// Remote: burpees-remote-2026.10.0.json — sequence_match_v1,
// standing (knee-hip ratio ≥0.68 AND arm-elevation angle ≥45°) →
// down (ratio ≤0.48 AND arm angle ≤40°) → standing → complete.
// The arm-elevation angle (wrist→shoulder→hip) is the scale-invariant
// form of the native hands-up/hands-down gates.
//
// Pose sources: parametric rig only (no app preview demo) — armsUp +
// burpeeDown generators.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

import 'conversion_pose_kit.dart';

const _spec = 'burpees-remote-2026.10.0.json';
const _activity = AiMotionActivity.burpees;

/// One rep = hands up → crouch with hands down → hands up. The trailing
/// hands-up block doubles as the next rep's standing phase.
List<NuvoPoseFrame> _reps({
  required int reps,
  PoseMap Function(PoseMap)? transform,
}) {
  final stand = skeleton();
  var oneRep = <(PoseMap, int)>[
    (armsUp(stand, 0.8), 4),
    (burpeeDown(stand), 4),
    (armsUp(stand, 0.8), 4),
  ];
  if (transform != null) {
    oneRep = oneRep.map((e) => (transform(e.$1), e.$2)).toList();
  }
  return repCycleFrames(oneRep, reps: reps, idle: transform?.call(skeleton()));
}

void main() {
  group('burpees native vs remote', () {
    test('three clean burpees count identically (parametric rig)', () {
      final r = runBoth(
        activity: _activity,
        frames: _reps(reps: 3),
        specFile: _spec,
      );
      expect(r.nativeCount, 3);
      expect(r.remoteCount, 3);
    });

    test('crouch with hands kept up counts nothing on either', () {
      // The hands-down reach is the identity of the DOWN phase on both
      // engines — a squat with hands raised is not a burpee.
      final stand = skeleton();
      final squatHandsUp = {
        ...squatDepth(stand, 0.9),
        'leftWrist': const Offset(0.30, 0.30),
        'rightWrist': const Offset(0.70, 0.30),
      };
      final frames = repCycleFrames([
        (armsUp(stand, 0.8), 4),
        (squatHandsUp, 4),
        (armsUp(stand, 0.8), 4),
      ], reps: 2);
      final r = runBoth(
        activity: _activity,
        frames: frames,
        specFile: _spec,
      );
      expect(r.nativeCount, 0);
      expect(r.remoteCount, 0);
    });

    test('hands-down crouch from arms-at-sides counts nothing', () {
      // Standing with arms at the sides never satisfies either engine's
      // standing gate, so the sequence cannot begin.
      final stand = skeleton();
      final frames = repCycleFrames([
        (stand, 4),
        (burpeeDown(stand), 4),
        (stand, 4),
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
        frames: jitterFrames(_reps(reps: 3), Random(43), 0.012),
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
  });
}

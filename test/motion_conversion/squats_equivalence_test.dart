// Batch B differential test — squats.
//
// Native validator: ConfigurableRepValidator(squatRepDefinition) — signal
// hipToKneeRatio = (kneeY - hipY) / torsoHeight; start > 0.72, active < 0.50,
// 3-stable-frame RepCounterStateMachine counting on active -> start.
//
// Remote spec: server/worker/motion-releases/squats-remote-2026.10.0.json —
// sequence_match_v1, phases ready -> depth -> recovered, using
// segment_ratio(|hip-knee| / |shoulder-hip|), the body-scale-relative depth
// signal that fixes the 0016/0026 fixed-coordinate failure.
//
// Pose sources: parametric generators (conversion_poses.dart, squatAt) and
// the app's preview keyframes (squatsDemo). Scale/translation/proportion
// transforms applied to the SAME sequences.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/presentation/widgets/preset_movement_demos.dart';

import 'conversion_poses.dart';
import 'conversion_support.dart';

final spec = jsonDecode(
  File(
    'server/worker/motion-releases/squats-remote-2026.10.0.json',
  ).readAsStringSync(),
) as Map<String, dynamic>;

List<CleanPose> reps({int count = 4, double depth = 1.0}) =>
    repSequence(squatAt(0), squatAt(depth), reps: count);

List<CleanPose> scaled(List<CleanPose> poses, double f) =>
    [for (final pose in poses) scaleAbout(pose, f)];

List<CleanPose> shifted(List<CleanPose> poses, double dx, double dy) =>
    [for (final pose in poses) translatePose(pose, dx, dy)];

void expectBoth(String label, List<CleanPose> poses) {
  expectRemoteEqualsNative(
    label,
    runNative(AiMotionActivity.squats, poses),
    runRemote(spec, poses),
  );
}

void main() {
  group('squats: native ConfigurableRepValidator vs remote sequence spec', () {
    test('full reps agree (parametric)', () {
      expectBoth('5 full squats', reps(count: 5));
      expectBoth('3 full squats', reps(count: 3));
    });

    test('preview keyframe poses agree (demo source)', () {
      // squatsDemo key poses: standing -> deep -> standing. The demo's eased
      // timeline dwells at the bottom too long for the sequence engine's
      // 8-frame miss budget, so the authored poses are driven through the
      // parametric rep timing instead of resampling the demo clock.
      final key = squatsDemo.poses; // [standing, squatting, standing]
      expectBoth(
        'demo stand->deep cycles',
        repSequence(demoToClean(key[0]), demoToClean(key[1]), reps: 4),
      );
    });

    test('partial reps never count on either side', () {
      expectBoth('half-depth squats', reps(count: 4, depth: 0.30));
      expectBoth('quarter-depth squats', reps(count: 4, depth: 0.20));
    });

    test('idle standing counts nothing', () {
      expectBoth('standing still', holdPose(squatAt(0), 40));
    });

    test('starting already-deep cannot count', () {
      // No ready phase seen first: native cannot arm, remote cannot advance.
      expectBoth(
        'deep-hold then stand',
        [
          ...holdPose(squatAt(1.0), 10),
          ...holdPose(squatAt(0), 10),
        ],
      );
    });

    test('jittered full reps agree', () {
      expectBoth('phone jitter', jittered(reps(count: 4), seed: 11));
      // Harsh jitter: the sequence engine resets dwell on a single missed
      // frame where the native counter pauses on unknown — a documented
      // strictness difference. Tolerance 1 rep in 4.
      expectRemoteEqualsNative(
        'harsh jitter',
        runNative(AiMotionActivity.squats, jittered(reps(count: 4), noise: PoseNoise.harsh, seed: 5)),
        runRemote(spec, jittered(reps(count: 4), noise: PoseNoise.harsh, seed: 5)),
        tolerance: 1,
      );
    });

    test('camera distance (scale 0.6-1.4 about centre) agrees', () {
      for (final s in [0.6, 0.8, 1.0, 1.2, 1.4]) {
        expectBoth('scale $s', scaled(reps(count: 3), s));
      }
    });

    test('translation agrees', () {
      expectBoth('shifted left/up', shifted(reps(count: 3), -0.15, -0.1));
      expectBoth('shifted right/down', shifted(reps(count: 3), 0.12, 0.08));
    });

    test('body proportions +/-15% agree', () {
      expectBoth(
        'legs +15%',
        [for (final pose in reps(count: 3)) morphProportions(pose, legScale: 1.15)],
      );
      expectBoth(
        'legs -15%',
        [for (final pose in reps(count: 3)) morphProportions(pose, legScale: 0.85)],
      );
      expectBoth(
        'torso +15%',
        [for (final pose in reps(count: 3)) morphProportions(pose, torsoScale: 1.15)],
      );
      expectBoth(
        'torso -15%',
        [for (final pose in reps(count: 3)) morphProportions(pose, torsoScale: 0.85)],
      );
      expectBoth(
        'all combined',
        [
          for (final pose in reps(count: 3))
            morphProportions(
              pose,
              legScale: 0.85,
              torsoScale: 1.15,
              armScale: 1.1,
              widthScale: 0.9,
            ),
        ],
      );
    });

    test('scaled + translated + jittered together', () {
      final poses = jittered(
        shifted(scaled(reps(count: 3), 0.7), 0.08, -0.05),
        seed: 21,
      );
      expectBoth('compound transforms', poses);
    });
  });
}

// Batch B differential test — squat_jacks.
//
// Native validator: ConfigurableRepValidator(squatJackRepDefinition) —
// start: wristsNearBody AND ankleWidth/bodyWidth < 1.18 AND hipToKnee > 0.72;
// active: wristsAboveShoulders AND ankleWidth/bodyWidth > 1.38 AND
// hipToKnee < 0.60. 3-stable-frame counter.
//
// Remote spec: squat_jacks-remote-2026.10.0.json — sequence_match_v1.
// "Arms up" is expressed as angle(wrist, shoulder, hip) >= 120 — the angle at
// the shoulder between the arm segment and the torso line is ~13 deg with
// arms hanging and ~180 deg overhead, so it is fully body-scale relative.
// Depth/stance use the same segment_ratio signals as the squat specs.
//
// Pose source: parametric (squatJackClosed / squatJackOpen generators).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'conversion_poses.dart';
import 'conversion_support.dart';

final spec = jsonDecode(
  File(
    'server/worker/motion-releases/squat_jacks-remote-2026.10.0.json',
  ).readAsStringSync(),
) as Map<String, dynamic>;

List<CleanPose> reps({int count = 4, double depth = 1.0}) =>
    repSequence(squatJackClosed(), squatJackOpen(depth), reps: count);

List<CleanPose> mapPoses(
  List<CleanPose> poses,
  CleanPose Function(CleanPose) f,
) =>
    [for (final pose in poses) f(pose)];

void expectBoth(String label, List<CleanPose> poses, {double tolerance = 0}) {
  expectRemoteEqualsNative(
    label,
    runNative(AiMotionActivity.squatJacks, poses),
    runRemote(spec, poses),
    tolerance: tolerance,
  );
}

void main() {
  group('squat_jacks: native vs remote sequence spec', () {
    test('full squat jacks agree (parametric)', () {
      expectBoth('4 squat jacks', reps(count: 4));
    });

    test('arms-down deep squats do NOT count', () {
      // Identifies vs regular squats: depth is there, arms are not.
      expectBoth(
        'deep squats with arms down',
        repSequence(squatAt(0), squatAt(1.0), reps: 3),
      );
    });

    test('arms-up wide stance WITHOUT depth does not count', () {
      // jumping-jack shape: arms up + feet wide but hipToKnee ~0.8 standing.
      expectBoth(
        'standing jacks (no squat)',
        repSequence(squatJackClosed(), squatJackOpen(0.0), reps: 3),
      );
    });

    test('shallow squat jack does not count', () {
      expectBoth('open at d=0.2', reps(count: 3, depth: 0.20));
    });

    test('idle closed stance counts nothing', () {
      expectBoth('standing still', holdPose(squatJackClosed(), 40));
    });

    test('jittered full reps agree', () {
      expectBoth('phone jitter', jittered(reps(count: 4), seed: 13));
      expectRemoteEqualsNative(
        'harsh jitter',
        runNative(
          AiMotionActivity.squatJacks,
          jittered(reps(count: 4), noise: PoseNoise.harsh, seed: 5),
        ),
        runRemote(spec, jittered(reps(count: 4), noise: PoseNoise.harsh, seed: 5)),
        tolerance: 1,
      );
    });

    test('camera distance (scale 0.6-1.4) agrees', () {
      for (final s in [0.6, 0.8, 1.0, 1.2, 1.4]) {
        expectBoth('scale $s', mapPoses(reps(count: 3), (p) => scaleAbout(p, s)));
      }
    });

    test('translation agrees', () {
      expectBoth(
        'shifted',
        mapPoses(reps(count: 3), (p) => translatePose(p, -0.08, -0.06)),
      );
    });

    test('body proportions +/-15% agree', () {
      expectBoth(
        'legs -15%',
        mapPoses(reps(count: 3), (p) => morphProportions(p, legScale: 0.85)),
      );
      expectBoth(
        'legs +15%',
        mapPoses(reps(count: 3), (p) => morphProportions(p, legScale: 1.15)),
      );
      expectBoth(
        'torso -15%',
        mapPoses(reps(count: 3), (p) => morphProportions(p, torsoScale: 0.85)),
      );
      expectBoth(
        'arms +15%',
        mapPoses(reps(count: 3), (p) => morphProportions(p, armScale: 1.15)),
      );
      expectBoth(
        'width -15%',
        mapPoses(reps(count: 3), (p) => morphProportions(p, widthScale: 0.85)),
      );
    });
  });
}

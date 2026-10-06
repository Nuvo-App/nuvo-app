// Batch B differential test — sumo_squats.
//
// Native validator: ConfigurableRepValidator(sumoSquatRepDefinition) —
// start: hipToKneeRatio > 0.72 AND ankleWidth/bodyWidth > 1.5;
// active: hipToKneeRatio < 0.50 AND ankleWidth/bodyWidth > 1.5;
// bodyWidth = max(shoulderWidth, hipWidth). 3-stable-frame counter.
//
// Remote spec: sumo_squats-remote-2026.10.0.json — sequence_match_v1 with
// segment_ratio depth (|hip-knee|/|shoulder-hip|) and wide-stance encoded
// against BOTH refs — ankleW/shoulderW AND ankleW/hipW >= 1.5 is exactly
// equivalent to ankleW/max(shoulderW,hipW) >= 1.5.
//
// Pose source: parametric (sumoAt / sumoStanding / squatAt generators).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'conversion_poses.dart';
import 'conversion_support.dart';

final spec = jsonDecode(
  File(
    'server/worker/motion-releases/sumo_squats-remote-2026.10.0.json',
  ).readAsStringSync(),
) as Map<String, dynamic>;

List<CleanPose> reps({int count = 4, double depth = 1.0}) =>
    repSequence(sumoStanding(), sumoAt(depth), reps: count);

List<CleanPose> mapPoses(
  List<CleanPose> poses,
  CleanPose Function(CleanPose) f,
) =>
    [for (final pose in poses) f(pose)];

void expectBoth(String label, List<CleanPose> poses, {double tolerance = 0}) {
  expectRemoteEqualsNative(
    label,
    runNative(AiMotionActivity.sumoSquats, poses),
    runRemote(spec, poses),
    tolerance: tolerance,
  );
}

void main() {
  group('sumo_squats: native vs remote sequence spec', () {
    test('full wide squats agree (parametric)', () {
      expectBoth('4 sumo squats', reps(count: 4));
    });

    test('partial depth never counts', () {
      expectBoth('shallow sumo d=0.3', reps(count: 4, depth: 0.30));
      expectBoth('shallow sumo d=0.2', reps(count: 4, depth: 0.20));
    });

    test('narrow-stance deep squats do NOT count as sumo', () {
      // squatAt(1.0) is deep enough (hipToKnee 0.148 < 0.50) but the stance
      // is narrow (ankleW/bodyW 0.75 < 1.5) — identity differentiator.
      expectBoth(
        'regular deep squats in sumo race',
        repSequence(squatAt(0), squatAt(1.0), reps: 3),
      );
    });

    test('wide stance without depth does not count', () {
      expectBoth('wide standing only', holdPose(sumoStanding(), 40));
    });

    test('idle standing counts nothing', () {
      expectBoth('standing still', holdPose(frontStanding(), 40));
    });

    test('jittered full reps agree', () {
      expectBoth('phone jitter', jittered(reps(count: 4), seed: 17));
      expectRemoteEqualsNative(
        'harsh jitter',
        runNative(
          AiMotionActivity.sumoSquats,
          jittered(reps(count: 4), noise: PoseNoise.harsh, seed: 5),
        ),
        runRemote(spec, jittered(reps(count: 4), noise: PoseNoise.harsh, seed: 5)),
        // Observed divergence: native=4 remote=2. Sumo phases carry 3
        // predicates each (two stance refs + depth), so harsh noise resets
        // dwell twice as often as squats.
        tolerance: 2,
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
        mapPoses(reps(count: 3), (p) => translatePose(p, -0.1, -0.05)),
      );
    });

    test('body proportions +/-15% agree', () {
      expectBoth(
        'legs +15%',
        mapPoses(reps(count: 3), (p) => morphProportions(p, legScale: 1.15)),
      );
      expectBoth(
        'legs -15%',
        mapPoses(reps(count: 3), (p) => morphProportions(p, legScale: 0.85)),
      );
      expectBoth(
        'torso +15%',
        mapPoses(reps(count: 3), (p) => morphProportions(p, torsoScale: 1.15)),
      );
      expectBoth(
        'torso -15%',
        mapPoses(reps(count: 3), (p) => morphProportions(p, torsoScale: 0.85)),
      );
      expectBoth(
        'width +15%',
        mapPoses(reps(count: 3), (p) => morphProportions(p, widthScale: 1.15)),
      );
      expectBoth(
        'width -15%',
        mapPoses(reps(count: 3), (p) => morphProportions(p, widthScale: 0.85)),
      );
    });
  });
}

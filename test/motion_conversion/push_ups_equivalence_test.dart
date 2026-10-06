// Batch B differential test — push_ups. (PARTIAL conversion)
//
// Native validator: PushupsValidator — RepCounterStateMachine with
// stableFrames=2; start = average elbow angle > 150 deg; active = elbow < 125
// deg AND shoulderDrop > 0.10 * movementScale (shoulderDrop measured against
// the ADAPTIVE _topShoulderY baseline). Gates: 6 upper-body landmarks at
// likelihood >= 0.25, average visibility >= 0.30, framing guard (all points
// inside [0.02, 0.98] margins), |left-right elbow| < 90 deg, hands below the
// shoulder line.
//
// Remote spec: push_ups-remote-2026.10.0.json — sequence_match_v1
// top -> bottom -> top_again using elbow `angle` and
// segment_ratio(|shoulder-wrist| / |shoulder-hip|) as the scale-invariant
// depth proxy.
//
// PARTIAL gaps (see B_REPORT.md): the adaptive top baseline, the framing
// guard, the asymmetry tolerance, and the hands-below gate have no predicate
// equivalent; the remote spec also requires hips for its depth reference,
// which the native treats as optional.
//
// Pose source: parametric pushupAt generator (side-view plank geometry
// following the app's push-up demo).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/presentation/widgets/preset_movement_demos.dart';

import 'conversion_poses.dart';
import 'conversion_support.dart';

final spec = jsonDecode(
  File(
    'server/worker/motion-releases/push_ups-remote-2026.10.0.json',
  ).readAsStringSync(),
) as Map<String, dynamic>;

List<CleanPose> reps({int count = 4, double bend = 1.0}) =>
    repSequence(pushupAt(0), pushupAt(bend), reps: count);

List<CleanPose> mapPoses(
  List<CleanPose> poses,
  CleanPose Function(CleanPose) f,
) =>
    [for (final pose in poses) f(pose)];

void expectBoth(String label, List<CleanPose> poses, {double tolerance = 0}) {
  expectRemoteEqualsNative(
    label,
    runNative(AiMotionActivity.pushUps, poses),
    runRemote(spec, poses),
    tolerance: tolerance,
  );
}

void main() {
  group('push_ups: native vs remote sequence spec (PARTIAL)', () {
    test('full push-ups agree (parametric)', () {
      expectBoth('4 push-ups', reps(count: 4));
    });

    test('preview keyframe poses agree (demo source)', () {
      // pushupsDemo key poses: top plank -> bottom (elbows ~90 deg) -> top.
      // Driven through parametric rep timing for the same reason as squats:
      // the eased demo timeline exceeds the sequence engine's miss budget.
      final key = pushupsDemo.poses; // [top, bottom, top]
      expectBoth(
        'demo top->bottom cycles',
        repSequence(demoToClean(key[0]), demoToClean(key[1]), reps: 4),
      );
    });

    test('partial dips never count', () {
      // elbow ~135 deg — inside the native 125..150 dead zone and above the
      // remote 120 deg bottom gate.
      expectBoth('half dip', reps(count: 4, bend: 0.42));
    });

    test('idle plank counts nothing', () {
      expectBoth('holding the top', holdPose(pushupAt(0), 40));
    });

    test('starting at the bottom cannot count', () {
      expectBoth(
        'bottom-first frames',
        [
          ...holdPose(pushupAt(1.0), 8),
          ...holdPose(pushupAt(0), 8),
        ],
      );
    });

    test('jittered full reps agree', () {
      expectBoth('phone jitter', jittered(reps(count: 4), seed: 19));
      expectRemoteEqualsNative(
        'harsh jitter',
        runNative(
          AiMotionActivity.pushUps,
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
        'shifted left',
        mapPoses(reps(count: 3), (p) => translatePose(p, -0.08, -0.05)),
      );
    });

    test('body proportions +/-15% agree', () {
      expectBoth(
        'arms +15%',
        mapPoses(reps(count: 3), (p) => morphProportions(p, armScale: 1.15)),
      );
      expectBoth(
        'arms -15%',
        mapPoses(reps(count: 3), (p) => morphProportions(p, armScale: 0.85)),
      );
      expectBoth(
        'torso +15%',
        mapPoses(reps(count: 3), (p) => morphProportions(p, torsoScale: 1.15)),
      );
      expectBoth(
        'legs -15%',
        mapPoses(reps(count: 3), (p) => morphProportions(p, legScale: 0.85)),
      );
    });

    // ── Documented PARTIAL divergence ─────────────────────────────────────
    test('gap: hips are optional for the native, required for the spec', () {
      // The remote depth reference is |shoulder-wrist|/|shoulder-hip|, so the
      // spec must list hips in requiredLandmarks; the native accepts frames
      // with no hip points at all (movementScale falls back to shoulder span).
      final noHips = [
        for (final pose in reps(count: 3))
          {
            for (final e in pose.entries)
              if (!e.key.endsWith('Hip')) e.key: e.value,
          },
      ];
      final native = runNative(AiMotionActivity.pushUps, noHips);
      final remote = runRemote(spec, noHips);
      // Quantified divergence: native still counts, remote cannot see a
      // required-landmark-complete frame.
      expect(native, greaterThan(0), reason: 'native tolerates missing hips');
      expect(remote, 0, reason: 'remote requires hips for the depth ratio');
    });
  });
}

// Batch B differential test — side_lunges. (PARTIAL conversion)
//
// Native validator: ConfigurableRepValidator(sideLungeRepDefinition) —
// start: BOTH knee angles > 154 deg; active: knee x-separation / hipWidth >
// 0.85 AND (left knee < 118 OR right knee < 118). 3-stable-frame counter.
// Camera: front view preferred; 2D x-separation is the lateral signature.
//
// Remote spec: side_lunges-remote-2026.10.0.json — sequence_match_v1
// straight -> separated -> straight_again. The straight phases reproduce the
// native start exactly (both knee `angle` predicates >= 154). The separated
// phase approximates the bend via knee-separation ratios — the DSL has no
// "either side" disjunction, so the OR of mirrored knee angles is the
// missing capability documented in B_REPORT.md.
//
// Pose source: parametric sideLunge generator (geometry follows the repo's
// own side-lunge fixture: knee ~112-117 deg, kneeSep ~2.25x hip width).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'conversion_poses.dart';
import 'conversion_support.dart';

final spec = jsonDecode(
  File(
    'server/worker/motion-releases/side_lunges-remote-2026.10.0.json',
  ).readAsStringSync(),
) as Map<String, dynamic>;

List<CleanPose> lunges({int countPerSide = 3}) {
  final out = <CleanPose>[];
  for (var i = 0; i < countPerSide; i++) {
    for (final dir in ['left', 'right']) {
      out.addAll(
        repSequence(frontStanding(), sideLunge(dir), standDwell: 4),
      );
    }
  }
  return out;
}

List<CleanPose> mapPoses(
  List<CleanPose> poses,
  CleanPose Function(CleanPose) f,
) =>
    [for (final pose in poses) f(pose)];

void expectBoth(String label, List<CleanPose> poses, {double tolerance = 0}) {
  expectRemoteEqualsNative(
    label,
    runNative(AiMotionActivity.sideLunges, poses),
    runRemote(spec, poses),
    tolerance: tolerance,
  );
}

void main() {
  group('side_lunges: native vs remote sequence spec (PARTIAL)', () {
    test('alternating side lunges agree (parametric)', () {
      expectBoth('3 left + 3 right lunges', lunges());
    });

    test('idle standing counts nothing', () {
      expectBoth('standing still', holdPose(frontStanding(), 40));
    });

    test('narrow stance with bent knees does not count', () {
      // Squat-like geometry: knees bent but x-separation below threshold.
      expectBoth(
        'narrow bent-knee dips',
        repSequence(frontStanding(), squatAt(1.0), reps: 3),
      );
    });

    test('jittered lunges agree', () {
      expectBoth('phone jitter', jittered(lunges(countPerSide: 2), seed: 23));
    });

    test('camera distance (scale 0.6-1.4) agrees', () {
      for (final s in [0.6, 0.8, 1.0, 1.2, 1.4]) {
        expectBoth(
          'scale $s',
          mapPoses(lunges(countPerSide: 2), (p) => scaleAbout(p, s)),
        );
      }
    });

    test('translation agrees', () {
      expectBoth(
        'shifted',
        mapPoses(lunges(countPerSide: 2), (p) => translatePose(p, 0.08, -0.04)),
      );
    });

    test('body proportions +/-15% agree', () {
      expectBoth(
        'legs -15%',
        mapPoses(lunges(countPerSide: 2), (p) => morphProportions(p, legScale: 0.85)),
      );
      expectBoth(
        'width +15%',
        mapPoses(lunges(countPerSide: 2), (p) => morphProportions(p, widthScale: 1.15)),
      );
      expectBoth(
        'torso -15%',
        mapPoses(lunges(countPerSide: 2), (p) => morphProportions(p, torsoScale: 0.85)),
      );
    });

    // ── Documented PARTIAL divergence ─────────────────────────────────────
    test('gap: a wide straight-leg stance satisfies separation without bend', () {
      // The native requires one knee < 118 deg; the remote spec approximates
      // the active phase by separation only, so a step-out with straight
      // legs completes the remote sequence where the native never arms.
      final poses = repSequence(frontStanding(), sumoStanding(), reps: 3);
      final native = runNative(AiMotionActivity.sideLunges, poses);
      final remote = runRemote(spec, poses);
      expect(native, 0, reason: 'no knee bend below 118 deg');
      expect(remote, greaterThan(0),
          reason: 'documented gap — the DSL cannot express the bend OR');
    });
  });
}

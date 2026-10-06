// W10 gap test — calf_raises. NO converted spec ships for this motion.
//
// Native: CalfRaisesValidator — a calf raise is a ~3-4%-of-frame rigid
// rise of the whole body: ankle Y measured against a rolling EMA baseline
// (rise > 0.07·torso = active, < 0.03·torso = re-arm), gated on extended
// knees (>150°). Baseline-relative by design: it works at any camera
// distance and framing because the threshold is a DELTA, not a position.
//
// Why no spec exists: the motion has no internal-geometry signature. The
// body rises rigidly — every segment ratio and every joint angle is
// (within noise) identical in the flat and on-toes poses. The only
// detector is "where are the ankles NOW vs where they were a second ago"
// — a TEMPORAL, baseline-relative comparison. The shipped predicate
// grammar (landmark_axis, angle, axis_delta, segment_ratio) is entirely
// instantaneous: axis_delta compares two points in the SAME frame, never
// a point against its own history.
//
// This test quantifies the gap instead of forcing a spec:
//  * the native validator keeps counting under camera-distance scale and
//    translation (its baseline makes it transform-invariant);
//  * a naive data-driven verifier — the best the current grammar can do,
//    a state_machine_v1 over raw ankle-Y thresholds, i.e. the exact 0026
//    failure mode — counts at the calibration position but silently drops
//    to zero the moment the subject is framed differently.
//
// MISSING CAPABILITY (requirement for an app release): a baseline-
// relative feature kind, e.g. `baseline_axis_delta` — "point.axis minus
// its session EMA baseline, normalized by a reference segment" with
// baseline-update policy (seed N stable frames, update only while
// grounded/down) expressed in the spec — or equivalently an
// `axis_delta`-against-rolling-baseline feature. That one primitive also
// covers the airborne gate used by jump_squats/lunge_jumps.

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/remote_verifier_runtime.dart';
import 'package:nuvo/features/races/ai/remote_verifier_spec.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

import 'conversion_pose_kit.dart';

const _activity = AiMotionActivity.calfRaises;

/// The strongest spec the shipped grammar can express: a state_machine_v1
/// over absolute ankle-Y thresholds calibrated to the reference skeleton —
/// precisely what migration 0026 reverted for being framing-fragile.
RemoteVerifierRuntime _naiveRuntime() {
  final spec = RemoteVerifierSpec.fromJson({
    'specSchemaVersion': 1,
    'releaseId': 'calf_raises-naive-gap-probe',
    'activityId': 'calf_raises',
    'engineType': 'state_machine_v1',
    'measurementType': 'repetitions',
    'requiredLandmarks': [
      'leftShoulder',
      'rightShoulder',
      'leftHip',
      'rightHip',
      'leftKnee',
      'rightKnee',
      'leftAnkle',
      'rightAnkle',
    ],
    'stableFrames': 2,
    'startRules': [
      // ankles at their calibrated resting height (0.95 in the rig)
      {'point': 'leftAnkle', 'axis': 'y', 'operator': 'gte', 'threshold': 0.93},
      {'point': 'rightAnkle', 'axis': 'y', 'operator': 'gte', 'threshold': 0.93},
    ],
    'activeRules': [
      // ankles lifted ~0.045 → on toes
      {'point': 'leftAnkle', 'axis': 'y', 'operator': 'lte', 'threshold': 0.92},
      {'point': 'rightAnkle', 'axis': 'y', 'operator': 'lte', 'threshold': 0.92},
    ],
  });
  return createRemoteVerifierRuntime(spec: spec, target: 999);
}

List<NuvoPoseFrame> _reps({
  required int reps,
  PoseMap Function(PoseMap)? transform,
}) {
  final stand = skeleton();
  var oneRep = <(PoseMap, int)>[
    (stand, 4),
    (calfRaise(stand, 1.0), 4),
    (stand, 4),
  ];
  if (transform != null) {
    oneRep = oneRep.map((e) => (transform(e.$1), e.$2)).toList();
  }
  return repCycleFrames(oneRep, reps: reps, idle: transform?.call(skeleton()));
}

int _runNaive(List<NuvoPoseFrame> frames) {
  final runtime = _naiveRuntime();
  runtime.start();
  for (final frame in frames) {
    runtime.update(frame);
  }
  return runtime.count;
}

void main() {
  group('calf_raises conversion gap (no spec shipped)', () {
    test('native counts calf raises at the calibration position', () {
      expect(runNative(_activity, _reps(reps: 3)), 3);
    });

    test('naive data-driven verifier counts ONLY at the calibration position', () {
      // Sanity: at the exact framing the thresholds were tuned for, the
      // naive verifier does count — this is what made 0016 look plausible.
      expect(_runNaive(_reps(reps: 3)), 3);
    });

    for (final scale in [0.6, 1.4]) {
      test('GAP: native still counts at scale $scale, naive verifier drops to 0', () {
        final frames = _reps(
          reps: 3,
          transform: (p) => transformPose(p, scale: scale),
        );
        final native = runNative(_activity, frames);
        final naive = _runNaive(frames);
        expect(native, 3, reason: 'native is baseline-relative');
        expect(naive, 0, reason: 'raw ankle-Y thresholds cannot track scale');
      });
    }

    test('GAP: native still counts when the subject shifts in frame, naive drops to 0', () {
      final frames = _reps(
        reps: 3,
        transform: (p) => transformPose(p, dy: 0.05),
      );
      final native = runNative(_activity, frames);
      final naive = _runNaive(frames);
      expect(native, 3);
      expect(naive, 0);
    });

    test('no instantaneous-geometry spec can see the raise', () {
      // The flat and on-toes poses are the same shape — rigid translation.
      // Every scale-invariant predicate the grammar offers evaluates
      // identically on both, so no instantaneous spec can separate them.
      final flat = skeleton();
      final toes = calfRaise(flat, 1.0);
      Offset delta(String a, String b, PoseMap p) =>
          Offset(p[a]!.dx - p[b]!.dx, p[a]!.dy - p[b]!.dy);
      for (final pair in [
        ('leftKnee', 'leftHip'),
        ('leftAnkle', 'leftKnee'),
        ('leftShoulder', 'leftHip'),
        ('leftWrist', 'leftShoulder'),
      ]) {
        final dFlat = delta(pair.$1, pair.$2, flat);
        final dToes = delta(pair.$1, pair.$2, toes);
        expect((dFlat - dToes).distance, lessThan(1e-9),
            reason: '${pair.$1}-${pair.$2} is rigid');
      }
    });
  });
}

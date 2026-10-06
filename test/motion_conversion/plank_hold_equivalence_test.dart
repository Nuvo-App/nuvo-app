// Batch B capability-gap test — plank_hold. (NO conversion)
//
// Native validator: PlankHoldValidator — accumulates held seconds while the
// body stays in a straight line: shoulder->hip->ankle collinearity checks
// (torso and shin line error vs body scale), average knee angle, camera
// orientation/framing gates, pause/resume on brief form loss.
//
// Why NO spec exists: hold_v1 accepts only raw {point, axis, operator,
// threshold 0..1} rules — no `angle`, `axis_delta`, or `segment_ratio`
// predicates on holdRules at all (the parser's _rules() only reads
// point/axis/operator/threshold), and sequence_match_v1 is repetitions-only.
// The hold's core check — hip not sagging off the shoulder-ankle LINE — is a
// collinearity test, which needs a body-relative feature that hold_v1 lacks.
//
// This file quantifies the gap: the strongest naive hold spec (fixed y-bands)
// diverges under translation exactly like migration 0026 documented.
//
// Pose source: parametric plankAt generator (side-view plank).

import 'package:flutter_test/flutter_test.dart';

import 'conversion_poses.dart';
import 'conversion_support.dart';

/// Best-effort hold spec: hips low in frame, shoulders above them — fixed
/// normalized bands (the 0016-era format).
final naiveHoldSpec = <String, dynamic>{
  'specSchemaVersion': 1,
  'releaseId': 'plank_hold-naive-gapprobe',
  'activityId': 'plank_hold',
  'engineType': 'hold_v1',
  'measurementType': 'duration',
  'requiredLandmarks': ['leftShoulder', 'leftHip', 'leftAnkle'],
  'stableFrames': 2,
  'holdRules': [
    {'point': 'leftHip', 'axis': 'y', 'operator': 'gte', 'threshold': 0.47},
    {'point': 'leftShoulder', 'axis': 'y', 'operator': 'lte', 'threshold': 0.46},
  ],
  
};

void main() {
  group('plank_hold: native hold vs best-effort naive spec (NO)', () {
    test('native accumulates held seconds on a plank', () {
      final held = runNative(
        AiMotionActivity.plankHold,
        holdPose(plankAt(), 90), // ~3s at 33ms/frame
      );
      expect(held, greaterThanOrEqualTo(2));
    });

    test('naive hold spec works at nominal framing but breaks under shift', () {
      // Nominal: hip y 0.50 >= 0.47, shoulder 0.42 <= 0.46 — the band fires.
      final nominalRemote = runRemote(naiveHoldSpec, holdPose(plankAt(), 90));
      expect(nominalRemote, greaterThanOrEqualTo(2));
      // Translate the plank up 0.15 — a person simply standing further back
      // or framing themselves higher. The native collinearity check is
      // translation-invariant; the fixed band is not.
      final shifted = holdPose(
        translatePose(plankAt(), 0, -0.15),
        90,
      );
      final shiftedNative = runNative(AiMotionActivity.plankHold, shifted);
      final shiftedRemote = runRemote(naiveHoldSpec, shifted);
      expect(shiftedNative, greaterThanOrEqualTo(2));
      expect(shiftedRemote, 0);
    });

    test('a sagging hip breaks the native hold but not the naive band', () {
      // Hip sag is the form fault the native rejects; the fixed y-band still
      // sees "hip low enough" and keeps holding — the inverse failure.
      final sagging = holdPose(plankAt(sag: 0.25), 90);
      final native = runNative(AiMotionActivity.plankHold, sagging);
      final remote = runRemote(naiveHoldSpec, sagging);
      expect(remote, greaterThanOrEqualTo(2),
          reason: 'fixed band cannot see collinearity');
      expect(native, lessThan(remote),
          reason: 'native rejects the sagging hip line');
    });
  });
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/custom_pose/custom_pose_verifier_spec.dart';
import '../../ai/motion_v2/motion_v2_models.dart';

/// Holds a custom movement the user successfully taught to Nuvo.
///
/// This is a local, in-session carrier so the learned spec can survive
/// navigation from Teach Nuvo into race creation.
class LearnedCustomMovement {
  const LearnedCustomMovement({
    this.verifierSpec,
    this.motionV2Spec,
    this.learnedAt,
  });

  /// V1 sequence-template spec — the pre-V2 race verifier format.
  final CustomPoseVerifierSpec? verifierSpec;

  /// V2 learned spec — the ONNX matcher spec of record for the race when
  /// present. Prefer it over [verifierSpec]: it's the engine that learned and
  /// live-tested the demos.
  final TaughtMotionV2Spec? motionV2Spec;
  final DateTime? learnedAt;

  /// Whichever learned spec the race should verify with — V2 when learned.
  TaughtMotionV2Spec? get preferredMotionV2Spec => motionV2Spec;

  String get movementName =>
      motionV2Spec?.movementName ?? verifierSpec?.movementName ?? '';
}

/// In-session state for the most recently learned custom movement.
///
/// `null` means no custom movement has been learned this session.
final learnedCustomMovementProvider = StateProvider<LearnedCustomMovement?>((ref) {
  return null;
});

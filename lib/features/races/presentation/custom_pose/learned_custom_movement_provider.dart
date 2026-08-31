import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/custom_pose/custom_pose_verifier_spec.dart';

/// Holds a custom movement the user successfully taught to Nuvo.
///
/// This is a local, in-session carrier so the learned spec can survive
/// navigation from Teach Nuvo into race creation.
class LearnedCustomMovement {
  const LearnedCustomMovement({
    required this.verifierSpec,
    this.learnedAt,
  });

  final CustomPoseVerifierSpec verifierSpec;
  final DateTime? learnedAt;

  String get movementName => verifierSpec.movementName;
}

/// In-session state for the most recently learned custom movement.
///
/// `null` means no custom movement has been learned this session.
final learnedCustomMovementProvider = StateProvider<LearnedCustomMovement?>((ref) {
  return null;
});

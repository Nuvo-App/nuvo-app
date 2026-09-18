import '../domain/motion_activity_catalog.dart';

/// Capabilities advertised to the Worker when a release is negotiated.
/// These are identifiers, not downloaded code. The installed app remains the
/// only place that owns executable verification logic.
class MotionCapabilities {
  const MotionCapabilities._();

  static const appBuild = String.fromEnvironment(
    'FLUTTER_BUILD_NUMBER',
    defaultValue: 'local',
  );

  static Set<String> current() => {
    'pose_landmarks_v1',
    'derived_features_v1',
    'state_machine_v1',
    'alternating_rep_v1',
    'hold_v1',
    'object_dots_v1',
    'object_composition_v1',
    for (final activity in motionActivityDefinitions)
      'native_${activity.activityId}_v1',
  };
}

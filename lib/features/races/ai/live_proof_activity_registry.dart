import '../data/ai_motion_models.dart';
import '../domain/motion_activity.dart';
import '../domain/motion_activity_catalog.dart';
import 'live_proof_models.dart';
import 'live_proof_motion_adapter.dart';
import 'motion_validators.dart';

const _kMotionValidatorVersion = 'nuvo-ai-motion-v1';

final List<LiveProofActivityDefinition> liveProofActivityDefinitions =
    motionActivityDefinitions
        .where(isCameraVerifiedMotionActivity)
        .map(_liveProofDefinitionForMotionActivity)
        .toList(growable: false);

LiveProofActivityDefinition? liveProofActivityForId(String? activityId) {
  final type = MotionActivityType.fromBackendValue(activityId);
  if (type == null) return null;
  final normalizedId = type.backendValue;
  for (final definition in liveProofActivityDefinitions) {
    if (definition.activityId == normalizedId) return definition;
  }
  return null;
}

bool isLiveProofActivity(String? activityId) =>
    liveProofActivityForId(activityId) != null;

LiveProofActivityDefinition _liveProofDefinitionForMotionActivity(
  MotionActivityDefinition activity,
) {
  return LiveProofActivityDefinition(
    activityId: activity.type.backendValue,
    title: activity.title,
    metric: activity.metric,
    unit: activity.proofLabel,
    defaultTarget: activity.defaultTarget,
    supportedFormats: activity.supportedFormats,
    requiredSignals: const {LiveProofSignalType.pose},
    validatorVersion: _kMotionValidatorVersion,
    createValidator: (config) => MotionLiveProofValidatorAdapter(
      config: config,
      motionValidator: createMotionValidator(
        AiMotionActivity.fromBackendValue(activity.type.backendValue),
        config.targetValue,
      ),
    ),
    instructions: activity.instructions,
    isHold: activity.isHold,
  );
}

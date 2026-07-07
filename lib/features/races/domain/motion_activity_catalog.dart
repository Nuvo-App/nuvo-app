import 'motion_activity.dart';

const motionActivityDefinitions = [
  MotionActivityDefinition(
    type: MotionActivityType.pushUps,
    title: 'Pushups',
    unit: 'pushups',
    defaultTarget: 10,
    aliases: ['pushups', 'push ups', 'push-up', 'push-ups'],
    proofLabel: 'pushups',
    cameraInstruction: 'Upper body front view',
  ),
  MotionActivityDefinition(
    type: MotionActivityType.jumpingJacks,
    title: 'Jumping Jacks',
    unit: 'jumping jacks',
    defaultTarget: 10,
    aliases: ['jumping jacks', 'jumping jack', 'jacks'],
    proofLabel: 'jumping jacks',
    cameraInstruction: 'Full body front view',
  ),
  MotionActivityDefinition(
    type: MotionActivityType.squats,
    title: 'Squats',
    unit: 'squats',
    defaultTarget: 10,
    aliases: ['squats', 'squat'],
    proofLabel: 'squats',
    cameraInstruction: 'Full body front view',
  ),
  MotionActivityDefinition(
    type: MotionActivityType.lunges,
    title: 'Lunges',
    unit: 'lunges',
    defaultTarget: 10,
    aliases: ['lunges', 'lunge'],
    proofLabel: 'lunges',
    cameraInstruction: 'Full body front or slight side view',
  ),
  MotionActivityDefinition(
    type: MotionActivityType.plankHold,
    title: 'Plank Hold',
    unit: 'seconds',
    defaultTarget: 20,
    isHold: true,
    aliases: ['plank hold', 'hold plank', 'plank'],
    proofLabel: 'plank hold',
    cameraInstruction: 'Side view',
  ),
];

const supportedMotionActivityTypes = {
  MotionActivityType.pushUps,
  MotionActivityType.squats,
  MotionActivityType.jumpingJacks,
  MotionActivityType.plankHold,
  MotionActivityType.lunges,
};

bool isCameraVerifiedMotionActivity(MotionActivityDefinition? definition) =>
    definition != null &&
    supportedMotionActivityTypes.contains(definition.type);

MotionActivityDefinition? motionActivityForType(MotionActivityType? type) {
  if (type == null) return null;
  for (final definition in motionActivityDefinitions) {
    if (definition.type == type) return definition;
  }
  return null;
}

MotionActivityDefinition? motionActivityForBackendValue(String? value) =>
    motionActivityForType(MotionActivityType.fromBackendValue(value));

MotionActivityDefinition? resolveRaceMotionActivity({
  String? aiActivityType,
  String? title,
  String? unit,
  String? targetUnit,
}) {
  final explicit = motionActivityForBackendValue(aiActivityType);
  if (isCameraVerifiedMotionActivity(explicit)) return explicit;

  final inferred = _inferSupportedMotionActivity([title, unit, targetUnit]);
  if (isCameraVerifiedMotionActivity(inferred)) return inferred;
  return null;
}

MotionActivityDefinition? _inferSupportedMotionActivity(
  Iterable<String?> values,
) {
  final normalized = values
      .whereType<String>()
      .join(' ')
      .toLowerCase()
      .replaceAll(RegExp(r'[-_]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (normalized.isEmpty) return null;

  if (RegExp(r'(^|[^a-z])push\s*ups?([^a-z]|$)').hasMatch(normalized) ||
      RegExp(r'(^|[^a-z])pushups?([^a-z]|$)').hasMatch(normalized)) {
    return motionActivityForType(MotionActivityType.pushUps);
  }
  if (RegExp(r'(^|[^a-z])squats?([^a-z]|$)').hasMatch(normalized)) {
    return motionActivityForType(MotionActivityType.squats);
  }
  if (RegExp(r'(^|[^a-z])jumping\s+jacks?([^a-z]|$)').hasMatch(normalized)) {
    return motionActivityForType(MotionActivityType.jumpingJacks);
  }
  if (RegExp(r'(^|[^a-z])lunges?([^a-z]|$)').hasMatch(normalized)) {
    return motionActivityForType(MotionActivityType.lunges);
  }
  if (RegExp(r'(^|[^a-z])planks?([^a-z]|$)').hasMatch(normalized)) {
    return motionActivityForType(MotionActivityType.plankHold);
  }
  return null;
}

ParsedRaceIdea parseRaceIdea(String input) {
  final normalized = input.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  final target = int.tryParse(
    RegExp(r'\d+').firstMatch(normalized)?.group(0) ?? '',
  );

  MotionActivityDefinition? matched;
  var matchedAliasLength = 0;
  for (final definition in motionActivityDefinitions) {
    for (final alias in definition.aliases) {
      final pattern = RegExp(
        r'(^|[^a-z])' + RegExp.escape(alias) + r'([^a-z]|$)',
      );
      if (pattern.hasMatch(normalized) && alias.length > matchedAliasLength) {
        matched = definition;
        matchedAliasLength = alias.length;
      }
    }
  }

  return ParsedRaceIdea(
    input: input,
    activity: matched,
    targetValue: target ?? matched?.defaultTarget ?? 1,
  );
}

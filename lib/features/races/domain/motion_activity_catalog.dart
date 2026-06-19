import 'motion_activity.dart';

const motionActivityDefinitions = [
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
    cameraInstruction: 'Full body front or slight side view',
  ),
  MotionActivityDefinition(
    type: MotionActivityType.highKnees,
    title: 'High Knees',
    unit: 'high knees',
    defaultTarget: 20,
    aliases: ['high knees', 'high knee', 'knees'],
    proofLabel: 'high knees',
    cameraInstruction: 'Full body front view',
  ),
  MotionActivityDefinition(
    type: MotionActivityType.armRaises,
    title: 'Arm Raises',
    unit: 'arm raises',
    defaultTarget: 10,
    aliases: ['arm raises', 'arm raise', 'raises'],
    proofLabel: 'arm raises',
    cameraInstruction: 'Upper/full body front view',
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

MotionActivityDefinition? motionActivityForType(MotionActivityType? type) {
  if (type == null) return null;
  for (final definition in motionActivityDefinitions) {
    if (definition.type == type) return definition;
  }
  return null;
}

MotionActivityDefinition? motionActivityForBackendValue(String? value) =>
    motionActivityForType(MotionActivityType.fromBackendValue(value));

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

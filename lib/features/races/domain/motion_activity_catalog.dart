import 'motion_activity.dart';

const motionActivityDefinitions = [
  MotionActivityDefinition(
    type: MotionActivityType.pushUps,
    title: 'Pushups',
    metric: RaceMetric.reps,
    suggestedTargets: [6, 8, 15, 25, 50, 100],
    supportedFormats: [
      RaceFormat.firstToGoal,
      RaceFormat.mostInWindow,
      RaceFormat.bestAttempt,
      RaceFormat.timedAttempt,
    ],
    aliases: ['pushups', 'push ups', 'push-up', 'push-ups'],
    proofLabel: 'pushups',
    cameraInstruction: 'Upper body front view',
    instructions: [
      'Keep your upper body and hands visible.',
      'Wait for the Ready signal.',
      'Finish each rep cleanly.',
    ],
  ),
  MotionActivityDefinition(
    type: MotionActivityType.jumpingJacks,
    title: 'Jumping Jacks',
    metric: RaceMetric.reps,
    suggestedTargets: [15, 30, 60, 100],
    supportedFormats: [
      RaceFormat.firstToGoal,
      RaceFormat.mostInWindow,
      RaceFormat.bestAttempt,
      RaceFormat.timedAttempt,
    ],
    aliases: ['jumping jacks', 'jumping jack', 'jacks'],
    proofLabel: 'jumping jacks',
    cameraInstruction: 'Full body front view',
    instructions: [
      'Keep your full body visible.',
      'Leave room above your head.',
      'Finish each rep cleanly.',
    ],
  ),
  MotionActivityDefinition(
    type: MotionActivityType.squats,
    title: 'Squats',
    metric: RaceMetric.reps,
    suggestedTargets: [10, 25, 50, 100],
    supportedFormats: [
      RaceFormat.firstToGoal,
      RaceFormat.mostInWindow,
      RaceFormat.bestAttempt,
      RaceFormat.timedAttempt,
    ],
    aliases: ['squats', 'squat'],
    proofLabel: 'squats',
    cameraInstruction: 'Full body front view',
    instructions: [
      'Keep your full body centered.',
      'Go lower.',
      'Stand tall to finish the rep.',
    ],
  ),
  MotionActivityDefinition(
    type: MotionActivityType.lunges,
    title: 'Lunges',
    metric: RaceMetric.reps,
    suggestedTargets: [10, 20, 40, 60],
    supportedFormats: [
      RaceFormat.firstToGoal,
      RaceFormat.mostInWindow,
      RaceFormat.bestAttempt,
      RaceFormat.timedAttempt,
    ],
    aliases: ['lunges', 'lunge'],
    proofLabel: 'lunges',
    cameraInstruction: 'Full body front or slight side view',
    instructions: [
      'Keep your full body visible.',
      'Step back into frame.',
      'Stand tall to finish the rep.',
    ],
  ),
  MotionActivityDefinition(
    type: MotionActivityType.plankHold,
    title: 'Plank',
    metric: RaceMetric.seconds,
    suggestedTargets: [20, 30, 60, 120, 600],
    supportedFormats: [
      RaceFormat.firstToGoal,
      RaceFormat.mostInWindow,
      RaceFormat.bestAttempt,
    ],
    isHold: true,
    aliases: ['plank hold', 'hold plank', 'plank'],
    proofLabel: 'plank hold',
    cameraInstruction: 'Side view',
    instructions: [
      'Use a side view.',
      'Keep your whole body visible.',
      'Keep your body straight.',
    ],
  ),
  MotionActivityDefinition(
    type: MotionActivityType.universalAi,
    title: 'Anything with Nuvo AI',
    metric: RaceMetric.reps,
    suggestedTargets: [3, 6, 10, 20, 50],
    supportedFormats: [
      RaceFormat.firstToGoal,
      RaceFormat.mostInWindow,
      RaceFormat.bestAttempt,
      RaceFormat.timedAttempt,
    ],
    aliases: ['nuvo ai', 'custom ai', 'anything', 'universal ai'],
    proofLabel: 'actions',
    cameraInstruction: 'Keep the action visible',
    instructions: [
      'Name the race after what Nuvo should count.',
      'Keep the action visible.',
      'Move one clean count at a time.',
    ],
  ),
];

const supportedMotionActivityTypes = {
  MotionActivityType.pushUps,
  MotionActivityType.squats,
  MotionActivityType.jumpingJacks,
  MotionActivityType.plankHold,
  MotionActivityType.lunges,
  MotionActivityType.universalAi,
};

bool isUniversalVisionMotionActivity(MotionActivityDefinition? definition) =>
    definition != null && definition.type == MotionActivityType.universalAi;

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
  if (RegExp(r'(^|[^a-z])nuvo\s+ai([^a-z]|$)').hasMatch(normalized) ||
      RegExp(r'(^|[^a-z])anything([^a-z]|$)').hasMatch(normalized)) {
    return motionActivityForType(MotionActivityType.universalAi);
  }
  return null;
}

ParsedRaceIdea parseRaceIdea(String input) {
  final normalized = input.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  final target = int.tryParse(
    RegExp(r'\d+').firstMatch(normalized)?.group(0) ?? '',
  );
  final format =
      normalized.contains('most ') ||
          normalized.contains('today') ||
          normalized.contains('weekend')
      ? RaceFormat.mostInWindow
      : normalized.contains('longest') || normalized.contains('best')
      ? RaceFormat.bestAttempt
      : normalized.contains('second') || normalized.contains('minute')
      ? RaceFormat.timedAttempt
      : RaceFormat.firstToGoal;
  final recurrence = normalized.contains('weekly')
      ? RaceRecurrence.weekly
      : normalized.contains('daily')
      ? RaceRecurrence.daily
      : RaceRecurrence.none;

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
    format: matched != null && matched.supportedFormats.contains(format)
        ? format
        : RaceFormat.firstToGoal,
    recurrence: recurrence,
    isAmbiguous:
        matched != null &&
        normalized.contains('weekly') &&
        matched.type == MotionActivityType.plankHold,
  );
}

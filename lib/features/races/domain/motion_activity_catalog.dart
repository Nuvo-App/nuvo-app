import 'package:flutter/material.dart';

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
    icon: Icons.fitness_center_rounded,
    framingLabel: 'Upper body + hands visible',
    preferredCameraView: PreferredCameraView.frontPreferred,
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
    icon: Icons.accessibility_new_rounded,
    framingLabel: 'Full body · leave room for arms',
    preferredCameraView: PreferredCameraView.frontPreferred,
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
    icon: Icons.person_outline_rounded,
    framingLabel: 'Full body centered in frame',
    preferredCameraView: PreferredCameraView.frontPreferred,
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
    icon: Icons.directions_walk_rounded,
    framingLabel: 'Full body · lower body visible',
    preferredCameraView: PreferredCameraView.frontOrSlightAngle,
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
    icon: Icons.straighten_rounded,
    framingLabel: 'Side view · full body in frame',
    preferredCameraView: PreferredCameraView.sideOrDiagonalRequired,
  ),
  MotionActivityDefinition(
    type: MotionActivityType.highKnees,
    title: 'High Knees',
    metric: RaceMetric.reps,
    suggestedTargets: [10, 20, 40, 60],
    supportedFormats: [
      RaceFormat.firstToGoal,
      RaceFormat.mostInWindow,
      RaceFormat.bestAttempt,
      RaceFormat.timedAttempt,
    ],
    aliases: ['high knees', 'high knee', 'high-knees', 'highknees'],
    proofLabel: 'high knees',
    cameraInstruction: 'Full body front view',
    instructions: [
      'Keep your full body visible.',
      'Lift each knee above your hip.',
      'Alternate legs cleanly.',
    ],
    icon: Icons.directions_run_rounded,
    framingLabel: 'Full body · lower body visible',
    preferredCameraView: PreferredCameraView.frontPreferred,
  ),
  MotionActivityDefinition(
    type: MotionActivityType.armRaises,
    title: 'Arm Raises',
    metric: RaceMetric.reps,
    suggestedTargets: [10, 20, 40, 60],
    supportedFormats: [
      RaceFormat.firstToGoal,
      RaceFormat.mostInWindow,
      RaceFormat.bestAttempt,
      RaceFormat.timedAttempt,
    ],
    aliases: ['arm raises', 'arm raise', 'arm-raises', 'armraises'],
    proofLabel: 'arm raises',
    cameraInstruction: 'Upper body front view',
    instructions: [
      'Keep your upper body and arms visible.',
      'Raise both arms above your shoulders.',
      'Lower both arms to finish the rep.',
    ],
    icon: Icons.sports_gymnastics_rounded,
    framingLabel: 'Upper body + arms visible',
    preferredCameraView: PreferredCameraView.frontPreferred,
  ),
  MotionActivityDefinition(
    type: MotionActivityType.sumoSquats,
    title: 'Sumo Squats',
    metric: RaceMetric.reps,
    suggestedTargets: [10, 20, 40, 60],
    supportedFormats: [
      RaceFormat.firstToGoal,
      RaceFormat.mostInWindow,
      RaceFormat.bestAttempt,
      RaceFormat.timedAttempt,
    ],
    aliases: ['sumo squats', 'sumo squat', 'sumo'],
    proofLabel: 'sumo squats',
    cameraInstruction: 'Full body front view',
    instructions: [
      'Stand with feet wider than shoulder width.',
      'Keep your full body centered.',
      'Go lower, stand tall to finish.',
    ],
    icon: Icons.accessibility_new_outlined,
    framingLabel: 'Full body · wide stance visible',
    preferredCameraView: PreferredCameraView.frontPreferred,
  ),
  MotionActivityDefinition(
    type: MotionActivityType.sideLunges,
    title: 'Side Lunges',
    metric: RaceMetric.reps,
    suggestedTargets: [8, 16, 30, 50],
    supportedFormats: [
      RaceFormat.firstToGoal,
      RaceFormat.mostInWindow,
      RaceFormat.bestAttempt,
      RaceFormat.timedAttempt,
    ],
    aliases: ['side lunges', 'side lunge', 'lateral lunges'],
    proofLabel: 'side lunges',
    cameraInstruction: 'Full body front view',
    instructions: [
      'Keep your full body visible.',
      'Step one leg out to the side.',
      'Stand tall to finish the rep.',
    ],
    icon: Icons.directions_walk_outlined,
    framingLabel: 'Full body · lateral space needed',
    preferredCameraView: PreferredCameraView.frontPreferred,
  ),
];

/// All preset movement types that support camera verification.
/// Derived from [motionActivityDefinitions] so the catalog is the single
/// source of truth for which movements are supported.
final Set<MotionActivityType> supportedMotionActivityTypes = {
  for (final definition in motionActivityDefinitions) definition.type,
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

  final inferred = inferSupportedMotionActivity([title, unit, targetUnit]);
  if (isCameraVerifiedMotionActivity(inferred)) return inferred;
  return null;
}

/// Infers a supported camera-verified [MotionActivityDefinition] from
/// free-text fields (title, unit, target unit). Returns null if no supported
/// movement matches.
MotionActivityDefinition? inferSupportedMotionActivity(
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
  if (RegExp(r'(^|[^a-z])high\s+knees?([^a-z]|$)').hasMatch(normalized) ||
      RegExp(r'(^|[^a-z])highknees?([^a-z]|$)').hasMatch(normalized)) {
    return motionActivityForType(MotionActivityType.highKnees);
  }
  if (RegExp(r'(^|[^a-z])arm\s+raises?([^a-z]|$)').hasMatch(normalized) ||
      RegExp(r'(^|[^a-z])armraises?([^a-z]|$)').hasMatch(normalized)) {
    return motionActivityForType(MotionActivityType.armRaises);
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

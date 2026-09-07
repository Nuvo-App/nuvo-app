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
    category: MovementCategory.upperBody,
    featured: true,
    sortPriority: 1,
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
    category: MovementCategory.cardio,
    featured: true,
    sortPriority: 3,
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
    category: MovementCategory.lowerBody,
    featured: true,
    sortPriority: 1,
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
    category: MovementCategory.lowerBody,
    featured: true,
    sortPriority: 2,
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
    category: MovementCategory.core,
    featured: false,
    sortPriority: 1,
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
    category: MovementCategory.cardio,
    featured: true,
    sortPriority: 5,
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
    category: MovementCategory.upperBody,
    featured: false,
    sortPriority: 2,
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
    category: MovementCategory.lowerBody,
    featured: false,
    sortPriority: 3,
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
    category: MovementCategory.lowerBody,
    featured: false,
    sortPriority: 4,
  ),
  MotionActivityDefinition(
    type: MotionActivityType.deepSquats,
    title: 'Deep Squats',
    metric: RaceMetric.reps,
    suggestedTargets: [8, 15, 30, 50],
    supportedFormats: [
      RaceFormat.firstToGoal,
      RaceFormat.mostInWindow,
      RaceFormat.bestAttempt,
      RaceFormat.timedAttempt,
    ],
    aliases: ['deep squats', 'deep squat', 'ass to grass', 'atg squats'],
    proofLabel: 'deep squats',
    cameraInstruction: 'Full body front view',
    instructions: [
      'Keep your full body centered.',
      'Squat below parallel — hips below knees.',
      'Stand tall to finish the rep.',
    ],
    icon: Icons.accessibility_new_rounded,
    framingLabel: 'Full body centered · room to squat deep',
    preferredCameraView: PreferredCameraView.frontPreferred,
    category: MovementCategory.lowerBody,
    featured: false,
    sortPriority: 5,
  ),
  MotionActivityDefinition(
    type: MotionActivityType.squatJacks,
    title: 'Squat Jacks',
    metric: RaceMetric.reps,
    suggestedTargets: [8, 15, 30, 50],
    supportedFormats: [
      RaceFormat.firstToGoal,
      RaceFormat.mostInWindow,
      RaceFormat.bestAttempt,
      RaceFormat.timedAttempt,
    ],
    aliases: ['squat jacks', 'squat jack', 'squatting jacks'],
    proofLabel: 'squat jacks',
    cameraInstruction: 'Full body front view',
    instructions: [
      'Keep your full body visible.',
      'Jump feet wide and squat down, arms up.',
      'Return to standing with feet together.',
    ],
    icon: Icons.accessibility_new_rounded,
    framingLabel: 'Full body · lateral space needed',
    preferredCameraView: PreferredCameraView.frontPreferred,
    category: MovementCategory.lowerBody,
    featured: false,
    sortPriority: 6,
  ),
  MotionActivityDefinition(
    type: MotionActivityType.jumpSquats,
    title: 'Jump Squats',
    metric: RaceMetric.reps,
    suggestedTargets: [8, 15, 30, 50],
    supportedFormats: [
      RaceFormat.firstToGoal,
      RaceFormat.mostInWindow,
      RaceFormat.bestAttempt,
      RaceFormat.timedAttempt,
    ],
    aliases: ['jump squats', 'jump squat', 'plyometric squats', 'squat jumps'],
    proofLabel: 'jump squats',
    cameraInstruction: 'Full body front view',
    instructions: [
      'Keep your full body visible.',
      'Squat down, then jump explosively upward.',
      'Land softly and stand tall to finish.',
    ],
    icon: Icons.accessibility_new_rounded,
    framingLabel: 'Full body · room to jump',
    preferredCameraView: PreferredCameraView.frontPreferred,
    category: MovementCategory.lowerBody,
    featured: false,
    sortPriority: 7,
  ),
  MotionActivityDefinition(
    type: MotionActivityType.lungeJumps,
    title: 'Lunge Jumps',
    metric: RaceMetric.reps,
    suggestedTargets: [8, 15, 30, 50],
    supportedFormats: [
      RaceFormat.firstToGoal,
      RaceFormat.mostInWindow,
      RaceFormat.bestAttempt,
      RaceFormat.timedAttempt,
    ],
    aliases: ['lunge jumps', 'lunge jump', 'jumping lunges', 'split jumps'],
    proofLabel: 'lunge jumps',
    cameraInstruction: 'Full body front or slight side view',
    instructions: [
      'Keep your full body visible.',
      'Lunge forward, then jump and switch legs in the air.',
      'Land in the opposite lunge to finish the rep.',
    ],
    icon: Icons.directions_walk_rounded,
    framingLabel: 'Full body · lateral space needed',
    preferredCameraView: PreferredCameraView.frontOrSlightAngle,
    category: MovementCategory.lowerBody,
    featured: false,
    sortPriority: 8,
  ),
  MotionActivityDefinition(
    type: MotionActivityType.runningInPlace,
    goalPromptOverride: 'How many steps?',
    displayUnitOverride: 'steps',
    title: 'Running in Place',
    metric: RaceMetric.reps,
    suggestedTargets: [50, 100, 200, 400],
    supportedFormats: [
      RaceFormat.firstToGoal,
      RaceFormat.mostInWindow,
      RaceFormat.bestAttempt,
      RaceFormat.timedAttempt,
    ],
    aliases: ['running in place', 'run in place', 'running'],
    proofLabel: 'running in place',
    cameraInstruction: 'Lower body front view',
    instructions: [
      'Keep your lower body visible.',
      'Alternate knees at a running cadence.',
      'Stay roughly in place.',
    ],
    icon: Icons.directions_run_rounded,
    framingLabel: 'Lower body visible',
    preferredCameraView: PreferredCameraView.frontPreferred,
    category: MovementCategory.cardio,
    featured: true,
    sortPriority: 4,
  ),
  MotionActivityDefinition(
    type: MotionActivityType.treadmillRunning,
    // Distance goal: targets are METRES (0.25 mi, 0.5 mi, 1 mi, 2 mi, 5 km).
    measurementType: MotionMeasurementType.distance,
    goalPromptOverride: 'How far?',
    title: 'Treadmill Running',
    metric: RaceMetric.reps,
    suggestedTargets: [402, 805, 1609, 3219, 5000],
    supportedFormats: [
      RaceFormat.firstToGoal,
      RaceFormat.mostInWindow,
      RaceFormat.bestAttempt,
      RaceFormat.timedAttempt,
    ],
    aliases: ['treadmill running', 'treadmill', 'running on treadmill'],
    proofLabel: 'treadmill running',
    cameraInstruction: 'Lower body front view',
    instructions: [
      'Keep your lower body visible.',
      'Nuvo estimates your distance from how you run.',
      'Camera stays fixed on you as you run.',
    ],
    icon: Icons.directions_run_rounded,
    framingLabel: 'Lower body visible',
    preferredCameraView: PreferredCameraView.frontPreferred,
    category: MovementCategory.cardio,
    featured: false,
    sortPriority: 5,
  ),
  MotionActivityDefinition(
    type: MotionActivityType.walkingInPlace,
    goalPromptOverride: 'How many steps?',
    displayUnitOverride: 'steps',
    title: 'Walking in Place',
    metric: RaceMetric.reps,
    suggestedTargets: [40, 80, 150, 300],
    supportedFormats: [
      RaceFormat.firstToGoal,
      RaceFormat.mostInWindow,
      RaceFormat.bestAttempt,
      RaceFormat.timedAttempt,
    ],
    aliases: ['walking in place', 'walk in place', 'walking'],
    proofLabel: 'walking in place',
    cameraInstruction: 'Lower body front view',
    instructions: [
      'Keep your lower body visible.',
      'Step in place, alternating feet.',
      'Stay roughly in place.',
    ],
    icon: Icons.directions_walk_rounded,
    framingLabel: 'Lower body visible',
    preferredCameraView: PreferredCameraView.frontPreferred,
    category: MovementCategory.lowerBody,
    featured: false,
    sortPriority: 9,
  ),
  MotionActivityDefinition(
    type: MotionActivityType.marchingInPlace,
    goalPromptOverride: 'How many steps?',
    displayUnitOverride: 'steps',
    title: 'Marching in Place',
    metric: RaceMetric.reps,
    suggestedTargets: [40, 80, 150, 300],
    supportedFormats: [
      RaceFormat.firstToGoal,
      RaceFormat.mostInWindow,
      RaceFormat.bestAttempt,
      RaceFormat.timedAttempt,
    ],
    aliases: ['marching in place', 'march in place', 'marching'],
    proofLabel: 'marching in place',
    cameraInstruction: 'Lower body front view',
    instructions: [
      'Keep your lower body visible.',
      'Lift each knee up high, alternating sides.',
      'Stay roughly in place.',
    ],
    icon: Icons.directions_walk_rounded,
    framingLabel: 'Lower body visible',
    preferredCameraView: PreferredCameraView.frontPreferred,
    category: MovementCategory.lowerBody,
    featured: false,
    sortPriority: 10,
  ),
  MotionActivityDefinition(
    type: MotionActivityType.buttKicks,
    goalPromptOverride: 'How many kicks?',
    displayUnitOverride: 'kicks',
    title: 'Butt Kicks',
    metric: RaceMetric.reps,
    suggestedTargets: [20, 40, 80, 150],
    supportedFormats: [
      RaceFormat.firstToGoal,
      RaceFormat.mostInWindow,
      RaceFormat.bestAttempt,
      RaceFormat.timedAttempt,
    ],
    aliases: ['butt kicks', 'butt kick', 'heel kicks', 'glute kicks'],
    proofLabel: 'butt kicks',
    cameraInstruction: 'Lower body front view',
    instructions: [
      'Keep your lower body visible.',
      'Kick your heels back toward your glutes.',
      'Alternate sides.',
    ],
    icon: Icons.bolt_rounded,
    framingLabel: 'Lower body visible',
    preferredCameraView: PreferredCameraView.frontPreferred,
    category: MovementCategory.lowerBody,
    featured: false,
    sortPriority: 11,
  ),
  MotionActivityDefinition(
    type: MotionActivityType.mountainClimbers,
    title: 'Mountain Climbers',
    metric: RaceMetric.reps,
    suggestedTargets: [20, 40, 80, 150],
    supportedFormats: [
      RaceFormat.firstToGoal,
      RaceFormat.mostInWindow,
      RaceFormat.bestAttempt,
      RaceFormat.timedAttempt,
    ],
    aliases: ['mountain climbers', 'mountain climber', 'climbers'],
    proofLabel: 'mountain climbers',
    cameraInstruction: 'Full body front view',
    instructions: [
      'Keep your full body visible.',
      'Hands planted, drive your knees in one at a time.',
      'Alternate sides.',
    ],
    icon: Icons.terrain_rounded,
    framingLabel: 'Full body · hands planted',
    preferredCameraView: PreferredCameraView.frontPreferred,
    category: MovementCategory.fullBody,
    featured: true,
    sortPriority: 2,
  ),
  MotionActivityDefinition(
    type: MotionActivityType.burpees,
    title: 'Burpees',
    metric: RaceMetric.reps,
    suggestedTargets: [5, 10, 20, 40],
    supportedFormats: [
      RaceFormat.firstToGoal,
      RaceFormat.mostInWindow,
      RaceFormat.bestAttempt,
      RaceFormat.timedAttempt,
    ],
    aliases: ['burpees', 'burpee'],
    proofLabel: 'burpees',
    cameraInstruction: 'Full body front view',
    instructions: [
      'Keep your full body visible.',
      'Crouch down with hands toward the floor.',
      'Stand tall to finish the rep.',
    ],
    icon: Icons.whatshot_rounded,
    framingLabel: 'Full body centered in frame',
    preferredCameraView: PreferredCameraView.frontPreferred,
    category: MovementCategory.fullBody,
    featured: true,
    sortPriority: 1,
  ),
  MotionActivityDefinition(
    type: MotionActivityType.stepUps,
    goalPromptOverride: 'How many step-ups?',
    displayUnitOverride: 'step-ups',
    title: 'Step-Ups',
    metric: RaceMetric.reps,
    suggestedTargets: [20, 40, 80, 150],
    supportedFormats: [
      RaceFormat.firstToGoal,
      RaceFormat.mostInWindow,
      RaceFormat.bestAttempt,
      RaceFormat.timedAttempt,
    ],
    aliases: ['step ups', 'step-ups', 'step up'],
    proofLabel: 'step-ups',
    cameraInstruction: 'Lower body front view',
    instructions: [
      'Keep your lower body visible.',
      'Step up and alternate legs.',
      'Stay roughly in place.',
    ],
    icon: Icons.stairs_rounded,
    framingLabel: 'Lower body visible',
    preferredCameraView: PreferredCameraView.frontPreferred,
    category: MovementCategory.lowerBody,
    featured: false,
    sortPriority: 12,
  ),
  MotionActivityDefinition(
    type: MotionActivityType.calfRaises,
    title: 'Calf Raises',
    metric: RaceMetric.reps,
    suggestedTargets: [15, 25, 50, 100],
    supportedFormats: [
      RaceFormat.firstToGoal,
      RaceFormat.mostInWindow,
      RaceFormat.bestAttempt,
      RaceFormat.timedAttempt,
    ],
    aliases: ['calf raises', 'calf raise', 'heel raises'],
    proofLabel: 'calf raises',
    cameraInstruction: 'Lower body front view',
    instructions: [
      'Keep your lower body visible.',
      'Rise onto your toes, then lower fully.',
      'Keep your knees straight.',
    ],
    icon: Icons.height_rounded,
    framingLabel: 'Lower body visible',
    preferredCameraView: PreferredCameraView.frontPreferred,
    category: MovementCategory.lowerBody,
    featured: false,
    sortPriority: 13,
  ),
  MotionActivityDefinition(
    type: MotionActivityType.lateralSteps,
    goalPromptOverride: 'How many side steps?',
    displayUnitOverride: 'steps',
    title: 'Lateral Steps',
    metric: RaceMetric.reps,
    suggestedTargets: [20, 40, 80, 150],
    supportedFormats: [
      RaceFormat.firstToGoal,
      RaceFormat.mostInWindow,
      RaceFormat.bestAttempt,
      RaceFormat.timedAttempt,
    ],
    aliases: ['lateral steps', 'side steps', 'side step', 'lateral step'],
    proofLabel: 'lateral steps',
    cameraInstruction: 'Full body front view',
    instructions: [
      'Keep your full body visible.',
      'Step side to side, alternating directions.',
      'Take a deliberate step, not a small shuffle.',
    ],
    icon: Icons.swap_horiz_rounded,
    framingLabel: 'Full body visible',
    preferredCameraView: PreferredCameraView.frontPreferred,
    category: MovementCategory.lowerBody,
    featured: false,
    sortPriority: 14,
  ),
];

/// All preset movement types that support camera verification.
/// Derived from [motionActivityDefinitions] so the catalog is the single
/// source of truth for which movements are supported.
final Set<MotionActivityType> supportedMotionActivityTypes = {
  for (final definition in motionActivityDefinitions) definition.type,
};

/// Movements marked `featured: true`, sorted by [sortPriority].
/// These appear in the "Popular" row of the picker.
final List<MotionActivityDefinition> featuredActivities = [
  for (final d in motionActivityDefinitions)
    if (d.featured) d,
]..sort((a, b) => a.sortPriority.compareTo(b.sortPriority));

/// All movements sorted by [sortPriority] within their category,
/// then categories in enum order.
final List<MotionActivityDefinition> sortedActivities = [
  ...motionActivityDefinitions,
]..sort((a, b) {
    final catCompare =
        a.category.index.compareTo(b.category.index);
    if (catCompare != 0) return catCompare;
    return a.sortPriority.compareTo(b.sortPriority);
  });

/// Movements in a specific category, sorted by [sortPriority].
List<MotionActivityDefinition> activitiesByCategory(
  MovementCategory category,
) {
  final result = [
    for (final d in motionActivityDefinitions)
      if (d.category == category) d,
  ];
  result.sort((a, b) => a.sortPriority.compareTo(b.sortPriority));
  return result;
}

/// Categories that have at least one movement.
List<MovementCategory> get activeCategories {
  final seen = <MovementCategory>{};
  for (final d in motionActivityDefinitions) {
    seen.add(d.category);
  }
  // Return in enum order
  return MovementCategory.values.where((c) => seen.contains(c)).toList();
}

/// Searches movements by title or aliases. Case-insensitive.
/// Returns matches sorted by [sortPriority].
List<MotionActivityDefinition> searchActivities(String query) {
  final normalized = query.toLowerCase().trim();
  if (normalized.isEmpty) return sortedActivities;
  final matches = <MotionActivityDefinition>[];
  for (final d in motionActivityDefinitions) {
    if (d.title.toLowerCase().contains(normalized)) {
      matches.add(d);
      continue;
    }
    for (final alias in d.aliases) {
      if (alias.toLowerCase().contains(normalized)) {
        matches.add(d);
        break;
      }
    }
  }
  matches.sort((a, b) => a.sortPriority.compareTo(b.sortPriority));
  return matches;
}

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
  if (RegExp(r'(^|[^a-z])treadmill([^a-z]|$)').hasMatch(normalized)) {
    return motionActivityForType(MotionActivityType.treadmillRunning);
  }
  if (RegExp(r'(^|[^a-z])running\s+in\s+place([^a-z]|$)').hasMatch(normalized) ||
      RegExp(r'(^|[^a-z])run\s+in\s+place([^a-z]|$)').hasMatch(normalized)) {
    return motionActivityForType(MotionActivityType.runningInPlace);
  }
  if (RegExp(r'(^|[^a-z])walking\s+in\s+place([^a-z]|$)').hasMatch(normalized) ||
      RegExp(r'(^|[^a-z])walk\s+in\s+place([^a-z]|$)').hasMatch(normalized)) {
    return motionActivityForType(MotionActivityType.walkingInPlace);
  }
  if (RegExp(r'(^|[^a-z])marching([^a-z]|$)').hasMatch(normalized) ||
      RegExp(r'(^|[^a-z])march\s+in\s+place([^a-z]|$)').hasMatch(normalized)) {
    return motionActivityForType(MotionActivityType.marchingInPlace);
  }
  if (RegExp(r'(^|[^a-z])butt\s+kicks?([^a-z]|$)').hasMatch(normalized)) {
    return motionActivityForType(MotionActivityType.buttKicks);
  }
  if (RegExp(r'(^|[^a-z])mountain\s+climbers?([^a-z]|$)').hasMatch(normalized)) {
    return motionActivityForType(MotionActivityType.mountainClimbers);
  }
  if (RegExp(r'(^|[^a-z])burpees?([^a-z]|$)').hasMatch(normalized)) {
    return motionActivityForType(MotionActivityType.burpees);
  }
  if (RegExp(r'(^|[^a-z])step\s*-?\s*ups?([^a-z]|$)').hasMatch(normalized)) {
    return motionActivityForType(MotionActivityType.stepUps);
  }
  if (RegExp(r'(^|[^a-z])calf\s+raises?([^a-z]|$)').hasMatch(normalized)) {
    return motionActivityForType(MotionActivityType.calfRaises);
  }
  if (RegExp(r'(^|[^a-z])lateral\s+steps?([^a-z]|$)').hasMatch(normalized) ||
      RegExp(r'(^|[^a-z])side\s+steps?([^a-z]|$)').hasMatch(normalized)) {
    return motionActivityForType(MotionActivityType.lateralSteps);
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

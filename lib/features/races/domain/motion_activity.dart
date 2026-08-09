import 'package:flutter/material.dart';

/// Camera framing preference for a preset movement.
enum PreferredCameraView {
  frontPreferred,
  frontOrSlightAngle,
  sideOrDiagonalRequired,
}

enum MotionActivityType {
  pushUps('push_ups'),
  jumpingJacks('jumping_jacks'),
  squats('squats'),
  lunges('lunges'),
  highKnees('high_knees'),
  armRaises('arm_raises'),
  plankHold('plank_hold'),
  sumoSquats('sumo_squats'),
  sideLunges('side_lunges');

  const MotionActivityType(this.backendValue);

  final String backendValue;

  static MotionActivityType? fromBackendValue(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == 'pushups' || normalized == 'push ups') {
      return MotionActivityType.pushUps;
    }
    if (normalized == 'lunge') return MotionActivityType.lunges;
    if (normalized == 'plank') return MotionActivityType.plankHold;
    if (normalized == 'sumo squat') return MotionActivityType.sumoSquats;
    if (normalized == 'side lunge') return MotionActivityType.sideLunges;
    for (final type in MotionActivityType.values) {
      if (type.backendValue == normalized) return type;
    }
    return null;
  }
}

enum RaceMetric {
  reps('reps', 'reps'),
  seconds('seconds', 'seconds');

  const RaceMetric(this.backendValue, this.label);

  final String backendValue;
  final String label;

  static RaceMetric? fromBackendValue(String? value) {
    return switch (value) {
      'reps' || 'rep' => RaceMetric.reps,
      'seconds' || 'second' || 'sec' => RaceMetric.seconds,
      _ => null,
    };
  }
}

enum RaceFormat {
  firstToGoal('first_to_goal', 'First to the goal'),
  mostInWindow('most_in_window', 'Most before time runs out'),
  bestAttempt('best_attempt', 'Best single attempt'),
  timedAttempt('timed_attempt', 'Timed race');

  const RaceFormat(this.backendValue, this.label);

  final String backendValue;
  final String label;
}

enum RaceRecurrence {
  none('none', 'One time'),
  daily('daily', 'Daily'),
  weekly('weekly', 'Weekly');

  const RaceRecurrence(this.backendValue, this.label);

  final String backendValue;
  final String label;
}

/// Broad browsing categories for the movement picker.
/// A movement has one primary category even if it involves multiple
/// body parts. Keep categories broad — do not create narrow taxonomies.
enum MovementCategory {
  upperBody('Upper Body'),
  lowerBody('Lower Body'),
  cardio('Cardio'),
  core('Core'),
  fullBody('Full Body');

  const MovementCategory(this.label);

  final String label;
}

class MotionActivityDefinition {
  const MotionActivityDefinition({
    required this.type,
    required this.title,
    required this.metric,
    required this.suggestedTargets,
    required this.supportedFormats,
    required this.aliases,
    required this.proofLabel,
    required this.cameraInstruction,
    required this.instructions,
    required this.icon,
    required this.framingLabel,
    required this.preferredCameraView,
    required this.category,
    this.isHold = false,
    this.featured = false,
    this.sortPriority = 100,
  });

  final MotionActivityType type;
  final String title;
  final RaceMetric metric;
  final List<int> suggestedTargets;
  final List<RaceFormat> supportedFormats;
  final bool isHold;
  final List<String> aliases;
  final String proofLabel;
  final String cameraInstruction;
  final List<String> instructions;
  final IconData icon;
  final String framingLabel;
  final PreferredCameraView preferredCameraView;

  /// Primary browsing category for the picker.
  final MovementCategory category;

  /// Whether this movement appears in the "Popular" row.
  final bool featured;

  /// Lower numbers sort first. Used for ordering within a category.
  final int sortPriority;

  int get defaultTarget => suggestedTargets.first;

  String get unit => metric.label;

  String targetLabel(int target) => '$target ${metric.label}';

  String counterLabel(int current, int target) =>
      '$current / $target ${metric.label}';
}

class ParsedRaceIdea {
  const ParsedRaceIdea({
    required this.input,
    required this.targetValue,
    this.format = RaceFormat.firstToGoal,
    this.recurrence = RaceRecurrence.none,
    this.activity,
    this.isAmbiguous = false,
  });

  final String input;
  final MotionActivityDefinition? activity;
  final int targetValue;
  final RaceFormat format;
  final RaceRecurrence recurrence;
  final bool isAmbiguous;

  bool get aiSupported => activity != null;
  String get title => input.trim().isEmpty ? 'New race' : input.trim();
  String get unit => activity?.metric.label ?? 'reps';
}

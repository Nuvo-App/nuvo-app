enum MotionActivityType {
  pushUps('push_ups'),
  jumpingJacks('jumping_jacks'),
  squats('squats'),
  lunges('lunges'),
  highKnees('high_knees'),
  armRaises('arm_raises'),
  plankHold('plank_hold');

  const MotionActivityType(this.backendValue);

  final String backendValue;

  static MotionActivityType? fromBackendValue(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == 'pushups' || normalized == 'push ups') {
      return MotionActivityType.pushUps;
    }
    if (normalized == 'lunge') return MotionActivityType.lunges;
    if (normalized == 'plank') return MotionActivityType.plankHold;
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
    this.isHold = false,
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

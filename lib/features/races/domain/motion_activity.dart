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
    for (final type in MotionActivityType.values) {
      if (type.backendValue == value) return type;
    }
    return null;
  }
}

class MotionActivityDefinition {
  const MotionActivityDefinition({
    required this.type,
    required this.title,
    required this.unit,
    required this.defaultTarget,
    required this.aliases,
    required this.proofLabel,
    required this.cameraInstruction,
    this.isHold = false,
  });

  final MotionActivityType type;
  final String title;
  final String unit;
  final int defaultTarget;
  final bool isHold;
  final List<String> aliases;
  final String proofLabel;
  final String cameraInstruction;

  String targetLabel(int target) => isHold ? '$target sec' : '$target $unit';

  String counterLabel(int current, int target) =>
      isHold ? '$current / $target sec' : '$current / $target $unit';
}

class ParsedRaceIdea {
  const ParsedRaceIdea({
    required this.input,
    required this.targetValue,
    this.activity,
  });

  final String input;
  final MotionActivityDefinition? activity;
  final int targetValue;

  bool get aiSupported => activity != null;
  String get title => input.trim().isEmpty ? 'New race' : input.trim();
  String get unit => activity?.unit ?? 'units';
}

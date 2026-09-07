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
  sideLunges('side_lunges'),
  deepSquats('deep_squats'),
  squatJacks('squat_jacks'),
  jumpSquats('jump_squats'),
  lungeJumps('lunge_jumps'),
  runningInPlace('running_in_place'),
  treadmillRunning('treadmill_running'),
  walkingInPlace('walking_in_place'),
  marchingInPlace('marching_in_place'),
  buttKicks('butt_kicks'),
  mountainClimbers('mountain_climbers'),
  burpees('burpees'),
  stepUps('step_ups'),
  calfRaises('calf_raises'),
  lateralSteps('lateral_steps');

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
    if (normalized == 'deep squat') return MotionActivityType.deepSquats;
    if (normalized == 'squat jack') return MotionActivityType.squatJacks;
    if (normalized == 'jump squat') return MotionActivityType.jumpSquats;
    if (normalized == 'lunge jump') return MotionActivityType.lungeJumps;
    if (normalized == 'run in place' || normalized == 'running') {
      return MotionActivityType.runningInPlace;
    }
    if (normalized == 'treadmill') return MotionActivityType.treadmillRunning;
    if (normalized == 'walk in place' || normalized == 'walking') {
      return MotionActivityType.walkingInPlace;
    }
    if (normalized == 'march in place' || normalized == 'marching') {
      return MotionActivityType.marchingInPlace;
    }
    if (normalized == 'butt kick') return MotionActivityType.buttKicks;
    if (normalized == 'mountain climber') {
      return MotionActivityType.mountainClimbers;
    }
    if (normalized == 'burpee') return MotionActivityType.burpees;
    if (normalized == 'step up' || normalized == 'stepup') {
      return MotionActivityType.stepUps;
    }
    if (normalized == 'calf raise') return MotionActivityType.calfRaises;
    if (normalized == 'lateral step' || normalized == 'side step') {
      return MotionActivityType.lateralSteps;
    }
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

/// How an activity's goal and progress are measured and phrased. The activity
/// catalog owns this so the composer prompt, race display, leaderboard, and
/// progress formatting all read from one source instead of each screen
/// deciding what "unit" means (that's how plank ended up showing "reps").
///
/// Serialization stays on [RaceMetric] (`reps` | `seconds`) — the Worker only
/// accepts those two. [distance] therefore rides the wire as `reps` with the
/// integer `target_value` / `progress_value` carrying **metres** (the server
/// treats it as an opaque cumulative integer); the client knows from the
/// activity catalog to render those metres as a running distance. `steps` /
/// `calories` / `completion` are documented future types with no consumer yet.
enum MotionMeasurementType {
  repetitions(RaceMetric.reps, 'reps'),
  duration(RaceMetric.seconds, 'seconds'),
  distance(RaceMetric.reps, 'mi');

  const MotionMeasurementType(this.raceMetric, this.defaultPluralUnit);

  final RaceMetric raceMetric;
  final String defaultPluralUnit;

  static MotionMeasurementType fromRaceMetric(RaceMetric m) =>
      m == RaceMetric.seconds
          ? MotionMeasurementType.duration
          : MotionMeasurementType.repetitions;
}

const double _metresPerMile = 1609.344;

/// Below this a distance reads better in whole metres than in decimal miles
/// ("150 m" not "0.09 mi"). 0.25 mi (the smallest mile-scale goal) is 402 m,
/// so everything under a quarter mile stays metric.
const int kMetresMilesCrossover = 400;

/// Metres → a trimmed mileage string: 402 → "0.25", 1609 → "1", 5000 → "3.11".
String formatMiles(int metres) {
  final miles = metres / _metresPerMile;
  // Two decimals is the honest ceiling for a camera estimate — never imply
  // more precision than that.
  var s = miles.toStringAsFixed(2);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  return s;
}

/// The one adaptive distance formatter — metres canonical, unit chosen for
/// legibility. `< 400 m → "24 m"`, otherwise `"0.63 mi"`. Used everywhere a
/// distance is shown (composer, verification, Arena, race detail, leaderboard,
/// results, progress).
String formatDistance(int metres) {
  final m = metres < 0 ? 0 : metres;
  if (m < kMetresMilesCrossover) return '$m m';
  return '${formatMiles(m)} mi';
}

/// Distance progress against a goal — both sides in the unit the *goal* scale
/// implies, so a 200 m race never flips to "0.12 mi" mid-run.
String formatDistanceProgress(int current, int target) {
  final metric = target < kMetresMilesCrossover;
  final c = current < 0 ? 0 : current;
  if (metric) return '$c / $target m';
  return '${formatMiles(c)} / ${formatMiles(target)} mi';
}

/// "8:42" from seconds-per-mile; null / out-of-range → null (caller hides it).
String? formatPacePerMile(double? secondsPerMile) {
  if (secondsPerMile == null ||
      !secondsPerMile.isFinite ||
      secondsPerMile < 180 ||
      secondsPerMile > 1500) {
    return null;
  }
  final total = secondsPerMile.round();
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}

/// "M:SS" clock form, always: "0:45", "2:00", "1:05".
String formatClock(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Compact duration for chips and inline: "45s" / "1 min" / "2 min" / "1:30".
String formatDurationShort(int seconds) {
  if (seconds < 60) return '${seconds}s';
  if (seconds % 60 == 0) return '${seconds ~/ 60} min';
  return formatClock(seconds);
}

/// Spoken duration for the win statement: "45 seconds" / "2 minutes" /
/// "1m 30s".
String formatDurationLong(int seconds) {
  if (seconds < 60) return '$seconds ${seconds == 1 ? 'second' : 'seconds'}';
  final m = seconds ~/ 60;
  final s = seconds % 60;
  if (s == 0) return '$m ${m == 1 ? 'minute' : 'minutes'}';
  return '${m}m ${s}s';
}

/// The full goal label: "25 reps" / "40 steps" / "2 minutes" / "0.25 mi".
String formatMotionTarget(
  MotionMeasurementType type,
  int value,
  String pluralUnit,
) =>
    switch (type) {
      MotionMeasurementType.duration => formatDurationLong(value),
      MotionMeasurementType.distance => formatDistance(value),
      MotionMeasurementType.repetitions => '$value $pluralUnit',
    };

/// Just the value for a composer suggestion chip: "25" / "45s" / "50 m" / "1 mi".
String formatMotionGoalOption(MotionMeasurementType type, int value) =>
    switch (type) {
      MotionMeasurementType.duration => formatDurationShort(value),
      MotionMeasurementType.distance => formatDistance(value),
      MotionMeasurementType.repetitions => '$value',
    };

/// Progress against a goal: "12 / 25 reps" / "0:45 / 2:00" / "45 / 200 m" /
/// "0.12 / 0.25 mi".
String formatMotionProgress(
  MotionMeasurementType type,
  int current,
  int target,
  String pluralUnit,
) =>
    switch (type) {
      MotionMeasurementType.duration =>
        '${formatClock(current)} / ${formatClock(target)}',
      MotionMeasurementType.distance => formatDistanceProgress(current, target),
      MotionMeasurementType.repetitions => '$current / $target $pluralUnit',
    };

/// Default composer question when the activity doesn't override it.
String defaultGoalPrompt(MotionMeasurementType type, String activityTitle) =>
    switch (type) {
      MotionMeasurementType.duration => 'How long?',
      MotionMeasurementType.distance => 'How far?',
      MotionMeasurementType.repetitions =>
        'How many ${activityTitle.toLowerCase()}?',
    };

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
    this.measurementType,
    this.goalPromptOverride,
    this.displayUnitOverride,
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

  /// Explicit measurement model. Null → derived from [metric] (so
  /// `RaceMetric.seconds` activities like plank become [duration]
  /// automatically).
  final MotionMeasurementType? measurementType;

  /// Composer question override, e.g. "How many steps?" for gait movements
  /// where "How many Running In Place?" reads badly. Null → [defaultGoalPrompt].
  final String? goalPromptOverride;

  /// Display noun override, e.g. "steps" / "kicks". Null → the measurement
  /// type's default plural ("reps" / "seconds"). Does NOT affect
  /// serialization — the wire metric is always [MotionMeasurementType.raceMetric].
  final String? displayUnitOverride;

  int get defaultTarget => suggestedTargets.first;

  MotionMeasurementType get resolvedMeasurementType =>
      measurementType ?? MotionMeasurementType.fromRaceMetric(metric);

  /// The noun shown to users ("reps", "steps", "seconds").
  String get unit =>
      displayUnitOverride ?? resolvedMeasurementType.defaultPluralUnit;

  /// The composer's goal question ("How many push-ups?", "How long?").
  String get goalPrompt =>
      goalPromptOverride ?? defaultGoalPrompt(resolvedMeasurementType, title);

  String targetLabel(int target) =>
      formatMotionTarget(resolvedMeasurementType, target, unit);

  String goalOptionLabel(int value) =>
      formatMotionGoalOption(resolvedMeasurementType, value);

  String counterLabel(int current, int target) =>
      formatMotionProgress(resolvedMeasurementType, current, target, unit);
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

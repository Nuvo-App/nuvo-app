import '../ai/custom_pose/custom_pose_verifier_spec.dart';
import 'motion_activity.dart';
import 'motion_activity_catalog.dart';
import 'race_name_interpreter.dart';

/// Returns the system-generated title for a given activity + target.
String generatedTitle(MotionActivityDefinition activity, int targetValue) =>
    'First to $targetValue ${activity.title}';

/// What kind of goal the race tracks.
enum RaceGoalKind {
  /// A supported movement counted and verified by the camera.
  movement,

  /// A non-physical / honor goal — progress is logged manually.
  manual,
}

/// Composer fields that carry provenance. A field enters
/// [RaceDraft.userEditedFields] the moment the user touches it; title
/// interpretation may fill any field NOT in this set — USER EDIT WINS.
enum RaceField {
  title,
  activity,
  goalKind,
  format,
  target,
  timing,
  manualGoal,
  manualUnit,
  recurrence,
  visibility,
  scoreDirection,
}

class RaceDraft {
  const RaceDraft({
    required this.title,
    required this.activity,
    required this.metric,
    required this.format,
    required this.targetValue,
    this.hasCustomName = false,
    this.recurrence = RaceRecurrence.none,
    this.visibility = 'invite_code',
    this.customActivityName,
    this.customUnit,
    this.verifierSpec,
    this.goalKind = RaceGoalKind.movement,
    this.manualGoalName,
    this.manualUnit,
    this.finishLineAt,
    this.attemptDurationSeconds,
    this.attemptLimit,
    this.scoreDirection = 'higher',
    this.userEditedFields = const {},
  });

  /// Movement (camera) or manual (honor-logged) goal.
  final RaceGoalKind goalKind;

  /// For [RaceGoalKind.manual]: what the goal is ("Read", "Meditate", …).
  final String? manualGoalName;

  /// For [RaceGoalKind.manual]: the free-text unit ("pages", "minutes", "days").
  final String? manualUnit;

  bool get isManual => goalKind == RaceGoalKind.manual;

  final String title;
  final MotionActivityDefinition activity;
  final RaceMetric metric;
  final RaceFormat format;
  final int targetValue;

  /// True only when the user has manually edited the race title.
  final bool hasCustomName;
  final RaceRecurrence recurrence;
  final String visibility;

  /// Populated only for races created from a Teach Nuvo custom movement.
  final String? customActivityName;

  /// Free-text unit for a custom movement ("reps", "rounds", …). Display only.
  final String? customUnit;

  final CustomPoseVerifierSpec? verifierSpec;

  /// Absolute finish line (ISO-8601). Required for [RaceFormat.mostInWindow]
  /// and any attempt race that should close on a deadline; the server is the
  /// authority on what "before the finish line" means.
  final String? finishLineAt;

  /// For [RaceFormat.timedAttempt]: how long each attempt runs, in seconds.
  final int? attemptDurationSeconds;

  /// Optional cap on how many attempts each racer may take.
  final int? attemptLimit;

  /// 'higher' = most/best value wins; 'lower' = lowest value wins (golf,
  /// fastest time). Maps to `minimum_attempt` scoring on the wire.
  final String scoreDirection;

  bool get lowerWins => scoreDirection == 'lower';

  /// Fields the user has manually set — provenance only, never sent to the
  /// backend. Title interpretation must not overwrite these.
  final Set<RaceField> userEditedFields;

  bool get isDeadlineMode =>
      format == RaceFormat.mostInWindow ||
      format == RaceFormat.bestAttempt ||
      format == RaceFormat.timedAttempt;

  bool get isCustom =>
      customActivityName != null && customActivityName!.isNotEmpty;

  /// True when the draft has everything required to start the race.
  /// For custom drafts, no preset activityId is required.
  bool get isValidToCreate {
    if (resolvedTitle.trim().isEmpty) return false;
    if (targetValue <= 0) return false;
    if (isManual) {
      return (manualGoalName ?? '').trim().isNotEmpty &&
          (manualUnit ?? '').trim().isNotEmpty;
    }
    if (isCustom) {
      return verifierSpec != null && customActivityName!.isNotEmpty;
    }
    return activity.activityId.isNotEmpty;
  }

  /// Activity name to show in review pages (preset, custom, or manual).
  String get displayActivityName => isManual
      ? (manualGoalName ?? 'Custom goal')
      : isCustom
      ? customActivityName!
      : activity.title;

  /// System-generated title for this draft, ignoring any manual name override.
  String get generatedTitleText => isManual
      ? 'First to $targetValue ${manualUnit ?? 'done'}'
      : isCustom
      ? 'First to $targetValue $customActivityName'
      : generatedTitle(activity, targetValue);

  /// The title to show everywhere. When not custom, derived from activity+target.
  String get resolvedTitle => hasCustomName ? title : generatedTitleText;

  RaceDraft copyWith({
    String? title,
    bool? hasCustomName,
    MotionActivityDefinition? activity,
    RaceMetric? metric,
    RaceFormat? format,
    int? targetValue,
    RaceRecurrence? recurrence,
    String? visibility,
    String? customActivityName,
    String? customUnit,
    CustomPoseVerifierSpec? verifierSpec,
    RaceGoalKind? goalKind,
    String? manualGoalName,
    String? manualUnit,
    String? finishLineAt,
    int? attemptDurationSeconds,
    int? attemptLimit,
    String? scoreDirection,
    bool clearTiming = false,
    bool clearCustom = false,
    Set<RaceField>? markEdited,
  }) {
    final nextActivity = activity ?? this.activity;
    final nextTarget = targetValue ?? this.targetValue;
    return RaceDraft(
      title: title ?? this.title,
      hasCustomName: hasCustomName ?? this.hasCustomName,
      activity: nextActivity,
      metric: metric ?? nextActivity.metric,
      format: format != null && nextActivity.supportedFormats.contains(format)
          ? format
          : this.format,
      targetValue: nextTarget,
      recurrence: recurrence ?? this.recurrence,
      visibility: visibility ?? this.visibility,
      customActivityName: clearCustom
          ? null
          : customActivityName ?? this.customActivityName,
      customUnit: clearCustom ? null : customUnit ?? this.customUnit,
      verifierSpec: clearCustom ? null : verifierSpec ?? this.verifierSpec,
      goalKind: goalKind ?? this.goalKind,
      manualGoalName: manualGoalName ?? this.manualGoalName,
      manualUnit: manualUnit ?? this.manualUnit,
      finishLineAt: clearTiming ? null : finishLineAt ?? this.finishLineAt,
      attemptDurationSeconds: clearTiming
          ? null
          : attemptDurationSeconds ?? this.attemptDurationSeconds,
      attemptLimit: clearTiming ? null : attemptLimit ?? this.attemptLimit,
      scoreDirection: scoreDirection ?? this.scoreDirection,
      userEditedFields: markEdited == null
          ? userEditedFields
          : {...userEditedFields, ...markEdited},
    );
  }

  RaceDraft asPreset({
    required MotionActivityDefinition activity,
    int? targetValue,
    bool? hasCustomName,
    String? title,
  }) {
    return RaceDraft(
      title: title ?? this.title,
      hasCustomName: hasCustomName ?? this.hasCustomName,
      activity: activity,
      metric: activity.metric,
      format: activity.supportedFormats.contains(format)
          ? format
          : activity.supportedFormats.first,
      targetValue: targetValue ?? this.targetValue,
      recurrence: recurrence,
      visibility: visibility,
      // Timing survives an activity switch — a timed battle stays a timed
      // battle when the user swaps push-ups for squats.
      finishLineAt: finishLineAt,
      attemptDurationSeconds: attemptDurationSeconds,
      attemptLimit: attemptLimit,
      scoreDirection: scoreDirection,
      userEditedFields: userEditedFields,
    );
  }

  Map<String, dynamic> toCreatePayload() {
    if (isCustom) {
      throw UnsupportedError(
        'Custom races must be created with createCustomRace, not toCreatePayload.',
      );
    }
    if (isManual) return _manualCreatePayload();
    return {
      'title': resolvedTitle,
      'description': '${activity.title} race verified by camera.',
      'category': 'fitness',
      'goalType': format.backendValue,
      'targetValue': targetValue,
      'unit': metric.backendValue,
      'targetUnit': metric.backendValue,
      'activityId': activity.activityId,
      'metric': metric.backendValue,
      'format': format.backendValue,
      'recurrence': recurrence.backendValue,
      'proofRequirement': 'ai_check',
      'proofReviewMode': 'auto_accept',
      'proofMode': 'ai_check',
      'aiActivityType': activity.activityId,
      'visibility': visibility,
      if (lowerWins) 'scoreDirection': 'lower',
      ..._timingPayload(),
    };
  }

  /// Finish-line / attempt fields shared by camera and manual payloads —
  /// omitted entirely when unset so first-to-goal races stay byte-identical
  /// to the pre-V2 contract.
  Map<String, dynamic> _timingPayload() => {
    if (finishLineAt != null && finishLineAt!.isNotEmpty)
      'finishLineAt': finishLineAt,
    if (attemptDurationSeconds != null)
      'attemptDurationSeconds': attemptDurationSeconds,
    if (attemptLimit != null) 'attemptLimit': attemptLimit,
  };

  Map<String, dynamic> _manualCreatePayload() {
    final unit = (manualUnit ?? 'done').trim();
    return {
      'title': resolvedTitle,
      'description': '${manualGoalName ?? 'Custom goal'} — progress logged manually.',
      'category': 'goal',
      'goalType': format.backendValue,
      'targetValue': targetValue,
      'unit': unit,
      'targetUnit': unit,
      'metric': 'reps',
      'format': format.backendValue,
      'recurrence': recurrence.backendValue,
      'proofRequirement': 'manual',
      'proofReviewMode': 'auto_accept',
      'proofMode': 'manual',
      'visibility': visibility,
      if (lowerWins) 'scoreDirection': 'lower',
      ..._timingPayload(),
    };
  }
}

RaceDraft? draftFromIdea(String idea) {
  if (idea.trim().isEmpty) return null;
  final i = interpretRaceName(idea);
  final activity = i.activity;
  if (activity == null) {
    // Custom subject — the typed name is the race name; goal is honor-logged.
    return RaceDraft(
      title: i.input,
      hasCustomName: true,
      activity: motionActivityDefinitions.first,
      metric: i.metric,
      format: i.format,
      targetValue: i.targetValue,
      recurrence: i.recurrence,
      goalKind: RaceGoalKind.manual,
      manualGoalName: i.manualGoalName,
      manualUnit: i.manualUnit,
      attemptDurationSeconds: i.attemptDurationSeconds,
      scoreDirection: i.scoreDirection,
    );
  }
  // Preset + canonical phrasing gets the generated title; anything else
  // keeps the user's words so the title never lies about the format.
  final generated = i.format == RaceFormat.firstToGoal;
  return RaceDraft(
    title: generated ? generatedTitle(activity, i.targetValue) : i.input,
    hasCustomName: !generated,
    activity: activity,
    metric: activity.metric,
    format: i.format,
    targetValue: i.targetValue,
    recurrence: i.recurrence,
    attemptDurationSeconds: i.attemptDurationSeconds,
    scoreDirection: i.scoreDirection,
  );
}

RaceDraft draftForActivity(MotionActivityDefinition activity) => RaceDraft(
  title: generatedTitle(activity, activity.defaultTarget),
  hasCustomName: false,
  activity: activity,
  metric: activity.metric,
  format: RaceFormat.firstToGoal,
  targetValue: activity.defaultTarget,
);

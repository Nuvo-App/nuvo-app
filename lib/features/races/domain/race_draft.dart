import '../ai/custom_pose/custom_pose_verifier_spec.dart';
import 'motion_activity.dart';
import 'motion_activity_catalog.dart';
import 'race_mode_semantics.dart';
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
  inviteCrew,
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
    this.inviteCrew = true,
    this.customActivityName,
    this.customUnit,
    this.verifierSpec,
    this.goalKind = RaceGoalKind.movement,
    this.manualGoalName,
    this.manualUnit,
    this.finishLineAt,
    this.clarification,
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

  /// Whether the invite link opens right after the race is created. Pure
  /// UX intent — Nuvo has no user-facing race privacy: the server stamps
  /// canonical access semantics at creation and this field is never sent.
  final bool inviteCrew;

  /// Populated only for races created from a Teach Nuvo custom movement.
  final String? customActivityName;

  /// Free-text unit for a custom movement ("reps", "rounds", …). Display only.
  final String? customUnit;

  final CustomPoseVerifierSpec? verifierSpec;

  /// Absolute finish line (ISO-8601). Required for [RaceFormat.mostInWindow]
  /// and any attempt race that should close on a deadline; the server is the
  /// authority on what "before the finish line" means.
  final String? finishLineAt;

  /// One unresolved question from interpreting the title ("What activity are
  /// you doing?"). Composer-facing only — never part of the create payload.
  final String? clarification;

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

  /// True when the draft has everything required to start the race —
  /// per format: only first-to-goal (and the manual/custom contracts, which
  /// the backend always scores against a target) requires a real number;
  /// deadline modes need a finish line; timed battles need a duration.
  bool get isValidToCreate {
    if (resolvedTitle.trim().isEmpty) return false;
    final needsTarget =
        format.usesScoreTarget || isManual || isCustom;
    if (needsTarget && targetValue <= 0) return false;
    if (format == RaceFormat.mostInWindow &&
        (finishLineAt ?? '').isEmpty) {
      return false;
    }
    if (format == RaceFormat.timedAttempt &&
        (attemptDurationSeconds ?? 0) <= 0) {
      return false;
    }
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

  /// System-generated title for this draft — mode-aware so a generated
  /// title never claims a finish line the format doesn't have.
  String get generatedTitleText => isManual
      ? (format.usesScoreTarget
          ? 'First to $targetValue ${manualUnit ?? 'done'}'
          : (manualGoalName ?? 'Custom goal'))
      : isCustom
      ? 'First to $targetValue $customActivityName'
      : switch (format) {
          RaceFormat.mostInWindow => 'Most ${activity.title}',
          RaceFormat.bestAttempt => 'Best ${activity.title} attempt',
          RaceFormat.timedAttempt =>
            '${formatDurationShort(attemptDurationSeconds ?? 60)} '
                '${activity.title} battle',
          _ => generatedTitle(activity, targetValue),
        };

  /// What winning this draft means — mode-derived so the review page and
  /// goal page never describe a rule the race doesn't play by.
  String get winStatement {
    final name = displayActivityName.toLowerCase();
    return switch (format) {
      RaceFormat.mostInWindow =>
        'Most verified $name before the finish line wins.',
      RaceFormat.bestAttempt => lowerWins
          ? 'Lowest score wins — every verified attempt counts.'
          : 'Best single attempt wins — every verified score counts.',
      RaceFormat.timedAttempt =>
        'Most $name in ${formatDurationShort(attemptDurationSeconds ?? 60)} wins.',
      // "First to 20 verified jumping jacks wins." — the bare figure for
      // reps, the spoken duration for timed goals.
      _ => 'First to $_winValueText verified $name wins.',
    };
  }

  String get _winValueText => metric == RaceMetric.seconds
      ? formatDurationShort(targetValue)
      : '$targetValue';

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
    bool? inviteCrew,
    String? customActivityName,
    String? customUnit,
    CustomPoseVerifierSpec? verifierSpec,
    RaceGoalKind? goalKind,
    String? manualGoalName,
    String? manualUnit,
    String? finishLineAt,
    String? clarification,
    int? attemptDurationSeconds,
    int? attemptLimit,
    String? scoreDirection,
    bool clearTiming = false,
    bool clearAttemptFields = false,
    bool clearCustom = false,
    bool clearClarification = false,
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
      inviteCrew: inviteCrew ?? this.inviteCrew,
      customActivityName: clearCustom
          ? null
          : customActivityName ?? this.customActivityName,
      customUnit: clearCustom ? null : customUnit ?? this.customUnit,
      verifierSpec: clearCustom ? null : verifierSpec ?? this.verifierSpec,
      goalKind: goalKind ?? this.goalKind,
      manualGoalName: manualGoalName ?? this.manualGoalName,
      manualUnit: manualUnit ?? this.manualUnit,
      finishLineAt: clearTiming ? null : finishLineAt ?? this.finishLineAt,
      clarification: clearClarification
          ? null
          : clarification ?? this.clarification,
      attemptDurationSeconds: clearTiming || clearAttemptFields
          ? null
          : attemptDurationSeconds ?? this.attemptDurationSeconds,
      attemptLimit: clearTiming || clearAttemptFields
          ? null
          : attemptLimit ?? this.attemptLimit,
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
      inviteCrew: inviteCrew,
      // Timing survives an activity switch — a timed battle stays a timed
      // battle when the user swaps push-ups for squats.
      finishLineAt: finishLineAt,
      clarification: clarification,
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
      // Only send a finish-line number when the format scores against one —
      // a best-attempt race carrying "50" would mint a fake progress bar.
      if (format.usesScoreTarget) 'targetValue': targetValue,
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
      // Proof contract: Nuvo is evidence-based — anything the camera can't
      // verify automatically requires a photo on every submission.
      'proofRequirement': 'photo_video',
      'proofReviewMode': 'auto_accept',
      'proofMode': 'photo',
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
      finishLineAt: _deadlineToIso(i.deadline),
      clarification: i.question,
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
    finishLineAt: _deadlineToIso(i.deadline),
    clarification: i.question,
    attemptDurationSeconds: i.attemptDurationSeconds,
    scoreDirection: i.scoreDirection,
  );
}

String? _deadlineToIso(String? phrase) =>
    deadlineUtcFromPhrase(phrase)?.toIso8601String();

RaceDraft draftForActivity(MotionActivityDefinition activity) => RaceDraft(
  title: generatedTitle(activity, activity.defaultTarget),
  hasCustomName: false,
  activity: activity,
  metric: activity.metric,
  format: RaceFormat.firstToGoal,
  targetValue: activity.defaultTarget,
);

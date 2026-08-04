import '../ai/custom_pose/custom_pose_verifier_spec.dart';
import 'motion_activity.dart';
import 'motion_activity_catalog.dart';

/// Returns the system-generated title for a given activity + target.
String generatedTitle(MotionActivityDefinition activity, int targetValue) =>
    'First to $targetValue ${activity.title}';

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
    this.verifierSpec,
  });

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
  final CustomPoseVerifierSpec? verifierSpec;

  bool get isCustom =>
      customActivityName != null && customActivityName!.isNotEmpty;

  /// True when the draft has everything required to start the race.
  /// For custom drafts, no preset activityId is required.
  bool get isValidToCreate {
    if (resolvedTitle.trim().isEmpty) return false;
    if (targetValue <= 0) return false;
    if (isCustom) {
      return verifierSpec != null &&
          customActivityName!.isNotEmpty;
    }
    return activity.type.backendValue.isNotEmpty;
  }

  /// Activity name to show in review pages (preset or custom).
  String get displayActivityName =>
      isCustom ? customActivityName! : activity.title;

  /// System-generated title for this draft, ignoring any manual name override.
  String get generatedTitleText => isCustom
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
    CustomPoseVerifierSpec? verifierSpec,
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
      customActivityName: customActivityName ?? this.customActivityName,
      verifierSpec: verifierSpec ?? this.verifierSpec,
    );
  }

  Map<String, dynamic> toCreatePayload() {
    if (isCustom) {
      throw UnsupportedError(
        'Custom races must be created with createCustomRace, not toCreatePayload.',
      );
    }
    return {
      'title': resolvedTitle,
      'description': '${activity.title} race verified by camera.',
      'category': 'fitness',
    'goalType': format.backendValue,
    'targetValue': targetValue,
    'unit': metric.backendValue,
    'targetUnit': metric.backendValue,
    'activityId': activity.type.backendValue,
    'metric': metric.backendValue,
    'format': format.backendValue,
    'recurrence': recurrence.backendValue,
    'proofRequirement': 'ai_check',
    'proofReviewMode': 'auto_accept',
    'proofMode': 'ai_check',
    'aiActivityType': activity.type.backendValue,
    'visibility': visibility,
  };
  }
}

RaceDraft? draftFromIdea(String idea) {
  final parsed = parseRaceIdea(idea);
  final activity = parsed.activity;
  if (activity == null) return null;
  return RaceDraft(
    title: generatedTitle(activity, parsed.targetValue),
    hasCustomName: false,
    activity: activity,
    metric: activity.metric,
    format: parsed.format,
    targetValue: parsed.targetValue,
    recurrence: parsed.recurrence,
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

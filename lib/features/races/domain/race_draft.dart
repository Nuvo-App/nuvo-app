import 'motion_activity.dart';
import 'motion_activity_catalog.dart';

class RaceDraft {
  const RaceDraft({
    required this.title,
    required this.activity,
    required this.metric,
    required this.format,
    required this.targetValue,
    this.recurrence = RaceRecurrence.none,
    this.visibility = 'invite_code',
  });

  final String title;
  final MotionActivityDefinition activity;
  final RaceMetric metric;
  final RaceFormat format;
  final int targetValue;
  final RaceRecurrence recurrence;
  final String visibility;

  RaceDraft copyWith({
    String? title,
    MotionActivityDefinition? activity,
    RaceMetric? metric,
    RaceFormat? format,
    int? targetValue,
    RaceRecurrence? recurrence,
    String? visibility,
  }) {
    final nextActivity = activity ?? this.activity;
    return RaceDraft(
      title: title ?? this.title,
      activity: nextActivity,
      metric: metric ?? nextActivity.metric,
      format: format != null && nextActivity.supportedFormats.contains(format)
          ? format
          : this.format,
      targetValue: targetValue ?? this.targetValue,
      recurrence: recurrence ?? this.recurrence,
      visibility: visibility ?? this.visibility,
    );
  }

  Map<String, dynamic> toCreatePayload() => {
    'title': title,
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

RaceDraft? draftFromIdea(String idea) {
  final parsed = parseRaceIdea(idea);
  final activity = parsed.activity;
  if (activity == null) return null;
  return RaceDraft(
    title: parsed.title,
    activity: activity,
    metric: activity.metric,
    format: parsed.format,
    targetValue: parsed.targetValue,
    recurrence: parsed.recurrence,
  );
}

RaceDraft draftForActivity(MotionActivityDefinition activity) => RaceDraft(
  title: 'First to ${activity.defaultTarget} ${activity.title}',
  activity: activity,
  metric: activity.metric,
  format: RaceFormat.firstToGoal,
  targetValue: activity.defaultTarget,
);

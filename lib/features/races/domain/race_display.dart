import '../data/race_models.dart';
import 'motion_activity.dart';
import 'motion_activity_catalog.dart';

const _completedRaceStatuses = {
  'completed',
  'complete',
  'finished',
  'archived',
  'cancelled',
};

MotionActivityDefinition? raceActivityDefinition(Race race) =>
    race.isCustomVerifierRace
    ? null
    : resolveRaceMotionActivity(
        aiActivityType: race.activityId ?? race.aiActivityType,
        title: race.title,
        unit: race.unit,
        targetUnit: race.targetUnit,
      );

RaceMetric raceMetric(Race race) {
  final parsed = RaceMetric.fromBackendValue(race.metric ?? race.targetUnit);
  if (parsed != null) return parsed;
  final activity = raceActivityDefinition(race);
  if (activity != null) return activity.metric;
  return RaceMetric.fromBackendValue(race.unit) ?? RaceMetric.reps;
}

String raceMetricLabel(Race race) => raceMetric(race).label;

/// The measurement model for a race — activity-driven, so a plank race
/// formats as a duration ("0:45 / 2:00") and a pushup race as reps
/// ("12 / 25 reps") without either screen deciding that itself.
MotionMeasurementType raceMeasurementType(Race race) {
  final activity = raceActivityDefinition(race);
  if (activity != null) return activity.resolvedMeasurementType;
  return MotionMeasurementType.fromRaceMetric(raceMetric(race));
}

/// The user-facing noun for a race's progress ("reps", "steps", "seconds").
String raceDisplayUnit(Race race) {
  final activity = raceActivityDefinition(race);
  if (activity != null) return activity.unit;
  return raceMeasurementType(race).defaultPluralUnit;
}

String raceActivityTitle(Race race) {
  if (race.isCustomVerifierRace) {
    final name =
        race.customActivityName ?? race.customVerifierSpec?.movementName;
    if (name != null && name.trim().isNotEmpty) return name.trim();
  }
  final activity = raceActivityDefinition(race);
  if (activity != null) return activity.title;
  final raw = race.activityId ?? race.aiActivityType ?? race.unit ?? 'race';
  return raw
      .replaceAll('_', ' ')
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

bool raceIsCompleted(Race race) => _completedRaceStatuses.contains(race.status);

bool raceIsActive(Race race) =>
    race.status == 'active' && !raceIsCompleted(race);

int raceProgressPercent(Race race, RaceParticipant? participant) {
  if (participant == null) return 0;
  final target = race.targetValue;
  if (target != null && target > 0) {
    return ((participant.progressValue / target) * 100).floor().clamp(0, 100);
  }
  return participant.progressPercent.clamp(0, 100);
}

String raceScoreLabel(Race race, int value) => formatMotionTarget(
      raceMeasurementType(race),
      value,
      raceDisplayUnit(race),
    );

String raceProgressLabel(Race race, RaceParticipant? participant) {
  if (participant == null) return '0';
  final target = race.targetValue;
  if (target != null && target > 0) {
    return formatMotionProgress(
      raceMeasurementType(race),
      participant.progressValue,
      target,
      raceDisplayUnit(race),
    );
  }
  return raceScoreLabel(race, participant.progressValue);
}

String raceTargetLabel(Race race) {
  final target = race.targetValue;
  if (target == null) return raceDisplayUnit(race);
  return formatMotionTarget(
    raceMeasurementType(race),
    target,
    raceDisplayUnit(race),
  );
}

List<RaceParticipant> serverRankedParticipants(Race race) {
  final participants = [...race.participants];
  participants.sort((a, b) {
    final rankA = a.rank ?? 1 << 20;
    final rankB = b.rank ?? 1 << 20;
    if (rankA != rankB) return rankA.compareTo(rankB);
    if (b.progressValue != a.progressValue) {
      return b.progressValue.compareTo(a.progressValue);
    }
    return a.joinedAt.compareTo(b.joinedAt);
  });
  return participants;
}

/// 1-based position in the standings order. Ties are broken deterministically
/// inside [serverRankedParticipants] (server rank, then progress, then join
/// time), so **every racer gets a distinct number** — no shared "2nd, 2nd".
/// Use this for all leaderboard display on active races.
int? positionalRank(Race race, String? userId) {
  if (userId == null) return null;
  final ranked = serverRankedParticipants(race);
  final index = ranked.indexWhere((p) => p.userId == userId);
  return index == -1 ? null : index + 1;
}

int? rankForUser(Race race, String? userId) {
  if (userId == null) return null;
  // Completed races: the server's final standings are authoritative.
  for (final standing in race.finalStandings) {
    if (standing.userId == userId) return standing.rank;
  }
  // Active races: distinct positional rank, never a tie.
  return positionalRank(race, userId);
}

String raceRankLabel(Race race, String? userId) {
  final rank = rankForUser(race, userId);
  return rank == null ? '--' : '#$rank';
}

String raceStatusLabel(Race race) {
  if (raceIsCompleted(race)) return 'Finished';
  if (race.status == 'active') return 'Live';
  return race.status.replaceAll('_', ' ');
}

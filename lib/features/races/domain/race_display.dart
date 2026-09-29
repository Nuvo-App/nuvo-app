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
  // A non-motion race still knows its unit from the backend ("strokes",
  // "books", "seconds"). Falling straight to the metric's default would
  // print "78 reps" for a golf round.
  final declared = race.targetUnit ?? race.unit;
  if (declared != null &&
      declared.isNotEmpty &&
      RaceMetric.fromBackendValue(declared) == null) {
    return declared;
  }
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
  if (participant == null) return 'Submit your first proof';
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
  final lowerIsBetter = race.scoreDirection == 'lower';
  final participants = [...race.participants];
  participants.sort((a, b) {
    final rankA = a.rank ?? 1 << 20;
    final rankB = b.rank ?? 1 << 20;
    if (rankA != rankB) return rankA.compareTo(rankB);
    if (b.progressValue != a.progressValue) {
      // Fastest-time races: lowest nonzero wins; zero means "no attempt
      // yet" and ranks last.
      if (lowerIsBetter) {
        final av = a.progressValue <= 0 ? 1 << 30 : a.progressValue;
        final bv = b.progressValue <= 0 ? 1 << 30 : b.progressValue;
        return av.compareTo(bv);
      }
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

/// Ordinal placement text — "1st", "8th", "999th". Shared so every race
/// surface spells rank the same way.
String raceOrdinal(int rank) {
  if (rank % 100 >= 11 && rank % 100 <= 13) return '${rank}th';
  return switch (rank % 10) {
    1 => '${rank}st',
    2 => '${rank}nd',
    3 => '${rank}rd',
    _ => '${rank}th',
  };
}

String raceStatusLabel(Race race) {
  if (raceIsCompleted(race)) return 'Finished';
  if (race.status == 'active') return 'Live';
  return race.status.replaceAll('_', ' ');
}

/// How a race's marks sit on the shared marker lane.
///
///   viewer   — the current user's fraction (null when they have no score
///              or aren't a participant).
///   rivals   — every other racer's fraction, best-first ordering preserved
///              from [serverRankedParticipants].
///   hasGoal  — a literal finish-line exists (higher-wins race with a
///              numeric target), so the lane ends in a goal ring. Without
///              one — best-attempt or lower-wins races — the lane is
///              *relative competition*: marks spread across the field's
///              range with the best score at the right edge and no goal
///              ring, so a golf score never reads as "78% complete".
({double? viewer, List<({RaceParticipant racer, double fraction})> rivals,
    bool hasGoal}) raceLaneGeometry(Race race, String? userId) {
  final ranked = serverRankedParticipants(race);
  final me = userId == null
      ? null
      : ranked.where((p) => p.userId == userId).firstOrNull;
  final others =
      ranked.where((p) => p.userId != userId && p.progressValue > 0).toList();

  // Goal lane: higher-wins race with a real finish target — marks are a
  // literal share of the distance to the line.
  final target = race.targetValue;
  final lowerWins = race.scoreDirection == 'lower';
  if (!lowerWins && target != null && target > 0) {
    return (
      viewer: me == null ? null : (me.progressValue / target).clamp(0.0, 1.0),
      rivals: [
        for (final p in others)
          (racer: p, fraction: (p.progressValue / target).clamp(0.0, 1.0)),
      ],
      hasGoal: true,
    );
  }

  // Performance lane: no finish-line target (best attempt), or lower-wins
  // (golf, fastest time) where more fill would invert the meaning. Marks
  // spread across the field's actual range — best score at the right.
  final scores = [
    if (me != null && me.progressValue > 0) me.progressValue,
    for (final p in others) p.progressValue,
  ];
  if (scores.isEmpty) return (viewer: null, rivals: const [], hasGoal: false);
  final best = scores.reduce((a, b) => lowerWins ? (a < b ? a : b) : (a > b ? a : b));
  final worst = scores.reduce((a, b) => lowerWins ? (a > b ? a : b) : (a < b ? a : b));
  double fractionFor(int value) {
    if (best == worst) return 0.6; // level field — marks sit past mid-lane
    final t = (value - worst) / (best - worst);
    return t.clamp(0.0, 1.0);
  }

  return (
    viewer: me != null && me.progressValue > 0
        ? fractionFor(me.progressValue)
        : null,
    rivals: [
      for (final p in others) (racer: p, fraction: fractionFor(p.progressValue)),
    ],
    hasGoal: false,
  );
}

/// The one rival worth naming on a compact track: the racer directly ahead
/// of the viewer (the next pass), the closest chaser when the viewer leads,
/// the leader when the viewer hasn't joined, else null for a solo board.
/// Never the viewer. Position comes from [serverRankedParticipants] — the
/// nullable server `rank` field is not required.
RaceParticipant? raceNearestRival(Race race, String? userId) {
  final ranked = serverRankedParticipants(race);
  final myIndex =
      userId == null ? -1 : ranked.indexWhere((p) => p.userId == userId);
  if (myIndex > 0) {
    for (var i = myIndex - 1; i >= 0; i--) {
      if (ranked[i].progressValue > 0) return ranked[i];
    }
    return null;
  }
  // Leading, or not on the board — the next scored racer is the reference.
  for (var i = myIndex + 1; i < ranked.length; i++) {
    if (ranked[i].progressValue > 0) return ranked[i];
  }
  return null;
}

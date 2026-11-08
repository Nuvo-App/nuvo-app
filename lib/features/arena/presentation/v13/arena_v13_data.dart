/// v13 Arena data layer — the joins between the race list, the /arena
/// snapshot's board order, the crew feed, and progression. Every function
/// here is pure so the copy decisions stay testable without pumping widgets.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nuvo/core/cache/cache_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/profile/application/activity_controller.dart';
import 'package:nuvo/features/profile/application/progression_controller.dart';
import 'package:nuvo/features/profile/data/progression_models.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/domain/motion_activity.dart';
import 'package:nuvo/features/races/domain/race_display.dart';
import 'package:nuvo/features/social/data/crew_activity.dart';

import '../../data/arena_models.dart';

// ── Providers ────────────────────────────────────────────────────────────────

/// Arena's 18-week activity window — `GET /profile/activity?days=126`.
/// Profile keeps its own 140-day fetch; the two windows cache under separate
/// domains so neither clobbers the other.
final arenaActivityProvider = FutureProvider.autoDispose<Map<String, int>>((
  ref,
) async {
  final token = await ref.read(secureTokenStoreProvider).getAccessToken();
  if (token == null) return const {};
  final store = ref.read(cacheStoreProvider);
  final account = ref.read(authControllerProvider).user?.id;
  final canCache = account != null && isValidCacheId(account);

  Map<String, int>? cached;
  if (canCache) {
    try {
      final entry = await store.read(
        account,
        'activity_18w',
        maxAge: const Duration(days: 30),
      );
      final data = entry?.data;
      if (data is Map) {
        cached = {
          for (final e in data.entries)
            if (e.value is num) e.key.toString(): (e.value as num).toInt(),
        };
      }
    } catch (_) {}
  }

  try {
    final fresh = await ref
        .read(profileActivityApiProvider)
        .fetch(token, days: 126);
    if (canCache) store.write(account, 'activity_18w', fresh);
    return fresh;
  } catch (_) {
    if (cached != null) return cached;
    rethrow;
  }
});

/// The badge collection behind Arena's four achievement tiles — featured
/// badges ride on the progression payload, but "most recently earned" needs
/// the collection's `unlockedAt`s. Failures degrade to the progression
/// payload alone (the caller treats this as optional).
final arenaBadgeCollectionProvider =
    FutureProvider.autoDispose<List<NuvoBadge>>((ref) async {
      if (!ref.watch(progressionControllerProvider).hasValue) {
        return const <NuvoBadge>[];
      }
      return ref.read(progressionControllerProvider.notifier).getBadges();
    });

// ── Names ────────────────────────────────────────────────────────────────────

/// "Hey [first name]" — first token of the full name, then the handle.
String arenaFirstName(String? fullName, String? username) {
  final name = fullName?.trim();
  if (name != null && name.isNotEmpty) {
    return name.split(RegExp(r'\s+')).first;
  }
  final handle = username?.trim();
  if (handle != null && handle.isNotEmpty) return handle;
  return 'there';
}

String firstNameOf(String displayName) {
  final parts = displayName
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty);
  return parts.isEmpty ? displayName : parts.first;
}

// ── Race ordering ────────────────────────────────────────────────────────────

/// Active races in the /arena snapshot's board order (focus first, then
/// live boards); races the snapshot doesn't name keep their list order at
/// the end. The snapshot is ordering metadata only — card data always comes
/// from the [Race] itself.
List<Race> arenaOrderedRaces(List<Race> races, ArenaSnapshot? snapshot) {
  final active = races.where(raceIsActive).toList();
  final boardIds = <String>[
    if (snapshot?.focusBoard case final b?) b.id,
    if (snapshot != null) ...snapshot.liveBoards.map((b) => b.id),
  ];
  if (boardIds.isEmpty) return active;
  final boardOrder = {for (var i = 0; i < boardIds.length; i++) boardIds[i]: i};
  final sourceOrder = {for (var i = 0; i < active.length; i++) active[i].id: i};
  active.sort((a, b) {
    final ai = boardOrder[a.id] ?? boardIds.length;
    final bi = boardOrder[b.id] ?? boardIds.length;
    if (ai != bi) return ai.compareTo(bi);
    return sourceOrder[a.id]!.compareTo(sourceOrder[b.id]!);
  });
  return active;
}

// ── Race card view-model ─────────────────────────────────────────────────────

/// The viewer's score — server viewerContext when the row carries it, else
/// the viewer's own participant row (demo fixtures have no viewerContext).
int arenaViewerScore(Race race, String? myId) =>
    race.viewerContext?.viewerScore ??
    (myId == null ? null : race.participantFor(myId)?.progressValue) ??
    0;

/// One racer in the ≤3-leader face row on a card.
typedef ArenaLeaderFace = ({
  String userId,
  String name,
  String? photoUrl,
  bool isMe,
});

/// Everything a swiper card needs, computed once per build.
class ArenaCardData {
  const ArenaCardData({
    required this.race,
    required this.movementLabel,
    required this.racerCount,
    required this.leaderFaces,
    this.timeLeft,
    required this.scoreText,
    this.goalText,
    required this.progress,
    this.gapLine,
    required this.score,
    this.rank,
    required this.total,
  });

  final Race race;
  final String movementLabel;
  final int racerCount;
  final List<ArenaLeaderFace> leaderFaces;
  final String? timeLeft;
  final String scoreText;
  final String? goalText;
  final double progress;
  final String? gapLine;

  /// Raw score — the value [V13NumberPop] diffs for the reward animation.
  final int score;
  final int? rank;
  final int total;
}

ArenaCardData arenaCardData(Race race, String? myId) {
  final vc = race.viewerContext;
  final score = arenaViewerScore(race, myId);
  final ranked = serverRankedParticipants(race);
  final total = ranked.length;
  final myIndex = myId == null
      ? -1
      : ranked.indexWhere((p) => p.userId == myId);
  final rank = vc?.rank ?? (myIndex >= 0 ? myIndex + 1 : null);

  final type = raceMeasurementType(race);
  final target = race.targetValue;
  final hasGoal = raceHasFinishLine(race) && target != null;

  final scoreText = switch (type) {
    MotionMeasurementType.duration => formatClock(score),
    MotionMeasurementType.distance => formatDistance(score),
    MotionMeasurementType.repetitions => '$score',
  };
  final goalText = hasGoal
      ? formatMotionTarget(type, target, raceDisplayUnit(race))
      : null;
  final progress = hasGoal
      ? (score / target).clamp(0.0, 1.0)
      : (raceLaneGeometry(race, myId).viewer ?? 0.0);

  return ArenaCardData(
    race: race,
    movementLabel: raceActivityTitle(race),
    racerCount: total,
    leaderFaces: [
      for (final p in ranked.take(3))
        (
          userId: p.userId,
          name: p.displayName,
          photoUrl: p.profilePhotoUrl,
          isMe: p.userId == myId,
        ),
    ],
    timeLeft: arenaTimeLeft(race),
    scoreText: scoreText,
    goalText: goalText,
    progress: progress,
    gapLine: _gapLine(race, myId, score, ranked, myIndex, rank, total, hasGoal),
    score: score,
    rank: rank,
    total: total,
  );
}

/// Compact countdown for the top-right pill — viewerContext seconds when
/// present, else the start/finish timestamps. Null when the race declares
/// neither (the pill is hidden rather than faked).
String? arenaTimeLeft(Race race) {
  final vc = race.viewerContext;
  if (vc?.timeRemainingSeconds != null) {
    return _compactDuration(vc!.timeRemainingSeconds!);
  }
  if (vc?.startsInSeconds != null) {
    return 'in ${_compactDuration(vc!.startsInSeconds!)}';
  }
  final now =
      DateTime.tryParse(race.serverTime ?? '')?.toUtc() ??
      DateTime.now().toUtc();
  final finish = DateTime.tryParse(race.finishLineAt ?? '');
  if (finish != null && finish.isAfter(now)) {
    return _compactDuration(finish.difference(now).inSeconds);
  }
  final start = DateTime.tryParse(race.startLineAt ?? '');
  if (start != null && start.isAfter(now)) {
    return 'in ${_compactDuration(start.difference(now).inSeconds)}';
  }
  return null;
}

String _compactDuration(int seconds) {
  if (seconds >= 86400) return '${seconds ~/ 86400}d';
  if (seconds >= 3600) return '${seconds ~/ 3600}h';
  if (seconds >= 60) return '${seconds ~/ 60}m';
  return '<1m';
}

/// The gap line under the progress bar. Higher-wins races name the racer
/// directly ahead ("9 behind Alex") or the closest chaser when leading
/// ("Leading Priya by 4"); goal-less formats lean on rank ("3rd of 7") so a
/// golf score never reads as a distance to a finish line that isn't there.
String? _gapLine(
  Race race,
  String? myId,
  int myScore,
  List<RaceParticipant> ranked,
  int myIndex,
  int? rank,
  int total,
  bool hasGoal,
) {
  final vc = race.viewerContext;
  final target = race.targetValue;
  final finished =
      vc?.isFinished == true ||
      (hasGoal && target != null && myScore >= target);
  if (finished) return 'You crossed the finish line';
  if (total <= 1) return 'Set the pace. Invite your friends to chase you.';
  if (myIndex < 0) return null;

  final lower = race.scoreDirection == 'lower';
  final isLeading = vc?.isLeading ?? (myIndex == 0);
  if (isLeading) {
    final chaser = myIndex + 1 < total ? ranked[myIndex + 1] : null;
    if (chaser == null) return null;
    final gap = lower
        ? chaser.progressValue - myScore
        : myScore - chaser.progressValue;
    final name = firstNameOf(chaser.displayName);
    return gap > 0 ? 'Leading $name by $gap' : 'Tied with $name';
  }

  // Lower-wins with no score yet: "0 behind" would be nonsense — rank only.
  if (lower && myScore <= 0) {
    return rank != null ? '${raceOrdinal(rank)} of $total' : null;
  }
  final ahead = ranked[myIndex - 1];
  final gap = lower
      ? myScore - ahead.progressValue
      : ahead.progressValue - myScore;
  final name = firstNameOf(ahead.displayName);
  final place = rank != null ? raceOrdinal(rank) : null;
  if (hasGoal) {
    return gap > 0 ? '$gap behind $name' : 'Tied with $name';
  }
  if (gap > 0) {
    return place != null
        ? '$gap behind $name · $place of $total'
        : '$gap behind $name';
  }
  return place != null ? 'Tied · $place of $total' : null;
}

// ── Nudge ────────────────────────────────────────────────────────────────────

/// The one actionable nudge under the swiper — someone passing you, else
/// the closest pass you can make.
class ArenaNudge {
  const ArenaNudge({
    required this.headline,
    required this.subline,
    required this.race,
    this.actorId,
    this.actorPhotoUrl,
  });

  final String headline;
  final String subline;
  final Race race;
  final String? actorId;
  final String? actorPhotoUrl;
}

/// Picks the nudge: the newest `rank_changed`/`lead_changed` feed item where
/// the viewer was overtaken in a race that's still active; else the active
/// race where the viewer is closest to the next rank. Null when nothing
/// actionable exists — the row hides instead of faking urgency.
ArenaNudge? pickArenaNudge({
  required List<CrewActivityItem> items,
  required List<Race> activeRaces,
  required String? myId,
}) {
  if (myId == null || activeRaces.isEmpty) return null;
  final byId = {for (final r in activeRaces) r.id: r};

  CrewActivityItem? pass;
  for (final item in items) {
    final actor = item.actor;
    if (actor == null || actor.id == myId) continue;
    final overtaken = switch (item.type) {
      'rank_changed' =>
        item.payload['overtakenUserIds'] is List &&
            (item.payload['overtakenUserIds'] as List).contains(myId),
      'lead_changed' => item.payload['displacedUserId'] == myId,
      _ => false,
    };
    if (!overtaken || byId[item.raceId] == null) continue;
    if (pass == null || item.occurredAt.isAfter(pass.occurredAt)) {
      pass = item;
    }
  }
  if (pass != null) {
    final race = byId[pass.raceId]!;
    final actor = pass.actor!;
    final me = race.participantFor(myId);
    final them = race.participantFor(actor.id);
    final lower = race.scoreDirection == 'lower';
    int? ahead;
    if (me != null && them != null) {
      final d = lower
          ? me.progressValue - them.progressValue
          : them.progressValue - me.progressValue;
      if (d > 0) ahead = d;
    }
    final title = race.title.isNotEmpty
        ? race.title
        : (pass.raceTitle ?? 'your race');
    return ArenaNudge(
      headline: '${firstNameOf(actor.displayName)} passed you',
      subline: ahead != null ? '$title · $ahead ahead' : title,
      race: race,
      actorId: actor.id,
      actorPhotoUrl: actor.profilePhotoUrl,
    );
  }

  Race? best;
  RaceParticipant? bestAhead;
  var bestGap = 1 << 30;
  for (final race in activeRaces) {
    final ranked = serverRankedParticipants(race);
    final mi = ranked.indexWhere((p) => p.userId == myId);
    if (mi <= 0) continue;
    final ahead = ranked[mi - 1];
    final myScore = arenaViewerScore(race, myId);
    final lower = race.scoreDirection == 'lower';
    final gap =
        race.viewerContext?.gapToNextRank ??
        (lower ? myScore - ahead.progressValue : ahead.progressValue - myScore);
    if (gap <= 0 || gap >= bestGap) continue;
    best = race;
    bestAhead = ahead;
    bestGap = gap;
  }
  if (best != null && bestAhead != null) {
    return ArenaNudge(
      headline: '$bestGap to pass ${firstNameOf(bestAhead.displayName)}',
      subline: best.title,
      race: best,
      actorId: bestAhead.userId,
      actorPhotoUrl: bestAhead.profilePhotoUrl,
    );
  }
  return null;
}

// ── Stats ────────────────────────────────────────────────────────────────────

/// The RACING / WINS / WIN RATE triple — the server's record when the
/// payload carries it; otherwise derived from the race list (the profile
/// screen's documented fallback for older Workers).
({String racing, String wins, String winRate})? arenaStats(
  ProfileRecord? record,
  List<Race> races,
  String? myId,
) {
  if (record != null) {
    return (
      racing: '${record.active}',
      wins: '${record.wins}',
      winRate: record.winRatePercent == null
          ? '—'
          : '${record.winRatePercent}%',
    );
  }
  if (races.isEmpty) return null;
  final active = races.where(raceIsActive).length;
  final finished = races.where(raceIsCompleted).toList();
  final wins = myId == null
      ? 0
      : finished.where((r) => r.winnerUserId == myId).length;
  return (
    racing: '$active',
    wins: '$wins',
    winRate: finished.isEmpty
        ? '—'
        : '${(wins * 100 / finished.length).round()}%',
  );
}

// ── Activity heat map ────────────────────────────────────────────────────────

/// `{'2024-05-01': 3}` → `{DateTime(2024,5,1): 3}` — V13HeatMap keys are
/// local date-only DateTimes.
Map<DateTime, int> arenaActivityDays(Map<String, int> raw) {
  final out = <DateTime, int>{};
  raw.forEach((key, value) {
    if (value <= 0) return;
    final parsed = DateTime.tryParse(key);
    if (parsed == null) return;
    final day = DateTime(parsed.year, parsed.month, parsed.day);
    out[day] = (out[day] ?? 0) + value;
  });
  return out;
}

int arenaActiveDayCount(Map<DateTime, int> days) => days.length;

int arenaProofTotal(Map<DateTime, int> days) =>
    days.values.fold(0, (sum, n) => sum + n);

// ── Achievement tiles ────────────────────────────────────────────────────────

/// Up to four tiles: featured badges first (server-ordered), then the
/// collection's most recently earned, then locked achievements nearest to
/// done so a short earned list still shows real progress.
List<NuvoBadge> arenaBadgeSlots(
  NuvoProgression progression,
  List<NuvoBadge> collection,
) {
  final out = <NuvoBadge>[];
  void add(NuvoBadge b) {
    if (out.length < 4 && !out.any((o) => o.unlockId == b.unlockId)) {
      out.add(b);
    }
  }

  for (final b in progression.featuredBadges) {
    if (b.unlocked) add(b);
  }
  final featuredIds = progression.featuredBadges.map((b) => b.unlockId).toSet();
  final earned =
      collection
          .where((b) => b.unlocked && !featuredIds.contains(b.unlockId))
          .toList()
        ..sort((a, b) => (b.unlockedAt ?? '').compareTo(a.unlockedAt ?? ''));
  earned.forEach(add);
  progression.newlyEarned.forEach(add);
  final next = progression.nextAchievement;
  if (next != null) add(next);
  final locked =
      collection
          .where(
            (b) =>
                !b.unlocked &&
                b.isAchievement &&
                !out.any((o) => o.unlockId == b.unlockId),
          )
          .toList()
        ..sort((a, b) => b.goalProgress.compareTo(a.goalProgress));
  locked.forEach(add);
  return out;
}

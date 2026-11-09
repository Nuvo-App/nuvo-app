import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/presentation/auth_controller.dart';
import '../onboarding/data/onboarding_v2_store.dart';
import '../onboarding/player/race_preview.dart';
import '../profile/data/progression_models.dart';
import '../races/data/race_models.dart';
import 'tour_controller.dart';

/// Id prefix of every client-only tour object. Anything carrying it is
/// practice data: it is drawn over real screens while the tour runs and is
/// never read from or written to the server.
const String kTourIdPrefix = 'tour-';
const String kTourPracticeRaceId = '${kTourIdPrefix}practice-race';
const String kTourJoinRaceId = '${kTourIdPrefix}join-race';
const String kTourBadgeId = '${kTourIdPrefix}badge-day-one';

/// The bots' public label.
const String kTourBotName = 'Nuvo Crew';

/// What a practice proof adds to the user's practice score.
const int kTourPracticeProofReps = 5;

bool isTourId(String? id) => id != null && id.startsWith(kTourIdPrefix);
bool isTourRace(Race race) => isTourId(race.id);

class TourDemoFriend {
  const TourDemoFriend({required this.id, required this.name});
  final String id;
  final String name;
}

/// Everything the tour overlays on real screens. Null whenever the tour is
/// not running.
class TourFixtures {
  const TourFixtures({
    required this.practiceRace,
    required this.joinableRace,
    required this.friends,
    required this.badge,
  });

  /// "Squat Race · First to 10" — Nuvo Crew bots on 6 and 4, the user on 0
  /// (5 after the first practice proof).
  final Race practiceRace;

  /// An open practice race with a Join pill on Compete.
  final Race joinableRace;
  final List<TourDemoFriend> friends;

  /// The earned "Day One" tile shown on Profile when the account has none.
  final NuvoBadge badge;
}

String _stamp() => DateTime.utc(2026).toIso8601String();

RaceParticipant _bot(String n, int score, int rank) => RaceParticipant(
  id: '${kTourIdPrefix}bot-$n-p',
  userId: '${kTourIdPrefix}bot-$n',
  displayName: kTourBotName,
  progressValue: score,
  progressPercent: score * 10,
  rank: rank,
  joinedAt: _stamp(),
);

Race _race({
  required String id,
  required String title,
  required String creatorId,
  required List<RaceParticipant> participants,
  RaceViewerContext? viewerContext,
  String visibility = 'private',
}) => Race(
  id: id,
  creatorId: creatorId,
  title: title,
  goalType: 'target',
  targetValue: 10,
  unit: 'reps',
  targetUnit: 'reps',
  aiActivityType: 'squat',
  status: 'active',
  visibility: visibility,
  createdAt: _stamp(),
  updatedAt: _stamp(),
  participants: participants,
  viewerContext: viewerContext,
);

/// Pure builder (tests call it directly).
TourFixtures buildTourFixtures({
  required String? userId,
  String? userName,
  String? q1,
  required bool practiceDone,
}) {
  final me = userId ?? '${kTourIdPrefix}me';
  final myScore = practiceDone ? kTourPracticeProofReps : 0;
  // Bots 6 and 4: with 5 reps the user passes the 4.
  final myRank = practiceDone ? 2 : 3;
  final participants = [
    _bot('a', 6, 1),
    if (practiceDone) ...[
      RaceParticipant(
        id: '${kTourIdPrefix}me-p',
        userId: me,
        displayName: userName ?? 'You',
        progressValue: myScore,
        progressPercent: myScore * 10,
        rank: myRank,
        joinedAt: _stamp(),
      ),
      _bot('b', 4, 3),
    ] else ...[
      _bot('b', 4, 2),
      RaceParticipant(
        id: '${kTourIdPrefix}me-p',
        userId: me,
        displayName: userName ?? 'You',
        progressValue: myScore,
        progressPercent: myScore * 10,
        rank: myRank,
        joinedAt: _stamp(),
      ),
    ],
  ];
  final practice = _race(
    id: kTourPracticeRaceId,
    title: obPracticeRaceName(q1),
    creatorId: '${kTourIdPrefix}bot-a',
    participants: participants,
    viewerContext: RaceViewerContext(
      raceId: kTourPracticeRaceId,
      status: 'active',
      rank: myRank,
      viewerScore: myScore,
      isMember: true,
    ),
  );
  final joinable = _race(
    id: kTourJoinRaceId,
    title: 'Pushup Race · Practice',
    creatorId: '${kTourIdPrefix}bot-c',
    visibility: 'public',
    participants: [_bot('c', 3, 1)],
  );
  return TourFixtures(
    practiceRace: practice,
    joinableRace: joinable,
    friends: const [
      TourDemoFriend(id: '${kTourIdPrefix}friend-1', name: 'Maya'),
      TourDemoFriend(id: '${kTourIdPrefix}friend-2', name: 'Jonah'),
    ],
    badge: const NuvoBadge(
      unlockId: kTourBadgeId,
      type: 'badge',
      key: 'day_one',
      name: 'Day One',
      description: 'You showed up. That is day one.',
      requiredLevel: 1,
      unlocked: true,
      featured: true,
      category: 'racing',
      iconKey: 'flag',
    ),
  );
}

/// The overlay. Null unless the tour is running; derived only from local
/// state — no repository, API client or token is ever read.
final tourFixturesProvider = Provider<TourFixtures?>((ref) {
  if (!ref.watch(tourActiveProvider)) return null;
  final done = ref.watch(tourControllerProvider.select((s) => s.practiceDone));
  final user = ref.watch(authControllerProvider.select((s) => s.user));
  final q1 = ref.watch(tourAnswerQ1Provider);
  return buildTourFixtures(
    userId: user?.id,
    userName: user?.fullName ?? user?.username,
    q1: q1,
    practiceDone: done,
  );
});

/// The starter-question answer that names the practice race.
final tourAnswerQ1Provider = Provider<String?>(
  (ref) => ref.watch(onboardingV2StoreProvider).answerQ1,
);

/// Joined state of the joinable race, client-side only.
final tourJoinedProvider = StateProvider<bool>((ref) => false);

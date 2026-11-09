import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import '../helpers/screenshot.dart';
import '../tour/tour_harness.dart';
import 'package:nuvo/features/tour/tour_anchors.dart';
import 'package:nuvo/features/tour/tour_controller.dart';
import 'package:nuvo/features/tour/tour_fixtures.dart';
import 'package:nuvo/features/races/presentation/v13/submit_proof_sheet.dart';
import 'package:nuvo/core/cache/cache_store.dart';
import 'package:nuvo/core/v13/v13.dart';
import 'package:nuvo/features/arena/data/arena_api.dart';
import 'package:nuvo/features/arena/data/arena_models.dart';
import 'package:nuvo/features/arena/data/arena_repository.dart';
import 'package:nuvo/features/arena/presentation/arena_controller.dart';
import 'package:nuvo/features/arena/presentation/v13/arena_v13_race_swiper.dart';
import 'package:nuvo/features/arena/presentation/v13/arena_v13_screen.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/notifications/application/notification_controller.dart';
import 'package:nuvo/features/notifications/data/notification_models.dart';
import 'package:nuvo/features/notifications/data/notification_repository.dart';
import 'package:nuvo/features/profile/application/activity_controller.dart';
import 'package:nuvo/features/profile/application/progression_controller.dart';
import 'package:nuvo/features/profile/data/activity_api.dart';
import 'package:nuvo/features/profile/data/progression_api.dart';
import 'package:nuvo/features/profile/data/progression_models.dart';
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/data/race_repository.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';
import 'package:nuvo/features/social/data/crew_activity.dart';

// ── Fakes ────────────────────────────────────────────────────────────────────

class _FakeAuthRepo extends AuthRepository {
  _FakeAuthRepo() : super(AuthApi(), SecureTokenStore());

  @override
  Future<RestoreResult> restoreSession() async => const RestoreOk(
    AuthUser(
      id: 'user-1',
      email: 'test@getnuvo.net',
      fullName: 'Test User',
      username: 'testuser',
      onboardingComplete: true,
      hasMemberPass: true,
      termsAccepted: true,
    ),
  );
}

class _FakeStore extends SecureTokenStore {
  @override
  Future<String?> getAccessToken() async => 'test-token';
}

class _RacesRepo extends RaceRepository {
  _RacesRepo({this.races = const [], this.throws = false})
    : super(RaceApi(), SecureTokenStore(), AuthApi());

  final List<Race> races;
  bool throws;
  int getRacesCalls = 0;

  @override
  Future<List<Race>> getRaces() async {
    getRacesCalls++;
    if (throws) throw const ApiException(503, 'Service Unavailable');
    return races;
  }
}

class _ArenaRepo extends ArenaRepository {
  _ArenaRepo(this.snapshot) : super(ArenaApi(), SecureTokenStore(), AuthApi());

  final ArenaSnapshot snapshot;

  @override
  Future<ArenaSnapshot> getArenaSnapshot() async => snapshot;
}

class _ProgApi extends ProgressionApi {
  _ProgApi({this.progression, this.badges = const []}) : super(client: null);

  final NuvoProgression? progression;
  final List<NuvoBadge> badges;

  @override
  Future<ProgressionFetch> getProgressionConditional(
    String token, {
    String? etag,
  }) async {
    return ProgressionFetch(
      data: progression ?? NuvoProgression.fromJson(const {'level': 2}),
    );
  }

  @override
  Future<List<NuvoBadge>> getBadges(String token) async => badges;
}

class _FeedRepo extends CrewActivityRepository {
  _FeedRepo(this.items)
    : super(CrewActivityApi(), SecureTokenStore(), AuthApi());

  final List<CrewActivityItem> items;

  @override
  Future<List<CrewActivityItem>> getFeed({
    int limit = 40,
    String? cursor,
  }) async => items;
}

class _NotifRepo implements NotificationRepository {
  _NotifRepo({this.unreadCount = 0});

  final int unreadCount;

  @override
  Future<NotificationPage> list({String? cursor, String? etag}) async =>
      NotificationPage(items: const [], unreadCount: unreadCount);

  @override
  Future<void> markRead(String id) async {}
  @override
  Future<void> markAllRead() async {}
}

class _ActivityApi extends ProfileActivityApi {
  _ActivityApi({this.days = const {}}) : super(client: null);

  final Map<String, int> days;
  int? requestedDays;

  @override
  Future<Map<String, int>> fetch(
    String token, {
    int days = 140,
    int? tzMinutes,
  }) async {
    requestedDays = days;
    return this.days;
  }
}

// ── Fixtures ─────────────────────────────────────────────────────────────────

RaceParticipant _p(String id, String name, int score, {int? rank}) =>
    RaceParticipant(
      id: 'part-$id',
      userId: id,
      displayName: name,
      progressValue: score,
      progressPercent: 0,
      rank: rank,
      joinedAt: '2025-01-01T00:00:00Z',
    );

Race _race({
  required String id,
  required String title,
  String activityId = 'pushups',
  int? targetValue = 50,
  List<RaceParticipant> participants = const [],
  RaceViewerContext? viewerContext,
  String status = 'active',
}) => Race(
  id: id,
  creatorId: 'u-alex',
  title: title,
  goalType: 'count',
  activityId: activityId,
  aiActivityType: activityId,
  targetValue: targetValue,
  unit: 'reps',
  metric: 'reps',
  targetUnit: 'reps',
  status: status,
  createdAt: '2025-01-01T00:00:00Z',
  updatedAt: '2025-01-01T00:00:00Z',
  participants: participants,
  viewerContext: viewerContext,
);

Race _pushupRace() => _race(
  id: 'r1',
  title: 'Pushup Battle',
  participants: [
    _p('u-alex', 'Alex Rivera', 41, rank: 1),
    _p('user-1', 'Test User', 39, rank: 2),
  ],
  viewerContext: const RaceViewerContext(
    raceId: 'r1',
    status: 'active',
    rank: 2,
    leaderUserId: 'u-alex',
    leaderScore: 41,
    viewerScore: 39,
    gapToLeader: 2,
    gapToNextRank: 2,
    timeRemainingSeconds: 5400,
    isMember: true,
  ),
);

Race _plankRace() => _race(
  id: 'r2',
  title: 'Plank Party',
  activityId: 'squats',
  targetValue: 60,
  participants: [
    _p('user-1', 'Test User', 56, rank: 1),
    _p('u-sam', 'Sam Okafor', 50, rank: 2),
  ],
  viewerContext: const RaceViewerContext(
    raceId: 'r2',
    status: 'active',
    rank: 1,
    leaderUserId: 'user-1',
    leaderScore: 56,
    viewerScore: 56,
    isLeading: true,
    isMember: true,
  ),
);

ArenaSnapshot _snapshot() => const ArenaSnapshot(
  mode: 'real',
  headerPulse: '',
  focusBoard: ArenaBoard(
    id: 'r1',
    source: 'real',
    title: 'Pushup Battle',
    progressLabel: '',
    boardContext: '',
    primaryActionLabel: '',
    primaryActionType: 'open_board',
    isResult: false,
  ),
  liveBoards: [
    ArenaBoard(
      id: 'r2',
      source: 'real',
      title: 'Plank Party',
      progressLabel: '',
      boardContext: '',
      primaryActionLabel: '',
      primaryActionType: 'open_board',
      isResult: false,
    ),
  ],
);

CrewActivityItem _passedYouItem() => CrewActivityItem(
  id: 'e1',
  type: 'rank_changed',
  occurredAt: DateTime.utc(2025, 1, 2),
  actor: const CrewActivityActor(id: 'u-alex', displayName: 'Alex Rivera'),
  raceId: 'r1',
  raceTitle: 'Pushup Battle',
  payload: const {
    'overtakenUserIds': ['user-1'],
    'previousRank': 1,
    'newRank': 2,
  },
);

NuvoProgression _progression({int? streakDays = 3}) =>
    NuvoProgression.fromBody({
      'progression': const {
        'level': 5,
        'totalXp': 1200,
        'currentLevelXp': 120,
        'nextLevelXp': 200,
        'progress': 0.6,
        'xpToNext': 80,
        'lastSeenLevel': 5,
        'achievementsEarned': 2,
        'achievementsTotal': 10,
        'featuredBadges': [
          {
            'unlockId': 'bdg-flag',
            'type': 'achievement',
            'key': 'off_the_line',
            'name': 'Off the Line',
            'unlocked': true,
            'category': 'racing',
            'iconKey': 'flag',
          },
        ],
      },
      'record': {
        'active': 3,
        'finished': 10,
        'wins': 4,
        'winRatePercent': 40,
        'streakDays': ?streakDays,
      },
    });

// ── Harness ──────────────────────────────────────────────────────────────────

void _tallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Widget _buildApp({
  List<Race> races = const [],
  bool racesThrow = false,
  _RacesRepo? racesRepo,
  List<CrewActivityItem> feed = const [],
  NuvoProgression? progression,
  List<NuvoBadge> badges = const [],
  Map<String, int> activityDays = const {},
  int unread = 0,
  List<Override> extra = const [],
}) {
  final router = GoRouter(
    initialLocation: '/arena',
    routes: [
      GoRoute(path: '/arena', builder: (_, _) => const ArenaScreenV13()),
      GoRoute(
        path: '/race/:id/proof',
        builder: (_, s) => _Stub('proof ${s.pathParameters['id']}'),
      ),
      GoRoute(
        path: '/race/:id',
        builder: (_, s) => _Stub('race ${s.pathParameters['id']}'),
      ),
      GoRoute(path: '/races/new', builder: (_, _) => const _Stub('new-race')),
      GoRoute(path: '/compete', builder: (_, _) => const _Stub('compete')),
      GoRoute(path: '/profile', builder: (_, _) => const _Stub('profile')),
      GoRoute(
        path: '/profile/badges',
        builder: (_, _) => const _Stub('badges'),
      ),
      GoRoute(
        path: '/notifications',
        builder: (_, _) => const _Stub('notifications'),
      ),
      GoRoute(
        path: '/u/:id',
        builder: (_, s) => _Stub('user ${s.pathParameters['id']}'),
      ),
    ],
  );
  addTearDown(router.dispose);
  return ProviderScope(
    overrides: [
      raceRepositoryProvider.overrideWithValue(
        racesRepo ?? _RacesRepo(races: races, throws: racesThrow),
      ),
      arenaRepositoryProvider.overrideWithValue(_ArenaRepo(_snapshot())),
      // In-memory cache — the file-backed store hangs under flutter_test's
      // binary messenger (path_provider has no handler).
      cacheStoreProvider.overrideWithValue(CacheStore.memory()),
      progressionApiProvider.overrideWithValue(
        _ProgApi(progression: progression, badges: badges),
      ),
      crewActivityRepositoryProvider.overrideWithValue(_FeedRepo(feed)),
      notificationRepositoryProvider.overrideWithValue(
        _NotifRepo(unreadCount: unread),
      ),
      profileActivityApiProvider.overrideWithValue(
        _ActivityApi(days: activityDays),
      ),
      secureTokenStoreProvider.overrideWithValue(_FakeStore()),
      authControllerProvider.overrideWith(
        (ref) => AuthController(_FakeAuthRepo()),
      ),
      ...extra,
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

class _Stub extends StatelessWidget {
  const _Stub(this.label);
  final String label;
  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text('STUB $label')));
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump();
}

/// Bounded pumps for taps that trigger route transitions — `pumpAndSettle`
/// waits forever on any still-shimmering skeleton or animation.
Future<void> _navPumps(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pump();
}

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(loadShotFonts);
  testWidgets('populated Arena renders header, race card, nudge, stats, '
      'heat map, and achievements', (tester) async {
    _tallViewport(tester);
    await tester.pumpWidget(
      _buildApp(
        races: [_pushupRace(), _plankRace()],
        feed: [_passedYouItem()],
        progression: _progression(),
        activityDays: {
          '2025-01-01': 2,
          '2025-01-02': 1,
          '2025-01-03': 1,
          '2025-01-04': 1,
        },
        unread: 7,
      ),
    );
    await _settle(tester);

    // Header — first name, streak + level, bell badge.
    expect(find.text('Hey Test'), findsOneWidget);
    expect(find.text('3 day streak · Level 5'), findsOneWidget);
    expect(find.text('7'), findsOneWidget); // bell badge

    // Race section — count + swipe hint, first card fully rendered.
    expect(find.text('YOUR RACES · 2'), findsOneWidget);
    expect(find.text('Swipe for more'), findsOneWidget);
    expect(find.text('Pushup Battle'), findsOneWidget);
    expect(find.text('39'), findsOneWidget); // viewer score
    expect(find.textContaining('/ 50'), findsOneWidget); // goal
    expect(find.text('2nd'), findsOneWidget); // place
    expect(find.text('of 2'), findsWidgets);
    expect(find.text('2 behind Alex'), findsOneWidget);
    expect(find.text('1h'), findsOneWidget); // countdown pill
    expect(find.text('Submit proof'), findsWidgets);

    // Nudge — the feed's rank_changed where I was overtaken.
    expect(find.text('Alex passed you'), findsOneWidget);
    expect(find.text('Pushup Battle · 2 ahead'), findsOneWidget);
    expect(find.text('Take it back'), findsOneWidget);

    // Stats triple from the server record.
    expect(find.text('RACING'), findsOneWidget);
    expect(find.text('4'), findsOneWidget); // wins
    expect(find.text('WIN RATE'), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);

    // Activity heat map — 18 weeks of proof days.
    expect(find.text('5 proofs · 18 weeks'), findsOneWidget);
    expect(find.text('4 active days'), findsOneWidget);
    expect(find.text('Less'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);

    // Achievements — earned/total + tiles.
    expect(find.text('ACHIEVEMENTS'), findsOneWidget);
    expect(find.text('2 of 10'), findsOneWidget);
    expect(find.text('Off the Line'), findsOneWidget);
    await shot(tester, 'v13_arena_populated');
    expect(tester.takeException(), isNull);
  });

  testWidgets('streak hides when the record does not carry streakDays', (
    tester,
  ) async {
    _tallViewport(tester);
    await tester.pumpWidget(
      _buildApp(
        races: [_pushupRace()],
        progression: _progression(streakDays: null),
      ),
    );
    await _settle(tester);

    expect(find.text('Hey Test'), findsOneWidget);
    expect(find.text('Level 5'), findsOneWidget);
    expect(find.textContaining('day streak'), findsNothing);
  });

  testWidgets('zero active races renders the first-race hero only', (
    tester,
  ) async {
    _tallViewport(tester);
    await tester.pumpWidget(_buildApp(progression: _progression()));
    await _settle(tester);

    expect(find.text('Your first race'), findsOneWidget);
    expect(find.text('Up for another one?'), findsNothing);
    expect(find.byType(V13GhostRace), findsOneWidget);
    expect(find.text('Start a race'), findsOneWidget);
    expect(find.text('Join a race'), findsOneWidget);
    expect(find.text('Swipe for more'), findsNothing);
    expect(find.text('Submit proof'), findsNothing);
  });

  group('empty states for a brand-new account', () {
    NuvoProgression fresh({Map<String, dynamic>? next}) =>
        NuvoProgression.fromBody({
          'progression': {
            'level': 1,
            'totalXp': 0,
            'progress': 0.0,
            'achievementsEarned': 0,
            'achievementsTotal': 43,
            'nextAchievement': ?next,
          },
          'record': const {'active': 0, 'finished': 0, 'wins': 0},
        });

    const firstProof = {
      'unlockId': 'bdg-first',
      'type': 'achievement',
      'key': 'first_proof',
      'name': 'First Proof',
      'unlocked': false,
      'category': 'proof',
      'iconKey': 'flag',
      'statKey': 'progresses_accepted',
      'threshold': 1,
      'progressValue': 0,
    };

    Future<void> pumpFresh(WidgetTester tester) async {
      _tallViewport(tester);
      await tester.pumpWidget(
        _buildApp(
          progression: fresh(next: firstProof),
          badges: [NuvoBadge.fromJson(firstProof)],
        ),
      );
      await _settle(tester);
    }

    testWidgets('header, hero, zero stats, map and achievements', (
      tester,
    ) async {
      await pumpFresh(tester);

      // Header: name, "Level 1 · Day 1", silhouette in the XP ring.
      expect(find.text('Hey Test'), findsOneWidget);
      expect(find.text('Level 1 · Day 1'), findsOneWidget);
      final ring = tester.widget<V13XpRing>(find.byType(V13XpRing));
      expect(ring.emptyFill, isNotNull);
      expect(find.byIcon(Icons.person_rounded), findsWidgets);

      // Hero.
      expect(find.text('Your first race'), findsOneWidget);

      // Zero stats.
      expect(find.text('Your first win is 1 proof away'), findsOneWidget);

      // Activity map.
      expect(find.text('Today starts your map'), findsOneWidget);
      expect(find.byType(V13HeatMap), findsOneWidget);

      // Achievements: 0 of 43, locked tile, closest is tappable.
      expect(find.text('0 of 43'), findsOneWidget);
      expect(find.byIcon(Icons.lock_rounded), findsWidgets);
      expect(find.text('First Proof · 1 proof to go'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('closest achievement opens the badges page', (tester) async {
      await pumpFresh(tester);
      await tester.ensureVisible(find.text('First Proof · 1 proof to go'));
      await tester.tap(find.text('First Proof · 1 proof to go'));
      await _navPumps(tester);
      expect(find.text('STUB badges'), findsOneWidget);
    });

    testWidgets('no countable target: no "to go" line', (tester) async {
      _tallViewport(tester);
      await tester.pumpWidget(
        _buildApp(
          progression: fresh(),
          badges: [
            NuvoBadge.fromJson(const {
              'unlockId': 'bdg-x',
              'type': 'achievement',
              'key': 'x',
              'name': 'Mystery',
              'unlocked': false,
            }),
          ],
        ),
      );
      await _settle(tester);
      expect(find.text('0 of 43'), findsOneWidget);
      expect(find.textContaining('to go'), findsNothing);
    });

    for (final (name, size) in [
      ('390x844', const Size(390, 844)),
      ('320x568', const Size(320, 568)),
    ]) {
      testWidgets('layout at $name', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          _buildApp(
            progression: fresh(next: firstProof),
            badges: [NuvoBadge.fromJson(firstProof)],
          ),
        );
        await _settle(tester);
        await shot(tester, 'arena_empty_top_$name');
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(ListView).first, const Offset(0, -520));
        await tester.pump(const Duration(milliseconds: 300));
        await shot(tester, 'arena_empty_bottom_$name');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('reduce motion: hero renders still', (tester) async {
      _tallViewport(tester);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: _buildApp(progression: fresh(next: firstProof)),
        ),
      );
      await _settle(tester);
      expect(find.text('Your first race'), findsOneWidget);
      // No repeating controllers: the frame queue drains.
      await tester.pumpAndSettle(const Duration(seconds: 1));
    });
  });

  testWidgets('race fetch error shows retry; retry loads the cards', (
    tester,
  ) async {
    _tallViewport(tester);
    final repo = _RacesRepo(races: [_pushupRace()], throws: true);
    await tester.pumpWidget(
      _buildApp(racesRepo: repo, progression: _progression()),
    );
    await _settle(tester);

    expect(find.text('Couldn’t load your races'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Pushup Battle'), findsNothing);

    repo.throws = false;
    await tester.tap(find.text('Retry'));
    await _settle(tester);

    // Card title + the closest-pass nudge's subline both carry the name.
    expect(find.text('Pushup Battle'), findsWidgets);
    expect(find.text('Submit proof'), findsOneWidget);
    expect(repo.getRacesCalls, greaterThanOrEqualTo(2));
  });

  testWidgets('tour: practice card + Submit proof anchors exist, practice '
      'proof completes client-side for 10 XP', (tester) async {
    _tallViewport(tester);
    final tour = runningTour(beat: 'arenaProof');
    await tester.pumpWidget(
      _buildApp(
        races: [_pushupRace()],
        progression: _progression(),
        extra: tour.overrides,
      ),
    );
    await _settle(tester);

    expect(
      TourAnchors.rectOf(TourAnchor.arenaRaceCard),
      isNotNull,
      reason: 'race card anchor',
    );
    expect(
      TourAnchors.rectOf(TourAnchor.submitProof),
      isNotNull,
      reason: 'Submit proof anchor',
    );
    expect(find.text('Practice'), findsWidgets);
    expect(find.text('Nuvo Crew'), findsNothing); // labels live in the race

    // Practice card is first; the real race is still there after it.
    expect(find.text('Pushup Battle'), findsWidgets);

    await tester.tap(
      find.descendant(
        of: find.byKey(TourAnchors.keyOf(TourAnchor.submitProof)),
        matching: find.text('Submit proof'),
      ),
    );
    await _navPumps(tester);
    expect(find.byType(SubmitProofV13Sheet), findsNothing);
    expect(find.text('Skip camera for now'), findsOneWidget);
    await tester.tap(find.text('Skip camera for now'));
    await _navPumps(tester);
    expect(tour.store.xpAwarded['arenaProof'], 10);
    expect(tour.store.cameraFallback, isTrue);
  });

  testWidgets('tour off: no practice card, no anchors', (tester) async {
    _tallViewport(tester);
    await tester.pumpWidget(
      _buildApp(races: [_pushupRace()], progression: _progression()),
    );
    await _settle(tester);
    expect(TourAnchors.rectOf(TourAnchor.arenaRaceCard), isNull);
    expect(find.text('Practice'), findsNothing);
  });

  testWidgets('Submit proof opens the Submit proof sheet for that race', (
    tester,
  ) async {
    _tallViewport(tester);
    await tester.pumpWidget(
      _buildApp(races: [_pushupRace()], progression: _progression()),
    );
    await _settle(tester);

    await tester.tap(find.text('Submit proof').first);
    await _navPumps(tester);
    expect(find.byType(SubmitProofV13Sheet), findsOneWidget);
  });

  testWidgets('Take it back opens the Submit proof sheet for the nudge race', (
    tester,
  ) async {
    _tallViewport(tester);
    await tester.pumpWidget(
      _buildApp(
        races: [_pushupRace()],
        feed: [_passedYouItem()],
        progression: _progression(),
      ),
    );
    await _settle(tester);

    await tester.tap(find.text('Take it back'));
    await _navPumps(tester);
    expect(find.byType(SubmitProofV13Sheet), findsOneWidget);
  });

  testWidgets('race card body opens race detail', (tester) async {
    _tallViewport(tester);
    await tester.pumpWidget(
      _buildApp(races: [_pushupRace()], progression: _progression()),
    );
    await _settle(tester);

    // The closest-pass nudge also names the race — tap the card's title.
    await tester.tap(
      find.descendant(
        of: find.byType(ArenaRaceCard),
        matching: find.text('Pushup Battle'),
      ),
    );
    await _navPumps(tester);
    expect(find.text('STUB race r1'), findsOneWidget);
  });

  testWidgets('bell pushes notifications', (tester) async {
    _tallViewport(tester);
    await tester.pumpWidget(_buildApp(progression: _progression()));
    await _settle(tester);

    await tester.tap(find.bySemanticsLabel('Notifications'));
    await _navPumps(tester);
    expect(find.text('STUB notifications'), findsOneWidget);
  });

  testWidgets('avatar goes to profile', (tester) async {
    _tallViewport(tester);
    await tester.pumpWidget(_buildApp(progression: _progression()));
    await _settle(tester);

    await tester.tap(find.bySemanticsLabel('Your profile').first);
    await _navPumps(tester);
    expect(find.text('STUB profile'), findsOneWidget);
  });

  testWidgets('Start a race pushes the composer', (tester) async {
    _tallViewport(tester);
    await tester.pumpWidget(_buildApp(progression: _progression()));
    await _settle(tester);

    await tester.tap(find.text('Start a race'));
    await _navPumps(tester);
    expect(find.text('STUB new-race'), findsOneWidget);
  });

  testWidgets('Join a race goes to Compete', (tester) async {
    _tallViewport(tester);
    await tester.pumpWidget(_buildApp(progression: _progression()));
    await _settle(tester);

    await tester.tap(find.text('Join a race'));
    await _navPumps(tester);
    expect(find.text('STUB compete'), findsOneWidget);
  });

  testWidgets('achievements link and badge tiles open the badges page', (
    tester,
  ) async {
    _tallViewport(tester);
    await tester.pumpWidget(_buildApp(progression: _progression()));
    await _settle(tester);

    await tester.tap(find.text('2 of 10'));
    await _navPumps(tester);
    expect(find.text('STUB badges'), findsOneWidget);
  });

  testWidgets('second race card renders after paging to it', (tester) async {
    // Phone-width viewport: page 2 is only a peek, not a built page.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _buildApp(
        races: [_pushupRace(), _plankRace()],
        progression: _progression(),
      ),
    );
    await _settle(tester);

    await tester.tap(find.bySemanticsLabel('Page 2 of 3'));
    await _navPumps(tester);

    expect(find.text('Plank Party'), findsOneWidget);
    expect(find.text('Leading Sam by 6'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

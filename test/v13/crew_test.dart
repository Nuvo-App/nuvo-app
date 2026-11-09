// Widget tests for the v13 Crew tab + Crew page: populated / empty / error
// states (with shots) plus the main tap paths and mutations.
import '../tour/tour_harness.dart';
import 'package:nuvo/features/tour/tour_anchors.dart';
import 'package:nuvo/features/tour/tour_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:nuvo/core/cache/cache_store.dart';
import 'package:nuvo/core/config/nuvo_flags.dart';
import 'package:nuvo/core/v13/v13.dart';
import 'package:nuvo/core/network/conditional.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/crew/application/crew_controller.dart';
import 'package:nuvo/features/crew/data/crew_api.dart';
import 'package:nuvo/features/crew/data/crew_repository.dart';
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/data/race_repository.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';
import 'package:nuvo/features/social/data/crew_activity.dart';
import 'package:nuvo/features/social/presentation/v13/crew_tab_v13_screen.dart';
import 'package:nuvo/features/squads/application/squad_controller.dart';
import 'package:nuvo/features/squads/data/squad_api.dart';
import 'package:nuvo/features/squads/presentation/v13/crew_page_v13_screen.dart';

import '../helpers/screenshot.dart';

// ── Fakes ────────────────────────────────────────────────────────────────

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

class _StubCrewRepo extends CrewRepository {
  _StubCrewRepo({
    this.members = const [],
    this.requests = const [],
    this.outgoing = const [],
    this.mutuals = const {},
    this.error,
  }) : super(CrewApi(), SecureTokenStore(), AuthApi());

  final List<PublicUser> members;
  final List<PublicUser> requests;
  final List<PublicUser> outgoing;
  final Map<String, CrewRequestMutuals> mutuals;
  final ApiException? error;

  final accepted = <String>[];
  final declined = <String>[];
  final removed = <String>[];

  @override
  Future<List<PublicUser>> getCrew() =>
      error != null ? Future.error(error!) : Future.value(members);
  @override
  Future<CrewRequestPage> getRequestPage() => Future.value(
    CrewRequestPage(incoming: requests, outgoing: outgoing, mutuals: mutuals),
  );
  @override
  Future<void> acceptRequest(String userId) async => accepted.add(userId);
  @override
  Future<void> declineRequest(String userId) async => declined.add(userId);
  @override
  Future<void> remove(String userId) async => removed.add(userId);
}

class _StubSquadRepo extends SquadRepository {
  _StubSquadRepo({
    this.groups = const [],
    this.detailData,
    this.weekRows,
    this.discoverItems = const [],
    this.previewData,
    this.listError,
    this.detailError,
  }) : super(SquadApi(), SecureTokenStore(), AuthApi());

  final List<CrewGroup> groups;
  final CrewGroupDetail? detailData;
  final List<CrewGroupStanding>? weekRows;
  final List<CrewDiscoverItem> discoverItems;
  final CrewGroupPreview? previewData;
  final ApiException? listError;
  final ApiException? detailError;

  final joinRequestsSent = <String>[];
  final mutedCalls = <bool>[];
  final autoJoinCalls = <String>[];

  @override
  Future<Conditional<List<CrewGroup>>> list({String? etag}) => listError != null
      ? Future.error(listError!)
      : Future.value(Conditional(data: groups, etag: 'e'));
  @override
  Future<Conditional<CrewGroupDetail>> detail(String id, {String? etag}) =>
      detailError != null
      ? Future.error(detailError!)
      : Future.value(Conditional(data: detailData, etag: 'd'));
  @override
  Future<CrewGroup> create(String name) async =>
      groups.isNotEmpty ? groups.first : _group(id: 'new', name: name);
  @override
  Future<void> join(String code) async {}
  @override
  Future<void> leave(String id) async {}
  @override
  Future<void> setRole(String id, String userId, String role) async {}
  @override
  Future<void> removeMember(String id, String userId) async {}

  // W2 additive — stubbed so the new sections fetch without a Worker.
  @override
  Future<List<CrewDiscoverItem>> discover() => Future.value(discoverItems);
  @override
  Future<CrewGroupPreview> preview(String id) => previewData != null
      ? Future.value(previewData!)
      : Future.error(const ApiException(404, 'Not found'));
  @override
  Future<List<CrewGroupStanding>> standings(
    String id, {
    String period = 'all',
  }) => weekRows == null
      ? Future.error(const ApiException(404, 'Not found'))
      : Future.value(weekRows!);
  @override
  Future<void> joinRequest(String id) async => joinRequestsSent.add(id);
  @override
  Future<void> approveJoinRequest(String id, String userId) async {}
  @override
  Future<void> declineJoinRequest(String id, String userId) async {}
  @override
  Future<void> setMuted(String id, {required bool on}) async =>
      mutedCalls.add(on);
  @override
  Future<void> reportCrew(String id, {String? reason}) async {}
  @override
  Future<void> setRecurringAutoJoin(
    String id,
    String recurringId, {
    required bool on,
  }) async => autoJoinCalls.add('$recurringId:$on');
}

class _StubActivityRepo extends CrewActivityRepository {
  _StubActivityRepo({this.items = const [], this.error})
    : super(CrewActivityApi(), SecureTokenStore(), AuthApi());
  final List<CrewActivityItem> items;
  final ApiException? error;
  final reacts = <String>[];

  @override
  Future<List<CrewActivityItem>> getFeed({int limit = 40, String? cursor}) =>
      error != null ? Future.error(error!) : Future.value(items);
  @override
  Future<ReactionSummary> react(CrewActivityItem item, String emoji) async {
    reacts.add(item.id);
    return const ReactionSummary(counts: {'fire': 3}, myReaction: 'fire');
  }

  @override
  Future<ReactionSummary> unreact(CrewActivityItem item) async =>
      const ReactionSummary(counts: {'fire': 1});
}

class _StubRaceRepo extends RaceRepository {
  _StubRaceRepo({this.races = const []})
    : super(RaceApi(), SecureTokenStore(), AuthApi());
  final List<Race> races;
  @override
  Future<List<Race>> getRaces() => Future.value(races);
  @override
  Future<List<Race>> getOpenRaces() => Future.value(const []);
  @override
  Future<Race> getRaceDetail(String id) =>
      Future.value(races.firstWhere((r) => r.id == id));
}

// ── Fixtures ─────────────────────────────────────────────────────────────

PublicUser _friend(String id, String name) =>
    PublicUser(id: id, displayName: name, initials: name.substring(0, 1));

CrewGroup _group({String id = 'c1', String name = 'Sunrise Crew'}) => CrewGroup(
  id: id,
  name: name,
  joinCode: 'SUN123',
  isOwner: false,
  memberCount: 4,
  raceCount: 3,
  myRole: 'admin',
  ownerName: 'Ben Carter',
  colorKey: 'sun',
  myRankWeek: 2,
  memberPreviews: const [
    CrewMemberPreview(userId: 'user-2', displayName: 'Ben Carter'),
    CrewMemberPreview(userId: 'user-3', displayName: 'Maya Miles'),
    CrewMemberPreview(userId: 'user-4', displayName: 'Theo North'),
  ],
  nextRecurring: const CrewRecurringRace(
    id: 'rr1',
    title: 'Morning pushups',
    schedule: 'Every Monday',
    rule: 'First to 100',
    inDays: 2,
    autoJoin: true,
  ),
  stats: const CrewGroupStats(wins: 4, races: 9, streakDays: 5),
  bio: 'Early runners only.',
);

CrewGroupDetail _detail() => CrewGroupDetail(
  group: _group(),
  races: const [
    CrewGroupRace(id: 'r1', title: 'Pushup Race', status: 'active'),
  ],
  standings: const [
    CrewGroupStanding(
      userId: 'user-2',
      displayName: 'Ben Carter',
      rank: 1,
      points: 9,
      wins: 2,
      races: 4,
      isYou: false,
    ),
    CrewGroupStanding(
      userId: 'user-1',
      displayName: 'Test User',
      rank: 2,
      points: 6,
      wins: 0,
      races: 4,
      isYou: true,
    ),
    CrewGroupStanding(
      userId: 'user-9',
      displayName: 'Wren Fox',
      rank: 3,
      points: 1,
      wins: 0,
      races: 1,
      isYou: false,
    ),
  ],
  members: const [
    CrewMember(userId: 'user-2', displayName: 'Ben Carter', role: 'owner'),
    CrewMember(userId: 'user-1', displayName: 'Test User', role: 'admin'),
    CrewMember(userId: 'user-3', displayName: 'Maya Miles', role: 'member'),
    CrewMember(userId: 'user-4', displayName: 'Theo North', role: 'member'),
  ],
  recurring: _group().nextRecurring == null
      ? const []
      : [_group().nextRecurring!],
);

Race _sharedRace() => const Race(
  id: 'r1',
  creatorId: 'user-2',
  title: 'Pushup Race',
  goalType: 'first_to_goal',
  targetValue: 100,
  unit: 'reps',
  proofRequirement: 'ai_check',
  proofMode: 'ai_check',
  verificationMethod: 'camera_pose',
  activityId: 'pushups',
  status: 'active',
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  participants: [
    RaceParticipant(
      id: 'p1',
      userId: 'user-1',
      displayName: 'Test User',
      progressValue: 20,
      progressPercent: 20,
      joinedAt: '2026-01-01T00:00:00Z',
    ),
    RaceParticipant(
      id: 'p2',
      userId: 'user-3',
      displayName: 'Maya Miles',
      progressValue: 40,
      progressPercent: 40,
      joinedAt: '2026-01-01T00:00:00Z',
    ),
  ],
  viewerContext: RaceViewerContext(
    raceId: 'r1',
    status: 'active',
    rank: 2,
    viewerScore: 20,
    leaderScore: 40,
    timeRemainingSeconds: 86400,
    isMember: true,
  ),
);

CrewActivityItem _feedItem() => CrewActivityItem(
  id: 'a1',
  type: 'progress_accepted',
  occurredAt: DateTime.now().subtract(const Duration(minutes: 4)),
  actor: const CrewActivityActor(id: 'user-3', displayName: 'Maya Miles'),
  raceId: 'r1',
  raceTitle: 'Pushup Race',
  payload: const {'score': 40},
  entityType: 'race',
  entityId: 'r1',
  reactions: const {'fire': 2},
);

List<Override> _overrides({
  _StubCrewRepo? crew,
  _StubSquadRepo? squads,
  _StubActivityRepo? activity,
  _StubRaceRepo? races,
}) {
  final sq = squads ?? _StubSquadRepo();
  return [
    crewControllerProvider.overrideWith(
      (ref) => CrewController(
        crew ?? _StubCrewRepo(),
        isPresentationDemo: () => false,
        cache: CacheStore.memory(),
        accountId: () => 'user-1',
      ),
    ),
    squadControllerProvider.overrideWith(
      (ref) =>
          SquadController(sq, CacheStore.memory(), accountId: () => 'user-1'),
    ),
    crewActivityProvider.overrideWith(
      (ref) => CrewActivityController(
        activity ?? _StubActivityRepo(),
        cache: CacheStore.memory(),
        accountId: () => 'user-1',
        demoUserId: () => 'user-1',
      ),
    ),
    squadRepositoryProvider.overrideWithValue(sq),
    raceRepositoryProvider.overrideWithValue(races ?? _StubRaceRepo()),
    authControllerProvider.overrideWith(
      (ref) => AuthController(_FakeAuthRepo()),
    ),
  ];
}

void _size(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.reset();
    NuvoFlags.crews.value = false;
  });
}

class _Probe extends StatelessWidget {
  const _Probe(this.label);
  final String label;
  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(label)));
}

void main() {
  setUpAll(loadShotFonts);
  setUp(() => NuvoFlags.crews.value = true);

  testWidgets('Crew tab populated: crews, racing now, requests, feed, '
      "friends' crews, friends", (tester) async {
    _size(tester);
    final crew = _StubCrewRepo(
      members: [
        _friend('user-3', 'Maya Miles'),
        _friend('user-4', 'Theo North'),
      ],
      requests: [_friend('u-kai', 'Kai Storm')],
      outgoing: [_friend('u-sam', 'Sam Vale')],
      mutuals: const {
        'u-kai': CrewRequestMutuals(
          count: 2,
          names: ['Priya Lane', 'Alex Row'],
        ),
      },
    );
    final squads = _StubSquadRepo(
      groups: [_group()],
      discoverItems: const [
        CrewDiscoverItem(
          id: 'c9',
          name: 'Night Owls',
          memberCount: 7,
          ownerName: 'Ben Carter',
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(
          crew: crew,
          squads: squads,
          activity: _StubActivityRepo(items: [_feedItem()]),
          races: _StubRaceRepo(races: [_sharedRace()]),
        ),
        child: const MaterialApp(home: CrewTabV13Screen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Crew'), findsWidgets);
    expect(find.text('Add friend'), findsOneWidget);
    expect(find.text('YOUR CREWS · 1'), findsOneWidget);
    expect(find.text('Sunrise Crew'), findsOneWidget);
    expect(find.text('4 members · Run by Ben Carter'), findsOneWidget);
    expect(find.text('#2 this week'), findsOneWidget);
    expect(find.text('Morning pushups · In 2 days'), findsOneWidget);
    expect(find.text('RACING RIGHT NOW'), findsOneWidget);
    // The cell names the movement now, not "Racing · <race title>".
    expect(find.text('Pushups'), findsWidgets);
    expect(find.text('Kai wants to race'), findsOneWidget);
    expect(find.text('Friends with Priya Lane and Alex Row'), findsOneWidget);
    expect(find.text('Waiting on Sam'), findsOneWidget);
    expect(find.text('WHAT YOUR CREW IS DOING'), findsOneWidget);
    expect(find.text('Maya submitted proof in Pushup Race'), findsOneWidget);
    expect(find.text('+40'), findsOneWidget);
    expect(find.text('Start a crew'), findsOneWidget);
    expect(find.text('Join with a code'), findsOneWidget);

    // Below-the-fold sections — scroll the main list to reveal them.
    await tester.drag(find.byType(ListView).first, const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text("YOUR FRIENDS' CREWS"), findsOneWidget);
    expect(find.text('Night Owls'), findsOneWidget);
    expect(find.text('Ask to join'), findsOneWidget);
    expect(find.text('FRIENDS · 2'), findsOneWidget);
    await shot(tester, 'v13_crew_tab_populated');
  });

  testWidgets('tour: My Nuvo code anchor exists only while the tour runs', (
    tester,
  ) async {
    _size(tester);
    final tour = runningTour(beat: 'crew');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [..._overrides(), ...tour.overrides],
        child: const MaterialApp(home: CrewTabV13Screen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(TourAnchors.rectOf(TourAnchor.myNuvoCode), isNotNull);
  });

  testWidgets('Crew tab empty state: real next actions, hidden sections', (
    tester,
  ) async {
    _size(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(),
        child: const MaterialApp(home: CrewTabV13Screen()),
      ),
    );
    // The hero floats forever; bounded pumps instead of pumpAndSettle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('YOUR CREWS · 0'), findsOneWidget);
    expect(
      find.text('No crews yet — start one or join with a code.'),
      findsOneWidget,
    );
    expect(find.text('Start a crew'), findsOneWidget);
    expect(find.text('Join with a code'), findsOneWidget);
    expect(find.text('RACING RIGHT NOW'), findsNothing);
    expect(find.text('Kai wants to race'), findsNothing);
    expect(find.text("YOUR FRIENDS' CREWS"), findsNothing);
    // No friends: the designed hero replaces the empty feed + friends rows.
    expect(find.text('Racing is better together'), findsOneWidget);
    expect(find.byType(V13QrPreview), findsOneWidget);
    expect(find.text('Share my code'), findsOneWidget);
    expect(find.text('Add friend'), findsNWidgets(2)); // top bar + hero link
    expect(find.text('Add your first friend'), findsNothing);
    expect(find.text('WHAT YOUR CREW IS DOING'), findsNothing);
    await shot(tester, 'v13_crew_tab_empty');
  });

  for (final (name, size) in [
    ('390x844', const Size(390, 844)),
    ('320x568', const Size(320, 568)),
  ]) {
    testWidgets('Crew tab empty hero layout at $name', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(),
          child: const MaterialApp(home: CrewTabV13Screen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await shot(tester, 'crew_empty_top_$name');
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await tester.pump(const Duration(milliseconds: 300));
      await shot(tester, 'crew_empty_bottom_$name');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Crew tab empty hero: reduce motion settles', (tester) async {
    _size(tester);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: ProviderScope(
          overrides: _overrides(),
          child: const MaterialApp(home: CrewTabV13Screen()),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('Racing is better together'), findsOneWidget);
  });

  testWidgets('Crew tab error rows + retry recovers', (tester) async {
    _size(tester);
    final crew = _StubCrewRepo(error: const ApiException(500, 'Server error'));
    final squads = _StubSquadRepo(
      listError: const ApiException(500, 'Server error'),
    );
    final activity = _StubActivityRepo(
      error: const ApiException(500, 'Server error'),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(crew: crew, squads: squads, activity: activity),
        child: const MaterialApp(home: CrewTabV13Screen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("Couldn't load your crews"), findsOneWidget);
    expect(find.text("Couldn't load your friends"), findsOneWidget);
    expect(find.text("Couldn't load your friends' activity"), findsOneWidget);
    expect(find.text('Retry'), findsNWidgets(3));
    await shot(tester, 'v13_crew_tab_error');
  });

  testWidgets('Crew tab taps push real routes; accept hits the repo', (
    tester,
  ) async {
    _size(tester);
    final crew = _StubCrewRepo(
      members: [_friend('user-3', 'Maya Miles')],
      requests: [_friend('u-kai', 'Kai Storm')],
    );
    final squads = _StubSquadRepo(groups: [_group()]);
    final router = GoRouter(
      initialLocation: '/pass',
      routes: [
        GoRoute(path: '/pass', builder: (_, _) => const CrewTabV13Screen()),
        GoRoute(
          path: '/crews/:id',
          builder: (_, s) => _Probe('crew:${s.pathParameters['id']}'),
        ),
        GoRoute(path: '/crew/add', builder: (_, _) => const _Probe('crew-add')),
        GoRoute(
          path: '/race/:id',
          builder: (_, s) => _Probe('race:${s.pathParameters['id']}'),
        ),
        GoRoute(
          path: '/u/:id',
          builder: (_, s) => _Probe('u:${s.pathParameters['id']}'),
        ),
        GoRoute(path: '/scan', builder: (_, _) => const _Probe('scan')),
        GoRoute(
          path: '/my-nuvo',
          builder: (_, state) => _Probe(
            state.uri.queryParameters['tab'] == 'scan' ? 'scan' : 'my-nuvo',
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(
          crew: crew,
          squads: squads,
          activity: _StubActivityRepo(items: [_feedItem()]),
        ),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    // Crew card → crew page.
    await tester.tap(find.text('Sunrise Crew'));
    await tester.pumpAndSettle();
    expect(find.text('crew:c1'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();

    // Feed row → its race destination.
    await tester.tap(find.text('Maya submitted proof in Pushup Race'));
    await tester.pumpAndSettle();
    expect(find.text('race:r1'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();

    // "See all" on Friends → the full friends list.
    await tester.tap(find.text('See all'));
    await tester.pumpAndSettle();
    expect(find.text('crew-add'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();

    // "Add friend" → the scanner.
    await tester.tap(find.text('Add friend'));
    await tester.pumpAndSettle();
    expect(find.text('scan'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();

    // Accept a request → controller mutation reaches the repo.
    await tester.tap(find.text('Accept'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(crew.accepted, contains('u-kai'));
  });

  testWidgets('Crew page populated: header, actions, leaderboard, recurring, '
      'members', (tester) async {
    _size(tester);
    final squads = _StubSquadRepo(
      groups: [_group()],
      detailData: _detail(),
      weekRows: const [
        CrewGroupStanding(
          userId: 'user-1',
          displayName: 'Test User',
          rank: 1,
          points: 6,
          wins: 1,
          races: 1,
          isYou: true,
        ),
      ],
    );
    final router = GoRouter(
      initialLocation: '/crews/c1',
      routes: [
        GoRoute(
          path: '/crews/:id',
          builder: (_, s) => CrewPageV13Screen(crewId: s.pathParameters['id']!),
        ),
        GoRoute(
          path: '/races/new',
          builder: (_, s) => _Probe(
            'new:${s.extra is RaceCreatePrefill ? (s.extra! as RaceCreatePrefill).crewId : 'none'}',
          ),
        ),
        GoRoute(
          path: '/my-nuvo',
          builder: (_, state) => _Probe(
            state.uri.queryParameters['tab'] == 'scan' ? 'scan' : 'my-nuvo',
          ),
        ),
        GoRoute(
          path: '/u/:id',
          builder: (_, s) => _Probe('u:${s.pathParameters['id']}'),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(squads: squads),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sunrise Crew'), findsWidgets);
    expect(find.text('Early runners only.'), findsOneWidget);
    expect(find.text('Start a crew race'), findsOneWidget);
    expect(find.text('Invite'), findsOneWidget);
    expect(find.text('CREW WINS'), findsOneWidget);
    expect(find.text('CREW STREAK'), findsOneWidget);
    expect(find.text('LEADERBOARD'), findsOneWidget);
    expect(find.text('This week'), findsOneWidget);
    expect(find.text('All time'), findsOneWidget);
    expect(find.text('Ben'), findsWidgets);
    expect(find.text('RECURRING RACES'), findsOneWidget);
    expect(find.text('Morning pushups'), findsOneWidget);
    expect(find.text('Every Monday · First to 100'), findsOneWidget);
    expect(find.text('MEMBERS · 4'), findsOneWidget);
    expect(find.text('Maya'), findsOneWidget);
    expect(find.text('You'), findsWidgets); // my row in standings + grid
    await shot(tester, 'v13_crew_page_populated');

    // This week → weekly rows from the W2 endpoint (Wren is all-time only).
    expect(find.text('Wren Fox'), findsNothing);
    // Flip to All time → detail payload rows.
    await tester.tap(find.text('All time'));
    await tester.pumpAndSettle();
    expect(find.text('Wren Fox'), findsOneWidget);

    // Primary action → /races/new with the crew prefill.
    await tester.tap(find.text('Start a crew race'));
    await tester.pumpAndSettle();
    expect(find.text('new:c1'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();

    // Invite → /my-nuvo.
    await tester.tap(find.text('Invite'));
    await tester.pumpAndSettle();
    expect(find.text('my-nuvo'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();

    // The 3-dot menu lists member actions.
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    expect(find.text('Share crew'), findsOneWidget);
    expect(find.text('Copy invite link'), findsOneWidget);
    expect(find.text('Mute crew'), findsOneWidget);
    expect(find.text('Leave crew'), findsOneWidget);
  });

  testWidgets('Crew page non-member preview: Ask to join', (tester) async {
    _size(tester);
    final squads = _StubSquadRepo(
      detailError: const ApiException(404, 'Not found'),
      previewData: const CrewGroupPreview(
        id: 'c9',
        name: 'Night Owls',
        memberCount: 7,
        ownerName: 'Ben Carter',
        bio: 'Late-night running crew.',
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(squads: squads),
        child: const MaterialApp(home: CrewPageV13Screen(crewId: 'c9')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Night Owls'), findsOneWidget);
    expect(find.text('7 members · Run by Ben Carter'), findsOneWidget);
    expect(find.text('Late-night running crew.'), findsOneWidget);
    expect(find.text('Ask to join'), findsOneWidget);
    await shot(tester, 'v13_crew_page_empty');

    await tester.tap(find.text('Ask to join'));
    await tester.pumpAndSettle();
    expect(squads.joinRequestsSent, contains('c9'));
    expect(find.text('Requested'), findsOneWidget);
  });

  testWidgets('Crew page error: retry rebuilds', (tester) async {
    _size(tester);
    final squads = _StubSquadRepo(
      detailError: const ApiException(500, 'Server error'),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(squads: squads),
        child: const MaterialApp(home: CrewPageV13Screen(crewId: 'c1')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("Couldn't load this crew"), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    await shot(tester, 'v13_crew_page_error');
  });
}

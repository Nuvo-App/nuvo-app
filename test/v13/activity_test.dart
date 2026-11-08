import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/core/cache/cache_store.dart';
import 'package:nuvo/core/v13/v13.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/crew/data/crew_api.dart';
import 'package:nuvo/features/crew/data/crew_repository.dart';
import 'package:nuvo/features/crew/application/crew_controller.dart';
import 'package:nuvo/features/notifications/application/notification_controller.dart';
import 'package:nuvo/features/notifications/data/notification_models.dart';
import 'package:nuvo/features/notifications/data/notification_repository.dart';
import 'package:nuvo/features/notifications/presentation/v13/activity_v13_screen.dart';
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/data/race_repository.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';
import 'package:nuvo/features/races/presentation/v13/submit_proof_sheet.dart';
import 'package:nuvo/features/social/domain/nuvo_destination.dart';

import '../helpers/screenshot.dart';

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

class _NotifRepo implements NotificationRepository {
  _NotifRepo({this.pages = const [], this.throws = false});

  /// First page, then any `loadMore` pages in order.
  final List<NotificationPage> pages;
  bool throws;
  int listCalls = 0;
  int markReadCalls = 0;
  int markAllReadCalls = 0;

  @override
  Future<NotificationPage> list({String? cursor, String? etag}) async {
    listCalls++;
    if (throws) {
      throw const ApiException(503, 'Service Unavailable');
    }
    if (cursor == null) return pages.first;
    final idx = listCalls - 1;
    return idx < pages.length ? pages[idx] : pages.last;
  }

  @override
  Future<void> markRead(String id) async => markReadCalls++;

  @override
  Future<void> markAllRead() async => markAllReadCalls++;
}

class _RacesRepo extends RaceRepository {
  _RacesRepo({this.races = const [], this.detailThrows = false})
    : super(RaceApi(), SecureTokenStore(), AuthApi());

  final List<Race> races;
  final bool detailThrows;
  int joinCalls = 0;

  @override
  Future<List<Race>> getRaces() async => races;

  @override
  Future<Race> getRaceDetail(String id) async {
    if (detailThrows) throw const ApiException(404, 'Not found');
    return races.firstWhere((r) => r.id == id);
  }

  @override
  Future<Race> joinRace(String id) async {
    joinCalls++;
    return races.firstWhere((r) => r.id == id);
  }
}

class _CrewRepo extends CrewRepository {
  _CrewRepo() : super(CrewApi(), SecureTokenStore(), AuthApi());

  int acceptCalls = 0;
  int declineCalls = 0;

  @override
  Future<CrewRequestPage> getRequestPage() async => const CrewRequestPage();

  @override
  Future<List<PublicUser>> getCrew() async => const [];

  @override
  Future<void> acceptRequest(String userId) async => acceptCalls++;

  @override
  Future<void> declineRequest(String userId) async => declineCalls++;
}

// ── Fixtures ─────────────────────────────────────────────────────────────────

NuvoNotification _notif({
  required String id,
  required String category,
  String? title,
  bool read = false,
  String? actorId,
  NuvoDestination? dest,
}) => NuvoNotification(
  id: id,
  category: category,
  title: title ?? 'Someone moved',
  createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
  read: read,
  destination: dest,
  actorId: actorId,
  actorName: actorId == null ? null : 'Noah',
);

Race _race(String id) => Race(
  id: id,
  creatorId: 'u-alex',
  title: 'Pushup Battle',
  goalType: 'count',
  activityId: 'pushups',
  aiActivityType: 'pushups',
  targetValue: 50,
  unit: 'reps',
  metric: 'reps',
  targetUnit: 'reps',
  status: 'active',
  createdAt: '2025-01-01T00:00:00Z',
  updatedAt: '2025-01-01T00:00:00Z',
);

// ── Harness ──────────────────────────────────────────────────────────────────

class _Stub extends StatelessWidget {
  const _Stub(this.label);
  final String label;
  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text('STUB $label')));
}

Widget _app({required _NotifRepo notifs, _RacesRepo? races, _CrewRepo? crew}) {
  final router = GoRouter(
    initialLocation: '/notifications',
    routes: [
      GoRoute(
        path: '/notifications',
        builder: (_, _) => const ActivityV13Screen(),
      ),
      GoRoute(path: '/arena', builder: (_, _) => const _Stub('arena')),
      GoRoute(
        path: '/race/:id/proof',
        builder: (_, s) => _Stub('proof ${s.pathParameters['id']}'),
      ),
      GoRoute(
        path: '/race/:id',
        builder: (_, s) => _Stub('race ${s.pathParameters['id']}'),
      ),
      GoRoute(path: '/profile', builder: (_, _) => const _Stub('profile')),
      GoRoute(
        path: '/u/:id',
        builder: (_, s) => _Stub('user ${s.pathParameters['id']}'),
      ),
      GoRoute(
        path: '/settings/notifications',
        builder: (_, _) => const _Stub('notif-settings'),
      ),
    ],
  );
  addTearDown(router.dispose);
  return ProviderScope(
    overrides: [
      notificationRepositoryProvider.overrideWithValue(notifs),
      raceRepositoryProvider.overrideWithValue(races ?? _RacesRepo()),
      crewRepositoryProvider.overrideWithValue(crew ?? _CrewRepo()),
      cacheStoreProvider.overrideWithValue(CacheStore.memory()),
      secureTokenStoreProvider.overrideWithValue(_FakeStore()),
      authControllerProvider.overrideWith(
        (ref) => AuthController(_FakeAuthRepo()),
      ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump();
}

void _viewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(loadShotFonts);

  testWidgets(
    'populated inbox groups New/Earlier, marks all read and shows actions',
    (tester) async {
      _viewport(tester);
      final repo = _NotifRepo(
        pages: [
          NotificationPage(
            unreadCount: 1,
            items: [
              _notif(
                id: 'n1',
                category: 'passed_on_leaderboard',
                title: 'Noah passed you in Pushup Battle',
                actorId: 'u-noah',
                dest: const RaceDestination('r1'),
              ),
              _notif(
                id: 'n2',
                category: 'race_joined',
                title: 'Sam joined Plank Party',
                read: true,
                dest: const RaceDestination('r2'),
              ),
            ],
          ),
        ],
      );
      await tester.pumpWidget(_app(notifs: repo));
      await _settle(tester);

      expect(find.text('NEW'), findsOneWidget);
      // Read items bucket by date: 5 minutes ago lands in Today.
      expect(find.text('TODAY'), findsOneWidget);
      expect(find.textContaining('Noah passed you in Pushup Battle', findRichText: true), findsOneWidget);
      expect(find.text('Take it back'), findsOneWidget);
      // Rows open on tap — no generic per-row View button.
      expect(find.text('View'), findsNothing);
      // Opening the screen clears the badge via read-all.
      expect(repo.markAllReadCalls, 1);
      await shot(tester, 'v13_activity_populated');
    },
  );

  testWidgets('empty inbox shows the caught-up state', (tester) async {
    _viewport(tester);
    final repo = _NotifRepo(
      pages: [const NotificationPage(items: [], unreadCount: 0)],
    );
    await tester.pumpWidget(_app(notifs: repo));
    await _settle(tester);

    expect(find.text('You’re all caught up'), findsOneWidget);
    expect(
      find.text('Race invites, friend requests and results will show up here.'),
      findsOneWidget,
    );
    await shot(tester, 'v13_activity_empty');
  });

  testWidgets('error state retries into the populated inbox', (tester) async {
    _viewport(tester);
    final repo = _NotifRepo(
      throws: true,
      pages: [
        NotificationPage(
          unreadCount: 1,
          items: [
            _notif(
              id: 'n1',
              category: 'race_joined',
              title: 'Sam joined Plank Party',
              read: true,
              dest: const RaceDestination('r2'),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(_app(notifs: repo));
    await _settle(tester);

    expect(find.text("Couldn't load activity"), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    await shot(tester, 'v13_activity_error');

    repo.throws = false;
    await tester.tap(find.text('Retry'));
    await _settle(tester);
    expect(find.textContaining('Sam joined Plank Party', findRichText: true), findsOneWidget);
    expect(repo.listCalls, greaterThan(1));
  });

  testWidgets('row tap marks read and routes to the destination', (
    tester,
  ) async {
    _viewport(tester);
    final repo = _NotifRepo(
      pages: [
        NotificationPage(
          unreadCount: 0,
          items: [
            _notif(
              id: 'n1',
              category: 'race_joined',
              title: 'Sam joined Plank Party',
              read: true,
              dest: const RaceDestination('r2'),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(_app(notifs: repo));
    await _settle(tester);

    await tester.tap(find.textContaining('Sam joined Plank Party', findRichText: true));
    await _settle(tester);
    expect(find.text('STUB race r2'), findsOneWidget);
  });

  testWidgets('Take it back opens the Submit proof sheet', (tester) async {
    _viewport(tester);
    final repo = _NotifRepo(
      pages: [
        NotificationPage(
          unreadCount: 1,
          items: [
            _notif(
              id: 'n1',
              category: 'passed_on_leaderboard',
              title: 'Noah passed you',
              actorId: 'u-noah',
              dest: const RaceDestination('r1'),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      _app(
        notifs: repo,
        races: _RacesRepo(races: [_race('r1')]),
      ),
    );
    await _settle(tester);

    await tester.tap(find.text('Take it back'));
    await _settle(tester);
    expect(find.byType(SubmitProofV13Sheet), findsOneWidget);
  });

  testWidgets('Take it back falls back to the proof route', (tester) async {
    _viewport(tester);
    final repo = _NotifRepo(
      pages: [
        NotificationPage(
          unreadCount: 1,
          items: [
            _notif(
              id: 'n1',
              category: 'passed_on_leaderboard',
              title: 'Noah passed you',
              actorId: 'u-noah',
              dest: const RaceDestination('r1'),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      _app(notifs: repo, races: _RacesRepo(detailThrows: true)),
    );
    await _settle(tester);

    await tester.tap(find.text('Take it back'));
    await _settle(tester);
    expect(find.text('STUB proof r1'), findsOneWidget);
  });

  testWidgets('race invite Accept joins and lands on the race', (tester) async {
    _viewport(tester);
    final races = _RacesRepo(races: [_race('r1')]);
    final repo = _NotifRepo(
      pages: [
        NotificationPage(
          unreadCount: 1,
          items: [
            _notif(
              id: 'n1',
              category: 'race_invite',
              title: 'Alex invited you to Pushup Battle',
              actorId: 'u-alex',
              dest: const RaceDestination('r1'),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(_app(notifs: repo, races: races));
    await _settle(tester);

    await tester.tap(find.text('Accept'));
    await _settle(tester);
    expect(races.joinCalls, 1);
    expect(find.text('STUB race r1'), findsOneWidget);
  });

  testWidgets('friend request Accept resolves through the crew flow', (
    tester,
  ) async {
    _viewport(tester);
    final crew = _CrewRepo();
    final repo = _NotifRepo(
      pages: [
        NotificationPage(
          unreadCount: 1,
          items: [
            _notif(
              id: 'n1',
              category: 'crew_request',
              title: 'Noah wants to connect',
              actorId: 'u-noah',
              dest: const ProfileDestination('u-noah'),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(_app(notifs: repo, crew: crew));
    await _settle(tester);

    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);
    await tester.tap(find.text('Accept'));
    await _settle(tester);
    expect(crew.acceptCalls, 1);
  });

  testWidgets('actor face taps through to the person', (tester) async {
    _viewport(tester);
    final repo = _NotifRepo(
      pages: [
        NotificationPage(
          unreadCount: 1,
          items: [
            _notif(
              id: 'n1',
              category: 'passed_on_leaderboard',
              title: 'Noah passed you',
              actorId: 'u-noah',
              dest: const RaceDestination('r1'),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(_app(notifs: repo));
    await _settle(tester);

    await tester.tap(find.byType(V13Face));
    await _settle(tester);
    expect(find.text('STUB user u-noah'), findsOneWidget);
  });
}

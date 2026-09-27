// THE root-destination correctness test: it pumps the REAL production
// router (`routerProvider` in lib/app/router.dart) — the same StatefulShellRoute
// the app runs — not a hand-built replica. Every other shell test
// constructs its own route table, which is why a wrong branch order once
// shipped while "all shell tests were green": they tested a copy.
//
// Per destination this asserts three things agree:
//   1. the rendered screen widget (content, not labels)
//   2. the highlighted nav item
//   3. the router's current location
//
// Canonical mapping under test:
//   0 Arena   /arena    → ArenaScreen
//   1 Compete /compete  → CompeteScreen
//   2 Verify  /move     → MoveScreen
//   3 Crew    /pass     → PassScreen
//   4 Profile /profile  → ProfileScreen
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/app/router.dart';
import 'package:nuvo/core/theme/app_colors.dart';
import 'package:nuvo/core/theme/app_theme.dart';
import 'package:nuvo/core/widgets/trackside_layout_diagnostics.dart';
import 'package:nuvo/features/arena/data/arena_api.dart';
import 'package:nuvo/features/arena/data/arena_models.dart';
import 'package:nuvo/features/arena/data/arena_repository.dart';
import 'package:nuvo/features/arena/presentation/arena_controller.dart';
import 'package:nuvo/features/arena/presentation/arena_screen.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/compete/presentation/compete_screen_fixed.dart';
import 'package:nuvo/features/crew/application/crew_controller.dart';
import 'package:nuvo/features/crew/data/crew_api.dart';
import 'package:nuvo/features/crew/data/crew_repository.dart';
import 'package:nuvo/features/move/presentation/move_screen.dart';
import 'package:nuvo/features/notifications/application/notification_controller.dart';
import 'package:nuvo/features/notifications/data/notification_models.dart';
import 'package:nuvo/features/notifications/data/notification_repository.dart';
import 'package:nuvo/features/onboarding/presentation/first_use_guide.dart';
import 'package:nuvo/features/pass/presentation/pass_screen.dart';
import 'package:nuvo/features/profile/presentation/profile_screen.dart';
import 'package:nuvo/features/races/data/motion_catalog.dart';
import 'package:nuvo/features/races/data/motion_catalog_cache.dart';
import 'package:nuvo/features/races/data/motion_catalog_repository.dart';
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/data/race_repository.dart';
import 'package:nuvo/features/races/presentation/motion_catalog_provider.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';
import 'package:nuvo/features/social/data/crew_activity.dart';

// ── Fakes (same pattern as shell_motion_test) ─────────────────────────────────

class _AuthRepo extends AuthRepository {
  _AuthRepo() : super(AuthApi(), SecureTokenStore());

  @override
  Future<RestoreResult> restoreSession() async => const RestoreOk(AuthUser(
        id: 'user-1',
        email: 'test@getnuvo.net',
        fullName: 'Test User',
        username: 'testuser',
        onboardingComplete: true,
        hasMemberPass: true,
        termsAccepted: true,
      ));
}

class _RaceRepo extends RaceRepository {
  _RaceRepo() : super(RaceApi(), SecureTokenStore(), AuthApi());

  @override
  Future<List<Race>> getRaces() async => const [];
}

class _ArenaRepo extends ArenaRepository {
  _ArenaRepo() : super(ArenaApi(), SecureTokenStore(), AuthApi());

  @override
  Future<ArenaSnapshot> getArenaSnapshot() async =>
      const ArenaSnapshot(mode: 'real', headerPulse: '');
}

class _CrewRepo implements CrewRepository {
  @override
  Future<List<PublicUser>> getCrew() async => const [];

  @override
  Future<CrewRequestPage> getRequestPage() async => const CrewRequestPage();

  @override
  Future<List<CrewSearchResult>> search(String query) async => const [];

  @override
  Future<PublicProfileCard> getUser(String userId) => throw UnimplementedError();
  @override
  Future<ConnectOutcome> add(String userId) async => ConnectOutcome.active;
  @override
  Future<void> acceptRequest(String userId) async {}
  @override
  Future<void> declineRequest(String userId) async {}
  @override
  Future<void> remove(String userId) async {}

  @override
  Future<void> reportUser(String userId, {String? reason}) async {}
  @override
  Future<void> reportRace(String raceId, {String? reason}) async {}
  @override
  Future<void> reportContent(String contentId, {String? reason}) async {}
  @override
  Future<void> blockUser(String userId) async {}
  @override
  Future<void> unblockUser(String userId) async {}
}

class _FeedRepo extends CrewActivityRepository {
  _FeedRepo() : super(CrewActivityApi(), SecureTokenStore(), AuthApi());

  @override
  Future<List<CrewActivityItem>> getFeed({int limit = 40, String? cursor}) =>
      Future.value(const []);
}

class _NotifRepo implements NotificationRepository {
  @override
  Future<NotificationPage> list({String? cursor}) async =>
      const NotificationPage(items: [], unreadCount: 0);
  @override
  Future<void> markRead(String id) async {}
  @override
  Future<void> markAllRead() async {}
}

class _CatalogRepo extends MotionCatalogRepository {
  _CatalogRepo() : super(RaceApi(), MotionCatalogCache());

  @override
  Future<MotionCatalogSnapshot> load({bool force = false}) async =>
      MotionCatalogSnapshot.bundled();
}

// ── Harness ───────────────────────────────────────────────────────────────────

class _App {
  _App(this.router, this.container);
  final GoRouter router;
  final ProviderContainer container;
}

/// Pumps the REAL router from lib/app/router.dart — same StatefulShellRoute,
/// same branch order, same _tabScreenFor — behind MaterialApp.router.
Future<_App> _pumpRealApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);

  final container = ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith((ref) => AuthController(_AuthRepo())),
      raceRepositoryProvider.overrideWithValue(_RaceRepo()),
      arenaRepositoryProvider.overrideWithValue(_ArenaRepo()),
      crewRepositoryProvider.overrideWithValue(_CrewRepo()),
      crewActivityRepositoryProvider.overrideWithValue(_FeedRepo()),
      notificationRepositoryProvider.overrideWithValue(_NotifRepo()),
      motionCatalogRepositoryProvider.overrideWithValue(_CatalogRepo()),
      // A guide-eligible account landing on /arena is redirected to /compete —
      // legitimate product behavior, not a mapping bug. Complete the guide so
      // this test exercises destination mapping only.
      firstRaceGuideProvider.overrideWith(
        (ref) => FirstRaceGuideStep.complete,
      ),
    ],
  );
  addTearDown(container.dispose);

  final router = container.read(routerProvider);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.light(),
        routerConfig: router,
      ),
    ),
  );
  // /splash → restore → SplashScreen hands off on its own timer; drive the
  // shell entry explicitly so the test doesn't depend on splash timing.
  await tester.pumpAndSettle();
  router.go('/arena');
  await tester.pumpAndSettle();
  return _App(router, container);
}

// ── Assertions ────────────────────────────────────────────────────────────────

/// label → (screen type marker, route path), canonical order.
final _matrix = <String, (Type screen, String path)>{
  'Arena': (ArenaScreen, '/arena'),
  'Compete': (CompeteScreen, '/compete'),
  'Verify': (MoveScreen, '/move'),
  'Crew': (PassScreen, '/pass'),
  'Profile': (ProfileScreen, '/profile'),
};

Finder _navLabel(String label) => find.descendant(
      of: find.byKey(TrackSideLayoutKeys.navigationRow),
      matching: find.text(label),
    );

Future<void> _tapNav(WidgetTester tester, String label) async {
  await tester.tap(_navLabel(label));
  await tester.pumpAndSettle();
}

void _expectDestination(_App app, WidgetTester tester, String label) {
  final (screenType, path) = _matrix[label]!;

  // 1. Content: the real screen widget is the visible root page.
  expect(
    find.byType(screenType),
    findsOneWidget,
    reason: 'tapping $label must render $screenType',
  );
  for (final other in _matrix.entries) {
    if (other.key == label) continue;
    expect(
      find.byType(other.value.$1),
      findsNothing,
      reason: '${other.key} must not be visible while $label is selected',
    );
  }

  // 2. Highlight: the destination's nav label reads through Nuvo blue.
  expect(
    tester.widget<Text>(_navLabel(label)).style?.color,
    NuvoColors.blue,
    reason: '$label must be the highlighted nav destination',
  );

  // 3. Location: the router agrees it is on the destination's path.
  expect(
    app.router.routerDelegate.currentConfiguration.uri.path,
    path,
    reason: '$label must resolve to $path',
  );
}

void main() {
  testWidgets('production router: every nav tap renders its own screen', (
    tester,
  ) async {
    final app = await _pumpRealApp(tester);

    // Boot lands on Arena; verify it before touching the nav.
    _expectDestination(app, tester, 'Arena');

    for (final label in _matrix.keys) {
      await _tapNav(tester, label);
      _expectDestination(app, tester, label);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('production router: full tour keeps body/nav/location aligned', (
    tester,
  ) async {
    final app = await _pumpRealApp(tester);
    for (final label in ['Crew', 'Compete', 'Profile', 'Verify', 'Arena']) {
      await _tapNav(tester, label);
      _expectDestination(app, tester, label);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('production router: deep links select the correct destination', (
    tester,
  ) async {
    final app = await _pumpRealApp(tester);
    for (final entry in _matrix.entries) {
      app.router.go(entry.value.$2);
      await tester.pumpAndSettle();
      _expectDestination(app, tester, entry.key);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('production router: branch order matches nav order', (
    tester,
  ) async {
    // The regression this guards: a StatefulShellRoute whose branches are
    // declared in a different order than the nav's index contract makes
    // goBranch(navIndex) land on the wrong screen while every label-level
    // test stays green. Assert the observable contract, not the structure.
    final app = await _pumpRealApp(tester);
    const taps = ['Compete', 'Verify', 'Crew', 'Arena', 'Profile'];
    for (final label in taps) {
      await _tapNav(tester, label);
      _expectDestination(app, tester, label);
    }
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:nuvo/core/theme/app_colors.dart';
import 'package:nuvo/core/theme/app_theme.dart';
import 'package:nuvo/core/widgets/bottom_nav.dart';
import 'package:nuvo/features/arena/data/arena_api.dart';
import 'package:nuvo/features/arena/data/arena_models.dart';
import 'package:nuvo/features/arena/data/arena_repository.dart';
import 'package:nuvo/features/arena/presentation/arena_controller.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/compete/presentation/compete_screen.dart';
import 'package:nuvo/features/move/presentation/move_screen.dart';
import 'package:nuvo/features/pass/presentation/pass_screen.dart';
import 'package:nuvo/features/profile/presentation/profile_screen.dart';
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/data/race_repository.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';
import 'package:nuvo/features/shell/presentation/main_shell.dart';
import 'package:nuvo/features/arena/presentation/arena_screen.dart';

/// Shared harness for rendering Nuvo's primary tabs in widget tests without
/// touching the network, real auth, or real storage.

class NuvoTab {
  const NuvoTab(this.name, this.route);
  final String name;
  final String route;
}

const kNuvoTabs = [
  NuvoTab('Arena', '/arena'),
  NuvoTab('Compete', '/compete'),
  NuvoTab('Verify', '/move'),
  NuvoTab('Crew', '/pass'),
  NuvoTab('Profile', '/profile'),
];

const kTestUser = AuthUser(
  id: 'u1',
  email: 'demo@nuvo.app',
  fullName: 'Nuvo Review',
  username: 'nuvoreview',
  onboardingComplete: true,
  hasMemberPass: true,
  termsAccepted: true,
);

// ── Fakes ────────────────────────────────────────────────────────────────────

class FakeAuthRepository extends AuthRepository {
  FakeAuthRepository() : super(AuthApi(), SecureTokenStore());

  @override
  Future<AuthUser?> restoreSession() async => kTestUser;

  @override
  Future<PassInfo> getMemberPass() async => const PassInfo(
        memberId: 'NUVO-KBHXKR',
        passSlug: 'nuvoreview',
        shareUrl: 'https://getnuvo.net/p/nuvoreview',
      );
}

class FakeRaceRepository extends RaceRepository {
  FakeRaceRepository({this.races = const []})
      : super(RaceApi(), SecureTokenStore(), AuthApi());

  final List<Race> races;

  @override
  Future<List<Race>> getRaces() async => races;

  @override
  Future<List<PublicUser>> getCrew() async => [];

  @override
  Future<List<PublicUser>> searchUsers(String query) async => [];
}

class FakeAuthController extends AuthController {
  FakeAuthController() : super(FakeAuthRepository());

  @override
  Future<void> sessionExpired() async {
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

class FakeRaceController extends RaceController {
  FakeRaceController({List<Race> races = const []})
      : super(FakeRaceRepository(races: races));
}

/// An ArenaController that never calls the network and exposes a fixed state.
class FakeArenaController extends ArenaController {
  FakeArenaController(this._fixed) : super(_FakeArenaRepository());

  final ArenaState _fixed;

  @override
  Future<void> loadSnapshot() async {
    if (mounted) state = _fixed;
  }
}

class _FakeArenaRepository extends ArenaRepository {
  _FakeArenaRepository()
      : super(ArenaApi(), SecureTokenStore(), AuthApi());

  @override
  Future<ArenaSnapshot> getArenaSnapshot() async =>
      const ArenaSnapshot(mode: 'real', headerPulse: '');
}

// ── Arena fixtures ───────────────────────────────────────────────────────────

ArenaMiniLeaderboardRow row(
  String label,
  String value, {
  bool me = false,
}) =>
    ArenaMiniLeaderboardRow(label: label, value: value, isCurrentUser: me);

ArenaBoard board({
  String id = 'r1',
  String title = 'First to 100 Pushups',
  String progressLabel = '65 / 100 reps',
  int? percent = 65,
  String actionLabel = 'Submit proof',
  String actionType = 'submit_proof',
  int? myRank = 2,
  int? racerCount = 3,
  int? daysLeft,
  bool isResult = false,
  List<ArenaMiniLeaderboardRow> leaderboard = const [],
}) =>
    ArenaBoard(
      id: id,
      source: 'real',
      title: title,
      progressLabel: progressLabel,
      boardContext: '35 to the finish line',
      primaryActionLabel: actionLabel,
      primaryActionType: actionType,
      progressPercent: percent,
      racerCount: racerCount,
      isResult: isResult,
      miniLeaderboard: leaderboard,
      myRank: myRank,
      daysLeft: daysLeft,
    );

ArenaActivity activity({
  String id = 'a1',
  String actor = 'Maya Chen',
  String text = 'Maya verified 20 pushups',
  String? raceTitle = 'First to 100 Pushups',
  String time = '12m ago',
  String type = 'proof_submitted',
}) =>
    ArenaActivity(
      id: id,
      actorName: actor,
      text: text,
      raceTitle: raceTitle,
      timeLabel: time,
      type: type,
    );

/// Convenience constructors for Arena snapshots in specific shapes.
abstract final class ArenaSnapshotBuilder {
  /// Exactly one active race.
  static ArenaSnapshot withBoard(ArenaBoard b) => ArenaSnapshot(
        mode: 'real',
        headerPulse: '',
        focusBoard: b,
      );

  /// Three active races, for pager behaviour.
  static ArenaSnapshot withBoards() => ArenaSnapshot(
        mode: 'real',
        headerPulse: '3 races live',
        focusBoard: board(),
        liveBoards: [
          board(
            id: 'r2',
            title: 'First to 60 Squats',
            progressLabel: '28 / 60 reps',
            percent: 47,
          ),
          board(
            id: 'r3',
            title: 'First to 40 Lunges',
            progressLabel: '0 / 40 reps',
            percent: 0,
          ),
        ],
      );
}

/// A populated Arena snapshot representing the normal demo state.
ArenaSnapshot populatedArena() => ArenaSnapshot(
      mode: 'real',
      headerPulse: '2 races need proof',
      focusBoard: board(
        leaderboard: [
          row('Maya Chen', '78 / 100'),
          row('Nuvo Review', '65 / 100', me: true),
          row('Dev Patel', '52 / 100'),
          row('Sam Okafor', '40 / 100'),
          row('Ana Ruiz', '31 / 100'),
        ],
      ),
      activity: [
        activity(),
        activity(id: 'a2', actor: 'Dev Patel', text: 'Dev joined the race', type: 'joined'),
        activity(id: 'a3', actor: 'Sam Okafor', text: 'Sam took the lead', type: 'leader_changed'),
      ],
    );

// ── Pumping ──────────────────────────────────────────────────────────────────

/// Builds the real shell + router for [initialRoute] with fakes wired in.
Widget buildNuvoApp({
  required String initialRoute,
  ArenaState? arenaState,
  List<Race> races = const [],
}) {
  final router = GoRouter(
    initialLocation: initialRoute,
    routes: [
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(path: '/arena', builder: (_, __) => const ArenaScreen()),
          GoRoute(path: '/compete', builder: (_, __) => const CompeteScreen()),
          GoRoute(path: '/move', builder: (_, __) => const MoveScreen()),
          GoRoute(path: '/pass', builder: (_, __) => const PassScreen()),
          GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
        ],
      ),
      // Destinations reached by primary actions.
      GoRoute(
          path: '/races/new',
          builder: (_, __) => const Scaffold(body: Text('New race'))),
      GoRoute(
          path: '/races/join',
          builder: (_, __) => const Scaffold(body: Text('Join race'))),
      GoRoute(
          path: '/race/:id',
          builder: (_, __) => const Scaffold(body: Text('Race room'))),
      GoRoute(
          path: '/race/:id/proof',
          builder: (_, __) => const Scaffold(body: Text('Submit proof'))),
      GoRoute(
          path: '/race/:id/invite',
          builder: (_, __) => const Scaffold(body: Text('Invite crew'))),
    ],
  );

  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith((ref) => FakeAuthController()),
      raceControllerProvider
          .overrideWith((ref) => FakeRaceController(races: races)),
      if (arenaState != null)
        arenaControllerProvider
            .overrideWith((ref) => FakeArenaController(arenaState)),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light(),
      darkTheme: AppTheme.light(),
      themeMode: ThemeMode.light,
      routerConfig: router,
    ),
  );
}

/// Pumps a tab at iPhone-14-Pro-like metrics, including a home-indicator inset.
Future<void> pumpNuvoTab(
  WidgetTester tester,
  String route, {
  Brightness platformBrightness = Brightness.light,
  ArenaState? arenaState,
  List<Race> races = const [],
  bool reduceMotion = false,
  Size size = const Size(390, 844),
  double bottomInset = 34,
  double topInset = 47,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.platformDispatcher.platformBrightnessTestValue =
      platformBrightness;
  tester.view.viewPadding = FakeViewPadding(
    top: topInset,
    bottom: bottomInset,
  );
  tester.view.padding = FakeViewPadding(
    top: topInset,
    bottom: bottomInset,
  );
  tester.view.platformDispatcher.accessibilityFeaturesTestValue =
      reduceMotion ? const FakeAccessibilityFeatures(disableAnimations: true)
                   : const FakeAccessibilityFeatures();

  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewPadding);
  addTearDown(tester.view.resetPadding);
  addTearDown(
      tester.view.platformDispatcher.clearPlatformBrightnessTestValue);
  addTearDown(tester
      .view.platformDispatcher.clearAccessibilityFeaturesTestValue);

  await tester.pumpWidget(buildNuvoApp(
    initialRoute: route,
    arenaState: arenaState,
    races: races,
  ));
  await tester.pumpAndSettle();
}

/// Asserts the floating nav pill is a white surface (never a dark bar).
void expectLightNavSurface(WidgetTester tester, String screenName) {
  final navFinder = find.byType(NuvoBottomNav);
  expect(navFinder, findsOneWidget, reason: '$screenName should have the nav');

  final pill = find
      .descendant(of: navFinder, matching: find.byType(Container))
      .evaluate()
      .map((e) => e.widget as Container)
      .firstWhere(
        (c) =>
            c.decoration is BoxDecoration &&
            (c.decoration as BoxDecoration).color == NuvoColors.surface,
        orElse: () => throw TestFailure(
          '$screenName: no white nav pill found — the navigation surface '
          'is not light.',
        ),
      );

  final deco = pill.decoration as BoxDecoration;
  expect(deco.color, NuvoColors.surface,
      reason: '$screenName nav pill must be white');
}

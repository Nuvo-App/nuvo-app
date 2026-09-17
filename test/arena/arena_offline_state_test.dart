// Arena's in-page connection-failure state (see AuthStatus.offline routing
// in auth_gate.dart / splash_screen.dart): no cached data shows a full
// "No connection" state; cached data stays visible with a compact banner
// instead of being replaced. Retry calls the real session retry path.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/race_repository.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';
import 'package:nuvo/features/shell/presentation/main_shell.dart';

const _user = AuthUser(
  id: 'user-1',
  email: 'test@getnuvo.net',
  onboardingComplete: true,
  hasMemberPass: true,
  termsAccepted: true,
);

class _ScriptedAuthRepo extends AuthRepository {
  _ScriptedAuthRepo(this._results) : super(AuthApi(), SecureTokenStore());
  final List<RestoreResult> _results;
  int _calls = 0;

  @override
  Future<RestoreResult> restoreSession() async {
    final r = _results[_calls.clamp(0, _results.length - 1)];
    _calls++;
    return r;
  }
}

class _EmptyArenaRepo extends ArenaRepository {
  _EmptyArenaRepo() : super(ArenaApi(), SecureTokenStore(), AuthApi());
  @override
  Future<ArenaSnapshot> getArenaSnapshot() async =>
      throw const ApiException(0, 'unreachable');
}

const _cachedBoard = ArenaBoard(
  id: 'race-1',
  source: 'real',
  title: 'First to 100 Pushups',
  progressLabel: '65 / 100 reps',
  boardContext: 'moving',
  primaryActionLabel: 'Submit proof',
  primaryActionType: 'submit_proof',
  progressPercent: 65,
  racerCount: 2,
  isResult: false,
);

class _CachedArenaRepo extends ArenaRepository {
  _CachedArenaRepo() : super(ArenaApi(), SecureTokenStore(), AuthApi());
  @override
  Future<ArenaSnapshot> getArenaSnapshot() async => const ArenaSnapshot(
    mode: 'real',
    headerPulse: '1 board needs proof',
    focusBoard: _cachedBoard,
  );
}

class _EmptyRaceRepo extends RaceRepository {
  _EmptyRaceRepo() : super(RaceApi(), SecureTokenStore(), AuthApi());
}

Future<ProviderContainer> _pumpArena(
  WidgetTester tester, {
  required RestoreResult authResult,
  required ArenaRepository arenaRepo,
  RestoreResult? retryResult,
}) async {
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
      authControllerProvider.overrideWith(
        (ref) => AuthController(
          _ScriptedAuthRepo([authResult, retryResult ?? const RestoreOk(_user)]),
        ),
      ),
      arenaRepositoryProvider.overrideWithValue(arenaRepo),
      raceRepositoryProvider.overrideWithValue(_EmptyRaceRepo()),
    ],
  );
  addTearDown(container.dispose);

  final router = GoRouter(
    initialLocation: '/arena',
    routes: [
      ShellRoute(
        builder: (c, s, child) => MainShell(child: child),
        routes: [
          GoRoute(path: '/arena', builder: (c, s) => const ArenaScreen()),
        ],
      ),
    ],
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets(
    'offline with no cached snapshot: shows a full "No connection" state',
    (tester) async {
      await _pumpArena(
        tester,
        authResult: const RestoreUnreachable(),
        arenaRepo: _EmptyArenaRepo(),
      );

      expect(find.text('No connection'), findsOneWidget);
      expect(
        find.text(
          "Nuvo couldn't load your races. Check your connection and try again.",
        ),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsWidgets);
      // Header + nav are still the normal Arena chrome, not replaced by a
      // bare error page (matches both the screen title and the nav label).
      expect(find.text('Arena'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'offline with a cached snapshot: content stays visible with a banner, '
    'not replaced',
    (tester) async {
      // Realistic sequence: the app was authenticated and already loaded a
      // snapshot (a real cache exists), then the connection drops on a
      // later revalidate — offline must not blank out what's already on
      // screen. (Going straight to offline on a cold launch, as the other
      // two tests do, never has a cache to begin with — arenaController
      // only starts loading once authenticated.)
      final container = await _pumpArena(
        tester,
        authResult: const RestoreOk(_user),
        retryResult: const RestoreUnreachable(),
        arenaRepo: _CachedArenaRepo(),
      );
      expect(find.text('First to 100 Pushups'), findsOneWidget);

      await container.read(authControllerProvider.notifier).retryRestore();
      await tester.pumpAndSettle();

      // The cached board is still on screen.
      expect(find.text('First to 100 Pushups'), findsOneWidget);
      // The compact banner is present instead of the full error state.
      expect(find.text('No connection'), findsNothing);
      expect(find.textContaining('No connection'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('retry calls the real session retry path and clears the '
      'offline state once it succeeds', (tester) async {
    final container = await _pumpArena(
      tester,
      authResult: const RestoreUnreachable(),
      arenaRepo: _CachedArenaRepo(),
    );
    expect(find.textContaining('No connection'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(container.read(authControllerProvider).status, AuthStatus.authenticated);
    expect(find.textContaining('No connection'), findsNothing);
  });
}

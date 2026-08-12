import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/compete/presentation/compete_screen.dart';
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/data/race_repository.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';
import 'package:nuvo/features/shell/presentation/main_shell.dart';

// ── Fixtures ─────────────────────────────────────────────────────────────────

const _kUser = AuthUser(
  id: 'u1',
  email: 'test@nuvo.app',
  fullName: 'Test User',
  username: 'test',
  onboardingComplete: true,
  hasMemberPass: true,
  termsAccepted: true,
);

// ── Mocks (same pattern as visual_system_golden_test) ────────────────────────

class _TestAuthRepository extends AuthRepository {
  _TestAuthRepository() : super(AuthApi(), SecureTokenStore());

  @override
  Future<AuthUser?> restoreSession() async => _kUser;

  @override
  Future<PassInfo> getMemberPass() async => const PassInfo(
        memberId: 'N-0001',
        passSlug: 'test',
        shareUrl: 'https://getnuvo.net/p/test',
      );
}

class _TestRaceRepository extends RaceRepository {
  _TestRaceRepository() : super(RaceApi(), SecureTokenStore(), AuthApi());

  @override
  Future<List<Race>> getRaces() async => [];

  @override
  Future<List<PublicUser>> getCrew() async => [];

  @override
  Future<List<PublicUser>> searchUsers(String query) async => [];
}

class _TestAuthController extends AuthController {
  _TestAuthController() : super(_TestAuthRepository());

  @override
  Future<void> sessionExpired() async {
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

class _TestRaceController extends RaceController {
  _TestRaceController() : super(_TestRaceRepository());
}

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('Compete actions', () {
    late GoRouter router;
    late String lastPushed;

    setUp(() {
      lastPushed = '';
      router = GoRouter(
        initialLocation: '/compete',
        routes: [
          ShellRoute(
            builder: (context, state, child) => MainShell(child: child),
            routes: [
              GoRoute(
                path: '/arena',
                builder: (context, state) => const SizedBox.shrink(),
              ),
              GoRoute(
                path: '/compete',
                builder: (context, state) => const CompeteScreen(),
              ),
              GoRoute(
                path: '/move',
                builder: (context, state) => const SizedBox.shrink(),
              ),
              GoRoute(
                path: '/pass',
                builder: (context, state) => const SizedBox.shrink(),
              ),
              GoRoute(
                path: '/profile',
                builder: (context, state) => const SizedBox.shrink(),
              ),
            ],
          ),
          GoRoute(
            path: '/races/join',
            builder: (context, state) {
              lastPushed = '/races/join';
              return const Scaffold(body: Text('Join Race'));
            },
          ),
          GoRoute(
            path: '/races/new',
            builder: (context, state) {
              lastPushed = '/races/new';
              return const Scaffold(body: Text('New Race'));
            },
          ),
        ],
      );
    });

    Widget buildApp() {
      return ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => _TestAuthController()),
          raceControllerProvider.overrideWith((ref) => _TestRaceController()),
        ],
        child: MaterialApp.router(routerConfig: router),
      );
    }

    testWidgets('Join race button is visible with readable text',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Find the Join race text anywhere in the widget tree
      final joinFinder = find.text('Join race');
      expect(joinFinder, findsOneWidget);
    });

    testWidgets('Join race navigates to /races/join', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Tap the Join race button
      final joinFinder = find.text('Join race');
      await tester.tap(joinFinder);
      await tester.pumpAndSettle();

      // Verify navigation occurred
      expect(lastPushed, '/races/join');
    });

    testWidgets('Start race navigates to /races/new', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Find and tap Start race
      final startFinder = find.text('Start race');
      expect(startFinder, findsWidgets);
      await tester.tap(startFinder.first);
      await tester.pumpAndSettle();

      expect(lastPushed, '/races/new');
    });
  });
}

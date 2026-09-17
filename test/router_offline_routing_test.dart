// RouterNotifier redirect coverage for the offline path — drives real
// navigation through a minimal router shaped like the app's own (see
// lib/app/router.dart + lib/features/auth/presentation/auth_gate.dart)
// rather than calling `redirect()` directly, so the test exercises the same
// GoRouter redirect-resolution loop the app actually runs on.
//
// Specifically covers the landmine called out when this routing was
// changed: authState.user! must never be dereferenced while offline
// (AuthState.user is null in that state) and MainShell must not be starved
// of its one entry point (Arena) while offline.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/auth/presentation/auth_gate.dart';

const _user = AuthUser(
  id: 'user-1',
  email: 'test@getnuvo.net',
  onboardingComplete: true,
  hasMemberPass: true,
  termsAccepted: true,
);

class _ScriptedAuthRepo extends AuthRepository {
  _ScriptedAuthRepo(this.result) : super(AuthApi(), SecureTokenStore());
  final RestoreResult result;

  @override
  Future<RestoreResult> restoreSession() async => result;
}

/// Never resolves — keeps AuthController genuinely stuck at
/// AuthStatus.loading for as long as the test needs, to check the redirect
/// decision made *during* that window (a `Future.value(result)` fake
/// resolves on the very next microtask, too fast to observe "loading").
class _PendingAuthRepo extends AuthRepository {
  _PendingAuthRepo() : super(AuthApi(), SecureTokenStore());

  @override
  Future<RestoreResult> restoreSession() => Completer<RestoreResult>().future;
}

class _Screen extends StatelessWidget {
  const _Screen(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Scaffold(body: Text(label));
}

/// Mirrors the app's real route shape closely enough to exercise
/// RouterNotifier: an unprotected splash + welcome, and protected arena /
/// profile (MainShell's tabs in the real app; plain screens here since the
/// redirect logic — not MainShell's own body — is under test).
///
/// Built via a plain ProviderContainer (not a Consumer inside the widget
/// tree) specifically so the GoRouter instance is created exactly once —
/// building it inside a widget that rebuilds on every auth-state change
/// recreates the router each time, which is not how the real app wires
/// this (routerProvider itself is a Provider, created once).
({GoRouter router, ProviderContainer container}) _buildRouter({
  RestoreResult? restoreResult,
  required String initialLocation,
}) {
  final container = ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith(
        (ref) => AuthController(
          restoreResult == null
              ? _PendingAuthRepo()
              : _ScriptedAuthRepo(restoreResult),
        ),
      ),
    ],
  );
  final notifier = container.read(routerNotifierProvider);
  final router = GoRouter(
    initialLocation: initialLocation,
    refreshListenable: notifier,
    redirect: notifier.redirect,
    routes: [
      GoRoute(path: '/splash', builder: (c, s) => const _Screen('splash')),
      GoRoute(path: '/welcome', builder: (c, s) => const _Screen('welcome')),
      GoRoute(path: '/arena', builder: (c, s) => const _Screen('arena')),
      GoRoute(path: '/profile', builder: (c, s) => const _Screen('profile')),
    ],
  );
  return (router: router, container: container);
}

Future<GoRouter> _pumpRouter(
  WidgetTester tester, {
  RestoreResult? restoreResult,
  String initialLocation = '/splash',
  bool settle = true,
}) async {
  final built = _buildRouter(
    restoreResult: restoreResult,
    initialLocation: initialLocation,
  );
  addTearDown(built.container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: built.container,
      child: MaterialApp.router(routerConfig: built.router),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  return built.router;
}

String _currentPath(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.path;

void main() {
  group('RouterNotifier', () {
    testWidgets('loading: a protected destination bounces to /splash', (
      tester,
    ) async {
      // restoreSession() is scripted to eventually resolve, but the
      // assertion that matters is the *first* redirect decision, made
      // while status is still loading — pump once (not pumpAndSettle) to
      // catch it before the async restore completes.
      final router = await _pumpRouter(
        tester,
        initialLocation: '/arena',
        settle: false,
      );
      expect(_currentPath(router), '/splash');
    });

    testWidgets('unauthenticated: a protected destination bounces to /welcome', (
      tester,
    ) async {
      final router = await _pumpRouter(
        tester,
        restoreResult: const RestoreNoSession(),
        initialLocation: '/arena',
      );
      expect(_currentPath(router), '/welcome');
    });

    testWidgets('authenticated: /arena is reachable directly', (tester) async {
      final router = await _pumpRouter(
        tester,
        restoreResult: const RestoreOk(_user),
        initialLocation: '/arena',
      );
      expect(_currentPath(router), '/arena');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'offline launch: /arena is reachable and never dereferences a null user',
      (tester) async {
        final router = await _pumpRouter(
          tester,
          restoreResult: const RestoreUnreachable(),
          initialLocation: '/arena',
        );
        expect(_currentPath(router), '/arena');
        // The historical landmine: `authState.user!` on a null user throws
        // a TypeError during redirect resolution, which surfaces here as a
        // FlutterError caught by the test framework.
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'offline: any OTHER protected destination bounces back to /arena, '
      'not left stranded on whatever was loading',
      (tester) async {
        final router = await _pumpRouter(
          tester,
          restoreResult: const RestoreUnreachable(),
          initialLocation: '/profile',
        );
        expect(_currentPath(router), '/arena');
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('offline: /splash itself is left alone (not force-redirected)', (
      tester,
    ) async {
      final router = await _pumpRouter(
        tester,
        restoreResult: const RestoreUnreachable(),
        initialLocation: '/splash',
      );
      expect(_currentPath(router), '/splash');
      expect(tester.takeException(), isNull);
    });
  });
}

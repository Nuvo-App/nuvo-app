// SplashScreen no longer becomes a permanent error/retry page when stored
// credentials exist but the server is unreachable — it finishes its launch
// animation and hands off to /arena, which owns the in-page connection
// state. Also covers: pumpAndSettle actually terminates now that the
// ambient dot-grid's infinitely-repeating AnimationController is gone.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/splash/presentation/splash_screen.dart';

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

class _Screen extends StatelessWidget {
  const _Screen(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Scaffold(body: Text(label));
}

Future<GoRouter> _pumpSplash(
  WidgetTester tester, {
  required RestoreResult restoreResult,
}) async {
  late final GoRouter router;
  final container = ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith(
        (ref) => AuthController(_ScriptedAuthRepo(restoreResult)),
      ),
    ],
  );
  addTearDown(container.dispose);
  router = GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(path: '/splash', builder: (c, s) => const SplashScreen()),
      GoRoute(path: '/arena', builder: (c, s) => const _Screen('arena')),
      GoRoute(
        path: '/welcome/intro',
        builder: (c, s) => const _Screen('welcome-intro'),
      ),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  // SplashScreen precaches 91 real PNG frames via precacheImage() before
  // starting its animation — real asset decoding, which needs the real
  // event loop (tester.runAsync), not just fake-clock pump() ticks, to
  // actually finish. Once that's done, the rest (frame animation, settle
  // animation, auto-continue Timer) all run on Flutter's normal
  // animation/timer clock, which pump() with an explicit duration does
  // advance correctly.
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
  });
  await tester.pump();
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return router;
}

String _currentPath(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.path;

void main() {
  testWidgets(
    'offline with stored credentials: splash finishes and hands off to /arena',
    (tester) async {
      final router = await _pumpSplash(
        tester,
        restoreResult: const RestoreUnreachable(),
      );
      expect(_currentPath(router), '/arena');
      // No permanent retry UI left behind on the splash route itself.
      expect(find.text("Couldn't reach Nuvo"), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('authenticated: splash hands off to /arena', (tester) async {
    final router = await _pumpSplash(tester, restoreResult: const RestoreOk(_user));
    expect(_currentPath(router), '/arena');
  });

  testWidgets('no stored session: splash hands off to /welcome/intro', (
    tester,
  ) async {
    final router = await _pumpSplash(
      tester,
      restoreResult: const RestoreNoSession(),
    );
    expect(_currentPath(router), '/welcome/intro');
  });
}

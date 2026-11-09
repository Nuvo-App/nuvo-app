// R2 + R3 (docs/statements/demo-account.md) at the router: where
// testing@getnuvo.net lands under both onboarding-v2 flag values.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/app/router.dart' show onboardingV2RouteRedirect;
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/auth/presentation/auth_gate.dart';
import 'package:nuvo/features/onboarding/presentation/first_use_guide.dart';

import 'onboarding_v2/auth_visuals_support.dart';

AuthUser _testing({required bool complete}) => AuthUser(
  id: 'review-1',
  email: 'testing@getnuvo.net',
  onboardingComplete: complete,
  hasMemberPass: true,
  termsAccepted: complete,
  ageAttested: complete,
  fullName: complete ? 'Maya Chen' : null,
  username: complete ? 'mayachen' : null,
  motionTrainingConsent: complete,
);

class _S extends StatelessWidget {
  const _S();
  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox());
}

Future<String> _land(
  WidgetTester tester, {
  required bool v2,
  required AuthUser user,
  required AuthIntent intent,
  required bool replay,
  required String start,
}) async {
  final auth = FakeAuth()
    ..state = AuthState(status: AuthStatus.authenticated, user: user);
  final c = ProviderContainer(
    overrides: [authControllerProvider.overrideWith((ref) => auth)],
  );
  addTearDown(c.dispose);
  c.read(authIntentProvider.notifier).state = intent;
  c.read(demoReplayProvider.notifier).state = replay;
  final n = c.read(
    ChangeNotifierProvider((ref) => RouterNotifier(ref, onboardingV2: v2)),
  );
  final router = GoRouter(
    initialLocation: start,
    redirectLimit: 6,
    refreshListenable: n,
    redirect: n.redirect,
    routes: [
      for (final p in [
        '/splash',
        '/welcome',
        '/arena',
        '/compete',
        '/onboarding-v2',
        '/onboarding/profile',
        '/onboarding/motion-consent',
        '/onboarding/nuvo',
        '/onboarding/notifications',
      ])
        GoRoute(
          path: p,
          redirect: p.startsWith('/onboarding')
              ? (_, s) =>
                    onboardingV2RouteRedirect(s.matchedLocation, enabled: v2)
              : null,
          builder: (_, _) => const _S(),
        ),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  return router.routerDelegate.currentConfiguration.uri.path;
}

void main() {
  const starts = ['/welcome', '/onboarding-v2', '/onboarding/nuvo', '/arena'];

  group('R2: Sign in skips onboarding entirely', () {
    for (final v2 in [true, false]) {
      for (final start in starts) {
        testWidgets('R2 flag=$v2 from $start lands in the app', (t) async {
          final path = await _land(
            t,
            v2: v2,
            user: _testing(complete: true),
            intent: AuthIntent.signIn,
            replay: false,
            start: start,
          );
          expect(path, '/arena');
        });
      }
    }
  });

  group('R3: Create account walks the full onboarding', () {
    for (final start in ['/welcome', '/arena', '/onboarding-v2']) {
      testWidgets('R3 flag=on from $start -> v2 flow', (t) async {
        final path = await _land(
          t,
          v2: true,
          user: _testing(complete: false),
          intent: AuthIntent.signUp,
          replay: true,
          start: start,
        );
        expect(path, '/onboarding-v2');
      });
      testWidgets('R3 flag=off from $start -> the real first-run setup', (
        t,
      ) async {
        final path = await _land(
          t,
          v2: false,
          user: _testing(complete: false),
          intent: AuthIntent.signUp,
          replay: true,
          start: start,
        );
        expect(path, startsWith('/onboarding/'));
      });
    }
  });
}

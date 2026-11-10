// The redirect-loop regression (store-review account, flag on):
// auth_gate -> /onboarding/profile -> route redirect -> /onboarding-v2 ->
// auth_gate -> /onboarding/profile ... Walks every owed-step state under
// both flag values and asserts the redirect chain is short and terminates.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/app/router.dart' show onboardingV2RouteRedirect;
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/auth/presentation/auth_gate.dart';
import 'package:nuvo/features/onboarding/presentation/first_use_guide.dart';

class _Repo extends AuthRepository {
  _Repo(this.result) : super(AuthApi(), SecureTokenStore());
  final RestoreResult result;
  @override
  Future<RestoreResult> restoreSession() async => result;
}

class _S extends StatelessWidget {
  const _S();
  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox());
}

AuthUser _user({
  String email = 'someone@example.com',
  bool complete = false,
  bool profile = false,
  bool consent = false,
  bool demo = false,
}) => AuthUser(
  isDemo: demo,
  id: 'u1',
  email: email,
  onboardingComplete: complete,
  hasMemberPass: true,
  termsAccepted: profile,
  ageAttested: profile,
  fullName: profile ? 'Test Person' : null,
  username: profile ? 'testperson' : null,
  motionTrainingConsent: consent,
);

void main() {
  const starts = [
    '/welcome',
    '/onboarding-v2',
    '/onboarding/profile',
    '/onboarding/motion-consent',
    '/onboarding/nuvo',
    '/onboarding/notifications',
  ];
  final states = <String, AuthUser>{
    'no profile': _user(),
    'profile, no consent': _user(profile: true),
    'all answered': _user(profile: true, consent: true),
    // Session restore detaches the literal store-review identity, so the
    // gate-equivalent backend-flagged demo account stands in for it.
    'review account': _user(email: 'review@example.com', demo: true),
  };

  for (final v2 in [true, false]) {
    for (final replay in [true, false]) {
      for (final e in states.entries) {
        for (final start in starts) {
          testWidgets('v2=$v2 replay=$replay ${e.key} from $start terminates', (
            tester,
          ) async {
            // Flag on: /onboarding-v2 is the single owner of every owed
            // state. Flag off: v1 behavior, only asserted loop-free.
            await _walkOrLoopFree(tester, v2, e.value, replay, start);
          });
        }
      }
    }
  }

  for (final v2 in [true, false]) {
    for (final replay in [true, false]) {
      testWidgets('v2=$v2 replay=$replay completed account reaches the app', (
        tester,
      ) async {
        for (final start in starts) {
          await _walkOrLoopFree(
            tester,
            v2,
            _user(email: 'review@example.com', demo: true, complete: true),
            replay,
            start,
            expectApp: v2,
          );
        }
      });
    }
  }
}

Future<void> _walkOrLoopFree(
  WidgetTester tester,
  bool v2,
  AuthUser user,
  bool replay,
  String start, {
  bool expectApp = false,
}) async {
  // Probe the real destination once, then assert the invariant.
  final container = ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith(
        (ref) => AuthController(_Repo(RestoreOk(user))),
      ),
    ],
  );
  addTearDown(container.dispose);
  container.read(demoReplayProvider.notifier).state = replay;
  final chain = <String>[];
  final notifier = container.read(
    ChangeNotifierProvider((ref) => RouterNotifier(ref, onboardingV2: v2)),
  );
  // Let session restore resolve first (the real app parks on /splash until
  // then); the redirect decisions under test are the authenticated ones.
  container.read(authControllerProvider);
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  final router = GoRouter(
    initialLocation: start,
    redirectLimit: 6,
    refreshListenable: notifier,
    redirect: (c, s) {
      final d = notifier.redirect(c, s);
      if (d != null) chain.add('${s.matchedLocation}->$d');
      return d;
    },
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
              ? (c, s) {
                  final d = onboardingV2RouteRedirect(
                    s.matchedLocation,
                    enabled: v2,
                  );
                  if (d != null) chain.add('${s.matchedLocation}=>$d');
                  return d;
                }
              : null,
          builder: (c, s) => const _S(),
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
  final path = router.routerDelegate.currentConfiguration.uri.path;
  final label =
      'v2=$v2 replay=$replay start=$start ${user.email} '
      'complete=${user.onboardingComplete} -> $path chain=$chain';
  expect(tester.takeException(), isNull, reason: label);
  expect(chain.length <= 3, isTrue, reason: label);
  if (v2 && !user.onboardingComplete && start != '/welcome') {
    expect(path, '/onboarding-v2', reason: label);
  }
  if (expectApp) {
    expect(path == '/arena' || path == '/compete', isTrue, reason: label);
  }
}

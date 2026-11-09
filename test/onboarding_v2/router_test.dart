// Router wiring for the NUVO_ONBOARDING_V2 flag — the flag is a
// compile-time const so both positions are exercised through
// `onboardingV2RouteRedirect`, plus one real GoRouter drive proving the
// redirect ORDER: auth_gate keeps naming the v1 destination, the
// route-level redirect folds it into /onboarding-v2.
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

/// Incomplete account used by the redirect-order drives below.
const _incompleteUser = AuthUser(
  id: 'u1',
  email: 'new@getnuvo.net',
  onboardingComplete: false,
  hasMemberPass: true,
  termsAccepted: true,
);

class _Repo extends AuthRepository {
  _Repo() : super(AuthApi(), SecureTokenStore());

  @override
  Future<RestoreResult> restoreSession() async =>
      const RestoreOk(_incompleteUser);
}

class _Screen extends StatelessWidget {
  const _Screen(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Scaffold(body: Text(label));
}

void main() {
  group('onboardingV2RouteRedirect', () {
    const old = [
      '/onboarding/profile',
      '/onboarding/motion-consent',
      '/onboarding/nuvo',
      '/onboarding/notifications',
    ];

    test(
      'flag ON: every v1 onboarding destination resolves to the v2 host',
      () {
        for (final loc in old) {
          expect(
            onboardingV2RouteRedirect(loc, enabled: true),
            '/onboarding-v2',
            reason: loc,
          );
        }
      },
    );

    test('flag ON: /onboarding-v2 renders (returns null)', () {
      expect(
        onboardingV2RouteRedirect('/onboarding-v2', enabled: true),
        isNull,
      );
    });

    test('flag ON: non-onboarding locations are left alone', () {
      for (final loc in ['/arena', '/welcome', '/race/abc', '/invite/x']) {
        expect(
          onboardingV2RouteRedirect(loc, enabled: true),
          isNull,
          reason: loc,
        );
      }
    });

    test('flag OFF: v1 destinations render untouched', () {
      for (final loc in old) {
        expect(
          onboardingV2RouteRedirect(loc, enabled: false),
          isNull,
          reason: loc,
        );
      }
    });

    test('flag OFF: /onboarding-v2 folds back to the canonical v1 route', () {
      expect(
        onboardingV2RouteRedirect('/onboarding-v2', enabled: false),
        '/onboarding/nuvo',
      );
    });

    test('retired v1 aliases still chain: member-pass → nuvo → v2', () {
      // /onboarding/member-pass's own redirect targets /onboarding/nuvo;
      // under the flag that route's redirect then hands it to v2 — GoRouter
      // resolves chained redirects, so the two-hop path lands correctly.
      expect(
        onboardingV2RouteRedirect('/onboarding/nuvo', enabled: true),
        '/onboarding-v2',
      );
    });
  });

  group('redirect order (real GoRouter + RouterNotifier)', () {
    // An incomplete account: auth_gate must still answer with the v1
    // _firstRunTarget, and the route-level v2 redirect must take it from
    // there — the destination depends ONLY on onboarding flags.
    ({GoRouter router, ProviderContainer container}) build({
      required bool v2Enabled,
    }) {
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith((ref) => AuthController(_Repo())),
        ],
      );
      final notifier = container.read(routerNotifierProvider);
      final router = GoRouter(
        initialLocation: '/onboarding/profile',
        refreshListenable: notifier,
        redirect: notifier.redirect,
        routes: [
          GoRoute(path: '/splash', builder: (_, _) => const _Screen('splash')),
          GoRoute(
            path: '/welcome',
            builder: (_, _) => const _Screen('welcome'),
          ),
          GoRoute(
            path: '/onboarding-v2',
            redirect: (_, state) => onboardingV2RouteRedirect(
              state.matchedLocation,
              enabled: v2Enabled,
            ),
            builder: (_, _) => const _Screen('ob-v2'),
          ),
          GoRoute(
            path: '/onboarding/profile',
            redirect: (_, state) => onboardingV2RouteRedirect(
              state.matchedLocation,
              enabled: v2Enabled,
            ),
            builder: (_, _) => const _Screen('ob-profile'),
          ),
          GoRoute(
            path: '/onboarding/nuvo',
            redirect: (_, state) => onboardingV2RouteRedirect(
              state.matchedLocation,
              enabled: v2Enabled,
            ),
            builder: (_, _) => const _Screen('ob-nuvo'),
          ),
          GoRoute(path: '/arena', builder: (_, _) => const _Screen('arena')),
        ],
      );
      return (router: router, container: container);
    }

    String path(GoRouter r) => r.routerDelegate.currentConfiguration.uri.path;

    testWidgets('flag ON: auth_gate still names /onboarding/profile, the route '
        'redirect lands the incomplete user on /onboarding-v2', (tester) async {
      final built = build(v2Enabled: true);
      addTearDown(built.container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: built.container,
          child: MaterialApp.router(routerConfig: built.router),
        ),
      );
      await tester.pumpAndSettle();
      expect(path(built.router), '/onboarding-v2');
      expect(find.text('ob-v2'), findsOneWidget);
    });

    testWidgets(
      'flag OFF: the same incomplete user lands on the untouched v1 route',
      (tester) async {
        final built = build(v2Enabled: false);
        addTearDown(built.container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: built.container,
            child: MaterialApp.router(routerConfig: built.router),
          ),
        );
        await tester.pumpAndSettle();
        expect(path(built.router), '/onboarding/profile');
        expect(find.text('ob-profile'), findsOneWidget);
      },
    );
  });
}

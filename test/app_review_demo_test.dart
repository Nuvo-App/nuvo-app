// App Review demo-account contract — the canonical store-review identity
// (testing@getnuvo.net) replays the deterministic first-use experience on
// every cold launch, while normal accounts never replay once onboarding is
// done. Also covers the auth back/loading fix and the real OTP resend
// cooldown that share this flow.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/core/widgets/nuvo_button.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/auth/presentation/auth_gate.dart';
import 'package:nuvo/features/auth/presentation/email_start_screen.dart';
import 'package:nuvo/features/auth/presentation/email_verify_screen.dart';
import 'package:nuvo/features/onboarding/data/first_use_store.dart';
import 'package:nuvo/features/onboarding/presentation/first_use_guide.dart';

const _reviewerUser = AuthUser(
  id: 'reviewer-1',
  email: 'testing@getnuvo.net',
  isDemo: true,
  fullName: 'Nuvo Review',
  username: 'nuvoreview',
  onboardingComplete: true,
  hasMemberPass: true,
  termsAccepted: true,
);

const _memberUser = AuthUser(
  id: 'member-1',
  email: 'member@example.com',
  onboardingComplete: true,
  hasMemberPass: true,
  termsAccepted: true,
);

/// Scripted auth repo — records calls; reviewer sign-in returns the demo
/// account; startEmailAuth can be held pending or failed per test.
class _AuthRepo extends AuthRepository {
  _AuthRepo({this.user = _memberUser})
    : super(AuthApi(), SecureTokenStore());

  AuthUser user;
  RestoreResult restoreResult = const RestoreNoSession();
  final emailStarts = <String>[];
  Completer<void>? pendingEmail;
  bool failEmail = false;
  bool failReviewer = false;

  @override
  Future<RestoreResult> restoreSession() async => restoreResult;

  @override
  Future<void> startEmailAuth(String email) async {
    emailStarts.add(email);
    if (pendingEmail != null) await pendingEmail!.future;
    if (failEmail) throw const ApiException(0, 'unreachable');
  }

  @override
  Future<AuthUser> signInReviewer(String email, String password) async {
    if (failReviewer) {
      throw const ApiException(401, 'Invalid review credentials');
    }
    return user;
  }

  @override
  Future<AuthUser> verifyEmailCode(String email, String code) async => user;
}

class _Screen extends StatelessWidget {
  const _Screen(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Scaffold(body: Text(label));
}

/// Minimal route table shaped like the app's auth-relevant routes, wired
/// through the REAL RouterNotifier so assertions exercise the actual guard.
({GoRouter router, ProviderContainer container}) _buildRouter({
  required AuthRepository repo,
  required String initialLocation,
  FirstUseStore? store,
}) {
  final container = ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith((ref) => AuthController(repo)),
      firstUseStoreProvider.overrideWithValue(store ?? FirstUseStore.memory()),
    ],
  );
  final notifier = container.read(routerNotifierProvider);
  final router = GoRouter(
    initialLocation: initialLocation,
    refreshListenable: notifier,
    redirect: notifier.redirect,
    routes: [
      GoRoute(path: '/welcome', builder: (_, _) => const _Screen('welcome')),
      GoRoute(
        path: '/auth/email',
        builder: (_, _) => const _Screen('email'),
      ),
      GoRoute(
        path: '/auth/verify',
        builder: (_, _) => const _Screen('verify'),
      ),
      GoRoute(
        path: '/onboarding/nuvo',
        builder: (_, _) => const _Screen('nuvo-story'),
      ),
      GoRoute(
        path: '/onboarding/notifications',
        builder: (_, _) => const _Screen('notifications'),
      ),
      GoRoute(path: '/arena', builder: (_, _) => const _Screen('arena')),
      GoRoute(path: '/compete', builder: (_, _) => const _Screen('compete')),
      GoRoute(path: '/profile', builder: (_, _) => const _Screen('profile')),
    ],
  );
  return (router: router, container: container);
}

Future<({GoRouter router, ProviderContainer container})> _pumpAt(
  WidgetTester tester, {
  required AuthRepository repo,
  required String location,
  FirstUseStore? store,
}) async {
  final built = _buildRouter(
    repo: repo,
    initialLocation: location,
    store: store,
  );
  addTearDown(built.container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: built.container,
      child: MaterialApp.router(routerConfig: built.router),
    ),
  );
  await tester.pumpAndSettle();
  return built;
}

String _path(GoRouter router) =>
    router.routerDelegate.currentConfiguration.last.matchedLocation;

void main() {
  group('resetDemoExperienceForColdLaunch', () {
    test('clears only Nuvo-owned experience flags for the demo account',
        () async {
      final store = FirstUseStore.memory();
      await store.ensureLoaded();
      await store.markNotificationPromptOwed();
      await store.markCameraPrimerSeen();
      await store.markIntroSeen();
      await store.markGuideDone(_reviewerUser.email);
      await store.markGuideDone('other@example.com');

      final container = ProviderContainer(
        overrides: [firstUseStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      container.read(firstRaceGuideProvider.notifier).state =
          FirstRaceGuideStep.composerGoal;

      await resetDemoExperienceForColdLaunch(container.read, _reviewerUser);

      expect(container.read(demoReplayProvider), isTrue);
      expect(
        container.read(firstRaceGuideProvider),
        FirstRaceGuideStep.idle,
      );
      expect(store.isNotificationPromptOwed, isFalse);
      expect(store.isCameraPrimerSeen, isFalse);
      expect(store.introSeen, isFalse);
      expect(store.isGuideDone(_reviewerUser.email), isFalse);
      // Other accounts' completions on the same install are untouched.
      expect(store.isGuideDone('other@example.com'), isTrue);
    });

    test('is a no-op for ordinary accounts', () async {
      final store = FirstUseStore.memory();
      await store.ensureLoaded();
      await store.markGuideDone(_memberUser.email);
      final container = ProviderContainer(
        overrides: [firstUseStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);

      await resetDemoExperienceForColdLaunch(container.read, _memberUser);

      expect(container.read(demoReplayProvider), isFalse);
      expect(
        container.read(firstRaceGuideProvider),
        FirstRaceGuideStep.idle,
      );
      expect(store.isGuideDone(_memberUser.email), isTrue);
    });

    test('replays every time it is called — not once per install', () async {
      final store = FirstUseStore.memory();
      await store.ensureLoaded();
      final container = ProviderContainer(
        overrides: [firstUseStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);

      // Simulate a completed first run, then a second cold launch.
      await resetDemoExperienceForColdLaunch(container.read, _reviewerUser);
      await store.markGuideDone(_reviewerUser.email);
      container.read(demoReplayProvider.notifier).state = false;

      await resetDemoExperienceForColdLaunch(container.read, _reviewerUser);
      expect(container.read(demoReplayProvider), isTrue);
      expect(store.isGuideDone(_reviewerUser.email), isFalse);
    });
  });

  group('route guard during demo replay', () {
    testWidgets(
      'armed replay forces every authenticated destination to the story',
      (tester) async {
        final repo = _AuthRepo(user: _reviewerUser)
          ..restoreResult = const RestoreOk(_reviewerUser);
        final built = await _pumpAt(tester, repo: repo, location: '/arena');
        built.container.read(demoReplayProvider.notifier).state = true;
        for (final loc in ['/arena', '/profile', '/welcome', '/auth/email']) {
          built.router.go(loc);
          await tester.pumpAndSettle();
          expect(_path(built.router), '/onboarding/nuvo', reason: loc);
        }
      },
    );

    testWidgets(
      'reviewer sign-in with an armed replay lands on the story, not the app',
      (tester) async {
        final repo = _AuthRepo(user: _reviewerUser);
        final built = await _pumpAt(tester, repo: repo, location: '/welcome');
        // Mirrors the email screen: the flag is armed before the sign-in
        // publishes auth state so this redirect already sees it.
        built.container.read(demoReplayProvider.notifier).state = true;
        await built.container
            .read(authControllerProvider.notifier)
            .signInReviewer('testing@getnuvo.net', 'pw');
        await tester.pumpAndSettle();
        expect(_path(built.router), '/onboarding/nuvo');
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'normal account without replay still lands on /arena — no regression',
      (tester) async {
        final repo = _AuthRepo(user: _memberUser);
        final built = await _pumpAt(tester, repo: repo, location: '/welcome');
        await built.container
            .read(authControllerProvider.notifier)
            .verifyEmailCode('member@example.com', '123456');
        await tester.pumpAndSettle();
        expect(_path(built.router), '/arena');
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('email start — back/loading recovery', () {
    Future<({GoRouter router, ProviderContainer container, _AuthRepo repo})>
    pumpEmailFlow(WidgetTester tester, {_AuthRepo? repo}) async {
      final repository = repo ?? _AuthRepo();
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => AuthController(repository),
          ),
          firstUseStoreProvider.overrideWithValue(FirstUseStore.memory()),
        ],
      );
      addTearDown(container.dispose);
      final router = GoRouter(
        initialLocation: '/auth/email',
        routes: [
          GoRoute(
            path: '/auth/email',
            builder: (_, _) => const EmailStartScreen(),
          ),
          GoRoute(
            path: '/auth/verify',
            builder: (_, state) =>
                Scaffold(body: Text('code for ${state.extra}')),
          ),
          GoRoute(path: '/welcome', builder: (_, _) => const _Screen('welcome')),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      return (router: router, container: container, repo: repository);
    }

    testWidgets(
      'submit → code screen → back leaves the form usable, no stuck spinner',
      (tester) async {
        final flow = await pumpEmailFlow(tester);
        await tester.enterText(find.byType(TextField), 'member@example.com');
        await tester.pump();
        await tester.tap(find.text('Send code'));
        await tester.pumpAndSettle();
        expect(_path(flow.router), '/auth/verify');

        // Back to the email screen — the button must be live, not spinning.
        flow.router.pop();
        await tester.pumpAndSettle();
        expect(_path(flow.router), '/auth/email');
        final button = tester.widget<NuvoPrimaryButton>(
          find.byType(NuvoPrimaryButton),
        );
        expect(button.loading, isFalse);
        expect(button.onPressed, isNotNull);

        // Immediate retry works.
        await tester.tap(find.text('Send code'));
        await tester.pumpAndSettle();
        expect(flow.repo.emailStarts.length, 2);
        expect(_path(flow.router), '/auth/verify');
      },
    );

    testWidgets(
      'double-tap fires one request; failure clears loading and allows retry',
      (tester) async {
        final repo = _AuthRepo()..pendingEmail = Completer<void>();
        final flow = await pumpEmailFlow(tester, repo: repo);
        await tester.enterText(find.byType(TextField), 'member@example.com');
        await tester.pump();
        await tester.tap(find.text('Send code'));
        await tester.pump();
        // While in-flight the button shows a spinner — tap the widget itself.
        await tester.tap(find.byType(NuvoPrimaryButton));
        await tester.pump();
        expect(repo.emailStarts.length, 1, reason: 'second tap is disabled');

        // Fail the in-flight request — loading clears, form stays usable.
        repo.failEmail = true;
        repo.pendingEmail!.complete();
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<NuvoPrimaryButton>(find.byType(NuvoPrimaryButton))
              .loading,
          isFalse,
        );
        expect(find.textContaining('Check your connection'), findsOneWidget);

        repo.pendingEmail = null;
        repo.failEmail = false;
        await tester.tap(find.text('Send code'));
        await tester.pumpAndSettle();
        expect(repo.emailStarts.length, 2);
        expect(_path(flow.router), '/auth/verify');
      },
    );

    testWidgets(
      'back during an in-flight request does not corrupt the session or push '
      'the code screen afterwards',
      (tester) async {
        final repo = _AuthRepo()..pendingEmail = Completer<void>();
        final flow = await pumpEmailFlow(tester, repo: repo);
        await tester.enterText(find.byType(TextField), 'member@example.com');
        await tester.pump();
        await tester.tap(find.text('Send code'));
        await tester.pump();
        flow.router.go('/welcome');
        await tester.pump();
        repo.pendingEmail!.complete();
        await tester.pumpAndSettle();
        // The mounted-guard prevented the stale push — still on /welcome.
        expect(_path(flow.router), '/welcome');
        expect(
          flow.container.read(authControllerProvider).status,
          AuthStatus.unauthenticated,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'testing@getnuvo.net routes to the password path, not the inbox code',
      (tester) async {
        final flow = await pumpEmailFlow(tester);
        await tester.enterText(
          find.byType(TextField),
          '  TESTING@GETNUVO.NET ',
        );
        await tester.pump();
        expect(find.byType(TextField), findsNWidgets(2));
        expect(
          tester.widget<TextField>(find.byType(TextField).last).obscureText,
          isTrue,
        );
        // No code is sent for the review identity.
        expect(flow.repo.emailStarts, isEmpty);
      },
    );

    testWidgets(
      'wrong reviewer password: clean error, armed replay restored, retry works',
      (tester) async {
        final repo = _AuthRepo(user: _reviewerUser)..failReviewer = true;
        final flow = await pumpEmailFlow(tester, repo: repo);
        await tester.enterText(
          find.byType(TextField).first,
          'testing@getnuvo.net',
        );
        await tester.pump(); // the password field mounts on reviewer email
        await tester.enterText(find.byType(TextField).last, 'wrong');
        await tester.pump();
        await tester.tap(find.text('Sign in'));
        await tester.pumpAndSettle();

        // Clean error, live button, no silent navigation.
        expect(find.text('Invalid review credentials.'), findsOneWidget);
        expect(
          tester
              .widget<NuvoPrimaryButton>(find.byType(NuvoPrimaryButton))
              .loading,
          isFalse,
        );
        // A failed credential must not leave the demo replay armed — a normal
        // account signing in next would get bounced into the story.
        expect(flow.container.read(demoReplayProvider), isFalse);

        repo.failReviewer = false;
        await tester.enterText(find.byType(TextField).last, 'review-pass');
        await tester.pump();
        await tester.tap(find.text('Sign in'));
        await tester.pumpAndSettle();
        expect(
          flow.container.read(authControllerProvider).status,
          AuthStatus.authenticated,
        );
        // The successful retry re-arms the replay for the route guard.
        expect(flow.container.read(demoReplayProvider), isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('OTP resend', () {
    Future<ProviderContainer> pumpVerify(
      WidgetTester tester, {
      required _AuthRepo repo,
    }) async {
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith((ref) => AuthController(repo)),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: EmailVerifyScreen(email: 'member@example.com'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      return container;
    }

    testWidgets(
      'cooldown counts down, enables resend, and a real send restarts it',
      (tester) async {
        final repo = _AuthRepo();
        await pumpVerify(tester, repo: repo);
        expect(find.text("Didn't get a code?"), findsOneWidget);
        expect(find.text('Resend code in 30s'), findsOneWidget);

        // Disabled during the countdown — no duplicate send is possible.
        await tester.tap(find.textContaining('Resend code in'));
        await tester.pump();
        expect(repo.emailStarts, isEmpty);

        await tester.pump(const Duration(seconds: 30));
        expect(find.text('Resend code'), findsOneWidget);
        await tester.tap(find.text('Resend code'));
        await tester.pumpAndSettle();
        expect(repo.emailStarts, ['member@example.com']);
        expect(find.text('New code sent'), findsOneWidget);
        expect(find.textContaining('Resend code in'), findsOneWidget);
      },
    );

    testWidgets('a failed resend keeps typed digits and stays recoverable', (
      tester,
    ) async {
      final repo = _AuthRepo()..failEmail = true;
      await pumpVerify(tester, repo: repo);
      await tester.enterText(find.byType(TextField).first, '1');
      await tester.pump(const Duration(seconds: 31));
      await tester.tap(find.text('Resend code'));
      await tester.pumpAndSettle();
      expect(repo.emailStarts, isNotEmpty);
      expect(
        find.textContaining('Check your connection'),
        findsOneWidget,
      );
      // The typed code is preserved — the failure was a send failure, not a
      // code failure.
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '1',
      );
      await tester.pump(const Duration(seconds: 31));
      repo.failEmail = false;
      await tester.tap(find.text('Resend code'));
      await tester.pumpAndSettle();
      expect(find.text('New code sent'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

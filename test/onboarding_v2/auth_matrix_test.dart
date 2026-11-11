// The intended-behavior matrix for sign-in / create-account:
//   entry {login sheet, "Create one" page} x provider {apple, google, email}
//   x account {new, existing} (+ testing@getnuvo.net, email only).
//
// Intended:
// - A NEW account (any provider, either entry) is created and walks into
//   player setup (S7).
// - An EXISTING account (any provider, either entry) logs straight in and
//   NEVER enters onboarding (destination /arena).
// - testing@getnuvo.net: sign-in skips onboarding (R2); create account walks
//   it (R3).
// - "Create one" shows a choice page; email is never chosen for the player.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/core/analytics/analytics_service.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/auth/presentation/auth_gate.dart';
import 'package:nuvo/features/onboarding/auth_visuals/social_sign_in.dart';
import 'package:nuvo/features/onboarding/data/first_run_flag.dart';
import 'package:nuvo/features/onboarding/data/onboarding_v2_store.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_flow_controller.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_step.dart';
import 'package:nuvo/features/onboarding/onboarding_v2_screen.dart';

import 'auth_visuals_support.dart';

AuthUser _user(String email, {required bool complete}) => AuthUser(
  id: 'u-$email',
  email: email,
  onboardingComplete: complete,
  hasMemberPass: true,
  termsAccepted: complete,
  ageAttested: complete,
  fullName: complete ? 'Existing Person' : null,
  username: complete ? 'existing' : null,
  motionTrainingConsent: complete,
);

/// What the server would return for each provider call.
class _ScriptedAuth extends FakeAuth {
  _ScriptedAuth(this.account);

  /// The person's account: existing (complete) or new (not yet).
  final AuthUser account;

  void _in(AuthUser u) =>
      state = AuthState(status: AuthStatus.authenticated, user: u);

  @override
  Future<void> verifyEmailCode(String email, String code) async {
    verified.add(code);
    _in(account);
  }

  @override
  Future<void> signInWithApple(
    String idToken, {
    String? fullName,
    String? authorizationCode,
  }) async => _in(account);

  @override
  Future<void> signInWithGoogle(String idToken) async => _in(account);

  @override
  Future<void> signInReviewer(
    String email,
    String password, {
    required AuthIntent intent,
  }) async {
    reviewerSignIns.add('$email|$password|${intent.name}');
    // R2: sign in -> the seeded complete account. R3: create -> reset account.
    _in(_user(email, complete: intent == AuthIntent.signIn));
  }
}

class _Rig {
  _Rig(this.container, this.router, this.auth);
  final ProviderContainer container;
  final GoRouter router;
  final _ScriptedAuth auth;

  String get location => router.routerDelegate.currentConfiguration.uri.path;
  OnboardingStep get step => container.read(onboardingFlowProvider).step;
}

Future<void> _pumpFor(WidgetTester t, [int ms = 1500]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<_Rig> _boot(WidgetTester t, AuthUser account) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = const Size(390, 844);
  addTearDown(t.view.reset);
  final auth = _ScriptedAuth(account);
  final container = ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith((ref) => auth),
      obSocialSignInProvider.overrideWithValue(FakeSocial()),
      onboardingV2StoreProvider.overrideWithValue(OnboardingV2Store.memory()),
      analyticsProvider.overrideWithValue(FakeAnalyticsService()),
      // Not the first open: a signed-out user lands on the login sheet.
      firstRunFlagProvider.overrideWithValue(MemoryFirstRunFlag(done: true)),
    ],
  );
  addTearDown(container.dispose);
  final notifier = container.read(
    ChangeNotifierProvider((ref) => RouterNotifier(ref, onboardingV2: true)),
  );
  final router = GoRouter(
    initialLocation: '/onboarding-v2',
    redirectLimit: 8,
    refreshListenable: notifier,
    redirect: notifier.redirect,
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SizedBox()),
      GoRoute(
        path: '/onboarding-v2',
        builder: (_, _) => const OnboardingV2Screen(),
      ),
      GoRoute(
        path: '/arena',
        builder: (_, _) => const Scaffold(body: Text('ARENA')),
      ),
    ],
  );
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await _pumpFor(t, 2000);
  return _Rig(container, router, auth);
}

enum _Entry { login, createPage }

enum _Provider { apple, google, email }

Future<void> _tapKey(WidgetTester t, String key) async {
  final f = find.byKey(ValueKey(key));
  expect(f, findsOneWidget, reason: key);
  await t.tap(f);
  await _pumpFor(t, 1200);
}

Future<void> _enter(WidgetTester t, _Rig rig, _Entry entry) async {
  expect(rig.step, OnboardingStep.signIn); // never the intro again
  if (entry == _Entry.createPage) {
    await _tapKey(t, 'ob-create-link');
    expect(rig.step, OnboardingStep.createAccount);
    // The choice page offers all three; nothing is pre-chosen.
    expect(find.byKey(const ValueKey('ob-apple')), findsOneWidget);
    expect(find.byKey(const ValueKey('ob-google')), findsOneWidget);
    expect(find.byKey(const ValueKey('ob-create-email')), findsOneWidget);
    expect(rig.step, isNot(OnboardingStep.email));
  }
}

Future<void> _choose(WidgetTester t, _Rig rig, _Entry e, _Provider p) async {
  switch (p) {
    case _Provider.apple:
      await _tapKey(t, 'ob-apple');
    case _Provider.google:
      await _tapKey(t, 'ob-google');
    case _Provider.email:
      await _tapKey(t, e == _Entry.login ? 'ob-email-link' : 'ob-create-email');
      expect(rig.step, OnboardingStep.email);
      await t.enterText(
        find.byKey(const ValueKey('ob-email-field')),
        'ava@gmail.com',
      );
      await _pumpFor(t, 400);
      await _tapKey(t, 'onboarding-cta'); // Send code
      expect(rig.step, OnboardingStep.code);
      await t.enterText(find.byKey(const ValueKey('ob-code-field')), '123456');
      await _pumpFor(t, 1500);
      // A NEW account stays on the flow and taps Next on the verified
      // screen; an EXISTING one was already routed to the app.
      if (rig.location == '/onboarding-v2') {
        await _tapKey(t, 'onboarding-cta');
      }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final entry in _Entry.values) {
    for (final provider in _Provider.values) {
      testWidgets('NEW account via ${provider.name} from ${entry.name}: '
          'created and walks into player setup', (t) async {
        final rig = await _boot(t, _user('ava@gmail.com', complete: false));
        await _enter(t, rig, entry);
        await _choose(t, rig, entry, provider);
        expect(rig.location, '/onboarding-v2');
        expect(rig.step, OnboardingStep.playerCard);
        expect(find.text('ARENA'), findsNothing);
      });

      testWidgets('EXISTING account via ${provider.name} from ${entry.name}: '
          'straight in, onboarding bypassed', (t) async {
        final rig = await _boot(t, _user('ava@gmail.com', complete: true));
        await _enter(t, rig, entry);
        await _choose(t, rig, entry, provider);
        expect(rig.location, '/arena');
        expect(find.text('ARENA'), findsOneWidget);
        expect(rig.step, isNot(OnboardingStep.playerCard));
      });
    }
  }

  testWidgets('R2: testing@ signs in (login sheet) -> skips onboarding', (
    t,
  ) async {
    final rig = await _boot(t, _user('testing@getnuvo.net', complete: true));
    await _enter(t, rig, _Entry.login);
    await _tapKey(t, 'ob-email-link');
    await t.enterText(
      find.byKey(const ValueKey('ob-email-field')),
      'testing@getnuvo.net',
    );
    await _pumpFor(t, 400);
    await t.enterText(
      find.byKey(const ValueKey('ob-email-password')),
      'testing123',
    );
    await _pumpFor(t, 300);
    await _tapKey(t, 'onboarding-cta');
    expect(
      rig.auth.reviewerSignIns.single,
      'testing@getnuvo.net|testing123|signIn',
    );
    expect(rig.location, '/arena');
    expect(rig.step, isNot(OnboardingStep.playerCard));
  });

  testWidgets('R3: testing@ create account (Create one) -> walks onboarding', (
    t,
  ) async {
    final rig = await _boot(t, _user('testing@getnuvo.net', complete: false));
    await _enter(t, rig, _Entry.createPage);
    await _tapKey(t, 'ob-create-email');
    await t.enterText(
      find.byKey(const ValueKey('ob-email-field')),
      'testing@getnuvo.net',
    );
    await _pumpFor(t, 400);
    await t.enterText(
      find.byKey(const ValueKey('ob-email-password')),
      'testing123',
    );
    await _pumpFor(t, 300);
    await _tapKey(t, 'onboarding-cta');
    expect(
      rig.auth.reviewerSignIns.single,
      'testing@getnuvo.net|testing123|signUp',
    );
    expect(rig.location, '/onboarding-v2');
    expect(rig.step, OnboardingStep.playerCard);
  });

  testWidgets('a "Create one" player who goes back lands on the login sheet', (
    t,
  ) async {
    final rig = await _boot(t, _user('ava@gmail.com', complete: false));
    await _enter(t, rig, _Entry.createPage);
    await _tapKey(t, 'ob-have-account-link');
    expect(rig.step, OnboardingStep.signIn);
    expect(find.byKey(const ValueKey('ob-create-link')), findsOneWidget);
  });
}

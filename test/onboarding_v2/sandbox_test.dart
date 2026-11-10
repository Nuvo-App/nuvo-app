// Practice mode (Settings > Replay onboarding): the whole v2 flow runs in an
// isolated container. Nothing reaches the real account, analytics or store,
// and leaving returns to the app exactly as it was.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/core/analytics/analytics_service.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/onboarding/data/onboarding_v2_store.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_flow_controller.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_step.dart';
import 'package:nuvo/features/onboarding/sandbox/onboarding_sandbox.dart';

/// Stands in for the REAL account controller: any call at all is a leak.
class _Tripwire extends StateNotifier<AuthState> implements AuthController {
  _Tripwire()
    : super(
        const AuthState(
          status: AuthStatus.authenticated,
          user: AuthUser(
            id: 'real',
            email: 'sideswifter2010@gmail.com',
            fullName: 'Real Name',
            username: 'realuser',
            onboardingComplete: true,
            hasMemberPass: true,
            termsAccepted: true,
          ),
        ),
      );

  final List<String> calls = [];

  @override
  dynamic noSuchMethod(Invocation i) {
    calls.add(i.memberName.toString());
    return super.noSuchMethod(i);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('practice run: zero real writes/analytics; exit restores', (
    t,
  ) async {
    final real = _Tripwire();
    final realAnalytics = FakeAnalyticsService();
    final realStore = OnboardingV2Store.memory();
    final sandboxAnalytics = FakeAnalyticsService();
    final sandbox = buildSandboxContainer(analytics: sandboxAnalytics);
    addTearDown(sandbox.dispose);

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: Builder(
              builder: (c) => TextButton(
                onPressed: () => c.push('/practice'),
                child: const Text('HOME'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/practice',
          builder: (_, _) => OnboardingSandbox(container: sandbox),
        ),
      ],
    );
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => real),
          analyticsProvider.overrideWithValue(realAnalytics),
          onboardingV2StoreProvider.overrideWithValue(realStore),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await t.tap(find.text('HOME'));
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const ValueKey('practice-tag')), findsOneWidget);

    // Walk the whole flow inside the sandbox.
    final flow = sandbox.read(onboardingFlowProvider.notifier);
    final auth = sandbox.read(authControllerProvider.notifier);
    await flow.skipIntros();
    await auth.signInWithApple('x');
    await auth.saveProfile(fullName: 'Practice', username: 'practice');
    for (final s in [
      OnboardingStep.signIn,
      OnboardingStep.email,
      OnboardingStep.code,
      OnboardingStep.playerCard,
      OnboardingStep.questions1,
      OnboardingStep.questions2,
      OnboardingStep.firstRaceReady,
    ]) {
      await flow.completeStep(s);
    }
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
    expect(sandbox.read(onboardingFlowProvider).step, OnboardingStep.levelUp);
    await flow.graduate();
    await flow.completeStep(OnboardingStep.levelUp);
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }

    // Zero leaks: the real account/analytics/store were never touched.
    expect(real.calls, isEmpty);
    expect(realAnalytics.events, isEmpty);
    expect(realStore.completedSteps, isEmpty);
    expect(real.state.user?.fullName, 'Real Name');
    expect(real.state.user?.onboardingComplete, isTrue);
    // Practice analytics stayed in the throwaway fake.
    expect(
      sandbox.read(authControllerProvider).user?.email,
      isNot('sideswifter2010@gmail.com'),
    );
    // Exit: back on the app, as it was.
    expect(find.text('HOME'), findsOneWidget);
    expect(find.byKey(const ValueKey('practice-tag')), findsNothing);
  });

  testWidgets('the Practice tag exits at any point', (t) async {
    final sandbox = buildSandboxContainer();
    addTearDown(sandbox.dispose);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: Builder(
              builder: (c) => TextButton(
                onPressed: () => c.push('/practice'),
                child: const Text('HOME'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/practice',
          builder: (_, _) => OnboardingSandbox(container: sandbox),
        ),
      ],
    );
    await t.pumpWidget(MaterialApp.router(routerConfig: router));
    await t.tap(find.text('HOME'));
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.tap(find.byKey(const ValueKey('practice-tag')));
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('HOME'), findsOneWidget);
  });
}

// Part A intro steps — S0 splash handoff, S1 tap duel, S2 skeleton loop,
// S3 board climb. Tests drive the real OnboardingV2Screen host (not the
// step widgets in isolation) so completion, skipping and advancement are
// asserted against the real flow order.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/analytics/analytics_service.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/onboarding/data/onboarding_v2_store.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_copy.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_flow_controller.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_step.dart';
import 'package:nuvo/features/onboarding/intro/intro_race_step.dart';
import 'package:nuvo/features/onboarding/intro/splash_step.dart';
import 'package:nuvo/features/onboarding/onboarding_v2_screen.dart';

class _NoSessionRepo extends AuthRepository {
  _NoSessionRepo() : super(AuthApi(), SecureTokenStore());

  @override
  Future<RestoreResult> restoreSession() async => const RestoreNoSession();
}

/// A never-resolving auth repo — the splash's tap-to-skip must wait on it.
class _PendingRepo extends AuthRepository {
  _PendingRepo() : super(AuthApi(), SecureTokenStore());

  @override
  Future<RestoreResult> restoreSession() => Completer<RestoreResult>().future;
}

/// Pumps the real flow host with a signed-out scripted auth repo and an
/// in-memory store. Returns the container for provider assertions.
Future<ProviderContainer> _pumpFlow(
  WidgetTester tester, {
  AuthRepository? authRepo,
}) async {
  final container = ProviderContainer(
    overrides: [
      onboardingV2StoreProvider.overrideWithValue(OnboardingV2Store.memory()),
      analyticsProvider.overrideWithValue(FakeAnalyticsService()),
      authControllerProvider.overrideWith(
        (ref) => AuthController(authRepo ?? _NoSessionRepo()),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: OnboardingV2Screen()),
    ),
  );
  return container;
}

OnboardingStep _step(ProviderContainer c) =>
    c.read(onboardingFlowProvider).step;

/// Pumps [seconds] in coarse steps (never pumpAndSettle — ambient floats
/// run forever by design).
Future<void> _pumpFor(WidgetTester tester, double seconds) async {
  final steps = (seconds * 10).ceil();
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('S0 ObSplashStep', () {
    testWidgets('auto-advances to the duel after the hold', (tester) async {
      final c = await _pumpFlow(tester);
      await _pumpFor(tester, 2.5);
      expect(_step(c), OnboardingStep.introRace);
      expect(find.byType(ObIntroRaceStep), findsOneWidget);
    });

    testWidgets('tap skips once auth resolved', (tester) async {
      final c = await _pumpFlow(tester);
      await tester.pump(); // auth resolves on the microtask flush
      await tester.tap(find.byType(ObSplashStep));
      // Let S1 mount and its staggered enter delays fire (they are
      // Future.delayed timers that would otherwise leak past test end).
      await _pumpFor(tester, 1);
      expect(_step(c), OnboardingStep.introRace);
    });

    testWidgets('tap before auth resolves does not skip', (tester) async {
      final c = await _pumpFlow(tester, authRepo: _PendingRepo());
      await tester.pump();
      await tester.tap(find.byType(ObSplashStep));
      await tester.pump();
      expect(_step(c), OnboardingStep.splash);
    });
  });

  group('S1 ObIntroRaceStep', () {
    Finder card() => find.byKey(const ValueKey('ob-duel-card'));
    Finder cta() => find.byKey(const ValueKey('onboarding-cta'));

    /// Lands on S1 through the real splash handoff.
    Future<ProviderContainer> onRaceStep(WidgetTester tester) async {
      final c = await _pumpFlow(tester);
      await _pumpFor(tester, 2.5);
      expect(find.byType(ObIntroRaceStep), findsOneWidget);
      return c;
    }

    testWidgets('taps score beads and the scripted duel always wins', (
      tester,
    ) async {
      await onRaceStep(tester);
      expect(find.text(ObCopy.introRaceHint), findsOneWidget);

      for (var i = 0; i < 10; i++) {
        await tester.tap(card(), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(find.text('10'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(find.text(ObCopy.introRaceWin), findsOneWidget);
    });

    testWidgets('early Next auto-plays and lands on introCamera', (
      tester,
    ) async {
      final c = await onRaceStep(tester);
      await tester.tap(cta());
      await _pumpFor(tester, 2.5);
      expect(_step(c), OnboardingStep.introCamera);
    });

    testWidgets('Skip compresses the intros onto signIn', (tester) async {
      final c = await onRaceStep(tester);
      await tester.tap(find.text(ObCopy.skip));
      await _pumpFor(tester, 1);
      expect(_step(c), OnboardingStep.signIn);
    });

    testWidgets('idle hand pointer appears once and never loops', (
      tester,
    ) async {
      await onRaceStep(tester);
      await _pumpFor(tester, 3.2);
      expect(find.byIcon(Icons.back_hand_rounded), findsOneWidget);
      await _pumpFor(tester, 2.5);
      expect(find.byIcon(Icons.back_hand_rounded), findsNWidgets(1));
    });
  });
}

// Part A intro steps — S0 splash handoff, S1 tap duel, S2 how-it-works
// (camera proof + board climb on one screen). Tests drive the real OnboardingV2Screen host (not the
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
import 'package:nuvo/features/onboarding/intro/intro_how_step.dart';
import 'package:nuvo/features/onboarding/intro/intro_race_step.dart';
import 'package:nuvo/features/onboarding/intro/splash_step.dart';
import 'package:nuvo/features/onboarding/onboarding_v2_screen.dart';
import 'package:nuvo/features/onboarding/shell/track_painter.dart';

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

    testWidgets('a fast tapper reaches the flag; ghosts end 1-2 beads back', (
      tester,
    ) async {
      await onRaceStep(tester);
      for (var i = 0; i < 20; i++) {
        await tester.tap(card(), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text(ObCopy.introRaceWin), findsOneWidget);

      final tokens = tester
          .widgetList<AnimatedPositioned>(find.byType(AnimatedPositioned))
          .toList();
      // Three lanes, one token each — the user's (middle) rides furthest.
      final lefts = [for (final t in tokens) t.left!];
      expect(lefts.length, 3);
      expect(lefts[1], greaterThan(lefts[0]));
      expect(lefts[1], greaterThan(lefts[2]));
    });

    testWidgets('tokens stay inside their lane, 16px clear of the card edge', (
      tester,
    ) async {
      await onRaceStep(tester);
      final cardRect = tester.getRect(card());
      for (var i = 0; i < 20; i++) {
        await tester.tap(card(), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(seconds: 1));
      for (final e in find.byType(AnimatedPositioned).evaluate()) {
        final r = tester.getRect(find.byWidget(e.widget));
        expect(r.left, greaterThanOrEqualTo(cardRect.left + 16));
        expect(r.right, lessThanOrEqualTo(cardRect.right - 16));
      }
    });

    testWidgets('early Next auto-plays and lands on the how-it-works screen', (
      tester,
    ) async {
      final c = await onRaceStep(tester);
      await tester.tap(cta());
      await _pumpFor(tester, 2.5);
      expect(_step(c), OnboardingStep.introHow);
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

    testWidgets('pre-auth screen paints no Track behind the copy', (
      tester,
    ) async {
      await onRaceStep(tester);
      expect(find.byType(TrackBackground), findsNothing);
    });
  });

  group('S2 ObIntroHowStep', () {
    Finder cta() => find.byKey(const ValueKey('onboarding-cta'));
    Finder meRow() => find.byKey(const ValueKey('You'));

    AnimatedOpacity pill(WidgetTester tester) => tester.widget<AnimatedOpacity>(
      find.byKey(const ValueKey('ob-verified-pill')),
    );

    double meTop(WidgetTester tester) =>
        tester.widget<AnimatedPositioned>(meRow()).top!;

    /// Lands on S2 through the real flow: splash auto-advances, then the
    /// S1 duel auto-plays off an early Next.
    Future<ProviderContainer> onHowStep(WidgetTester tester) async {
      final c = await _pumpFlow(tester);
      await _pumpFor(tester, 2.5);
      await tester.tap(cta());
      await _pumpFor(tester, 2.5);
      expect(find.byType(ObIntroHowStep), findsOneWidget);
      return c;
    }

    testWidgets('reps count on squat bottoms and verify after three', (
      tester,
    ) async {
      await onHowStep(tester);
      expect(pill(tester).opacity, 0);

      await _pumpFor(tester, 2.4); // ~2 squat bottoms at 1.4 s/rep
      expect(pill(tester).opacity, 0);

      await _pumpFor(tester, 1.4); // third bottom lands
      expect(pill(tester).opacity, 1);
      expect(find.text(ObCopy.introCameraPill), findsOneWidget);
    });

    testWidgets('your row starts 4th and climbs to 1st after the proof', (
      tester,
    ) async {
      await onHowStep(tester);
      expect(find.text(ObCopy.introBoardCta), findsOneWidget);
      expect(find.text(ObCopy.introBoardLogin), findsOneWidget);
      expect(find.text(ObCopy.skip), findsOneWidget);
      final fourth = meTop(tester);
      expect(fourth, greaterThan(0));

      await _pumpFor(tester, 3.0);
      expect(meTop(tester), fourth); // still waiting on the proof
      await _pumpFor(tester, 4.0);
      expect(meTop(tester), 0.0);
    });

    testWidgets('tapping the phone replays the rep count', (tester) async {
      await onHowStep(tester);
      await _pumpFor(tester, 2.5);
      await tester.tap(
        find.byKey(const ValueKey('ob-camera-card')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(pill(tester).opacity, 0);
      expect(meTop(tester), greaterThan(0));
    });

    testWidgets('Create my player advances with sign-up intent', (
      tester,
    ) async {
      final c = await onHowStep(tester);
      await tester.tap(cta());
      await _pumpFor(tester, 1);
      expect(_step(c), OnboardingStep.signIn);
      expect(c.read(authIntentProvider), AuthIntent.signUp);
    });

    testWidgets('I already have an account advances with sign-in intent', (
      tester,
    ) async {
      final c = await onHowStep(tester);
      c.read(authIntentProvider.notifier).state = AuthIntent.signUp;
      await tester.tap(find.text(ObCopy.introBoardLogin));
      await _pumpFor(tester, 1);
      expect(_step(c), OnboardingStep.signIn);
      expect(c.read(authIntentProvider), AuthIntent.signIn);
    });

    testWidgets('Skip lands on the sheet', (tester) async {
      final c = await onHowStep(tester);
      await tester.tap(find.text(ObCopy.skip));
      await _pumpFor(tester, 1);
      expect(_step(c), OnboardingStep.signIn);
    });
  });
}

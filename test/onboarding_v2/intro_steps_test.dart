// Part A intro steps — S0 splash handoff, S1 tap duel, S2 skeleton loop,
// S3 board climb. Widget tests drive the real flow provider against an
// in-memory store so advancement is asserted on OnboardingFlowState.step.
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
import 'package:nuvo/features/onboarding/flow/onboarding_flow_controller.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_step.dart';
import 'package:nuvo/features/onboarding/intro/splash_step.dart';
import 'package:nuvo/features/onboarding/shell/onboarding_shell_controller.dart';

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

/// The scaffolding the flow host provides around every step: ProviderScope
/// (flow + auth + analytics) and OnboardingShellScope. Returns the container
/// so tests can read [onboardingFlowProvider] directly.
ProviderContainer _harnessContainer({AuthRepository? authRepo}) =>
    ProviderContainer(
      overrides: [
        onboardingV2StoreProvider.overrideWithValue(
          OnboardingV2Store.memory(),
        ),
        analyticsProvider.overrideWithValue(FakeAnalyticsService()),
        authControllerProvider.overrideWith(
          (ref) => AuthController(authRepo ?? _NoSessionRepo()),
        ),
      ],
    );

Widget _harness({
  required ProviderContainer container,
  required OnboardingShellController shell,
  required Widget child,
}) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    home: OnboardingShellScope(controller: shell, child: child),
  ),
);

OnboardingStep _step(ProviderContainer c) =>
    c.read(onboardingFlowProvider).step;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('S0 ObSplashStep', () {
    testWidgets('auto-advances to introRace after the hold', (tester) async {
      final container = _harnessContainer();
      addTearDown(container.dispose);
      final shell = OnboardingShellController();
      await tester.pumpWidget(
        _harness(
          container: container,
          shell: shell,
          child: const ObSplashStep(),
        ),
      );

      // The scripted repo resolves auth on a microtask (pump flushes it);
      // the 1.2s logo hold runs on the animation clock — pump past it.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(_step(container), OnboardingStep.introRace);
      shell.dispose();
    });

    testWidgets('tap skips once auth resolved', (tester) async {
      final container = _harnessContainer();
      addTearDown(container.dispose);
      final shell = OnboardingShellController();
      await tester.pumpWidget(
        _harness(
          container: container,
          shell: shell,
          child: const ObSplashStep(),
        ),
      );
      // Auth resolves on the first pump's microtask flush.
      await tester.pump();

      await tester.tap(find.byType(ObSplashStep));
      await tester.pump();

      expect(_step(container), OnboardingStep.introRace);
      shell.dispose();
    });

    testWidgets('tap before auth resolves does not skip', (tester) async {
      final container = _harnessContainer(authRepo: _PendingRepo());
      addTearDown(container.dispose);
      final shell = OnboardingShellController();
      await tester.pumpWidget(
        _harness(
          container: container,
          shell: shell,
          child: const ObSplashStep(),
        ),
      );
      await tester.pump();
      await tester.tap(find.byType(ObSplashStep));
      await tester.pump();

      expect(_step(container), OnboardingStep.splash);
      shell.dispose();
    });
  });
}

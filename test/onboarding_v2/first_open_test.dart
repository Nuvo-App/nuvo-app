// The intro opens on the very first open of the app only. Afterwards a
// signed-out user lands on the login sheet. R1 keeps testing@getnuvo.net
// cold opens clean (the first-run flag is part of what it wipes).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/analytics/analytics_service.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/demo_account_marker.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/onboarding/data/first_run_flag.dart';
import 'package:nuvo/features/onboarding/data/onboarding_v2_store.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_flow_controller.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_step.dart';
import 'package:nuvo/features/onboarding/onboarding_v2_screen.dart';

class _NoSession extends AuthRepository {
  _NoSession() : super(AuthApi(), SecureTokenStore());
  @override
  Future<RestoreResult> restoreSession() async => const RestoreNoSession();
}

Future<(OnboardingStep, MemoryFirstRunFlag)> _coldOpen(
  WidgetTester t,
  MemoryFirstRunFlag flag,
) async {
  final c = ProviderContainer(
    overrides: [
      firstRunFlagProvider.overrideWithValue(flag),
      // A fresh process: nothing in memory, the store is empty.
      onboardingV2StoreProvider.overrideWithValue(OnboardingV2Store.memory()),
      analyticsProvider.overrideWithValue(FakeAnalyticsService()),
      authControllerProvider.overrideWith(
        (ref) => AuthController(_NoSession()),
      ),
    ],
  );
  addTearDown(c.dispose);
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: OnboardingV2Screen()),
    ),
  );
  for (var i = 0; i < 25; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  return (c.read(onboardingFlowProvider).step, flag);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('very first open shows the intro, and records it', (t) async {
    final (step, flag) = await _coldOpen(t, MemoryFirstRunFlag());
    expect(step, OnboardingStep.introRace);
    expect(flag.done, isTrue);
  });

  testWidgets('second cold open goes straight to the login, not the intro', (
    t,
  ) async {
    final flag = MemoryFirstRunFlag();
    await _coldOpen(t, flag); // first open
    await t.pumpWidget(const SizedBox());
    final (step, _) = await _coldOpen(t, flag); // second open
    expect(step, OnboardingStep.signIn);
  });

  testWidgets('R1: after testing@ the first-run flag is wiped -> clean intro', (
    t,
  ) async {
    // What the R1 cold start deletes includes the first-run flag file...
    expect(
      FileDemoAccountMarker.wipedFileNames,
      contains(FirstRunFlag.fileName),
    );
    // ...so the next open behaves like a first install: the intro shows.
    final flag = MemoryFirstRunFlag(done: true)..done = false; // wiped
    final (step, _) = await _coldOpen(t, flag);
    expect(step, OnboardingStep.introRace);
  });
}

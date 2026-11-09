import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/onboarding/data/onboarding_v2_store.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_copy.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_flow_controller.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_step.dart';
import 'package:nuvo/features/onboarding/player/first_race_ready_step.dart';
import 'package:nuvo/features/onboarding/shell/onboarding_shell_controller.dart';

import 'helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(ProviderContainer, OnboardingShellController)> pump(
    WidgetTester tester, {
    String? q1,
  }) async {
    final shell = OnboardingShellController();
    await tester.pumpWidget(
      playerHarness(
        shell: shell,
        store: OnboardingV2Store.memory(),
        child: const ObFirstRaceReadyStep(),
      ),
    );
    final c = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    final flow = c.read(onboardingFlowProvider.notifier);
    await flow.restore();
    for (final st in OnboardingStep.values) {
      if (st == OnboardingStep.firstRaceReady) break;
      await flow.completeStep(st);
    }
    if (q1 != null) await flow.setAnswer(1, q1);
    return (c, shell);
  }

  testWidgets(
    'seeds the race name from Q1, building then live, auto-advances',
    (tester) async {
      final (c, shell) = await pump(tester, q1: ObCopy.q1Fitness);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(ObCopy.firstRaceBuilding), findsOneWidget);
      expect(find.text('First to 10'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1200));
      expect(find.text(ObCopy.firstRaceLive), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 100));
      final s = c.read(onboardingFlowProvider);
      expect(s.step, OnboardingStep.levelUp);
      expect(s.xpAwarded[OnboardingStep.firstRaceReady], 5);
      shell.dispose();
    },
  );

  testWidgets(
    'skipped answers fall back to the default race; CTA skips ahead',
    (tester) async {
      final (c, shell) = await pump(tester);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('First to 10'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('onboarding-cta')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(c.read(onboardingFlowProvider).step, OnboardingStep.levelUp);
      // The timer must not double-award.
      await tester.pump(const Duration(seconds: 3));
      expect(
        c.read(onboardingFlowProvider).xpAwarded[OnboardingStep.firstRaceReady],
        5,
      );
      shell.dispose();
    },
  );
}

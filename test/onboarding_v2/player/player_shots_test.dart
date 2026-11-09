import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/onboarding/data/onboarding_v2_store.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_copy.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_flow_controller.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_step.dart';
import 'package:nuvo/features/onboarding/player/first_race_ready_step.dart';
import 'package:nuvo/features/onboarding/player/player_card_step.dart';
import 'package:nuvo/features/onboarding/player/questions_one_step.dart';
import 'package:nuvo/features/onboarding/player/questions_two_step.dart';
import 'package:nuvo/features/onboarding/shell/onboarding_shell_controller.dart';

import '../../helpers/screenshot.dart';
import 'helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadShotFonts);

  const sizes = {'390': Size(390, 844), '320': Size(320, 568)};

  Future<ProviderContainer> pump(
    WidgetTester tester,
    Size size,
    Widget child, {
    double keyboard = 0,
    OnboardingStep? upTo,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.reset);
    final shell = OnboardingShellController();
    addTearDown(shell.dispose);
    await tester.pumpWidget(
      playerHarness(
        shell: shell,
        store: OnboardingV2Store.memory(),
        child: child,
        overrides: [
          obUsernameCheckerProvider.overrideWithValue((u) async => true),
          obPlayerSaveProvider.overrideWithValue((s) async {}),
        ],
      ),
    );
    final c = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    final flow = c.read(onboardingFlowProvider.notifier);
    await flow.restore();
    for (final st in OnboardingStep.values) {
      if (st == upTo) break;
      await flow.completeStep(st);
    }
    return c;
  }

  for (final e in sizes.entries) {
    testWidgets('S7 ${e.key}', (tester) async {
      await pump(
        tester,
        e.value,
        const ObPlayerCardStep(),
        upTo: OnboardingStep.playerCard,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await shot(tester, 's7_empty_${e.key}');
      await tester.enterText(
        find.byType(EditableText).at(0),
        'Akshay Kumar Venkataraman',
      );
      await tester.enterText(find.byType(EditableText).at(1), 'akshay');
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.ensureVisible(
        find.byKey(const ValueKey('player-card-terms')),
      );
      await tester.tap(find.byKey(const ValueKey('player-card-terms')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await shot(tester, 's7_filled_${e.key}');
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -600),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await shot(tester, 's7_bottom_${e.key}');
      await tester.pump(const Duration(seconds: 4));
    });
    testWidgets('S7 keyboard ${e.key}', (tester) async {
      await pump(
        tester,
        e.value,
        const ObPlayerCardStep(),
        keyboard: e.key == '390' ? 336 : 260,
        upTo: OnboardingStep.playerCard,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.ensureVisible(find.byType(EditableText).at(0));
      await tester.showKeyboard(find.byType(EditableText).at(0));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await shot(tester, 's7_kb_${e.key}');
      await tester.pump(const Duration(seconds: 4));
    });
    testWidgets('S8 Q1 ${e.key}', (tester) async {
      await pump(
        tester,
        e.value,
        const ObQuestionsOneStep(),
        upTo: OnboardingStep.questions1,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await shot(tester, 's8q1_empty_${e.key}');
      await tester.ensureVisible(find.text(ObCopy.q1Running));
      await tester.tap(find.text(ObCopy.q1Running));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await shot(tester, 's8q1_pick_${e.key}');
    });
    testWidgets('S8 Q2 ${e.key}', (tester) async {
      await pump(
        tester,
        e.value,
        const ObQuestionsTwoStep(),
        upTo: OnboardingStep.questions2,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await shot(tester, 's8q2_empty_${e.key}');
      await tester.ensureVisible(find.text(ObCopy.q2Solo));
      await tester.tap(find.text(ObCopy.q2Solo));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await shot(tester, 's8q2_pick_${e.key}');
    });
    testWidgets('S9 ${e.key}', (tester) async {
      final c = await pump(
        tester,
        e.value,
        const ObFirstRaceReadyStep(),
        upTo: OnboardingStep.firstRaceReady,
      );
      await c
          .read(onboardingFlowProvider.notifier)
          .setAnswer(1, ObCopy.q1Fitness);
      await tester.pump(const Duration(milliseconds: 300));
      await shot(tester, 's9_a_${e.key}');
      await tester.pump(const Duration(milliseconds: 900));
      await shot(tester, 's9_b_${e.key}');
      await tester.pump(const Duration(milliseconds: 600));
      await shot(tester, 's9_c_${e.key}');
      await tester.pump(const Duration(seconds: 2));
    });
  }
}

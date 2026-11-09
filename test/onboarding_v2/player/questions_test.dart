import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/onboarding/data/onboarding_v2_store.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_copy.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_flow_controller.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_step.dart';
import 'package:nuvo/features/onboarding/player/questions_one_step.dart';
import 'package:nuvo/features/onboarding/player/questions_two_step.dart';
import 'package:nuvo/features/onboarding/player/race_preview.dart';
import 'package:nuvo/features/onboarding/shell/onboarding_shell_controller.dart';

import 'helpers.dart';

Finder _cta() => find.byKey(const ValueKey('onboarding-cta'));
bool _enabled(WidgetTester t) =>
    ((t.widget<Container>(_cta()).decoration!) as BoxDecoration).color ==
    const Color(0xFF1264FF);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  OnboardingShellController? shellOrNull;
  late ProviderContainer c;

  Future<void> pump(WidgetTester tester, Widget child, OnboardingStep at) async {
    shellOrNull = OnboardingShellController();
    await tester.pumpWidget(
      playerHarness(
        shell: shellOrNull!,
        store: OnboardingV2Store.memory(),
        child: child,
      ),
    );
    c = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    final flow = c.read(onboardingFlowProvider.notifier);
    await flow.restore();
    for (final st in OnboardingStep.values) {
      if (st == at) break;
      await flow.completeStep(st);
    }
    await tester.pump(const Duration(seconds: 1));
  }

  tearDown(() => shellOrNull?.dispose());

  test('race activity names', () {
    expect(obRacePreviewTitle(ObCopy.q1Reading), 'Reading Race');
    expect(obPracticeRaceName(ObCopy.q1Fitness), 'Squat Race · First to 10');
    expect(obPracticeRaceName(null), 'Squat Race · First to 10');
  });

  testWidgets('Q1: CTA gated, pick persists and rewrites preview', (
    tester,
  ) async {
    await pump(tester, const ObQuestionsOneStep(), OnboardingStep.questions1);
    expect(_enabled(tester), isFalse);
    expect(find.text('Squat Race'), findsOneWidget);
    await tester.ensureVisible(find.text(ObCopy.q1Reading));
    await tester.tap(find.text(ObCopy.q1Reading));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Reading Race'), findsOneWidget);
    expect(c.read(onboardingFlowProvider).answerQ1, ObCopy.q1Reading);
    expect(_enabled(tester), isTrue);
    await tester.tap(_cta());
    await tester.pump(const Duration(milliseconds: 100));
    final s = c.read(onboardingFlowProvider);
    expect(s.step, OnboardingStep.questions2);
    expect(s.xpAwarded[OnboardingStep.questions1] ?? 0, 0);
  });

  testWidgets('Q1 skip pays +10 and lands on first race ready', (tester) async {
    await pump(tester, const ObQuestionsOneStep(), OnboardingStep.questions1);
    await tester.tap(find.text(ObCopy.skip));
    await tester.pump(const Duration(milliseconds: 100));
    final s = c.read(onboardingFlowProvider);
    expect(s.step, OnboardingStep.firstRaceReady);
    expect(s.answerQ1, isNull);
    expect(s.xpAwarded[OnboardingStep.questions2], 10);
  });

  testWidgets('Q2: pick persists, Next pays +10', (tester) async {
    await pump(tester, const ObQuestionsTwoStep(), OnboardingStep.questions2);
    expect(_enabled(tester), isFalse);
    await tester.ensureVisible(find.text(ObCopy.q2Solo));
    await tester.tap(find.text(ObCopy.q2Solo));
    await tester.pump(const Duration(seconds: 1));
    expect(c.read(onboardingFlowProvider).answerQ2, ObCopy.q2Solo);
    await tester.tap(_cta());
    await tester.pump(const Duration(milliseconds: 100));
    final s = c.read(onboardingFlowProvider);
    expect(s.step, OnboardingStep.firstRaceReady);
    expect(s.xpAwarded[OnboardingStep.questions2], 10);
  });

  testWidgets('Q2 skip pays +10 once', (tester) async {
    await pump(tester, const ObQuestionsTwoStep(), OnboardingStep.questions2);
    await tester.tap(find.text(ObCopy.skip));
    await tester.pump(const Duration(milliseconds: 100));
    final s = c.read(onboardingFlowProvider);
    expect(s.step, OnboardingStep.firstRaceReady);
    expect(s.answerQ2, isNull);
    expect(s.xpAwarded[OnboardingStep.questions2], 10);
  });
}

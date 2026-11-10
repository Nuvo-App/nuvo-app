import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/motion/motion.dart';
import 'package:nuvo/features/onboarding/data/onboarding_v2_store.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_copy.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_flow_controller.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_step.dart';
import 'package:nuvo/features/onboarding/player/player_card_step.dart';
import 'package:nuvo/features/onboarding/shell/onboarding_shell_controller.dart';

import 'helpers.dart';

Finder _cta() => find.byKey(const ValueKey('onboarding-cta'));

bool _ctaEnabled(WidgetTester t) {
  final box = t.widget<Container>(_cta());
  final deco = box.decoration! as BoxDecoration;
  return deco.color == const Color(0xFF1264FF);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late OnboardingShellController shell;
  late OnboardingV2Store store;
  late List<ObPlayerProfileSave> saved;
  late Set<String> taken;

  Future<void> pump(WidgetTester tester) async {
    saved = [];
    taken = {'taken1'};
    shell = OnboardingShellController();
    store = OnboardingV2Store.memory();
    await tester.pumpWidget(
      playerHarness(
        shell: shell,
        store: store,
        child: const ObPlayerCardStep(),
        overrides: [
          obUsernameCheckerProvider.overrideWithValue(
            (u) async => !taken.contains(u),
          ),
          obPlayerSaveProvider.overrideWithValue((s) async => saved.add(s)),
        ],
      ),
    );
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> fill(WidgetTester tester, String name, String user) async {
    await tester.enterText(find.byType(TextField).at(0), name);
    await tester.enterText(find.byType(TextField).at(1), user);
    // Debounce + async check.
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
  }

  Future<void> tickTerms(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const ValueKey('player-card-terms')));
    await tester.tap(find.byKey(const ValueKey('player-card-terms')));
    await tester.pump();
  }

  tearDown(() => shell.dispose());

  testWidgets('card shows live name and @username', (tester) async {
    await pump(tester);
    await fill(tester, 'Akshay P', 'AkshayP');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('player-card-name')),
        matching: find.text('Akshay P'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('player-card-username')),
        matching: find.text('@akshayp'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a typed character scales in on the card', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField).at(0), 'A');
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(0), 'Ak');
    await tester.pump();
    final pop = find.descendant(
      of: find.byKey(const ValueKey('player-card-name')),
      matching: find.byType(TweenAnimationBuilder<double>),
    );
    expect(pop, findsOneWidget);
    // Settles back to plain text once the next rebuild lands.
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('CTA gated on name + available username + terms', (tester) async {
    await pump(tester);
    expect(_ctaEnabled(tester), isFalse);
    await fill(tester, 'Akshay', 'akshayp');
    expect(_ctaEnabled(tester), isFalse, reason: 'terms not ticked');
    await tickTerms(tester);
    expect(_ctaEnabled(tester), isTrue);
    await tester.enterText(find.byType(TextField).at(0), '  ');
    await tester.pump();
    expect(_ctaEnabled(tester), isFalse, reason: 'blank name');
  });

  testWidgets('taken username shows coral error + one-tap alternatives', (
    tester,
  ) async {
    await pump(tester);
    await fill(tester, 'Akshay', 'taken1');
    await tickTerms(tester);
    expect(find.text('@taken1 is taken'), findsOneWidget);
    expect(_ctaEnabled(tester), isFalse);
    expect(find.text('try @taken112'), findsOneWidget);
    await tester.ensureVisible(find.text('try @taken112'));
    await tester.tap(find.text('try @taken112'));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    expect(_ctaEnabled(tester), isTrue);
    expect(find.text('@taken1 is taken'), findsNothing);
  });

  testWidgets('invalid format never reaches the server check', (tester) async {
    await pump(tester);
    await fill(tester, 'Akshay', 'no spaces ok');
    // Spaces are filtered by the formatter; symbols are reported.
    await tester.enterText(find.byType(TextField).at(1), 'bad-name');
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('Use only letters, numbers, or underscore.'), findsOne);
    await tickTerms(tester);
    expect(_ctaEnabled(tester), isFalse);
  });

  testWidgets('That\'s me saves, awards +15 and advances', (tester) async {
    await pump(tester);
    final c = ProviderScope.containerOf(
      tester.element(find.byType(ObPlayerCardStep)),
    );
    await c.read(onboardingFlowProvider.notifier).restore();
    final flow = c.read(onboardingFlowProvider.notifier);
    for (final st in OnboardingStep.values) {
      if (st == OnboardingStep.playerCard) break;
      await flow.completeStep(st);
    }
    expect(c.read(onboardingFlowProvider).step, OnboardingStep.playerCard);
    await fill(tester, 'Akshay', 'akshayp');
    await tickTerms(tester);
    await tester.tap(_cta());
    await tester.pump();
    expect(saved, hasLength(1));
    // The card stamps first, then the flow moves on.
    expect(c.read(onboardingFlowProvider).step, OnboardingStep.playerCard);
    await tester.pump(
      NuvoMotion.springDuration + const Duration(milliseconds: 100),
    );
    expect(saved.single.fullName, 'Akshay');
    expect(saved.single.username, 'akshayp');
    final s = c.read(onboardingFlowProvider);
    expect(s.xpAwarded[OnboardingStep.playerCard], 15);
    expect(s.step, OnboardingStep.questions1);
  });

  testWidgets('save failure shows an inline error and stays', (tester) async {
    await pump(tester);
    await tester.pumpWidget(
      playerHarness(
        shell: shell,
        store: store,
        child: const ObPlayerCardStep(),
        overrides: [
          obUsernameCheckerProvider.overrideWithValue((_) async => true),
          obPlayerSaveProvider.overrideWithValue((_) async => throw 'x'),
        ],
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await fill(tester, 'Akshay', 'akshayp');
    await tickTerms(tester);
    await tester.tap(_cta());
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('player-card-error')), findsOneWidget);
    expect(_ctaEnabled(tester), isTrue);
  });

  testWidgets('copy: one title and only the username why-line', (tester) async {
    await pump(tester);
    expect(find.text(ObCopy.playerCardTitle), findsOneWidget);
    expect(find.text(ObCopy.playerCardUsernameWhy), findsOneWidget);
  });
}

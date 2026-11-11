// The 5-page intro: swipeable AND one Continue button, one animation per
// page, progress bar hidden on page 1 and monotone + honest after that.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/analytics/analytics_service.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/onboarding/data/first_run_flag.dart';
import 'package:nuvo/features/onboarding/data/onboarding_v2_store.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_flow_controller.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_step.dart';
import 'package:nuvo/features/onboarding/onboarding_v2_screen.dart';
import 'package:nuvo/features/onboarding/shell/ob_progress.dart';

class _NoSession extends AuthRepository {
  _NoSession() : super(AuthApi(), SecureTokenStore());
  @override
  Future<RestoreResult> restoreSession() async => const RestoreNoSession();
}

Future<ProviderContainer> _boot(WidgetTester t, {bool reduce = false}) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = const Size(390, 844);
  addTearDown(t.view.reset);
  final c = ProviderContainer(
    overrides: [
      firstRunFlagProvider.overrideWithValue(MemoryFirstRunFlag()),
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
      child: MaterialApp(
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(disableAnimations: reduce),
          child: child!,
        ),
        home: const OnboardingV2Screen(),
      ),
    ),
  );
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  return c;
}

Future<void> _tapNext(WidgetTester t) async {
  await t.tap(find.byKey(const ValueKey('onboarding-cta')));
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

OnboardingStep _step(ProviderContainer c) =>
    c.read(onboardingFlowProvider).step;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'progress formula: monotone, 0 -> exactly 1, never ahead of the truth',
    () {
      ObProgress.reset();
      expect(ObProgress.total, 8);
      var prev = -1.0;
      for (var done = 0; done <= ObProgress.total; done++) {
        final f = ObProgress.fractionFor(done);
        expect(f, greaterThan(prev));
        prev = f;
      }
      expect(ObProgress.fractionFor(0), 0);
      expect(ObProgress.fractionFor(8), 1);
      // Encouraging but bounded: never more than the real ratio + 0.30.
      for (var done = 0; done <= 8; done++) {
        expect(
          ObProgress.fractionFor(done),
          lessThanOrEqualTo(done / 8 + 0.30),
        );
      }
      // The floor never goes backwards.
      ObProgress.reset();
      final high = ObProgress.shown(6);
      expect(ObProgress.shown(2), high);
    },
  );

  testWidgets('five pages; no progress bar on page 1, a bar from page 2', (
    t,
  ) async {
    final c = await _boot(t);
    expect(_step(c), OnboardingStep.introRace);
    expect(find.text('Race anything.'), findsOneWidget);
    expect(find.byKey(const ValueKey('ob-progress')), findsNothing);
    var last = -1.0;
    for (final title in [
      'Prove it on camera.',
      'Climb the board.',
      'Race with your crew.',
      'Level up.',
    ]) {
      await _tapNext(t);
      expect(find.text(title), findsOneWidget);
      expect(find.byKey(const ValueKey('ob-progress')), findsOneWidget);
      final bar = t.getSize(find.byKey(const ValueKey('ob-progress')));
      // fill = inner FractionallySizedBox width
      final fill = t
          .getSize(
            find.descendant(
              of: find.byKey(const ValueKey('ob-progress')),
              matching: find.byType(FractionallySizedBox),
            ),
          )
          .width;
      final f = fill / (bar.width - 5);
      expect(f, greaterThanOrEqualTo(last - 0.001)); // never backwards
      last = f;
    }
    expect(find.text('Get started'), findsOneWidget);
  });

  testWidgets('swipe works and the CTA is the only thing ever required', (
    t,
  ) async {
    final c = await _boot(t);
    await t.drag(
      find.byKey(const ValueKey('ob-intro-pages')),
      const Offset(-300, 0),
    );
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Prove it on camera.'), findsOneWidget);
    expect(_step(c), OnboardingStep.introRace);
  });

  testWidgets('Get started goes to the login exactly once (double tap)', (
    t,
  ) async {
    final c = await _boot(t);
    for (var i = 0; i < 4; i++) {
      await _tapNext(t);
    }
    final cta = find.byKey(const ValueKey('onboarding-cta'));
    await t.tap(cta);
    await t.tap(cta, warnIfMissed: false);
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(_step(c), OnboardingStep.signIn);
  });

  testWidgets('Skip leaves from any page', (t) async {
    final c = await _boot(t);
    await _tapNext(t);
    await t.tap(find.byKey(const ValueKey('ob-intro-skip')));
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(_step(c), OnboardingStep.signIn);
  });

  testWidgets('reduce motion: pages show their finished frame, no loops', (
    t,
  ) async {
    await _boot(t, reduce: true);
    await t.pump(const Duration(seconds: 6));
    expect(find.text('Race anything.'), findsOneWidget);
  });
}

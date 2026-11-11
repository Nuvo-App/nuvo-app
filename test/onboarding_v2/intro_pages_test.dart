// The 5-page intro: swipeable AND one Continue button, one animation per
// page, progress bar hidden on page 1 and monotone + honest after that.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/analytics/analytics_service.dart';
import 'package:nuvo/core/motion/motion.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/onboarding/data/first_run_flag.dart';
import 'package:nuvo/features/onboarding/data/onboarding_v2_store.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_flow_controller.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_step.dart';
import 'package:nuvo/features/onboarding/intro/intro_demos.dart';
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

/// Real frames, like a device (one big pump would collapse every mark into
/// a single frame).
Future<void> _run(WidgetTester t, int ms) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

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
    // Wait out the arrival dwell, then ONE deliberate tap.
    for (var i = 0; i < 15; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.tap(cta);
    await t.tap(cta, warnIfMissed: false);
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(_step(c), OnboardingStep.createAccount);
    expect(c.read(authIntentProvider), AuthIntent.signUp);
  });

  testWidgets('Skip leaves from any page', (t) async {
    final c = await _boot(t);
    await _tapNext(t);
    await t.tap(find.byKey(const ValueKey('ob-intro-skip')));
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(_step(c), OnboardingStep.createAccount);
  });

  testWidgets('reduce motion: pages show their finished frame, no loops', (
    t,
  ) async {
    await _boot(t, reduce: true);
    await t.pump(const Duration(seconds: 6));
    expect(find.text('Race anything.'), findsOneWidget);
  });

  testWidgets('landing on the last page never navigates by itself', (t) async {
    final c = await _boot(t);
    for (var i = 0; i < 4; i++) {
      await _tapNext(t);
    }
    expect(find.text('Level up.'), findsOneWidget);
    for (var i = 0; i < 60; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(_step(c), OnboardingStep.introRace); // waits for the tap
    expect(find.text('Get started'), findsOneWidget);
  });

  testWidgets('a double tap on Next from page 4 lands on 5 and stays', (
    t,
  ) async {
    final c = await _boot(t);
    for (var i = 0; i < 3; i++) {
      await _tapNext(t);
    }
    final cta = find.byKey(const ValueKey('onboarding-cta'));
    await t.tap(cta);
    await t.tap(cta, warnIfMissed: false); // the stray second tap
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Level up.'), findsOneWidget);
    expect(_step(c), OnboardingStep.introRace);
  });

  testWidgets('animations play once and hold (no loop, no replay)', (t) async {
    await _boot(t);
    double demoT() => t.widget<IntroDemo>(find.byType(IntroDemo).first).t;
    await t.pump(const Duration(seconds: 4));
    expect(demoT(), 1.0);
    await t.pump(const Duration(seconds: 3));
    expect(demoT(), 1.0); // still holding: it did not loop
    await _tapNext(t);
    await t.pump(const Duration(seconds: 4));
    await t.drag(
      find.byKey(const ValueKey('ob-intro-pages')),
      const Offset(300, 0),
    ); // back to page 1
    for (var i = 0; i < 15; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Race anything.'), findsOneWidget);
    // Revisiting shows the final frame immediately, not a replay.
    expect(demoT(), 1.0);
  });

  for (final size in [
    const Size(320, 568),
    const Size(360, 640),
    const Size(390, 844),
    const Size(430, 932),
  ]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('no overflow on any page at ${size.width}x${size.height} '
          'text x$scale', (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = size;
        addTearDown(t.view.reset);
        final c = ProviderContainer(
          overrides: [
            firstRunFlagProvider.overrideWithValue(MemoryFirstRunFlag()),
            onboardingV2StoreProvider.overrideWithValue(
              OnboardingV2Store.memory(),
            ),
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
                data: MediaQuery.of(
                  ctx,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: const OnboardingV2Screen(),
            ),
          ),
        );
        for (var i = 0; i < 20; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        for (var p = 0; p < 5; p++) {
          await t.pump(const Duration(seconds: 4));
          expect(t.takeException(), isNull, reason: 'page ${p + 1}');
          // The CTA and the title are fully on screen.
          final cta = t.getRect(find.byKey(const ValueKey('onboarding-cta')));
          expect(cta.bottom, lessThanOrEqualTo(size.height));
          if (p < 4) await _tapNext(t);
        }
      });
    }
  }

  testWidgets('no page is ever skipped: swipes and taps visit 1..5 in order', (
    t,
  ) async {
    final c = await _boot(t);
    const titles = [
      'Race anything.',
      'Prove it on camera.',
      'Climb the board.',
      'Race with your crew.',
      'Level up.',
    ];
    final visited = <int>[];
    int current() => [
      for (var i = 0; i < titles.length; i++)
        if (find.text(titles[i]).evaluate().isNotEmpty &&
            t.getRect(find.text(titles[i]).first).center.dx.abs() < 400 &&
            t.getRect(find.text(titles[i]).first).left >= 0)
          i,
    ].last;
    visited.add(current());
    Future<void> swipe() async {
      await t.drag(
        find.byKey(const ValueKey('ob-intro-pages')),
        const Offset(-380, 0),
      );
      for (var i = 0; i < 14; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    // Mix swipes and taps.
    await swipe();
    visited.add(current());
    await _tapNext(t);
    visited.add(current());
    await swipe();
    visited.add(current());
    await _tapNext(t);
    visited.add(current());
    expect(visited, [0, 1, 2, 3, 4]);
    expect(_step(c), OnboardingStep.introRace); // still inside the intro
    // Flinging past the last page does nothing: page 5 is the last.
    await t.fling(
      find.byKey(const ValueKey('ob-intro-pages')),
      const Offset(-500, 0),
      3000,
    );
    for (var i = 0; i < 14; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Level up.'), findsOneWidget);
    expect(_step(c), OnboardingStep.introRace);
  });

  testWidgets('Skip is the only way out before the last page', (t) async {
    final c = await _boot(t);
    for (var i = 0; i < 3; i++) {
      await _tapNext(t);
      expect(_step(c), OnboardingStep.introRace);
    }
    await t.tap(find.byKey(const ValueKey('ob-intro-skip')));
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(_step(c), OnboardingStep.createAccount);
  });

  testWidgets('each page fires its climax haptic once; level-up fires last', (
    t,
  ) async {
    final rec = <String>[];
    NuvoHaptics.recorder = rec;
    addTearDown(() => NuvoHaptics.recorder = null);
    await _boot(t);
    await _run(t, 6000);
    expect(rec.where((e) => e == 'burst').length, 1); // race climax
    expect(rec.where((e) => e == 'tick').length, greaterThanOrEqualTo(3));
    expect(rec, contains('thud')); // the held breath before it
    expect(rec.indexOf('thud'), lessThan(rec.indexOf('burst')));
    rec.clear();
    for (var i = 0; i < 4; i++) {
      await _tapNext(t);
      await _run(t, 6000);
    }
    // Page 5 played: ticks up the bar, the thud, then the strong burst.
    expect(rec.where((e) => e == 'burst').length, greaterThanOrEqualTo(1));
    expect(rec.last, 'burst'); // the level-up break is the last, biggest hit
    // Replaying (revisit) fires nothing again.
    final before = rec.length;
    await t.drag(
      find.byKey(const ValueKey('ob-intro-pages')),
      const Offset(380, 0),
    );
    await _run(t, 2000);
    expect(rec.length, before);
  });

  testWidgets('reduce motion: final frames, one light haptic, no ticks', (
    t,
  ) async {
    final rec = <String>[];
    NuvoHaptics.recorder = rec;
    addTearDown(() => NuvoHaptics.recorder = null);
    await _boot(t, reduce: true);
    await _run(t, 7000);
    expect(rec, ['light']);
    await _tapNext(t);
    expect(rec.where((e) => e != 'light'), isEmpty);
  });

  testWidgets('progress completes the intro only when level-up lands', (
    t,
  ) async {
    await _boot(t);
    for (var i = 0; i < 4; i++) {
      await _tapNext(t);
    }
    double frac() {
      final bar = t.getSize(find.byKey(const ValueKey('ob-progress')));
      final fill = t
          .getSize(
            find.descendant(
              of: find.byKey(const ValueKey('ob-progress')),
              matching: find.byType(FractionallySizedBox),
            ),
          )
          .width;
      return fill / (bar.width - 5);
    }

    await _run(t, 500); // page 5 just arrived
    final early = frac();
    await _run(t, 6000); // the level-up has landed
    final landed = frac();
    expect(landed, greaterThan(early));
    expect(landed, closeTo(ObProgress.fractionFor(5), 0.02));
  });

  test('soft spring (leaderboard climb) barely overshoots', () {
    var peak = 0.0;
    for (var i = 0; i <= 100; i++) {
      peak = peak > NuvoMotion.softSpring.transform(i / 100)
          ? peak
          : NuvoMotion.softSpring.transform(i / 100);
    }
    expect(peak, lessThan(1.03));
    expect(NuvoMotion.softSpring.transform(1), 1);
    // ...while the regular spring is livelier (kept for pops and slams).
    var loud = 0.0;
    for (var i = 0; i <= 100; i++) {
      loud = loud > NuvoMotion.spring.transform(i / 100)
          ? loud
          : NuvoMotion.spring.transform(i / 100);
    }
    expect(loud, greaterThan(peak));
  });
}

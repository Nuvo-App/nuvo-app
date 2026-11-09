// Screenshot pass for S4–S6 at 390x844 and 320x568 (SHOTS_DIR=... to save).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/onboarding/auth_visuals/code_step.dart';
import 'package:nuvo/features/onboarding/auth_visuals/email_step.dart';
import 'package:nuvo/features/onboarding/auth_visuals/sign_in_step.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_step.dart';

import '../helpers/screenshot.dart';
import 'auth_visuals_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Real Manrope is only loaded when SHOTS_DIR is set; with the test font the
  // text is wider than life and would report false overflows.
  final shotsOn = (Platform.environment['SHOTS_DIR'] ?? '').isNotEmpty;
  setUpAll(loadShotFonts);

  const sizes = {'l': Size(390, 844), 'xs': Size(320, 568)};

  // NuvoEnter staggers with a real-time Future.delayed; give it real time.
  Future<void> settle(WidgetTester t, [int ms = 1000]) async {
    await t.pump(const Duration(milliseconds: 300)); // fires the stagger timers
    await t.pump(const Duration(milliseconds: 50)); // starts the tickers
    await t.pump(Duration(milliseconds: ms));
  }

  Future<AuthHarness> boot(
    WidgetTester t,
    Size size,
    OnboardingStep at,
    Widget screen, {
    double keyboard = 0,
    String? email,
    String? clipboard,
  }) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData') {
            return clipboard == null
                ? null
                : <String, dynamic>{'text': clipboard};
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    final bottom = keyboard > 34 ? 0.0 : 34.0;
    t.view.padding = FakeViewPadding(top: 47, bottom: bottom);
    t.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
    t.view.viewInsets = FakeViewPadding(bottom: keyboard);
    addTearDown(t.view.reset);
    final h = AuthHarness();
    await t.runAsync(() async {
      await h.startAt(at);
      if (email != null) {
        await h.flow.setEmail(email);
      }
    });
    await t.pumpWidget(h.app(screen));
    await settle(t);
    addTearDown(() async => t.pumpWidget(const SizedBox()));
    return h;
  }

  for (final e in sizes.entries) {
    final tag = e.key;
    final size = e.value;
    final kb = size.height > 700 ? 336.0 : 260.0;

    testWidgets('S4 sheet $tag', skip: !shotsOn, (t) async {
      await boot(t, size, OnboardingStep.signIn, const ObSignInStep());
      await t.pump(const Duration(seconds: 1));
      await shot(t, 's4_$tag');
    });

    testWidgets('S5 empty $tag', skip: !shotsOn, (t) async {
      await boot(
        t,
        size,
        OnboardingStep.email,
        const ObEmailStep(),
        keyboard: kb,
      );
      await shot(t, 's5_empty_kb_$tag');
    });
    testWidgets('S5 empty nokb $tag', skip: !shotsOn, (t) async {
      await boot(t, size, OnboardingStep.email, const ObEmailStep());
      await shot(t, 's5_empty_$tag');
    });
    testWidgets('S5 typing $tag', skip: !shotsOn, (t) async {
      await boot(
        t,
        size,
        OnboardingStep.email,
        const ObEmailStep(),
        keyboard: kb,
      );
      await t.enterText(find.byKey(const ValueKey('ob-email-field')), 'ava');
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 900));
      await shot(t, 's5_typing_$tag');
    });
    testWidgets('S5 valid $tag', skip: !shotsOn, (t) async {
      await boot(
        t,
        size,
        OnboardingStep.email,
        const ObEmailStep(),
        keyboard: kb,
      );
      await t.enterText(
        find.byKey(const ValueKey('ob-email-field')),
        'ava.longname@gmail.com',
      );
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 1200));
      await shot(t, 's5_valid_$tag');
    });
    testWidgets('S5 valid nokb $tag', skip: !shotsOn, (t) async {
      await boot(t, size, OnboardingStep.email, const ObEmailStep());
      await t.enterText(
        find.byKey(const ValueKey('ob-email-field')),
        'ava@gmail.com',
      );
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 1200));
      await shot(t, 's5_valid_nokb_$tag');
    });
    testWidgets('S5 reviewer $tag', skip: !shotsOn, (t) async {
      await boot(
        t,
        size,
        OnboardingStep.email,
        const ObEmailStep(),
        keyboard: kb,
      );
      await t.enterText(
        find.byKey(const ValueKey('ob-email-field')),
        'testing@getnuvo.net',
      );
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 1200));
      await shot(t, 's5_reviewer_$tag');
    });
    testWidgets('S5 reviewer nokb $tag', skip: !shotsOn, (t) async {
      await boot(t, size, OnboardingStep.email, const ObEmailStep());
      await t.enterText(
        find.byKey(const ValueKey('ob-email-field')),
        'testing@getnuvo.net',
      );
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 1200));
      await shot(t, 's5_reviewer_nokb_$tag');
    });

    testWidgets('S6 empty kb $tag', skip: !shotsOn, (t) async {
      await boot(
        t,
        size,
        OnboardingStep.code,
        const ObCodeStep(),
        keyboard: kb,
        email: 'ava@gmail.com',
        clipboard: '482915',
      );
      await shot(t, 's6_empty_kb_$tag');
    });
    testWidgets('S6 empty nokb $tag', skip: !shotsOn, (t) async {
      await boot(
        t,
        size,
        OnboardingStep.code,
        const ObCodeStep(),
        email: 'ava@gmail.com',
        clipboard: '482915',
      );
      await shot(t, 's6_empty_$tag');
    });
    testWidgets('S6 partial $tag', skip: !shotsOn, (t) async {
      await boot(
        t,
        size,
        OnboardingStep.code,
        const ObCodeStep(),
        keyboard: kb,
        email: 'ava@gmail.com',
      );
      await t.enterText(find.byKey(const ValueKey('ob-code-field')), '4829');
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 900));
      await shot(t, 's6_partial_$tag');
    });
    testWidgets('S6 verified $tag', skip: !shotsOn, (t) async {
      await boot(
        t,
        size,
        OnboardingStep.code,
        const ObCodeStep(),
        email: 'ava@gmail.com',
      );
      await t.enterText(find.byKey(const ValueKey('ob-code-field')), '482915');
      await t.pump(const Duration(milliseconds: 40));
      await t.pump(const Duration(milliseconds: 600));
      await shot(t, 's6_verified_$tag');
      await t.pump(const Duration(seconds: 2));
    });
    testWidgets('S6 tips $tag', skip: !shotsOn, (t) async {
      await boot(
        t,
        size,
        OnboardingStep.code,
        const ObCodeStep(),
        email: 'ava@gmail.com',
      );
      await t.ensureVisible(find.byKey(const ValueKey('ob-code-tips')));
      await t.tap(find.byKey(const ValueKey('ob-code-tips')));
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 900));
      await shot(t, 's6_tips_$tag');
    });
  }
}

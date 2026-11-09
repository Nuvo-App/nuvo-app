// S6 — code boxes: type / paste / autofill / backspace, auto-submit,
// success stamp + XP, error + lockout, resend countdown, tips sheet.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/onboarding/auth_visuals/code_step.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_step.dart';

import 'auth_visuals_support.dart';

const _field = ValueKey('ob-code-field');

String _boxText(WidgetTester t, int i) {
  final box = find.byKey(ValueKey('ob-code-box-$i'));
  final texts = find.descendant(of: box, matching: find.byType(Text));
  if (texts.evaluate().isEmpty) return '';
  return t.widget<Text>(texts.first).data ?? '';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AuthHarness> pump(
    WidgetTester t, {
    String? clipboard,
  }) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData') {
            return clipboard == null ? null : <String, dynamic>{'text': clipboard};
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    t.view.physicalSize = const Size(800, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final h = AuthHarness();
    await t.runAsync(() async {
      await h.startAt(OnboardingStep.email);
      await h.flow.setEmail('ava@gmail.com');
      await h.flow.completeStep(OnboardingStep.email);
    });
    await t.pumpWidget(h.app(const ObCodeStep()));
    await t.pump(const Duration(milliseconds: 900));
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
    });
    return h;
  }

  Future<void> enter(WidgetTester t, String s) async {
    await t.enterText(find.byKey(_field), s);
    await t.pump(const Duration(milliseconds: 100));
  }

  Future<void> advance(WidgetTester t, int ms) async {
    await t.pump(Duration(milliseconds: ms));
    await t.pump(Duration(milliseconds: ms));
  }

  testWidgets('shows the spec copy and six empty boxes', (t) async {
    await pump(t);
    expect(find.text('Check your email.'), findsOneWidget);
    expect(find.text('Enter the 6 digit code.'), findsOneWidget);
    expect(find.text('Code sent to ava@gmail.com'), findsOneWidget);
    expect(find.text('Resend in 30s'), findsOneWidget);
    for (var i = 0; i < 6; i++) {
      expect(_boxText(t, i), '');
    }
    final field = t.widget<TextField>(find.byKey(_field));
    expect(field.autofillHints, contains(AutofillHints.oneTimeCode));
  });

  testWidgets('typing fills boxes in order; backspace empties the last', (
    t,
  ) async {
    final h = await pump(t);
    await enter(t, '123');
    expect([for (var i = 0; i < 6; i++) _boxText(t, i)], [
      '1', '2', '3', '', '', '',
    ]);
    await enter(t, '12');
    expect([for (var i = 0; i < 6; i++) _boxText(t, i)], [
      '1', '2', '', '', '', '',
    ]);
    expect(h.auth.verified, isEmpty);
  });

  testWidgets('a pasted code fills every box and auto-submits', (t) async {
    final h = await pump(t);
    h.auth.verifyError = const ApiException(0, 'offline'); // keep the boxes
    await enter(t, '482 915');
    expect([for (var i = 0; i < 6; i++) _boxText(t, i)], [
      '4', '8', '2', '9', '1', '5',
    ]);
    expect(h.auth.verified, ['482915']);
    await advance(t, 300);
  });

  testWidgets('autofill with extra characters is cut to six digits', (t) async {
    final h = await pump(t);
    await enter(t, '123456789');
    await advance(t, 300);
    expect(h.auth.verified, ['123456']);
  });

  testWidgets('verified: stamp, then +10 XP and on to S7', (t) async {
    final h = await pump(t);
    await enter(t, '123456');
    await advance(t, 100);
    expect(find.text('VERIFIED'), findsOneWidget);
    expect(h.state.step, OnboardingStep.code); // still holding
    await advance(t, 500);
    await advance(t, 500);
    expect(h.state.step, OnboardingStep.playerCard);
    expect(h.state.totalXp, 10);
  });

  testWidgets('wrong code: error line, boxes clear, no XP', (t) async {
    final h = await pump(t);
    h.auth.verifyError = const ApiException(401, 'bad');
    await enter(t, '111111');
    await advance(t, 100);
    expect(find.text('That code did not match. Try again.'), findsOneWidget);
    await advance(t, 400);
    await advance(t, 400);
    expect(_boxText(t, 0), '');
    expect(h.state.step, OnboardingStep.code);
    expect(h.state.totalXp, 0);
    // The user can try again.
    h.auth.verifyError = null;
    await enter(t, '222222');
    await advance(t, 100);
    expect(h.auth.verified, ['111111', '222222']);
    await advance(t, 1000);
  });

  testWidgets('five wrong codes lock input for a minute', (t) async {
    final h = await pump(t);
    h.auth.verifyError = const ApiException(401, 'bad');
    for (var i = 0; i < 5; i++) {
      await enter(t, '11111$i');
      await advance(t, 400);
      await advance(t, 400);
    }
    expect(find.text('Too many tries. Wait 1 minute.'), findsOneWidget);
    expect(t.widget<TextField>(find.byKey(_field)).readOnly, isTrue);
    await t.tap(find.byKey(const ValueKey('onboarding-cta')));
    await t.pump();
    expect(h.auth.verified.length, 5);
    for (var i = 0; i < 61; i++) {
      await t.pump(const Duration(seconds: 1));
    }
    expect(find.text('Too many tries. Wait 1 minute.'), findsNothing);
    expect(t.widget<TextField>(find.byKey(_field)).readOnly, isFalse);
  });

  testWidgets('offline keeps the digits and shows the connection line', (
    t,
  ) async {
    final h = await pump(t);
    h.auth.verifyError = const ApiException(0, 'offline');
    await enter(t, '123456');
    await advance(t, 100);
    expect(
      find.text("Can't reach Nuvo. Check your connection and try again."),
      findsOneWidget,
    );
    expect(_boxText(t, 5), '6');
    // CTA retries once the network is back.
    h.auth.verifyError = null;
    await t.tap(find.byKey(const ValueKey('onboarding-cta')));
    await advance(t, 100);
    expect(h.auth.verified.length, 2);
    await advance(t, 1000);
  });

  testWidgets('resend counts down 30s then sends a new code', (t) async {
    final h = await pump(t);
    await t.pump(const Duration(seconds: 5));
    expect(find.text('Resend in 25s'), findsOneWidget);
    expect(find.byKey(const ValueKey('ob-code-resend')), findsNothing);
    for (var i = 0; i < 26; i++) {
      await t.pump(const Duration(seconds: 1));
    }
    expect(find.text('Send a new code'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('ob-code-resend')));
    await advance(t, 100);
    expect(h.auth.startedFor, ['ava@gmail.com']);
    expect(find.text('New code sent'), findsOneWidget);
    expect(find.text('Resend in 30s'), findsOneWidget);
  });

  testWidgets('"Didn\'t get it?" opens tips; Change email goes to S5', (
    t,
  ) async {
    final h = await pump(t);
    await t.drag(find.byType(SingleChildScrollView).first, const Offset(0, -400));
    await t.pump(const Duration(seconds: 1));
    await t.tap(find.byKey(const ValueKey('ob-code-tips')));
    await t.pump(const Duration(seconds: 1));
    expect(find.text("Didn't get the code?"), findsOneWidget);
    expect(find.text('Check your spam or promotions folder.'), findsOneWidget);
    await t.pump(const Duration(seconds: 1));
    await t.pump(const Duration(seconds: 1));
    await t.tap(find.text('Change email'));
    await t.pump(const Duration(seconds: 1));
    expect(h.state.step, OnboardingStep.email);
  });

  testWidgets('Change link goes back to the email step', (t) async {
    final h = await pump(t);
    await t.tap(find.byKey(const ValueKey('ob-code-change')));
    await t.pump();
    expect(h.state.step, OnboardingStep.email);
  });

  testWidgets('clipboard chip offers a copied code', (t) async {
    final h = await pump(t, clipboard: '482915');
    expect(find.text('Paste 482915?'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('ob-paste-chip')));
    await advance(t, 300);
    expect(h.auth.verified, ['482915']);
    await advance(t, 1000);
  });

  testWidgets('no chip for a non-code clipboard', (t) async {
    await pump(t, clipboard: 'hello there');
    expect(find.byKey(const ValueKey('ob-paste-chip')), findsNothing);
  });
}

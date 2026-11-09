// S4 — the "Save your spot" sheet: copy, Apple/Google wiring, error state,
// and the email hand-off.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/onboarding/auth_visuals/sign_in_step.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_step.dart';

import 'auth_visuals_support.dart';

/// The hero loops forever, so pumpAndSettle never returns: pump a fixed span.
Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 15; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AuthHarness> pump(WidgetTester t, {FakeSocial? social}) async {
    final h = AuthHarness(social: social);
    await t.runAsync(() => h.startAt(OnboardingStep.signIn));
    await t.pumpWidget(h.app(const ObSignInStep()));
    await _settle(t);
    return h;
  }

  testWidgets('shows the spec copy and both providers', (t) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await pump(t);
    expect(find.text('Save your spot'), findsOneWidget);
    expect(
      find.text('So your races, friends and level are yours.'),
      findsOneWidget,
    );
    expect(find.text('Continue with Apple'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Use email instead'), findsOneWidget);
    expect(find.textContaining('By continuing you agree'), findsOneWidget);
  });

  testWidgets('Apple signs in, settles email+code and lands +10 on S7', (
    t,
  ) async {
    final social = FakeSocial();
    final h = await pump(t, social: social);
    await t.tap(find.byKey(const ValueKey('ob-apple')));
    await t.pump(const Duration(milliseconds: 50));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await _settle(t);
    expect(social.appleCalls, 1);
    expect(h.state.step, OnboardingStep.playerCard);
    expect(h.state.totalXp, 10);
    expect(h.state.completed, contains(OnboardingStep.email));
    expect(h.state.completed, contains(OnboardingStep.code));
  });

  testWidgets('Google cancel returns quietly to the sheet', (t) async {
    final social = FakeSocial(cancelGoogle: true);
    final h = await pump(t, social: social);
    await t.tap(find.byKey(const ValueKey('ob-google')));
    await _settle(t);
    expect(social.googleCalls, 1);
    expect(h.state.step, OnboardingStep.signIn);
    expect(find.byKey(const ValueKey('ob-signin-error')), findsNothing);
  });

  testWidgets('a failure shows the coral line, not a dialog', (t) async {
    final h = await pump(t, social: FakeSocial(fail: true));
    await t.tap(find.byKey(const ValueKey('ob-apple')));
    await _settle(t);
    expect(find.text('Apple Sign In was cancelled or failed.'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(h.state.step, OnboardingStep.signIn);
  });

  testWidgets('Use email instead goes to S5', (t) async {
    final h = await pump(t);
    await t.tap(find.byKey(const ValueKey('ob-email-link')));
    await _settle(t);
    expect(h.state.step, OnboardingStep.email);
    expect(h.state.totalXp, 0);
  });
}

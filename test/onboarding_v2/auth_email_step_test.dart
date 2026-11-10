// S5 — player-pass email screen: domain chips, typo hint, valid stamp,
// send wiring, inline errors.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/onboarding/auth_visuals/email_step.dart';
import 'package:nuvo/features/onboarding/auth_visuals/email_utils.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_step.dart';

import 'auth_visuals_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ObEmail helpers', () {
    test('format validation', () {
      expect(ObEmail.isValid('ava@gmail.com'), isTrue);
      expect(ObEmail.isValid('  Ava@Gmail.com '), isTrue);
      expect(ObEmail.isValid('ava@gmail'), isFalse);
      expect(ObEmail.isValid('ava@'), isFalse);
      expect(ObEmail.isValid(''), isFalse);
    });

    test('chips need a local part and filter by the typed domain', () {
      expect(ObEmail.domainChips(''), isEmpty);
      expect(ObEmail.domainChips('ava'), ['gmail.com', 'icloud.com']);
      expect(ObEmail.domainChips('ava@g'), ['gmail.com']);
      expect(ObEmail.domainChips('ava@gmail.com'), isEmpty);
      expect(ObEmail.domainChips('ava@ucla'), ['ucla.edu']);
    });

    test('withDomain replaces the typed domain', () {
      expect(ObEmail.withDomain('ava', 'gmail.com'), 'ava@gmail.com');
      expect(ObEmail.withDomain('ava@gm', 'gmail.com'), 'ava@gmail.com');
    });

    test('typo suggestions', () {
      expect(ObEmail.typoSuggestion('ava@gmial.com'), 'gmail.com');
      expect(ObEmail.typoSuggestion('ava@gmail.cm'), 'gmail.com');
      expect(ObEmail.typoSuggestion('ava@hotmial.com'), 'hotmail.com');
      expect(ObEmail.typoSuggestion('ava@gmail.com'), isNull);
      expect(ObEmail.typoSuggestion('ava@mail.com'), isNull);
      expect(ObEmail.typoSuggestion('ava@ucla.edu'), isNull);
      expect(ObEmail.typoSuggestion('ava@gmail.c'), isNull);
      expect(ObEmail.typoSuggestion('ava'), isNull);
    });
  });

  Future<AuthHarness> pump(WidgetTester t) async {
    final h = AuthHarness();
    await t.runAsync(() => h.startAt(OnboardingStep.email));
    await t.pumpWidget(h.app(const ObEmailStep()));
    await t.pump(const Duration(seconds: 1));
    return h;
  }

  Future<void> type(WidgetTester t, String s) async {
    await t.enterText(find.byKey(const ValueKey('ob-email-field')), s);
    await t.pump(const Duration(milliseconds: 600));
  }

  testWidgets('empty: stamp not verified, hint shown, CTA inert', (t) async {
    final h = await pump(t);
    expect(find.byKey(const ValueKey('ob-brand-mark')), findsOneWidget);
    expect(find.text('Enter your email'), findsOneWidget);
    expect(find.text("What's your email?"), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('onboarding-cta')));
    await t.pump();
    expect(h.auth.startedFor, isEmpty);
    expect(h.state.step, OnboardingStep.email);
  });

  testWidgets('chip inserts the domain and the stamp reads Ready', (t) async {
    await pump(t);
    await type(t, 'ava');
    expect(find.byKey(const ValueKey('ob-chip-gmail.com')), findsOneWidget);
    await t.ensureVisible(find.byKey(const ValueKey('ob-chip-gmail.com')));
    await t.tap(find.byKey(const ValueKey('ob-chip-gmail.com')));
    await t.pump(const Duration(milliseconds: 600));
    final field = t.widget<TextField>(
      find.byKey(const ValueKey('ob-email-field')),
    );
    expect(field.controller!.text, 'ava@gmail.com');
    expect(find.text('Enter your email'), findsNothing);
  });

  testWidgets('typo hint corrects the domain on tap', (t) async {
    await pump(t);
    await type(t, 'ava@gmial.com');
    expect(find.text('Did you mean gmail.com?'), findsOneWidget);
    await t.ensureVisible(find.byKey(const ValueKey('ob-email-typo')));
    await t.tap(find.byKey(const ValueKey('ob-email-typo')));
    await t.pump(const Duration(milliseconds: 100));
    await t.pump(const Duration(milliseconds: 600));
    final field = t.widget<TextField>(
      find.byKey(const ValueKey('ob-email-field')),
    );
    expect(field.controller!.text, 'ava@gmail.com');
    expect(find.byKey(const ValueKey('ob-email-typo')), findsNothing);
  });

  testWidgets('Send code starts email auth and moves to S6', (t) async {
    final h = await pump(t);
    await type(t, 'Ava@Gmail.com');
    await t.tap(find.byKey(const ValueKey('onboarding-cta')));
    await t.pump();
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await t.pump(const Duration(seconds: 1));
    expect(h.auth.startedFor, ['ava@gmail.com']);
    expect(h.state.step, OnboardingStep.code);
    expect(h.state.email, 'ava@gmail.com');
    expect(h.state.totalXp, 0);
  });

  testWidgets('network and rate-limit errors stay inline', (t) async {
    final h = await pump(t);
    await type(t, 'ava@gmail.com');
    h.auth.startError = const ApiException(0, 'offline');
    await t.tap(find.byKey(const ValueKey('onboarding-cta')));
    await t.pump(const Duration(seconds: 1));
    expect(
      find.text("Can't reach Nuvo. Check your connection and try again."),
      findsOneWidget,
    );
    expect(h.state.step, OnboardingStep.email);

    h.auth.startError = const ApiException(429, 'slow down');
    await t.tap(find.byKey(const ValueKey('onboarding-cta')));
    await t.pump(const Duration(seconds: 1));
    expect(
      find.text('Too many codes. Wait a minute and try again.'),
      findsOneWidget,
    );
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('review account: password field, no OTP, signs in via reviewer', (
    t,
  ) async {
    final h = await pump(t);
    await type(t, 'ava@gmail.com');
    expect(find.byKey(const ValueKey('ob-email-password')), findsNothing);
    await type(t, 'testing@getnuvo.net');
    expect(find.byKey(const ValueKey('ob-email-password')), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    await t.enterText(
      find.byKey(const ValueKey('ob-email-password')),
      'testing123',
    );
    await t.pump();
    await t.tap(find.byKey(const ValueKey('onboarding-cta')));
    await t.pump(const Duration(seconds: 1));
    expect(h.auth.startedFor, isEmpty);
    expect(h.auth.reviewerSignIns, ['testing@getnuvo.net|testing123|signIn']);
    expect(h.state.step, isNot(OnboardingStep.email));
  });
}

// Keyboard-bug regression: opening the keyboard re-lays the screen out
// (viewInsets change). The text field must survive that with the SAME State
// (same IME connection), keep focus and its text, and keep reacting.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nuvo/core/analytics/analytics_service.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_flow_controller.dart';
import 'package:nuvo/features/onboarding/onboarding_v2_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/onboarding/auth_visuals/code_step.dart';
import 'package:nuvo/features/onboarding/auth_visuals/email_step.dart';
import 'package:nuvo/features/onboarding/data/onboarding_v2_store.dart';
import 'package:nuvo/features/onboarding/player/player_card_step.dart';
import 'package:nuvo/features/onboarding/shell/onboarding_shell_controller.dart';
import 'player/helpers.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_step.dart';

import 'auth_visuals_support.dart';

Future<void> _pumpFor(WidgetTester t, Duration d) async {
  for (var ms = 0; ms < d.inMilliseconds; ms += 100) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The default test font is far wider than Manrope: ignore its overflow
  // noise (this file is about focus, not glyph metrics).
  setUp(() {
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      if (d.exceptionAsString().contains('overflowed')) return;
      prev?.call(d);
    };
    addTearDown(() => FlutterError.onError = prev);
  });

  testWidgets('email: opening the keyboard keeps the same field, focus, text', (
    t,
  ) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(390, 844);
    addTearDown(t.view.reset);
    final h = AuthHarness();
    await t.runAsync(() => h.startAt(OnboardingStep.email));
    await t.pumpWidget(h.app(const ObEmailStep()));
    await _pumpFor(t, const Duration(seconds: 1));

    final fieldFinder = find.byKey(const ValueKey('ob-email-field'));
    final before = t.state<EditableTextState>(
      find.descendant(of: fieldFinder, matching: find.byType(EditableText)),
    );
    await t.tap(fieldFinder);
    await t.enterText(fieldFinder, 'ava@gmail');
    await _pumpFor(t, const Duration(milliseconds: 300));

    // The keyboard opens.
    t.view.viewInsets = const FakeViewPadding(bottom: 336);
    addTearDown(t.view.resetViewInsets);
    await _pumpFor(t, const Duration(seconds: 3));

    final after = t.state<EditableTextState>(
      find.descendant(of: fieldFinder, matching: find.byType(EditableText)),
    );
    expect(
      identical(before, after),
      isTrue,
      reason:
          'the field was re-created: the IME connection (keyboard) '
          'drops and the field stops working',
    );
    expect(after.widget.focusNode.hasFocus, isTrue);
    expect(after.widget.controller.text, 'ava@gmail');

    await t.enterText(fieldFinder, 'ava@gmail.com');
    await _pumpFor(t, const Duration(seconds: 2));
    expect(
      t
          .widget<TextField>(
            find.descendant(of: fieldFinder, matching: find.byType(TextField)),
          )
          .controller!
          .text,
      'ava@gmail.com',
    );
    expect(after.widget.focusNode.hasFocus, isTrue);
  });

  Future<void> keyboardOpens(WidgetTester t) async {
    t.view.viewInsets = const FakeViewPadding(bottom: 336);
    addTearDown(t.view.resetViewInsets);
    await _pumpFor(t, const Duration(seconds: 3));
  }

  EditableTextState editable(WidgetTester t, Key key) =>
      t.state<EditableTextState>(
        find.descendant(
          of: find.byKey(key),
          matching: find.byType(EditableText),
        ),
      );

  testWidgets('code: field survives the keyboard, keeps focus and text', (
    t,
  ) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(390, 844);
    addTearDown(t.view.reset);
    final h = AuthHarness();
    await t.runAsync(() => h.startAt(OnboardingStep.code));
    await t.pumpWidget(h.app(const ObCodeStep()));
    await _pumpFor(t, const Duration(seconds: 1));
    const key = ValueKey('ob-code-field');
    final before = editable(t, key);
    await t.enterText(find.byKey(key), '123');
    await keyboardOpens(t);
    final after = editable(t, key);
    expect(identical(before, after), isTrue);
    expect(after.widget.focusNode.hasFocus, isTrue);
    expect(after.widget.controller.text, '123');
  });

  testWidgets('player card: name and username survive the keyboard', (t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(390, 844);
    addTearDown(t.view.reset);
    final shell = OnboardingShellController();
    addTearDown(shell.dispose);
    await t.pumpWidget(
      playerHarness(
        shell: shell,
        store: OnboardingV2Store.memory(),
        child: const ObPlayerCardStep(),
      ),
    );
    await _pumpFor(t, const Duration(seconds: 1));
    final nameF = find.byType(TextField).first;
    final userF = find.byType(TextField).at(1);
    final nameBefore = t.state<EditableTextState>(
      find.descendant(of: nameF, matching: find.byType(EditableText)),
    );
    await t.enterText(nameF, 'Ava Lee');
    await keyboardOpens(t);
    final nameAfter = t.state<EditableTextState>(
      find.descendant(
        of: find.byType(TextField).first,
        matching: find.byType(EditableText),
      ),
    );
    expect(identical(nameBefore, nameAfter), isTrue);
    expect(nameAfter.widget.controller.text, 'Ava Lee');
    await t.enterText(userF, 'avalee');
    await _pumpFor(t, const Duration(seconds: 2));
    final userAfter = t.state<EditableTextState>(
      find.descendant(
        of: find.byType(TextField).at(1),
        matching: find.byType(EditableText),
      ),
    );
    expect(userAfter.widget.controller.text, 'avalee');
  });

  testWidgets(
    'real host: type a full email while the keyboard animates up, char by char',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(390, 844);
      addTearDown(t.view.reset);
      final store = OnboardingV2Store.memory();
      final c = ProviderContainer(
        overrides: [
          onboardingV2StoreProvider.overrideWithValue(store),
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
          child: const MaterialApp(home: OnboardingV2Screen()),
        ),
      );
      await _pumpFor(t, const Duration(milliseconds: 500));
      final flow = c.read(onboardingFlowProvider.notifier);
      await flow.skipIntros();
      await flow.completeStep(OnboardingStep.signIn); // -> email
      await _pumpFor(t, const Duration(seconds: 2));
      const key = ValueKey('ob-email-field');
      expect(find.byKey(key), findsOneWidget);
      final before = editable(t, key);

      await t.tap(find.byKey(key));
      const email = 'ava.lee@gmail.com';
      var typed = '';
      for (var i = 0; i < email.length; i++) {
        // The keyboard rises over the first ~10 characters (animated insets).
        final inset = (336.0 * ((i + 1) / 10)).clamp(0.0, 336.0);
        t.view.viewInsets = FakeViewPadding(bottom: inset);
        typed += email[i];
        await t.enterText(find.byKey(key), typed);
        await t.pump(const Duration(milliseconds: 40));
        final now = editable(t, key);
        expect(
          identical(before, now),
          isTrue,
          reason: 'field re-created at "$typed"',
        );
        expect(now.widget.controller.text, typed);
        expect(
          now.widget.focusNode.hasFocus,
          isTrue,
          reason: 'focus lost at "$typed"',
        );
      }
      addTearDown(t.view.resetViewInsets);
      await _pumpFor(t, const Duration(seconds: 2));
      final end = editable(t, key);
      expect(identical(before, end), isTrue);
      expect(end.widget.controller.text, email);
      expect(end.widget.focusNode.hasFocus, isTrue);
      // The CTA reacted (valid email) and the field is on screen above it.
      final cta = t.getRect(find.byKey(const ValueKey('onboarding-cta')));
      final field = t.getRect(find.byKey(key));
      expect(field.bottom, lessThanOrEqualTo(cta.top));
      expect(field.top, greaterThan(0));
    },
  );

  for (final size in [const Size(390, 844), const Size(320, 568)]) {
    testWidgets('CTA keeps a clear gap above the keyboard at ${size.width}', (
      t,
    ) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = size;
      addTearDown(t.view.reset);
      final h = AuthHarness();
      await t.runAsync(() => h.startAt(OnboardingStep.email));
      await t.pumpWidget(h.app(const ObEmailStep()));
      await _pumpFor(t, const Duration(seconds: 1));
      final kb = size.height > 700 ? 336.0 : 260.0;
      t.view.viewInsets = FakeViewPadding(bottom: kb);
      addTearDown(t.view.resetViewInsets);
      await _pumpFor(t, const Duration(seconds: 2));
      final cta = t.getRect(find.byKey(const ValueKey('onboarding-cta')));
      expect(size.height - kb - cta.bottom, greaterThanOrEqualTo(16));
    });
  }
}

class _NoSession extends AuthRepository {
  _NoSession() : super(AuthApi(), SecureTokenStore());
  @override
  Future<RestoreResult> restoreSession() async => const RestoreNoSession();
}

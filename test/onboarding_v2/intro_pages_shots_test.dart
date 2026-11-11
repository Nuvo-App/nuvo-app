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
import 'package:nuvo/features/onboarding/onboarding_v2_screen.dart';
import 'dart:io';
import '../helpers/screenshot.dart';

class _NoSession extends AuthRepository {
  _NoSession() : super(AuthApi(), SecureTokenStore());
  @override
  Future<RestoreResult> restoreSession() async => const RestoreNoSession();
}

Future<ProviderContainer> _boot(
  WidgetTester t,
  Size size, {
  bool reduce = false,
}) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = size;
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final on = (Platform.environment['SHOTS_DIR'] ?? '').isNotEmpty;
  setUpAll(loadShotFonts);
  for (final e in {
    'l': const Size(390, 844),
    'xs': const Size(320, 568),
  }.entries) {
    testWidgets('intro pages ${e.key}', skip: !on, (t) async {
      await _boot(t, e.value);
      for (var p = 0; p < 5; p++) {
        // let the page's single animation reach a telling frame
        await t.pump(const Duration(milliseconds: 2900));
        await shot(t, 'intro_${e.key}_$p');
        if (p < 4) await _tapNext(t);
      }
    });
  }
}

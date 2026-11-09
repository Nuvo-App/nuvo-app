// Visual proof of the intro screens at the two reference phone sizes.
// Run with SHOTS_DIR=/tmp/shots_r1 to write PNGs; without it the test only
// asserts that nothing overflows or throws.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/analytics/analytics_service.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/onboarding/data/onboarding_v2_store.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_flow_controller.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_step.dart';
import 'package:nuvo/features/onboarding/onboarding_v2_screen.dart';

import '../helpers/screenshot.dart';

class _NoSessionRepo extends AuthRepository {
  _NoSessionRepo() : super(AuthApi(), SecureTokenStore());

  @override
  Future<RestoreResult> restoreSession() async => const RestoreNoSession();
}

Future<void> _pumpFor(WidgetTester tester, double seconds) async {
  for (var i = 0; i < (seconds * 20).ceil(); i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadShotFonts);

  for (final size in [const Size(390, 844), const Size(320, 568)]) {
    final tag = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('intro screens at $tag', (tester) async {
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(
        overrides: [
          onboardingV2StoreProvider.overrideWithValue(
            OnboardingV2Store.memory(),
          ),
          analyticsProvider.overrideWithValue(FakeAnalyticsService()),
          authControllerProvider.overrideWith(
            (ref) => AuthController(_NoSessionRepo()),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: OnboardingV2Screen()),
        ),
      );
      await _pumpFor(tester, 0.6);
      await shot(tester, 'r1_${tag}_0_splash');

      await _pumpFor(tester, 2.4);
      expect(
        container.read(onboardingFlowProvider).step,
        OnboardingStep.introRace,
      );
      await shot(tester, 'r1_${tag}_1_duel_idle');

      // A brisk tapper: 9 taps.
      for (var i = 0; i < 9; i++) {
        await tester.tapAt(Offset(size.width / 2, size.height * 0.4));
        await tester.pump(const Duration(milliseconds: 120));
      }
      await shot(tester, 'r1_${tag}_2_duel_mid');
      for (var i = 0; i < 11; i++) {
        await tester.tapAt(Offset(size.width / 2, size.height * 0.4));
        await tester.pump(const Duration(milliseconds: 120));
      }
      await _pumpFor(tester, 0.7);
      await shot(tester, 'r1_${tag}_3_duel_won');

      await tester.tap(find.byKey(const ValueKey('onboarding-cta')));
      await _pumpFor(tester, 1.0);
      expect(
        container.read(onboardingFlowProvider).step,
        OnboardingStep.introHow,
      );
      await shot(tester, 'r1_${tag}_4_how_start');
      await _pumpFor(tester, 3.0);
      await shot(tester, 'r1_${tag}_5_how_rep2');
      await _pumpFor(tester, 1.9);
      await shot(tester, 'r1_${tag}_6_how_verified');
      await _pumpFor(tester, 2.6);
      await shot(tester, 'r1_${tag}_7_how_first');

      // The sheet the intro hands off to (its own 320 px layout belongs to
      // the auth screens pass, so it is only captured on the tall phone).
      if (size.width > 320) {
        await tester.tap(find.byKey(const ValueKey('onboarding-cta')));
        await _pumpFor(tester, 1.5);
        await shot(tester, 'r1_${tag}_8_sheet');
      }
    });
  }
}

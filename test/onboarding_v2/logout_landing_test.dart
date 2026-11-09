// An explicit sign-out lands on the login sheet (S4), never the intro. A cold
// open (flag unset) still starts at the intro (R1 stays clean).
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

class _Repo extends AuthRepository {
  _Repo() : super(AuthApi(), SecureTokenStore());
  @override
  Future<RestoreResult> restoreSession() async => const RestoreNoSession();
}

Future<OnboardingStep> _land(
  WidgetTester t, {
  required bool explicit,
  required String previousEmail,
}) async {
  final store = OnboardingV2Store.memory();
  await store.ensureLoaded();
  await store.attachAccount(previousEmail); // the account that just left
  final c = ProviderContainer(
    overrides: [
      onboardingV2StoreProvider.overrideWithValue(store),
      analyticsProvider.overrideWithValue(FakeAnalyticsService()),
      authControllerProvider.overrideWith((ref) => AuthController(_Repo())),
    ],
  );
  addTearDown(c.dispose);
  c.read(explicitSignOutProvider.notifier).state = explicit;
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: OnboardingV2Screen()),
    ),
  );
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  return c.read(onboardingFlowProvider).step;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final email in ['member@example.com', 'testing@getnuvo.net']) {
    testWidgets('logout of $email lands on the login sheet', (t) async {
      expect(
        await _land(t, explicit: true, previousEmail: email),
        OnboardingStep.signIn,
      );
    });
    testWidgets('cold open after $email starts at the intro', (t) async {
      expect(
        await _land(t, explicit: false, previousEmail: email),
        OnboardingStep.introRace,
      );
    });
  }
}

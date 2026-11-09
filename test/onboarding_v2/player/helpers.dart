import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nuvo/core/analytics/analytics_service.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/onboarding/data/onboarding_v2_store.dart';
import 'package:nuvo/features/onboarding/shell/onboarding_shell_controller.dart';

class FakeAuthRepo extends AuthRepository {
  FakeAuthRepo() : super(AuthApi(), SecureTokenStore());

  @override
  Future<RestoreResult> restoreSession() async => const RestoreNoSession();
}

/// Pumps [child] inside the shell scope with memory-backed providers.
Widget playerHarness({
  required Widget child,
  required OnboardingShellController shell,
  required OnboardingV2Store store,
  List<Override> overrides = const [],
}) => ProviderScope(
  overrides: [
    onboardingV2StoreProvider.overrideWithValue(store),
    analyticsProvider.overrideWithValue(FakeAnalyticsService()),
    authControllerProvider.overrideWith((ref) => AuthController(FakeAuthRepo())),
    ...overrides,
  ],
  child: MaterialApp(
    home: OnboardingShellScope(controller: shell, child: child),
  ),
);

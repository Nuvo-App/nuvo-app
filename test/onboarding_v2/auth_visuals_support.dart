// Shared harness for the Part B (S4–S6) widget tests.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nuvo/core/analytics/analytics_service.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/onboarding/auth_visuals/social_sign_in.dart';
import 'package:nuvo/features/onboarding/data/onboarding_v2_store.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_flow_controller.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_step.dart';
import 'package:nuvo/features/onboarding/shell/onboarding_shell_controller.dart';
import 'package:nuvo/features/onboarding/shell/xp_rail.dart';

const testUser = AuthUser(
  id: 'u1',
  email: 'ava@gmail.com',
  onboardingComplete: false,
  hasMemberPass: false,
  termsAccepted: false,
);

/// An AuthController stand-in: records calls, scripted outcomes.
class FakeAuth extends StateNotifier<AuthState> implements AuthController {
  FakeAuth() : super(const AuthState(status: AuthStatus.unauthenticated));

  final List<String> startedFor = [];
  final List<String> verified = [];
  Object? startError;
  Object? verifyError;

  @override
  Future<void> startEmailAuth(String email) async {
    startedFor.add(email);
    if (startError != null) throw startError!;
  }

  @override
  Future<void> verifyEmailCode(String email, String code) async {
    verified.add(code);
    if (verifyError != null) throw verifyError!;
    state = const AuthState(status: AuthStatus.authenticated, user: testUser);
  }

  @override
  Future<void> signInWithApple(
    String idToken, {
    String? fullName,
    String? authorizationCode,
  }) async {
    state = const AuthState(status: AuthStatus.authenticated, user: testUser);
  }

  @override
  Future<void> signInWithGoogle(String idToken) async {
    state = const AuthState(status: AuthStatus.authenticated, user: testUser);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSocial implements ObSocialSignIn {
  FakeSocial({this.fail = false, this.cancelGoogle = false});
  final bool fail;
  final bool cancelGoogle;
  int appleCalls = 0;
  int googleCalls = 0;

  @override
  Future<void> apple(AuthController auth) async {
    appleCalls++;
    if (fail) throw Exception('apple failed');
    await auth.signInWithApple('tok');
  }

  @override
  Future<bool> google(AuthController auth) async {
    googleCalls++;
    if (fail) throw Exception('google failed');
    if (cancelGoogle) return false;
    await auth.signInWithGoogle('tok');
    return true;
  }
}

class AuthHarness {
  AuthHarness({FakeSocial? social})
    : auth = FakeAuth(),
      social = social ?? FakeSocial(),
      store = OnboardingV2Store.memory(),
      analytics = FakeAnalyticsService();

  final FakeAuth auth;
  final FakeSocial social;
  final OnboardingV2Store store;
  final FakeAnalyticsService analytics;
  final shell = OnboardingShellController();
  late final ProviderContainer container = ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith((ref) => auth),
      obSocialSignInProvider.overrideWithValue(social),
      onboardingV2StoreProvider.overrideWithValue(store),
      analyticsProvider.overrideWithValue(analytics),
    ],
  );

  OnboardingFlowController get flow =>
      container.read(onboardingFlowProvider.notifier);
  OnboardingFlowState get state => container.read(onboardingFlowProvider);

  /// Restores the flow and walks it to [step] (completing everything before).
  Future<void> startAt(OnboardingStep step) async {
    await flow.restore();
    for (final s in OnboardingStep.values) {
      if (s == step) break;
      if (s.index < step.index) await flow.completeStep(s);
    }
  }

  /// Hosts [child] the way OnboardingV2Screen does (scope + XP overlay),
  /// swapping on the flow's current step is the test's job.
  Widget app(Widget child, {double textScale = 1}) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: OnboardingShellScope(
        controller: shell,
        child: Stack(children: [child, XpFlyOverlay(controller: shell)]),
      ),
    ),
  );
}

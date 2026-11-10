import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics_service.dart';
import '../../auth/presentation/auth_controller.dart';
import '../auth_visuals/social_sign_in.dart';
import '../data/onboarding_v2_store.dart';
import '../flow/onboarding_flow_controller.dart';
import '../flow/onboarding_step.dart';
import '../levelup/onboarding_reward.dart';
import '../onboarding_v2_screen.dart';
import '../player/player_card_step.dart';
import 'sandbox_auth.dart';

/// Practice mode: the full onboarding v2 flow running in its OWN isolated
/// provider container. Nothing in it can reach the real session: auth is a
/// local stand-in, the progress store is in memory, analytics are recorded
/// in a throwaway fake (never sent), the profile/username/photo writes and
/// the level-up grant are stubbed, and the real app's providers are never
/// read or written. Closing it just disposes the container.
class OnboardingSandbox extends StatefulWidget {
  const OnboardingSandbox({super.key, @visibleForTesting this.container});

  /// Tests inject their own container to inspect it.
  final ProviderContainer? container;

  @override
  State<OnboardingSandbox> createState() => _OnboardingSandboxState();
}

class _OnboardingSandboxState extends State<OnboardingSandbox> {
  late final ProviderContainer _container =
      widget.container ?? buildSandboxContainer();

  @override
  void dispose() {
    if (widget.container == null) _container.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UncontrolledProviderScope(
    container: _container,
    child: const OnboardingV2Screen(sandbox: true),
  );
}

/// The isolated container (a ROOT container: it has no parent, so nothing
/// from the real app leaks in).
ProviderContainer buildSandboxContainer({AnalyticsService? analytics}) {
  final fake = analytics ?? FakeAnalyticsService();
  return ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith((ref) => SandboxAuth()),
      authIntentProvider.overrideWith((ref) => AuthIntent.signIn),
      analyticsProvider.overrideWithValue(fake),
      onboardingV2StoreProvider.overrideWithValue(OnboardingV2Store.memory()),
      obSocialSignInProvider.overrideWithValue(const SandboxSocialSignIn()),
      obPlayerSaveProvider.overrideWithValue((save) async {}),
      onboardingRewardFetcherProvider.overrideWithValue(
        () async => OnboardingReward.fallback,
      ),
      onboardingFlowProvider.overrideWith(
        (ref) => OnboardingFlowController(
          store: ref.watch(onboardingV2StoreProvider),
          analytics: fake,
          onGraduate: () async {},
          cutSteps: kCutSteps,
          inputLock: OnboardingFlowController.appInputLock,
        ),
      ),
    ],
  );
}

/// Apple/Google in practice mode: no platform sheet, no token — it just
/// "signs in" the throwaway practice user.
class SandboxSocialSignIn extends ObSocialSignIn {
  const SandboxSocialSignIn();

  @override
  Future<void> apple(AuthController auth) => auth.signInWithApple('practice');

  @override
  Future<bool> google(AuthController auth) async {
    await auth.signInWithGoogle('practice');
    return true;
  }
}

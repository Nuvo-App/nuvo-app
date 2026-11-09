import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/motion.dart';
import '../../core/v13/tokens.dart';
import '../auth/presentation/auth_controller.dart';
import 'auth_visuals/code_step.dart';
import 'auth_visuals/email_step.dart';
import 'auth_visuals/sign_in_step.dart';
import 'flow/onboarding_flow_controller.dart';
import 'flow/onboarding_step.dart';
import 'intro/intro_board_step.dart';
import 'intro/intro_camera_step.dart';
import 'intro/intro_race_step.dart';
import 'intro/splash_step.dart';
import 'levelup/level_up_step.dart';
import 'player/first_race_ready_step.dart';
import 'player/player_card_step.dart';
import 'player/questions_one_step.dart';
import 'player/questions_two_step.dart';
import 'shell/onboarding_shell_controller.dart';
import 'shell/xp_rail.dart';
import 'tour/arena_tour_step.dart';
import 'tour/notify_opt_in_step.dart';
import 'tour/tour_compete_step.dart';
import 'tour/tour_crew_step.dart';
import 'tour/tour_profile_step.dart';

/// The onboarding-v2 flow host — owns the persistent
/// [OnboardingShellController], swaps the active step with the spec's
/// enter/exit transition, and performs the graduation handoff to /arena.
///
/// Routing contract (auth_gate untouched, see docs/NAVIGATION_MAP.md):
/// this screen is reachable signed-out (the intros/sign-in are part of the
/// flow) and signed-in-incomplete; a signed-in-COMPLETE account is bounced
/// back to /arena by the host itself.
class OnboardingV2Screen extends ConsumerStatefulWidget {
  const OnboardingV2Screen({super.key});

  @override
  ConsumerState<OnboardingV2Screen> createState() => _OnboardingV2ScreenState();
}

class _OnboardingV2ScreenState extends ConsumerState<OnboardingV2Screen> {
  late final OnboardingShellController _shell = OnboardingShellController();
  bool _graduating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = ref.read(authControllerProvider).user;
      if (user != null && user.onboardingComplete) {
        context.go('/arena');
        return;
      }
      ref
          .read(onboardingFlowProvider.notifier)
          .restore(accountEmail: user?.email);
    });
  }

  @override
  void dispose() {
    _shell.dispose();
    super.dispose();
  }

  /// The account that just authenticated mid-flow adopts the anonymous
  /// pre-auth progress (or wipes a different person's record).
  void _onAuthChanged(AuthState? prev, AuthState next) {
    final email = next.user?.email;
    final prevEmail = prev?.user?.email;
    if (email != null && email != prevEmail) {
      ref.read(onboardingFlowProvider.notifier).attachAccount(email);
    }
  }

  /// The flow ran out of steps (or the tour-skip deferral resolved): write
  /// the server flag, then leave — the same write old builds make.
  Future<void> _maybeGraduate(
    OnboardingFlowState? prev,
    OnboardingFlowState next,
  ) async {
    if (!next.readyToGraduate || _graduating) return;
    _graduating = true;
    final ok = await ref.read(onboardingFlowProvider.notifier).graduate();
    if (!mounted) return;
    if (ok) {
      context.go('/arena');
    } else {
      _graduating = false;
    }
  }

  void _onStepChanged(OnboardingFlowState? prev, OnboardingFlowState next) {
    _shell.panTrackTo(next.step.index);
    _shell.syncXp(next.totalXp);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider, _onAuthChanged);
    ref.listen(onboardingFlowProvider, _maybeGraduate);
    ref.listen(onboardingFlowProvider, _onStepChanged);

    final flow = ref.watch(onboardingFlowProvider);
    if (!flow.restored) {
      return const Scaffold(
        backgroundColor: V13.bg,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return OnboardingShellScope(
      controller: _shell,
      child: Stack(
        children: [
          AnimatedSwitcher(
            duration: NuvoMotion.reduceMotionOf(context)
                ? NuvoMotion.reduceMotionFade
                : NuvoMotion.springDuration,
            transitionBuilder: NuvoMotion.stepTransition,
            child: KeyedSubtree(
              key: ValueKey(flow.step),
              child: _stepScreen(flow.step),
            ),
          ),
          XpFlyOverlay(controller: _shell),
        ],
      ),
    );
  }

  Widget _stepScreen(OnboardingStep step) => switch (step) {
    OnboardingStep.splash => const ObSplashStep(),
    OnboardingStep.introRace => const ObIntroRaceStep(),
    OnboardingStep.introCamera => const ObIntroCameraStep(),
    OnboardingStep.introBoard => const ObIntroBoardStep(),
    OnboardingStep.signIn => const ObSignInStep(),
    OnboardingStep.email => const ObEmailStep(),
    OnboardingStep.code => const ObCodeStep(),
    OnboardingStep.playerCard => const ObPlayerCardStep(),
    OnboardingStep.questions1 => const ObQuestionsOneStep(),
    OnboardingStep.questions2 => const ObQuestionsTwoStep(),
    OnboardingStep.firstRaceReady => const ObFirstRaceReadyStep(),
    OnboardingStep.arenaTour => const ObArenaTourStep(),
    OnboardingStep.notifyOptIn => const ObNotifyOptInStep(),
    OnboardingStep.tourCompete => const ObTourCompeteStep(),
    OnboardingStep.tourCrew => const ObTourCrewStep(),
    OnboardingStep.tourProfile => const ObTourProfileStep(),
    OnboardingStep.levelUp => const ObLevelUpStep(),
  };
}

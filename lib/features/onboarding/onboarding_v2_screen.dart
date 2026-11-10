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
import 'intro/intro_how_step.dart';
import 'intro/intro_race_step.dart';
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
  const OnboardingV2Screen({super.key, this.sandbox = false});

  /// Practice mode (Settings > Replay onboarding): isolated providers, a
  /// visible tag, and leaving pops back instead of entering the Arena.
  final bool sandbox;

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
      if (!widget.sandbox && user != null && user.onboardingComplete) {
        context.go('/arena');
        return;
      }
      _restoreAndRoute(user?.email);
    });
  }

  Future<void> _restoreAndRoute(String? email) async {
    final flow = ref.read(onboardingFlowProvider.notifier);
    await flow.restore(accountEmail: email);
    if (!mounted || email != null || widget.sandbox) return;
    // Explicit sign-out: land on the login sheet, not the intro.
    if (ref.read(explicitSignOutProvider)) {
      ref.read(explicitSignOutProvider.notifier).state = false;
      ref.read(authIntentProvider.notifier).state = AuthIntent.signIn;
      final s = ref.read(onboardingFlowProvider).step;
      if (s == OnboardingStep.introRace || s == OnboardingStep.introHow) {
        await flow.skipIntros();
      }
    }
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
    // graduate() never blocks on the network (it falls back to a pending
    // local graduation + background retry), so this always enters Arena.
    // Level Up's own CTA already graduated → don't write twice.
    if (!next.completed.contains(OnboardingStep.levelUp)) {
      await ref.read(onboardingFlowProvider.notifier).graduate();
    }
    if (!mounted) return;
    _leave();
  }

  /// Real flow: into the Arena. Practice mode: back to where it was opened.
  void _leave() {
    if (widget.sandbox) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/profile');
      }
      return;
    }
    context.go('/arena');
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
    // Not restored yet, or finished and graduating: a calm loader — never a
    // fallback step (Level Up only appears as the step after the tour).
    if (!flow.restored || flow.readyToGraduate) {
      return const Scaffold(
        backgroundColor: V13.bg,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final flowBody = OnboardingShellScope(
      controller: _shell,
      child: Stack(
        children: [
          AnimatedSwitcher(
            duration: NuvoMotion.reduceMotionOf(context)
                ? NuvoMotion.reduceMotionFade
                : NuvoMotion.springDuration,
            // The outgoing screen is gone in the quick exit, and the
            // incoming one only starts fading in once it is — no frames
            // where two hero cards are on screen at once.
            reverseDuration: NuvoMotion.exit,
            transitionBuilder: _stepTransition,
            child: KeyedSubtree(
              key: ValueKey(flow.step),
              child: _stepScreen(flow.step),
            ),
          ),
          XpFlyOverlay(controller: _shell),
        ],
      ),
    );
    if (!widget.sandbox) return flowBody;
    // Practice mode: shift the flow's chrome down and tag it clearly.
    final mq = MediaQuery.of(context);
    return Stack(
      children: [
        MediaQuery(
          data: mq.copyWith(
            padding: mq.padding.copyWith(top: mq.padding.top + 30),
          ),
          child: flowBody,
        ),
        Positioned(
          top: mq.padding.top + 4,
          left: 0,
          right: 0,
          child: Center(child: _PracticeTag(onExit: _leave)),
        ),
      ],
    );
  }

  /// [NuvoMotion.stepTransition], with the entering child held back until
  /// the leaving one has faded (first 40% of the enter is still).
  static Widget _stepTransition(Widget child, Animation<double> animation) {
    final entering = AnimatedBuilder(
      animation: animation,
      child: NuvoMotion.stepTransition(child, animation),
      builder: (context, c) => Opacity(
        opacity: ((animation.value - 0.4) / 0.6).clamp(0.0, 1.0),
        child: c,
      ),
    );
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) => animation.status == AnimationStatus.reverse
          ? NuvoMotion.stepTransition(child, animation)
          : entering,
    );
  }

  Widget _stepScreen(OnboardingStep step) => switch (step) {
    // Retired: auto-completed by the controller, never rendered.
    OnboardingStep.splash => const SizedBox.shrink(),
    OnboardingStep.introRace => const ObIntroRaceStep(),
    OnboardingStep.introHow => const ObIntroHowStep(),
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

/// "Practice mode" pill — always visible, tap to leave.
class _PracticeTag extends StatelessWidget {
  const _PracticeTag({required this.onExit});

  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return NuvoPressable(
      key: const ValueKey('practice-tag'),
      onTap: onExit,
      borderRadius: BorderRadius.circular(V13.radiusPill),
      semanticLabel: 'Practice mode. Nothing is saved. Tap to exit.',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: V13.sun,
          borderRadius: BorderRadius.circular(V13.radiusPill),
          border: Border.all(color: V13.navy, width: V13.outline),
        ),
        child: Text(
          'Practice mode \u00b7 nothing is saved \u00b7 Exit',
          style: V13.caption.copyWith(
            color: V13.navy,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

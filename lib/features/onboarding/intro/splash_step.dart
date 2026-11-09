import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/asset_paths.dart';
import '../../../core/motion/motion.dart';
import '../../../core/v13/tokens.dart';
import '../../auth/presentation/auth_controller.dart';
import '../flow/onboarding_flow_controller.dart';
import '../flow/onboarding_step.dart';
import '../shell/onboarding_shell_controller.dart';
import '../shell/track_painter.dart';

/// S0 — splash handoff (spec: "existing logo anim, tap to skip once auth
/// resolved; logo blue dot becomes first Track bead and travels into S1").
///
/// The existing launch frame sequence plays once over
/// [NuvoMotion.splashHold]; the image is laid out so the animation's final
/// resting ball lands exactly on the Track's avatar bead (progress 0 sits
/// at width/2, height·0.44 in [TrackPainter]). When the step advances, the
/// frame image drops and the identical bead beneath keeps moving — the dot
/// literally becomes the first bead and rides the 420 ms pan into S1.
///
/// Advance = animation finished AND auth resolved ([AuthStatus] != loading);
/// a tap skips the rest of the hold only once auth has resolved, mirroring
/// the launch splash's contract.
class ObSplashStep extends ConsumerStatefulWidget {
  const ObSplashStep({super.key});

  @override
  ConsumerState<ObSplashStep> createState() => _ObSplashStepState();
}

class _ObSplashStepState extends ConsumerState<ObSplashStep>
    with SingleTickerProviderStateMixin {
  /// Displayed frame-image size.
  static const double _imgSize = 240;

  /// The ball's resting center inside the last frame, as a fraction of the
  /// frame image (the launch animation settles top-center).
  static const Offset _ballRest = Offset(0.5, 0.19);

  /// The Track's avatar bead at progress 0 — [TrackPainter] puts it at
  /// (w/2, h·0.44).
  static const double _beadYFraction = 0.44;

  late final AnimationController _frames = AnimationController(
    vsync: this,
    duration: NuvoMotion.splashHold,
  );

  bool _done = false;
  bool _animEnded = false;

  @override
  void initState() {
    super.initState();
    _frames.addStatusListener((status) {
      if (status != AnimationStatus.completed) return;
      setState(() => _animEnded = true);
      _tryAdvance();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_frames.isAnimating || _animEnded) return;
    if (NuvoMotion.reduceMotionOf(context)) {
      // Reduce-motion: the sequence is the motion — hold the settled frame.
      _frames.value = 1;
      _animEnded = true;
      scheduleMicrotask(_tryAdvance);
      return;
    }
    _frames.forward();
  }

  bool get _authResolved =>
      ref.read(authControllerProvider).status != AuthStatus.loading;

  void _tryAdvance() {
    if (!mounted || _done || !_animEnded || !_authResolved) return;
    _done = true;
    // Dropping the frame image reveals the identical bead painted by the
    // Track underneath — the "dot becomes a bead" handoff.
    setState(() {});
    ref
        .read(onboardingFlowProvider.notifier)
        .completeStep(OnboardingStep.splash);
  }

  /// Tap-to-skip: only once auth resolved (spec). While loading, taps fall
  /// through — the launch splash behaves the same way.
  void _onTap() {
    if (_authResolved) {
      setState(() => _animEnded = true);
      _tryAdvance();
    }
  }

  @override
  void dispose() {
    _frames.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Auth resolving mid-hold completes the step without a tap.
    ref.listen(authControllerProvider, (_, _) => _tryAdvance());

    final shell = OnboardingShellScope.of(context);
    return Scaffold(
      backgroundColor: V13.bg,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _onTap,
        child: Stack(
          children: [
            TrackBackground(controller: shell),
            LayoutBuilder(
              builder: (context, constraints) {
                final bead = Offset(
                  constraints.maxWidth / 2,
                  constraints.maxHeight * _beadYFraction,
                );
                final imgTop = bead.dy - _ballRest.dy * _imgSize;
                return Stack(
                  children: [
                    // The wordmark — the real splash's end state, quiet.
                    Positioned(
                      left: 0,
                      right: 0,
                      top: constraints.maxHeight * 0.22,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'WELCOME TO',
                            style: V13.label.copyWith(
                              color: V13.blue,
                              fontSize: 13,
                              letterSpacing: 3.1,
                            ),
                          ),
                          const SizedBox(height: V13.gapSm),
                          Image.asset(
                            'assets/branding/nuvotext.png',
                            width: 190,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => Text(
                              'nuvo',
                              style: V13.title.copyWith(fontSize: 40),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // The launch frame sequence — ends with the blue ball
                    // resting exactly on the Track's first bead.
                    if (!_done)
                      Positioned(
                        left: bead.dx - _ballRest.dx * _imgSize,
                        top: imgTop,
                        child: AnimatedBuilder(
                          animation: _frames,
                          builder: (context, _) {
                            final frame = (_frames.value *
                                    (AssetPaths.splashFrameCount - 1))
                                .round()
                                .clamp(0, AssetPaths.splashFrameCount - 1);
                            return Image.asset(
                              AssetPaths.splashFrame(frame),
                              width: _imgSize,
                              height: _imgSize,
                              gaplessPlayback: true,
                              filterQuality: FilterQuality.medium,
                              errorBuilder: (_, _, _) => const _SplashDot(),
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Fallback for the frame sequence — the bead the animation ends on.
class _SplashDot extends StatelessWidget {
  const _SplashDot();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: const Alignment(0, -0.62),
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: V13.blue,
          shape: BoxShape.circle,
          border: Border.all(color: V13.navy, width: V13.outline),
        ),
        child: Center(
          child: Container(
            width: 9,
            height: 9,
            decoration: const BoxDecoration(
              color: V13.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

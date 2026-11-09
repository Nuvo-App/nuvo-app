import 'package:flutter/material.dart';

import '../../../core/motion/motion.dart';
import '../../../core/v13/tokens.dart';
import '../flow/onboarding_copy.dart';

enum ObStampState { none, ready, verified }

/// The "player pass" ticket shared by S5 and S6: outlined sky ticket with a
/// perforated stub, the Nuvo mark, PLAYER PASS, the typed email on a
/// monospace line and a stamp slot. [compact] shrinks it to 60% (keyboard
/// up); [printing] lifts it while a code is being sent.
class ObPlayerPass extends StatelessWidget {
  const ObPlayerPass({
    super.key,
    required this.email,
    this.stamp = ObStampState.none,
    this.compact = false,
    this.printing = false,
    this.caption,
  });

  final String email;
  final ObStampState stamp;
  final bool compact;
  final bool printing;

  /// Optional line under the email ("Code sent to ...").
  final String? caption;

  static const double width = 300;
  static const double height = 170;

  @override
  Widget build(BuildContext context) {
    final reduce = NuvoMotion.reduceMotionOf(context);
    final duration = reduce ? Duration.zero : NuvoMotion.springDuration;
    return Center(
      child: OverflowBox(
        maxWidth: width,
        maxHeight: height,
        child: AnimatedScale(
          scale: compact ? 0.6 : 1,
          duration: duration,
          curve: NuvoMotion.spring,
          child: AnimatedSlide(
            offset: Offset(0, printing ? -NuvoMotion.printLift / height : 0),
            duration: duration,
            curve: NuvoMotion.spring,
            child: NuvoFloat(
              child: SizedBox(
                width: width,
                height: height,
                child: _Ticket(email: email, stamp: stamp, caption: caption),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Ticket extends StatelessWidget {
  const _Ticket({
    required this.email,
    required this.stamp,
    required this.caption,
  });

  final String email;
  final ObStampState stamp;
  final String? caption;

  static const double stubWidth = 96;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: V13.sky,
        borderRadius: BorderRadius.circular(V13.radiusCard),
        border: Border.all(color: V13.navy, width: V13.outlineThick),
        boxShadow: V13.shadow6,
      ),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(V13.gapLg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: V13.navy,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'N',
                          style: V13.buttonLabel.copyWith(color: V13.white),
                        ),
                      ),
                      const SizedBox(width: V13.gapSm),
                      Expanded(
                        child: Text(
                          ObCopy.playerPassLabel,
                          style: V13.label.copyWith(color: V13.navy),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    email.isEmpty ? 'you@email.com' : email,
                    key: const ValueKey('ob-pass-email'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: email.isEmpty
                          ? V13.navy.withValues(alpha: 0.4)
                          : V13.navy,
                    ),
                  ),
                  if (caption != null) ...[
                    const SizedBox(height: V13.gapXs),
                    Text(
                      caption!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: V13.caption.copyWith(color: V13.navy),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const _Perforation(),
          SizedBox(
            width: stubWidth,
            child: Center(child: ObStamp(state: stamp)),
          ),
        ],
      ),
    );
  }
}

/// Dashed tear line with the two bg-coloured notches.
class _Perforation extends StatelessWidget {
  const _Perforation();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 2,
      child: LayoutBuilder(
        builder: (context, c) {
          final dashes = (c.maxHeight / 10).floor();
          return Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (var i = 0; i < dashes; i++)
                Container(width: 2, height: 5, color: V13.navy),
            ],
          );
        },
      ),
    );
  }
}

/// The stamp slot: muted "Not verified yet", mint "Ready", mint "VERIFIED"
/// (which slams in).
class ObStamp extends StatelessWidget {
  const ObStamp({super.key, required this.state});

  final ObStampState state;

  @override
  Widget build(BuildContext context) {
    final label = switch (state) {
      ObStampState.none => ObCopy.emailStampNotVerified,
      ObStampState.ready => ObCopy.emailStampReady,
      ObStampState.verified => ObCopy.codeStampVerified,
    };
    final active = state != ObStampState.none;
    final reduce = NuvoMotion.reduceMotionOf(context);
    final box = Transform.rotate(
      angle: -0.14,
      child: Container(
        key: ValueKey('ob-stamp-${state.name}'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: active ? V13.mint : Colors.transparent,
          borderRadius: BorderRadius.circular(V13.radiusTile),
          border: Border.all(
            color: active ? V13.navy : V13.navy.withValues(alpha: 0.35),
            width: V13.outlineThick,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: V13.label.copyWith(
            color: active ? V13.navy : V13.navy.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
    if (reduce || !active) return box;
    // Slam: starts oversized and springs down onto the ticket (overshoot
    // comes from the spring curve).
    return TweenAnimationBuilder<double>(
      key: ValueKey(state),
      tween: Tween(begin: 1.8, end: 1),
      duration: NuvoMotion.springDuration,
      curve: NuvoMotion.spring,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: box,
    );
  }
}

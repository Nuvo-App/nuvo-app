import 'package:flutter/material.dart';

import '../../../core/motion/motion.dart';
import '../../../core/v13/tokens.dart';
import '../flow/onboarding_copy.dart';

enum ObStampState { none, ready, verified }

/// The "player pass" ticket shared by S5 and S6: outlined sky ticket with a
/// perforated stub, the Nuvo mark, PLAYER PASS, the typed email (each
/// character springs in as it is typed) and a stamp slot. It scales to fit
/// whatever hero slot the screen gives it (never overflowing, never tiny on a
/// tall phone); [printing] lifts it while a code is being sent.
class ObPlayerPass extends StatelessWidget {
  const ObPlayerPass({
    super.key,
    required this.email,
    this.stamp = ObStampState.none,
    this.printing = false,
    this.caption,
    this.header,
  });

  final String email;
  final ObStampState stamp;
  final bool printing;

  /// Optional line under the email ("Code sent to ...").
  final String? caption;

  /// Optional small line above the ticket ("Step 1 of 4"); only drawn when
  /// the slot is tall enough to carry it.
  final String? header;

  static const double width = 300;
  static const double height = 176;

  @override
  Widget build(BuildContext context) {
    final reduce = NuvoMotion.reduceMotionOf(context);
    final duration = reduce ? Duration.zero : NuvoMotion.springDuration;
    return ClipRect(
      clipBehavior: Clip.none,
      child: LayoutBuilder(
        builder: (context, c) {
          final showHeader = header != null && c.maxHeight >= 230;
          // Room for the hard shadow (6) and the float travel.
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (showHeader)
                Padding(
                  padding: const EdgeInsets.only(bottom: V13.gapMd),
                  child: Text(header!, style: V13.caption),
                ),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
                  child: AnimatedSlide(
                    offset: Offset(
                      0,
                      printing ? -NuvoMotion.printLift / height : 0,
                    ),
                    duration: duration,
                    curve: NuvoMotion.spring,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: NuvoFloat(
                        child: SizedBox(
                          width: width,
                          height: height,
                          child: _Ticket(
                            email: email,
                            stamp: stamp,
                            caption: caption,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
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

  static const double stubWidth = 92;

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
              padding: const EdgeInsets.fromLTRB(
                V13.gapLg,
                V13.gapLg,
                V13.gapMd,
                V13.gapLg,
              ),
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
                  _EmailLine(email: email),
                  const SizedBox(height: V13.gapSm),
                  if (caption != null)
                    Text(
                      caption!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: V13.caption.copyWith(color: V13.navy),
                    )
                  else
                    const _Barcode(),
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

/// The typed address on the ticket. Each character springs in from 40% as it
/// lands (keyed by position + glyph, so only new characters animate); a long
/// address shrinks to fit rather than clipping.
class _EmailLine extends StatelessWidget {
  const _EmailLine({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    final empty = email.isEmpty;
    final text = empty ? 'you@email.com' : email;
    final style = V13.bodyStrong.copyWith(
      fontSize: 15,
      height: 1.2,
      letterSpacing: 0.4,
      color: empty ? V13.navy.withValues(alpha: 0.4) : V13.navy,
    );
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: SizedBox(
        height: 22,
        child: Align(
          alignment: Alignment.centerLeft,
          child: FittedBox(
            key: const ValueKey('ob-pass-email'),
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < text.length; i++)
                  empty
                      ? Text(text[i], style: style)
                      : _CharPop(
                          key: ValueKey('$i${text[i]}'),
                          child: Text(text[i], style: style),
                        ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CharPop extends StatelessWidget {
  const _CharPop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (NuvoMotion.reduceMotionOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.4, end: 1),
      duration: NuvoMotion.springDuration,
      curve: NuvoMotion.spring,
      builder: (context, scale, child) => Opacity(
        opacity: ((scale - 0.4) / 0.4).clamp(0.0, 1.0),
        child: Transform.scale(scale: scale, child: child),
      ),
      child: child,
    );
  }
}

/// The decorative barcode strip along the ticket's bottom edge.
class _Barcode extends StatelessWidget {
  const _Barcode();

  static const _bars = [2, 1, 3, 1, 2, 2, 1, 3, 2, 1, 1, 3, 1, 2, 3, 1, 2, 1];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 18,
      child: Row(
        children: [
          for (var i = 0; i < _bars.length; i++) ...[
            Container(
              width: _bars[i].toDouble(),
              color: V13.navy.withValues(alpha: 0.75),
            ),
            const SizedBox(width: 2),
          ],
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

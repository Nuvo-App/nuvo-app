import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../motion/motion.dart';
import '../tokens.dart';
import 'v13_button.dart';
import 'v13_card.dart';
import 'v13_nuvo_qr.dart';

/// The designed empty state: one coloured, floating hero card with a moving
/// [art] slot, a title, one sentence, one blue CTA and an optional text link.
/// Replaces dashed "nothing here" boxes (onboarding-v2 spec, EMPTY STATES).
///
/// With [expandArt] the card fills the height it is given (the Arena swiper
/// hands it the race card's height) and the art takes the spare room;
/// otherwise the art is [artHeight] tall and the card hugs its content.
class V13EmptyHero extends StatelessWidget {
  const V13EmptyHero({
    super.key,
    required this.color,
    required this.art,
    required this.title,
    required this.body,
    required this.ctaLabel,
    required this.onCta,
    this.ctaIcon,
    this.linkLabel,
    this.onLink,
    this.expandArt = false,
    this.artHeight = 120,
    this.semanticLabel,
  });

  final Color color;
  final Widget art;
  final String title;
  final String body;
  final String ctaLabel;
  final IconData? ctaIcon;
  final VoidCallback onCta;
  final String? linkLabel;
  final VoidCallback? onLink;
  final bool expandArt;
  final double artHeight;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final artBox = expandArt
        ? Expanded(child: Center(child: art))
        : SizedBox(
            height: artHeight,
            child: Center(child: art),
          );
    return NuvoFloat(
      phase: 0,
      child: V13Card(
        color: color,
        radius: V13.radiusCard,
        shadow: V13.shadow6,
        padding: const EdgeInsets.all(V13.gapMd + 2),
        semanticLabel: semanticLabel ?? title,
        child: Column(
          mainAxisSize: expandArt ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            artBox,
            const SizedBox(height: V13.gapMd),
            Text(
              title,
              style: V13.cardTitle.copyWith(fontSize: 22),
              textAlign: TextAlign.center,
              maxLines: 2,
            ),
            const SizedBox(height: V13.gapXs),
            Text(
              body,
              style: V13.body.copyWith(
                color: V13.navy,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: V13.gapMd),
            V13Button.primary(
              label: ctaLabel,
              icon: ctaIcon,
              fullWidth: true,
              onPressed: onCta,
            ),
            if (linkLabel != null && onLink != null)
              NuvoPressable(
                onTap: onLink,
                semanticLabel: linkLabel,
                child: Container(
                  height: 40,
                  alignment: Alignment.center,
                  child: Text(
                    linkLabel!,
                    style: V13.buttonLabel.copyWith(
                      color: V13.navy,
                      decoration: TextDecoration.underline,
                      decorationColor: V13.navy,
                      decorationStyle: TextDecorationStyle.solid,
                      decorationThickness: 2,
                    ),
                  ),
                ),
              )
            else
              const SizedBox(height: V13.gapXs),
          ],
        ),
      ),
    );
  }
}

/// A ghosted race: three silhouette racers on their lanes creeping toward a
/// finish flag. Purely decorative — still under reduce-motion.
class V13GhostRace extends StatefulWidget {
  const V13GhostRace({super.key, this.height = 108});

  final double height;

  @override
  State<V13GhostRace> createState() => _V13GhostRaceState();
}

class _V13GhostRaceState extends State<V13GhostRace>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: NuvoMotion.floatPeriod,
  );
  bool _started = false;

  // Resting progress per lane (front to back) and which lane is "you".
  static const _progress = [0.66, 0.46, 0.26];
  static const _youLane = 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!NuvoMotion.reduceMotionOf(context)) _ctrl.repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: LayoutBuilder(
          builder: (context, c) {
            final laneH = widget.height / 3;
            final token = math.min(laneH - 6, 34.0);
            const flagW = 26.0;
            final trackW = c.maxWidth - flagW - 4;
            return AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) {
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (var i = 0; i < 3; i++) ...[
                      Positioned(
                        left: 0,
                        width: trackW + token / 2,
                        top: laneH * i + laneH / 2 - 1,
                        child: Container(
                          height: 2,
                          decoration: BoxDecoration(
                            color: V13.navy.withValues(alpha: 0.28),
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                      Positioned(
                        left:
                            (trackW - token) *
                            (_progress[i] +
                                0.035 *
                                    math.sin(
                                      _ctrl.value * 2 * math.pi + i * 2.1,
                                    )),
                        top: laneH * i + (laneH - token) / 2,
                        child: _Racer(size: token, you: i == _youLane),
                      ),
                    ],
                    const Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      width: flagW,
                      child: _FinishLine(),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _Racer extends StatelessWidget {
  const _Racer({required this.size, required this.you});

  final double size;
  final bool you;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: V13.card,
        border: Border.all(
          color: you ? V13.blue : V13.navy,
          width: you ? V13.outlineThick : V13.outline,
        ),
        boxShadow: const [BoxShadow(color: V13.navy, offset: Offset(0, 2))],
      ),
      child: Icon(
        Icons.person_rounded,
        size: size * 0.62,
        color: V13.navy.withValues(alpha: 0.5),
      ),
    );
  }
}

class _FinishLine extends StatelessWidget {
  const _FinishLine();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 2.5,
          decoration: BoxDecoration(
            color: V13.navy,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const Positioned(
          top: 0,
          left: 5,
          child: Icon(Icons.flag_rounded, size: 22, color: V13.navy),
        ),
      ],
    );
  }
}

/// A faded leaderboard: three ghost rows (rank, silhouette, name bar,
/// points bar). Decorative art for "add friends to see a board".
class V13GhostBoard extends StatelessWidget {
  const V13GhostBoard({super.key});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : V13.gapSm),
              child: Opacity(
                opacity: 1 - i * 0.22,
                child: Row(
                  children: [
                    SizedBox(
                      width: 22,
                      child: Text('${i + 1}', style: V13.numberSm),
                    ),
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: V13.card,
                        border: Border.all(
                          color: i == 1 ? V13.blue : V13.navy,
                          width: V13.outline,
                        ),
                      ),
                      child: Icon(
                        Icons.person_rounded,
                        size: 20,
                        color: V13.navy.withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(width: V13.gapMd),
                    Expanded(
                      child: Container(
                        height: 10,
                        margin: EdgeInsets.only(right: 24.0 + i * 16),
                        decoration: BoxDecoration(
                          color: V13.divider,
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ),
                    Container(
                      width: 36,
                      height: 10,
                      decoration: BoxDecoration(
                        color: V13.divider,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "Add friends to see a board" — the white leaderboard empty card with a
/// ghost board and one outlined QR button (the screen keeps its single blue
/// CTA elsewhere).
class V13BoardEmpty extends StatelessWidget {
  const V13BoardEmpty({
    super.key,
    required this.title,
    required this.buttonLabel,
    required this.onPressed,
  });

  final String title;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return V13Card(
      padding: const EdgeInsets.all(V13.gapLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const V13GhostBoard(),
          const SizedBox(height: V13.gapLg),
          Text(title, style: V13.cardTitle, textAlign: TextAlign.center),
          const SizedBox(height: V13.gapMd),
          V13Button.secondary(
            label: buttonLabel,
            icon: Icons.qr_code_2_rounded,
            fullWidth: true,
            onPressed: onPressed,
          ),
        ],
      ),
    );
  }
}

/// A small white tile holding a real, scannable Nuvo-style QR — the preview
/// art for "share my code" empty states.
class V13QrPreview extends StatelessWidget {
  const V13QrPreview({super.key, this.size = 104});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.all(V13.gapSm),
        decoration: BoxDecoration(
          color: V13.card,
          borderRadius: BorderRadius.circular(V13.radiusTileLg),
          border: Border.all(color: V13.navy, width: V13.outlineThick),
          boxShadow: V13.shadow4,
        ),
        child: V13NuvoQr(data: 'https://getnuvo.net', size: size),
      ),
    );
  }
}

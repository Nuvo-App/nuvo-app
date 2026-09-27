import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'nuvo_motion.dart';

/// A two-faced card where the flip itself is the interaction — it separates
/// two information layers ("who are they?" ↔ "how do we compete?"), never a
/// decorative spin.
///
/// Contract (docs/ui/NUVO_PLAY_SYSTEM.md §13.4):
/// - Flip only the card — surrounding chrome (sheet handle, actions) is
///   the caller's and stays put.
/// - Controlled: the parent owns [flipped] and MUST also render a labelled
///   affordance ("Stats ↻" / "About ↻"). The card's own tap ([onFlip]) is
///   a convenience, never the only doorway.
/// - One 400ms rotation, moderate perspective, spring settle; a mid-flight
///   tap reverses from the current angle — no autoplay, no looping.
/// - Fixed footprint via [height] so the host (a bottom sheet) never
///   jumps between faces.
/// - Reduced motion: crossfade + slight slide instead of 3D rotation.
class NuvoFlipCard extends StatefulWidget {
  const NuvoFlipCard({
    super.key,
    required this.front,
    required this.back,
    required this.flipped,
    this.onFlip,
    this.height,
  });

  /// The face shown while [flipped] is false — the identity layer.
  final Widget front;

  /// The face shown while [flipped] is true — the competitive layer.
  final Widget back;

  /// Which side faces out. Parent-owned.
  final bool flipped;

  /// Card-face tap. Callers should toggle [flipped] here AND from their
  /// labelled affordance.
  final VoidCallback? onFlip;

  /// Optional fixed height — pass it whenever both faces must occupy an
  /// exact footprint (the person sheet's contract). When null, the card
  /// sizes to the taller face and keeps that footprint between flips.
  final double? height;

  @override
  State<NuvoFlipCard> createState() => _NuvoFlipCardState();
}

class _NuvoFlipCardState extends State<NuvoFlipCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    value: widget.flipped ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant NuvoFlipCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.flipped == widget.flipped) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _ctrl.value = widget.flipped ? 1 : 0;
      return;
    }
    // 400ms — inside the 350–450ms budget — with a hint of overshoot past
    // flat so the card physically settles instead of stopping dead.
    _ctrl.animateTo(
      widget.flipped ? 1 : 0,
      duration: const Duration(milliseconds: 400),
      curve: NuvoMotion.spring,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final face = widget.flipped ? widget.back : widget.front;
    final child = Semantics(
      button: widget.onFlip != null,
      hint: 'Flips to the other side',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onFlip,
        child: MediaQuery.disableAnimationsOf(context)
            ? AnimatedSwitcher(
                duration: NuvoMotion.select,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position:
                        Tween<Offset>(
                          begin: const Offset(0, 0.04),
                          end: Offset.zero,
                        ).animate(anim),
                    child: child,
                  ),
                ),
                child: KeyedSubtree(
                  key: ValueKey(widget.flipped),
                  child: face,
                ),
              )
            : AnimatedBuilder(
                animation: _ctrl,
                builder: (context, _) {
                  final angle = _ctrl.value * math.pi;
                  // Swap faces while edge-on; the back is un-mirrored by
                  // subtracting π from its accumulated rotation.
                  final showBack = angle >= math.pi / 2;
                  final faceAngle = showBack ? angle - math.pi : angle;
                  return Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0012)
                      ..rotateY(faceAngle),
                    child: showBack ? widget.back : widget.front,
                  );
                },
              ),
      ),
    );
    if (widget.height != null) {
      return SizedBox(height: widget.height, child: child);
    }
    // No explicit height: the inactive face stays laid out invisibly so the
    // card's footprint is the TALLER of the two faces — the page below never
    // shifts when the card turns.
    return Stack(
      children: [
        Visibility(
          visible: false,
          maintainSize: true,
          maintainState: true,
          maintainAnimation: true,
          child: ExcludeSemantics(
            child: widget.flipped ? widget.front : widget.back,
          ),
        ),
        child,
      ],
    );
  }
}

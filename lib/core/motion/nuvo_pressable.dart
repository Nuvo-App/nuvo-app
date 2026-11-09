import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';

import 'nuvo_haptics.dart';
import 'nuvo_motion.dart';

/// The onboarding-v2 press interaction — every tappable surface uses this.
///
/// Spec: "pressDown 90ms easeOut, translate 3px into shadow, shadow 4px to
/// 1px, on every button/chip/tab/actionable row." The shadow plate stays on
/// the floor at its full offset while the surface sinks [NuvoMotion.pressSink]
/// px toward it, so 1 px of plate remains visible at full press — the
/// "4 → 1" read comes from the geometry, not an animated shadow repaint.
/// Release springs back on [NuvoMotion.spring] and fires [NuvoHaptics.light]
/// (gated on the Settings haptics toggle). Reduce-motion presses jump
/// straight to the pressed state.
class NuvoPressable extends StatefulWidget {
  const NuvoPressable({
    super.key,
    required this.child,
    this.onTap,
    this.shadow,
    this.borderRadius,
    this.sink = NuvoMotion.pressSink,
    this.haptic = true,
    this.enabled = true,
    this.semanticLabel,
  }) : assert(
         shadow == null || borderRadius != null,
         'borderRadius is required when shadow is managed by NuvoPressable',
       );

  final Widget child;
  final VoidCallback? onTap;

  /// The resting hard shadow (usually a single `Offset(0, 4)` plate). Drawn
  /// by this widget so it can be compressed during the press — pass the same
  /// [borderRadius] the child uses.
  final List<BoxShadow>? shadow;

  /// Radius the shadow shares with the child's surface.
  final BorderRadius? borderRadius;

  /// Sink distance. Defaults to [NuvoMotion.pressSink] (3 px).
  final double sink;

  /// Fire [NuvoHaptics.light] on tap.
  final bool haptic;

  /// Blocks all interaction when false.
  final bool enabled;

  final String? semanticLabel;

  @override
  State<NuvoPressable> createState() => _NuvoPressableState();
}

class _NuvoPressableState extends State<NuvoPressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: NuvoMotion.pressDown,
    reverseDuration: NuvoMotion.springDuration,
  );

  Offset? _downAt;

  /// A drag (scrolling a list that holds this surface) releases the press so
  /// it doesn't sink while content scrolls under the finger.
  void _move(PointerMoveEvent e) {
    final start = _downAt;
    if (start == null) return;
    if ((e.position - start).distance > kTouchSlop) {
      _downAt = null;
      _up();
    }
  }

  /// Pointer-down (not the gesture arena's delayed tap-down) so the sink
  /// starts the instant a finger lands.
  void _down(PointerDownEvent e) {
    _downAt = e.position;
    if (NuvoMotion.reduceMotionOf(context)) {
      _ctrl.value = 1;
    } else {
      _ctrl.animateTo(
        1,
        duration: NuvoMotion.pressDown,
        curve: NuvoMotion.pressDownCurve,
      );
    }
  }

  /// Release: let the surface finish landing on its plate first — a fast tap
  /// otherwise reverses before the sink is visible — then spring back.
  Future<void> _up() async {
    if (NuvoMotion.reduceMotionOf(context)) {
      _ctrl.value = 0;
      return;
    }
    if (_ctrl.value < 1) {
      await _ctrl.animateTo(
        1,
        duration: NuvoMotion.pressDown * (1 - _ctrl.value),
        curve: NuvoMotion.pressDownCurve,
      );
    }
    if (!mounted) return;
    await _ctrl.animateTo(
      0,
      duration: NuvoMotion.springDuration,
      curve: NuvoMotion.spring,
    );
  }

  void _tap() {
    if (widget.haptic) NuvoHaptics.light();
    widget.onTap?.call();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final interactive = widget.enabled && widget.onTap != null;
    final shadow = widget.shadow;
    return Semantics(
      button: true,
      enabled: interactive,
      label: widget.semanticLabel,
      child: Listener(
        onPointerDown: interactive ? _down : null,
        onPointerMove: interactive ? _move : null,
        onPointerUp: interactive
            ? (_) {
                if (_downAt == null) return;
                _downAt = null;
                _up();
              }
            : null,
        onPointerCancel: interactive ? (_) => _up() : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: interactive ? _tap : null,
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, child) {
              final t = _ctrl.value;
              Widget result = Transform.translate(
                offset: Offset(0, widget.sink * t),
                child: child,
              );
              if (shadow != null) {
                // The plate stays on the floor at its resting offset; the
                // surface slides toward it and covers all but 1 px at full
                // press — the shadow reads as compressed, never repainted.
                result = DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: widget.borderRadius,
                    boxShadow: shadow,
                  ),
                  child: result,
                );
              }
              return result;
            },
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

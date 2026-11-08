import 'package:flutter/material.dart';

import '../motion.dart';

/// The v13 press interaction — every tappable surface uses this.
///
/// On finger-down the surface sinks toward its shadow plate: it translates
/// by the shadow's offset and the shadow is removed, so the surface reads
/// as landing flat on the plate. Release springs back on [V13Motion.spring]
/// and fires a light haptic (gated on the haptics pref).
///
/// When [shadow] is provided it is drawn by this widget (sharing
/// [borderRadius] with the child) so it can be managed during the press —
/// pass the same radius the child uses. Without [shadow] the pressable just
/// translates by [pressDepth].
class V13Pressable extends StatefulWidget {
  const V13Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.shadow,
    this.borderRadius,
    this.pressDepth,
    this.haptic = true,
    this.enabled = true,
    this.semanticLabel,
  }) : assert(
         shadow == null || borderRadius != null,
         'borderRadius is required when shadow is managed by V13Pressable',
       );

  final Widget child;
  final VoidCallback? onTap;

  /// The resting hard shadow. Drawn under the child and removed on press.
  final List<BoxShadow>? shadow;

  /// Radius the shadow shares with the child's surface.
  final BorderRadius? borderRadius;

  /// Sink distance when [shadow] is null. Defaults to the shadow's vertical
  /// offset, else 4.
  final double? pressDepth;

  /// Fire [V13Haptics.light] on tap.
  final bool haptic;

  /// Blocks all interaction when false.
  final bool enabled;

  final String? semanticLabel;

  @override
  State<V13Pressable> createState() => _V13PressableState();
}

class _V13PressableState extends State<V13Pressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: V13Motion.pressIn,
    reverseDuration: V13Motion.medium,
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Offset get _sink {
    final shadow = widget.shadow;
    if (shadow != null && shadow.isNotEmpty) return shadow.first.offset;
    final d = widget.pressDepth ?? 4;
    return Offset(0, d);
  }

  void _down(TapDownDetails _) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _ctrl.value = 1;
    } else {
      _ctrl.forward();
    }
  }

  void _up() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _ctrl.value = 0;
      return;
    }
    _ctrl.animateTo(0, duration: V13Motion.medium, curve: V13Motion.spring);
  }

  void _tap() {
    if (widget.haptic) V13Haptics.light();
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final interactive = widget.enabled && widget.onTap != null;
    final shadow = widget.shadow;
    return Semantics(
      button: true,
      enabled: interactive,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: interactive ? _tap : null,
        onTapDown: interactive ? _down : null,
        onTapUp: interactive ? (_) => _up() : null,
        onTapCancel: interactive ? _up : null,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, child) {
            final t = _ctrl.value;
            Widget result = Transform.translate(
              offset: _sink * t,
              child: child,
            );
            if (shadow != null) {
              // The plate stays on the "floor"; the surface sinks onto it.
              // Once past halfway the plate is covered, so it drops out.
              result = DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: widget.borderRadius,
                  boxShadow: t > 0.5 ? const <BoxShadow>[] : shadow,
                ),
                child: result,
              );
            }
            return result;
          },
          child: widget.child,
        ),
      ),
    );
  }
}

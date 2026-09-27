import 'package:flutter/material.dart';

/// Faded-edge scroll treatment — a Flutter port of the scroll-area masking
/// used by skiper-ui.com/v1/skiper87: content approaching the top/bottom (or
/// left/right) edge of a bounded scroll viewport eases to transparent instead
/// of hitting a hard clip.
///
/// Mechanics:
///
/// - A [ShaderMask] with `BlendMode.dstIn` multiplies the child's alpha by a
///   gradient over the viewport. It is a true alpha mask — the gradient's
///   color channels never touch the content — so the same widget works over
///   light and dark surfaces with no background-color dependency.
/// - Edge visibility comes from scroll metrics delivered by
///   [ScrollNotification]s, not a [ScrollController]: whatever controller,
///   scroll position restoration, or `ensureVisible` behavior the scrollable
///   already owns is untouched.
/// - Each edge's fade ramps in over the first [edgeExtent] pixels of travel
///   and holds, so the mask emerges continuously with the scroll rather than
///   snapping on/off. An edge with no hidden content stays fully opaque:
///   at rest at the top there is no top fade, at the bottom no bottom fade,
///   and content too short to scroll gets no fade at all.
/// - Overscroll reads naturally: pixels clamp into the same ramp, so iOS
///   bounce never exposes a mask boundary or a phantom fade.
/// - Because the mask is applied to the scrollable itself (not an overlay in
///   a `Stack`), taps, drags, flings, and semantics pass through unchanged.
///   Only scroll notifications at depth 0 are used, so nested scrollables
///   (e.g. a horizontal shelf inside a vertical page) don't leak their
///   metrics into this mask.
///
/// Wrap any scrollable — `ListView`, `SingleChildScrollView`,
/// `CustomScrollView`, `GridView` — where content visually enters or exits a
/// constrained viewport. Skip full-screen feeds that already scroll beneath
/// intentional chrome, and skip content that never scrolls.
class NuvoFadeScroll extends StatefulWidget {
  const NuvoFadeScroll({
    super.key,
    required this.child,
    this.edgeExtent = 28,
    this.axis = Axis.vertical,
  });

  /// The scrollable to mask.
  final Widget child;

  /// Maximum fade depth in logical pixels, measured from each edge.
  final double edgeExtent;

  /// Fade orientation until the first scroll metrics arrive (after which the
  /// real scroll axis is used). Set explicitly when wrapping a horizontal
  /// scrollable.
  final Axis axis;

  @override
  State<NuvoFadeScroll> createState() => _NuvoFadeScrollState();
}

class _NuvoFadeScrollState extends State<NuvoFadeScroll> {
  /// Fade strength at the leading/trailing edges, 0 (fully visible) → 1
  /// (full [edgeExtent] fade).
  double _leading = 0;
  double _trailing = 0;
  late Axis _axis = widget.axis;

  bool _onScroll(ScrollNotification notification) {
    // Nested scrollables report at depth > 0 — only the direct child drives
    // this mask.
    if (notification.depth != 0) return false;
    final metrics = notification.metrics;
    final max = metrics.maxScrollExtent;
    final leading = max <= 0
        ? 0.0
        : (metrics.pixels / widget.edgeExtent).clamp(0.0, 1.0);
    final trailing = max <= 0
        ? 0.0
        : ((max - metrics.pixels) / widget.edgeExtent).clamp(0.0, 1.0);
    if (leading != _leading ||
        trailing != _trailing ||
        metrics.axis != _axis) {
      setState(() {
        _leading = leading;
        _trailing = trailing;
        _axis = metrics.axis;
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) {
          final extent = _axis == Axis.vertical ? rect.height : rect.width;
          final f = extent <= 0
              ? 0.0
              : (widget.edgeExtent / extent).clamp(0.0, 0.5);
          return LinearGradient(
            begin: _axis == Axis.vertical
                ? Alignment.topCenter
                : Alignment.centerLeft,
            end: _axis == Axis.vertical
                ? Alignment.bottomCenter
                : Alignment.centerRight,
            colors: [
              Colors.white.withValues(alpha: 1 - _leading),
              Colors.white,
              Colors.white,
              Colors.white.withValues(alpha: 1 - _trailing),
            ],
            stops: [0.0, f, 1 - f, 1.0],
          ).createShader(rect);
        },
        child: widget.child,
      ),
    );
  }
}

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../tokens.dart';
import 'v13_pressable.dart';

/// The signature v13 surface: flat fill, 2 px navy outline, hard offset
/// shadow, 24 px radius. The [V13Card.dashed] variant swaps the solid
/// outline for a dashed one and drops the shadow (used for "empty / add"
/// slots like "Up for another one?").
class V13Card extends StatelessWidget {
  const V13Card({
    super.key,
    required this.child,
    this.color = V13.card,
    this.padding,
    this.radius = V13.radiusCard,
    this.shadow = V13.shadow4,
    this.onTap,
    this.semanticLabel,
  }) : dashed = false;

  /// Dashed "add slot" card — white fill, dashed navy outline, no shadow.
  const V13Card.dashed({
    super.key,
    required this.child,
    this.color = V13.card,
    this.padding,
    this.radius = V13.radiusCard,
    this.onTap,
    this.semanticLabel,
  }) : dashed = true,
       shadow = const <BoxShadow>[];

  final Widget child;
  final Color color;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final List<BoxShadow> shadow;
  final bool dashed;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    Widget box = Container(
      padding: padding ?? const EdgeInsets.all(V13.gapLg),
      decoration: BoxDecoration(
        color: color,
        borderRadius: borderRadius,
        border: dashed ? null : Border.all(color: V13.navy, width: V13.outline),
        boxShadow: onTap == null ? shadow : null,
      ),
      child: child,
    );
    if (dashed) {
      box = CustomPaint(
        foregroundPainter: _DashedBorderPainter(radius: radius),
        child: box,
      );
    }
    if (onTap != null) {
      return V13Pressable(
        onTap: onTap,
        shadow: shadow.isNotEmpty ? shadow : null,
        borderRadius: borderRadius,
        semanticLabel: semanticLabel,
        child: box,
      );
    }
    return box;
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.radius});

  final double radius;

  static const double _dash = 7;
  static const double _gap = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = V13.navy
      ..style = PaintingStyle.stroke
      ..strokeWidth = V13.outline;
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(V13.outline / 2),
      Radius.circular(radius),
    );
    final path = ui.Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + _dash).clamp(0, metric.length).toDouble();
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.radius != radius;
}

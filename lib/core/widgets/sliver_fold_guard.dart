import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A sliver that never lets its child straddle the fold at rest.
///
/// If, at scroll offset 0, the child would start above the fold line and end
/// below it (so the first screen shows it cut off), the sliver adds leading
/// space equal to the distance to the line. The child then starts just below
/// the fold and appears whole as the page scrolls. A child that fits above
/// the line, or starts beyond it, is untouched.
///
/// [foldInset] is the distance from the bottom of the viewport to the line —
/// for the app's pages, the floating nav's top edge.
class SliverFoldGuard extends SingleChildRenderObjectWidget {
  const SliverFoldGuard({
    super.key,
    required this.foldInset,
    required Widget super.child,
  });

  final double foldInset;

  @override
  RenderSliverFoldGuard createRenderObject(BuildContext context) =>
      RenderSliverFoldGuard(foldInset: foldInset);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSliverFoldGuard renderObject,
  ) {
    renderObject
      ..foldInset = foldInset
      ..markNeedsLayout();
  }
}

class RenderSliverFoldGuard extends RenderSliverToBoxAdapter {
  RenderSliverFoldGuard({required this.foldInset});

  double foldInset;

  double _gap = 0;

  @override
  double childMainAxisPosition(RenderBox child) =>
      super.childMainAxisPosition(child) + _gap;

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      geometry = SliverGeometry.zero;
      return;
    }
    final c = constraints;
    child.layout(c.asBoxConstraints(), parentUsesSize: true);
    final h = switch (c.axis) {
      Axis.horizontal => child.size.width,
      Axis.vertical => child.size.height,
    };
    final top = c.precedingScrollExtent;
    final line = c.viewportMainAxisExtent - foldInset;
    final gap = (top < line && top + h > line) ? line - top + 2 : 0.0;
    _gap = gap;
    final total = gap + h;

    final paintedExtent = calculatePaintOffset(c, from: 0, to: total);
    final cacheExtent = calculateCacheOffset(c, from: 0, to: total);
    geometry = SliverGeometry(
      scrollExtent: total,
      paintExtent: paintedExtent,
      paintOrigin: 0,
      cacheExtent: cacheExtent,
      maxPaintExtent: total,
      hitTestExtent: paintedExtent,
      hasVisualOverflow: total > c.remainingPaintExtent || c.scrollOffset > 0,
    );
    setChildParentData(child, c, geometry!);
    final data = child.parentData! as SliverPhysicalParentData;
    data.paintOffset += Offset(0, math.max(0, gap));
  }
}

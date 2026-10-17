import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// First-screen fitting for the tab pages.
///
/// A page puts its sections in a [FoldFitColumn] inside a [SliverFoldFit].
/// At rest (scroll offset 0) the column looks at where the fold falls and, if
/// a section would be cut off by it, adjusts the space around the sections
/// above so the first screen is full and nothing is sliced:
///
///  * if the section overshoots the fold by a little, the flexible gaps
///    above it ([FoldGap]) tighten until it fits whole;
///  * otherwise the gaps above grow (up to a cap) to fill the screen and the
///    section starts just below the fold, appearing whole on scroll.
///
/// A [FoldBelow] section always starts below the fold (e.g. Quick starts).
///
/// [foldInset] is the distance from the bottom of the viewport to the fold —
/// for the app's pages, the floating nav's top edge.
class SliverFoldFit extends MultiChildRenderObjectWidget {
  const SliverFoldFit({
    super.key,
    required this.foldInset,
    this.enabled = true,
    required super.children,
  });

  final double foldInset;

  /// Off while the page is being used in place (a section expanded, search
  /// open, a long feed): the sections then simply stack and scroll.
  final bool enabled;

  @override
  RenderSliverFoldFit createRenderObject(BuildContext context) =>
      RenderSliverFoldFit(foldInset: foldInset, enabled: enabled);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSliverFoldFit renderObject,
  ) {
    renderObject
      ..foldInset = foldInset
      ..enabled = enabled
      ..markNeedsLayout();
  }
}

class _FitParentData extends SliverPhysicalParentData
    with ContainerParentDataMixin<RenderBox> {}

class RenderSliverFoldFit extends RenderSliver
    with
        ContainerRenderObjectMixin<RenderBox, _FitParentData>,
        RenderSliverHelpers {
  RenderSliverFoldFit({required this.foldInset, required this.enabled});

  double foldInset;
  bool enabled;

  /// How much one gap may grow when filling the screen.
  static const double maxGrow = 24;

  /// How much of the gaps above may be given up to keep a section whole.
  static const double maxShrinkShare = 0.4;

  /// Largest blank band (share of the viewport) worth leaving to avoid a cut.
  static const double maxHole = 0.10;

  /// Extra space the gaps were given (negative when tightened). For tests.
  double lastAdjustment = 0;

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! _FitParentData) {
      child.parentData = _FitParentData();
    }
  }

  @override
  void performLayout() {
    final c = constraints;
    final childConstraints = c.asBoxConstraints();
    final kids = <RenderBox>[];
    for (var k = firstChild; k != null; k = childAfter(k)) {
      k.layout(childConstraints, parentUsesSize: true);
      kids.add(k);
    }
    if (kids.isEmpty) {
      geometry = SliverGeometry.zero;
      return;
    }

    final top = c.precedingScrollExtent;
    final line = c.viewportMainAxisExtent - foldInset;

    final tops = <double>[];
    var y = 0.0;
    for (final k in kids) {
      tops.add(y);
      y += k.size.height;
    }

    // First section the fold would cut (or that must start below it).
    int? s;
    var forced = false;
    for (var i = 0; enabled && i < kids.length; i++) {
      final k = kids[i];
      if (k is RenderFoldGap) continue;
      final absTop = top + tops[i];
      final absBottom = absTop + k.size.height;
      if (k is RenderFoldBelow && absTop < line + 2) {
        s = i;
        forced = true;
        break;
      }
      if (absTop < line && absBottom > line) {
        s = i;
        break;
      }
    }

    final gaps = <int>[];
    var gapTotal = 0.0;
    if (s != null) {
      for (var i = 0; i < s; i++) {
        if (kids[i] is RenderFoldGap) {
          gaps.add(i);
          gapTotal += kids[i].size.height;
        }
      }
    }

    lastAdjustment = 0;
    final delta = List<double>.filled(kids.length, 0);
    if (s != null) {
      final sTop = top + tops[s];
      final overshoot = sTop + kids[s].size.height - (line - 2);
      if (!forced &&
          gaps.isNotEmpty &&
          overshoot > 0 &&
          overshoot <= gapTotal * maxShrinkShare) {
        // Tighten the gaps above so the section ends just above the fold.
        final f = (gapTotal - overshoot) / gapTotal;
        for (final i in gaps) {
          delta[i] = kids[i].size.height * (f - 1);
        }
        lastAdjustment = -overshoot;
      } else {
        // Grow the gaps (capped) and start the section just below the fold.
        final slack = math.max(0.0, line + 2 - sTop);
        var grown = 0.0;
        if (gaps.isNotEmpty) {
          final each = math.min(slack / gaps.length, maxGrow);
          grown = each * gaps.length;
        }
        // A large section that can't be absorbed by the gaps would leave a
        // hole instead of a full screen; let it scroll in naturally.
        final hole = slack - grown;
        if (forced || hole <= c.viewportMainAxisExtent * maxHole) {
          if (gaps.isNotEmpty) {
            final each = math.min(slack / gaps.length, maxGrow);
            for (final i in gaps) {
              delta[i] = each;
            }
          }
          delta[s] += hole; // calm space before the section
          lastAdjustment = slack;
        }
      }
    }

    var offset = 0.0;
    for (var i = 0; i < kids.length; i++) {
      final k = kids[i];
      if (k is RenderFoldGap) {
        offset += k.size.height + delta[i];
      } else {
        if (i == s) offset += delta[i];
        (k.parentData! as SliverPhysicalParentData).paintOffset = Offset(
          0,
          offset - c.scrollOffset,
        );
        offset += k.size.height;
      }
    }

    final painted = calculatePaintOffset(c, from: 0, to: offset);
    final cache = calculateCacheOffset(c, from: 0, to: offset);
    geometry = SliverGeometry(
      scrollExtent: offset,
      paintExtent: painted,
      paintOrigin: 0,
      cacheExtent: cache,
      maxPaintExtent: offset,
      hitTestExtent: painted,
      hasVisualOverflow: offset > c.remainingPaintExtent || c.scrollOffset > 0,
    );
  }

  @override
  double childMainAxisPosition(RenderBox child) =>
      (child.parentData! as SliverPhysicalParentData).paintOffset.dy;

  @override
  double childCrossAxisPosition(RenderBox child) => 0;

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final data = child.parentData! as SliverPhysicalParentData;
    data.applyPaintTransform(transform);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (geometry == null || geometry!.paintExtent <= 0) return;
    for (var k = firstChild; k != null; k = childAfter(k)) {
      final data = k.parentData! as SliverPhysicalParentData;
      context.paintChild(k, offset + data.paintOffset);
    }
  }

  @override
  bool hitTestChildren(
    SliverHitTestResult result, {
    required double mainAxisPosition,
    required double crossAxisPosition,
  }) {
    for (var k = lastChild; k != null; k = childBefore(k)) {
      if (hitTestBoxChild(
        BoxHitTestResult.wrap(result),
        k,
        mainAxisPosition: mainAxisPosition,
        crossAxisPosition: crossAxisPosition,
      )) {
        return true;
      }
    }
    return false;
  }
}

/// Space between sections that [FoldFitColumn] may grow or tighten.
class FoldGap extends LeafRenderObjectWidget {
  const FoldGap(this.height, {super.key});

  final double height;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderFoldGap(height);

  @override
  void updateRenderObject(BuildContext context, RenderFoldGap renderObject) {
    renderObject.height = height;
  }
}

class RenderFoldGap extends RenderBox {
  RenderFoldGap(this._height);

  double _height;
  double get height => _height;
  set height(double v) {
    if (v == _height) return;
    _height = v;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    size = constraints.constrain(Size(constraints.maxWidth, _height));
  }
}

/// Marks a section that must start below the fold at rest.
class FoldBelow extends SingleChildRenderObjectWidget {
  const FoldBelow({super.key, required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => RenderFoldBelow();
}

class RenderFoldBelow extends RenderProxyBox {}

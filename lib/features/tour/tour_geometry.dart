import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../core/motion/motion.dart';

/// The rounded cutout around [target]: target radius + the pad, the whole
/// target inflated by the pad.
RRect tourCutout(Rect target, {double targetRadius = 16}) =>
    RRect.fromRectAndRadius(
      target.inflate(NuvoMotion.tourCutoutPad),
      Radius.circular(targetRadius + NuvoMotion.tourCutoutPad),
    );

enum TourBubbleSide { above, below }

class TourBubblePlacement {
  const TourBubblePlacement({
    required this.rect,
    required this.side,
    required this.tailX,
  });

  /// Where the bubble sits, in overlay coordinates.
  final Rect rect;
  final TourBubbleSide side;

  /// Tail tip x relative to the bubble's left edge.
  final double tailX;
}

/// Where the bubble goes: below the cutout when it fits, else above, else
/// on the roomier side; always clear of the cutout. Horizontally centered
/// on the cutout, kept inside [margin] of the screen edges.
TourBubblePlacement placeTourBubble({
  required Rect cutout,
  required Size screen,
  required Size bubble,
  EdgeInsets safe = EdgeInsets.zero,
  double gap = 14,
  double margin = 16,
  double tailInset = 28,
  TourBubbleSide? forceSide,
}) {
  final top = safe.top + margin;
  final bottom = screen.height - safe.bottom - margin;
  final roomBelow = bottom - (cutout.bottom + gap);
  final roomAbove = (cutout.top - gap) - top;
  final below = forceSide != null
      ? forceSide == TourBubbleSide.below
      : roomBelow >= bubble.height ||
            (roomAbove < bubble.height && roomBelow >= roomAbove);
  final y = below
      ? cutout.bottom + gap
      : math.max(top, cutout.top - gap - bubble.height);
  final maxLeft = math.max(margin, screen.width - margin - bubble.width);
  final x = (cutout.center.dx - bubble.width / 2).clamp(margin, maxLeft);
  final tail = (cutout.center.dx - x).clamp(
    tailInset,
    math.max(tailInset, bubble.width - tailInset),
  );
  return TourBubblePlacement(
    rect: Rect.fromLTWH(x.toDouble(), y, bubble.width, bubble.height),
    side: below ? TourBubbleSide.below : TourBubbleSide.above,
    tailX: tail.toDouble(),
  );
}

/// Whether [target] needs the auto-scroll: any part outside the band the
/// user can actually see (below the status bar, above the dock).
bool tourTargetOffscreen(
  Rect target, {
  required Size screen,
  required double top,
  required double bottom,
}) => target.top < top || target.bottom > screen.height - bottom;

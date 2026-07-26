import 'dart:math' as math;

class TrackViewGeometry {
  const TrackViewGeometry._();

  static double normalizeProgress({
    required num completedAmount,
    required num goal,
  }) {
    if (goal <= 0) return 0;
    return (completedAmount / goal).clamp(0.0, 1.0).toDouble();
  }

  static double worldXForProgress({
    required double normalizedProgress,
    required double worldWidth,
  }) {
    final edgePadding = horizontalEdgePadding(worldWidth: worldWidth);
    final drawableWidth = (worldWidth - edgePadding * 2).clamp(
      0.0,
      double.infinity,
    );
    return (edgePadding + normalizedProgress.clamp(0.0, 1.0) * drawableWidth)
        .toDouble();
  }

  static double horizontalEdgePadding({required double worldWidth}) {
    return (worldWidth * 0.263).clamp(44.0, 240.0).toDouble();
  }

  static double worldYForProgress({
    required double normalizedProgress,
    required double availableHeight,
  }) {
    final progress = normalizedProgress.clamp(0.0, 1.0);
    final centerY = availableHeight * 0.16;
    final radiusY = availableHeight * 0.68;
    return (centerY + math.sin(progress * math.pi) * radiusY)
        .clamp(availableHeight * 0.12, availableHeight * 0.84)
        .toDouble();
  }
}

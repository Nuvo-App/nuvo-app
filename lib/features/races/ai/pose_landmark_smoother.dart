import 'dart:math' as math;

import '../data/ai_motion_models.dart';

/// Stabilizes landmark coordinates without inventing landmarks during a
/// detector miss. Slow movement gets stronger smoothing; fast movement gets a
/// higher response so valid repetitions do not feel delayed.
class PoseLandmarkSmoother {
  PoseLandmarkSmoother({
    this.minimumAlpha = 0.24,
    this.maximumAlpha = 0.72,
    this.resetAfter = const Duration(milliseconds: 320),
  });

  final double minimumAlpha;
  final double maximumAlpha;
  final Duration resetAfter;

  Map<String, NuvoPosePoint> _previous = const {};
  DateTime? _previousAt;

  NuvoPoseFrame smooth(NuvoPoseFrame frame) {
    if (frame.points.isEmpty) {
      reset();
      return frame;
    }

    final previousAt = _previousAt;
    final previous = _previous;
    final elapsed = previousAt == null
        ? null
        : frame.createdAt.difference(previousAt);
    final shouldReset = elapsed == null || elapsed > resetAfter;
    final closeOrCropped = _isCloseOrCropped(frame);

    final output = <String, NuvoPosePoint>{};
    for (final entry in frame.points.entries) {
      final current = entry.value;
      final old = shouldReset ? null : previous[entry.key];
      if (old == null) {
        output[entry.key] = current;
        continue;
      }

      final speed =
          _distance(current, old) /
          math.max(
            (elapsed?.inMicroseconds ?? 1) / Duration.microsecondsPerSecond,
            0.001,
          );
      final motionResponse = (speed * 3.0).clamp(0.0, 1.0);
      final requestedAlpha =
          minimumAlpha + (maximumAlpha - minimumAlpha) * motionResponse;
      // Near-camera estimates can jump when a landmark is cropped or changes
      // scale. Do not mistake that detector instability for fast movement.
      final alpha = closeOrCropped
          ? math.min(requestedAlpha, 0.30)
          : requestedAlpha;
      output[entry.key] = NuvoPosePoint(
        x: _blend(old.x, current.x, alpha),
        y: _blend(old.y, current.y, alpha),
        z: _blend(old.z, current.z, alpha),
        likelihood: current.likelihood,
      );
    }

    _previous = output;
    _previousAt = frame.createdAt;
    return NuvoPoseFrame(
      points: output,
      imageWidth: frame.imageWidth,
      imageHeight: frame.imageHeight,
      createdAt: frame.createdAt,
    );
  }

  void reset() {
    _previous = const {};
    _previousAt = null;
  }

  static double _blend(double previous, double current, double alpha) =>
      previous + (current - previous) * alpha;

  static double _distance(NuvoPosePoint a, NuvoPosePoint b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  bool _isCloseOrCropped(NuvoPoseFrame frame) {
    const framingPoints = [
      'leftShoulder',
      'rightShoulder',
      'leftElbow',
      'rightElbow',
      'leftWrist',
      'rightWrist',
      'leftHip',
      'rightHip',
    ];
    final points = framingPoints
        .map(frame.point)
        .whereType<NuvoPosePoint>()
        .where((point) => point.likelihood >= 0.45)
        .toList(growable: false);
    if (points.length < 6) return false;

    final minX = points.map((point) => point.x).reduce(math.min);
    final maxX = points.map((point) => point.x).reduce(math.max);
    final minY = points.map((point) => point.y).reduce(math.min);
    final maxY = points.map((point) => point.y).reduce(math.max);
    return minX < 0.025 ||
        maxX > 0.975 ||
        minY < 0.025 ||
        maxY > 0.975 ||
        maxX - minX > 0.90 ||
        maxY - minY > 0.90;
  }
}

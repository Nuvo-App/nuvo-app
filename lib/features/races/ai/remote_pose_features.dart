import 'dart:math' as math;

import '../data/ai_motion_models.dart';

/// Canonical derived-pose-feature math for remote verifier engines.
///
/// Every engine that needs an angle, an axis delta, or a normalized segment
/// ratio computes it here — implementations are never duplicated per engine.
/// All functions are pure, operate on normalized 2D landmark coordinates,
/// and FAIL CLOSED: missing landmarks, low-likelihood points, NaN/inf
/// inputs, and degenerate geometry (zero-length vectors) return null —
/// never a number that could accidentally satisfy a predicate.
class RemotePoseFeatures {
  const RemotePoseFeatures._();

  /// Minimum segment length in normalized units. Below this the landmark
  /// geometry is noise — an angle or ratio derived from it is meaningless.
  static const _epsilon = 1e-4;

  /// The interior angle at [b] between segments (b→a) and (b→c), in degrees
  /// 0..180. Null when any point is missing/low-likelihood or either segment
  /// is degenerate.
  static double? angle({
    required NuvoPosePoint? a,
    required NuvoPosePoint? b,
    required NuvoPosePoint? c,
    double minLikelihood = 0.35,
  }) {
    if (!_valid(a, minLikelihood) ||
        !_valid(b, minLikelihood) ||
        !_valid(c, minLikelihood)) {
      return null;
    }
    final ux = a!.x - b!.x;
    final uy = a.y - b.y;
    final vx = c!.x - b.x;
    final vy = c.y - b.y;
    final uLen = math.sqrt(ux * ux + uy * uy);
    final vLen = math.sqrt(vx * vx + vy * vy);
    if (uLen < _epsilon || vLen < _epsilon) return null;
    final dot = ux * vx + uy * vy;
    final cross = (ux * vy - uy * vx).abs();
    final degrees = math.atan2(cross, dot) * 180 / math.pi;
    return degrees.isFinite ? degrees : null;
  }

  /// `a.axis - b.axis` in normalized units. Positive means [a] is below
  /// [b] on the y axis (y grows downward in image space) or right on x.
  /// Null on any invalid input.
  static double? axisDelta({
    required NuvoPosePoint? a,
    required NuvoPosePoint? b,
    required bool isX,
    double minLikelihood = 0.35,
  }) {
    if (!_valid(a, minLikelihood) || !_valid(b, minLikelihood)) return null;
    final delta = isX ? a!.x - b!.x : a!.y - b!.y;
    return delta.isFinite ? delta : null;
  }

  /// `|a−b| / |refA−refB|` — a scale-invariant distance ratio. Null when the
  /// reference segment is degenerate (zero-length ratios are meaningless
  /// and must never satisfy a predicate).
  static double? segmentRatio({
    required NuvoPosePoint? a,
    required NuvoPosePoint? b,
    required NuvoPosePoint? refA,
    required NuvoPosePoint? refB,
    double minLikelihood = 0.35,
  }) {
    if (!_valid(a, minLikelihood) ||
        !_valid(b, minLikelihood) ||
        !_valid(refA, minLikelihood) ||
        !_valid(refB, minLikelihood)) {
      return null;
    }
    final rx = refA!.x - refB!.x;
    final ry = refA.y - refB.y;
    final refLen = math.sqrt(rx * rx + ry * ry);
    if (refLen < _epsilon) return null;
    final dx = a!.x - b!.x;
    final dy = a.y - b.y;
    final ratio = math.sqrt(dx * dx + dy * dy) / refLen;
    return ratio.isFinite ? ratio : null;
  }

  static bool _valid(NuvoPosePoint? p, double minLikelihood) =>
      p != null &&
      p.x.isFinite &&
      p.y.isFinite &&
      p.likelihood >= minLikelihood;
}

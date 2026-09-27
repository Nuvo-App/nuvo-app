import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Size/detail configuration for [NuvoRacePath]. Hero cards get the full
/// curved treatment; compact cards (featured race cards) get a lighter
/// version of the same curve; tiny list rows get a simplified, mostly
/// straight line so dense lists don't turn into a wall of little paintings.
enum NuvoRacePathVariant { hero, compact, mini }

/// A left-to-right race progress path whose SHAPE is unique per race but
/// stable across rebuilds — derived deterministically from [raceId], never
/// randomized per frame. The same race always renders the same path; a
/// different race renders a visibly different (but equally readable) one.
///
/// The actual progress marker and filled portion always correspond to
/// [progress] (0.0–1.0) measured along that race's own path — this is a real
/// progress indicator with a distinctive shape, not decoration layered over
/// a generic straight bar.
class NuvoRacePath extends StatelessWidget {
  const NuvoRacePath({
    super.key,
    required this.raceId,
    required this.progress,
    this.variant = NuvoRacePathVariant.hero,
    this.trackColor,
    this.progressColor,
    this.completedColor,
  });

  final String raceId;

  /// 0.0–1.0. Values outside this range are clamped.
  final double progress;
  final NuvoRacePathVariant variant;
  final Color? trackColor;
  final Color? progressColor;
  final Color? completedColor;

  double get _height => switch (variant) {
    NuvoRacePathVariant.hero => 42,
    NuvoRacePathVariant.compact => 30,
    NuvoRacePathVariant.mini => 16,
  };

  @override
  Widget build(BuildContext context) {
    final clamped = progress.clamp(0.0, 1.0);
    final seed = _seedFor(raceId);
    return Semantics(
      label: 'Race progress',
      value: '${(clamped * 100).round()}%',
      child: SizedBox(
        height: _height,
        width: double.infinity,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: clamped),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          builder: (context, animatedProgress, _) => CustomPaint(
            painter: _RacePathPainter(
              seed: seed,
              progress: animatedProgress,
              variant: variant,
              trackColor: trackColor ?? NuvoColors.trackBg,
              progressColor: progressColor ?? NuvoColors.blue,
              completedColor: completedColor ?? NuvoColors.success,
            ),
          ),
        ),
      ),
    );
  }
}

/// A stable 32-bit FNV-1a hash of [raceId]. Pure function of the input —
/// same race ID always produces the same seed, so the generated path never
/// jumps around on rebuild, only differs between distinct races.
int _seedFor(String raceId) {
  var hash = 0x811c9dc5;
  for (final unit in raceId.codeUnits) {
    hash = (hash ^ unit) & 0xFFFFFFFF;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}

class _RacePathPainter extends CustomPainter {
  const _RacePathPainter({
    required this.seed,
    required this.progress,
    required this.variant,
    required this.trackColor,
    required this.progressColor,
    required this.completedColor,
  });

  final int seed;
  final double progress;
  final NuvoRacePathVariant variant;
  final Color trackColor;
  final Color progressColor;
  final Color completedColor;

  /// Deterministic pseudo-random value in [0, 1) for a given [salt], derived
  /// purely from [seed] — no external randomness, no per-frame variance.
  double _rand(int salt) {
    final mixed = (seed ^ (salt * 0x9E3779B1)) & 0xFFFFFFFF;
    final scrambled = (mixed * 2654435761) & 0xFFFFFFFF;
    return (scrambled % 10000) / 10000.0;
  }

  Path _buildPath(Size size, double startX, double finishX, double baseY) {
    final span = finishX - startX;
    if (variant == NuvoRacePathVariant.mini || span < 40) {
      // Too small to bend meaningfully — stay a straight line rather than
      // overcomplicate a tiny list row.
      return Path()
        ..moveTo(startX, baseY)
        ..lineTo(finishX, baseY);
    }

    // Restrained, seed-derived variation: 1–2 gentle bends, a wave
    // direction, and an amplitude bounded to a fixed fraction of the
    // available height — enough to make every race recognizable without
    // ever producing an unreadable roller coaster.
    final usableHalfHeight = baseY * 0.72;
    final bendCount = 1 + (_rand(1) * 2).floor(); // 1 or 2
    final baseDirection = _rand(2) < 0.5 ? 1.0 : -1.0;
    final amplitude = usableHalfHeight * (0.55 + _rand(3) * 0.45);
    final segment = span / bendCount;

    final path = Path()..moveTo(startX, baseY);
    for (var i = 0; i < bendCount; i++) {
      final segStart = startX + segment * i;
      final segEnd = startX + segment * (i + 1);
      final segDirection = bendCount == 1
          ? baseDirection
          : (i.isEven ? baseDirection : -baseDirection);
      final bendY =
          baseY - segDirection * amplitude * (0.85 + _rand(4 + i) * 0.15);
      final c1x = segStart + segment * (0.30 + _rand(6 + i) * 0.12);
      final c2x = segStart + segment * (0.70 - _rand(7 + i) * 0.12);
      path.cubicTo(c1x, bendY, c2x, bendY, segEnd, baseY);
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = switch (variant) {
      NuvoRacePathVariant.hero => 16.0,
      NuvoRacePathVariant.compact => 8.0,
      NuvoRacePathVariant.mini => 3.0,
    };
    final progressWidth = switch (variant) {
      NuvoRacePathVariant.hero => 10.0,
      NuvoRacePathVariant.compact => 5.0,
      NuvoRacePathVariant.mini => 3.0,
    };
    final flagReserve = switch (variant) {
      NuvoRacePathVariant.hero => 36.0,
      NuvoRacePathVariant.compact => 22.0,
      NuvoRacePathVariant.mini => 0.0,
    };
    final startX = strokeWidth / 2 + 2;
    final finishX = size.width - flagReserve;
    final baseY = size.height / 2;

    final path = _buildPath(size, startX, finishX, baseY);
    final metric = path.computeMetrics().first;

    final trackPaint = Paint()
      ..color = trackColor
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, trackPaint);

    final isDone = progress >= 1.0;
    final coveredLength = metric.length * progress;
    if (coveredLength > 0) {
      final progressPaint = Paint()
        ..color = isDone ? completedColor : progressColor
        ..strokeWidth = progressWidth
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawPath(metric.extractPath(0, coveredLength), progressPaint);
    }

    if (variant == NuvoRacePathVariant.mini) return;

    final tangent = metric.getTangentForOffset(
      coveredLength.clamp(0.0, metric.length),
    );
    final markerPosition = tangent?.position ?? Offset(startX, baseY);
    final markerColor = isDone ? completedColor : progressColor;
    final markerRadius = variant == NuvoRacePathVariant.hero
        ? (progress <= 0 ? 7.0 : 10.0)
        : (progress <= 0 ? 4.5 : 6.5);
    canvas.drawCircle(markerPosition, markerRadius, Paint()..color = markerColor);
    canvas.drawCircle(
      markerPosition,
      markerRadius,
      Paint()
        ..color = NuvoColors.navy
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );

    // Finish flag at the path's actual endpoint.
    final flagX = finishX + (variant == NuvoRacePathVariant.hero ? 12 : 8);
    final poleHeight = variant == NuvoRacePathVariant.hero ? 28.0 : 16.0;
    final poleTop = baseY - poleHeight * 0.6;
    canvas.drawRect(
      Rect.fromLTWH(flagX, poleTop, 2, poleHeight),
      Paint()..color = NuvoColors.border,
    );
    final flagSize = variant == NuvoRacePathVariant.hero ? 15.0 : 9.0;
    canvas.drawPath(
      Path()
        ..moveTo(flagX + 2, poleTop)
        ..lineTo(flagX + 2 + flagSize, poleTop + poleHeight * 0.22)
        ..lineTo(flagX + 2, poleTop + poleHeight * 0.44)
        ..close(),
      Paint()..color = NuvoColors.navy,
    );
  }

  @override
  bool shouldRepaint(covariant _RacePathPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.seed != seed ||
      oldDelegate.variant != variant ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.progressColor != progressColor ||
      oldDelegate.completedColor != completedColor;
}

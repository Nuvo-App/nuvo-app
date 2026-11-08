import 'package:flutter/material.dart';

import '../../../../core/v13/v13.dart';
import '../../data/progression_models.dart';
import '../widgets/nuvo_badges.dart';

/// Display label for a stored favorite-movement key. Unknown keys fall back
/// to a prettified version of the key — the value is server-trusted text,
/// never a route or a URL.
String v13MovementLabel(String key) => switch (key) {
  'pushups' || 'push_ups' || 'push-ups' => 'Pushups',
  'squats' => 'Squats',
  'jumping_jacks' || 'jumping-jacks' => 'Jumping jacks',
  'lunges' => 'Lunges',
  'plank' || 'plank_hold' || 'plank-hold' => 'Plank',
  _ =>
    key
        .replaceAll(RegExp(r'[-_]'), ' ')
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' '),
};

/// Achievement accent — category-driven, palette-only. Milestone/legendary
/// rarity and winning categories earn gold; locked tiles never color-fill.
Color v13BadgeAccent(NuvoBadge badge) {
  if (badge.isMilestone) return V13.gold;
  return switch (badge.category) {
    'winning' => V13.gold,
    'racing' => V13.coral,
    'performance' => V13.mint,
    'creation' || 'motion' => V13.lilac,
    'social' || 'variety' => V13.sun,
    _ => V13.sky,
  };
}

/// The shared achievement tile — a navy-outlined squircle with the badge
/// glyph. Earned tiles color-fill with a hard shadow; locked tiles stay
/// dashed with a faint glyph and an optional progress track.
class V13BadgeTile extends StatelessWidget {
  const V13BadgeTile({
    super.key,
    required this.icon,
    required this.accent,
    required this.earned,
    this.progress = 0,
    this.size = 64,
    this.onTap,
    this.semanticLabel,
  });

  /// Convenience for a catalog badge.
  V13BadgeTile.badge(
    NuvoBadge badge, {
    super.key,
    this.size = 64,
    this.onTap,
    this.semanticLabel,
  }) : icon = nuvoBadgeIconFor(badge.iconKey),
       accent = v13BadgeAccent(badge),
       earned = badge.unlocked,
       progress = badge.goalProgress;

  final IconData icon;
  final Color accent;
  final bool earned;

  /// 0..1 fill under a locked tile — only drawn when > 0.
  final double progress;
  final double size;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final radius = size * 0.28;
    final tile = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: earned ? accent : V13.card,
        borderRadius: BorderRadius.circular(radius),
        border: earned ? Border.all(color: V13.navy, width: V13.outline) : null,
        boxShadow: earned ? V13.shadow3 : null,
      ),
      child: earned
          ? Icon(icon, size: size * 0.46, color: V13.navy)
          : _DashedBadge(
              radius: radius,
              child: Icon(icon, size: size * 0.42, color: V13.muted),
            ),
    );

    Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        tile,
        if (!earned && progress > 0) ...[
          const SizedBox(height: V13.gapXs),
          SizedBox(
            width: size,
            child: V13ProgressBar(value: progress, height: 5),
          ),
        ],
      ],
    );
    if (onTap != null) {
      content = V13Pressable(
        onTap: onTap,
        pressDepth: 2,
        borderRadius: BorderRadius.circular(radius),
        semanticLabel: semanticLabel,
        child: content,
      );
    }
    return content;
  }
}

/// Circular dashed outline painter — the "locked" look shared by locked
/// achievements, locked friendship badges and empty featured slots.
class V13DashedBox extends StatelessWidget {
  const V13DashedBox({
    super.key,
    required this.child,
    this.radius = V13.radiusCard,
    this.padding = EdgeInsets.zero,
    this.size,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final double? size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(radius: radius),
      child: Container(
        width: size,
        height: size,
        padding: padding,
        child: child,
      ),
    );
  }
}

class _DashedBadge extends StatelessWidget {
  const _DashedBadge({required this.radius, required this.child});

  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(radius: radius),
      child: Center(child: child),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.radius});

  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = V13.muted
      ..style = PaintingStyle.stroke
      ..strokeWidth = V13.outline;
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    ).deflate(V13.outline / 2);
    final path = Path()..addRRect(rect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      const dash = 5.0;
      const gap = 4.0;
      while (distance < metric.length) {
        final end = (distance + dash).clamp(0.0, metric.length).toDouble();
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.radius != radius;
}

/// Races / Wins / Friends — the shared profile counter strip.
class V13ProfileCounts extends StatelessWidget {
  const V13ProfileCounts({super.key, this.races, this.wins, this.friends});

  final int? races;
  final int? wins;
  final int? friends;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (value, label) in [
          (races, 'Races'),
          (wins, 'Wins'),
          (friends, 'Friends'),
        ]) ...[
          Expanded(
            child: Column(
              children: [
                Text(value == null ? '–' : '$value', style: V13.numberSm),
                Text(label, style: V13.caption),
              ],
            ),
          ),
          if (label != 'Friends')
            Container(width: 2, height: 26, color: V13.divider),
        ],
      ],
    );
  }
}

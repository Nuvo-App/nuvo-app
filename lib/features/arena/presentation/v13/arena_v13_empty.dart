import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:nuvo/core/motion/motion.dart';
import 'package:nuvo/core/v13/v13.dart';
import 'package:nuvo/features/profile/data/progression_models.dart';
import 'package:nuvo/features/profile/presentation/widgets/nuvo_badges.dart';

/// Activity map for an account with no proofs yet: a faded 18x7 grid whose
/// first square (today) is outlined blue.
class ArenaActivityEmpty extends StatelessWidget {
  const ArenaActivityEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Today starts your map', style: V13.bodyStrong),
        Text('Every proof you submit lights up a square.', style: V13.caption),
        const SizedBox(height: V13.gapMd),
        const V13HeatMap(
          counts: {},
          weeks: 18,
          showLegend: false,
          faded: true,
          highlightToday: true,
          semanticLabel: 'Empty activity map. Today starts your map.',
        ),
      ],
    );
  }
}

/// "How many to go" line for a locked achievement, or null when the badge
/// carries no countable target.
String? arenaToGoLabel(NuvoBadge badge) {
  final t = badge.threshold;
  if (t == null || t <= 0) return null;
  final rem = t - badge.progressValue;
  if (rem <= 0) return null;
  final key = badge.statKey ?? '';
  if (key.contains('proof') || key.contains('progress')) {
    return rem == 1 ? '1 proof to go' : '$rem proofs to go';
  }
  return '$rem to go';
}

/// Achievements with nothing earned yet: locked tiles with a progress arc,
/// the "0 of N" count, and the closest one called out and tappable.
class ArenaAchievementsEmpty extends StatelessWidget {
  const ArenaAchievementsEmpty({
    super.key,
    required this.progression,
    required this.tiles,
    required this.onOpenBadges,
  });

  final NuvoProgression progression;
  final List<NuvoBadge> tiles;
  final VoidCallback onOpenBadges;

  NuvoBadge get _closest {
    final next = progression.nextAchievement;
    if (next != null && arenaToGoLabel(next) != null) {
      for (final t in tiles) {
        if (t.unlockId == next.unlockId) return t;
      }
    }
    var best = tiles.first;
    for (final t in tiles) {
      if (t.goalProgress > best.goalProgress) best = t;
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final closest = _closest;
    final toGo = arenaToGoLabel(closest);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        V13SectionHeader(
          title: 'Achievements',
          trailingLabel: '0 of ${progression.achievementsTotal}',
          onTrailingTap: onOpenBadges,
        ),
        const SizedBox(height: V13.gapLg),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) const SizedBox(width: V13.gapMd),
              Expanded(
                child: _LockedTile(
                  badge: tiles[i],
                  highlight: tiles[i].unlockId == closest.unlockId,
                  onTap: onOpenBadges,
                ),
              ),
            ],
          ],
        ),
        if (toGo != null) ...[
          const SizedBox(height: V13.gapLg),
          NuvoPressable(
            onTap: onOpenBadges,
            semanticLabel: '${closest.name}, $toGo',
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: V13.gapMd + 2,
                vertical: V13.gapMd,
              ),
              decoration: BoxDecoration(
                color: V13.blue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(V13.radiusButton),
                border: Border.all(color: V13.blue, width: V13.outline),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${closest.name} · $toGo',
                      style: V13.bodyStrong.copyWith(color: V13.navy),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: V13.blue,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _LockedTile extends StatelessWidget {
  const _LockedTile({
    required this.badge,
    required this.highlight,
    required this.onTap,
  });

  final NuvoBadge badge;
  final bool highlight;
  final VoidCallback onTap;

  static const double _size = 56;
  static const double _ring = 66;

  @override
  Widget build(BuildContext context) {
    Widget art = SizedBox.square(
      dimension: _ring,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _ArcPainter(
                progress: badge.goalProgress,
                active: highlight,
              ),
            ),
          ),
          Container(
            width: _size - 6,
            height: _size - 6,
            decoration: BoxDecoration(
              color: V13.card,
              borderRadius: BorderRadius.circular(V13.radiusTileLg),
              border: Border.all(color: V13.navy, width: V13.outline),
              boxShadow: V13.shadow3,
            ),
            child: Icon(
              nuvoBadgeIconFor(badge.iconKey),
              size: 24,
              color: V13.navy.withValues(alpha: 0.5),
            ),
          ),
          Positioned(
            right: 2,
            bottom: 2,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: V13.sun,
                border: Border.all(color: V13.navy, width: V13.outline),
              ),
              child: const Icon(Icons.lock_rounded, size: 11, color: V13.navy),
            ),
          ),
        ],
      ),
    );
    if (highlight) art = NuvoFloat(child: art);
    return V13Pressable(
      onTap: onTap,
      semanticLabel: '${badge.name}, locked',
      child: Column(
        children: [
          SizedBox(
            height: _ring + 6,
            child: Center(child: art),
          ),
          const SizedBox(height: V13.gapXs),
          Text(
            badge.name,
            style: V13.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  const _ArcPainter({required this.progress, required this.active});

  final double progress;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 4.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = active ? V13.blue.withValues(alpha: 0.25) : V13.divider;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect,
        const Radius.circular(V13.radiusTileLg + 4),
      ),
      track,
    );
    if (progress <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = V13.blue;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          rect,
          const Radius.circular(V13.radiusTileLg + 4),
        ),
      );
    for (final m in path.computeMetrics()) {
      canvas.drawPath(m.extractPath(0, m.length * math.min(progress, 1)), arc);
    }
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.progress != progress || old.active != active;
}

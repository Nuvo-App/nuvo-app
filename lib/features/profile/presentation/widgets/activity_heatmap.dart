import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../application/activity_controller.dart';

/// Shade for a day's verified-proof count: 0 = none, 1..4 = light..dark.
int heatLevel(int proofs) {
  if (proofs <= 0) return 0;
  if (proofs == 1) return 1;
  if (proofs <= 3) return 2;
  if (proofs <= 6) return 3;
  return 4;
}

String _key(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The grid's days, oldest first, whole weeks (Mon-Sun columns) ending in the
/// week that contains [today]. Cells after [today] are null.
List<DateTime?> heatmapDays(DateTime today, {int weeks = 20}) {
  final t = DateTime(today.year, today.month, today.day);
  final monday = t.subtract(Duration(days: t.weekday - 1));
  final start = monday.subtract(Duration(days: 7 * (weeks - 1)));
  return [
    for (var i = 0; i < weeks * 7; i++)
      () {
        final d = DateTime(start.year, start.month, start.day + i);
        return d.isAfter(t) ? null : d;
      }(),
  ];
}

/// Profile heat map — verified proofs per day over the last 20 weeks.
/// Hidden if the load fails; never shows invented data. While loading it
/// holds its place so the first viewport doesn't jump.
///
/// [minHeight] is the room the Profile's first viewport leaves for this
/// section; the card absorbs it (see [ActivityHeatmap]).
class ActivityHeatmapSection extends ConsumerWidget {
  const ActivityHeatmapSection({super.key, this.today, this.minHeight = 0});

  /// Test hook.
  final DateTime? today;
  final double minHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(profileActivityProvider);
    return data.when(
      data: (counts) =>
          ActivityHeatmap(counts: counts, today: today, minHeight: minHeight),
      loading: () => SizedBox(height: minHeight),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

/// Dark-mode fill for heat level 1..4 — the lifted accent blended over the
/// card with alpha steps wide enough to tell neighbouring levels apart.
@visibleForTesting
Color heatmapDarkLevelColor(NuvoThemeColors c, int level) =>
    c.accent.withValues(alpha: (0.40 + 0.20 * (level - 1)).clamp(0.0, 1.0));

/// The heat map card. Cells are square-ish rounded tiles sized from the
/// available width (`clamp((width - gaps) / weeks, 4, 18)`). When the
/// Profile hands it a [minHeight], the cells grow taller than wide up to
/// [maxCellRatio] to use the room, and whatever is still left is spread
/// evenly between header, grid and the Less/More key — so the card never
/// looks stretched and the key always ends the card.
class ActivityHeatmap extends StatelessWidget {
  const ActivityHeatmap({
    super.key,
    required this.counts,
    this.today,
    this.minHeight = 0,
  });

  final Map<String, int> counts;
  final DateTime? today;

  /// Minimum height of the whole section, including its top gap.
  final double minHeight;

  static const int weeks = 20;
  static const double maxCellRatio = 1.3;
  static const double _topGap = 18;
  static const double _pad = 14;
  static const double _gap = 3;
  static const double _cellOutline = 1.25;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final days = heatmapDays(today ?? DateTime.now(), weeks: weeks);
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    final activeDays = counts.values.where((v) => v > 0).length;
    final scaler = MediaQuery.textScalerOf(context);

    final dark = Theme.of(context).brightness == Brightness.dark;
    // Dark: lifted accent over the card with wider alpha steps and a clearly
    // visible empty cell; light ramp is unchanged.
    Color shade(int level) => dark
        ? (level == 0
              ? c.inkMuted.withValues(alpha: 0.22)
              : heatmapDarkLevelColor(c, level))
        : (level == 0
              ? c.inkMuted.withValues(alpha: 0.12)
              : NuvoColors.blue.withValues(alpha: 0.25 + 0.2 * (level - 1)));

    // Conservative line-height estimates so the budget never overshoots.
    final headerH = scaler.scale(16) * 1.5;
    final keyH = math.max(10.0, scaler.scale(11) * 1.6);

    return Semantics(
      label:
          'Activity. $total verified proofs on $activeDays days in the last $weeks weeks.',
      child: Padding(
        padding: const EdgeInsets.only(top: _topGap),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: math.max(0, minHeight - _topGap),
          ),
          child: Container(
            padding: const EdgeInsets.all(_pad),
            decoration: BoxDecoration(
              // White card (no ice-blue plane) so the outlined tiles read as a
              // layer sitting on it.
              color: c.surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: c.border, width: 2),
              boxShadow: AppShadows.hardOffset(c.inkShadow),
            ),
            child: LayoutBuilder(
              builder: (context, box) {
                final cell = ((box.maxWidth - _gap * (weeks - 1)) / weeks)
                    .clamp(4.0, 18.0);
                // Height the grid may take: the section's room minus the
                // card padding, header, key and the two breathing gaps.
                final budget = minHeight -
                    _topGap -
                    _pad * 2 -
                    headerH -
                    keyH -
                    2 * 12;
                final cellH = ((budget - _gap * 6) / 7).clamp(
                  cell,
                  cell * maxCellRatio,
                );
                final radius = math.min(cell, cellH) * 0.28;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Activity',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: c.ink,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        Flexible(
                          child: Text(
                            '$total verified proofs',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(color: c.inkMuted),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (var w = 0; w < weeks; w++)
                          Column(
                            children: [
                              for (var d = 0; d < 7; d++)
                                Padding(
                                  padding: EdgeInsets.only(
                                    bottom: d < 6 ? _gap : 0,
                                  ),
                                  child: Container(
                                    width: cell,
                                    height: cellH,
                                    decoration: BoxDecoration(
                                      color: () {
                                        final day = days[w * 7 + d];
                                        if (day == null) {
                                          return Colors.transparent;
                                        }
                                        return shade(
                                          heatLevel(counts[_key(day)] ?? 0),
                                        );
                                      }(),
                                      borderRadius: BorderRadius.circular(
                                        radius,
                                      ),
                                      // A firm ink outline on every day tile —
                                      // thick enough to read at this size, thin
                                      // enough to stay a texture.
                                      border: days[w * 7 + d] == null
                                          ? null
                                          : Border.all(
                                              color: c.border,
                                              width: _cellOutline,
                                            ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Less',
                            style: Theme.of(
                              context,
                            ).textTheme.labelSmall?.copyWith(color: c.inkMuted),
                          ),
                          const SizedBox(width: 4),
                          for (var l = 0; l <= 4; l++)
                            Padding(
                              padding: const EdgeInsets.only(left: 3),
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: shade(l),
                                  borderRadius: BorderRadius.circular(3),
                                  border: Border.all(
                                    color: c.border,
                                    width: _cellOutline,
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(width: 4),
                          Text(
                            'More',
                            style: Theme.of(
                              context,
                            ).textTheme.labelSmall?.copyWith(color: c.inkMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

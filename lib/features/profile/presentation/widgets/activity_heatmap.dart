import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
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
/// Hidden while loading or if the load fails; never shows invented data.
class ActivityHeatmapSection extends ConsumerWidget {
  const ActivityHeatmapSection({super.key, this.today});

  /// Test hook.
  final DateTime? today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(profileActivityProvider);
    return data.maybeWhen(
      data: (counts) => ActivityHeatmap(counts: counts, today: today),
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class ActivityHeatmap extends StatelessWidget {
  const ActivityHeatmap({super.key, required this.counts, this.today});

  final Map<String, int> counts;
  final DateTime? today;

  static const int weeks = 20;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final days = heatmapDays(today ?? DateTime.now(), weeks: weeks);
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    final activeDays = counts.values.where((v) => v > 0).length;

    Color shade(int level) => level == 0
        ? c.inkMuted.withValues(alpha: 0.12)
        : NuvoColors.blue.withValues(alpha: 0.25 + 0.2 * (level - 1));

    return Semantics(
      label:
          'Activity. $total verified proofs on $activeDays days in the last $weeks weeks.',
      child: Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Activity',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: c.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '$total verified proofs',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: c.inkMuted),
                ),
              ],
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, box) {
                const gap = 3.0;
                final cell = ((box.maxWidth - gap * (weeks - 1)) / weeks).clamp(
                  4.0,
                  18.0,
                );
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (var w = 0; w < weeks; w++)
                      Column(
                        children: [
                          for (var d = 0; d < 7; d++)
                            Padding(
                              padding: EdgeInsets.only(bottom: d < 6 ? gap : 0),
                              child: Container(
                                width: cell,
                                height: cell,
                                decoration: BoxDecoration(
                                  color: () {
                                    final day = days[w * 7 + d];
                                    if (day == null) return Colors.transparent;
                                    return shade(
                                      heatLevel(counts[_key(day)] ?? 0),
                                    );
                                  }(),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
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
                        borderRadius: BorderRadius.circular(2),
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
          ],
        ),
      ),
    );
  }
}

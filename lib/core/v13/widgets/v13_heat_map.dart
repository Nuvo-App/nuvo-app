import 'package:flutter/material.dart';

import '../tokens.dart';

/// Activity heat map — [weeks] columns × 7 day rows of blue-intensity
/// squares, GitHub-style, ending at today. Counts come from
/// `Map<DateTime, int>` (any time component is stripped).
class V13HeatMap extends StatelessWidget {
  const V13HeatMap({
    super.key,
    required this.counts,
    this.weeks = 18,
    this.showLegend = true,
    this.semanticLabel,
    this.faded = false,
    this.highlightToday = false,
  });

  /// Proof counts keyed by day. Time-of-day is ignored.
  final Map<DateTime, int> counts;

  /// Columns of 7 days. Spec: 18.
  final int weeks;
  final bool showLegend;
  final String? semanticLabel;

  /// Lighter empty squares — the "your map starts here" empty state.
  final bool faded;

  /// Draws today's square outlined in blue.
  final bool highlightToday;

  static const double _gap = 4;
  static const List<double> _levels = [0.35, 0.55, 0.8, 1.0];

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    // Columns are Sunday-start weeks; the last column ends at today.
    final sinceSunday = today.weekday % 7;
    // Calendar arithmetic, not Duration: subtracting 24h blocks across a DST
    // change lands on 23:00/01:00 and no cell ever matches a midnight key.
    final start = DateTime(
      today.year,
      today.month,
      today.day - ((weeks - 1) * 7 + sinceSunday),
    );

    final normalized = <DateTime, int>{};
    var maxCount = 0;
    var totalProofs = 0;
    counts.forEach((raw, count) {
      if (count <= 0) return;
      final day = DateUtils.dateOnly(raw);
      normalized[day] = (normalized[day] ?? 0) + count;
      if (normalized[day]! > maxCount) maxCount = normalized[day]!;
      totalProofs += count;
    });

    final grid = LayoutBuilder(
      builder: (context, constraints) {
        final cell = ((constraints.maxWidth - _gap * (weeks - 1)) / weeks)
            .clamp(6.0, 16.0)
            .toDouble();
        return SizedBox(
          width: weeks * cell + _gap * (weeks - 1),
          height: 7 * cell + _gap * 6,
          child: Column(
            children: [
              for (var row = 0; row < 7; row++) ...[
                if (row > 0) const SizedBox(height: _gap),
                Row(
                  children: [
                    for (var col = 0; col < weeks; col++) ...[
                      if (col > 0) const SizedBox(width: _gap),
                      _cell(start, row, col, today, normalized, maxCount, cell),
                    ],
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );

    return Semantics(
      label: semanticLabel ?? 'Activity heat map, $totalProofs proofs',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          grid,
          if (showLegend) ...[
            const SizedBox(height: V13.gapSm),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Less', style: V13.caption),
                const SizedBox(width: 6),
                const _LegendCell(color: V13.divider),
                for (final a in _levels)
                  _LegendCell(color: V13.blue.withValues(alpha: a)),
                const SizedBox(width: 6),
                Text('More', style: V13.caption),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _cell(
    DateTime start,
    int row,
    int col,
    DateTime today,
    Map<DateTime, int> counts,
    int maxCount,
    double size,
  ) {
    final day = DateTime(start.year, start.month, start.day + col * 7 + row);
    if (day.isAfter(today)) {
      return SizedBox.square(dimension: size);
    }
    final count = counts[day] ?? 0;
    if (highlightToday && day == today) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: V13.card,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: V13.blue, width: 2),
        ),
      );
    }
    Color fill = faded ? V13.divider.withValues(alpha: 0.6) : V13.divider;
    if (count > 0 && maxCount > 0) {
      final level = ((count / maxCount) * _levels.length).ceil().clamp(
        1,
        _levels.length,
      );
      fill = V13.blue.withValues(alpha: _levels[level - 1]);
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

class _LegendCell extends StatelessWidget {
  const _LegendCell({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../tokens.dart';

/// One stat in a [V13StatTriple].
class V13Stat {
  const V13Stat({required this.label, required this.value});

  /// Rendered uppercased in the muted label style.
  final String label;
  final String value;
}

/// Three stats in a row split by vertical dividers — "RACING / WINS /
/// WIN RATE" on Arena, "Crew wins / Races / Crew streak" on crew pages.
class V13StatTriple extends StatelessWidget {
  const V13StatTriple({super.key, required this.stats});

  final List<V13Stat> stats;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < stats.length; i++) ...[
          if (i > 0)
            const ColoredBox(
              color: V13.divider,
              child: SizedBox(width: 2, height: 40),
            ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  stats[i].value,
                  style: V13.number,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  stats[i].label.toUpperCase(),
                  style: V13.label.copyWith(fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

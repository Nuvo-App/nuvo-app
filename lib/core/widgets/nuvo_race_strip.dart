import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text_styles.dart';
import 'pressable_scale.dart';

class NuvoRaceStripData {
  const NuvoRaceStripData({
    required this.id,
    required this.title,
    this.rank,
    this.progressLabel,
    this.progressPercent,
    this.urgent = false,
  });

  final String id;
  final String title;
  final int? rank;
  final String? progressLabel;
  final int? progressPercent;
  final bool urgent;
}

class NuvoRaceStripRail extends StatelessWidget {
  const NuvoRaceStripRail({
    super.key,
    required this.races,
    required this.selectedId,
    required this.onTap,
  });

  final List<NuvoRaceStripData> races;
  final String? selectedId;
  final ValueChanged<NuvoRaceStripData> onTap;

  @override
  Widget build(BuildContext context) {
    if (races.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 62,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: races.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final race = races[index];
          return NuvoRaceStrip(
            race: race,
            selected: race.id == selectedId,
            onTap: () => onTap(race),
          );
        },
      ),
    );
  }
}

class NuvoRaceStrip extends StatelessWidget {
  const NuvoRaceStrip({
    super.key,
    required this.race,
    required this.selected,
    required this.onTap,
  });

  final NuvoRaceStripData race;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final progress = (race.progressPercent ?? 0).clamp(0, 100) / 100;
    final meta = race.rank != null
        ? '#${race.rank}'
        : race.progressLabel ?? '${race.progressPercent ?? 0}%';

    return PressableScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: 168,
        height: 58,
        padding: const EdgeInsets.fromLTRB(13, 10, 13, 9),
        decoration: BoxDecoration(
          color: selected ? NuvoColors.navy : NuvoColors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: selected
                ? NuvoColors.navy
                : race.urgent
                ? NuvoColors.navy.withValues(alpha: 0.62)
                : NuvoColors.navy.withValues(alpha: 0.18),
            width: selected || race.urgent ? 1.5 : 1,
          ),
          boxShadow: selected || race.urgent ? AppShadows.selectedShadow : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    race.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.labelMedium.copyWith(
                      color: selected ? NuvoColors.white : NuvoColors.navy,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  meta,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: selected
                        ? NuvoColors.white.withValues(alpha: 0.78)
                        : NuvoColors.navy.withValues(alpha: 0.56),
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              ],
            ),
            const Spacer(),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                minHeight: 3,
                value: progress,
                backgroundColor: selected
                    ? NuvoColors.white.withValues(alpha: 0.16)
                    : NuvoColors.border,
                color: NuvoColors.blue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

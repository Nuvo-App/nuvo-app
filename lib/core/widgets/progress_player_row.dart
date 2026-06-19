import 'package:flutter/material.dart';

import '../../data/models/race.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'nuvo_progress_bar.dart';

class ProgressPlayerRow extends StatelessWidget {
  const ProgressPlayerRow({
    super.key,
    required this.player,
    this.highlight = false,
  });

  final RacePlayer player;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: highlight ? NuvoColors.softBlue : NuvoColors.lavenderRow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: highlight ? NuvoColors.blue : Colors.transparent,
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: highlight ? NuvoColors.blue : NuvoColors.navy,
            child: Text(
              player.initials,
              style: AppTextStyles.labelSmall.copyWith(
                color: NuvoColors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        player.name,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.labelLarge.copyWith(
                          color: NuvoColors.navy,
                        ),
                      ),
                    ),
                    Text(
                      '${player.progress}%',
                      style: AppTextStyles.labelMedium.copyWith(
                        color: NuvoColors.blue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                NuvoProgressBar(value: player.progress / 100, height: 6),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

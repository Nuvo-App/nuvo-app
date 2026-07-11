import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'nuvo_avatar.dart';

class NuvoLeaderboardEntry {
  const NuvoLeaderboardEntry({
    required this.id,
    required this.rank,
    required this.name,
    required this.value,
    required this.initials,
    this.photoUrl,
    this.isCurrentUser = false,
    this.isLeader = false,
  });

  final String id;
  final int rank;
  final String name;
  final String value;
  final String initials;
  final String? photoUrl;
  final bool isCurrentUser;
  final bool isLeader;
}

class NuvoLeaderboard extends StatelessWidget {
  const NuvoLeaderboard({
    super.key,
    required this.entries,
    this.emptyLabel = 'No leaderboard yet.',
    this.animateRows = false,
  });

  final List<NuvoLeaderboardEntry> entries;
  final String emptyLabel;
  final bool animateRows;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return SizedBox(
        height: 52,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            emptyLabel,
            style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
          ),
        ),
      );
    }

    final sorted = [...entries]..sort((a, b) => a.rank.compareTo(b.rank));
    return Column(
      children: [
        for (var i = 0; i < sorted.length; i++) ...[
          NuvoLeaderboardRow(entry: sorted[i]),
          if (i < sorted.length - 1)
            Divider(
              height: 1,
              thickness: 1,
              color: NuvoColors.border.withValues(alpha: 0.74),
            ),
        ],
      ],
    );
  }
}

class NuvoLeaderboardRow extends StatelessWidget {
  const NuvoLeaderboardRow({super.key, required this.entry});

  final NuvoLeaderboardEntry entry;

  @override
  Widget build(BuildContext context) {
    final role = entry.isCurrentUser
        ? NuvoCompetitorAvatarRole.currentUser
        : entry.isLeader
        ? NuvoCompetitorAvatarRole.leader
        : NuvoCompetitorAvatarRole.standard;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: entry.isCurrentUser ? NuvoColors.panel : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 3,
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: entry.isCurrentUser
                    ? NuvoColors.blue
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 9),
            SizedBox(
              width: 26,
              child: Text(
                '#${entry.rank}',
                textAlign: TextAlign.left,
                style: AppTextStyles.labelMedium.copyWith(
                  color: entry.isLeader && !entry.isCurrentUser
                      ? NuvoColors.gold
                      : NuvoColors.navy.withValues(alpha: 0.58),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: NuvoCompetitorAvatar(
                id: entry.id,
                initials: entry.initials,
                photoUrl: entry.photoUrl,
                size: 30,
                role: role,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: NuvoColors.navy,
                  fontWeight: entry.isCurrentUser
                      ? FontWeight.w800
                      : FontWeight.w600,
                  height: 1.1,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              entry.value,
              style: AppTextStyles.number(
                15,
                color: entry.isCurrentUser ? NuvoColors.blue : NuvoColors.navy,
                weight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

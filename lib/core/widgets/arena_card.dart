import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/race.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'nuvo_button.dart';
import 'nuvo_progress_bar.dart';
import 'pressable_scale.dart';
import 'progress_player_row.dart';

class StackedRaceCard extends StatelessWidget {
  const StackedRaceCard({
    super.key,
    required this.label,
    required this.title,
    required this.players,
    this.subtitle,
    this.note,
    this.ctaLabel,
    this.onCta,
    this.compact = false,
  });

  final String label;
  final String title;
  final String? subtitle;
  final String? note;
  final List<RacePlayer> players;
  final String? ctaLabel;
  final VoidCallback? onCta;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(compact ? 24 : 30);

    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 10),
      child: Stack(
        children: [
          Positioned.fill(
            top: 10,
            left: 10,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: NuvoColors.navy,
                borderRadius: radius,
              ),
            ),
          ),
          Positioned.fill(
            top: 5,
            left: 5,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: NuvoColors.softBlue,
                borderRadius: radius,
                border: Border.all(color: NuvoColors.border, width: 1.2),
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.all(compact ? 18 : 22),
            decoration: BoxDecoration(
              color: NuvoColors.white,
              borderRadius: radius,
              border: Border.all(
                color: NuvoColors.blue.withValues(alpha: 0.36),
                width: 1.4,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: AppTextStyles.brandLabel.copyWith(
                    color: NuvoColors.blue,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  style:
                      (compact
                              ? AppTextStyles.headlineMedium
                              : AppTextStyles.displayMedium)
                          .copyWith(color: NuvoColors.navy),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    subtitle!,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: NuvoColors.muted,
                    ),
                  ),
                ],
                if (note != null) ...[
                  const SizedBox(height: 10),
                  _InfoPill(label: note!),
                ],
                const SizedBox(height: 18),
                for (var i = 0; i < players.length; i++) ...[
                  ProgressPlayerRow(player: players[i], highlight: i == 0),
                  if (i != players.length - 1) const SizedBox(height: 9),
                ],
                if (ctaLabel != null) ...[
                  const SizedBox(height: 18),
                  NuvoPrimaryButton(
                    label: ctaLabel!,
                    icon: Icons.arrow_forward_rounded,
                    expand: true,
                    onPressed: onCta,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CompactRaceCard extends StatelessWidget {
  const CompactRaceCard({super.key, required this.race, this.onTap});

  final Race race;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final average =
        race.players.map((p) => p.progress).fold<int>(0, (sum, p) => sum + p) /
        race.players.length;

    return PressableScale(
      onTap: onTap ?? () => context.push('/race/${race.id}'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: NuvoColors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: NuvoColors.border),
          boxShadow: [
            BoxShadow(
              color: NuvoColors.navy2.withValues(alpha: 0.04),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    race.title,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.titleLarge,
                  ),
                ),
                _InfoPill(label: '${race.daysLeft}d'),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              race.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
            ),
            const SizedBox(height: 14),
            NuvoProgressBar(value: average / 100, height: 7),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final player in race.players.take(3))
                  Align(
                    widthFactor: 0.72,
                    child: CircleAvatar(
                      radius: 15,
                      backgroundColor: NuvoColors.blue,
                      child: Text(
                        player.initials,
                        style: AppTextStyles.labelSmall.copyWith(
                          color: NuvoColors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                const Spacer(),
                Text(
                  race.proof,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: NuvoColors.blue,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: NuvoColors.icyBlue,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: NuvoColors.border),
      ),
      child: Text(
        label,
        style: AppTextStyles.labelSmall.copyWith(
          color: NuvoColors.navy,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

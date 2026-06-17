import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/nuvo_card.dart';
import '../../../../core/widgets/nuvo_chip.dart';
import '../../../../core/widgets/nuvo_progress_bar.dart';
import '../../domain/models/challenge.dart';
import '../../domain/models/participant.dart';

/// Challenge feed card — clean, informative, consumer-grade.
class ChallengeCard extends StatelessWidget {
  const ChallengeCard({
    super.key,
    required this.challenge,
    this.onTap,
  });

  final Challenge challenge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final avgProgress = challenge.participants.isEmpty
        ? 0.0
        : challenge.participants
                .map((p) => p.progress)
                .reduce((a, b) => a + b) /
            challenge.participants.length /
            100;

    final hot = challenge.isHot;
    final borderColor =
        hot ? AppColors.warning.withValues(alpha: 0.22) : AppColors.border;

    return NuvoCard(
      onTap: onTap,
      borderColor: borderColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: category + days + hot badge
          Row(
            children: [
              NuvoChip(label: challenge.category.label),
              const SizedBox(width: 8),
              if (hot) _HotDot(),
              const Spacer(),
              Text(
                '${challenge.daysLeft}d left',
                style: AppTextStyles.labelSmall.copyWith(
                  color: challenge.daysLeft <= 3
                      ? AppColors.danger
                      : AppColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Title
          Text(
            challenge.title,
            style: AppTextStyles.titleLarge,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),

          // Description
          if (challenge.description != null) ...[
            const SizedBox(height: 5),
            Text(
              challenge.description!,
              style: AppTextStyles.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          const SizedBox(height: 16),

          // Progress
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Progress', style: AppTextStyles.labelSmall),
              Text(
                '${(avgProgress * 100).toInt()}%',
                style: AppTextStyles.labelSmall
                    .copyWith(color: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 6),
          NuvoProgressBar(value: avgProgress),

          const SizedBox(height: 16),

          // Bottom row: avatar stack + count + prize
          Row(
            children: [
              _AvatarStack(participants: challenge.participants),
              const SizedBox(width: 8),
              Text(
                '${challenge.participants.length} competing',
                style: AppTextStyles.labelSmall,
              ),
              const Spacer(),
              _PrizePill(challenge: challenge),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hot indicator dot
// ---------------------------------------------------------------------------

class _HotDot extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        gradient: AppGradients.hot,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_fire_department_rounded,
              size: 11, color: Colors.white),
          const SizedBox(width: 3),
          Text(
            'HOT',
            style: AppTextStyles.labelSmall.copyWith(
              color: Colors.white,
              fontSize: 9,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Avatar stack (capped at 4 + overflow)
// ---------------------------------------------------------------------------

class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.participants});
  final List<Participant> participants;

  static const _visible = 4;
  static const _size = 24.0;
  static const _overlap = 8.0;

  @override
  Widget build(BuildContext context) {
    final shown = participants.take(_visible).toList();
    final overflow = participants.length - shown.length;
    final total = shown.length + (overflow > 0 ? 1 : 0);
    final width =
        total * (_size - _overlap) + _overlap;

    return SizedBox(
      width: width,
      height: _size,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * (_size - _overlap),
              child: _Avatar(participant: shown[i]),
            ),
          if (overflow > 0)
            Positioned(
              left: shown.length * (_size - _overlap),
              child: _OverflowBubble(count: overflow),
            ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.participant});
  final Participant participant;

  @override
  Widget build(BuildContext context) {
    final initial = participant.username.isNotEmpty
        ? participant.username[0].toUpperCase()
        : '?';
    return Container(
      width: _AvatarStack._size,
      height: _AvatarStack._size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppGradients.brand,
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: AppTextStyles.labelSmall.copyWith(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _OverflowBubble extends StatelessWidget {
  const _OverflowBubble({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _AvatarStack._size,
      height: _AvatarStack._size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surfaceElevated,
        border: Border.all(color: AppColors.border),
      ),
      alignment: Alignment.center,
      child: Text(
        '+$count',
        style:
            AppTextStyles.labelSmall.copyWith(fontSize: 9, color: AppColors.textSecondary),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Prize pill
// ---------------------------------------------------------------------------

class _PrizePill extends StatelessWidget {
  const _PrizePill({required this.challenge});
  final Challenge challenge;

  @override
  Widget build(BuildContext context) {
    final isUsd = challenge.prizeType == PrizeType.usd;
    final label = isUsd
        ? Formatters.money(challenge.prizePool)
        : '${challenge.participants.length * 25} Glory';
    final color = isUsd ? AppColors.mint : AppColors.dreamPurple;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isUsd
                ? Icons.attach_money_rounded
                : Icons.emoji_events_rounded,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTextStyles.labelMedium.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

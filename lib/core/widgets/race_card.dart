import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/formatters.dart';
import 'animations.dart';
import 'nuvo_card.dart';
import '../../features/challenges/domain/models/challenge.dart';
import '../../features/challenges/domain/models/participant.dart';

/// Primary race feed card — white, no HOT badge, no emojis.
class RaceCard extends StatelessWidget {
  const RaceCard({
    super.key,
    required this.challenge,
    this.onLogProgress,
    this.onTap,
  });

  final Challenge challenge;
  final VoidCallback? onLogProgress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final sorted = [...challenge.participants]
      ..sort((a, b) => b.progress.compareTo(a.progress));
    final leader = sorted.isNotEmpty ? sorted.first : null;
    final you = challenge.participants.isNotEmpty
        ? challenge.participants.first
        : null;
    final yourRank = you == null
        ? 1
        : sorted.indexWhere((p) => p.id == you.id) + 1;

    final avgProgress = challenge.participants.isEmpty
        ? 0.0
        : challenge.participants
                .map((p) => p.progress)
                .reduce((a, b) => a + b) /
            challenge.participants.length /
            100;

    return NuvoCard(
      onTap: onTap ?? onLogProgress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: category chip + days pill
          Row(
            children: [
              _CategoryPill(label: challenge.category.label),
              const Spacer(),
              _DaysPill(daysLeft: challenge.daysLeft),
            ],
          ),
          const SizedBox(height: 12),

          // Title
          Text(
            challenge.title,
            style: AppTextStyles.titleLarge,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),

          // Rank / leader callout
          if (leader != null) ...[
            const SizedBox(height: 6),
            _RankRow(
              yourRank: yourRank,
              leader: leader,
              you: you,
            ),
          ],

          const SizedBox(height: 14),

          // Progress bar — animates 0 → value on first render
          Row(
            children: [
              Text('Progress', style: AppTextStyles.labelSmall),
              const Spacer(),
              Text(
                '${(avgProgress * 100).toInt()}%',
                style: AppTextStyles.labelSmall.copyWith(
                    color: NuvoColors.blue),
              ),
            ],
          ),
          const SizedBox(height: 6),
          AnimatedProgressBar(value: avgProgress),

          const SizedBox(height: 14),

          // Bottom row: avatars + proof tag + stakes + log button
          Row(
            children: [
              _AvatarRow(participants: challenge.participants),
              const SizedBox(width: 8),
              _ProofTag(category: challenge.category),
              const Spacer(),
              _StakesPill(challenge: challenge),
            ],
          ),

          if (onLogProgress != null) ...[
            const SizedBox(height: 14),
            _LogProgressButton(onPressed: onLogProgress!),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _CategoryPill extends StatelessWidget {
  const _CategoryPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: NuvoColors.sectionBlue,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: NuvoColors.border),
      ),
      child: Text(
        label,
        style: AppTextStyles.labelSmall.copyWith(color: NuvoColors.blue),
      ),
    );
  }
}

class _DaysPill extends StatelessWidget {
  const _DaysPill({required this.daysLeft});
  final int daysLeft;

  @override
  Widget build(BuildContext context) {
    final urgent = daysLeft <= 3;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: urgent
            ? AppColors.danger.withValues(alpha: 0.08)
            : NuvoColors.bluePale,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: urgent
              ? AppColors.danger.withValues(alpha: 0.25)
              : NuvoColors.border,
        ),
      ),
      child: Text(
        daysLeft == 0 ? 'Ends today' : '${daysLeft}d left',
        style: AppTextStyles.labelSmall.copyWith(
          color: urgent ? AppColors.danger : NuvoColors.blue,
        ),
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.yourRank,
    required this.leader,
    required this.you,
  });
  final int yourRank;
  final Participant leader;
  final Participant? you;

  @override
  Widget build(BuildContext context) {
    final isLeading = you != null && you!.id == leader.id;
    final label = isLeading
        ? 'You are leading'
        : 'You are #$yourRank · ${leader.username} leads by '
            '${leader.progress - (you?.progress ?? 0)}%';

    return Row(
      children: [
        Icon(
          isLeading
              ? Icons.emoji_events_rounded
              : Icons.arrow_upward_rounded,
          size: 13,
          color: isLeading ? NuvoColors.mint : NuvoColors.muted,
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _AvatarRow extends StatelessWidget {
  const _AvatarRow({required this.participants});
  final List<Participant> participants;

  static const _max = 4;
  static const _size = 22.0;
  static const _overlap = 7.0;

  @override
  Widget build(BuildContext context) {
    final shown = participants.take(_max).toList();
    final overflow = participants.length - shown.length;
    final total = shown.length + (overflow > 0 ? 1 : 0);
    final width = total * (_size - _overlap) + _overlap;

    return SizedBox(
      width: width,
      height: _size,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * (_size - _overlap),
              child: _MiniAvatar(
                  initial: shown[i].username.isNotEmpty
                      ? shown[i].username[0].toUpperCase()
                      : '?'),
            ),
          if (overflow > 0)
            Positioned(
              left: shown.length * (_size - _overlap),
              child: _OverflowDot(count: overflow),
            ),
        ],
      ),
    );
  }
}

class _MiniAvatar extends StatelessWidget {
  const _MiniAvatar({required this.initial});
  final String initial;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _AvatarRow._size,
      height: _AvatarRow._size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: NuvoColors.blue,
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
            fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white),
      ),
    );
  }
}

class _OverflowDot extends StatelessWidget {
  const _OverflowDot({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _AvatarRow._size,
      height: _AvatarRow._size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: NuvoColors.sectionBlue,
        border: Border.all(color: NuvoColors.border),
      ),
      alignment: Alignment.center,
      child: Text(
        '+$count',
        style: const TextStyle(
            fontSize: 8, fontWeight: FontWeight.w600, color: NuvoColors.muted),
      ),
    );
  }
}

class _ProofTag extends StatelessWidget {
  const _ProofTag({required this.category});
  final ChallengeCategory category;

  String get _label => switch (category) {
        ChallengeCategory.fitness => 'Wearable',
        ChallengeCategory.learning => 'AI check-in',
        ChallengeCategory.habits => 'Peer judged',
        ChallengeCategory.custom => 'Self report',
      };

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.verified_rounded, size: 12, color: NuvoColors.muted),
        const SizedBox(width: 4),
        Text(_label, style: AppTextStyles.labelSmall),
      ],
    );
  }
}

class _StakesPill extends StatelessWidget {
  const _StakesPill({required this.challenge});
  final Challenge challenge;

  @override
  Widget build(BuildContext context) {
    final isUsd =
        challenge.prizeType == PrizeType.usd && challenge.prizePool > 0;
    final label = isUsd
        ? Formatters.money(challenge.prizePool)
        : 'Bragging rights';
    final color = isUsd ? NuvoColors.mint : NuvoColors.muted;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                : Icons.workspace_premium_rounded,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _LogProgressButton extends StatelessWidget {
  const _LogProgressButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: NuvoColors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: NuvoColors.blue),
        ),
        alignment: Alignment.center,
        child: Text(
          'Log progress',
          style: AppTextStyles.labelMedium.copyWith(color: NuvoColors.blue),
        ),
      ),
    );
  }
}

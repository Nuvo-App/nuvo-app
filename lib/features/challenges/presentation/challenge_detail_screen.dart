import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/dream_background.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_card.dart';
import '../../../core/widgets/nuvo_chip.dart';
import '../../../core/widgets/nuvo_progress_bar.dart';
import '../application/challenge_providers.dart';
import '../domain/models/challenge.dart';
import '../domain/models/participant.dart';

/// Standalone screen (outside shell) — has its own Scaffold + back button.
class ChallengeDetailScreen extends ConsumerWidget {
  const ChallengeDetailScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final challengeAsync = ref.watch(challengeByIdProvider(id));

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: GestureDetector(
          onTap: () => context.go('/arena'),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border),
            ),
            child: const Icon(
              Icons.arrow_back_rounded,
              color: AppColors.textPrimary,
              size: 20,
            ),
          ),
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DreamBackground(),
          challengeAsync.when(
            data: (challenge) => _DetailBody(challenge: challenge),
            loading: () => const Center(
              child: CircularProgressIndicator(
                  color: AppColors.primary, strokeWidth: 2),
            ),
            error: (e, _) => Center(
              child: Text(
                'Could not load challenge.',
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.challenge});
  final Challenge challenge;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top + kToolbarHeight;

    return ListView(
      padding: EdgeInsets.fromLTRB(20, topPad + 8, 20, 40),
      children: [
        // Category + days
        Row(
          children: [
            NuvoChip(label: challenge.category.label),
            const Spacer(),
            Text(
              '${challenge.daysLeft}d remaining',
              style: AppTextStyles.labelSmall.copyWith(
                color: challenge.daysLeft <= 3
                    ? AppColors.danger
                    : AppColors.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Title
        Text(challenge.title, style: AppTextStyles.headlineLarge),

        if (challenge.description != null) ...[
          const SizedBox(height: 10),
          Text(
            challenge.description!,
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.textSecondary),
          ),
        ],

        const SizedBox(height: 24),

        // Stats row
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Prize Pool',
                value: challenge.prizeType == PrizeType.usd
                    ? '\$${challenge.prizePool.toStringAsFixed(0)}'
                    : '${challenge.participants.length * 25} Glory',
                color: challenge.prizeType == PrizeType.usd
                    ? AppColors.mint
                    : AppColors.dreamPurple,
                icon: challenge.prizeType == PrizeType.usd
                    ? Icons.attach_money_rounded
                    : Icons.emoji_events_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: 'Players',
                value: '${challenge.participants.length}',
                color: AppColors.primary,
                icon: Icons.people_rounded,
              ),
            ),
          ],
        ),

        const SizedBox(height: 28),

        // Leaderboard section
        Text(
          'Leaderboard',
          style: AppTextStyles.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          'Live rankings based on verified progress',
          style: AppTextStyles.bodySmall,
        ),
        const SizedBox(height: 14),

        NuvoCard(
          padding: const EdgeInsets.all(4),
          child: Column(
            children: [
              for (var i = 0; i < challenge.participants.length; i++)
                _LeaderboardRow(
                  rank: i + 1,
                  participant: challenge.participants[i],
                  isLast: i == challenge.participants.length - 1,
                ),
            ],
          ),
        ),

        const SizedBox(height: 28),

        // Actions
        NuvoPrimaryButton(
          label: 'Join Challenge',
          icon: Icons.bolt_rounded,
          expand: true,
          onPressed: () => context.go('/arena'),
        ),
        const SizedBox(height: 12),
        NuvoSecondaryButton(
          label: 'Share with Crew',
          icon: Icons.share_rounded,
          expand: true,
          onPressed: () => context.go('/invite'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Stat card (prize / players)
// ---------------------------------------------------------------------------

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return NuvoCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: AppTextStyles.headlineMedium.copyWith(color: color),
          ),
          const SizedBox(height: 2),
          Text(label, style: AppTextStyles.labelSmall),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Leaderboard row
// ---------------------------------------------------------------------------

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({
    required this.rank,
    required this.participant,
    this.isLast = false,
  });
  final int rank;
  final Participant participant;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final isFirst = rank == 1;
    final rankColor = isFirst ? AppColors.mint : AppColors.textMuted;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Rank badge
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isFirst
                      ? AppColors.mint.withValues(alpha: 0.12)
                      : AppColors.surfaceElevated,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$rank',
                  style: AppTextStyles.labelMedium.copyWith(color: rankColor),
                ),
              ),
              const SizedBox(width: 12),

              // Avatar initial
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppGradients.brand,
                ),
                alignment: Alignment.center,
                child: Text(
                  participant.username.isNotEmpty
                      ? participant.username[0].toUpperCase()
                      : '?',
                  style: AppTextStyles.labelLarge
                      .copyWith(color: Colors.white, fontSize: 14),
                ),
              ),
              const SizedBox(width: 12),

              // Username + progress bar
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '@${participant.username}',
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    NuvoProgressBar(value: participant.progress / 100),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Progress percentage
              Text(
                '${participant.progress}%',
                style: AppTextStyles.labelMedium.copyWith(
                  color: isFirst ? AppColors.mint : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          const Divider(
            height: 1,
            indent: 16,
            endIndent: 16,
            color: AppColors.border,
          ),
      ],
    );
  }
}

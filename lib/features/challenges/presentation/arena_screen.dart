import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/animations.dart';
import '../../../core/widgets/race_card.dart';
import '../application/challenge_providers.dart';
import '../domain/models/challenge.dart';

/// Home screen — "Compete on anything. With anyone."
///
/// Rendered inside [MainShell] — no Scaffold here.
class ArenaScreen extends ConsumerWidget {
  const ArenaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final challengesAsync = ref.watch(activeChallengesProvider);

    return RefreshIndicator.adaptive(
      onRefresh: () async => ref.invalidate(activeChallengesProvider),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          const SliverToBoxAdapter(child: _HomeTopBar()),
          ...challengesAsync.when(
            data: (challenges) => _buildSlivers(context, challenges),
            loading: () => [
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: CircularProgressIndicator(
                    color: NuvoColors.blue,
                    strokeWidth: 2,
                  ),
                ),
              ),
            ],
            error: (_, _) => [
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Icon(
                    Icons.wifi_off_rounded,
                    size: 40,
                    color: NuvoColors.muted,
                  ),
                ),
              ),
            ],
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  List<Widget> _buildSlivers(
      BuildContext context, List<Challenge> challenges) {
    return [
      // Hero card — the most urgent active race
      if (challenges.isNotEmpty)
        SliverToBoxAdapter(
          child: FadeSlideIn(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: _NextMoveCard(challenge: challenges.first),
            ),
          ),
        ),

      // Empty state when no races at all
      if (challenges.isEmpty)
        SliverToBoxAdapter(
          child: FadeSlideIn(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.flag_outlined,
                    size: 48,
                    color: NuvoColors.border,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No active races',
                    style: AppTextStyles.titleLarge
                        .copyWith(color: NuvoColors.muted),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Start your first race to compete with your crew.',
                    style: AppTextStyles.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),

      // Quick action pills
      const SliverToBoxAdapter(child: _QuickActions()),

      // Secondary race cards
      if (challenges.length > 1)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
            child: Text('Active races', style: AppTextStyles.titleMedium),
          ),
        ),
      if (challenges.length > 1)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          sliver: SliverList.separated(
            itemCount: challenges.length - 1,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) => FadeSlideIn(
              delay: Duration(milliseconds: 80 + 60 * i),
              child: PressableScale(
                child: RaceCard(
                  challenge: challenges[i + 1],
                  onTap: () =>
                      context.go('/challenge/${challenges[i + 1].id}'),
                  onLogProgress: () =>
                      context.go('/challenge/${challenges[i + 1].id}'),
                ),
              ),
            ),
          ),
        ),

      // Crew activity feed
      const SliverToBoxAdapter(child: _CrewActivitySection()),
    ];
  }
}

// ---------------------------------------------------------------------------
// Home top bar — personal greeting, no logo
// ---------------------------------------------------------------------------

class _HomeTopBar extends StatelessWidget {
  const _HomeTopBar();

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting =
        hour < 12 ? 'Morning' : hour < 17 ? 'Afternoon' : 'Evening';

    return Container(
      color: NuvoColors.white,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$greeting, Akshay',
                style: AppTextStyles.headlineMedium,
              ),
              const SizedBox(height: 2),
              Text(
                'Ready to make a move?',
                style: AppTextStyles.bodySmall,
              ),
            ],
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => GoRouter.of(context).go('/profile'),
            child: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: NuvoColors.blue,
              ),
              alignment: Alignment.center,
              child: Text(
                'AD',
                style: AppTextStyles.labelMedium
                    .copyWith(color: NuvoColors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Next Move hero card — first (most urgent) active race
// ---------------------------------------------------------------------------

class _NextMoveCard extends StatelessWidget {
  const _NextMoveCard({required this.challenge});
  final Challenge challenge;

  @override
  Widget build(BuildContext context) {
    final sorted = [...challenge.participants]
      ..sort((a, b) => b.progress.compareTo(a.progress));
    final you =
        challenge.participants.isNotEmpty ? challenge.participants.first : null;
    final leader = sorted.isNotEmpty ? sorted.first : null;
    final yourRank =
        you == null ? 1 : sorted.indexWhere((p) => p.id == you.id) + 1;
    final yourProgress = (you?.progress ?? 0) / 100.0;
    final isLeading =
        you != null && leader != null && you.id == leader.id;

    final daysLeft = challenge.daysLeft;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: NuvoColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: NuvoColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 20,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: NuvoColors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  'Your next move',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: NuvoColors.blue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: daysLeft <= 3
                      ? AppColors.danger.withValues(alpha: 0.08)
                      : NuvoColors.bluePale,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: daysLeft <= 3
                        ? AppColors.danger.withValues(alpha: 0.25)
                        : NuvoColors.border,
                  ),
                ),
                child: Text(
                  daysLeft == 0 ? 'Ends today' : '${daysLeft}d left',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: daysLeft <= 3 ? AppColors.danger : NuvoColors.blue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Title
          Text(
            challenge.title,
            style: AppTextStyles.headlineMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),

          // Rank line
          Row(
            children: [
              Icon(
                isLeading
                    ? Icons.emoji_events_rounded
                    : Icons.trending_up_rounded,
                size: 14,
                color: isLeading ? NuvoColors.mint : NuvoColors.blue,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  isLeading
                      ? "You're leading the pack"
                      : "You're #$yourRank · ${leader?.username ?? ''} leads",
                  style: AppTextStyles.bodySmall.copyWith(
                    color: isLeading ? NuvoColors.mint : NuvoColors.muted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Progress
          Row(
            children: [
              Text('Your progress', style: AppTextStyles.labelSmall),
              const Spacer(),
              Text(
                '${(yourProgress * 100).toInt()}%',
                style:
                    AppTextStyles.labelSmall.copyWith(color: NuvoColors.blue),
              ),
            ],
          ),
          const SizedBox(height: 6),
          AnimatedProgressBar(value: yourProgress, height: 8),
          const SizedBox(height: 16),

          // Avatars + CTA
          Row(
            children: [
              // Avatar strip
              if (challenge.participants.isNotEmpty)
                _SmallAvatarStrip(participants: challenge.participants),
              const Spacer(),
              GestureDetector(
                onTap: () => context.go('/challenge/${challenge.id}'),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: NuvoColors.blue,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Log progress',
                        style: AppTextStyles.labelMedium
                            .copyWith(color: NuvoColors.white),
                      ),
                      const SizedBox(width: 5),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        size: 14,
                        color: NuvoColors.white,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SmallAvatarStrip extends StatelessWidget {
  const _SmallAvatarStrip({required this.participants});
  final List<dynamic> participants;

  static const _size = 24.0;
  static const _overlap = 8.0;
  static const _max = 3;

  @override
  Widget build(BuildContext context) {
    final shown = participants.take(_max).toList();
    final total = shown.length;
    final width = total * (_size - _overlap) + _overlap;

    return SizedBox(
      width: width,
      height: _size,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * (_size - _overlap),
              child: Container(
                width: _size,
                height: _size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: NuvoColors.blue,
                  border: Border.all(color: NuvoColors.white, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text(
                  (shown[i].username as String).isNotEmpty
                      ? (shown[i].username as String)[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quick action pills
// ---------------------------------------------------------------------------

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    return FadeSlideIn(
      delay: const Duration(milliseconds: 120),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: Row(
          children: [
            _ActionPill(
              icon: Icons.flag_rounded,
              label: 'Start race',
              onTap: () => context.go('/create'),
            ),
            const SizedBox(width: 8),
            _ActionPill(
              icon: Icons.people_rounded,
              label: 'Add friends',
              onTap: () => context.go('/crew'),
            ),
            const SizedBox(width: 8),
            _ActionPill(
              icon: Icons.check_circle_outline_rounded,
              label: 'Submit proof',
              onTap: () => context.go('/verification'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: NuvoColors.sectionBlue,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: NuvoColors.border),
          ),
          child: Column(
            children: [
              Icon(icon, size: 20, color: NuvoColors.blue),
              const SizedBox(height: 5),
              Text(
                label,
                style: AppTextStyles.labelSmall
                    .copyWith(color: NuvoColors.blue),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Crew activity section (mock data)
// ---------------------------------------------------------------------------

class _CrewActivitySection extends StatelessWidget {
  const _CrewActivitySection();

  static const _activities = [
    (
      Icons.emoji_events_rounded,
      NuvoColors.mint,
      'Jordan passed you in "100 Pushups a Day"',
      '2h ago',
    ),
    (
      Icons.people_rounded,
      NuvoColors.blue,
      'Sam joined your "No Sugar — 21 Days" race',
      '5h ago',
    ),
    (
      Icons.check_circle_rounded,
      NuvoColors.blue,
      'Mika submitted proof for "Read 30 Min / Day"',
      '1d ago',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Crew activity', style: AppTextStyles.titleMedium),
          const SizedBox(height: 12),
          ..._activities.map(
            (a) => _ActivityTile(
              icon: a.$1,
              iconColor: a.$2,
              text: a.$3,
              time: a.$4,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({
    required this.icon,
    required this.iconColor,
    required this.text,
    required this.time,
  });
  final IconData icon;
  final Color iconColor;
  final String text;
  final String time;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: AppTextStyles.bodyMedium),
                const SizedBox(height: 2),
                Text(time, style: AppTextStyles.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

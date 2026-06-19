import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_error_state.dart';
import '../../../core/widgets/nuvo_shared_components.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../races/data/race_models.dart';
import '../../races/presentation/race_controller.dart';

class ArenaScreen extends ConsumerWidget {
  const ArenaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final raceState = ref.watch(raceControllerProvider);

    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    final firstName = user?.fullName?.split(' ').first ?? 'there';
    final initials = user?.avatarInitials ?? '?';

    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: RefreshIndicator(
        onRefresh: () => ref.read(raceControllerProvider.notifier).loadRaces(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
          children: [
            // ── Header ────────────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$greeting, $firstName',
                        style: AppTextStyles.headlineLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Ready to make a move?',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: NuvoColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                PressableScale(
                  onTap: () => _showNotificationsSheet(context),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: NuvoColors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: NuvoColors.border),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x1207152B),
                          blurRadius: 0,
                          offset: Offset(2, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.notifications_none_rounded,
                      color: NuvoColors.navy,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: NuvoColors.navy,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initials,
                    style: AppTextStyles.labelMedium.copyWith(
                      color: NuvoColors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 22),

            // ── Featured race or empty state ─────────────────────────────────
            if (raceState.loading && raceState.races.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (raceState.error != null && raceState.races.isEmpty)
              NuvoErrorState(
                message: raceState.error!,
                onRetry: () =>
                    ref.read(raceControllerProvider.notifier).loadRaces(),
              )
            else if (raceState.races.isNotEmpty)
              _FeaturedRaceCard(race: raceState.races.first, userId: user?.id)
            else
              _EmptyState(onStart: () => context.push('/races/new')),

            const SizedBox(height: 20),

            // ── Quick actions ────────────────────────────────────────────────
            const NuvoSectionHeader(title: 'Quick actions', bottomPadding: 10),
            Row(
              children: [
                Expanded(
                  child: _ActionCard(
                    icon: Icons.add_rounded,
                    title: 'Start a race',
                    onTap: () => context.push('/races/new'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionCard(
                    icon: Icons.group_add_rounded,
                    title: 'Invite crew',
                    onTap: () => context.go('/pass'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // ── Active races ─────────────────────────────────────────────────
            if (raceState.races.isNotEmpty) ...[
              const NuvoSectionHeader(title: 'Active races', bottomPadding: 10),
              for (final race in raceState.races) ...[
                _buildRaceRow(context, race),
                const SizedBox(height: 10),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRaceRow(BuildContext context, Race race) {
    final topParticipant = race.participants.isNotEmpty
        ? race.participants.first
        : null;
    final progress = topParticipant?.progressPercent ?? 0;
    final isComplete = progress >= 100;
    final isAi = race.isSupportedAiMotionRace;
    final participantLabel =
        '${race.participantCount} ${race.participantCount == 1 ? 'participant' : 'participants'}';

    return NuvoDenseRaceRow(
      title: race.title,
      subtitle: participantLabel,
      progressPercent: progress,
      isComplete: isComplete,
      isAiMotion: isAi,
      onTap: () => context.push('/race/${race.id}'),
    );
  }
}

// ── Featured race (prominent hero card at top) ────────────────────────────────

class _FeaturedRaceCard extends StatelessWidget {
  const _FeaturedRaceCard({required this.race, this.userId});

  final Race race;
  final String? userId;

  @override
  Widget build(BuildContext context) {
    final leaderProgress = race.participants.isNotEmpty
        ? race.participants.first.progressPercent
        : 0;
    final myProgress = userId != null
        ? (race.participantFor(userId!)?.progressPercent ?? leaderProgress)
        : leaderProgress;
    final progressPercent = myProgress;
    final isComplete = myProgress >= 100;
    final participantCount = race.participantCount;

    return PressableScale(
      onTap: () => context.push('/race/${race.id}'),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: NuvoColors.navy,
          borderRadius: BorderRadius.all(Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Color(0xC007152B),
              blurRadius: 0,
              offset: Offset(5, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isComplete ? 'Finished' : 'Your next move',
              style: AppTextStyles.labelMedium.copyWith(
                color: NuvoColors.white.withValues(alpha: 0.55),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              race.title,
              style: AppTextStyles.headlineMedium.copyWith(
                color: NuvoColors.white,
              ),
            ),
            if (race.description != null) ...[
              const SizedBox(height: 4),
              Text(
                race.description!,
                style: AppTextStyles.bodySmall.copyWith(
                  color: NuvoColors.white.withValues(alpha: 0.60),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 14),
            if (race.targetValue != null) ...[
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progressPercent / 100,
                        backgroundColor: NuvoColors.white.withValues(
                          alpha: 0.15,
                        ),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isComplete ? NuvoColors.success : NuvoColors.blue,
                        ),
                        minHeight: 5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '$progressPercent%',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: NuvoColors.white.withValues(alpha: 0.70),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Text(
                  '$participantCount ${participantCount == 1 ? 'participant' : 'participants'}',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: NuvoColors.white.withValues(alpha: 0.55),
                  ),
                ),
                const Spacer(),
                if (isComplete)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: NuvoColors.success.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: NuvoColors.success.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      'Complete',
                      style: AppTextStyles.labelMedium.copyWith(
                        color: NuvoColors.success,
                      ),
                    ),
                  )
                else
                  GestureDetector(
                    onTap: () => context.push('/race/${race.id}/proof'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: NuvoColors.blue,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x4007152B),
                            blurRadius: 0,
                            offset: Offset(2, 3),
                          ),
                        ],
                      ),
                      child: Text(
                        'Submit proof',
                        style: AppTextStyles.labelMedium.copyWith(
                          color: NuvoColors.white,
                        ),
                      ),
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

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: NuvoColors.icyBlue,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: NuvoColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1007152B),
            blurRadius: 0,
            offset: Offset(3, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(Icons.flag_rounded, color: NuvoColors.blue, size: 36),
          const SizedBox(height: 12),
          Text('Your start line is clear.', style: AppTextStyles.titleLarge),
          const SizedBox(height: 6),
          Text(
            'Create your first race and pull in your crew.',
            style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          PressableScale(
            onTap: onStart,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: NuvoColors.blue,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x5007152B),
                    blurRadius: 0,
                    offset: Offset(3, 4),
                  ),
                ],
              ),
              child: Text(
                'Start a race',
                style: AppTextStyles.labelMedium.copyWith(
                  color: NuvoColors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Notifications sheet ───────────────────────────────────────────────────────

void _showNotificationsSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: NuvoColors.page,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: NuvoColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            const Icon(
              Icons.notifications_none_rounded,
              color: NuvoColors.blue,
              size: 44,
            ),
            const SizedBox(height: 16),
            Text('No race updates yet.', style: AppTextStyles.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'When your crew joins, submits proof, or crosses the finish line, updates will appear here.',
              style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}

// ── Quick action card ─────────────────────────────────────────────────────────

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: NuvoColors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: NuvoColors.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x2007152B),
              blurRadius: 0,
              offset: Offset(3, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                color: NuvoColors.blue,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: NuvoColors.white, size: 19),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: AppTextStyles.labelLarge)),
          ],
        ),
      ),
    );
  }
}

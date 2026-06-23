import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_avatar.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_shared_components.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../races/data/race_models.dart';
import '../../races/presentation/create_race_screen.dart';
import '../../races/presentation/race_controller.dart';

class CompeteScreen extends ConsumerWidget {
  const CompeteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final raceState = ref.watch(raceControllerProvider);
    final user = ref.watch(authControllerProvider).user;
    final uid = user?.id;

    final active = raceState.races.where((r) => r.status == 'active').toList();
    final finished = raceState.races.where((r) => r.status != 'active').toList();

    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => ref.read(raceControllerProvider.notifier).loadRaces(),
          child: CustomScrollView(
            slivers: [
              // ── Header ──────────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'RACES',
                        style: AppTextStyles.brandLabel.copyWith(
                          color: NuvoColors.blue,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text('Your races.', style: AppTextStyles.displaySmall),
                    ],
                  ),
                ),
              ),

              // ── Actions ──────────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: NuvoPrimaryButton(
                          label: 'New race',
                          expand: true,
                          onPressed: () => context.push('/races/new'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: NuvoOutlineButton(
                          label: 'Join',
                          expand: true,
                          onPressed: () => context.push('/races/join'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Content ──────────────────────────────────────────────────────
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 120),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    if (raceState.loading && raceState.races.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else if (raceState.error != null && raceState.races.isEmpty)
                      Text(
                        raceState.error!,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: NuvoColors.muted,
                        ),
                      )
                    else if (raceState.races.isEmpty)
                      _EmptyState(onStart: () => context.push('/races/new'))
                    else ...[
                      // Active races
                      if (active.isNotEmpty) ...[
                        Text(
                          'ACTIVE',
                          style: AppTextStyles.brandLabel.copyWith(
                            color: NuvoColors.muted,
                          ),
                        ),
                        const SizedBox(height: 12),
                        for (final race in active) ...[
                          _RaceLaneCard(
                            race: race,
                            userId: uid,
                            onTap: () => context.push('/race/${race.id}'),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ],

                      // Finished races
                      if (finished.isNotEmpty) ...[
                        SizedBox(height: active.isEmpty ? 0 : 24),
                        Text(
                          'FINISHED',
                          style: AppTextStyles.brandLabel.copyWith(
                            color: NuvoColors.muted,
                          ),
                        ),
                        const SizedBox(height: 12),
                        for (final race in finished) ...[
                          _RaceLaneCard(
                            race: race,
                            userId: uid,
                            onTap: () => context.push('/race/${race.id}'),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ],

                      // Quick starts (collapsed at bottom)
                      const SizedBox(height: 24),
                      Text(
                        'QUICK STARTS',
                        style: AppTextStyles.brandLabel.copyWith(
                          color: NuvoColors.muted,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _QuickStartRow(
                        icon: Icons.directions_run_rounded,
                        label: '10 Jumping Jacks',
                        sublabel: 'AI MoveCheck · 10 reps',
                        onTap: () => context.push(
                          '/races/new',
                          extra: RaceCreatePrefill.jumpingJacks,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _QuickStartRow(
                        icon: Icons.fitness_center_rounded,
                        label: '100 Push-Ups',
                        sublabel: 'Manual · track your reps',
                        onTap: () => context.push('/races/new'),
                      ),
                      const SizedBox(height: 8),
                      _QuickStartRow(
                        icon: Icons.menu_book_rounded,
                        label: 'Study Sprint',
                        sublabel: 'Manual · track sessions',
                        onTap: () => context.push('/races/new'),
                      ),
                    ],
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Race lane card ────────────────────────────────────────────────────────────

class _RaceLaneCard extends StatelessWidget {
  const _RaceLaneCard({
    required this.race,
    required this.onTap,
    this.userId,
  });

  final Race race;
  final String? userId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final myPart = userId != null ? race.participantFor(userId!) : null;
    final pct = myPart?.progressPercent ?? 0;
    final count = race.participantCount;
    final isComplete = pct >= 100 || race.status != 'active';

    // Other participants for avatar row (exclude self)
    final others = race.participants
        .where((p) => p.userId != userId)
        .take(4)
        .toList();

    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          color: NuvoColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: NuvoColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    race.displayTitle,
                    style: AppTextStyles.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  isComplete ? 'Done' : '$pct%',
                  style: AppTextStyles.labelMedium.copyWith(
                    color: isComplete ? NuvoColors.success : NuvoColors.muted,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: NuvoColors.muted,
                  size: 16,
                ),
              ],
            ),
            const SizedBox(height: 10),
            NuvoRaceLane(progressPercent: pct, trackHeight: 2.5, dotDiameter: 9),
            const SizedBox(height: 8),
            // Participant row — avatars + count
            Row(
              children: [
                if (others.isNotEmpty) ...[
                  _ParticipantAvatarRow(participants: others, total: count),
                ] else
                  Text(
                    'Solo race',
                    style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Quick start row ───────────────────────────────────────────────────────────

// ── Participant avatar row ────────────────────────────────────────────────────

class _ParticipantAvatarRow extends StatelessWidget {
  const _ParticipantAvatarRow({
    required this.participants,
    required this.total,
  });

  final List<RaceParticipant> participants;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        NuvoAvatarStack(
          avatars: participants
              .map((p) => (initials: p.displayName, photoUrl: p.profilePhotoUrl))
              .toList(),
          total: total,
          size: 18,
          max: 4,
        ),
        const SizedBox(width: 6),
        Text(
          '$total ${total == 1 ? 'racer' : 'racers'}',
          style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
        ),
      ],
    );
  }
}

// ── Quick start row ───────────────────────────────────────────────────────────

class _QuickStartRow extends StatelessWidget {
  const _QuickStartRow({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String sublabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: NuvoColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: NuvoColors.divider),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: NuvoColors.panel,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: NuvoColors.border),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: NuvoColors.navy, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppTextStyles.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    sublabel,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: NuvoColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              color: NuvoColors.muted,
              size: 13,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('No races yet.', style: AppTextStyles.headlineMedium),
        const SizedBox(height: 6),
        Text(
          'Start a race, set a finish line, and pull in your crew.',
          style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
        ),
        const SizedBox(height: 20),
        NuvoPrimaryButton(label: 'Start a race', expand: true, onPressed: onStart),
      ],
    );
  }
}

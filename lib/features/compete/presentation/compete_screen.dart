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

// Dark palette — mirrors arena_screen
const _kCard = Color(0xFF0D2040);
const _kCardBorder = Color(0x18FFFFFF);
const _kSub = Color(0x99FFFFFF); // white 60%
const _kMuted = Color(0x61FFFFFF); // white 38%

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
      backgroundColor: NuvoColors.navy,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: NuvoColors.blue,
          backgroundColor: _kCard,
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
                          letterSpacing: 2.0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Your races.',
                        style: AppTextStyles.displaySmall.copyWith(
                          color: Colors.white,
                        ),
                      ),
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
                        child: NuvoBlueButton(
                          label: 'New race',
                          expand: true,
                          onPressed: () => context.push('/races/new'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: _DarkOutlineButton(
                          label: 'Join',
                          onTap: () => context.push('/races/join'),
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
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 48),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: NuvoColors.blue,
                          ),
                        ),
                      )
                    else if (raceState.error != null && raceState.races.isEmpty)
                      Text(
                        raceState.error!,
                        style: AppTextStyles.bodyMedium.copyWith(color: _kSub),
                      )
                    else if (raceState.races.isEmpty)
                      _EmptyState(onStart: () => context.push('/races/new'))
                    else ...[
                      // Active races
                      if (active.isNotEmpty) ...[
                        Text(
                          'ACTIVE',
                          style: AppTextStyles.brandLabel.copyWith(
                            color: _kMuted,
                            letterSpacing: 1.5,
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
                            color: _kMuted,
                            letterSpacing: 1.5,
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

                      // Quick starts
                      const SizedBox(height: 28),
                      Text(
                        'QUICK STARTS',
                        style: AppTextStyles.brandLabel.copyWith(
                          color: _kMuted,
                          letterSpacing: 1.5,
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

    final others = race.participants
        .where((p) => p.userId != userId)
        .take(4)
        .toList();

    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _kCardBorder),
          boxShadow: const [
            BoxShadow(
              color: Color(0x20000000),
              blurRadius: 20,
              offset: Offset(0, 6),
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
                    race.displayTitle,
                    style: AppTextStyles.titleMedium.copyWith(
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  isComplete ? 'Done' : '$pct%',
                  style: AppTextStyles.labelMedium.copyWith(
                    color: isComplete ? NuvoColors.success : NuvoColors.blue,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  color: _kMuted,
                  size: 16,
                ),
              ],
            ),
            const SizedBox(height: 12),
            NuvoRaceLane(progressPercent: pct, onDark: true, trackHeight: 2.5, dotDiameter: 9),
            const SizedBox(height: 12),
            Row(
              children: [
                if (others.isNotEmpty) ...[
                  _ParticipantAvatarRow(participants: others, total: count),
                ] else
                  Text(
                    'Solo race',
                    style: AppTextStyles.bodySmall.copyWith(color: _kMuted),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

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
          borderColor: _kCard,
        ),
        const SizedBox(width: 6),
        Text(
          '$total ${total == 1 ? 'racer' : 'racers'}',
          style: AppTextStyles.bodySmall.copyWith(color: _kMuted),
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _kCardBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF2B7FFF), NuvoColors.blue],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: NuvoColors.blue.withValues(alpha: 0.30),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppTextStyles.titleMedium.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sublabel,
                    style: AppTextStyles.bodySmall.copyWith(color: _kSub),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              color: _kMuted,
              size: 13,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Dark outline button ───────────────────────────────────────────────────────

class _DarkOutlineButton extends StatelessWidget {
  const _DarkOutlineButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _kCardBorder),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: AppTextStyles.labelLarge.copyWith(color: Colors.white),
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
        Text(
          'No races yet.',
          style: AppTextStyles.headlineMedium.copyWith(color: Colors.white),
        ),
        const SizedBox(height: 6),
        Text(
          'Start a race, set a finish line, and pull in your crew.',
          style: AppTextStyles.bodyMedium.copyWith(color: _kSub),
        ),
        const SizedBox(height: 20),
        NuvoBlueButton(
          label: 'Start a race',
          expand: true,
          onPressed: onStart,
        ),
      ],
    );
  }
}

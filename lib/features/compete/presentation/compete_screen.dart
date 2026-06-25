import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_race_widgets.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../races/data/race_models.dart';
import '../../races/domain/chase_context.dart';
import '../../races/presentation/race_controller.dart';

class CompeteScreen extends ConsumerWidget {
  const CompeteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final raceState = ref.watch(raceControllerProvider);
    final user = ref.watch(authControllerProvider).user;
    final uid = user?.id;

    final active =
        raceState.races.where((r) => r.status == 'active').toList();
    final finished =
        raceState.races.where((r) => r.status != 'active').toList();

    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () =>
              ref.read(raceControllerProvider.notifier).loadRaces(),
          child: CustomScrollView(
            slivers: [
              // ── Header ────────────────────────────────────────────────────
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
                      Text(
                        'Your boards.',
                        style: AppTextStyles.headlineLarge,
                      ),
                    ],
                  ),
                ),
              ),

              // ── Action buttons ────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: NuvoPrimaryButton(
                          label: 'Build a Race',
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

              // ── Race list ─────────────────────────────────────────────────
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
                          _CompeteRaceLane(
                            race: race,
                            userId: uid,
                            onTap: () => context.push('/race/${race.id}'),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ],

                      // Finished races
                      if (finished.isNotEmpty) ...[
                        SizedBox(height: active.isEmpty ? 0 : 24),
                        Text(
                          'PAST',
                          style: AppTextStyles.brandLabel.copyWith(
                            color: NuvoColors.muted,
                          ),
                        ),
                        const SizedBox(height: 12),
                        for (final race in finished) ...[
                          _CompeteRaceLane(
                            race: race,
                            userId: uid,
                            onTap: () => context.push('/race/${race.id}'),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ],
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

class _CompeteRaceLane extends StatelessWidget {
  const _CompeteRaceLane({
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
    final isComplete = pct >= 100 || race.status != 'active';

    final chase = userId != null
        ? ChaseContext.compute(race, userId!)
        : null;

    final avatars = race.participants
        .take(5)
        .map((p) => (initials: _firstInitial(p.displayName), photoUrl: p.profilePhotoUrl))
        .toList();

    return RaceLaneRow(
      title: race.displayTitle,
      raceTypeLabel: _raceTypeLabel(race),
      progressPercent: pct,
      scoreLabel: _scoreLabel(race, myPart),
      gapCopy: isComplete ? null : chase?.chaseCopy,
      avatars: avatars,
      racerCount: race.participantCount,
      recentActivityLine: _recentActivityLine(race),
      isComplete: isComplete,
      onTap: onTap,
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _raceTypeLabel(Race race) {
  if (race.targetValue != null) {
    final unit = race.unit ?? race.targetUnit ?? 'reps';
    return 'First to ${race.targetValue} $unit';
  }
  if (race.finishLineAt != null) return 'Most by time';
  return 'Crew race';
}

String _scoreLabel(Race race, RaceParticipant? myPart) {
  final val = myPart?.progressValue ?? 0;
  final unit = race.unit ?? race.targetUnit ?? 'reps';
  if (race.targetValue != null) {
    return '$val / ${race.targetValue}';
  }
  return '$val $unit';
}

String? _recentActivityLine(Race race) {
  final move = race.recentMoves.firstOrNull;
  if (move == null) return null;
  final name = move.displayName.trim().split(' ').first;
  final val = move.value;
  final unit = race.unit ?? race.targetUnit ?? 'reps';
  if (val != null && val > 0) return '$name added $val $unit';
  return null;
}

String _firstInitial(String name) {
  final trimmed = name.trim();
  return trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
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
          'Build a race, set a finish line, and pull in your crew.',
          style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
        ),
        const SizedBox(height: 20),
        NuvoPrimaryButton(
          label: 'Build a Race',
          expand: true,
          onPressed: onStart,
        ),
      ],
    );
  }
}

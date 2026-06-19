import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_empty_state.dart';
import '../../../core/widgets/nuvo_error_state.dart';
import '../../races/data/race_models.dart';
import '../../races/presentation/race_controller.dart';

class _QuickStart {
  const _QuickStart({
    required this.title,
    required this.unit,
    required this.targetValue,
  });

  final String title;
  final String unit;
  final int targetValue;
}

const _quickStarts = [
  _QuickStart(title: 'Race to a 6-pack', unit: 'sessions', targetValue: 20),
  _QuickStart(title: 'Ship a side project', unit: 'milestones', targetValue: 5),
  _QuickStart(title: 'Most books read', unit: 'books', targetValue: 10),
  _QuickStart(title: '30 days no scrolling', unit: 'days', targetValue: 30),
  _QuickStart(title: 'Longest run streak', unit: 'runs', targetValue: 14),
];

class CompeteScreen extends ConsumerWidget {
  const CompeteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final raceState = ref.watch(raceControllerProvider);

    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: RefreshIndicator(
        onRefresh: () => ref.read(raceControllerProvider.notifier).loadRaces(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            Text('Compete', style: AppTextStyles.headlineLarge),
            const SizedBox(height: 8),
            Text(
              'Create a race, pull in your crew, and move the leaderboard with proof.',
              style: AppTextStyles.bodyLarge.copyWith(color: NuvoColors.muted),
            ),
            const SizedBox(height: 22),
            NuvoPrimaryButton(
              label: 'Start a race',
              icon: Icons.flag_rounded,
              expand: true,
              onPressed: () => context.push('/races/new'),
            ),
            const SizedBox(height: 12),
            NuvoOutlineButton(
              label: 'Join with code',
              icon: Icons.key_rounded,
              expand: true,
              onPressed: () => context.push('/races/join'),
            ),
            const SizedBox(height: 26),
            Text('Your races', style: AppTextStyles.titleLarge),
            const SizedBox(height: 12),
            if (raceState.loading && raceState.races.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (raceState.error != null && raceState.races.isEmpty)
              NuvoErrorState(
                message: raceState.error!,
                onRetry: () =>
                    ref.read(raceControllerProvider.notifier).loadRaces(),
              )
            else if (raceState.races.isEmpty)
              NuvoEmptyState(
                icon: Icons.flag_rounded,
                title: 'Your start line is clear.',
                body: 'Create your first race and pull in your crew.',
                ctaLabel: 'Start a race',
                onCta: () => context.push('/races/new'),
              )
            else
              for (final race in raceState.races) ...[
                _RaceListTile(race: race),
                const SizedBox(height: 10),
              ],
            const SizedBox(height: 24),
            Text('Quick starts', style: AppTextStyles.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Choose a race template, then finish the setup on the next screen.',
              style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
            ),
            const SizedBox(height: 12),
            for (final quickStart in _quickStarts) ...[
              _QuickStartTile(
                quickStart: quickStart,
                onTap: () => context.push('/races/new'),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _RaceListTile extends StatelessWidget {
  const _RaceListTile({required this.race});

  final Race race;

  @override
  Widget build(BuildContext context) {
    final leader = race.participants.isNotEmpty
        ? race.participants.first
        : null;
    final progress = leader?.progressPercent ?? 0;
    final participantLabel =
        '${race.participantCount} ${race.participantCount == 1 ? 'participant' : 'participants'}';
    final progressLabel = race.targetValue == null ? '' : ' · $progress% done';

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => context.push('/race/${race.id}'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: NuvoColors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: NuvoColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                color: NuvoColors.navy,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.leaderboard_rounded,
                color: NuvoColors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    race.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.titleMedium,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$participantLabel$progressLabel',
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
              size: 14,
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickStartTile extends StatelessWidget {
  const _QuickStartTile({required this.quickStart, required this.onTap});

  final _QuickStart quickStart;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: NuvoColors.icyBlue,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: NuvoColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome_rounded, color: NuvoColors.blue),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(quickStart.title, style: AppTextStyles.titleMedium),
                  const SizedBox(height: 3),
                  Text(
                    '${quickStart.targetValue} ${quickStart.unit}',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: NuvoColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

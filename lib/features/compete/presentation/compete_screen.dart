import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/animations.dart' hide PressableScale;
import '../../../core/widgets/nuvo_avatar.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_icons.dart';
import '../../../core/widgets/nuvo_shared_components.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../races/data/race_models.dart';
import '../../races/domain/camera_verification_resolver.dart';
import '../../races/presentation/create_race_screen.dart';
import '../../races/presentation/race_controller.dart';

class CompeteScreen extends ConsumerWidget {
  const CompeteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final raceState = ref.watch(raceControllerProvider);
    final user = ref.watch(authControllerProvider).user;
    final uid = user?.id;

    final cameraRaces = raceState.races
        .where((race) => resolveCameraVerification(race).isCameraVerifiable)
        .toList();
    final active = cameraRaces.where((r) => r.status == 'active').toList();
    final finished = raceState.races
        .where((r) => r.status != 'active')
        .where((race) => resolveCameraVerification(race).isCameraVerifiable)
        .toList();

    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: NuvoColors.blue,
          backgroundColor: NuvoColors.surface,
          onRefresh: () =>
              ref.read(raceControllerProvider.notifier).loadRaces(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: _CompeteHero(
                    activeCount: active.length,
                    finishedCount: finished.length,
                    onStart: () => context.push('/races/new'),
                    onJoin: () => context.push('/races/join'),
                  ),
                ),
              ),

              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 120),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    if (raceState.loading && raceState.races.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: NuvoColors.blue,
                          ),
                        ),
                      )
                    else if (raceState.error != null && raceState.races.isEmpty)
                      Text(
                        raceState.error!,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: NuvoColors.muted,
                        ),
                      )
                    else if (raceState.races.isEmpty || cameraRaces.isEmpty)
                      _EmptyState(onStart: () => context.push('/races/new'))
                    else ...[
                      // Active races
                      if (active.isNotEmpty) ...[
                        const _SectionLabel(label: 'Active'),
                        const SizedBox(height: 12),
                        for (var i = 0; i < active.length; i++) ...[
                          FadeSlideIn(
                            delay: Duration(milliseconds: 60 * i),
                            child: _RaceLaneCard(
                              race: active[i],
                              userId: uid,
                              onTap: () => context.push('/race/${active[i].id}'),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ],

                      // Finished races
                      if (finished.isNotEmpty) ...[
                        SizedBox(height: active.isEmpty ? 0 : 24),
                        const _SectionLabel(label: 'Finished'),
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
                      const _SectionLabel(label: 'Quick starts'),
                      const SizedBox(height: 12),
                      _QuickStartRow(
                        icon: Icons.directions_run_rounded,
                        label: '10 Jumping Jacks',
                        sublabel: 'MoveCheck · camera verification',
                        accentColor: NuvoColors.blue,
                        onTap: () => context.push(
                          '/races/new',
                          extra: RaceCreatePrefill.jumpingJacks,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _QuickStartRow(
                        icon: Icons.fitness_center_rounded,
                        label: '10 Pushups',
                        sublabel: 'MoveCheck · camera verification',
                        accentColor: NuvoColors.coral,
                        onTap: () => context.push(
                          '/races/new',
                          extra: RaceCreatePrefill.pushups,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _QuickStartRow(
                        icon: Icons.accessibility_new_rounded,
                        label: '10 Squats',
                        sublabel: 'MoveCheck · camera verification',
                        accentColor: NuvoColors.aqua,
                        onTap: () => context.push(
                          '/races/new',
                          extra: RaceCreatePrefill.squats,
                        ),
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

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: NuvoColors.blue,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: AppTextStyles.labelMedium.copyWith(
            color: NuvoColors.muted,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

// ── Hero ──────────────────────────────────────────────────────────────────────

class _CompeteHero extends StatelessWidget {
  const _CompeteHero({
    required this.activeCount,
    required this.finishedCount,
    required this.onStart,
    required this.onJoin,
  });

  final int activeCount;
  final int finishedCount;
  final VoidCallback onStart;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: NuvoColors.border),
        boxShadow: [
          BoxShadow(
            color: NuvoColors.blue.withValues(alpha: 0.08),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: NuvoColors.navy,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Center(
                  child: NuvoIcon(NuvoIconType.flag, color: NuvoColors.white, size: 20),
                ),
              ),
              const Spacer(),
              _CountPill(value: '$activeCount', label: 'active'),
              const SizedBox(width: 8),
              _CountPill(value: '$finishedCount', label: 'done'),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'Races',
            style: AppTextStyles.headlineMedium.copyWith(
              color: NuvoColors.navy,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Create a race, set a goal, pull in your crew.',
            style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: NuvoPrimaryButton(
                  label: 'Start race',
                  expand: true,
                  onPressed: onStart,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: NuvoOutlineButton(
                  label: 'Join',
                  expand: true,
                  onPressed: onJoin,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: NuvoColors.panel,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: AppTextStyles.labelLarge.copyWith(color: NuvoColors.blueInk),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(color: NuvoColors.muted),
          ),
        ],
      ),
    );
  }
}

// ── Race lane card ────────────────────────────────────────────────────────────

class _RaceLaneCard extends StatelessWidget {
  const _RaceLaneCard({required this.race, required this.onTap, this.userId});

  final Race race;
  final String? userId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final myPart = userId != null ? race.participantFor(userId!) : null;
    final pct = myPart?.progressPercent ?? 0;
    final count = race.participantCount;
    final isComplete = pct >= 100 || race.status != 'active';
    final isActive = race.status == 'active';

    final others = race.participants
        .where((p) => p.userId != userId)
        .take(4)
        .toList();

    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(
          color: NuvoColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? NuvoColors.blue.withValues(alpha: 0.20)
                : NuvoColors.border,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x08050B14),
              blurRadius: 16,
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
                    style: AppTextStyles.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isComplete
                        ? NuvoColors.success.withValues(alpha: 0.10)
                        : NuvoColors.blue.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    isComplete ? 'Done' : '$pct%',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: isComplete ? NuvoColors.success : NuvoColors.blue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const NuvoIcon(NuvoIconType.arrow, color: NuvoColors.textMuted, size: 14),
              ],
            ),
            const SizedBox(height: 12),
            NuvoRaceLane(
              progressPercent: pct,
              trackHeight: 3,
              dotDiameter: 10,
              delay: const Duration(milliseconds: 100),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (others.isNotEmpty)
                  _ParticipantAvatarRow(participants: others, total: count)
                else
                  Text(
                    'Solo race',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: NuvoColors.textMuted,
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
              .map(
                (p) => (initials: p.displayName, photoUrl: p.profilePhotoUrl),
              )
              .toList(),
          total: total,
          size: 20,
          max: 4,
          borderColor: NuvoColors.surface,
        ),
        const SizedBox(width: 7),
        Text(
          '$total ${total == 1 ? 'racer' : 'racers'}',
          style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.textMuted),
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
    this.accentColor = NuvoColors.blue,
  });

  final IconData icon;
  final String label;
  final String sublabel;
  final VoidCallback onTap;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: NuvoColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: NuvoColors.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x080A1A33),
              blurRadius: 14,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: accentColor, size: 20),
            ),
            const SizedBox(width: 14),
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
            const NuvoIcon(NuvoIconType.arrow, color: NuvoColors.textMuted, size: 13),
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
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: NuvoColors.blue.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const NuvoIcon(NuvoIconType.flag, color: NuvoColors.blue, size: 22),
        ),
        const SizedBox(height: 20),
        Text(
          'No races yet.',
          style: AppTextStyles.headlineMedium.copyWith(color: NuvoColors.navy),
        ),
        const SizedBox(height: 8),
        Text(
          'Start a race, set a finish line, and pull in your crew.',
          style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
        ),
        const SizedBox(height: 20),
        NuvoPrimaryButton(
          label: 'Start a race',
          expand: true,
          onPressed: onStart,
        ),
      ],
    );
  }
}

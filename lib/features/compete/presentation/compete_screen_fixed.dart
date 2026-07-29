import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_geometry.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/bottom_nav.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_shared_components.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../races/presentation/create_race_screen.dart';
import '../../races/presentation/race_controller.dart';

class CompeteScreen extends ConsumerWidget {
  const CompeteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final raceState = ref.watch(raceControllerProvider);

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
                child: _CompeteHero(
                  onStart: () => context.push('/races/new'),
                  onJoin: () => context.push('/races/join'),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  18,
                  20,
                  NuvoBottomNav.bottomPadding(context),
                ),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    if (raceState.loading)
                      const LinearProgressIndicator(
                        minHeight: 2,
                        color: NuvoColors.blue,
                        backgroundColor: NuvoColors.panel,
                      ),
                    if (raceState.error != null) ...[
                      if (raceState.loading) const SizedBox(height: 14),
                      _InlineNotice(raceState.error!),
                    ],
                    if (raceState.loading || raceState.error != null)
                      const SizedBox(height: 22),
                    const _SectionLabel(
                      label: 'Pick a start line',
                      sublabel: 'Tap one and adjust the finish line next.',
                    ),
                    const SizedBox(height: 12),
                    _QuickStartRow(
                      icon: Icons.fitness_center_rounded,
                      label: 'First to 100 Pushups',
                      sublabel: 'Fast setup · camera verified',
                      onTap: () => context.push(
                        '/races/new',
                        extra: RaceCreatePrefill.pushups,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _QuickStartRow(
                      icon: Icons.person_outline_rounded,
                      label: 'First to 15 Squats',
                      sublabel: 'Leg day · clean reps count',
                      onTap: () => context.push(
                        '/races/new',
                        extra: RaceCreatePrefill.squats,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _QuickStartRow(
                      icon: Icons.accessibility_new_rounded,
                      label: 'First to 500 Jumping Jacks',
                      sublabel: 'Full body · loud leaderboard moves',
                      onTap: () => context.push(
                        '/races/new',
                        extra: RaceCreatePrefill.jumpingJacks,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _QuickStartRow(
                      icon: Icons.directions_walk_rounded,
                      label: 'First to 40 Lunges',
                      sublabel: 'Side-to-side race energy',
                      onTap: () => context.push(
                        '/races/new',
                        extra: RaceCreatePrefill.lunges,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _QuickStartRow(
                      icon: Icons.timer_outlined,
                      label: 'First to 300 Plank Seconds',
                      sublabel: 'Hold steady · seconds count',
                      onTap: () => context.push(
                        '/races/new',
                        extra: RaceCreatePrefill.plank,
                      ),
                    ),
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, this.sublabel});
  final String label;
  final String? sublabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.titleMedium.copyWith(
            color: NuvoColors.navy,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        if (sublabel != null) ...[
          const SizedBox(height: 3),
          Text(
            sublabel!,
            style: AppTextStyles.bodySmall.copyWith(
              color: NuvoColors.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}

class _CompeteHero extends StatelessWidget {
  const _CompeteHero({required this.onStart, required this.onJoin});

  final VoidCallback onStart;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: NuvoColors.navy,
        borderRadius: BorderRadius.circular(NuvoRadii.hero),
        border: Border.all(color: NuvoColors.navy, width: 2),
        boxShadow: AppShadows.hardShadow4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: NuvoColors.blue,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                'Start line',
                style: AppTextStyles.labelMedium.copyWith(
                  color: NuvoColors.white.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Compete',
                      style: AppTextStyles.headlineLarge.copyWith(
                        color: NuvoColors.white,
                        height: 1.05,
                        fontSize: 32,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Pick the race, set the finish line, then let Nuvo verify the proof.',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: NuvoColors.white.withValues(alpha: 0.72),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const _ModePill(label: 'AI Motion Proof'),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: NuvoPrimaryButton(
                  label: 'Start race',
                  expand: true,
                  onPressed: onStart,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: NuvoOutlineButton(
                  label: 'Join',
                  icon: Icons.group_add_rounded,
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

class _ModePill extends StatelessWidget {
  const _ModePill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: NuvoColors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(NuvoRadii.pill),
        border: Border.all(color: NuvoColors.white.withValues(alpha: 0.14)),
      ),
      child: Text(
        label,
        style: AppTextStyles.labelSmall.copyWith(
          color: NuvoColors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NuvoColors.panelLight,
        borderRadius: BorderRadius.circular(NuvoRadii.md),
        border: Border.all(color: NuvoColors.border),
      ),
      child: Text(
        message,
        style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.textMuted),
      ),
    );
  }
}

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
      child: NuvoHardOffset(
        offset: 3,
        radius: NuvoRadii.lg,
        plateColor: NuvoColors.navy,
        faceColor: NuvoColors.white,
        borderColor: NuvoColors.navy,
        borderWidth: 1.5,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: NuvoColors.panel,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: NuvoColors.border, width: 1.2),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: NuvoColors.navy, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppTextStyles.titleMedium.copyWith(
                      color: NuvoColors.navy,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sublabel,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: NuvoColors.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: NuvoColors.textMuted,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

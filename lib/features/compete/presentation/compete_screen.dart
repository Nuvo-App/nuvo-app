import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_shared_components.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../races/presentation/create_race_screen.dart';

class _QuickStart {
  const _QuickStart({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.unit,
    required this.targetValue,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String unit;
  final int targetValue;
}

const _quickStarts = [
  _QuickStart(
    title: '10 Jumping Jacks',
    subtitle: 'AI Motion Proof · 10 reps',
    icon: Icons.directions_run_rounded,
    unit: 'reps',
    targetValue: 10,
  ),
  _QuickStart(
    title: 'Race to 100 Push-Ups',
    subtitle: 'Manual proof · track your reps',
    icon: Icons.fitness_center_rounded,
    unit: 'push-ups',
    targetValue: 100,
  ),
  _QuickStart(
    title: 'Study Sprint',
    subtitle: 'Manual proof · track sessions',
    icon: Icons.menu_book_rounded,
    unit: 'sessions',
    targetValue: 20,
  ),
  _QuickStart(
    title: 'Ship a Side Project',
    subtitle: 'Milestone proof · set your own goals',
    icon: Icons.rocket_launch_rounded,
    unit: 'milestones',
    targetValue: 5,
  ),
  _QuickStart(
    title: '30 Days No Scrolling',
    subtitle: 'Manual proof · daily commitment',
    icon: Icons.phone_locked_rounded,
    unit: 'days',
    targetValue: 30,
  ),
];

class CompeteScreen extends StatelessWidget {
  const CompeteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        children: [
          // ── Page header ────────────────────────────────────────────────────
          const NuvoPageHeader(
            title: 'Compete',
            subtitle:
                'Create a race, pull in your crew, and move the leaderboard.',
          ),
          const SizedBox(height: 22),

          // ── Primary action ─────────────────────────────────────────────────
          NuvoPrimaryButton(
            label: 'Start a race',
            icon: Icons.flag_rounded,
            expand: true,
            onPressed: () => context.push('/races/new'),
          ),
          const SizedBox(height: 10),

          // ── Secondary action ───────────────────────────────────────────────
          NuvoOutlineButton(
            label: 'Join with code',
            icon: Icons.key_rounded,
            expand: true,
            onPressed: () => context.push('/races/join'),
          ),
          const SizedBox(height: 28),

          // ── Quick starts ───────────────────────────────────────────────────
          const NuvoSectionHeader(title: 'Quick starts', bottomPadding: 4),
          Text(
            'Choose a template and start in seconds.',
            style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < _quickStarts.length; i++) ...[
            _QuickStartTile(
              quickStart: _quickStarts[i],
              featured: i == 0,
              onTap: () => context.push(
                '/races/new',
                extra: i == 0 ? RaceCreatePrefill.jumpingJacks : null,
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

// ── Quick start tile ──────────────────────────────────────────────────────────

class _QuickStartTile extends StatelessWidget {
  const _QuickStartTile({
    required this.quickStart,
    required this.onTap,
    this.featured = false,
  });

  final _QuickStart quickStart;
  final VoidCallback onTap;
  final bool featured;

  @override
  Widget build(BuildContext context) {
    if (featured) {
      // AI Motion featured template — navy card with double shadow
      return PressableScale(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: NuvoColors.navy,
            borderRadius: BorderRadius.all(Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Color(0x1407152B),
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
              BoxShadow(
                color: Color(0x0B07152B),
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: NuvoColors.blue,
                  borderRadius: BorderRadius.circular(13),
                ),
                alignment: Alignment.center,
                child: Icon(quickStart.icon, color: NuvoColors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      quickStart.title,
                      style: AppTextStyles.titleMedium.copyWith(
                        color: NuvoColors.white,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      quickStart.subtitle,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: NuvoColors.white.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: NuvoColors.white.withValues(alpha: 0.45),
                size: 13,
              ),
            ],
          ),
        ),
      );
    }

    // Non-featured: NuvoActionTile (icon, title, proof subtitle, arrow)
    return NuvoActionTile(
      icon: quickStart.icon,
      title: quickStart.title,
      subtitle: quickStart.subtitle,
      iconBg: NuvoColors.icyBlue,
      iconColor: NuvoColors.navy,
      onTap: onTap,
    );
  }
}

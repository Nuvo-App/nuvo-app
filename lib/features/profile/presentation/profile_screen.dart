import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_card.dart';
import '../../../core/widgets/nuvo_progress_bar.dart';


/// Profile tab — inside the bottom nav shell (no Scaffold here).
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
      children: [
        // Settings button
        Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onTap: () {},
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: NuvoColors.sectionBlue,
                shape: BoxShape.circle,
                border: Border.all(color: NuvoColors.border),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.settings_rounded,
                  size: 17, color: NuvoColors.muted),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Profile header
        const _ProfileHeader(),
        const SizedBox(height: 28),

        // Stat bento
        const _StatsBento(),
        const SizedBox(height: 28),

        // Active races
        const _ActiveSection(),
        const SizedBox(height: 28),

        // Achievements
        const _AchievementsSection(),
        const SizedBox(height: 28),

        // More links
        _MoreLink(
          label: 'Connected Devices',
          icon: Icons.watch_rounded,
          accent: AppColors.dreamPurple,
          onTap: () => context.go('/devices'),
        ),
        const SizedBox(height: 24),

        NuvoSecondaryButton(
          label: 'Browse race ideas',
          icon: Icons.lightbulb_rounded,
          expand: true,
          onPressed: () => context.go('/challenge-ideas'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Profile header — avatar, name, handle, member ID
// ---------------------------------------------------------------------------

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Avatar circle
        Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: NuvoColors.blue,
          ),
          alignment: Alignment.center,
          child: Text(
            'AD',
            style: AppTextStyles.headlineMedium
                .copyWith(color: NuvoColors.white),
          ),
        ),
        const SizedBox(width: 16),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Akaash Deepak', style: AppTextStyles.headlineMedium),
              const SizedBox(height: 2),
              Text(
                '@akaash',
                style: AppTextStyles.bodyMedium
                    .copyWith(color: NuvoColors.muted),
              ),
              const SizedBox(height: 10),

              // Member ID pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: NuvoColors.sectionBlue,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: NuvoColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.fingerprint_rounded,
                        size: 12, color: NuvoColors.blue),
                    const SizedBox(width: 5),
                    Text(
                      'NUVO-AKSHAY-4821',
                      style: AppTextStyles.brandLabel
                          .copyWith(color: NuvoColors.blue),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Streak badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: NuvoColors.mint.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                      color: NuvoColors.mint.withValues(alpha: 0.28)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.bolt_rounded,
                        size: 13, color: NuvoColors.mint),
                    const SizedBox(width: 4),
                    Text(
                      '7-day streak',
                      style: AppTextStyles.labelMedium
                          .copyWith(color: NuvoColors.mint),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Stats bento
// ---------------------------------------------------------------------------

class _StatsBento extends StatelessWidget {
  const _StatsBento();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: _BentoStat(value: '12', label: 'Wins', color: NuvoColors.mint)),
        SizedBox(width: 10),
        Expanded(child: _BentoStat(value: '3', label: 'Losses', color: AppColors.danger)),
        SizedBox(width: 10),
        Expanded(child: _BentoStat(value: '4', label: 'Active', color: NuvoColors.blue)),
      ],
    );
  }
}

class _BentoStat extends StatelessWidget {
  const _BentoStat({
    required this.value,
    required this.label,
    required this.color,
  });
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return NuvoCard(
      elevated: true,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: AppTextStyles.headlineMedium.copyWith(color: color)),
          const SizedBox(height: 2),
          Text(label, style: AppTextStyles.labelSmall),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Active races
// ---------------------------------------------------------------------------

class _ActiveSection extends StatelessWidget {
  const _ActiveSection();

  static const _races = [
    ('100 Pushups a Day', 0.64),
    ('Wake at 5:30 AM', 0.80),
    ('Read 30 Min / Day', 0.50),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Active races', style: AppTextStyles.titleLarge),
        const SizedBox(height: 12),
        NuvoCard(
          padding: const EdgeInsets.all(4),
          child: Column(
            children: [
              for (var i = 0; i < _races.length; i++) ...[
                _RaceRow(title: _races[i].$1, progress: _races[i].$2),
                if (i < _races.length - 1)
                  const Divider(height: 1, indent: 16, endIndent: 16),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _RaceRow extends StatelessWidget {
  const _RaceRow({required this.title, required this.progress});
  final String title;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: AppTextStyles.bodyMedium)),
              const SizedBox(width: 8),
              Text(
                '${(progress * 100).toInt()}%',
                style: AppTextStyles.labelMedium
                    .copyWith(color: NuvoColors.blue),
              ),
            ],
          ),
          const SizedBox(height: 8),
          NuvoProgressBar(value: progress),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Achievements — icons, no emojis
// ---------------------------------------------------------------------------

class _AchievementsSection extends StatelessWidget {
  const _AchievementsSection();

  static const _badges = [
    (Icons.emoji_events_rounded, NuvoColors.mint, 'First Win'),
    (Icons.bolt_rounded, AppColors.warning, 'Streak Builder'),
    (Icons.verified_rounded, NuvoColors.blue, 'Proof Verified'),
    (Icons.people_rounded, NuvoColors.blue, 'Crew Captain'),
    (Icons.schedule_rounded, NuvoColors.muted, 'Early Riser'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Achievements', style: AppTextStyles.titleLarge),
        const SizedBox(height: 12),
        SizedBox(
          height: 88,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _badges.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final (icon, color, label) = _badges[i];
              return _BadgeTile(icon: icon, color: color, label: label);
            },
          ),
        ),
      ],
    );
  }
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile({
    required this.icon,
    required this.color,
    required this.label,
  });
  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 84,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: NuvoColors.sectionBlue,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NuvoColors.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 24, color: color),
          const SizedBox(height: 6),
          Text(
            label,
            style: AppTextStyles.labelSmall,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// More links
// ---------------------------------------------------------------------------

class _MoreLink extends StatelessWidget {
  const _MoreLink({
    required this.label,
    required this.icon,
    required this.accent,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: NuvoColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: NuvoColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: accent, size: 17),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label, style: AppTextStyles.bodyMedium),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: NuvoColors.muted, size: 20),
          ],
        ),
      ),
    );
  }
}

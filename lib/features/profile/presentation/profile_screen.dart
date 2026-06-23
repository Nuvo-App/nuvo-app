import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_avatar.dart';
import '../../../core/widgets/nuvo_shared_components.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../races/data/race_models.dart';
import '../../races/presentation/race_controller.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final displayName = user?.fullName ?? user?.email ?? '—';
    final username = user?.username != null ? '@${user!.username}' : null;
    final initials = user?.avatarInitials ?? '?';
    final photoUrl = user?.profilePhotoUrl;
    debugPrint('PROFILE_SCREEN_PHOTO_URL: $photoUrl');
    final uid = user?.id;

    final raceState = ref.watch(raceControllerProvider);
    final activeCount = raceState.races
        .where((r) => r.status == 'active')
        .length;
    final finishedCount = raceState.races
        .where((r) => r.status != 'active')
        .length;
    final moveCount = raceState.races.fold<int>(
      0,
      (s, r) => s + r.recentProofs.length,
    );
    final progressValues = raceState.races
        .expand((r) => r.participants)
        .map((p) => p.progressPercent)
        .toList();
    final avgProgress = progressValues.isEmpty
        ? 0
        : (progressValues.fold<int>(0, (s, v) => s + v) / progressValues.length)
              .round();

    final safeTop = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: CustomScrollView(
        slivers: [
          // ── Navy header ───────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              color: NuvoColors.navy,
              padding: EdgeInsets.fromLTRB(20, safeTop + 24, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top row: label + edit
                  Row(
                    children: [
                      Text(
                        'PROFILE',
                        style: AppTextStyles.brandLabel.copyWith(
                          color: NuvoColors.white.withValues(alpha: 0.45),
                        ),
                      ),
                      const Spacer(),
                      PressableScale(
                        onTap: () => context.push('/profile/edit'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'Edit',
                            style: AppTextStyles.labelMedium.copyWith(
                              color: NuvoColors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Avatar + name
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      NuvoAvatar(
                        initials: initials,
                        photoUrl: photoUrl,
                        size: NuvoAvatarSizes.profile,
                        bgColor: Colors.white.withValues(alpha: 0.14),
                        textColor: NuvoColors.white,
                        borderColor: Colors.white.withValues(alpha: 0.25),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              style: AppTextStyles.headlineLarge.copyWith(
                                color: NuvoColors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (username != null) ...[
                              const SizedBox(height: 3),
                              Text(
                                username,
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: NuvoColors.white.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Stats row
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      _HeaderStat(value: '$activeCount', label: 'Active'),
                      _HeaderDivider(),
                      _HeaderStat(value: '$finishedCount', label: 'Finished'),
                      _HeaderDivider(),
                      _HeaderStat(value: '$moveCount', label: 'Moves'),
                      _HeaderDivider(),
                      _HeaderStat(value: '$avgProgress%', label: 'Avg'),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── White body ────────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Race history
                Text(
                  'RACE HISTORY',
                  style: AppTextStyles.brandLabel.copyWith(
                    color: NuvoColors.muted,
                  ),
                ),
                const SizedBox(height: 12),

                if (raceState.loading && raceState.races.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (raceState.races.isEmpty)
                  Text(
                    'Start your first race to build your history.',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: NuvoColors.muted,
                    ),
                  )
                else
                  for (final race in raceState.races.take(6)) ...[
                    _ProfileRaceRow(
                      race: race,
                      userId: uid,
                      onTap: () => context.push('/race/${race.id}'),
                    ),
                    const SizedBox(height: 8),
                  ],

                const SizedBox(height: 32),

                // Account
                Text(
                  'ACCOUNT',
                  style: AppTextStyles.brandLabel.copyWith(
                    color: NuvoColors.muted,
                  ),
                ),
                const SizedBox(height: 12),
                _AccountRow(
                  icon: Icons.badge_rounded,
                  label: 'Crew pass',
                  onTap: () => context.go('/pass'),
                ),
                const SizedBox(height: 8),
                _AccountRow(
                  icon: Icons.edit_rounded,
                  label: 'Edit profile',
                  onTap: () => context.push('/profile/edit'),
                ),
                const SizedBox(height: 8),
                _AccountRow(
                  icon: Icons.logout_rounded,
                  label: 'Sign out',
                  isDanger: true,
                  onTap: () =>
                      ref.read(authControllerProvider.notifier).logout(),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Header stat ───────────────────────────────────────────────────────────────

class _HeaderStat extends StatelessWidget {
  const _HeaderStat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            value,
            style: AppTextStyles.displaySmall.copyWith(color: NuvoColors.white),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: NuvoColors.white.withValues(alpha: 0.45),
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 32,
    color: Colors.white.withValues(alpha: 0.12),
    margin: const EdgeInsets.symmetric(horizontal: 4),
  );
}

// ── Profile race row ──────────────────────────────────────────────────────────

class _ProfileRaceRow extends StatelessWidget {
  const _ProfileRaceRow({required this.race, required this.onTap, this.userId});

  final Race race;
  final String? userId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final myPart = userId != null ? race.participantFor(userId!) : null;
    final pct = myPart?.progressPercent ?? 0;
    final isActive = race.status == 'active';

    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: NuvoColors.white,
          borderRadius: BorderRadius.circular(14),
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
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: isActive
                        ? NuvoColors.blue.withValues(alpha: 0.10)
                        : NuvoColors.panel,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isActive ? 'Active' : _statusLabel(race.status),
                    style: AppTextStyles.labelSmall.copyWith(
                      color: isActive ? NuvoColors.blue : NuvoColors.muted,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            NuvoRaceLane(
              progressPercent: pct,
              trackHeight: 2.5,
              dotDiameter: 9,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Account row ───────────────────────────────────────────────────────────────

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDanger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDanger;

  @override
  Widget build(BuildContext context) {
    final color = isDanger ? NuvoColors.danger : NuvoColors.navy;

    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: NuvoColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: NuvoColors.divider),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.bodyMedium.copyWith(color: color),
              ),
            ),
            if (!isDanger)
              const Icon(
                Icons.chevron_right_rounded,
                color: NuvoColors.muted,
                size: 16,
              ),
          ],
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _statusLabel(String status) => switch (status) {
  'completed' || 'complete' || 'finished' => 'Finished',
  'archived' => 'Archived',
  'cancelled' => 'Cancelled',
  _ => status.replaceAll('_', ' '),
};

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

const _kProfileBlack = NuvoColors.page;
const _kProfileBorder = NuvoColors.border;
const _kProfileBlueBorder = NuvoColors.blue;
const _kProfileTextMuted = NuvoColors.muted;

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
      backgroundColor: _kProfileBlack,
      body: CustomScrollView(
        slivers: [
          // ── Navy header ───────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    NuvoColors.navy,
                    NuvoColors.blueInk,
                    NuvoColors.blue,
                  ],
                ),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(34),
                ),
                boxShadow: [
                  BoxShadow(
                    color: NuvoColors.blue.withValues(alpha: 0.24),
                    blurRadius: 34,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              padding: EdgeInsets.fromLTRB(20, safeTop + 22, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top row: label + edit
                  Row(
                    children: [
                      Text(
                        'PROFILE',
                        style: AppTextStyles.brandLabel.copyWith(
                          color: NuvoColors.white.withValues(alpha: 0.72),
                          letterSpacing: 0,
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
                            color: NuvoColors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: NuvoColors.white.withValues(alpha: 0.22),
                            ),
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
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: NuvoColors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: NuvoColors.white.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        NuvoAvatar(
                          initials: initials,
                          photoUrl: photoUrl,
                          size: NuvoAvatarSizes.profile,
                          bgColor: NuvoColors.blue.withValues(alpha: 0.22),
                          textColor: NuvoColors.white,
                          borderColor: NuvoColors.blue.withValues(alpha: 0.55),
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
                                  fontWeight: FontWeight.w900,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (username != null) ...[
                                const SizedBox(height: 5),
                                Text(
                                  username,
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    color: NuvoColors.white.withValues(
                                      alpha: 0.74,
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: NuvoColors.white.withValues(
                                    alpha: 0.18,
                                  ),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: NuvoColors.blue.withValues(
                                      alpha: 0.24,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  'Member pass active',
                                  style: AppTextStyles.labelSmall.copyWith(
                                    color: NuvoColors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Stats row
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: NuvoColors.white.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: NuvoColors.white.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Row(
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
                  ),
                ],
              ),
            ),
          ),

          // ── Profile body ──────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 112),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Race history
                const _SectionLabel(label: 'Race history'),
                const SizedBox(height: 12),

                if (raceState.loading && raceState.races.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: NuvoColors.blue,
                      ),
                    ),
                  )
                else if (raceState.races.isEmpty)
                  Text(
                    'Start your first race to build your history.',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: _kProfileTextMuted,
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
                const _SectionLabel(label: 'Account'),
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
            style: AppTextStyles.displaySmall.copyWith(
              color: NuvoColors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: _kProfileTextMuted,
              letterSpacing: 0,
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
    color: NuvoColors.white.withValues(alpha: 0.22),
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
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? _kProfileBlueBorder : _kProfileBorder,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x10050B14),
              blurRadius: 18,
              offset: Offset(0, 8),
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
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: isActive
                        ? NuvoColors.blue.withValues(alpha: 0.18)
                        : Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: isActive
                          ? NuvoColors.blue.withValues(alpha: 0.35)
                          : _kProfileBorder,
                    ),
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
    final bg = isDanger
        ? NuvoColors.danger.withValues(alpha: 0.10)
        : NuvoColors.icyBlue;

    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: NuvoColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDanger
                ? NuvoColors.danger.withValues(alpha: 0.30)
                : _kProfileBorder,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
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
                color: _kProfileTextMuted,
                size: 16,
              ),
          ],
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

// ── Helpers ───────────────────────────────────────────────────────────────────

String _statusLabel(String status) => switch (status) {
  'completed' || 'complete' || 'finished' => 'Finished',
  'archived' => 'Archived',
  'cancelled' => 'Cancelled',
  _ => status.replaceAll('_', ' '),
};

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/count_up_text.dart';
import '../../../core/widgets/nuvo_avatar.dart';
import '../../../core/widgets/nuvo_icons.dart';
import '../../../core/widgets/nuvo_shared_components.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../races/data/race_models.dart';
import '../../races/presentation/race_controller.dart';

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
      backgroundColor: NuvoColors.navy,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          // ── Navy header — never reveals white on overscroll ─────────────
          SliverToBoxAdapter(
            child: Container(
              decoration: const BoxDecoration(
                color: NuvoColors.navy,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
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
                        Hero(
                          tag: 'profile-avatar',
                          child: NuvoAvatar(
                            initials: initials,
                            photoUrl: photoUrl,
                            size: NuvoAvatarSizes.profile,
                            bgColor: NuvoColors.blue.withValues(alpha: 0.22),
                            textColor: NuvoColors.white,
                            borderColor: NuvoColors.blue.withValues(alpha: 0.55),
                          ),
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
                        _HeaderStat(value: activeCount, label: 'Active'),
                        _HeaderDivider(),
                        _HeaderStat(value: finishedCount, label: 'Finished'),
                        _HeaderDivider(),
                        _HeaderStat(value: moveCount, label: 'Moves'),
                        _HeaderDivider(),
                        _HeaderStat(value: avgProgress, label: 'Avg', suffix: '%'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Profile body — page-colored background ────────────────────────
          SliverFillRemaining(
            hasScrollBody: false,
            child: Container(
              color: NuvoColors.page,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 112),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _profileBody(raceState, uid, context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _profileBody(
    RaceState raceState,
    String? uid,
    BuildContext context,
  ) {
    return [
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
    ];
  }
}

// ── Header stat ───────────────────────────────────────────────────────────────

class _HeaderStat extends StatelessWidget {
  const _HeaderStat({required this.value, required this.label, this.suffix = ''});
  final int value;
  final String label;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value.toDouble()),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
            builder: (context, animated, _) => Text(
              '${animated.round()}$suffix',
              style: AppTextStyles.number(24, color: NuvoColors.white, weight: FontWeight.w800),
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
    final uid = userId;
    final myPart = uid != null ? race.participantFor(uid) : null;
    final pct = myPart?.progressPercent ?? 0;
    final isComplete = pct >= 100;
    final isActive = race.status == 'active' && !isComplete;
    final rank = _rankForUser(race, userId);
    final movementIcon = _movementIconData(race.aiActivityType);
    final lastAt = _lastActivityAt(race, userId);
    final racerCount = race.participantCount;
    final others = race.participants
        .where((p) => p.userId != userId)
        .take(3)
        .toList();
    final isCameraVerified = race.isAiMotionRace;

    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: NuvoColors.white,
          borderRadius: BorderRadius.circular(18),
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
            // Title row with movement icon and rank/status
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (movementIcon != null) ...[
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: NuvoColors.icyBlue,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      movementIcon,
                      color: NuvoColors.blue,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        race.displayTitle,
                        style: AppTextStyles.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _metaLine(
                          pct: pct,
                          racerCount: racerCount,
                          isCameraVerified: isCameraVerified,
                          lastAt: lastAt,
                        ),
                        style: AppTextStyles.bodySmall.copyWith(
                          color: NuvoColors.muted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (rank != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isComplete
                          ? NuvoColors.success.withValues(alpha: 0.10)
                          : NuvoColors.navy.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: CountUpText(
                      value: rank,
                      prefix: '#',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: isComplete
                            ? NuvoColors.success
                            : NuvoColors.navy,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isActive
                          ? NuvoColors.blue.withValues(alpha: 0.10)
                          : _kProfileBorder.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      isActive ? 'Active' : _statusLabel(race.status),
                      style: AppTextStyles.labelSmall.copyWith(
                        color: isActive ? NuvoColors.blue : NuvoColors.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: NuvoRaceLane(
                    progressPercent: pct,
                    trackHeight: 3,
                    dotDiameter: 9,
                  ),
                ),
                if (racerCount > 1) ...[
                  const SizedBox(width: 12),
                  NuvoAvatarStack(
                    avatars: others
                        .map(
                          (p) => (
                            initials: _initials(p.displayName),
                            photoUrl: p.profilePhotoUrl
                          ),
                        )
                        .toList(),
                    total: racerCount - 1,
                    size: 24,
                    max: 3,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _initials(String displayName) {
    final parts = displayName.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    final s = displayName.trim();
    return s.isEmpty ? '?' : s[0].toUpperCase();
  }

  static int? _rankForUser(Race race, String? userId) {
    if (userId == null) return null;
    final sorted = [...race.participants]
      ..sort((a, b) => b.progressPercent.compareTo(a.progressPercent));
    final idx = sorted.indexWhere((p) => p.userId == userId);
    return idx == -1 ? null : idx + 1;
  }

  static IconData? _movementIconData(String? aiActivityType) {
    return switch (aiActivityType) {
      'push_ups' || 'pushups' => Icons.fitness_center_rounded,
      'plank_hold' || 'plank' => Icons.straighten_rounded,
      'jumping_jacks' => Icons.accessibility_new_rounded,
      'squats' => Icons.person_outline_rounded,
      'lunges' => Icons.directions_walk_rounded,
      'high_knees' => Icons.directions_run_rounded,
      'arm_raises' => Icons.sports_gymnastics_rounded,
      _ => null,
    };
  }

  static String? _lastActivityAt(Race race, String? userId) {
    if (race.recentProofs.isEmpty) return null;
    final myProofs = userId != null
        ? race.recentProofs.where((p) => p.userId == userId).toList()
        : race.recentProofs;
    if (myProofs.isEmpty) return null;
    myProofs.sort(
      (a, b) => b.createdAt.compareTo(a.createdAt),
    );
    return myProofs.first.createdAt;
  }

  static String _metaLine({
    required int pct,
    required int racerCount,
    required bool isCameraVerified,
    required String? lastAt,
  }) {
    final parts = <String>[
      if (pct >= 100) 'Finished' else '$pct% complete',
      if (racerCount > 1) '$racerCount racers' else 'Solo',
      if (isCameraVerified) 'Camera verified',
    ];
    if (lastAt != null) {
      final ago = _timeAgo(lastAt);
      if (ago.isNotEmpty) parts.add(ago);
    }
    return parts.join(' · ');
  }

  static String _timeAgo(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inSeconds < 60) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return '';
    }
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
              const NuvoIcon(NuvoIconType.arrow, color: _kProfileTextMuted, size: 14),
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

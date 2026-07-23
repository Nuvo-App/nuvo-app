import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_geometry.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/bottom_nav.dart';
import '../../../core/widgets/count_up_text.dart';
import '../../../core/widgets/nuvo_avatar.dart';
import '../../../core/widgets/nuvo_icons.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../races/data/race_models.dart';
import '../../races/domain/race_display.dart';
import '../../races/presentation/race_controller.dart';

const _kProfileBorder = NuvoColors.border;
const _kProfileTextMuted = NuvoColors.muted;

const _kPrivacyUrl = 'https://getnuvo.net/privacy';
const _kTermsUrl = 'https://getnuvo.net/terms';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This will permanently delete your Nuvo account and log you out on all devices. '
          'This action cannot be undone from the app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: NuvoColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(authControllerProvider.notifier).deleteAccount();
      if (mounted) context.go('/welcome');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete account. Try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final displayName = user?.fullName ?? user?.email ?? '—';
    final username = user?.username != null ? '@${user!.username}' : null;
    final initials = user?.avatarInitials ?? '?';
    final photoUrl = user?.profilePhotoUrl;
    final uid = user?.id;

    final raceState = ref.watch(raceControllerProvider);
    final activeCount = raceState.races.where(raceIsActive).length;
    final finishedCount = raceState.races.where(raceIsCompleted).length;
    final moveCount = raceState.races.fold<int>(
      0,
      (s, r) => s + r.recentProofs.length,
    );
    final progressValues = uid == null
        ? <int>[]
        : raceState.races
              .map((r) => r.participantFor(uid)?.progressPercent)
              .whereType<int>()
              .toList();
    final avgProgress = progressValues.isEmpty
        ? 0
        : (progressValues.fold<int>(0, (s, v) => s + v) / progressValues.length)
              .round();

    final safeTop = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              padding: EdgeInsets.fromLTRB(22, safeTop + 20, 22, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top row: label + edit
                  Row(
                    children: [
                      Text(
                        'Profile',
                        style: AppTextStyles.headlineLarge.copyWith(
                          color: NuvoColors.navy,
                          fontSize: 32,
                          letterSpacing: -0.9,
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
                            color: NuvoColors.panel,
                            borderRadius: BorderRadius.circular(NuvoRadii.pill),
                            border: NuvoBorders.quiet,
                          ),
                          child: Text(
                            'Edit',
                            style: AppTextStyles.labelMedium.copyWith(
                              color: NuvoColors.navy,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),

                  // Avatar + name
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          NuvoColors.icyBlue,
                          NuvoColors.surface,
                          NuvoColors.surface,
                        ],
                        stops: [0, 0.42, 1],
                      ),
                      borderRadius: BorderRadius.circular(NuvoRadii.hero),
                      border: Border.all(color: NuvoColors.navy, width: 2),
                      boxShadow: const [
                        BoxShadow(
                          color: NuvoColors.navy,
                          blurRadius: 0,
                          offset: Offset(4, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Hero(
                          tag: 'profile-avatar',
                          child: NuvoAvatar(
                            initials: initials,
                            photoUrl: photoUrl,
                            size: NuvoAvatarSizes.xl,
                            bgColor: NuvoColors.panel,
                            textColor: NuvoColors.navy,
                            borderColor: NuvoColors.border,
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
                                  color: NuvoColors.navy,
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (username != null) ...[
                                const SizedBox(height: 5),
                                Text(
                                  username,
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    color: NuvoColors.textMuted,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    color: NuvoColors.blue,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Member pass active',
                                    style: AppTextStyles.labelSmall.copyWith(
                                      color: NuvoColors.navy,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Stats row
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: NuvoColors.panel,
                      borderRadius: BorderRadius.circular(NuvoRadii.lg),
                      border: NuvoBorders.quiet,
                    ),
                    child: Row(
                      children: [
                        _HeaderStat(value: activeCount, label: 'Active'),
                        _HeaderDivider(),
                        _HeaderStat(value: finishedCount, label: 'Finished'),
                        _HeaderDivider(),
                        _HeaderStat(value: moveCount, label: 'Moves'),
                        _HeaderDivider(),
                        _HeaderStat(
                          value: avgProgress,
                          label: 'Avg',
                          suffix: '%',
                        ),
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
              padding: EdgeInsets.fromLTRB(
                20,
                18,
                20,
                NuvoBottomNav.bottomPadding(context),
              ),
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
    final races = raceState.races.take(6).toList();
    final activeRaces = races.where(raceIsActive).toList();
    final finishedRaces = races.where(raceIsCompleted).toList();
    final otherRaces = races
        .where((race) => !raceIsActive(race) && !raceIsCompleted(race))
        .toList();

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
          style: AppTextStyles.bodyMedium.copyWith(color: _kProfileTextMuted),
        )
      else ...[
        if (activeRaces.isNotEmpty) ...[
          const _SubsectionLabel(label: 'Active'),
          const SizedBox(height: 8),
          _ProfileRaceGroup(races: activeRaces, userId: uid),
        ],
        if (finishedRaces.isNotEmpty) ...[
          SizedBox(height: activeRaces.isEmpty ? 0 : 14),
          const _SubsectionLabel(label: 'Finished'),
          const SizedBox(height: 8),
          _ProfileRaceGroup(races: finishedRaces, userId: uid),
        ],
        if (otherRaces.isNotEmpty) ...[
          SizedBox(
            height: activeRaces.isEmpty && finishedRaces.isEmpty ? 0 : 14,
          ),
          const _SubsectionLabel(label: 'Other'),
          const SizedBox(height: 8),
          _ProfileRaceGroup(races: otherRaces, userId: uid),
        ],
      ],

      const SizedBox(height: 24),

      // Account
      const _SectionLabel(label: 'Account'),
      const SizedBox(height: 12),
      _AccountRow(
        icon: Icons.badge_rounded,
        label: 'Member pass',
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
        onTap: () => ref.read(authControllerProvider.notifier).logout(),
      ),
      const SizedBox(height: 8),
      _AccountRow(
        icon: Icons.delete_outline_rounded,
        label: 'Delete account',
        isDanger: true,
        onTap: _confirmDeleteAccount,
      ),
      const SizedBox(height: 24),

      // Legal
      const _SectionLabel(label: 'Legal'),
      const SizedBox(height: 12),
      _AccountRow(
        icon: Icons.policy_rounded,
        label: 'Privacy Policy',
        onTap: () => _openUrl(_kPrivacyUrl),
      ),
      const SizedBox(height: 8),
      _AccountRow(
        icon: Icons.description_rounded,
        label: 'Terms of Service',
        onTap: () => _openUrl(_kTermsUrl),
      ),
    ];
  }
}

// ── Header stat ───────────────────────────────────────────────────────────────

class _HeaderStat extends StatelessWidget {
  const _HeaderStat({
    required this.value,
    required this.label,
    this.suffix = '',
  });
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
              style: AppTextStyles.number(
                24,
                color: NuvoColors.navy,
                weight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: NuvoColors.muted,
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
    color: NuvoColors.navy.withValues(alpha: 0.12),
    margin: const EdgeInsets.symmetric(horizontal: 4),
  );
}

class _SubsectionLabel extends StatelessWidget {
  const _SubsectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: AppTextStyles.labelMedium.copyWith(
        color: NuvoColors.textMuted,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _ProfileRaceGroup extends StatelessWidget {
  const _ProfileRaceGroup({required this.races, this.userId});

  final List<Race> races;
  final String? userId;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: NuvoColors.border, width: 1.25),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < races.length; i++) ...[
            _ProfileRaceRow(
              race: races[i],
              userId: userId,
              onTap: () => context.push('/race/${races[i].id}'),
            ),
            if (i < races.length - 1)
              const Divider(
                height: 1,
                thickness: 1,
                indent: 64,
                color: NuvoColors.divider,
              ),
          ],
        ],
      ),
    );
  }
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
    final pct = raceProgressPercent(race, myPart);
    final isComplete = raceIsCompleted(race);
    final isActive = raceIsActive(race);
    final rank = rankForUser(race, userId);
    final movementIcon = _movementIconData(
      race.activityId ?? race.aiActivityType,
    );
    final lastAt = _lastActivityAt(race, userId);
    final racerCount = race.participantCount;
    final isCameraVerified = race.isAiMotionRace;

    return PressableScale(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 78),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        color: isComplete
            ? NuvoColors.success.withValues(alpha: 0.05)
            : isActive
            ? NuvoColors.surface
            : NuvoColors.panel,
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
                    child: Icon(movementIcon, color: NuvoColors.blue, size: 18),
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
                          scoreLabel: raceProgressLabel(race, myPart),
                          isComplete: isComplete,
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
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(NuvoRadii.pill),
              child: LinearProgressIndicator(
                value: (pct / 100).clamp(0.0, 1.0),
                minHeight: 3,
                color: isComplete ? NuvoColors.success : NuvoColors.blue,
                backgroundColor: NuvoColors.trackBg,
              ),
            ),
          ],
        ),
      ),
    );
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
    myProofs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return myProofs.first.createdAt;
  }

  static String _metaLine({
    required String scoreLabel,
    required bool isComplete,
    required int racerCount,
    required bool isCameraVerified,
    required String? lastAt,
  }) {
    final parts = <String>[
      if (isComplete) 'Finished' else scoreLabel,
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: NuvoColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: NuvoBorders.quiet,
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
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
              const NuvoIcon(
                NuvoIconType.arrow,
                color: _kProfileTextMuted,
                size: 14,
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
    return Text(
      label,
      style: AppTextStyles.titleMedium.copyWith(
        color: NuvoColors.navy,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
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

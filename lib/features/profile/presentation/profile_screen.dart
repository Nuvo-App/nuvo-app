import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_geometry.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/bottom_nav.dart';
import '../../../core/widgets/nuvo_avatar.dart';
import '../../../core/widgets/nuvo_confirm_dialog.dart';
import '../../../core/widgets/nuvo_error_state.dart';
import '../../../core/widgets/nuvo_icons.dart';
import '../../../core/widgets/nuvo_race_components.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../onboarding/presentation/first_use_guide.dart';
import '../../races/data/race_models.dart';
import '../../races/domain/race_display.dart';
import '../../races/presentation/race_controller.dart';

const _kProfileTextMuted = NuvoColors.muted;

const _kPrivacyUrl = 'https://getnuvo.net/privacy';
const _kTermsUrl = 'https://getnuvo.net/terms';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  static const _demoAccountEmails = {
    'sideswifter2010@gmai.com',
    'sideswifter2010@gmail.com',
  };

  Future<void> _replayDemo() async {
    ref.read(firstRaceGuideProvider.notifier).state =
        FirstRaceGuideStep.competeStart;
    ref.read(demoReplayProvider.notifier).state = true;
    if (mounted) context.go('/splash');
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showNuvoConfirmDialog(
      context,
      title: 'Delete account?',
      message:
          'This will permanently delete your Nuvo account and log you out on all devices. '
          'This action cannot be undone from the app.',
      confirmLabel: 'Delete',
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
    final canReplayDemo =
        user != null &&
        (_demoAccountEmails.contains(user.email.trim().toLowerCase()) ||
            user.username?.trim().toLowerCase() == 'akshay');

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

    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.fromLTRB(22, 32, 22, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top row: label + edit
                  Row(
                    children: [
                      Text('Profile', style: AppTextStyles.screenTitle),
                      const Spacer(),
                      PressableScale(
                        onTap: () => context.push('/profile/edit'),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 36),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
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
                  const SizedBox(height: 20),

                  // Avatar + name — plain layout, no card surface
                  Row(
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
                            const SizedBox(height: NuvoSpacing.sm),
                            Row(
                              children: [
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: NuvoColors.blue,
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    'Member pass active',
                                    style: AppTextStyles.labelSmall.copyWith(
                                      color: NuvoColors.navy,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Stats row
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: NuvoColors.panel,
                      borderRadius: BorderRadius.circular(NuvoRadii.lg),
                      border: NuvoBorders.hero,
                    ),
                    child: Row(
                      children: [
                        _HeaderStat(
                          value: activeCount,
                          label: 'Active',
                          color: NuvoColors.blue,
                        ),
                        _HeaderDivider(),
                        _HeaderStat(
                          value: finishedCount,
                          label: 'Finished',
                          color: NuvoColors.success,
                        ),
                        _HeaderDivider(),
                        _HeaderStat(
                          value: moveCount,
                          label: 'Moves',
                          color: NuvoColors.warning,
                        ),
                        _HeaderDivider(),
                        _HeaderStat(
                          value: avgProgress,
                          label: 'Avg',
                          suffix: '%',
                          color: NuvoColors.gold,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Profile body — page-colored background ────────────────────────
          SliverToBoxAdapter(
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
                children: _profileBody(
                  raceState,
                  uid,
                  context,
                  canReplayDemo: canReplayDemo,
                ),
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
    BuildContext context, {
    required bool canReplayDemo,
  }) {
    final races = raceState.races.take(6).toList();
    final activeRaces = races.where(raceIsActive).toList();
    final finishedRaces = races.where(raceIsCompleted).toList();
    final otherRaces = races
        .where((race) => !raceIsActive(race) && !raceIsCompleted(race))
        .toList();

    return [
      // Race history
      const _SectionLabel(label: 'Race history'),
      const SizedBox(height: NuvoSpacing.md),

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
      else if (raceState.races.isEmpty && raceState.error != null)
        // Load failed with nothing cached — say so, don't imply "no races".
        NuvoErrorState(
          message: "Couldn't load your race history.",
          onRetry: () =>
              ref.read(raceControllerProvider.notifier).loadRaces(),
        )
      else if (raceState.races.isEmpty)
        Text(
          'Start your first race to build your history.',
          style: AppTextStyles.bodyMedium.copyWith(color: _kProfileTextMuted),
        )
      else ...[
        if (activeRaces.isNotEmpty) ...[
          const _SubsectionLabel(label: 'Active'),
          const SizedBox(height: NuvoSpacing.sm),
          _ProfileRaceGroup(races: activeRaces, userId: uid),
        ],
        if (finishedRaces.isNotEmpty) ...[
          SizedBox(height: activeRaces.isEmpty ? 0 : 14),
          const _SubsectionLabel(label: 'Finished'),
          const SizedBox(height: NuvoSpacing.sm),
          _ProfileRaceGroup(races: finishedRaces, userId: uid),
        ],
        if (otherRaces.isNotEmpty) ...[
          SizedBox(
            height: activeRaces.isEmpty && finishedRaces.isEmpty ? 0 : 14,
          ),
          const _SubsectionLabel(label: 'Other'),
          const SizedBox(height: NuvoSpacing.sm),
          _ProfileRaceGroup(races: otherRaces, userId: uid),
        ],
      ],

      const SizedBox(height: NuvoSpacing.xxl),

      // Account
      const _SectionLabel(label: 'Account'),
      const SizedBox(height: NuvoSpacing.md),
      _AccountRow(
        icon: Icons.badge_rounded,
        label: 'Member pass',
        onTap: () => context.go('/pass'),
      ),
      if (canReplayDemo) ...[
        const SizedBox(height: NuvoSpacing.sm),
        _AccountRow(
          icon: Icons.replay_rounded,
          label: 'Replay demo',
          onTap: _replayDemo,
        ),
      ],
      const SizedBox(height: NuvoSpacing.sm),
      _AccountRow(
        icon: Icons.logout_rounded,
        label: 'Sign out',
        isDanger: true,
        onTap: () => ref.read(authControllerProvider.notifier).logout(),
      ),
      const SizedBox(height: NuvoSpacing.sm),
      _AccountRow(
        icon: Icons.delete_outline_rounded,
        label: 'Delete account',
        isDanger: true,
        isDestructiveLowEmphasis: true,
        onTap: _confirmDeleteAccount,
      ),
      const SizedBox(height: NuvoSpacing.xxl),

      // Legal
      const _SectionLabel(label: 'Legal'),
      const SizedBox(height: NuvoSpacing.md),
      _AccountRow(
        icon: Icons.policy_rounded,
        label: 'Privacy Policy',
        onTap: () => _openUrl(_kPrivacyUrl),
      ),
      const SizedBox(height: NuvoSpacing.sm),
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
    this.color = NuvoColors.navy,
  });
  final int value;
  final String label;
  final String suffix;
  final Color color;

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
                color: color,
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
        borderRadius: BorderRadius.circular(NuvoRadii.lg),
        border: NuvoBorders.hero,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < races.length; i++) ...[
            _buildRow(context, races[i]),
            if (i < races.length - 1)
              const Divider(
                height: 1,
                thickness: 1,
                indent: 54,
                color: NuvoColors.divider,
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildRow(BuildContext context, Race race) {
    final uid = userId;
    final myPart = uid != null ? race.participantFor(uid) : null;
    final pct = raceProgressPercent(race, myPart);
    final rank = rankForUser(race, userId);
    final activity = raceActivityTitle(race);
    final progressLabel = raceProgressLabel(race, myPart);
    final isComplete = raceIsCompleted(race);

    final avatars = race.participants.where((p) => p.userId != userId).map((p) {
      final name = p.displayName.trim();
      final initials = name.isEmpty
          ? '?'
          : name
                .split(RegExp(r'\s+'))
                .where((w) => w.isNotEmpty)
                .take(2)
                .map((w) => w[0].toUpperCase())
                .join();
      return (initials: initials, photoUrl: p.profilePhotoUrl, id: p.userId);
    }).toList();

    if (isComplete) {
      return RaceResultRow(
        raceTitle: race.displayTitle,
        movementLabel: activity,
        rank: rank,
        participantCount: race.participantCount,
        avatars: avatars,
        onTap: () => context.push('/race/${race.id}'),
      );
    }

    return RaceRow(
      raceTitle: race.displayTitle,
      movementLabel: activity,
      progressLabel: progressLabel,
      progressPercent: pct,
      rank: rank,
      participantCount: race.participantCount,
      avatars: avatars,
      onTap: () => context.push('/race/${race.id}'),
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
    this.isDestructiveLowEmphasis = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDanger;
  final bool isDestructiveLowEmphasis;

  @override
  Widget build(BuildContext context) {
    final color = isDestructiveLowEmphasis
        ? NuvoColors.muted
        : (isDanger ? NuvoColors.danger : NuvoColors.navy);
    final bg = isDestructiveLowEmphasis
        ? NuvoColors.panel
        : (isDanger
              ? NuvoColors.danger.withValues(alpha: 0.10)
              : NuvoColors.icyBlue);

    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: NuvoColors.surface,
          borderRadius: BorderRadius.circular(NuvoRadii.card),
          border: NuvoBorders.hero,
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(NuvoRadii.xs),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: NuvoSpacing.md),
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.bodyMedium.copyWith(color: color),
              ),
            ),
            if (!isDanger && !isDestructiveLowEmphasis)
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

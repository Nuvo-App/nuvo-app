import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_geometry.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/bottom_nav.dart';
import '../../../core/widgets/count_up_text.dart';
import '../../../core/widgets/nuvo_avatar.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../races/data/race_models.dart';
import '../../races/domain/race_display.dart';
import '../../races/presentation/race_controller.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// PROFILE — Light-Mode "Athlete Identity"
// Premium light athlete profile with performance halo and achievement visuals.
// ═══════════════════════════════════════════════════════════════════════════════

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

    final safeTop = MediaQuery.viewPaddingOf(context).top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: NuvoColors.page,
        body: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: NuvoBottomNav.bottomPadding(context),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Header ────────────────────────────────────────
                    _ProfileHeader(safeTop: safeTop),

                    // ── Identity card ────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                      child: _IdentityCard(
                        displayName: displayName,
                        username: username,
                        initials: initials,
                        photoUrl: photoUrl,
                        avgProgress: avgProgress,
                        finishedCount: finishedCount,
                        onEdit: () => context.push('/profile/edit'),
                      ),
                    ),

                    // ── Stats ──────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: _StatsRow(
                        activeCount: activeCount,
                        finishedCount: finishedCount,
                        moveCount: moveCount,
                        avgProgress: avgProgress,
                      ),
                    ),

                    // ── Race history ─────────────────────────────────
                    const _SectionLabel(title: 'Race history'),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _raceHistory(raceState, uid, context),
                    ),

                    // ── Account ──────────────────────────────────────
                    const _SectionLabel(title: 'Account'),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _AccountGroup(
                        items: [
                          _AccountItem(
                            icon: Icons.badge_rounded,
                            label: 'Member pass',
                            onTap: () => context.go('/pass'),
                          ),
                          _AccountItem(
                            icon: Icons.edit_rounded,
                            label: 'Edit profile',
                            onTap: () => context.push('/profile/edit'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _AccountGroup(
                        items: [
                          _AccountItem(
                            icon: Icons.logout_rounded,
                            label: 'Sign out',
                            isDanger: true,
                            onTap: () => ref
                                .read(authControllerProvider.notifier)
                                .logout(),
                          ),
                          _AccountItem(
                            icon: Icons.delete_outline_rounded,
                            label: 'Delete account',
                            isDanger: true,
                            onTap: _confirmDeleteAccount,
                          ),
                        ],
                      ),
                    ),

                    // ── Legal ─────────────────────────────────────────
                    const _SectionLabel(title: 'Legal'),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _AccountGroup(
                        items: [
                          _AccountItem(
                            icon: Icons.policy_rounded,
                            label: 'Privacy Policy',
                            onTap: () => _openUrl(_kPrivacyUrl),
                          ),
                          _AccountItem(
                            icon: Icons.description_rounded,
                            label: 'Terms of Service',
                            onTap: () => _openUrl(_kTermsUrl),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _raceHistory(
    RaceState raceState,
    String? uid,
    BuildContext context,
  ) {
    final races = raceState.races.take(8).toList();
    final activeRaces = races.where(raceIsActive).toList();
    final finishedRaces = races.where(raceIsCompleted).toList();

    if (raceState.loading && raceState.races.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: NuvoColors.blue,
          ),
        ),
      );
    }

    if (raceState.races.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        decoration: BoxDecoration(
          color: NuvoColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: NuvoColors.border, width: 1),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: NuvoColors.blue.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.history_rounded,
                color: NuvoColors.blue,
                size: 22,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Start your first race to build your history.',
              style: AppTextStyles.bodyMedium.copyWith(
                color: NuvoColors.textMuted,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (activeRaces.isNotEmpty) ...[
          _SubLabel(label: 'Active', color: NuvoColors.blue),
          const SizedBox(height: 8),
          _ProfileRaceGroup(races: activeRaces, userId: uid),
        ],
        if (finishedRaces.isNotEmpty) ...[
          SizedBox(height: activeRaces.isEmpty ? 0 : 14),
          _SubLabel(label: 'Finished', color: NuvoColors.success),
          const SizedBox(height: 8),
          _ProfileRaceGroup(races: finishedRaces, userId: uid),
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// HEADER
// ═══════════════════════════════════════════════════════════════════════════════

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.safeTop});
  final double safeTop;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(22, safeTop + 14, 22, 16),
      child: Row(
        children: [
          Text(
            'NUVO',
            style: AppTextStyles.labelSmall.copyWith(
              color: NuvoColors.blue,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.0,
              fontSize: 10,
            ),
          ),
          const Spacer(),
          Text(
            'Profile',
            style: AppTextStyles.screenTitle.copyWith(
              color: NuvoColors.navy,
              fontSize: 34,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// IDENTITY CARD — Signature component
// ═══════════════════════════════════════════════════════════════════════════════

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({
    required this.displayName,
    required this.username,
    required this.initials,
    required this.photoUrl,
    required this.avgProgress,
    required this.finishedCount,
    required this.onEdit,
  });
  final String displayName;
  final String? username;
  final String initials;
  final String? photoUrl;
  final int avgProgress;
  final int finishedCount;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: NuvoColors.border, width: 1),
        boxShadow: AppShadows.heroShadow,
      ),
      child: Row(
        children: [
          // Performance Halo — multi-layered progress rings around avatar
          SizedBox(
            width: 82,
            height: 82,
            child: CustomPaint(
              painter: _PerformanceHaloPainter(
                avgProgress: avgProgress,
                finishedCount: finishedCount,
              ),
              child: Center(
                child: Hero(
                  tag: 'profile-avatar',
                  child: NuvoAvatar(
                    initials: initials,
                    photoUrl: photoUrl,
                    size: 52,
                    bgColor: NuvoColors.panel,
                    textColor: NuvoColors.navy,
                    borderColor: NuvoColors.border,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: AppTextStyles.headlineMedium.copyWith(
                    color: NuvoColors.navy,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (username != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    username!,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: NuvoColors.textMuted,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: NuvoColors.blue,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: NuvoColors.blue.withValues(alpha: 0.4),
                            blurRadius: 4,
                          ),
                        ],
                      ),
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
          PressableScale(
            onTap: onEdit,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: NuvoColors.blue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: NuvoColors.blue.withValues(alpha: 0.15),
                ),
              ),
              child: Text(
                'Edit',
                style: AppTextStyles.labelMedium.copyWith(
                  color: NuvoColors.blue,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Performance Halo — Multi-layered concentric progress rings.
/// Outer ring: average race progress (blue arc).
/// Middle ring: completion indicator (tick marks for finished races).
/// Inner ring: subtle grid for depth.
/// Inspired by Arena's orbital ring geometry.
class _PerformanceHaloPainter extends CustomPainter {
  _PerformanceHaloPainter({
    required this.avgProgress,
    required this.finishedCount,
  });
  final int avgProgress;
  final int finishedCount;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2 - 2;
    final middleRadius = outerRadius - 6;

    // Outer ring background
    canvas.drawCircle(
      center,
      outerRadius,
      Paint()
        ..color = const Color(0xFFE8ECF2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    // Outer ring: average progress arc
    if (avgProgress > 0) {
      final sweep = (avgProgress / 100) * 2 * math.pi;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: outerRadius),
        -math.pi / 2,
        sweep,
        false,
        Paint()
          ..color = NuvoColors.blue
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }

    // Middle ring: faint grid for depth
    canvas.drawCircle(
      center,
      middleRadius,
      Paint()
        ..color = NuvoColors.blue.withValues(alpha: 0.04)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Achievement tick marks (one per finished race, max 12)
    final ticks = finishedCount.clamp(0, 12);
    for (var i = 0; i < ticks; i++) {
      final angle = (i / 12) * 2 * math.pi - math.pi / 2;
      final inner = middleRadius - 2;
      final outer = middleRadius + 2;
      canvas.drawLine(
        Offset(center.dx + inner * math.cos(angle),
            center.dy + inner * math.sin(angle)),
        Offset(center.dx + outer * math.cos(angle),
            center.dy + outer * math.sin(angle)),
        Paint()
          ..color = NuvoColors.success.withValues(alpha: 0.6)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }

    // Progress indicator dot at the arc tip
    if (avgProgress > 0) {
      final dotAngle = (avgProgress / 100) * 2 * math.pi - math.pi / 2;
      final dotX = center.dx + outerRadius * math.cos(dotAngle);
      final dotY = center.dy + outerRadius * math.sin(dotAngle);
      canvas.drawCircle(
        Offset(dotX, dotY), 4,
        Paint()..color = NuvoColors.blue,
      );
      canvas.drawCircle(
        Offset(dotX, dotY), 6,
        Paint()..color = NuvoColors.blue.withValues(alpha: 0.15),
      );
    }
  }

  @override
  bool shouldRepaint(_PerformanceHaloPainter old) =>
      old.avgProgress != avgProgress || old.finishedCount != finishedCount;
}

// ═══════════════════════════════════════════════════════════════════════════════
// STATS ROW
// ═══════════════════════════════════════════════════════════════════════════════

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.activeCount,
    required this.finishedCount,
    required this.moveCount,
    required this.avgProgress,
  });
  final int activeCount;
  final int finishedCount;
  final int moveCount;
  final int avgProgress;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: NuvoColors.border, width: 1),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          _StatCell(value: activeCount, label: 'Active'),
          _StatDivider(),
          _StatCell(value: finishedCount, label: 'Finished'),
          _StatDivider(),
          _StatCell(value: moveCount, label: 'Moves'),
          _StatDivider(),
          _StatCell(value: avgProgress, label: 'Avg %'),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.value, required this.label});
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value.toDouble()),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
            builder: (context, animated, _) => Text(
              '${animated.round()}',
              style: AppTextStyles.number(
                22,
                color: NuvoColors.navy,
                weight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: NuvoColors.textMuted,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 28,
      color: NuvoColors.divider,
      margin: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION LABEL
// ═══════════════════════════════════════════════════════════════════════════════

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 14),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: NuvoColors.blue,
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            title.toUpperCase(),
            style: AppTextStyles.labelSmall.copyWith(
              color: NuvoColors.textMuted,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

class _SubLabel extends StatelessWidget {
  const _SubLabel({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: AppTextStyles.labelMedium.copyWith(
            color: NuvoColors.textMuted,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// RACE GROUP
// ═══════════════════════════════════════════════════════════════════════════════

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
        border: Border.all(color: NuvoColors.border, width: 1),
        boxShadow: AppShadows.card,
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
                indent: 50,
                color: NuvoColors.divider,
              ),
          ],
        ],
      ),
    );
  }
}

class _ProfileRaceRow extends StatelessWidget {
  const _ProfileRaceRow({
    required this.race,
    required this.onTap,
    this.userId,
  });
  final Race race;
  final String? userId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final uid = userId;
    final myPart = uid != null ? race.participantFor(uid) : null;
    final isComplete = raceIsCompleted(race);
    final isActive = raceIsActive(race);
    final rank = rankForUser(race, userId);
    final movementIcon = _movementIconData(
      race.activityId ?? race.aiActivityType,
    );

    return PressableScale(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: [
            // Activity icon
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isComplete
                    ? NuvoColors.success.withValues(alpha: 0.08)
                    : isActive
                        ? NuvoColors.blue.withValues(alpha: 0.08)
                        : NuvoColors.panelLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                movementIcon ?? Icons.emoji_events_rounded,
                color: isComplete
                    ? NuvoColors.success
                    : isActive
                        ? NuvoColors.blue
                        : NuvoColors.textMuted,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    race.displayTitle,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: NuvoColors.navy,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    raceProgressLabel(race, myPart),
                    style: AppTextStyles.bodySmall.copyWith(
                      color: NuvoColors.textMuted,
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
                      ? NuvoColors.success.withValues(alpha: 0.08)
                      : NuvoColors.panelLight,
                  borderRadius: BorderRadius.circular(NuvoRadii.pill),
                ),
                child: CountUpText(
                  value: rank,
                  prefix: '#',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: isComplete ? NuvoColors.success : NuvoColors.navy,
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
                      ? NuvoColors.blue.withValues(alpha: 0.08)
                      : NuvoColors.panelLight,
                  borderRadius: BorderRadius.circular(NuvoRadii.pill),
                ),
                child: Text(
                  isActive ? 'Active' : _statusLabel(race.status),
                  style: AppTextStyles.labelSmall.copyWith(
                    color: isActive ? NuvoColors.blue : NuvoColors.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
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
}

// ═══════════════════════════════════════════════════════════════════════════════
// ACCOUNT GROUP
// ═══════════════════════════════════════════════════════════════════════════════

class _AccountItem {
  const _AccountItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDanger = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDanger;
}

class _AccountGroup extends StatelessWidget {
  const _AccountGroup({required this.items});
  final List<_AccountItem> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: NuvoColors.border, width: 1),
        boxShadow: AppShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            _AccountRow(
              icon: items[i].icon,
              label: items[i].label,
              onTap: items[i].onTap,
              isDanger: items[i].isDanger,
            ),
            if (i < items.length - 1)
              const Divider(
                height: 1,
                thickness: 1,
                indent: 56,
                color: NuvoColors.divider,
              ),
          ],
        ],
      ),
    );
  }
}

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
    final bgColor = isDanger
        ? NuvoColors.danger.withValues(alpha: 0.08)
        : NuvoColors.blue.withValues(alpha: 0.06);

    return PressableScale(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(10),
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
                color: NuvoColors.textMuted,
                size: 18,
              ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════════════════════════

String _statusLabel(String status) => switch (status) {
  'completed' || 'complete' || 'finished' => 'Finished',
  'archived' => 'Archived',
  'cancelled' => 'Cancelled',
  _ => status.replaceAll('_', ' '),
};

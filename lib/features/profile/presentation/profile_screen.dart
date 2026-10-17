import 'widgets/activity_heatmap.dart';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/demo/presentation_demo.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_geometry.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/nuvo_entrance.dart';
import '../../../core/theme/nuvo_theme_mode.dart';
import '../../../core/widgets/bottom_nav.dart';
import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/widgets/nuvo_avatar.dart';
import '../../../core/widgets/nuvo_back_header.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_confirm_dialog.dart';
import '../../../core/widgets/nuvo_icons.dart';
import '../../../core/widgets/nuvo_motion.dart';
import '../../../core/widgets/nuvo_number_flow.dart';
import '../../../core/widgets/nuvo_toggle.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../arena/presentation/arena_controller.dart';
import '../../auth/data/auth_api.dart';
import '../../auth/data/auth_models.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../onboarding/presentation/first_use_guide.dart';
import '../../races/domain/race_display.dart';
import '../../races/presentation/race_controller.dart';
import '../application/progression_controller.dart';
import '../data/progression_models.dart';
import 'widgets/nuvo_badges.dart';

part 'settings_screen.dart';

const _kPrivacyUrl = 'https://getnuvo.net/privacy';
const _kTermsUrl = 'https://getnuvo.net/terms';

/// Profile — "who am I on Nuvo, and what have I done?"
///
/// Information order: identity → level → achievements → record → Your Nuvo.
/// Racing now and recent results live on Compete and Crew; account, privacy
/// and legal live in [SettingsScreen].
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _progressionRetryScheduled = false;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    ref.watch(presentationModeEnabledProvider);
    // The level-up moment lives on MainShell — it fires wherever a race
    // action revalidates progression across a threshold.
    final progressionAsync = ref.watch(progressionControllerProvider);
    final progression = progressionAsync.valueOrNull;
    // Retry a failed first read once per visit — a transient progression
    // outage must never leave the level section permanently blank.
    if (!_progressionRetryScheduled &&
        !progressionAsync.hasValue &&
        !progressionAsync.isLoading) {
      _progressionRetryScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(progressionControllerProvider.notifier).load(force: false);
        }
      });
    }
    final authUser = ref.watch(authControllerProvider).user;
    final user = authUser == null ? null : presentedUser(authUser);
    final uid = user?.id;

    final raceState = ref.watch(raceControllerProvider);
    final guide = ref.watch(firstRaceGuideProvider);
    final activeCount = raceState.races.where(raceIsActive).length;
    final finishedRaces = raceState.races.where(raceIsCompleted).toList();
    // Wins come only from server-owned truth: the recorded winner, or a
    // #1 entry in final standings (covers tied-for-first, where the server
    // leaves winnerUserId null). A cancelled race's positional rank never
    // counts as a win.
    final wins = uid == null
        ? 0
        : finishedRaces
              .where(
                (r) =>
                    r.winnerUserId == uid ||
                    r.finalStandings.any((s) => s.userId == uid && s.rank == 1),
              )
              .length;
    final winRate = finishedRaces.isEmpty
        ? null
        : (wins / finishedRaces.length * 100).round();

    final screen = Scaffold(
      backgroundColor: c.page,
      body: RefreshIndicator(
        color: NuvoColors.blue,
        backgroundColor: c.surface,
        onRefresh: () => Future.wait([
          ref.read(raceControllerProvider.notifier).loadRaces(),
          ref.read(progressionControllerProvider.notifier).load(),
        ]),
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  NuvoSpacing.pageHorizontal,
                  32,
                  NuvoSpacing.pageHorizontal,
                  NuvoBottomNav.bottomPadding(context),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Profile',
                      style: AppTextStyles.screenTitle.copyWith(color: c.ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: NuvoSpacing.lg),

                    // Identity — the person, not the account. Settings and
                    // everything administrative live one tap away.
                    _IdentityCard(
                      user: user,
                      level: progression?.level,
                    ).nuvoEnter(),
                    const SizedBox(height: NuvoSpacing.lg),

                    // Level — the progression that belongs to the person,
                    // not any one race. Tap it for what the level means.
                    _LevelTrack(
                      key: FirstRaceGuideKeys.profileProgress,
                      state: progressionAsync,
                    ).nuvoEnter(),
                    const SizedBox(height: NuvoSpacing.lg),

                    // Achievements are one row — the collection, the next
                    // goal and the next unlock live behind it.
                    _AchievementsRow(progression: progression),

                    // The record — racing now, wins, win rate — then the
                    // activity heat map.
                    const SizedBox(height: NuvoSpacing.xl),
                    _StatsStrip(
                      activeCount: activeCount,
                      wins: wins,
                      winRate: winRate,
                    ),
                    const ActivityHeatmapSection(),
                    const SizedBox(height: NuvoSpacing.xl),

                    // Your Nuvo — the things that are mine and how the app
                    // feels. Account, privacy and legal live in Settings.
                    const _SectionLabel(label: 'Your Nuvo'),
                    const SizedBox(height: NuvoSpacing.md),
                    _ProfileActionGroup(
                      children: [
                        _AccountRow(
                          icon: Icons.qr_code_2_rounded,
                          label: 'My code',
                          subtitle: 'Your code and pass link',
                          onTap: () => context.push('/my-nuvo'),
                        ),
                        _AccountRow(
                          icon: Icons.notifications_outlined,
                          label: 'Notifications',
                          subtitle: 'Race and crew updates',
                          onTap: () =>
                              context.push('/settings/notifications'),
                        ),
                        const _AppearanceRow(),
                        _AccountRow(
                          icon: Icons.settings_outlined,
                          label: 'Settings',
                          subtitle: 'Account, privacy and legal',
                          onTap: () => context.push('/settings'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    // Final guided step: the first proof just landed — point at the real
    // progression it moved, then 'Got it' completes the guide for good.
    if (guide == FirstRaceGuideStep.profileReward) {
      return Stack(
        children: [
          screen,
          FirstRaceGuideCoach(
            step: FirstRaceGuideStep.profileReward,
            targetKey: FirstRaceGuideKeys.profileProgress,
            eyebrow: 'PROOF LANDED',
            title: 'You’re on the board.',
            body: 'Every verified effort moves your profile forward.',
            actionLabel: 'Got it',
          ),
        ],
      );
    }
    return screen;
  }
}

// ── Identity ──────────────────────────────────────────────────────────────────

/// Who I am on Nuvo: avatar, name, handle and level. The user is the hero —
/// this lives directly on the page, no card around it. Sharing the identity
/// is the "My code" row under Your Nuvo.
class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.user, this.level});

  final AuthUser? user;

  /// The person's Nuvo level — identity metadata, shown as a quiet blue
  /// line under the handle. Null while progression is still loading; the
  /// line simply isn't claimed until the server answers.
  final int? level;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final displayName = user?.fullName ?? user?.email ?? '—';
    final username = user?.username != null ? '@${user!.username}' : null;
    final initials = user?.avatarInitials ?? '?';
    final photoUrl = user?.profilePhotoUrl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Hero(
              tag: 'profile-avatar',
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // The identity mark gets physical treatment — navy
                  // edge + hard offset — because this is the one object
                  // on the page that is the person.
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: c.border, width: 2.5),
                      boxShadow: [
                        BoxShadow(
                          color: c.inkShadow,
                          offset: const Offset(2.5, 2.5),
                          blurRadius: 0,
                        ),
                      ],
                    ),
                    child: NuvoAvatar(
                      initials: initials,
                      photoUrl: photoUrl,
                      size: 74,
                      bgColor: nuvoAvatarColorFor(user?.id ?? ''),
                      textColor: NuvoColors.white,
                    ),
                  ),
                  // Edit docks onto the avatar's corner — a tactile ice
                  // dial attached to the identity object, not a floating
                  // pencil. The 26px circle rides a 44px tap target.
                  Positioned(
                    right: -8,
                    bottom: -8,
                    child: Semantics(
                      button: true,
                      label: 'Edit profile',
                      child: NuvoPressable(
                        onTap: () => context.push('/profile/edit'),
                        scale: 0.94,
                        haptic: false,
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: Center(
                            child: Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                color: c.surface,
                                shape: BoxShape.circle,
                                border: Border.all(color: c.border, width: 1.5),
                              ),
                              child: Icon(
                                Icons.edit_outlined,
                                color: c.ink,
                                size: 13,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: NuvoSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: AppTextStyles.headlineMedium.copyWith(color: c.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (username != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      username,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: c.inkSubtle,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (level != null) ...[
                    const SizedBox(height: 6),
                    // The level is status, not helper text — an ice badge
                    // under the name, the same figure the leaderboard sees.
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: c.panelLight,
                        borderRadius: BorderRadius.circular(NuvoRadii.pill),
                      ),
                      child: Text(
                        'LEVEL $level',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: NuvoColors.blue,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                        ),
                        maxLines: 1,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Level track ─────────────────────────────────────────────────────────────

/// The "what's next" collectible under the progression track — navy
/// structural edge + hard offset, the same object language as the earned
/// badges. Small, grounded, named — never a floating lock on the bar.
class _NextUnlockArtifact extends StatelessWidget {
  const _NextUnlockArtifact({required this.unlock});

  final NuvoUnlockRef unlock;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final iconKey = unlock.metadata?['iconKey'] as String?;
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border, width: 2),
        boxShadow: [
          BoxShadow(
            color: c.inkShadow,
            offset: const Offset(3, 3),
            blurRadius: 0,
          ),
        ],
      ),
      child: Icon(
        iconKey != null
            ? nuvoBadgeIconFor(iconKey)
            : Icons.lock_outline_rounded,
        size: 20,
        color: c.ink,
      ),
    );
  }
}

/// Persistent progression — the Nuvo Level that belongs to the person,
/// not any single race: the level header, the beam to the next level and the
/// XP still owed. The whole plate is tappable — it opens what the level
/// means and what the next one unlocks. Always present: real data fills it,
/// a quiet skeleton holds its place while the server answers, and an outage
/// reads as a sync note — never a missing piece of identity.
class _LevelTrack extends ConsumerWidget {
  const _LevelTrack({super.key, required this.state});

  final AsyncValue<NuvoProgression> state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.themeColors;
    final p = state.valueOrNull;
    if (p == null) {
      return state.hasError
          ? _ProgressionUnavailable(c: c, ref: ref)
          : _ProgressionSkeleton(c: c);
    }
    // Near the threshold the payoff turns gold — level-up is the one gold
    // moment in the progression loop, so the last stretch previews it.
    final nearNext = p.progress >= 0.9;
    final xpColor = nearNext ? NuvoColors.gold : NuvoColors.blue;
    return Semantics(
      button: true,
      label: 'Level ${p.level}. ${p.xpToNext} XP to level ${p.level + 1}. '
          'Tap to see what levels unlock.',
      child: NuvoPressable(
        onTap: () => _showLevelExplainer(context, p),
        scale: 0.99,
        haptic: false,
        // A soft ice plate stages the progression — one quiet support
        // plane, not a card: no navy edge, no hard offset.
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: c.panelLight,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: c.border.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // LEVEL header row — the level figure on the left, the XP
              // fraction on the right, sharing one baseline.
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'LEVEL ',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: c.ink,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                          ),
                        ),
                        // The level number is the anchor — the same figure
                        // the leaderboard sees.
                        TextSpan(
                          text: '${p.level}',
                          style: AppTextStyles.statLarge(
                            24,
                            color: NuvoColors.blue,
                            weight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Spacer(),
                  Text(
                    '${p.currentLevelXp} / ${p.nextLevelXp} XP',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.labelSmall.copyWith(
                      color: c.inkSubtle,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // The beam — one straight run to the next level.
              _LevelRoute(level: p.level, progress: p.progress, color: xpColor),
              const SizedBox(height: 6),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        '${p.xpToNext} XP to Level ${p.level + 1}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.labelSmall.copyWith(
                          color: xpColor,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    // The one hint that this plate answers a question.
                    Icon(Icons.info_outline_rounded, size: 14, color: xpColor),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the level means — how XP is earned and what the next level unlocks.
/// Numbers mirror the server's XP economy (worker `XP_AWARDS`).
void _showLevelExplainer(BuildContext context, NuvoProgression p) {
  final c = context.themeColors;
  final next = p.nextUnlock;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: c.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Level ${p.level}',
              style: AppTextStyles.titleLarge.copyWith(
                color: c.ink,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${p.xpToNext} XP to Level ${p.level + 1}',
              style: AppTextStyles.bodyMedium.copyWith(
                color: NuvoColors.blue,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: NuvoSpacing.lg),
            Text(
              'XP comes from racing',
              style: AppTextStyles.labelLarge.copyWith(
                color: c.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            for (final line in const [
              '+10 for every accepted proof',
              '+25 for finishing a race',
              '+15 for winning one',
              '+5 for a personal best',
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  line,
                  style: AppTextStyles.bodyMedium.copyWith(color: c.inkMuted),
                ),
              ),
            const SizedBox(height: NuvoSpacing.lg),
            Text(
              next == null
                  ? 'You have everything this level unlocks'
                  : 'Level ${next.level} unlocks',
              style: AppTextStyles.labelLarge.copyWith(
                color: c.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (next != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  _NextUnlockArtifact(unlock: next),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          next.name,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: c.ink,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if ((next.description ?? '').isNotEmpty)
                          Text(
                            next.description!,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: c.inkMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: NuvoSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: NuvoPrimaryButton(
                label: 'See achievements',
                expand: true,
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  context.push('/profile/badges');
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The route itself — a drawn path, not a bar. The climb runs the upper
/// lane from the current level's filled anchor, steps down through a
/// small bend, and finishes at the open ring that is the next level. The
/// viewer's bead rides the path — including through the bend — and a
/// short connector drops under the ring where the next collectible
/// docks. Level numerals sit ON the route's ends.
class _LevelRoute extends StatelessWidget {
  const _LevelRoute({
    required this.level,
    required this.progress,
    required this.color,
  });

  final int level;
  final double progress;
  final Color color;

  // Beam geometry shared by the painter and the level numerals.
  static const double lane = 12;
  static const double beamY = 15; // the lane's center
  static const double padL = 30; // start numeral zone
  static const double padR = 30; // finish numeral zone
  static const double ringR = 10;
  static const double height = 30;

  static double ringX(double width) => width - padR - ringR;

  // The beam — one straight run from the start anchor to the finish
  // ring. Shared by the painter (draw + bead).
  static Path routePath(double w) => Path()
    ..moveTo(padL, beamY)
    ..lineTo(ringX(w), beamY);

  // Bead offset along the path — held clear of the anchor and the ring.
  static double beadOffset(double pathLength, double progress) =>
      (pathLength * progress.clamp(0.0, 1.0))
          .clamp(20.0, math.max(20.0, pathLength - 24))
          .toDouble();

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _RoutePainter(
          level: level,
          progress: progress,
          color: color,
          c: c,
          scaler: MediaQuery.textScalerOf(context),
        ),
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  _RoutePainter({
    required this.level,
    required this.progress,
    required this.color,
    required this.c,
    required this.scaler,
  });

  final int level;
  final double progress;
  final Color color;
  final dynamic c;
  final TextScaler scaler;

  @override
  void paint(Canvas canvas, Size size) {
    final end = _LevelRoute.ringX(size.width);
    final path = _LevelRoute.routePath(size.width);

    // Ice track — the whole remaining route.
    canvas.drawPath(
      path,
      Paint()
        ..color = c.track
        ..style = PaintingStyle.stroke
        ..strokeWidth = _LevelRoute.lane
        ..strokeCap = StrokeCap.round,
    );

    final metric = path.computeMetrics().first;
    final len = metric.length;
    final p = progress.clamp(0.0, 1.0);
    if (p > 0) {
      canvas.drawPath(
        metric.extractPath(0, len * p),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = _LevelRoute.lane
          ..strokeCap = StrokeCap.round,
      );
    }

    // Start anchor — the current level's filled mark.
    canvas.drawCircle(
      const Offset(_LevelRoute.padL, _LevelRoute.beamY),
      7,
      Paint()..color = c.ink,
    );

    // The viewer's bead ON the route — colored fill, navy edge, white
    // core, the same "you" mark the race lanes carry.
    final pos = metric
        .getTangentForOffset(_LevelRoute.beadOffset(len, progress))!
        .position;
    canvas
      ..drawCircle(pos, 9, Paint()..color = color)
      ..drawCircle(
        pos,
        9,
        Paint()
          ..color = c.border
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      )
      ..drawCircle(pos, 3, Paint()..color = Colors.white);

    // Finish ring — the next level, open until earned.
    final ring = Offset(end, _LevelRoute.beamY);
    canvas
      ..drawCircle(ring, _LevelRoute.ringR, Paint()..color = c.surface)
      ..drawCircle(
        ring,
        _LevelRoute.ringR,
        Paint()
          ..color = NuvoColors.blue
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );

    // Level numerals ON the route's ends.
    _paintNum(
      canvas,
      '$level',
      right: _LevelRoute.padL - 8,
      cy: _LevelRoute.beamY,
      color: c.ink,
    );
    _paintNum(
      canvas,
      '${level + 1}',
      left: end + _LevelRoute.ringR + 4,
      cy: _LevelRoute.beamY,
      color: c.inkSubtle,
    );
  }

  void _paintNum(
    Canvas canvas,
    String text, {
    double? left,
    double? right,
    required double cy,
    required Color color,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: AppTextStyles.statLarge(
          15,
          color: color,
          weight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout();
    final x = left ?? right! - tp.width;
    tp.paint(canvas, Offset(x, cy - tp.height / 2));
  }

  @override
  bool shouldRepaint(_RoutePainter old) =>
      old.level != level ||
      old.progress != progress ||
      old.color != color ||
      old.c != c ||
      old.scaler != scaler;
}

/// First-read placeholder — same rhythm as the real section so nothing
/// jumps when the payload lands.
class _ProgressionSkeleton extends StatelessWidget {
  const _ProgressionSkeleton({required this.c});
  final dynamic c;

  @override
  Widget build(BuildContext context) {
    Widget bar(double w, double h) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: c.panelLight,
        borderRadius: BorderRadius.circular(999),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            bar(90, 22),
            const Spacer(),
            bar(70, 12),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          height: 12,
          decoration: BoxDecoration(
            color: c.panelLight,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(height: 8),
        Center(child: bar(130, 10)),
      ],
    );
  }
}

/// The server didn't answer — keep the slot, tell the truth quietly, offer
/// a retry. A progression outage never blanks the profile's identity area.
class _ProgressionUnavailable extends StatelessWidget {
  const _ProgressionUnavailable({required this.c, required this.ref});
  final dynamic c;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return NuvoPressable(
      onTap: () =>
          ref.read(progressionControllerProvider.notifier).load(force: true),
      scale: 0.99,
      haptic: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'LEVEL',
            style: AppTextStyles.titleMedium.copyWith(
              color: c.inkMuted,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: NuvoSpacing.sm),
          Text(
            'Progress syncs when you\'re back online — tap to retry.',
            style: AppTextStyles.bodySmall.copyWith(color: c.inkMuted),
          ),
        ],
      ),
    );
  }
}

// ── Achievements section ────────────────────────────────────────────────────

/// The collection as one row: how many are earned, up to three featured
/// ones, and a chevron — the whole row opens the Achievements screen, where
/// the next goal, the next unlock and every achievement live.
class _AchievementsRow extends StatelessWidget {
  const _AchievementsRow({required this.progression});

  final NuvoProgression? progression;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final p = progression;
    if (p == null || p.achievementsTotal == 0) return const SizedBox.shrink();
    final featured = p.featuredBadges.take(3).toList();
    return Semantics(
      button: true,
      label: 'Achievements, ${p.achievementsEarned} of '
          '${p.achievementsTotal} earned. Tap to see all.',
      child: NuvoPressable(
        onTap: () => context.push('/profile/badges'),
        scale: 0.99,
        haptic: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(NuvoRadii.card),
            border: Border.all(color: c.divider, width: 1),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Achievements',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.sectionTitle.copyWith(
                        color: c.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${p.achievementsEarned} of ${p.achievementsTotal} '
                      'earned · see all',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: c.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              for (final badge in featured) ...[
                const SizedBox(width: 6),
                NuvoAchievementBadge(badge: badge, size: 34),
              ],
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: c.inkSubtle),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Stats strip ───────────────────────────────────────────────────────────────

/// Competitive snapshot: racing now, wins, win rate. Color carries meaning —
/// blue = live, gold = first place, navy = the neutral record.
class _StatsStrip extends StatelessWidget {
  const _StatsStrip({
    required this.activeCount,
    required this.wins,
    required this.winRate,
  });

  final int activeCount;
  final int wins;

  /// Wins / finished races, or null when the user has no finished races —
  /// a rate over zero races is not a stat worth inventing.
  final int? winRate;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    return Row(
      children: [
        _HeaderStat(
          value: activeCount,
          label: 'RACING',
          color: NuvoColors.blue,
        ),
        _HeaderDivider(),
        _HeaderStat(value: wins, label: 'WINS', color: NuvoColors.gold),
        _HeaderDivider(),
        _HeaderStat(
          value: winRate,
          label: 'WIN RATE',
          suffix: winRate == null ? '' : '%',
          color: c.ink,
        ),
      ],
    );
  }
}

// ── Header stat ───────────────────────────────────────────────────────────────

class _HeaderStat extends StatelessWidget {
  const _HeaderStat({
    required this.value,
    required this.label,
    this.suffix = '',
    this.color,
  });

  /// Null renders a quiet em-dash — used for win rate when there are no
  /// finished races, instead of implying 0%.
  final int? value;
  final String label;
  final String suffix;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (value == null)
            Text(
              '—',
              style: AppTextStyles.number(
                24,
                color: c.inkDim,
                weight: FontWeight.w800,
              ),
            )
          else
            // Digit-roll so a refreshed count visibly flows to the new
            // value instead of swapping text.
            NuvoNumberFlow(
              value: value!,
              format: (v) => '$v$suffix',
              style: AppTextStyles.number(
                24,
                color: color ?? c.ink,
                weight: FontWeight.w800,
              ),
            ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTextStyles.labelUppercase(
              10,
              color: c.inkSubtle,
            ).copyWith(color: context.themeColors.inkSubtle),
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
    height: 26,
    color: context.themeColors.border.withValues(alpha: 0.5),
    margin: const EdgeInsets.symmetric(horizontal: 6),
  );
}

// ── Racing-now shelf — horizontal race tiles ─────────────────────────────────

// ── Active race tile — progress is the headline ─────────────────────────────

// ── Result tile — placement earned ───────────────────────────────────────────

// ── Best finish — one earned mark, compact ────────────────────────────────────

class _ProfileActionGroup extends StatelessWidget {
  const _ProfileActionGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    // Page-level rows under a section label — same contract as the race
    // groups above: no enclosing sheet, just a hairline aligned to the text
    // column (past the 32px icon well + its leading padding).
    return Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          children[i],
          if (i < children.length - 1)
            Divider(height: 1, thickness: 1, indent: 58, color: c.divider),
        ],
      ],
    );
  }
}

// ── Presentation mode toggle ────────────────────────────────────────────────
//
// Only ever visible to the one account this is built for — flips between
// this account's real data and the fixed demo fixtures used for offline
// presentations (App Store screenshots, pitching). Off by default; never
// touches the backend either way.

class _PresentationModeRow extends StatelessWidget {
  const _PresentationModeRow({required this.enabled, required this.onChanged});

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: c.panelLight,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.slideshow_rounded, color: c.ink, size: 17),
          ),
          const SizedBox(width: NuvoSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Presentation mode',
                  style: AppTextStyles.bodyMedium.copyWith(color: c.ink),
                ),
                Text(
                  enabled
                      ? 'Showing demo data for presenting'
                      : 'Off — showing your real data',
                  style: AppTextStyles.labelSmall.copyWith(color: c.inkSubtle),
                ),
              ],
            ),
          ),
          NuvoToggle(value: enabled, onChanged: onChanged),
        ],
      ),
    );
  }
}

// ── Appearance row ────────────────────────────────────────────────────────────
//
// The persisted light/dark store exists (`nuvoThemeModeProvider`); this row
// is the only place it surfaces. The whole app re-themes on toggle — that
// repaint IS the feedback, so the row itself stays quiet.

class _AppearanceRow extends ConsumerWidget {
  const _AppearanceRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.themeColors;
    final isDark = ref.watch(nuvoThemeModeProvider) == ThemeMode.dark;
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: c.panelLight,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
              color: c.ink,
              size: 17,
            ),
          ),
          const SizedBox(width: NuvoSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Appearance',
                  style: AppTextStyles.bodyMedium.copyWith(color: c.ink),
                ),
                Text(
                  isDark ? 'Dark' : 'Light',
                  style: AppTextStyles.labelSmall.copyWith(color: c.inkSubtle),
                ),
              ],
            ),
          ),
          NuvoToggle(
            value: isDark,
            onChanged: (_) => ref.read(nuvoThemeModeProvider.notifier).toggle(),
          ),
        ],
      ),
    );
  }
}

// ── Account row ───────────────────────────────────────────────────────────────

/// Settings → Privacy & Data → "Help improve Nuvo Motion". Reads and writes
/// the SERVER consent state — onboarding and this toggle are the same truth.
class _MotionConsentRow extends ConsumerStatefulWidget {
  const _MotionConsentRow();

  @override
  ConsumerState<_MotionConsentRow> createState() => _MotionConsentRowState();
}

class _MotionConsentRowState extends ConsumerState<_MotionConsentRow> {
  bool? _enabled;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _enabled =
        ref.read(authControllerProvider).user?.motionTrainingConsent ?? false;
    // Refresh from the server so cross-device state is accurate.
    ref
        .read(authControllerProvider.notifier)
        .getMotionConsent()
        .then((v) {
          if (mounted) setState(() => _enabled = v);
        })
        .catchError((_) {});
  }

  Future<void> _set(bool value) async {
    if (_saving) return;
    setState(() {
      _enabled = value;
      _saving = true;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .setMotionConsent(consented: value);
    } on ApiException catch (e) {
      // Pre-attestation accounts (signed up before the eligibility step
      // existed) must confirm minimum age once before opting in. That is
      // the only 403 this endpoint produces for an attested-anything user.
      if (value && e.statusCode == 403 && mounted) {
        setState(() => _saving = false);
        final attested = await showNuvoConfirmDialog(
          context,
          title: 'Before you opt in',
          message:
              'Confirm you are at least 13 years old to help improve Nuvo Motion.',
          confirmLabel: 'I\u2019m at least 13',
        );
        if (attested == true && mounted) {
          try {
            await ref.read(authControllerProvider.notifier).attestAge();
            await ref
                .read(authControllerProvider.notifier)
                .setMotionConsent(consented: true);
            if (mounted) setState(() => _enabled = true);
            return;
          } catch (_) {
            /* fall through to generic error */
          }
        }
      }
      if (mounted) setState(() => _enabled = !value);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update this setting.')),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _enabled = !value);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update this setting.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: c.panelLight,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.motion_photos_on_rounded, color: c.ink, size: 17),
          ),
          const SizedBox(width: NuvoSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Help improve Nuvo Motion',
                  style: AppTextStyles.bodyMedium.copyWith(color: c.ink),
                ),
                Text(
                  'Save motion-point data from AI Motion Proof to improve '
                  'Nuvo\u2019s motion models. Camera video and audio aren\u2019t '
                  'uploaded.',
                  style: AppTextStyles.labelSmall.copyWith(color: c.inkSubtle),
                ),
              ],
            ),
          ),
          NuvoToggle(
            value: _enabled ?? false,
            onChanged: _enabled == null ? null : _set,
          ),
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
    this.subtitle,
    this.isDanger = false,
    this.isAction = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Quiet context under the label ("Race and crew updates").
  final String? subtitle;

  /// The one destructive treatment — red, reserved for Delete account.
  final bool isDanger;

  /// Actions (Sign out) fire something in place rather than navigating —
  /// ink, not danger, and no chevron since there's no destination.
  final bool isAction;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final color = isDanger ? NuvoColors.danger : c.ink;
    final bg = isDanger
        ? NuvoColors.danger.withValues(alpha: 0.10)
        : c.panelLight;
    final navigates = !isDanger && !isAction;

    return PressableScale(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 17),
            ),
            const SizedBox(width: NuvoSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppTextStyles.bodyMedium.copyWith(color: color),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: AppTextStyles.labelSmall.copyWith(
                        color: isDanger
                            ? NuvoColors.danger.withValues(alpha: 0.65)
                            : c.inkSubtle,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (navigates)
              NuvoIcon(NuvoIconType.arrow, color: c.inkMuted, size: 14),
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
        color: context.themeColors.ink,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
    );
  }
}

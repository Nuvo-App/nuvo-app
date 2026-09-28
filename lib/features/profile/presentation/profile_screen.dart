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
import '../../../core/widgets/nuvo_avatar.dart';
import '../../../core/widgets/nuvo_confirm_dialog.dart';
import '../../../core/widgets/nuvo_empty_state.dart';
import '../../../core/widgets/nuvo_error_state.dart';
import '../../../core/widgets/nuvo_icons.dart';
import '../../../core/widgets/nuvo_motion.dart';
import '../../../core/widgets/nuvo_number_flow.dart';
import '../../../core/widgets/nuvo_progress_bar.dart';
import '../../../core/widgets/nuvo_race_components.dart';
import '../../../core/widgets/nuvo_toggle.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../arena/presentation/arena_controller.dart';
import '../../auth/data/auth_api.dart';
import '../../auth/data/auth_models.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../onboarding/presentation/first_use_guide.dart';
import '../../races/data/race_models.dart';
import '../../races/domain/race_display.dart';
import '../../races/presentation/race_controller.dart';
import '../application/progression_controller.dart';
import '../data/progression_models.dart';
import 'widgets/nuvo_badges.dart';

const _kPrivacyUrl = 'https://getnuvo.net/privacy';
const _kTermsUrl = 'https://getnuvo.net/terms';

/// Profile — "who am I on Nuvo, and what have I done?"
///
/// Information order is the product order: identity → competitive snapshot →
/// racing now → recent results → utilities. Race rows reuse the canonical
/// [RaceRow]/[RaceResultRow] components shared with Compete, and every race
/// tap lands on `/race/:id` like everywhere else in the app.
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

  // Sections summarize; a capped list expands inline instead of growing the
  // main profile linearly with the user's history.
  static const _sectionCap = 3;
  // Racing now is a personal status module, not a list — the first viewport
  // carries ONE featured race (closest to the finish line) plus See all;
  // the rest live behind the inline expansion.
  static const _racingFeaturedCap = 1;
  bool _racingExpanded = false;
  bool _resultsExpanded = false;
  bool _otherExpanded = false;
  bool _progressionRetryScheduled = false;

  Future<void> _replayDemo() async {
    ref.read(firstRaceGuideProvider.notifier).state =
        FirstRaceGuideStep.competeStart;
    ref.read(demoReplayProvider.notifier).state = true;
    if (mounted) context.go('/splash');
  }

  Future<void> _setPresentationMode(bool enabled) async {
    if (!canTogglePresentationMode(ref.read(authControllerProvider).user)) return;
    final persistence = setPresentationModeEnabled(enabled);
    // Clear generations before loading so an older request cannot restore the
    // previous mode. Crew and notifications observe the preference directly.
    final races = ref.read(raceControllerProvider.notifier)..clearRaces();
    final arena = ref.read(arenaControllerProvider.notifier)..clearSnapshot();
    await Future.wait([
      persistence,
      races.loadRaces(force: true),
      arena.loadSnapshot(force: true),
    ]);
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
    final canReplayDemo =
        user != null &&
        (_demoAccountEmails.contains(user.email.trim().toLowerCase()) ||
            user.username?.trim().toLowerCase() == 'akshay');
    final canTogglePresentation =
        user != null && canTogglePresentationMode(user);

    final raceState = ref.watch(raceControllerProvider);
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
                    r.finalStandings.any(
                      (s) => s.userId == uid && s.rank == 1,
                    ),
              )
              .length;
    final winRate = finishedRaces.isEmpty
        ? null
        : (wins / finishedRaces.length * 100).round();

    return Scaffold(
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
                padding: const EdgeInsets.fromLTRB(20, 32, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top row: label + edit
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Profile',
                            style: AppTextStyles.screenTitle.copyWith(
                              color: c.ink,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Spacer(),
                        // Icon-only edit — same header-icon contract as
                        // Crew (NuvoPressable → 44px hit target → 24px navy
                        // icon), hugging the page gutter, not a floating
                        // capsule.
                        Semantics(
                          button: true,
                          label: 'Edit profile',
                          child: NuvoPressable(
                            onTap: () => context.push('/profile/edit'),
                            scale: 0.94,
                            haptic: false,
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              // The glyph's right edge lands on the page
                              // gutter — the 44px hit target extends left.
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Icon(
                                  Icons.edit_outlined,
                                  color: c.ink,
                                  size: 22,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: NuvoSpacing.lg),

                    // Identity — the person, not the account. Avatar uses the
                    // same deterministic palette color other racers see on
                    // leaderboards; Edit stays in the header so this card is
                    // about who I am, not settings.
                    _IdentityCard(user: user).nuvoEnter(),
                    const SizedBox(height: NuvoSpacing.lg),

                    // Level — the progression that belongs to the person,
                    // not any one race. Always visible: data fills it, a
                    // quiet skeleton holds its place while the server
                    // answers, and a failure reads as "syncing" — never a
                    // missing piece of identity.
                    _ProgressionSection(state: progressionAsync).nuvoEnter(),
                    const SizedBox(height: NuvoSpacing.lg),

                    // Competitive snapshot — three stats that mean something.
                    _StatsStrip(
                      activeCount: activeCount,
                      wins: wins,
                      winRate: winRate,
                    ),
                    const SizedBox(height: NuvoSpacing.lg),

                    // The collection is part of identity — featured
                    // achievements with names, or the next target in reach
                    // when nothing is featured yet. Never an empty section.
                    _AchievementsSection(progression: progression),
                    const SizedBox(height: NuvoSpacing.lg),

                    // One goal in reach — the reason to race again.
                    _NextUpCard(progression: progression),
                  ],
                ),
              ),
            ),

            // ── Profile body — page-colored background ──────────────────────
            // Content flows at normal section rhythm — no fold seam. A row
            // that lands under the dock is hidden by the shell's occlusion
            // band and scrolls clear, same contract as Compete
            // (docs/ui/MAIN_SCREEN_LAYOUT_CONTRACT.md).
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                20,
                18,
                20,
                NuvoBottomNav.bottomPadding(context),
              ),
              sliver: SliverToBoxAdapter(
                child: Container(
                  color: c.page,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _profileBody(
                      raceState,
                      uid,
                      context,
                      canReplayDemo: canReplayDemo,
                      canTogglePresentation: canTogglePresentation,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _profileBody(
    RaceState raceState,
    String? uid,
    BuildContext context, {
    required bool canReplayDemo,
    required bool canTogglePresentation,
  }) {
    final activeRaces = raceState.races.where(raceIsActive).toList()
      // The race nearest its finish line is the one that matters right now.
      ..sort((a, b) {
        final ap = raceProgressPercent(a, uid == null ? null : a.participantFor(uid));
        final bp = raceProgressPercent(b, uid == null ? null : b.participantFor(uid));
        return bp.compareTo(ap);
      });
    final finishedRaces = raceState.races.where(raceIsCompleted).toList();
    final otherRaces = raceState.races
        .where((race) => !raceIsActive(race) && !raceIsCompleted(race))
        .toList();

    // Best finish — the lowest placement across completed races, read from
    // canonical standings/participants. Null when there's nothing earned.
    Race? bestFinish;
    var bestFinishRank = 0;
    for (final race in finishedRaces) {
      final rank = rankForUser(race, uid);
      if (rank != null && (bestFinish == null || rank < bestFinishRank)) {
        bestFinish = race;
        bestFinishRank = rank;
      }
    }

    // Race sections in order — Racing now, Recent results, Other — at
    // normal section rhythm. Content flows naturally; a row that lands
    // under the dock at rest is hidden by the shell's occlusion band and
    // scrolls clear, same contract as Compete (docs §15). No fold seam —
    // short pages are never vertically distributed to fill the viewport.
    final raceSections = <Widget>[
      if (activeRaces.isNotEmpty)
        _RaceSection(
          label: 'Racing now',
          races: activeRaces,
          userId: uid,
          expanded: _racingExpanded,
          cap: _racingFeaturedCap,
          onToggleExpand: () =>
              setState(() => _racingExpanded = !_racingExpanded),
        ),
      if (finishedRaces.isNotEmpty) ...[
        if (activeRaces.isNotEmpty) const SizedBox(height: NuvoSpacing.xl),
        _RaceSection(
          label: 'Recent results',
          races: finishedRaces,
          userId: uid,
          expanded: _resultsExpanded,
          cap: _sectionCap,
          onToggleExpand: () =>
              setState(() => _resultsExpanded = !_resultsExpanded),
        ),
      ],
      if (otherRaces.isNotEmpty) ...[
        if (activeRaces.isNotEmpty || finishedRaces.isNotEmpty)
          const SizedBox(height: NuvoSpacing.xl),
        _RaceSection(
          label: 'Other',
          races: otherRaces,
          userId: uid,
          expanded: _otherExpanded,
          cap: _sectionCap,
          onToggleExpand: () =>
              setState(() => _otherExpanded = !_otherExpanded),
        ),
      ],
    ];

    return [
      // Racing now / recent results / history
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
          onRetry: () => ref.read(raceControllerProvider.notifier).loadRaces(),
        )
      else if (raceState.races.isEmpty)
        NuvoEmptyState(
          icon: Icons.flag_rounded,
          title: 'Your first race starts here',
          body: 'Start or join a race to build your Nuvo history.',
          ctaLabel: 'Find a race',
          onCta: () => context.go('/compete'),
          compact: true,
        )
      else
        ...raceSections,

      // One earned personal mark — best placement across finished races,
      // read straight from canonical standings. Hidden when nothing has
      // been earned yet; never invented.
      if (bestFinish != null) ...[
        const SizedBox(height: NuvoSpacing.xxl),
        _BestFinishRow(
          race: bestFinish,
          rank: bestFinishRank,
          scoreLabel: bestFinish.finalStandings
              .where((s) => s.userId == uid)
              .map((s) => raceScoreLabel(bestFinish!, s.scoreValue))
              .firstOrNull,
        ),
      ],

      const SizedBox(height: NuvoSpacing.xxl),

      // Your Nuvo — the things that are mine and how the app feels.
      const _SectionLabel(label: 'Your Nuvo'),
      const SizedBox(height: NuvoSpacing.md),
      _ProfileActionGroup(
        children: [
          _AccountRow(
            icon: Icons.qr_code_2_rounded,
            label: 'My Nuvo',
            subtitle: 'Your code and pass link',
            onTap: () => context.push('/my-nuvo'),
          ),
          _AccountRow(
            icon: Icons.badge_rounded,
            label: 'Member pass',
            subtitle: 'The card other racers see',
            onTap: () => context.go('/pass'),
          ),
          _AccountRow(
            icon: Icons.notifications_outlined,
            label: 'Notifications',
            subtitle: 'Race and crew updates',
            onTap: () => context.push('/settings/notifications'),
          ),
          const _AppearanceRow(),
        ],
      ),
      const SizedBox(height: NuvoSpacing.xl),

      // Gated tools only — this group doesn't exist for normal accounts.
      // Presentation/demo controls stay behind the existing account gates.
      if (canReplayDemo || canTogglePresentation || kDebugMode) ...[
        const _SectionLabel(label: 'App'),
        const SizedBox(height: NuvoSpacing.md),
        _ProfileActionGroup(
          children: [
            if (canReplayDemo)
              _AccountRow(
                icon: Icons.replay_rounded,
                label: 'Replay the guide',
                onTap: _replayDemo,
              ),
            if (canTogglePresentation)
              _PresentationModeRow(
                enabled: presentationModeToggleEnabled,
                onChanged: _setPresentationMode,
              ),
            if (kDebugMode)
              _AccountRow(
                icon: Icons.tune_rounded,
                label: 'Rive Calibration',
                onTap: () => context.push('/dev/rive-calibration'),
              ),
          ],
        ),
        const SizedBox(height: NuvoSpacing.xl),
      ],

      // Privacy & Data — the server-backed training-consent control. Same
      // choice as onboarding; toggling writes through to the account.
      const _SectionLabel(label: 'Privacy & Data'),
      const SizedBox(height: NuvoSpacing.md),
      const _ProfileActionGroup(children: [_MotionConsentRow()]),
      const SizedBox(height: NuvoSpacing.xl),

      // Account — session actions. Destructive red belongs to Delete alone;
      // Sign out is a normal action, not a danger.
      const _SectionLabel(label: 'Account'),
      const SizedBox(height: NuvoSpacing.md),
      _ProfileActionGroup(
        children: [
          _AccountRow(
            icon: Icons.person_outline_rounded,
            label: 'Edit profile',
            subtitle: 'Photo, name, username',
            onTap: () => context.push('/profile/edit'),
          ),
          _AccountRow(
            icon: Icons.logout_rounded,
            label: 'Sign out',
            isAction: true,
            onTap: () => ref.read(authControllerProvider.notifier).logout(),
          ),
          _AccountRow(
            icon: Icons.delete_outline_rounded,
            label: 'Delete account',
            isDanger: true,
            onTap: _confirmDeleteAccount,
          ),
        ],
      ),
      const SizedBox(height: NuvoSpacing.xxl),

      // Legal
      const _SectionLabel(label: 'Legal'),
      const SizedBox(height: NuvoSpacing.md),
      _ProfileActionGroup(
        children: [
          _AccountRow(
            icon: Icons.policy_rounded,
            label: 'Privacy Policy',
            onTap: () => _openUrl(_kPrivacyUrl),
          ),
          _AccountRow(
            icon: Icons.description_rounded,
            label: 'Terms of Service',
            onTap: () => _openUrl(_kTermsUrl),
          ),
        ],
      ),
    ];
  }
}

// ── Identity ──────────────────────────────────────────────────────────────────

/// Who I am on Nuvo: avatar, name, handle, member status, and the "My Nuvo"
/// path to share that identity. The user is the hero — this lives directly on
/// the page, no card around it.
class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.user});

  final AuthUser? user;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final displayName = user?.fullName ?? user?.email ?? '—';
    final username = user?.username != null ? '@${user!.username}' : null;
    final initials = user?.avatarInitials ?? '?';
    final photoUrl = user?.profilePhotoUrl;
    final hasPass = user?.hasMemberPass ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Hero(
              tag: 'profile-avatar',
              child: NuvoAvatar(
                initials: initials,
                photoUrl: photoUrl,
                size: NuvoAvatarSizes.lg,
                bgColor: nuvoAvatarColorFor(user?.id ?? ''),
                textColor: NuvoColors.white,
              ),
            ),
            const SizedBox(width: NuvoSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: AppTextStyles.headlineMedium.copyWith(
                      color: c.ink,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (username != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      username,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: c.inkSubtle,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: NuvoSpacing.md),
        Wrap(
          spacing: NuvoSpacing.sm,
          runSpacing: NuvoSpacing.sm,
          children: [
            if (hasPass)
              _IdentityChip(
                icon: Icons.check_circle_rounded,
                iconColor: NuvoColors.blue,
                label: 'Member pass',
                onTap: () => context.go('/pass'),
              ),
            _IdentityChip(
              icon: Icons.qr_code_2_rounded,
              iconColor: c.ink,
              label: 'My Nuvo',
              trailing: true,
              onTap: () => context.push('/my-nuvo'),
            ),
          ],
        ),
      ],
    );
  }
}

class _IdentityChip extends StatelessWidget {
  const _IdentityChip({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
    this.trailing = false,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;
  final bool trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    return PressableScale(
      onTap: onTap,
      scale: 0.96,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: c.panelLight,
          borderRadius: BorderRadius.circular(NuvoRadii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTextStyles.labelSmall.copyWith(
                color: c.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (trailing) ...[
              const SizedBox(width: 4),
              NuvoIcon(NuvoIconType.arrow, color: c.inkSubtle, size: 12),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Progression section ─────────────────────────────────────────────────────

/// Persistent progression — the Nuvo Level that belongs to the person, not
/// any single race. Type, progress, and the next reward carry it; nothing
/// boxes it in, so it reads as part of the identity rather than an attached
/// card. The section is ALWAYS present: real data fills it, a quiet
/// skeleton holds its place while the server answers, and an outage reads
/// as a sync note — never a missing piece of the profile.
class _ProgressionSection extends ConsumerWidget {
  const _ProgressionSection({required this.state});

  final AsyncValue<NuvoProgression> state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.themeColors;
    final p = state.valueOrNull;

    if (p == null) {
      if (state.hasError) return _ProgressionUnavailable(c: c, ref: ref);
      return _ProgressionSkeleton(c: c);
    }

    final next = p.nextUnlock;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                'LEVEL ${p.level}',
                style: AppTextStyles.titleMedium.copyWith(
                  color: c.ink,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            Text(
              '${p.currentLevelXp} / ${p.nextLevelXp} XP',
              style: AppTextStyles.labelSmall.copyWith(
                color: c.inkSubtle,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: NuvoSpacing.sm),
        NuvoProgressBar(
          value: p.progress,
          height: 8,
          color: NuvoColors.blue,
          trackColor: c.track,
        ),
        const SizedBox(height: NuvoSpacing.sm),
        Text(
          '${p.xpToNext} XP to Level ${p.level + 1}',
          style: AppTextStyles.labelSmall.copyWith(
            color: NuvoColors.blue,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (next != null) ...[
          const SizedBox(height: NuvoSpacing.sm),
          Divider(height: 1, thickness: 1, color: c.divider),
          const SizedBox(height: NuvoSpacing.sm),
          Text(
            'NEXT UNLOCK',
            style: AppTextStyles.labelUppercase(
              10,
              color: c.inkSubtle,
            ).copyWith(color: c.inkSubtle),
          ),
          const SizedBox(height: NuvoSpacing.sm),
          Row(
            children: [
              NuvoBadgeDisc(
                badge: NuvoBadge(
                  unlockId: next.unlockId,
                  type: next.type,
                  key: next.key,
                  name: next.name,
                  requiredLevel: next.level,
                  metadata: next.metadata,
                  unlocked: false,
                  featured: false,
                ),
                size: 36,
              ),
              const SizedBox(width: NuvoSpacing.sm),
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Level ${next.level}',
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
      ],
    );
  }
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
        bar(90, 14),
        const SizedBox(height: NuvoSpacing.sm),
        NuvoProgressBar(value: 0, height: 8, trackColor: c.track),
        const SizedBox(height: NuvoSpacing.sm),
        bar(120, 10),
        const SizedBox(height: NuvoSpacing.md),
        Divider(height: 1, thickness: 1, color: c.divider),
        const SizedBox(height: NuvoSpacing.md),
        bar(70, 9),
        const SizedBox(height: NuvoSpacing.sm),
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: c.panelLight,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: NuvoSpacing.sm),
            bar(110, 10),
          ],
        ),
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
      onTap: () => ref
          .read(progressionControllerProvider.notifier)
          .load(force: true),
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

/// The collection is part of identity: featured achievements as named
/// objects under an earned/total count, or the locked target in reach when
/// nothing is featured yet. Never an empty section — the next goal is the
/// point.
class _AchievementsSection extends StatelessWidget {
  const _AchievementsSection({required this.progression});

  final NuvoProgression? progression;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final p = progression;
    if (p == null) return const SizedBox.shrink();

    final featured = p.featuredBadges;
    final next = p.nextAchievement;
    if (featured.isEmpty && next == null && p.achievementsTotal == 0) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NuvoPressable(
          onTap: () => context.push('/profile/badges'),
          scale: 0.98,
          haptic: false,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  'Achievements',
                  style: AppTextStyles.sectionTitle.copyWith(
                    color: c.ink,
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Spacer(),
              Text(
                '${p.achievementsEarned} / ${p.achievementsTotal}',
                style: AppTextStyles.labelSmall.copyWith(
                  color: c.inkSubtle,
                  fontWeight: FontWeight.w800,
                ),
                maxLines: 1,
              ),
              const SizedBox(width: 4),
              const NuvoIcon(
                NuvoIconType.arrow,
                color: NuvoColors.blue,
                size: 12,
              ),
            ],
          ),
        ),
        const SizedBox(height: NuvoSpacing.sm + 2),
        if (featured.isNotEmpty)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < featured.length; i++) ...[
                Expanded(
                  child: Column(
                    children: [
                      NuvoAchievementBadge(badge: featured[i], size: 52),
                      const SizedBox(height: 6),
                      Text(
                        featured[i].name,
                        style: AppTextStyles.labelSmall.copyWith(
                          color: c.inkSubtle,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                if (i < featured.length - 1)
                  const SizedBox(width: NuvoSpacing.sm),
              ],
              // Fill unused slot columns so names align across layouts.
              for (var i = featured.length; i < p.featuredSlots; i++)
                const Expanded(child: SizedBox.shrink()),
            ],
          )
        else if (next != null)
          Row(
            children: [
              NuvoAchievementBadge(badge: next, size: 52),
              const SizedBox(width: NuvoSpacing.sm),
              Expanded(
                child: Text(
                  '${next.name} — ${next.description ?? 'keep racing'}',
                  style: AppTextStyles.bodySmall.copyWith(color: c.inkMuted),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

// ── Next up ───────────────────────────────────────────────────────────────────

/// The one goal in reach — a locked achievement with live canonical
/// progress. This is what makes the next race feel like it advances the
/// person, not just the leaderboard.
class _NextUpCard extends StatelessWidget {
  const _NextUpCard({required this.progression});

  final NuvoProgression? progression;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final next = progression?.nextAchievement;
    if (next == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'NEXT UP',
          style: AppTextStyles.labelUppercase(
            10,
            color: c.inkSubtle,
          ).copyWith(color: c.inkSubtle),
        ),
        const SizedBox(height: NuvoSpacing.sm),
        Container(
          padding: const EdgeInsets.all(NuvoSpacing.md),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(NuvoRadii.md),
            border: Border.all(color: c.border, width: 2),
            boxShadow: [
              BoxShadow(
                color: c.inkShadow,
                offset: const Offset(3, 3),
                blurRadius: 0,
              ),
            ],
          ),
          child: Row(
            children: [
              NuvoAchievementBadge(badge: next, size: 44),
              const SizedBox(width: NuvoSpacing.md),
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (next.description != null)
                      Text(
                        next.description!,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: c.inkMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: NuvoProgressBar(
                            value: next.goalProgress,
                            height: 6,
                            color: NuvoColors.blue,
                            trackColor: c.track,
                          ),
                        ),
                        const SizedBox(width: NuvoSpacing.sm),
                        Text(
                          '${next.progressValue} / ${next.threshold}',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: c.inkSubtle,
                            fontWeight: FontWeight.w800,
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
      ],
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          _HeaderStat(value: activeCount, label: 'RACING', color: NuvoColors.blue),
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
      ),
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
          const SizedBox(height: 3),
          Text(
            label,
            style: AppTextStyles.labelUppercase(10, color: c.inkSubtle).copyWith(color: context.themeColors.inkSubtle),
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
    color: context.themeColors.ink.withValues(alpha: 0.12),
    margin: const EdgeInsets.symmetric(horizontal: 4),
  );
}

// ── Race section — capped grouped list with inline expansion ─────────────────

/// A labeled race group ("Racing now", "Recent results") capped at [cap]
/// rows, expanding inline on "See all" — the same pattern Compete uses for
/// its race list, so the summary doesn't grow linearly with history.
class _RaceSection extends StatelessWidget {
  const _RaceSection({
    required this.label,
    required this.races,
    required this.userId,
    required this.expanded,
    required this.cap,
    required this.onToggleExpand,
  });

  final String label;
  final List<Race> races;
  final String? userId;
  final bool expanded;
  final int cap;
  final VoidCallback onToggleExpand;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final visible = expanded ? races : races.take(cap).toList();
    final hasMore = races.length > cap;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                '$label · ${races.length}',
                style: AppTextStyles.sectionTitle.copyWith(color: c.ink),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Spacer(),
            if (hasMore)
              NuvoPressable(
                onTap: onToggleExpand,
                haptic: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Text(
                    expanded ? 'Show less' : 'See all',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: c.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: NuvoSpacing.sm),
        _ProfileRaceGroup(races: visible, userId: userId),
      ],
    );
  }
}

class _ProfileRaceGroup extends StatelessWidget {
  const _ProfileRaceGroup({required this.races, this.userId});

  final List<Race> races;
  final String? userId;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    // Structured-compact level: rows sit on the page under the section
    // title — no enclosing sheet. The only separator is a hairline aligned
    // to the shared text column, past the 44px placement/icon column.
    return Column(
      children: [
        for (var i = 0; i < races.length; i++) ...[
          _buildRow(context, races[i]),
          if (i < races.length - 1)
            Divider(
              height: 1,
              thickness: 1,
              indent: 52,
              color: c.divider,
            ),
        ],
      ],
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
      return _ResultTile(
        raceTitle: race.displayTitle,
        movementLabel: activity,
        scoreLabel:
            myPart != null ? raceScoreLabel(race, myPart.progressValue) : null,
        rank: rank,
        participantCount: race.participantCount,
        avatars: avatars,
        onTap: () => context.push('/race/${race.id}'),
      );
    }

    // Derived context for an in-flight race: how far I still have to go,
    // formatted through the canonical metric formatter ("11 reps", "0:45").
    // Falls back to the activity name when the goal isn't a fixed target
    // or I'm already at the line.
    final target = race.targetValue;
    final remaining = target != null &&
            myPart != null &&
            target > myPart.progressValue
        ? raceScoreLabel(race, target - myPart.progressValue)
        : null;

    return _ActiveRaceTile(
      raceTitle: race.displayTitle,
      movementLabel: activity,
      icon: raceActivityDefinition(race)?.icon ??
          Icons.fitness_center_rounded,
      progressLabel: progressLabel,
      progressPercent: pct,
      remainingLabel: remaining,
      rank: rank,
      participantCount: race.participantCount,
      avatars: avatars,
      onTap: () => context.push('/race/${race.id}'),
    );
  }
}

// ── Active race tile — progress is the headline ─────────────────────────────

/// "Racing now" row. The track and my position carry the card — a race
/// I'm inside is a standing, not a list entry. At the start line it
/// stays quiet rather than drawing an empty bar.
class _ActiveRaceTile extends StatelessWidget {
  const _ActiveRaceTile({
    required this.raceTitle,
    required this.movementLabel,
    required this.icon,
    required this.progressLabel,
    required this.progressPercent,
    required this.rank,
    required this.participantCount,
    required this.avatars,
    required this.onTap,
    this.remainingLabel,
  });

  final String raceTitle;
  final String movementLabel;
  final IconData icon;
  final String progressLabel;
  final int progressPercent;
  final int? rank;
  final int participantCount;
  final List<({String initials, String? photoUrl, String id})> avatars;
  final VoidCallback onTap;

  /// "11 reps" remaining to the finish line — derived from the canonical
  /// target, shown instead of the activity label when it exists.
  final String? remainingLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final hasProof = progressPercent > 0;

    return Semantics(
      button: true,
      label: raceTitle,
      child: PressableScale(
        onTap: onTap,
        scale: 0.985,
        child: Container(
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.symmetric(vertical: NuvoSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The 44px leading column matches _ResultTile's placement
              // column — every text column in the list shares one gutter.
              SizedBox(
                width: 44,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: c.panelLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: c.ink, size: 18),
                  ),
                ),
              ),
              const SizedBox(width: NuvoSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            raceTitle,
                            style: AppTextStyles.raceRowTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (hasProof)
                          RacePlacement(rank: rank, size: 15)
                        else
                          Text(
                            'Start line',
                            style: AppTextStyles.labelSmall.copyWith(
                              color: c.inkSubtle,
                              fontWeight: FontWeight.w700,
                              fontSize: 10,
                              letterSpacing: 0.3,
                            ),
                          ),
                      ],
                    ),
                    if (hasProof) ...[
                      const SizedBox(height: 4),
                      Text(
                        progressLabel,
                        style: AppTextStyles.labelMedium.copyWith(
                          color: c.ink,
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 7),
                      RaceProgress(
                        progressPercent: progressPercent,
                        trackHeight: 3,
                        dotDiameter: 9,
                      ),
                      const SizedBox(height: 7),
                    ] else
                      const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            remainingLabel != null
                                ? '$remainingLabel to finish · '
                                    '$participantCount '
                                    '${participantCount == 1 ? 'racer' : 'racers'}'
                                : '$movementLabel · $participantCount '
                                    '${participantCount == 1 ? 'racer' : 'racers'}',
                            style: AppTextStyles.raceRowMeta.copyWith(color: context.themeColors.inkSubtle),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (avatars.isNotEmpty)
                          RacePeople(
                            avatars: avatars,
                            total: participantCount,
                            size: 20,
                            max: 3,
                          ),
                      ],
                    ),
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

// ── Result tile — placement earned ───────────────────────────────────────────

/// Finished race row. A win reads as achievement — gold placement block,
/// trophy mark — while every other placement stays neutral. No progress
/// track: the absence of movement says the race is over.
class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.raceTitle,
    required this.movementLabel,
    required this.scoreLabel,
    required this.rank,
    required this.participantCount,
    required this.avatars,
    required this.onTap,
  });

  final String raceTitle;
  final String movementLabel;
  final String? scoreLabel;
  final int? rank;
  final int participantCount;
  final List<({String initials, String? photoUrl, String id})> avatars;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final won = rank == 1;
    final meta = scoreLabel != null
        ? '$scoreLabel · $participantCount '
            '${participantCount == 1 ? 'racer' : 'racers'}'
        : '$movementLabel · $participantCount '
            '${participantCount == 1 ? 'racer' : 'racers'}';

    return Semantics(
      button: true,
      label: raceTitle,
      child: PressableScale(
        onTap: onTap,
        scale: 0.985,
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(vertical: NuvoSpacing.md),
          child: Row(
            children: [
              SizedBox(
                width: 44,
                child: Column(
                  children: [
                    if (won) ...[
                      const Icon(
                        Icons.emoji_events_rounded,
                        size: 15,
                        color: NuvoColors.gold,
                      ),
                      const SizedBox(height: 1),
                    ],
                    Text(
                      rank != null ? _ordinalLabel(rank!) : '--',
                      style: AppTextStyles.placementLabel(
                        color: won
                            ? NuvoColors.gold
                            : c.inkSubtle,
                        size: won ? 14 : 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: NuvoSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      raceTitle,
                      style: AppTextStyles.raceRowTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      meta,
                      style: AppTextStyles.raceRowMeta.copyWith(color: context.themeColors.inkSubtle),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (avatars.isNotEmpty) ...[
                const SizedBox(width: NuvoSpacing.sm),
                RacePeople(
                  avatars: avatars,
                  total: participantCount,
                  size: 22,
                  max: 3,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _ordinalLabel(int n) {
  if (n % 100 >= 11 && n % 100 <= 13) return '${n}TH';
  return switch (n % 10) {
    1 => '${n}ST',
    2 => '${n}ND',
    3 => '${n}RD',
    _ => '${n}TH',
  };
}

// ── Best finish — one earned mark, compact ────────────────────────────────────

/// The strongest placement I've ever reached — gold when it's a win,
/// neutral otherwise. A slim module, not a card competing with the result
/// rows above it. Only renders when canonical standings say something.
class _BestFinishRow extends StatelessWidget {
  const _BestFinishRow({
    required this.race,
    required this.rank,
    this.scoreLabel,
  });

  final Race race;
  final int rank;
  final String? scoreLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final won = rank == 1;

    return Semantics(
      button: true,
      label: 'Best finish — ${_ordinalLabel(rank)} in ${race.displayTitle}',
      child: PressableScale(
        onTap: () => context.push('/race/${race.id}'),
        scale: 0.985,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(
                won
                    ? Icons.emoji_events_rounded
                    : Icons.military_tech_rounded,
                size: 17,
                color: won ? NuvoColors.gold : c.inkMuted,
              ),
              const SizedBox(width: NuvoSpacing.sm),
              Text(
                'BEST FINISH',
                style: AppTextStyles.labelUppercase(
                  10,
                  color: won ? NuvoColors.gold : c.inkSubtle,
                ),
              ),
              const SizedBox(width: NuvoSpacing.sm),
              Expanded(
                child: Text(
                  '${_ordinalLabel(rank)} · ${race.displayTitle}',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: c.ink,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (scoreLabel != null) ...[
                const SizedBox(width: NuvoSpacing.sm),
                Text(
                  scoreLabel!,
                  style: AppTextStyles.labelMedium.copyWith(
                    color: c.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

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
            Divider(
              height: 1,
              thickness: 1,
              indent: 58,
              color: c.divider,
            ),
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
            child: Icon(
              Icons.slideshow_rounded,
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
                  'Presentation mode',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: c.ink,
                  ),
                ),
                Text(
                  enabled
                      ? 'Showing demo data for presenting'
                      : 'Off — showing your real data',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: c.inkSubtle,
                  ),
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
    final isDark =
        ref.watch(nuvoThemeModeProvider) == ThemeMode.dark;
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
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: c.ink,
                  ),
                ),
                Text(
                  isDark ? 'Dark' : 'Light',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: c.inkSubtle,
                  ),
                ),
              ],
            ),
          ),
          NuvoToggle(
            value: isDark,
            onChanged: (_) =>
                ref.read(nuvoThemeModeProvider.notifier).toggle(),
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
            child: Icon(
              Icons.motion_photos_on_rounded,
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
              NuvoIcon(
                NuvoIconType.arrow,
                color: c.inkMuted,
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
        color: context.themeColors.ink,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
    );
  }
}

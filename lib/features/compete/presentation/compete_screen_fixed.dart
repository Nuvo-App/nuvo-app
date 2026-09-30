import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_geometry.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/nuvo_responsive.dart';
import '../../../core/widgets/bottom_nav.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_empty_state.dart';
import '../../../core/widgets/nuvo_error_state.dart';
import '../../../core/widgets/nuvo_flip_card.dart';
import '../../../core/widgets/nuvo_race_components.dart';
import '../../../core/widgets/nuvo_motion.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../races/data/race_models.dart';
import '../../races/domain/motion_activity.dart';
import '../../races/domain/race_display.dart';
import '../../races/presentation/race_controller.dart';
import '../../profile/presentation/widgets/xp_reward.dart';
import '../../onboarding/presentation/first_use_guide.dart';

/// Compete — Phase 1 design language.
///
/// IA preserved from Variant B (Stage 2):
/// 1. Compact header (title + active/finished summary + Start/Join)
/// 2. ONE loud "Continue competing" navy surface (NuvoFeaturedRaceCard)
/// 3. "Your races" compact list (capped at 3, inline See all)
/// 4. Waiting-for-crew summary (NuvoWaitingCrewSummary)
/// 5. Finished summary (NuvoFinishedSummary)
/// 6. Quick Starts in a compact 2-column wrap (NuvoQuickStart)
///
/// Visual presentation rebuilt with race product components that encode
/// competition, placement, crew completeness, and results — not generic cards.
class CompeteScreen extends ConsumerStatefulWidget {
  const CompeteScreen({super.key});

  @override
  ConsumerState<CompeteScreen> createState() => _CompeteScreenState();
}

class _CompeteScreenState extends ConsumerState<CompeteScreen> {
  bool _racesExpanded = false;
  bool _waitingExpanded = false;
  bool _finishedExpanded = false;

  /// Which face of the featured race card is out — action layer (front) ↔
  /// in-race status layer (back). The flip is the seam between the two.
  bool _featuredFlipped = false;

  static const _racesCap = 3;

  @override
  Widget build(BuildContext context) {
    final raceState = ref.watch(raceControllerProvider);
    final user = ref.watch(authControllerProvider).user;
    final uid = user?.id;

    // Every race the user is in — camera (movement) and non-camera (manual /
    // check-in / photo) goals alike. Non-camera races were previously hidden
    // here, which made non-physical goals impossible to act on.
    final cameraRaces = raceState.races;
    final active = cameraRaces.where(raceIsActive).toList();
    final waiting = active.where((race) => race.participantCount <= 1).toList();
    final inMotion = active.where((race) => race.participantCount > 1).toList();
    final needsAttention = inMotion.isNotEmpty
        ? inMotion.first
        : active.isNotEmpty
        ? active.first
        : null;
    final inMotionRows = inMotion
        .where((race) => race.id != needsAttention?.id)
        .toList();
    final finished = raceState.races.where(raceIsCompleted).toList();

    final screen = Scaffold(
      backgroundColor: context.themeColors.page,
      body: RefreshIndicator(
        color: NuvoColors.blue,
        backgroundColor: context.themeColors.surface,
        onRefresh: () => ref.read(raceControllerProvider.notifier).loadRaces(),
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: _CompactHeader(
                activeCount: active.length,
                finishedCount: finished.length,
                onStart: () {
                  if (ref.read(firstRaceGuideProvider) ==
                      FirstRaceGuideStep.competeStart) {
                    ref.read(firstRaceGuideProvider.notifier).state =
                        FirstRaceGuideStep.composerName;
                  }
                  context.push('/races/new');
                },
                onJoin: () => context.push('/races/join'),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                NuvoSpacing.pageHorizontal,
                // Header actions → featured card gets a real section gap,
                // not a seam — the top of the page breathes.
                NuvoSpacing.xl,
                NuvoSpacing.pageHorizontal,
                0,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  if (raceState.loading && raceState.races.isEmpty)
                    const _CompeteSkeleton(key: ValueKey('compete-skeleton'))
                  else if (raceState.error != null && raceState.races.isEmpty)
                    NuvoErrorState(
                      message: "Couldn't load your races.",
                      onRetry: () =>
                          ref.read(raceControllerProvider.notifier).loadRaces(),
                    )
                  else if (raceState.races.isEmpty || cameraRaces.isEmpty)
                    _EmptyState(
                      onStart: () => context.push('/races/new'),
                      onJoin: () => context.push('/races/join'),
                    )
                  else ...[
                    if (needsAttention != null) ...[
                      _buildFeaturedCard(needsAttention, uid),
                      const SizedBox(height: NuvoSpacing.xl),
                    ],
                    if (inMotionRows.isNotEmpty) ...[
                      _CappedRaceList(
                        races: inMotionRows,
                        userId: uid,
                        expanded: _racesExpanded,
                        cap: _racesCap,
                        onToggleExpand: () =>
                            setState(() => _racesExpanded = !_racesExpanded),
                        onOpen: (race) => context.push('/race/${race.id}'),
                      ),
                      // Back to canvas — a real section beat separates the
                      // field from the secondary destinations below it.
                      const SizedBox(height: NuvoSpacing.xl),
                    ],
                    if (waiting.isNotEmpty) ...[
                      NuvoWaitingCrewSummary(
                        raceCount: waiting.length,
                        totalWaitingSlots: _totalWaitingSlots(waiting),
                        avatars: _collectAvatars(waiting, uid),
                        expanded: _waitingExpanded,
                        onToggle: () => setState(
                          () => _waitingExpanded = !_waitingExpanded,
                        ),
                        children: [
                          const SizedBox(height: NuvoSpacing.sm),
                          _SummaryExpansionList(
                            races: waiting,
                            userId: uid,
                            onOpen: (race) => context.push('/race/${race.id}'),
                          ),
                        ],
                      ),
                      const SizedBox(height: NuvoSpacing.sm),
                    ],
                    if (finished.isNotEmpty) ...[
                      NuvoFinishedSummary(
                        raceCount: finished.length,
                        wonCount: _wonCount(finished, uid),
                        expanded: _finishedExpanded,
                        onToggle: () => setState(
                          () => _finishedExpanded = !_finishedExpanded,
                        ),
                        children: [
                          const SizedBox(height: NuvoSpacing.sm),
                          _FinishedExpansionList(
                            races: finished,
                            userId: uid,
                            onOpen: (race) => context.push('/race/${race.id}'),
                          ),
                        ],
                      ),
                      const SizedBox(height: NuvoSpacing.sm),
                    ],
                  ],
                ]),
              ),
            ),
            // Quick starts flow as one continuous grid — the shell's dock
            // occlusion covers whatever crosses the fold, so a seam split
            // would only manufacture a dead zone between the last fitting
            // row and the tiles below it.
            if (raceState.races.isNotEmpty && cameraRaces.isNotEmpty)
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  NuvoSpacing.pageHorizontal,
                  0,
                  NuvoSpacing.pageHorizontal,
                  NuvoBottomNav.bottomPadding(context),
                ),
                sliver: SliverToBoxAdapter(
                  child: _QuickStarts(
                    onStart: (prefill) =>
                        context.push('/races/new', extra: prefill),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.only(
                  bottom: NuvoBottomNav.bottomPadding(context),
                ),
                sliver: const SliverToBoxAdapter(child: SizedBox.shrink()),
              ),
          ],
        ),
      ),
    );

    final guide = ref.watch(firstRaceGuideProvider);
    if (guide != FirstRaceGuideStep.competeStart) return screen;
    return Stack(
      children: [
        screen,
        FirstRaceGuideCoach(
          step: guide,
          targetKey: FirstRaceGuideKeys.competeStart,
          eyebrow: 'FIRST MOVE',
          title: 'Start your first race.',
          body: 'Tap Start.',
        ),
      ],
    );
  }

  Widget _buildFeaturedCard(Race race, String? uid) {
    final myPart = uid != null ? race.participantFor(uid) : null;
    final pct = raceProgressPercent(race, myPart);
    final rank = rankForUser(race, uid);
    final activity = raceActivityTitle(race);
    final target = raceTargetLabel(race);
    final progressLabel = raceProgressLabel(race, myPart);

    final avatars = _collectAvatars([race], uid);
    final racerStack = RacePeople(
      avatars: avatars,
      total: race.participantCount,
      size: 28,
      max: 4,
    );

    final hasProof = pct > 0;
    void open() => context.push('/race/${race.id}');
    void flip() {
      NuvoHaptics.select();
      setState(() => _featuredFlipped = !_featuredFlipped);
    }

    // The featured race reads as a standing, not metadata: the viewer's
    // score is the anchor, the lane names the marks (You / rival / Goal),
    // and the stakes line says what the next proof changes. Rival and gap
    // data come only from canonical server state — never invented.
    final c = context.themeColors;
    final myValue = myPart?.progressValue ?? 0;
    final targetValue = race.targetValue;
    final isSeconds = raceMetric(race) == RaceMetric.seconds;
    String fmt(int v) => isSeconds ? formatClock(v) : '$v';

    // Lane geometry is canonical: a real finish target gives a literal
    // share-of-distance lane; best-attempt and lower-wins races get a
    // relative-competition lane with no goal ring.
    final geo = raceLaneGeometry(race, uid);
    final vc = race.viewerContext;
    final completed = raceIsCompleted(race);
    final leading = (vc?.isLeading ?? false) || rank == 1;
    final tied = vc?.isTied ?? false;
    final rival = raceNearestRival(race, uid);
    final rivalMark = rival == null
        ? null
        : geo.rivals
            .where((r) => r.racer.userId == rival.userId)
            .firstOrNull;

    List<RaceTrackMarker>? markers;
    String? anchorValue;
    String? anchorSuffix;
    String? goalLabel;
    if (geo.hasGoal) {
      anchorValue = fmt(myValue);
      anchorSuffix = '/ ${raceScoreLabel(race, targetValue!)}';
      goalLabel = 'Goal ${fmt(targetValue)}';
    } else {
      // No denominator — the score stands alone ("78 strokes", not "0%").
      anchorValue = raceScoreLabel(race, myValue);
    }
    if (geo.viewer != null || rivalMark != null) {
      markers = [
        if (rivalMark != null)
          RaceTrackMarker(
            fraction: rivalMark.fraction,
            label:
                '${_firstName(rival!.displayName)} ${fmt(rival.progressValue)}',
            color: c.ink,
            // A tied race gives the rival the viewer's physical mark size —
            // equal standing reads as equal marks.
            size: tied ? 11 : null,
          ),
        if (geo.viewer != null)
          RaceTrackMarker(
            fraction: geo.viewer!,
            label: 'You ${fmt(myValue)}',
            color: leading ? NuvoColors.success : NuvoColors.actionBlue,
            isViewer: true,
            haloColor:
                leading && !completed ? NuvoColors.success : null,
          ),
      ];
    }

    // Two semantic faces (docs/ui/NUVO_PLAY_SYSTEM.md §13.4): front = "what
    // race is this and what can I do?", back = "what's happening inside it?"
    // The card flips; page geometry around it never does. Card taps still
    // open the race — the flip belongs to the labelled ↻ affordances only.
    return NuvoFlipCard(
      flipped: _featuredFlipped,
      front: NuvoFeaturedRaceCard(
        raceId: race.id,
        activityLabel: activity,
        targetLabel: target,
        raceTitle: race.displayTitle,
        progressPercent: pct,
        progressLabel: progressLabel,
        racerStack: racerStack,
        rank: rank,
        showRank: hasProof,
        actionLabel: hasProof ? 'View leaderboard' : 'Open race',
        ctaIcon: null,
        headerAction: _FlipAffordance(label: 'Updates ↻', onTap: flip),
        anchorValue: anchorValue,
        anchorSuffix: anchorSuffix,
        trackMarkers: markers,
        goalLabel: goalLabel,
        trackFillColor:
            leading ? NuvoColors.success : NuvoColors.actionBlue,
        trackHasGoal: geo.hasGoal,
        goalReached: completed,
        contextNote: _stakesLine(race, uid),
        // Always open the race board (the leaderboard). Logging progress /
        // verifying happens from the pinned action on that screen — every
        // "open a race" tap in the app lands in the same place.
        onOpen: open,
      ),
      back: _FeaturedRaceStatusFace(
        race: race,
        userId: uid,
        flipAction: _FlipAffordance(label: 'Race ↻', onTap: flip),
        onOpen: open,
      ),
    );
  }

  /// The stakes under the hero lane — what the next proof changes. Order:
  /// the server's viewerContext verdict (lead / tied / gap) first, then the
  /// honest "distance left" fallback when no verdict exists.
  String? _stakesLine(Race race, String? uid) {
    final vc = race.viewerContext;
    if (vc != null) {
      if (vc.isLeading) {
        final gap = vc.gapToNextRank;
        return gap != null && gap > 0
            ? 'You lead by ${raceScoreLabel(race, gap)}'
            : 'You lead';
      }
      if (vc.isTied && vc.rank == 1) return 'Tied at the front';
      final gap = vc.gapToLeader;
      if (gap != null && gap > 0) {
        return '${raceScoreLabel(race, gap)} to take 1st';
      }
    }
    final myPart = uid != null ? race.participantFor(uid) : null;
    final target = race.targetValue;
    if (target != null &&
        target > 0 &&
        myPart != null &&
        target > myPart.progressValue) {
      return '${raceScoreLabel(race, target - myPart.progressValue)} left';
    }
    return null;
  }

  int _wonCount(List<Race> races, String? uid) {
    if (uid == null) return 0;
    var count = 0;
    for (final race in races) {
      if (rankForUser(race, uid) == 1) count++;
    }
    return count;
  }

  int _totalWaitingSlots(List<Race> waiting) {
    // Each waiting race has 1 participant (the creator). A "full" race has 2+.
    // We show up to 3 empty slots total across all waiting races.
    return waiting.length.clamp(0, 3);
  }

  /// Collect avatar tuples from race participants (excluding the current user
  /// so the stack shows opponents, not self).
  List<({String initials, String? photoUrl, String id})> _collectAvatars(
    List<Race> races,
    String? uid,
  ) {
    final result = <({String initials, String? photoUrl, String id})>[];
    for (final race in races) {
      for (final p in race.participants) {
        if (p.userId == uid) continue;
        final name = p.displayName.trim();
        final initials = name.isEmpty
            ? '?'
            : name
                  .split(RegExp(r'\s+'))
                  .where((w) => w.isNotEmpty)
                  .take(2)
                  .map((w) => w[0].toUpperCase())
                  .join();
        result.add((
          initials: initials,
          photoUrl: p.profilePhotoUrl,
          id: p.userId,
        ));
      }
    }
    return result;
  }
}

// ── Compact header ────────────────────────────────────────────────────────────

class _CompactHeader extends StatelessWidget {
  const _CompactHeader({
    required this.activeCount,
    required this.finishedCount,
    required this.onStart,
    required this.onJoin,
  });

  final int activeCount;
  final int finishedCount;
  final VoidCallback onStart;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final summary = finishedCount > 0
        ? '$activeCount active · $finishedCount finished'
        : '$activeCount ${activeCount == 1 ? 'race' : 'races'} active';

    // On narrow phones the title would have to truncate to fit beside the
    // actions — drop the buttons to their own row instead so the title
    // stays whole and Start still reads as the primary move.
    final compact = context.isCompactWidth;
    final start = NuvoPrimaryButton(
      key: FirstRaceGuideKeys.competeStart,
      label: 'Start',
      onPressed: onStart,
      small: true,
      expand: compact,
      // Tighter padding than a full-width button so the title +
      // both actions fit at the 1.3 text-scale clamp.
      horizontalPadding: 16,
    );
    final join = NuvoOutlineButton(
      label: 'Join',
      onPressed: onJoin,
      small: true,
      expand: compact,
      horizontalPadding: 14,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NuvoSpacing.pageHorizontal,
        NuvoSpacing.lg,
        NuvoSpacing.pageHorizontal,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Compete',
                      style: AppTextStyles.screenTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: NuvoSpacing.xs),
                    Text(
                      summary,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: context.themeColors.inkMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (!compact) ...[
                start,
                const SizedBox(width: NuvoSpacing.sm),
                join,
              ],
            ],
          ),
          if (compact) ...[
            const SizedBox(height: NuvoSpacing.md),
            Row(
              children: [
                // Primary takes the bigger share; Join stays secondary.
                Expanded(flex: 3, child: start),
                const SizedBox(width: NuvoSpacing.sm),
                Expanded(flex: 2, child: join),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── Capped race list with inline See all ──────────────────────────────────────

class _CappedRaceList extends StatelessWidget {
  const _CappedRaceList({
    required this.races,
    required this.userId,
    required this.expanded,
    required this.cap,
    required this.onToggleExpand,
    required this.onOpen,
  });

  final List<Race> races;
  final String? userId;
  final bool expanded;
  final int cap;
  final VoidCallback onToggleExpand;
  final ValueChanged<Race> onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final visible = expanded ? races : races.take(cap).toList();
    final hasMore = races.length > cap;
    // A race is an object only once it has real motion behind it — a race
    // on the start line is still information, and stays flat on the field.
    bool hasMotion(Race race) =>
        raceProgressPercent(
          race,
          userId != null ? race.participantFor(userId!) : null,
        ) >
        0;

    // The active-races field — a middle plane between the hero and the
    // canvas. Ice tint groups the section; no navy edge, no shadow —
    // grouping is the plane's whole job.
    return Container(
      padding: const EdgeInsets.fromLTRB(
        NuvoSpacing.sm,
        NuvoSpacing.md,
        NuvoSpacing.sm,
        NuvoSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: c.panelLight,
        borderRadius: BorderRadius.circular(NuvoRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: NuvoSpacing.xs),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Your races · ${races.length} active',
                    style: AppTextStyles.sectionTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
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
                          color: context.themeColors.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: NuvoSpacing.xs),
          // Two tiers on one field: races with motion rise off the plane as
          // white objects; start-line races stay flat, hairlines between
          // them — depth is earned by progress, not handed to every row.
          for (var i = 0; i < visible.length; i++) ...[
            if (i > 0) const SizedBox(height: NuvoSpacing.xs),
            if (i > 0 && !hasMotion(visible[i]) && !hasMotion(visible[i - 1]))
              Padding(
                padding: const EdgeInsets.only(bottom: NuvoSpacing.xs),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: c.divider,
                ),
              ),
            _buildRow(context, visible[i], i + 1, raised: hasMotion(visible[i])),
          ],
        ],
      ),
    );
  }

  Widget _buildRow(
    BuildContext context,
    Race race,
    int index, {
    bool raised = false,
  }) {
    final c = context.themeColors;
    final myPart = userId != null ? race.participantFor(userId!) : null;
    final pct = raceProgressPercent(race, myPart);
    final rank = rankForUser(race, userId);
    final avatars = _rowAvatars(race, userId);
    final activity = raceActivityTitle(race);
    final progressLabel = raceProgressLabel(race, myPart);
    final completed = raceIsCompleted(race);
    // Distance to the finish line, when the race has a numeric target
    // still ahead of the viewer ("22 left" / "1:18 left").
    final targetValue = race.targetValue;
    final left = targetValue != null &&
            targetValue > 0 &&
            myPart != null &&
            targetValue > myPart.progressValue
        ? targetValue - myPart.progressValue
        : null;
    final remaining = left == null
        ? null
        : '${raceMetric(race) == RaceMetric.seconds ? formatClock(left) : left} left';

    // Quick lane — the viewer's mark plus the racer directly ahead. Lower-
    // wins and best-attempt races get the relative-competition lane (no
    // finish ring) from the shared geometry helper.
    final geo = raceLaneGeometry(race, userId);
    final rival = raceNearestRival(race, userId);
    final rivalMark = rival == null
        ? null
        : geo.rivals
            .where((r) => r.racer.userId == rival.userId)
            .firstOrNull;
    final leading = rank == 1 || (race.viewerContext?.isLeading ?? false);
    List<RaceTrackMarker>? markers;
    if (geo.viewer != null) {
      markers = [
        if (rivalMark != null)
          RaceTrackMarker(
            fraction: rivalMark.fraction,
            label: _firstName(rival!.displayName),
            color: c.ink,
          ),
        RaceTrackMarker(
          fraction: geo.viewer!,
          label: 'You',
          color: leading ? NuvoColors.success : NuvoColors.actionBlue,
          isViewer: true,
          haloColor: leading && !completed ? NuvoColors.success : null,
        ),
      ];
    }
    final contextNote = pct > 0 ? _raceRowContext(race, userId) : null;

    return NuvoRaceRow(
      raceTitle: race.displayTitle,
      movementLabel: activity,
      progressLabel: progressLabel,
      progressPercent: pct,
      rank: rank,
      participantCount: race.participantCount,
      avatars: avatars,
      remainingLabel: remaining,
      trackMarkers: markers,
      hasGoal: geo.hasGoal,
      goalReached: completed,
      contextNote: contextNote,
      contextColor: contextNote == null
          ? null
          : leading
              ? NuvoColors.success
              : NuvoColors.actionBlue,
      // Finishing pays +25 — deterministic from the server award table.
      // On the field it docks as a tag on the context line, not a third
      // text line.
      rewardArtifact: true,
      rewardLabel: myPart != null && !completed
          ? 'Finish · +$kXpFinish XP'
          : null,
      raised: raised,
      onTap: () => onOpen(race),
    );
  }

  List<({String initials, String? photoUrl, String id})> _rowAvatars(
    Race race,
    String? uid,
  ) {
    return race.participants.where((p) => p.userId != uid).map((p) {
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
  }
}

/// List of compact race rows used inside an expanded summary section.
class _SummaryExpansionList extends StatelessWidget {
  const _SummaryExpansionList({
    required this.races,
    required this.userId,
    required this.onOpen,
  });

  final List<Race> races;
  final String? userId;
  final ValueChanged<Race> onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < races.length; i++) ...[
          _buildRow(context, races[i], i + 1),
          if (i < races.length - 1)
            Divider(
              height: 1,
              thickness: 1,
              indent: 26,
              endIndent: 12,
              color: context.themeColors.divider,
            ),
        ],
      ],
    );
  }

  Widget _buildRow(BuildContext context, Race race, int index) {
    final c = context.themeColors;
    final myPart = userId != null ? race.participantFor(userId!) : null;
    final pct = raceProgressPercent(race, myPart);
    final rank = rankForUser(race, userId);
    final activity = raceActivityTitle(race);
    final progressLabel = raceProgressLabel(race, myPart);
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

    final geo = raceLaneGeometry(race, userId);
    final rival = raceNearestRival(race, userId);
    final rivalMark = rival == null
        ? null
        : geo.rivals
            .where((r) => r.racer.userId == rival.userId)
            .firstOrNull;
    final leading = rank == 1 || (race.viewerContext?.isLeading ?? false);
    final contextNote = pct > 0 ? _raceRowContext(race, userId) : null;

    return NuvoRaceRow(
      raceTitle: race.displayTitle,
      movementLabel: activity,
      progressLabel: progressLabel,
      progressPercent: pct,
      rank: rank,
      participantCount: race.participantCount,
      avatars: avatars,
      trackMarkers: geo.viewer == null
          ? null
          : [
              if (rivalMark != null)
                RaceTrackMarker(
                  fraction: rivalMark.fraction,
                  label: _firstName(rival!.displayName),
                  color: c.ink,
                ),
              RaceTrackMarker(
                fraction: geo.viewer!,
                label: 'You',
                color:
                    leading ? NuvoColors.success : NuvoColors.actionBlue,
                isViewer: true,
                haloColor: leading ? NuvoColors.success : null,
              ),
            ],
      hasGoal: geo.hasGoal,
      goalReached: raceIsCompleted(race),
      contextNote: contextNote,
      contextColor: contextNote == null
          ? null
          : leading
              ? NuvoColors.success
              : NuvoColors.actionBlue,
      rewardLabel: myPart != null ? 'Finish · +$kXpFinish XP' : null,
      onTap: () => onOpen(race),
    );
  }
}

/// List of finished race rows used inside the finished summary expansion.
class _FinishedExpansionList extends StatelessWidget {
  const _FinishedExpansionList({
    required this.races,
    required this.userId,
    required this.onOpen,
  });

  final List<Race> races;
  final String? userId;
  final ValueChanged<Race> onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < races.length; i++) ...[
          _buildRow(races[i]),
          if (i < races.length - 1)
            Divider(
              height: 1,
              thickness: 1,
              indent: 26,
              endIndent: 12,
              color: context.themeColors.divider,
            ),
        ],
      ],
    );
  }

  Widget _buildRow(Race race) {
    final rank = rankForUser(race, userId);
    final activity = raceActivityTitle(race);
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

    return NuvoFinishedRaceRow(
      raceTitle: race.displayTitle,
      movementLabel: activity,
      rank: rank,
      participantCount: race.participantCount,
      avatars: avatars,
      onTap: () => onOpen(race),
    );
  }
}

// ── Quick Starts (playable race presets) ──────────────────────────────────────

class _QuickStarts extends StatelessWidget {
  const _QuickStarts({required this.onStart});
  final ValueChanged<RaceCreatePrefill> onStart;

  static const double _tileHeight = 96;

  static final _items = [
    (
      icon: Icons.fitness_center_rounded,
      movementName: 'Pushups',
      format: 'First to 100',
      prefill: RaceCreatePrefill.pushups,
    ),
    (
      icon: Icons.sports_kabaddi_rounded,
      movementName: 'Squats',
      format: 'First to 15',
      prefill: RaceCreatePrefill.squats,
    ),
    (
      icon: Icons.accessibility_new_rounded,
      movementName: 'Jumping Jacks',
      format: 'First to 500',
      prefill: RaceCreatePrefill.jumpingJacks,
    ),
    (
      icon: Icons.directions_walk_rounded,
      movementName: 'Lunges',
      format: 'First to 40',
      prefill: RaceCreatePrefill.lunges,
    ),
    (
      icon: Icons.timer_outlined,
      movementName: 'Plank',
      format: '300-sec hold',
      prefill: RaceCreatePrefill.plank,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    // One continuous grid — the dock's occlusion mask hides whatever
    // crosses the fold, and scroll reveals it. Rows flow at the wrap's
    // run spacing; a lone last item spans the row instead of sitting as
    // a broken half-tile.
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - NuvoSpacing.sm) / 2;
        Widget tile(int i) {
          final item = _items[i];
          return SizedBox(
            width: i == _items.length - 1 && _items.length.isOdd
                ? constraints.maxWidth
                : itemWidth,
            height: _tileHeight,
            child: _QuickStartTile(
              icon: item.icon,
              movementName: item.movementName,
              format: item.format,
              onTap: () => onStart(item.prefill),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: NuvoSpacing.lg),
            Text('Quick starts', style: AppTextStyles.sectionTitle),
            const SizedBox(height: NuvoSpacing.sm),
            Wrap(
              spacing: NuvoSpacing.sm,
              runSpacing: NuvoSpacing.sm,
              children: [for (var i = 0; i < _items.length; i++) tile(i)],
            ),
          ],
        );
      },
    );
  }
}

/// A playable race preset. One visual contract for every tile: quiet
/// navy border on white, movement icon in an ice well, movement name,
/// then the game format in blue — pick a game, not a configuration.
/// No alternating fills: a tile is tappable or it doesn't exist.
class _QuickStartTile extends StatelessWidget {
  const _QuickStartTile({
    required this.icon,
    required this.movementName,
    required this.format,
    required this.onTap,
  });

  final IconData icon;
  final String movementName;
  final String format;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      scale: 0.96,
      child: Container(
        padding: const EdgeInsets.all(NuvoSpacing.md),
        decoration: BoxDecoration(
          color: context.themeColors.surface,
          borderRadius: BorderRadius.circular(NuvoRadii.md),
          border: Border.all(color: context.themeColors.border, width: 1.25),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: context.themeColors.panelLight,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    icon,
                    color: context.themeColors.ink,
                    size: 17,
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.arrow_forward_rounded,
                  color: context.themeColors.inkDim,
                  size: 15,
                ),
              ],
            ),
            const Spacer(),
            Text(
              movementName,
              style: AppTextStyles.titleMedium.copyWith(
                fontSize: 14,
                height: 1.1,
                color: context.themeColors.ink,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            Text(
              format,
              style: AppTextStyles.raceRowMeta.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: NuvoColors.blue,
                letterSpacing: 0.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Loading skeleton ──────────────────────────────────────────────────────────

class _CompeteSkeleton extends StatelessWidget {
  const _CompeteSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    Widget block(
      double height, {
      double? width,
      double radius = NuvoRadii.md,
    }) => Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: context.themeColors.surface,
        borderRadius: BorderRadius.circular(radius),
      ),
    );

    return Shimmer.fromColors(
      baseColor: context.themeColors.divider,
      highlightColor: context.themeColors.surface,
      period: const Duration(milliseconds: 1400),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          block(150, radius: NuvoRadii.lg),
          const SizedBox(height: NuvoSpacing.xxl),
          block(16, width: 140, radius: NuvoRadii.badge),
          const SizedBox(height: NuvoSpacing.sm),
          block(64),
          const SizedBox(height: NuvoSpacing.xs),
          block(64),
          const SizedBox(height: NuvoSpacing.xs),
          block(64),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onStart, this.onJoin});
  final VoidCallback onStart;
  final VoidCallback? onJoin;

  @override
  Widget build(BuildContext context) {
    // Compact by design — the header already owns Start/Join; Arena carries
    // the first-run pitch. This just anchors where races will appear.
    return NuvoEmptyState(
      icon: Icons.flag_rounded,
      title: 'Your races will live here.',
      body: 'Start a race or join with a code — every finish line you set '
          'lands here.',
      ctaLabel: 'Start a race',
      onCta: onStart,
      secondaryLabel: onJoin != null ? 'Join with a code' : null,
      onSecondary: onJoin,
      compact: true,
    );
  }
}

/// First name for lane/rivalry labels — rivals are people, and first names
/// are how a crew actually reads them.
/// The one-line stakes under a quick row — what the next proof changes.
/// Server verdicts first, then the honest "to pass" gap computed from
/// canonical standings; never fabricated.
String? _raceRowContext(Race race, String? uid) {
  final vc = race.viewerContext;
  final rival = raceNearestRival(race, uid);
  final rivalName = rival == null ? null : _firstName(rival.displayName);
  if (vc != null) {
    if (vc.isLeading) {
      final gap = vc.gapToNextRank;
      return gap != null && gap > 0 && rivalName != null
          ? 'You lead $rivalName by ${raceScoreLabel(race, gap)}'
          : 'You lead';
    }
    if (vc.isTied && vc.rank == 1) return 'Tied at the front';
    if (rivalName != null && vc.gapToNextRank != null) {
      return '${raceScoreLabel(race, vc.gapToNextRank!)} to pass '
          '$rivalName';
    }
  }
  final myPart = uid != null ? race.participantFor(uid) : null;
  if (rival != null && myPart != null) {
    final gap = (rival.progressValue - myPart.progressValue).abs();
    if (gap > 0) {
      return '${raceScoreLabel(race, gap)} to pass $rivalName';
    }
    if (rivalName != null) return 'Level with $rivalName';
  }
  return null;
}

String _firstName(String displayName) {
  final first = displayName.trim().split(RegExp(r'\s+')).firstOrNull ?? '';
  return first.isEmpty ? 'Crew' : first;
}

// ── Featured card faces ─────────────────────────────────────────────────────

/// The labelled ↻ control both faces of the featured card expose — the flip
/// is never hidden behind a mystery tap. Quiet labelSmall text: the card
/// content and its CTA stay dominant.
class _FlipAffordance extends StatelessWidget {
  const _FlipAffordance({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: NuvoPressable(
        haptic: false, // the flip fires select once
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 0, 8),
          child: Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: NuvoColors.blue,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }
}

/// The featured card's back face — "what's happening inside this race?"
/// answered from canonical race data only: server-ranked standings, the
/// viewer's competitive context (lead / gap), and the latest proof or
/// update timestamp. Same card chrome as the front (navy outline + hard
/// shadow + blue action strip) so the flip reads as one object turning,
/// not a different card appearing.
class _FeaturedRaceStatusFace extends StatelessWidget {
  const _FeaturedRaceStatusFace({
    required this.race,
    required this.userId,
    required this.flipAction,
    required this.onOpen,
  });

  final Race race;
  final String? userId;
  final Widget flipAction;
  final VoidCallback onOpen;

  static String _ago(String iso) {
    try {
      final diff = DateTime.now().difference(DateTime.parse(iso).toLocal());
      if (diff.inSeconds < 60) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return '';
    }
  }

  static String _first(String displayName) => displayName.split(' ').first;

  /// "You lead by 6 reps" / "6 reps behind Riley" / "Tied at the front" —
  /// the server's viewerContext is the canonical read; derived standings
  /// only fill the gaps it doesn't cover.
  String? _positionLine(List<RaceParticipant> ranked) {
    final vc = race.viewerContext;
    final leaderName = ranked.isEmpty
        ? null
        : _first(
            ranked
                .firstWhere(
                  (p) => p.userId == vc?.leaderUserId,
                  orElse: () => ranked.first,
                )
                .displayName,
          );
    if (vc != null) {
      if (vc.isLeading) {
        final gap = vc.gapToNextRank;
        return gap != null && gap > 0
            ? 'You lead by ${raceScoreLabel(race, gap)}'
            : 'You lead';
      }
      if (vc.isTied && vc.rank == 1) return 'Tied at the front';
      final gap = vc.gapToLeader;
      if (gap != null && gap > 0) {
        return leaderName == null
            ? '${raceScoreLabel(race, gap)} behind'
            : '${raceScoreLabel(race, gap)} behind $leaderName';
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ranked = serverRankedParticipants(race);
    final top = ranked.take(3).toList();
    final myRank = rankForUser(race, userId);
    final meBelow =
        userId != null && myRank != null && myRank > 3
            ? ranked.where((p) => p.userId == userId).firstOrNull
            : null;
    final position = _positionLine(ranked);
    final proof = race.recentProofs.isEmpty ? null : race.recentProofs.first;
    final proofValue = proof?.value ?? proof?.detectedValue;
    final latest = proof == null
        ? 'Last update · ${_ago(race.updatedAt)}'
        : '${proof.userId == userId ? 'You' : _first(proof.displayName)} '
            'logged '
            '${proofValue == null
                ? 'a proof'
                : raceScoreLabel(race, proofValue)}'
            ' · ${_ago(proof.createdAt)}';
    final anyProgress = ranked.any((p) => p.progressValue > 0);

    final c = context.themeColors;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(NuvoRadii.lg),
        border: Border.all(color: c.border, width: 2),
        boxShadow: AppShadows.hardOffset(
          c.inkShadow,
          offset: const Offset(7, 7),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(NuvoRadii.lg - 1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              color: c.surface,
              padding: const EdgeInsets.fromLTRB(
                NuvoSpacing.lg,
                NuvoSpacing.md,
                NuvoSpacing.lg,
                NuvoSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'RACE STATUS',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: c.inkMuted,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const Spacer(),
                      flipAction,
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (!anyProgress)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        ranked.length <= 1
                            ? 'Waiting for the first proof — it sets the pace.'
                            : 'No proofs yet — the board is still open.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: c.inkMuted,
                        ),
                      ),
                    )
                  else ...[
                    for (final p in top)
                      _StandingRow(
                        rank: p.rank ?? (top.indexOf(p) + 1),
                        name:
                            p.userId == userId ? 'You' : _first(p.displayName),
                        score: raceScoreLabel(race, p.progressValue),
                        isMe: p.userId == userId,
                      ),
                    if (meBelow != null)
                      _StandingRow(
                        rank: myRank!,
                        name: 'You',
                        score:
                            raceScoreLabel(race, meBelow.progressValue),
                        isMe: true,
                      ),
                  ],
                  if (position != null && anyProgress) ...[
                    const SizedBox(height: 4),
                    Text(
                      position,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: c.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    latest,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.labelSmall.copyWith(
                      color: c.inkMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            // Blue action strip — same shell as the front; the single action
            // is still "open this race".
            Container(
              color: NuvoColors.actionBlue,
              padding: const EdgeInsets.symmetric(
                horizontal: NuvoSpacing.lg,
                vertical: NuvoSpacing.sm,
              ),
              child: Row(
                children: [
                  Text(
                    '${race.participantCount} racing',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: NuvoColors.white.withValues(alpha: 0.85),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  NuvoPressable(
                    haptic: false,
                    onTap: onOpen,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Open race',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: NuvoColors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          color: NuvoColors.white,
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One compact standings row on the status face — placement, name, score.
class _StandingRow extends StatelessWidget {
  const _StandingRow({
    required this.rank,
    required this.name,
    required this.score,
    required this.isMe,
  });

  final int rank;
  final String name;
  final String score;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            child: Text(
              '$rank',
              style: AppTextStyles.labelSmall.copyWith(
                color: c.ink,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodySmall.copyWith(
                color: c.ink,
                fontWeight: isMe ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            score,
            style: AppTextStyles.labelSmall.copyWith(
              color: c.inkMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

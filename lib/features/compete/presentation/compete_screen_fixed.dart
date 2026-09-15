import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_geometry.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/bottom_nav.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_empty_state.dart';
import '../../../core/widgets/nuvo_error_state.dart';
import '../../../core/widgets/nuvo_race_components.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../races/data/race_models.dart';
import '../../races/domain/race_display.dart';
import '../../races/presentation/create_race_screen.dart';
import '../../races/presentation/race_controller.dart';
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
      backgroundColor: NuvoColors.page,
      body: RefreshIndicator(
        color: NuvoColors.blue,
        backgroundColor: NuvoColors.surface,
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
              padding: EdgeInsets.fromLTRB(
                NuvoSpacing.pageHorizontal,
                NuvoSpacing.lg,
                NuvoSpacing.pageHorizontal,
                NuvoBottomNav.bottomPadding(context),
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  if (raceState.loading && raceState.races.isEmpty)
                    const _CompeteSkeleton(key: ValueKey('compete-skeleton'))
                  else if (raceState.error != null && raceState.races.isEmpty)
                    NuvoErrorState(
                      message: "Couldn't load your races.",
                      onRetry: () => ref
                          .read(raceControllerProvider.notifier)
                          .loadRaces(),
                    )
                  else if (raceState.races.isEmpty || cameraRaces.isEmpty)
                    _EmptyState(
                      onStart: () => context.push('/races/new'),
                      onJoin: () => context.push('/races/join'),
                    )
                  else ...[
                    if (needsAttention != null) ...[
                      _buildFeaturedCard(needsAttention, uid),
                      const SizedBox(height: NuvoSpacing.xxl),
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
                      const SizedBox(height: NuvoSpacing.lg),
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
                    const SizedBox(height: NuvoSpacing.xxl),
                    _QuickStarts(
                      onStart: (prefill) =>
                          context.push('/races/new', extra: prefill),
                    ),
                    const SizedBox(height: NuvoSpacing.xxl),
                  ],
                ]),
              ),
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
          title: 'Start your first race here.',
          body:
              'Tap Start. I will stay with you while you set the finish line.',
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

    return NuvoFeaturedRaceCard(
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
      // Always open the race board (the leaderboard). Logging progress /
      // verifying happens from the pinned action on that screen — every
      // "open a race" tap in the app lands in the same place.
      onOpen: () => context.push('/race/${race.id}'),
    );
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

    final topInset = MediaQuery.of(context).padding.top;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        NuvoSpacing.pageHorizontal,
        topInset + NuvoSpacing.xl,
        NuvoSpacing.pageHorizontal,
        0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Compete', style: AppTextStyles.screenTitle),
                const SizedBox(height: NuvoSpacing.xs),
                Text(
                  summary,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: NuvoColors.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          NuvoPrimaryButton(
            key: FirstRaceGuideKeys.competeStart,
            label: 'Start',
            onPressed: onStart,
            small: true,
          ),
          const SizedBox(width: NuvoSpacing.sm),
          NuvoOutlineButton(label: 'Join', onPressed: onJoin, small: true),
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
    final visible = expanded ? races : races.take(cap).toList();
    final hasMore = races.length > cap;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                'Your races · ${races.length} active',
                style: AppTextStyles.sectionTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Spacer(),
            if (hasMore)
              GestureDetector(
                onTap: onToggleExpand,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Text(
                    expanded ? 'Show less' : 'See all',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: NuvoColors.navy,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: NuvoSpacing.sm),
        Container(
          decoration: BoxDecoration(
            color: NuvoColors.surface,
            borderRadius: BorderRadius.circular(NuvoRadii.md),
            border: NuvoBorders.hero,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < visible.length; i++) ...[
                _buildRow(visible[i], i + 1),
                if (i < visible.length - 1)
                  const Divider(
                    height: 1,
                    thickness: 1,
                    indent: 54,
                    color: NuvoColors.divider,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRow(Race race, int index) {
    final myPart = userId != null ? race.participantFor(userId!) : null;
    final pct = raceProgressPercent(race, myPart);
    final rank = rankForUser(race, userId);
    final avatars = _rowAvatars(race, userId);
    final activity = raceActivityTitle(race);
    final progressLabel = raceProgressLabel(race, myPart);

    return NuvoRaceRow(
      raceTitle: race.displayTitle,
      movementLabel: activity,
      progressLabel: progressLabel,
      progressPercent: pct,
      rank: rank,
      participantCount: race.participantCount,
      avatars: avatars,
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
    return Container(
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(NuvoRadii.md),
        border: NuvoBorders.hero,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < races.length; i++) ...[
            _buildRow(races[i], i + 1),
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

  Widget _buildRow(Race race, int index) {
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

    return NuvoRaceRow(
      raceTitle: race.displayTitle,
      movementLabel: activity,
      progressLabel: progressLabel,
      progressPercent: pct,
      rank: rank,
      participantCount: race.participantCount,
      avatars: avatars,
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
    return Container(
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(NuvoRadii.md),
        border: NuvoBorders.hero,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < races.length; i++) ...[
            _buildRow(races[i]),
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

// ── Quick Starts (compact 2-column wrap) ──────────────────────────────────────

class _QuickStarts extends StatelessWidget {
  const _QuickStarts({required this.onStart});
  final ValueChanged<RaceCreatePrefill> onStart;

  static const _items = [
    (
      icon: Icons.fitness_center_rounded,
      movementName: 'Pushups',
      target: '100 reps',
      prefill: RaceCreatePrefill.pushups,
    ),
    (
      icon: Icons.accessibility_new_rounded,
      movementName: 'Squats',
      target: '15 reps',
      prefill: RaceCreatePrefill.squats,
    ),
    (
      icon: Icons.accessibility_new_rounded,
      movementName: 'Jumping Jacks',
      target: '500 reps',
      prefill: RaceCreatePrefill.jumpingJacks,
    ),
    (
      icon: Icons.directions_walk_rounded,
      movementName: 'Lunges',
      target: '40 reps',
      prefill: RaceCreatePrefill.lunges,
    ),
    (
      icon: Icons.timer_outlined,
      movementName: 'Plank',
      target: '300 sec',
      prefill: RaceCreatePrefill.plank,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick starts', style: AppTextStyles.sectionTitle),
        const SizedBox(height: NuvoSpacing.sm),
        SizedBox(
          height: 56,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(right: NuvoSpacing.pageHorizontal),
            itemCount: _items.length,
            separatorBuilder: (_, _) => const SizedBox(width: NuvoSpacing.sm),
            itemBuilder: (_, index) {
              final item = _items[index];
              return _QuickStartChip(
                icon: item.icon,
                movementName: item.movementName,
                target: item.target,
                onTap: () => onStart(item.prefill),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _QuickStartChip extends StatelessWidget {
  const _QuickStartChip({
    required this.icon,
    required this.movementName,
    required this.target,
    required this.onTap,
  });

  final IconData icon;
  final String movementName;
  final String target;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      scale: 0.96,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: NuvoSpacing.lg,
          vertical: NuvoSpacing.sm + 2,
        ),
        decoration: BoxDecoration(
          color: NuvoColors.surface,
          borderRadius: BorderRadius.circular(NuvoRadii.md),
          border: NuvoBorders.hero,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: NuvoColors.navy, size: 18),
            const SizedBox(width: NuvoSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  movementName,
                  style: AppTextStyles.raceRowTitle.copyWith(
                    fontSize: 13,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  target,
                  style: AppTextStyles.raceRowMeta.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: NuvoColors.muted,
                    letterSpacing: 0.2,
                  ),
                  maxLines: 1,
                ),
              ],
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
    Widget block(double height, {double? width, double radius = NuvoRadii.md}) =>
        Container(
          height: height,
          width: width,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(radius),
          ),
        );

    return Shimmer.fromColors(
      baseColor: NuvoColors.divider,
      highlightColor: NuvoColors.surface,
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
    return NuvoEmptyState(
      icon: Icons.flag_rounded,
      title: 'No races yet',
      body: 'Create one to set a finish line — pushups, a plank, a daily '
          'check-in — then pull in your crew. Every proof you log moves the '
          'board.',
      ctaLabel: 'Create a race',
      onCta: onStart,
      secondaryLabel: onJoin != null ? 'Join with a code' : null,
      onSecondary: onJoin,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_geometry.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/bottom_nav.dart';
import '../../../core/widgets/nuvo_empty_state.dart';
import '../../../core/widgets/nuvo_error_state.dart';
import '../../../core/widgets/nuvo_loading_indicator.dart';
import '../../../core/widgets/nuvo_race_components.dart';
import '../../../core/widgets/nuvo_motion.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../notifications/domain/notification_display.dart';
import '../../races/data/race_models.dart';
import '../../races/domain/camera_verification_resolver.dart';
import '../../races/domain/chase_context.dart';
import '../../races/domain/race_display.dart';
import '../../races/presentation/race_controller.dart';

/// Verify — Variant B IA.
///
/// Screen question: "What should I act on next, and how do I get into
/// verification immediately?"
///
/// Structure:
/// 1. Compact Verify header ("Verify" + "N ready to move")
/// 2. Ready / Completed / Recent segmented state
/// 3. ONE loud "Up next" verification card (Ready segment only)
/// 4. "Also ready" compact rows (capped, inline See all)
/// 5. No repeated full-width Verify buttons
/// 6. Completed/Recent shown through the segmented state
class MoveScreen extends ConsumerStatefulWidget {
  const MoveScreen({super.key});

  @override
  ConsumerState<MoveScreen> createState() => _MoveScreenState();
}

enum _VerifySegment { ready, completed, recent }

class _MoveScreenState extends ConsumerState<MoveScreen> {
  _VerifySegment _segment = _VerifySegment.ready;
  int _segmentDirection = 1;
  bool _readyExpanded = false;
  bool _completedExpanded = false;
  bool _recentExpanded = false;

  // Generous defaults, not "exactly enough to match a mockup" — a real
  // viewport with real data should read as populated, not artificially
  // truncated to three rows with a blank lower half. "See all" still exists
  // for the true long tail.
  static const _readyCap = 8;
  static const _completedCap = 8;
  static const _recentCap = 8;

  void _setSegment(_VerifySegment next) {
    if (next == _segment) return;
    final oldIndex = _VerifySegment.values.indexOf(_segment);
    final nextIndex = _VerifySegment.values.indexOf(next);
    setState(() {
      _segmentDirection = nextIndex >= oldIndex ? 1 : -1;
      _segment = next;
      _readyExpanded = false;
      _completedExpanded = false;
      _recentExpanded = false;
    });
  }

  void _moveSegment(int delta) {
    final index = _VerifySegment.values.indexOf(_segment);
    final nextIndex = (index + delta).clamp(
      0,
      _VerifySegment.values.length - 1,
    );
    _setSegment(_VerifySegment.values[nextIndex]);
  }

  @override
  Widget build(BuildContext context) {
    final raceState = ref.watch(raceControllerProvider);
    final user = ref.watch(authControllerProvider).user;
    final uid = user?.id;

    // Camera and non-camera (manual / check-in) goals both surface here — a
    // manual race is still "ready to move", it just logs progress instead of
    // opening the camera.
    final cameraRaces = raceState.races;

    // Ready order = distance to the finish line — the race that needs the
    // least proof leads ("what can I prove next" = "what finishes soonest").
    // Decorated index sort keeps the server's order on ties (Dart's sort
    // isn't stable).
    final readyUnsorted = cameraRaces.where((race) {
      final myPart = uid != null ? race.participantFor(uid) : null;
      return race.status == 'active' && (myPart?.progressPercent ?? 0) < 100;
    }).toList();
    final readyRaces = [
      for (final e in readyUnsorted.indexed.toList()
        ..sort((a, b) {
          final pa = _remainingToGoal(a.$2, uid);
          final pb = _remainingToGoal(b.$2, uid);
          return pa != pb ? pa.compareTo(pb) : a.$1.compareTo(b.$1);
        }))
        e.$2,
    ];

    final completedRaces = cameraRaces.where((race) {
      final myPart = uid != null ? race.participantFor(uid) : null;
      return (myPart?.progressPercent ?? 0) >= 100;
    }).toList();

    final recentMoves = cameraRaces
        .expand((r) => r.recentProofs.map((p) => (race: r, proof: p)))
        .take(20)
        .toList();

    void openVerification(Race race) {
      debugLogCameraVerificationDecision(
        race,
        resolveCameraVerification(race),
        routeAction: 'move_screen_to_submit_proof',
      );
      context.push('/race/${race.id}/proof').then((_) {
        ref.read(raceControllerProvider.notifier).loadRaces();
      });
    }

    final allEmpty =
        readyRaces.isEmpty && completedRaces.isEmpty && recentMoves.isEmpty;

    return Scaffold(
      backgroundColor: NuvoColors.page,
      // bottom:false — the shell's own SafeArea + Scaffold's bottomNavigationBar
      // already account for the nav; a second bottom-safe inset here doubled
      // up with the nav's own reserved height on some layouts (root cause of
      // the "content behind nav" reports, see MainShell's doc-comment).
      body: SafeArea(
        bottom: false,
        child: ListView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          padding: EdgeInsets.fromLTRB(
            22,
            32,
            22,
            NuvoBottomNav.bottomPadding(context),
          ),
          children: [
            // ── Compact header ────────────────────────────────────────
            _CompactVerifyHeader(readyCount: readyRaces.length),
            const SizedBox(height: NuvoSpacing.xl),

            // ── Loading / error / empty ───────────────────────────────
            if (raceState.loading &&
                readyRaces.isEmpty &&
                completedRaces.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: NuvoLoadingIndicator(),
                ),
              )
            else if (raceState.error != null &&
                readyRaces.isEmpty &&
                completedRaces.isEmpty)
              NuvoErrorState(
                message: "Couldn't load your races.",
                onRetry: () =>
                    ref.read(raceControllerProvider.notifier).loadRaces(),
              )
            else if (allEmpty)
              _EmptyState(onStart: () => context.push('/races/new'))
            // ── Segmented control + segment content ───────────────────
            else ...[
              _SegmentedControl(
                segment: _segment,
                readyCount: readyRaces.length,
                completedCount: completedRaces.length,
                recentCount: recentMoves.length,
                onChanged: _setSegment,
              ),
              const SizedBox(height: NuvoSpacing.xl),

              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragEnd: (details) {
                  final velocity = details.primaryVelocity ?? 0;
                  if (velocity < -120) _moveSegment(1);
                  if (velocity > 120) _moveSegment(-1);
                },
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  reverseDuration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    final offset = Tween<Offset>(
                      begin: Offset(0.12 * _segmentDirection, 0),
                      end: Offset.zero,
                    ).animate(animation);
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(position: offset, child: child),
                    );
                  },
                  child: KeyedSubtree(
                    key: ValueKey(_segment),
                    child: switch (_segment) {
                      _VerifySegment.ready => _ReadySegment(
                        races: readyRaces,
                        userId: uid,
                        expanded: _readyExpanded,
                        cap: _readyCap,
                        onToggleExpand: () =>
                            setState(() => _readyExpanded = !_readyExpanded),
                        onVerify: openVerification,
                        onStartRace: () => context.push('/races/new'),
                      ),
                      _VerifySegment.completed => _CompletedSegment(
                        races: completedRaces,
                        userId: uid,
                        expanded: _completedExpanded,
                        cap: _completedCap,
                        onToggleExpand: () => setState(
                          () => _completedExpanded = !_completedExpanded,
                        ),
                        onOpen: (race) => context.push('/race/${race.id}'),
                      ),
                      _VerifySegment.recent => _RecentSegment(
                        entries: recentMoves,
                        userId: uid,
                        expanded: _recentExpanded,
                        cap: _recentCap,
                        onToggleExpand: () =>
                            setState(() => _recentExpanded = !_recentExpanded),
                        onOpen: (race) => context.push('/race/${race.id}'),
                      ),
                    },
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Distance to the finish line for Ready ordering — the canonical
/// `viewerContext.goalRemaining` when the server sends it, else
/// `target − progress` on the participant. Races without a measurable goal
/// sort last, keeping their original (server) order among themselves.
int _remainingToGoal(Race race, String? userId) {
  final vc = race.viewerContext;
  if (vc?.goalRemaining != null) return vc!.goalRemaining!;
  final myPart = userId != null ? race.participantFor(userId) : null;
  final target = race.targetValue;
  if (target != null && target > 0 && myPart != null) {
    return (target - myPart.progressValue).clamp(0, target);
  }
  return 1 << 20;
}

/// "11 reps left" / "45s left" — the canonical score label for the gap to
/// the goal, or null when the race has no measurable finish.
String? _goalRemainingLabel(Race race, String? userId) {
  final vc = race.viewerContext;
  final remaining = vc?.goalRemaining ??
      (() {
        final myPart =
            userId != null ? race.participantFor(userId) : null;
        final target = race.targetValue;
        if (target != null && target > 0 && myPart != null) {
          return (target - myPart.progressValue).clamp(0, target);
        }
        return null;
      })();
  if (remaining == null || remaining <= 0) return null;
  return '${raceScoreLabel(race, remaining)} left';
}

// ── Compact header ────────────────────────────────────────────────────────────

class _CompactVerifyHeader extends StatelessWidget {
  const _CompactVerifyHeader({required this.readyCount});
  final int readyCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Verify', style: AppTextStyles.screenTitle),
        const SizedBox(height: NuvoSpacing.xs),
        Text(
          readyCount > 0
              ? '$readyCount ${readyCount == 1 ? 'race' : 'races'} ready to move'
              : 'No races ready to move',
          style: AppTextStyles.bodySmall.copyWith(
            color: NuvoColors.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ── Segmented control ─────────────────────────────────────────────────────────

class _SegmentedControl extends StatelessWidget {
  const _SegmentedControl({
    required this.segment,
    required this.readyCount,
    required this.completedCount,
    required this.recentCount,
    required this.onChanged,
  });

  final _VerifySegment segment;
  final int readyCount;
  final int completedCount;
  final int recentCount;
  final ValueChanged<_VerifySegment> onChanged;

  @override
  Widget build(BuildContext context) {
    // A FILTER, not three stacked buttons: label + count share one line, so
    // the whole control reads as a compact segmented switcher (~48–56px
    // total) rather than a tall three-button module. The selection is a
    // single pill that SLIDES between slots — the state moves, instead of a
    // new widget appearing per tab.
    final selectedIndex = _VerifySegment.values.indexOf(segment);
    final selectedColor = switch (segment) {
      _VerifySegment.ready => NuvoColors.blue,
      _VerifySegment.completed => NuvoColors.success,
      _VerifySegment.recent => NuvoColors.accent,
    };

    return Container(
      decoration: BoxDecoration(
        // A filter tray, not a card: quiet ice fill, no navy frame —
        // the sliding colored pill carries all the state weight.
        color: NuvoColors.panelLight,
        borderRadius: BorderRadius.circular(NuvoRadii.md),
      ),
      padding: const EdgeInsets.all(3),
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedAlign(
              // -1 / 0 / +1 across the three equal slots.
              alignment: Alignment(selectedIndex - 1.0, 0),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: FractionallySizedBox(
                widthFactor: 1 / 3,
                heightFactor: 1,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    color: selectedColor,
                    borderRadius: BorderRadius.circular(NuvoRadii.xs),
                  ),
                ),
              ),
            ),
          ),
          Row(
            children: [
              _SegmentTab(
                label: 'Ready',
                count: readyCount,
                icon: Icons.pending_actions_rounded,
                selected: segment == _VerifySegment.ready,
                // The sliding pill carries the accent color; the tab only
                // needs the on-pill foreground when selected.
                onPill: NuvoColors.white,
                onTap: () => onChanged(_VerifySegment.ready),
              ),
              _SegmentTab(
                label: 'Completed',
                count: completedCount,
                icon: Icons.check_circle_outline_rounded,
                selected: segment == _VerifySegment.completed,
                onPill: NuvoColors.white,
                onTap: () => onChanged(_VerifySegment.completed),
              ),
              _SegmentTab(
                label: 'Recent',
                count: recentCount,
                icon: Icons.history_rounded,
                selected: segment == _VerifySegment.recent,
                // Recent is history, not a warning: the restrained tan
                // accent pill takes navy text instead of white.
                onPill: NuvoColors.navy,
                onTap: () => onChanged(_VerifySegment.recent),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SegmentTab extends StatelessWidget {
  const _SegmentTab({
    required this.label,
    required this.count,
    required this.icon,
    required this.selected,
    required this.onPill,
    required this.onTap,
  });

  final String label;
  final int count;
  final IconData icon;
  final bool selected;

  /// Foreground color when the sliding pill is underneath this tab.
  final Color onPill;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Label + count share one line — a compact filter tab, not a stacked
    // two-line button. The count reads as secondary (smaller, dimmer) but
    // never disappears into its own row. The pill behind carries the state
    // color; this tab is transparent hit surface + foreground only.
    final fg = selected ? onPill : NuvoColors.textMuted;
    return Expanded(
      child: NuvoPressable(
        onTap: onTap,
        haptic: false,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelMedium.copyWith(
                    fontSize: 13,
                    color: fg,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '$count',
                maxLines: 1,
                style: AppTextStyles.labelSmall.copyWith(
                  fontSize: 11,
                  color: selected
                      ? fg.withValues(alpha: 0.75)
                      : NuvoColors.textDim,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Ready segment ─────────────────────────────────────────────────────────────

class _ReadySegment extends StatelessWidget {
  const _ReadySegment({
    required this.races,
    required this.userId,
    required this.expanded,
    required this.cap,
    required this.onToggleExpand,
    required this.onVerify,
    required this.onStartRace,
  });

  final List<Race> races;
  final String? userId;
  final bool expanded;
  final int cap;
  final VoidCallback onToggleExpand;
  final ValueChanged<Race> onVerify;
  final VoidCallback onStartRace;

  @override
  Widget build(BuildContext context) {
    if (races.isEmpty) {
      return _SegmentEmptyState(
        icon: Icons.directions_run_rounded,
        title: 'No races ready to verify.',
        subtitle: 'Start or join a race to begin logging moves.',
        actionLabel: 'Start a race',
        onAction: onStartRace,
        // "Ready to verify" is an actionable state, not a problem — brand
        // blue, not the semantic warning color reserved for actual issues.
        accent: NuvoColors.blue,
      );
    }

    final upNext = races.first;
    final alsoReady = races.skip(1).toList();
    final visibleAlsoReady = expanded
        ? alsoReady
        : alsoReady.take(cap).toList();
    final hasMore = alsoReady.length > cap;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Up next (ONE loud surface) ────────────────────────────────────────
        Text('Up next', style: AppTextStyles.sectionTitle),
        const SizedBox(height: 10),
        _UpNextCard(
          race: upNext,
          userId: userId,
          onVerify: () => onVerify(upNext),
        ),
        if (alsoReady.isNotEmpty) ...[
          const SizedBox(height: NuvoSpacing.xl),
          Row(
            children: [
              Text('Also ready', style: AppTextStyles.sectionTitle),
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
                      expanded ? 'Show less' : 'See all ${alsoReady.length}',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: NuvoColors.navy,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          // Level-0 rows directly on the page — this is a pick-list of
          // movements to perform, not a list of records. The movement glyph
          // carries the "what", the meta line carries the finish line.
          for (var i = 0; i < visibleAlsoReady.length; i++) ...[
            _ReadyMovementRow(
              race: visibleAlsoReady[i],
              userId: userId,
              onTap: () => onVerify(visibleAlsoReady[i]),
            ),
            if (i < visibleAlsoReady.length - 1)
              const Divider(
                height: 1,
                thickness: 1,
                indent: 50,
                color: NuvoColors.divider,
              ),
          ],
        ],
      ],
    );
  }
}

// ── Up next card (ONE loud surface) ───────────────────────────────────────────

class _UpNextCard extends StatelessWidget {
  const _UpNextCard({required this.race, required this.onVerify, this.userId});

  final Race race;
  final String? userId;
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    final myPart = userId != null ? race.participantFor(userId!) : null;
    final pct = raceProgressPercent(race, myPart);
    final activity = raceActivityTitle(race);
    final target = raceTargetLabel(race);
    final progressLabel = raceProgressLabel(race, myPart);
    final rank = rankForUser(race, userId);

    // "What will this proof change?" — the canonical stakes line the race
    // detail screen already speaks (ChaseContext: "Beat Noah. 14 to take
    // #2", "Defend your lead…"); fallback is the plain distance to finish.
    // Composed from server truth only — never invented context.
    final chase = userId != null ? ChaseContext.compute(race, userId!) : null;
    final contextNote =
        chase?.chaseCopy ?? _goalRemainingLabel(race, userId);

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

    // Motion-preview seam (another agent owns the runtime): a future
    // "preview movement" surface slots into RaceHero's `headerAction` —
    // a quiet ~28×28 affordance pinned to the title row's trailing edge.
    // Its activity identity is `raceActivityDefinition(race)`
    // (MotionActivityDefinition.type / .title / .preferredCameraView),
    // already computed above; race.id seeds any per-race preview cache.
    return RaceHero(
      raceId: race.id,
      activityLabel: activity,
      targetLabel: target,
      raceTitle: race.displayTitle,
      progressPercent: pct,
      progressLabel: progressLabel,
      racerStack: RacePeople(
        avatars: avatars,
        total: race.participantCount,
        size: 28,
        max: 4,
      ),
      rank: rank,
      contextNote: contextNote,
      onOpen: onVerify,
      actionLabel: 'Start verification',
      ctaIcon: Icons.camera_alt_rounded,
    );
  }
}

// ── Ready movement row — pick a movement, go move ────────────────────────────

/// A lean action row for "Also ready": movement glyph, race name, a meta
/// line that carries real state (start line / progress + rank or distance
/// to finish), a thin progress track, arrow. No card — the loud "Up next"
/// hero above carries the race identity; this row answers "what else can
/// I prove, and how close is it?"
class _ReadyMovementRow extends StatelessWidget {
  const _ReadyMovementRow({
    required this.race,
    required this.onTap,
    this.userId,
  });

  final Race race;
  final String? userId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final myPart = userId != null ? race.participantFor(userId!) : null;
    final activity = raceActivityTitle(race);
    final progressLabel = raceProgressLabel(race, myPart);
    final pct = raceProgressPercent(race, myPart);
    final icon =
        raceActivityDefinition(race)?.icon ?? Icons.fitness_center_rounded;

    // Meta line — canonical state only:
    //   start line:  "Pushups · Start line · 8 racers"
    //   in progress: "Squats · 12 / 25 reps · #4"            (multi-racer)
    //                "12 / 25 reps · 13 reps left"          (solo)
    final String meta;
    if (pct <= 0) {
      final count = race.participantCount;
      meta = count > 1
          ? '$activity · Start line · $count racers'
          : '$activity · Start line';
    } else {
      final rank = race.participantCount > 1
          ? rankForUser(race, userId)
          : null;
      final rankLabel = rank != null ? '#$rank' : null;
      final remaining = _goalRemainingLabel(race, userId);
      meta = [activity, progressLabel, ?rankLabel, ?remaining].join(' · ');
    }

    return PressableScale(
      onTap: onTap,
      scale: 0.98,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                // Actionable = blue. These rows invite a move right now,
                // so the glyph well carries Nuvo's action color at a quiet
                // tint — same semantic as the Ready segment pill.
                color: NuvoColors.blue.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: NuvoColors.blue, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    race.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.raceRowTitle.copyWith(fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.raceRowMeta.copyWith(
                      fontSize: 12,
                      color: NuvoColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 7),
                  // The race's lane in miniature — same track language as
                  // the hero and Compete rows, so "how far along" reads at
                  // a glance without leaving the queue.
                  RaceProgress(
                    progressPercent: pct,
                    trackHeight: 3,
                    dotDiameter: 7,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.arrow_forward_rounded,
              color: NuvoColors.textDim,
              size: 17,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Completed segment ─────────────────────────────────────────────────────────

class _CompletedSegment extends StatelessWidget {
  const _CompletedSegment({
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
    if (races.isEmpty) {
      return const _SegmentEmptyState(
        icon: Icons.check_circle_outline_rounded,
        title: 'No completed races yet.',
        subtitle: 'Races you finish will show up here.',
      );
    }

    final visible = expanded ? races : races.take(cap).toList();
    final hasMore = races.length > cap;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasMore)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: NuvoPressable(
                onTap: onToggleExpand,
                haptic: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Text(
                    expanded ? 'Show less' : 'See all ${races.length}',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: NuvoColors.navy,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: NuvoColors.surface,
            borderRadius: BorderRadius.circular(NuvoRadii.card),
            border: NuvoBorders.quiet,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < visible.length; i++) ...[
                _CompletedRaceRow(
                  race: visible[i],
                  userId: userId,
                  onTap: () => onOpen(visible[i]),
                ),
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
}

class _CompletedRaceRow extends StatelessWidget {
  const _CompletedRaceRow({
    required this.race,
    required this.onTap,
    this.userId,
  });

  final Race race;
  final String? userId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rank = rankForUser(race, userId);
    final activity = raceActivityTitle(race);

    // Consequence, not queue: what the race became — a win, a finish, or
    // a hit goal — plus when it happened. All canonical fields
    // (`winnerUserId`, `raceIsCompleted`, `completedAt`).
    final won = race.winnerUserId != null && race.winnerUserId == userId;
    final outcome = won
        ? 'Won'
        : raceIsCompleted(race)
            ? 'Finished'
            : 'Goal reached';
    final completed = DateTime.tryParse(race.completedAt ?? '')?.toUtc();
    final ago =
        completed != null ? notificationRelativeTime(completed) : null;

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

    return RaceResultRow(
      raceTitle: race.displayTitle,
      movementLabel: ago != null ? '$activity · $outcome $ago' : '$activity · $outcome',
      rank: rank,
      participantCount: race.participantCount,
      avatars: avatars,
      onTap: onTap,
    );
  }
}

// ── Recent segment ────────────────────────────────────────────────────────────

class _RecentSegment extends StatelessWidget {
  const _RecentSegment({
    required this.entries,
    required this.expanded,
    required this.cap,
    required this.onToggleExpand,
    required this.onOpen,
    this.userId,
  });

  final List<({Race race, RaceProof proof})> entries;
  final bool expanded;
  final int cap;
  final VoidCallback onToggleExpand;
  final ValueChanged<Race> onOpen;
  final String? userId;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const _SegmentEmptyState(
        icon: Icons.history_rounded,
        title: 'No recent moves.',
        subtitle: 'Proofs you submit will appear here.',
      );
    }

    final visible = expanded ? entries : entries.take(cap).toList();
    final hasMore = entries.length > cap;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasMore)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: NuvoPressable(
                onTap: onToggleExpand,
                haptic: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Text(
                    expanded ? 'Show less' : 'See all ${entries.length}',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: NuvoColors.navy,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: NuvoColors.surface,
            borderRadius: BorderRadius.circular(NuvoRadii.card),
            border: NuvoBorders.quiet,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < visible.length; i++) ...[
                _RecentProofRow(
                  proof: visible[i].proof,
                  race: visible[i].race,
                  userId: userId,
                  onTap: () => onOpen(visible[i].race),
                ),
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
}

class _RecentProofRow extends StatelessWidget {
  const _RecentProofRow({
    required this.proof,
    required this.race,
    required this.onTap,
    this.userId,
  });

  final RaceProof proof;
  final Race race;
  final VoidCallback onTap;
  final String? userId;

  @override
  Widget build(BuildContext context) {
    final isChecked =
        proof.verificationStatus == 'ai_verified' ||
        proof.verificationStatus == 'accepted';
    final isRejected =
        proof.verificationStatus == 'ai_failed' ||
        proof.verificationStatus == 'rejected';

    final statusLabel = switch (proof.verificationStatus) {
      'ai_verified' => 'Verified',
      'accepted' => 'Verified',
      'ai_failed' => 'Not counted',
      'rejected' => 'Not counted',
      'needs_review' => 'Under review',
      _ => 'Logged',
    };

    final isPending =
        proof.verificationStatus == 'needs_review' ||
        proof.verificationStatus == 'ai_pending' ||
        proof.verificationStatus == 'pending';
    final statusColor = isChecked
        ? NuvoColors.success
        : isRejected
        ? NuvoColors.danger
        : isPending
        ? NuvoColors.warning
        : NuvoColors.muted;

    // "What changed because I proved it": accepted amount, the rank move it
    // caused when the server recorded one, and when — all canonical fields
    // on the move log (value, rankBefore→rankAfter, createdAt).
    final rankDelta =
        proof.rankBefore != null &&
            proof.rankAfter != null &&
            proof.rankBefore != proof.rankAfter
        ? '#${proof.rankBefore} → #${proof.rankAfter}'
        : null;
    final occurred = DateTime.tryParse(proof.createdAt)?.toUtc();
    final ago = occurred != null ? notificationRelativeTime(occurred) : null;

    final valueStr = [
      if (proof.value != null) '+${proof.value} ${race.unit ?? 'reps'}',
      ?ago,
    ].join(' · ');
    final meta = valueStr.isEmpty ? null : valueStr;

    final initial = proof.displayName.isNotEmpty
        ? proof.displayName[0].toUpperCase()
        : '?';
    // The avatar already says who — the meta line only needs "You" for the
    // viewer's own proofs, which is most of a personal history.
    final actorName =
        proof.userId == userId ? 'You' : proof.displayName;

    final activity = raceActivityTitle(race);

    return RaceActivityRow(
      raceTitle: race.displayTitle,
      movementLabel: activity,
      actorName: actorName,
      actorInitial: initial,
      actorPhotoUrl: proof.profilePhotoUrl,
      actorId: proof.userId,
      valueStr: meta,
      statusLabel: statusLabel,
      statusColor: statusColor,
      statusNote: rankDelta,
      onTap: onTap,
    );
  }
}

// ── Segment empty state ───────────────────────────────────────────────────────

class _SegmentEmptyState extends StatelessWidget {
  const _SegmentEmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
    this.accent = NuvoColors.blue,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return NuvoEmptyState(
      icon: icon,
      title: title,
      body: subtitle,
      ctaLabel: actionLabel,
      onCta: onAction,
      accent: accent,
      compact: true,
    );
  }
}

// ── Empty state (all segments empty) ──────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return NuvoEmptyState(
      icon: Icons.directions_run_rounded,
      title: 'Nothing to verify yet',
      body:
          'Create a race, then log your moves here. Nuvo checks each one and '
          'moves the leaderboard.',
      ctaLabel: 'Create a race',
      onCta: onStart,
    );
  }
}

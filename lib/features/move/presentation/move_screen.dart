import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_geometry.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/bottom_nav.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_empty_state.dart';
import '../../../core/widgets/nuvo_error_state.dart';
import '../../../core/widgets/nuvo_loading_indicator.dart';
import '../../../core/widgets/nuvo_number_flow.dart';
import '../../../core/widgets/nuvo_race_components.dart';
import '../../../core/widgets/nuvo_motion.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../notifications/domain/notification_display.dart';
import '../../races/data/race_models.dart';
import '../../races/domain/camera_verification_resolver.dart';
import '../../races/domain/motion_activity.dart';
import '../../races/domain/race_display.dart';
import '../../races/presentation/race_controller.dart';

/// Verify — the action surface.
///
/// Arena is what's happening, Compete is the race shelf, Crew is people,
/// Profile is identity. Verify is where you GO DO SOMETHING: the most
/// action-oriented destination in the nav.
///
/// Screen question: "What can I do right now to move my races forward?"
///
/// A race is NOT assumed to be movement + reps + camera: FlexiRace goals can
/// be reps, books, grades, golf scores, durations — anything. Each race's
/// canonical proof capability ([_ProofAction] — resolved from verifier/
/// proof fields, never the title) and its canonical score semantics
/// (target / no-denominator, higher/lower-wins, timed) drive both the CTA
/// and the hero layout.
///
/// Structure:
/// 1. Header — "Verify" + "Make your move." + ready count + history
/// 2. Light Ready / Completed / Recent tabs (sliding underline)
/// 3. Compositional "Up next" hero — the result is the anchor, the proof
///    method and action sit in a blue band, no bordered dashboard card
/// 4. "Ready next" tactile rows with competitor context, hairline rhythm
/// 5. Completed = history index, Recent = proof timeline — bare rows
///
/// State change creates motion: NuvoNumberFlow on the hero result, a
/// lead-take flash, NuvoStateMorph when the hero advances to the next
/// race. Idle stays calm.
class MoveScreen extends ConsumerStatefulWidget {
  const MoveScreen({super.key});

  @override
  ConsumerState<MoveScreen> createState() => _MoveScreenState();
}

enum _VerifySegment { ready, completed, recent }

/// What "verify" means for a race — resolved from the race's canonical
/// verifier/proof fields (the same truth the proof screen branches on),
/// never inferred from the title.
enum _ProofAction { motion, manual, generic }

_ProofAction _proofActionFor(Race race) {
  if (resolveCameraVerification(race).isCameraVerifiable) {
    return _ProofAction.motion;
  }
  if (race.verifierType == manualLogVerifierType ||
      race.proofMode == 'manual') {
    return _ProofAction.manual;
  }
  return _ProofAction.generic;
}

/// The CTA the race's proof capability actually performs.
({String label, IconData icon}) _proofCta(Race race) => switch (
    _proofActionFor(race)) {
  _ProofAction.motion => (
    label: 'Start AI Motion Proof',
    icon: Icons.camera_alt_rounded,
  ),
  _ProofAction.manual => (
    label: _isAccumulating(race) ? 'Log progress' : 'Add result',
    icon: Icons.edit_note_rounded,
  ),
  _ProofAction.generic => (
    label: 'Submit proof',
    icon: Icons.upload_rounded,
  ),
};

/// Whether each new submission ADDS to a running total (reps, books read)
/// vs. standing alone as a best attempt (golf score, test grade, plank
/// time). Drives "+N" vs bare score presentation and the manual CTA.
bool _isAccumulating(Race race) =>
    race.scoringRule == 'cumulative_sum' ||
    race.format == 'first_to_goal' ||
    race.format == 'most_in_window';

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

    // Camera and non-camera goals surface identically — what differs is the
    // proof action each row offers, resolved per race by _proofActionFor.
    final myRaces = raceState.races;

    // Ready order = distance to the finish line — the race that needs the
    // least proof leads ("what can I prove next" = "what finishes soonest").
    // Decorated index sort keeps the server's order on ties (Dart's sort
    // isn't stable).
    final readyUnsorted = myRaces.where((race) {
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

    // Completed = the server says the race ended OR I hit my goal. A
    // lowest-wins / best-attempt race can close without a 100% bar.
    final completedRaces = myRaces.where((race) {
      final myPart = uid != null ? race.participantFor(uid) : null;
      return raceIsCompleted(race) || (myPart?.progressPercent ?? 0) >= 100;
    }).toList();

    final recentMoves = myRaces
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
      backgroundColor: context.themeColors.page,
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
            // ── Action header ─────────────────────────────────────────
            _VerifyHeader(
              readyCount: readyRaces.length,
              onHistory: () => _setSegment(_VerifySegment.recent),
            ),
            const SizedBox(height: NuvoSpacing.lg),

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
              _VerifyTabs(
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
                        onStartRace: () => context.go('/compete'),
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

// ── Action header ─────────────────────────────────────────────────────────────

/// "Verify / Make your move. / N races ready" + a history affordance that
/// jumps to the Recent segment (a real destination — the proof timeline).
class _VerifyHeader extends StatelessWidget {
  const _VerifyHeader({required this.readyCount, required this.onHistory});

  final int readyCount;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Make your move.',
                  style: AppTextStyles.screenTitle),
            ),
            NuvoPressable(
              onTap: onHistory,
              haptic: false,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.history_rounded,
                  size: 21,
                  color: c.inkMuted,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: NuvoSpacing.xs),
        Text(
          readyCount > 0
              ? '$readyCount ${readyCount == 1 ? 'race' : 'races'} ready'
              : 'Nothing waiting on you',
          style: AppTextStyles.bodySmall.copyWith(
            color: c.inkMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ── Tabs ─────────────────────────────────────────────────────────────────────

/// Light tab strip — selected label + a blue underline that SLIDES between
/// slots. No pill tray, no container: the tabs read as a filter, and the
/// compact footprint keeps the hero above the fold.
class _VerifyTabs extends StatelessWidget {
  const _VerifyTabs({
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
    final c = context.themeColors;
    final selectedIndex = _VerifySegment.values.indexOf(segment);

    return SizedBox(
      height: 42,
      child: Stack(
        children: [
          // The selection indicator is one sliding element, not a per-tab
          // color swap — the state moves.
          Positioned.fill(
            child: AnimatedAlign(
              // -1 / 0 / +1 across the three equal slots.
              alignment: Alignment(selectedIndex - 1.0, 1),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: FractionallySizedBox(
                widthFactor: 1 / 3,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    height: 3,
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    decoration: BoxDecoration(
                      color: NuvoColors.blue,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Row(
            children: [
              _VerifyTab(
                label: 'Ready',
                count: readyCount,
                selected: segment == _VerifySegment.ready,
                onTap: () => onChanged(_VerifySegment.ready),
              ),
              _VerifyTab(
                label: 'Completed',
                count: completedCount,
                selected: segment == _VerifySegment.completed,
                onTap: () => onChanged(_VerifySegment.completed),
              ),
              _VerifyTab(
                label: 'Recent',
                count: recentCount,
                selected: segment == _VerifySegment.recent,
                onTap: () => onChanged(_VerifySegment.recent),
              ),
            ],
          ),
          // Grounding hairline under the whole strip.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(height: 1, color: c.divider),
          ),
        ],
      ),
    );
  }
}

class _VerifyTab extends StatelessWidget {
  const _VerifyTab({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final fg = selected ? c.ink : c.inkSubtle;
    return Expanded(
      child: NuvoPressable(
        onTap: onTap,
        haptic: false,
        child: Container(
          height: double.infinity,
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelMedium.copyWith(
                    fontSize: 13.5,
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
                  color: selected ? NuvoColors.blue : c.inkDim,
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
        icon: Icons.emoji_events_outlined,
        title: 'Nothing to prove yet.',
        subtitle:
            'Join a race or start one, then your next move shows up here.',
        actionLabel: 'Find a race',
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
        // ── Up next — the action surface. When a race finishes and the
        // next one steps up, the hero morphs to the new race (state change
        // → motion), rather than silently swapping content.
        NuvoStateMorph(
          stateKey: upNext.id,
          child: _UpNextHero(
            race: upNext,
            userId: userId,
            onVerify: () => onVerify(upNext),
          ),
        ),
        if (alsoReady.isNotEmpty) ...[
          const SizedBox(height: NuvoSpacing.xxl),
          Row(
            children: [
              Text(
                'Ready next',
                style: AppTextStyles.labelMedium.copyWith(
                  fontSize: 14.5,
                  color: context.themeColors.ink,
                  fontWeight: FontWeight.w800,
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
                      expanded ? 'Show less' : 'See all ${alsoReady.length}',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: context.themeColors.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          // Level-0 tactile rows directly on the page — hairline rhythm, no
          // card-per-row. The hero above is the one loud surface.
          for (var i = 0; i < visibleAlsoReady.length; i++) ...[
            _ReadyRow(
              race: visibleAlsoReady[i],
              userId: userId,
              onTap: () => onVerify(visibleAlsoReady[i]),
            ),
            if (i < visibleAlsoReady.length - 1)
              Divider(
                height: 1,
                thickness: 1,
                color: context.themeColors.divider,
              ),
          ],
        ],
      ],
    );
  }
}

// ── Up next hero — the compositional action surface ──────────────────────────

/// Not a bordered dashboard card: a composition of kicker → title → goal →
/// giant result → competitor context → blue action band. The RESULT is the
/// visual anchor — "72" with a real track to 100 when a denominator exists,
/// or the bare "94%" / "78" / "1:42" when the race is a best-attempt or
/// lower-wins race with no finish line (no fake track, no fake denominator).
///
/// Scoring semantics change the personality:
///   first_to_goal / cumulative+target → "72" + "/100" + thin track
///   best_attempt higher-wins          → "94%" YOUR BEST
///   best_attempt lower-wins           → "78" STROKES CURRENT BEST
///   timed_attempt                     → "1:42" BEST
///
/// State change creates motion: NuvoNumberFlow rolls the result, taking
/// the lead fires a short "YOU TOOK THE LEAD" flash + haptic, and a new
/// hero race morphs in via NuvoStateMorph.
class _UpNextHero extends StatefulWidget {
  const _UpNextHero({
    required this.race,
    required this.onVerify,
    this.userId,
  });

  final Race race;
  final String? userId;
  final VoidCallback onVerify;

  @override
  State<_UpNextHero> createState() => _UpNextHeroState();
}

class _UpNextHeroState extends State<_UpNextHero> {
  bool _leadFlash = false;

  int? _rank() => rankForUser(widget.race, widget.userId);

  @override
  void didUpdateWidget(_UpNextHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Same race, rank moved to 1st while visible → the proof just changed
    // the competition. A single flash + haptic marks the takeover; nothing
    // loops or confetti-spams.
    if (widget.race.id == oldWidget.race.id) {
      final was = rankForUser(oldWidget.race, oldWidget.userId);
      final now = _rank();
      if (now == 1 && was != null && was > 1 && !_leadFlash) {
        setState(() => _leadFlash = true);
        HapticFeedback.mediumImpact();
        Future.delayed(const Duration(milliseconds: 2600), () {
          if (mounted) setState(() => _leadFlash = false);
        });
      }
    }
  }

  /// The huge number's formatter — timed races read as clocks ("1:42"),
  /// percent-unit races carry their glyph ("94%"), everything else is a
  /// bare figure whose unit label sits beside it.
  String Function(int) get _anchorFormat {
    if (raceMetric(widget.race) == RaceMetric.seconds) {
      return formatClock;
    }
    if (raceDisplayUnit(widget.race) == 'percent') {
      return (v) => '$v%';
    }
    return (v) => '$v';
  }

  /// The adjacent competitor — the person directly above the viewer when
  /// chasing, the runner-up when leading. Null for solo races: no invented
  /// rivalry.
  RaceParticipant? _rival(List<RaceParticipant> others, int? rank) {
    if (others.isEmpty) return null;
    if (rank != null && rank > 1) {
      for (final p in others) {
        if (p.rank == rank - 1) return p;
      }
    }
    return others.first;
  }

  /// One human competitive line — "1 rep to pass Noah", "You lead Maya by
  /// 3", "Set the pace". Canonical values only; passing is claimed only as
  /// far as the adjacent rank actually moves.
  String _contextLine(
    int? rank,
    int myValue,
    RaceParticipant? rival,
    RaceParticipant? leader,
  ) {
    final race = widget.race;
    if (race.participantCount <= 1 || rival == null) return 'Set the pace';
    if (rank == null || myValue <= 0) {
      return leader != null && leader.progressValue > 0
          ? 'Make your first move — ${_firstName(leader.displayName)} has '
              '${_scoreText(race, leader.progressValue)}'
          : 'Make your first move';
    }
    if (rank == 1) {
      final runnerUp = rival;
      if (runnerUp.progressValue <= 0) return "You're in the lead";
      final gap = (myValue - runnerUp.progressValue).abs();
      return gap == 0 || widget.race.viewerContext?.isTied == true
          ? 'Tied with ${_firstName(runnerUp.displayName)} — next proof wins it'
          : 'You lead ${_firstName(runnerUp.displayName)} by ${_scoreText(race, gap)}';
    }
    final gap = rival.progressValue - myValue;
    if (gap <= 0) {
      return 'Catch ${_firstName(rival.displayName)}';
    }
    return rank == 2
        ? '${_scoreText(race, gap)} to take 1st'
        : '${_scoreText(race, gap)} to pass ${_firstName(rival.displayName)}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final race = widget.race;
    final myPart = widget.userId != null
        ? race.participantFor(widget.userId!)
        : null;
    final hasDenominator = (race.targetValue ?? 0) > 0;
    final myValue = myPart?.progressValue ?? 0;
    final hasResult = myValue > 0;
    final rank = _rank();
    // A rank only means something once there's a result — a solo race or an
    // unscored entry must not claim "1st".
    final earnedRank = hasResult ? rank : null;
    final lower = race.scoreDirection == 'lower';
    final mood = _moodFor(race, widget.userId);
    final accent = _activityAccent(race);

    // Competitors in standing order — canonical rank when the server sends
    // it, else score ordering by race direction.
    final others = race.participants
        .where((p) => p.userId != widget.userId)
        .toList()
      ..sort((a, b) {
        final ar = a.rank;
        final br = b.rank;
        if (ar != null && br != null) return ar.compareTo(br);
        if (ar != null) return -1;
        if (br != null) return 1;
        return lower
            ? a.progressValue.compareTo(b.progressValue)
            : b.progressValue.compareTo(a.progressValue);
      });
    final rival = _rival(others, rank);
    final leader = others.isNotEmpty ? others.first : null;

    return Stack(
      children: [
        Column(
          key: const Key('verify-up-next-hero'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Race name + earned rank — no kicker, the hero is the headline.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    race.displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.screenTitle.copyWith(
                      fontSize: 23,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
                if (earnedRank != null) ...[
                  const SizedBox(width: 10),
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      _ordinalLabel(earnedRank).toLowerCase(),
                      style: AppTextStyles.placementLabel(
                        size: 14,
                        // A shared first isn't the payoff yet — gold waits
                        // for the outright lead/win.
                        color: mood == _VerifyMood.tied
                            ? c.ink
                            : (_placementTint(earnedRank) ?? c.inkSubtle),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Text(
              _goalSentence(race),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodySmall.copyWith(
                color: c.inkMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            // The result is the anchor — its color carries the state.
            _HeroAnchor(
              race: race,
              value: myValue,
              hasDenominator: hasDenominator,
              hasResult: hasResult,
              format: _anchorFormat,
              accent: accent,
              moodColor: _moodText(mood, c),
            ),
            if (hasDenominator) ...[
              const SizedBox(height: 14),
              // The track IS the rivalry: viewer mark, rival mark, goal
              // ring — named, canonical, animated. No card underneath.
              RaceMarkerTrack(
                fillColor: _moodMarker(mood),
                goalLabel: 'Goal ${_anchorFormat(race.targetValue!)}',
                markers: [
                  if (rival != null && rival.progressValue > 0)
                    RaceTrackMarker(
                      fraction: rival.progressValue / race.targetValue!,
                      label:
                          '${_firstName(rival.displayName)} '
                          '${_anchorFormat(rival.progressValue)}',
                      color: c.ink,
                    ),
                  RaceTrackMarker(
                    fraction: myValue / race.targetValue!,
                    label: 'You ${_anchorFormat(myValue)}',
                    color: _moodMarker(mood),
                    isViewer: true,
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 14),
            ],
            // The stakes live on the page, not in a tinted card — one line
            // under the lane, colored by standing.
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              style: AppTextStyles.labelMedium.copyWith(
                fontSize: 13.5,
                color: mood == _VerifyMood.startLine
                    ? c.ink
                    : _moodText(mood, c),
                fontWeight: FontWeight.w700,
              ),
              child: Text(
                _contextLine(rank, myValue, rival, leader),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 16),
            // One primary action — the proof method IS the label.
            NuvoPrimaryButton(
              key: const Key('verify-hero-cta'),
              label: _proofCta(race).label,
              onPressed: widget.onVerify,
              icon: _proofCta(race).icon,
              expand: true,
              height: 48,
            ),
          ],
        ),
        // Lead-takeover flash — state change creates motion; idle stays calm.
        Positioned(
          top: 14,
          left: 18,
          right: 18,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: _leadFlash ? 1 : 0,
              duration: const Duration(milliseconds: 260),
              child: AnimatedSlide(
                offset: _leadFlash ? Offset.zero : const Offset(0, -0.4),
                duration: const Duration(milliseconds: 300),
                curve: NuvoMotion.spring,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      // The competitive payoff — gold lives here and
                      // nowhere else.
                      color: NuvoColors.gold,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                          color: c.inkShadow,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      'YOU TOOK THE LEAD',
                      style: AppTextStyles.labelUppercase(11).copyWith(
                        color: NuvoColors.navy,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The anchor region: giant result + (only when real) thin track, or the
/// bare best-result with its unit/label. NuvoNumberFlow rolls the figure
/// whenever canonical progress lands while the hero is visible.
class _HeroAnchor extends StatelessWidget {
  const _HeroAnchor({
    required this.race,
    required this.value,
    required this.hasDenominator,
    required this.hasResult,
    required this.format,
    required this.accent,
    required this.moodColor,
  });

  final Race race;
  final int value;
  final bool hasDenominator;
  final bool hasResult;
  final String Function(int) format;

  /// The activity's accent family — tints the unit/result labels.
  final Color accent;

  /// The mood's text color — the giant number goes green/amber when the
  /// state earns it, ink while chasing or at the start line.
  final Color moodColor;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final numberColor =
        hasResult && moodColor != c.inkSubtle ? moodColor : c.ink;
    final style = AppTextStyles.statLarge(42, color: numberColor);

    if (hasDenominator) {
      // First-to-goal / cumulative-with-target: "72" + "/ 100" + real track.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              NuvoNumberFlow(value: value, format: format, style: style),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '/ ${_heroTargetLabel(race)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelMedium.copyWith(
                    fontSize: 16,
                    color: c.inkSubtle,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }

    // No denominator — the result itself is the hero. No track.
    final unit = raceDisplayUnit(race);
    final showUnit =
        hasResult && unit.isNotEmpty && unit != 'percent' &&
        raceMetric(race) != RaceMetric.seconds;
    final resultLabel = hasResult
        ? (race.scoreDirection == 'lower' ? 'CURRENT BEST' : 'YOUR BEST')
        : 'NO SCORE YET';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        NuvoNumberFlow(value: value, format: format, style: style),
        const SizedBox(width: 10),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showUnit)
                Text(
                  unit.toUpperCase(),
                  style: AppTextStyles.labelUppercase(10.5).copyWith(
                    color: c.inkMuted,
                  ),
                ),
              Text(
                resultLabel,
                style: AppTextStyles.labelUppercase(10.5).copyWith(
                  color: hasResult ? accent : c.inkDim,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── State + activity color ───────────────────────────────────────────────────

/// The hero's competitive mood — derived from canonical standing only.
enum _VerifyMood { startLine, chasing, tied, leading }

_VerifyMood _moodFor(Race race, String? userId) {
  final myPart = userId != null ? race.participantFor(userId) : null;
  final myValue = myPart?.progressValue ?? 0;
  if (myValue <= 0) return _VerifyMood.startLine;
  final rank = rankForUser(race, userId);
  if (rank == null) return _VerifyMood.chasing;
  if (race.viewerContext?.isTied == true) return _VerifyMood.tied;
  if (rank == 1) return _VerifyMood.leading;
  return _VerifyMood.chasing;
}

/// Marker/track color — the state is carried by the track and dots.
/// Palette is state-based only: blue = racing/chasing (a tie is still a
/// chase), green = leading. Gold is reserved for the win payoff.
Color _moodMarker(_VerifyMood m) => switch (m) {
  _VerifyMood.startLine => NuvoColors.blue,
  _VerifyMood.chasing => NuvoColors.blue,
  _VerifyMood.tied => NuvoColors.blue,
  _VerifyMood.leading => NuvoColors.success,
};

/// Text color for mood statements — the *_On variants keep contrast on
/// light surfaces; on dark they stay readable since they sit on ink text.
Color _moodText(_VerifyMood m, NuvoThemeColors c) => switch (m) {
  _VerifyMood.startLine => c.inkSubtle,
  _VerifyMood.chasing => NuvoColors.blue,
  _VerifyMood.tied => NuvoColors.blue,
  _VerifyMood.leading => NuvoColors.successOn,
};

/// The activity's accent family — canonical fields only, no invented art.
/// Timed/endurance reads teal, academic violet, books indigo,
/// lower-is-better sage, everything else stays Nuvo blue.
Color _activityAccent(Race race) {
  if (raceMetric(race) == RaceMetric.seconds) return NuvoColors.avatarTeal;
  final unit = raceDisplayUnit(race);
  if (unit == 'percent') return NuvoColors.avatarPlum;
  if (unit == 'books' || unit == 'pages') return NuvoColors.avatarIndigo;
  if (race.scoreDirection == 'lower') return NuvoColors.avatarSage;
  return NuvoColors.blue;
}

String _firstName(String displayName) {
  final parts = displayName.trim().split(RegExp(r'\s+'));
  return parts.isEmpty ? 'Racer' : parts.first;
}

String _ordinalLabel(int n) {
  if (n > 99) return '99+';
  if (n >= 11 && n <= 13) return '${n}TH';
  return switch (n % 10) {
    1 => '${n}ST',
    2 => '${n}ND',
    3 => '${n}RD',
    _ => '${n}TH',
  };
}

Color? _placementTint(int? rank) => switch (rank) {
  1 => NuvoColors.position1,
  2 => NuvoColors.position2,
  3 => NuvoColors.position3,
  _ => null,
};

/// Compact target text for the hero — timed races read "2:00", not
/// "2 minutes"; everything else uses the canonical target label.
String _heroTargetLabel(Race race) {
  final target = race.targetValue ?? 0;
  return raceMetric(race) == RaceMetric.seconds
      ? formatClock(target)
      : raceTargetLabel(race);
}

/// One-line scoring explanation — how this race is won, canonical.
String _goalSentence(Race race) {
  final target = race.targetValue;
  final hasTarget = target != null && target > 0;
  if (race.format == 'first_to_goal' || race.format == 'most_in_window') {
    return hasTarget
        ? 'First to ${_heroTargetLabel(race)}'
        : 'Most ${raceDisplayUnit(race)} wins';
  }
  if (race.format == 'timed_attempt') {
    return hasTarget ? 'Beat ${_heroTargetLabel(race)}' : 'Best time wins';
  }
  return race.scoreDirection == 'lower'
      ? 'Lowest score wins'
      : 'Highest score wins';
}

/// Compact score text — percent races carry their glyph ("94%"); every
/// other unit uses the canonical label ("78 strokes", "1:42"). A value of
/// 1 strips the plural so the screen never reads "1 reps".
String _scoreText(Race race, int value) {
  if (raceDisplayUnit(race) == 'percent') return '$value%';
  final label = raceScoreLabel(race, value);
  if (value == 1 && label.endsWith('s')) {
    return label.substring(0, label.length - 1);
  }
  return label;
}

// ── Ready row — dense competitive row, no card ───────────────────────────────

/// A "Ready next" row: title + earned rank, canonical result/progress, a
/// thin track when a denominator exists, and one context line — what's
/// left, who to pass, or the start line. The whole row is the tap target;
/// no repeated blue verb, the chevron carries the affordance.
class _ReadyRow extends StatelessWidget {
  const _ReadyRow({
    required this.race,
    required this.onTap,
    this.userId,
  });

  final Race race;
  final String? userId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final myPart = userId != null ? race.participantFor(userId!) : null;
    final hasDenominator = (race.targetValue ?? 0) > 0;
    final myValue = myPart?.progressValue ?? 0;
    final hasResult = myValue > 0;
    final lower = race.scoreDirection == 'lower';
    final earnedRank = hasResult ? rankForUser(race, userId) : null;
    final mood = _moodFor(race, userId);

    // Canonical meta: "39 / 50 reps" · "Best · 78 strokes" · "Start line".
    final String meta = !hasResult
        ? race.participantCount > 1
            ? 'Start line · ${race.participantCount} racers'
            : 'Start line'
        : hasDenominator
            ? raceProgressLabel(race, myPart)
            : 'Best · ${_scoreText(race, myValue)}';

    // One context line — what's left or who to pass. No invented rivalry.
    String? contextLine;
    if (hasResult && hasDenominator) {
      final remaining = race.targetValue! - myValue;
      if (remaining > 0) {
        contextLine = '${_scoreText(race, remaining)} left';
      }
    } else if (hasResult && race.participantCount > 1) {
      final others = race.participants
          .where((p) => p.userId != userId)
          .toList()
        ..sort((a, b) {
          final ar = a.rank;
          final br = b.rank;
          if (ar != null && br != null) return ar.compareTo(br);
          if (ar != null) return -1;
          if (br != null) return 1;
          return lower
              ? a.progressValue.compareTo(b.progressValue)
              : b.progressValue.compareTo(a.progressValue);
        });
      final rank = rankForUser(race, userId);
      RaceParticipant? rival;
      if (others.isNotEmpty) {
        rival = others.first;
        if (rank != null && rank > 1) {
          rival = others.firstWhere((p) => p.rank == rank - 1,
              orElse: () => others.first);
        }
      }
      if (rival != null && rival.progressValue > 0) {
        final gap = (rival.progressValue - myValue).abs();
        if (gap > 0) {
          contextLine = rank == 1
              ? 'You lead ${_firstName(rival.displayName)} '
                  'by ${_scoreText(race, gap)}'
              : '${_scoreText(race, gap)} to pass '
                  '${_firstName(rival.displayName)}';
        }
      }
    }

    return PressableScale(
      onTap: onTap,
      scale: 0.98,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    race.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.raceRowTitle.copyWith(fontSize: 15),
                  ),
                ),
                if (earnedRank != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    _ordinalLabel(earnedRank).toLowerCase(),
                    style: AppTextStyles.placementLabel(
                      size: 12.5,
                      color: _placementTint(earnedRank) ?? c.inkSubtle,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 3),
            Text(
              meta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.raceRowMeta.copyWith(
                fontSize: 12.5,
                color: c.inkSubtle,
              ),
            ),
            if (hasDenominator && hasResult) ...[
              const SizedBox(height: 7),
              RaceProgress(
                progressPercent: raceProgressPercent(race, myPart),
                trackHeight: 3,
                dotDiameter: 6,
                fillColor: _moodMarker(mood),
              ),
            ],
            const SizedBox(height: 5),
            Row(
              children: [
                Expanded(
                  child: Text(
                    contextLine ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.labelSmall.copyWith(
                      fontSize: 12,
                      color: contextLine != null &&
                              mood != _VerifyMood.startLine
                          ? _moodText(mood, c)
                          : c.inkSubtle,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_rounded,
                  color: c.inkDim,
                  size: 16,
                ),
              ],
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
                      color: context.themeColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        // Bare history rows — a completed index, not a stack of cards.
        Column(
          children: [
            for (var i = 0; i < visible.length; i++) ...[
              _CompletedRaceRow(
                race: visible[i],
                userId: userId,
                onTap: () => onOpen(visible[i]),
              ),
              if (i < visible.length - 1)
                Divider(
                  height: 1,
                  thickness: 1,
                  indent: 50,
                  color: context.themeColors.divider,
                ),
            ],
          ],
        ),
      ],
    );
  }
}

/// A completed race reads as a record: name, "1st · 100 reps", when it
/// landed. Bare row + hairline — tapping goes to Race Detail.
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
    final c = context.themeColors;
    final rank = rankForUser(race, userId);
    final myPart =
        userId != null ? race.participantFor(userId!) : null;
    final score = (myPart?.progressValue ?? 0) > 0
        ? _scoreText(race, myPart!.progressValue)
        : null;

    // Consequence, not queue: a win, a finish, or a hit goal — plus when
    // it happened. All canonical fields (`winnerUserId`, `raceIsCompleted`,
    // `completedAt`).
    final won = race.winnerUserId != null && race.winnerUserId == userId;
    final outcome = won
        ? 'Won'
        : raceIsCompleted(race)
            ? 'Finished'
            : 'Goal reached';
    final completed = DateTime.tryParse(race.completedAt ?? '')?.toUtc();
    final ago =
        completed != null ? notificationRelativeTime(completed) : null;
    final when = ago != null ? '$outcome $ago' : outcome;

    return PressableScale(
      onTap: onTap,
      scale: 0.98,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                // Completed = green; the gold payoff belongs to wins alone.
                color: won
                    ? NuvoColors.gold.withValues(alpha: 0.14)
                    : NuvoColors.success.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                won
                    ? Icons.emoji_events_rounded
                    : Icons.flag_outlined,
                color: won ? NuvoColors.gold : NuvoColors.successOn,
                size: 18,
              ),
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
                    [
                      if (rank != null) _ordinalLabel(rank).toLowerCase(),
                      ?score,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.raceRowMeta.copyWith(
                      fontSize: 12.5,
                      color: rank != null
                          ? (_placementTint(rank) ?? c.inkSubtle)
                          : c.inkSubtle,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    when,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.raceRowMeta.copyWith(
                      fontSize: 12,
                      color: won ? NuvoColors.gold : NuvoColors.successOn,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.arrow_forward_rounded,
              color: c.inkDim,
              size: 17,
            ),
          ],
        ),
      ),
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
        title: 'No recent proof.',
        subtitle: 'Results you submit will appear here.',
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
                      color: context.themeColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        // The proof timeline — bare rows with day eyebrows, no cards.
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < visible.length; i++) ...[
              if (_dayBucket(visible[i].proof) !=
                  (i > 0 ? _dayBucket(visible[i - 1].proof) : null)) ...[
                if (i > 0) const SizedBox(height: NuvoSpacing.md),
                Text(
                  _dayBucket(visible[i].proof),
                  style: AppTextStyles.labelUppercase(11).copyWith(
                    color: context.themeColors.inkDim,
                  ),
                ),
                const SizedBox(height: 4),
              ],
              _RecentProofRow(
                proof: visible[i].proof,
                race: visible[i].race,
                userId: userId,
                onTap: () => onOpen(visible[i].race),
              ),
              if (i < visible.length - 1 &&
                  _dayBucket(visible[i + 1].proof) ==
                      _dayBucket(visible[i].proof))
                Divider(
                  height: 1,
                  thickness: 1,
                  indent: 0,
                  color: context.themeColors.divider,
                ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Day grouping for the timeline — "TODAY", "YESTERDAY", weekday within a
/// week, "EARLIER" beyond. Canonical proof timestamps only.
String _dayBucket(RaceProof proof) {
  final occurred = DateTime.tryParse(proof.createdAt)?.toLocal();
  if (occurred == null) return 'EARLIER';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(occurred.year, occurred.month, occurred.day);
  final diff = today.difference(day).inDays;
  if (diff <= 0) return 'TODAY';
  if (diff == 1) return 'YESTERDAY';
  if (diff < 7) {
    const weekdays = [
      'MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY',
      'FRIDAY', 'SATURDAY', 'SUNDAY',
    ];
    return weekdays[day.weekday - 1];
  }
  return 'EARLIER';
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
        : context.themeColors.inkMuted;

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

    // Canonical score label — never a hardcoded "reps". Accumulating races
    // read as gains ("+10 reps", "+2 books"); best-attempt races read as the
    // result itself ("78 strokes", "94%") — a golf round isn't "+78".
    final value = proof.value;
    final valueLabel = value == null
        ? null
        : _isAccumulating(race)
            ? '+${_scoreText(race, value)}'
            : _scoreText(race, value);

    final actorName =
        proof.userId == userId ? 'You' : proof.displayName;

    // "What changed because I proved it" — accepted amount, the rank move
    // it caused when the server recorded one, verification state.
    final metaParts = [
      statusLabel,
      ?rankDelta,
    ];

    return PressableScale(
      onTap: onTap,
      scale: 0.98,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (valueLabel != null)
                  Flexible(
                    child: Text(
                      valueLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.raceRowTitle.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: Text(
                      statusLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.raceRowTitle.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                if (ago != null)
                  Text(
                    ago,
                    style: AppTextStyles.labelSmall.copyWith(
                      fontSize: 11.5,
                      color: context.themeColors.inkDim,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '$actorName · ${race.displayTitle}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.raceRowMeta.copyWith(
                fontSize: 12.5,
                color: context.themeColors.inkSubtle,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    metaParts.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.labelSmall.copyWith(
                      fontSize: 11.5,
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
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
      icon: Icons.emoji_events_outlined,
      title: 'Nothing to prove yet.',
      body:
          'Join a race or start one, then your next move shows up here.',
      ctaLabel: 'Create a race',
      onCta: onStart,
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_geometry.dart';
import '../../../core/theme/app_shadows.dart';
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
import '../../races/presentation/ai_motion_proof_entry.dart';
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

// Proof-action semantics are canonical in race_display.dart
// (raceProofAction / raceProofCta / raceIsAccumulating) — Race Detail and
// Verify resolve the same race to the same CTA.

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
    // Ready = every live race — including ones where I already hit the
    // goal and the crew is still racing. Those read green ("GOAL REACHED")
    // instead of asking for more proof; they sort after actionable races.
    final readyUnsorted = myRaces
        .where((race) => race.status == 'active')
        .toList();
    final readyRaces = [
      for (final e
          in readyUnsorted.indexed.toList()..sort((a, b) {
            var pa = _remainingToGoal(a.$2, uid);
            var pb = _remainingToGoal(b.$2, uid);
            // A race I'm done with never leads the queue — it trails the
            // races that still need proof.
            if (pa <= 0) pa = 1 << 21;
            if (pb <= 0) pb = 1 << 21;
            return pa != pb ? pa.compareTo(pb) : a.$1.compareTo(b.$1);
          }))
        e.$2,
    ];

    // Completed = the race itself ended. A live race where I've hit my
    // goal stays in Ready (it can still flip on a rival's proof).
    final completedRaces = myRaces
        .where((race) => raceIsCompleted(race))
        .toList();

    final recentMoves = myRaces
        .expand((r) => r.recentProofs.map((p) => (race: r, proof: p)))
        .take(20)
        .toList();

    void openVerification(Race race) {
      // Canonical entry: camera-verifiable races go straight to the
      // fullscreen verifier; manual races keep the proof chooser.
      unawaited(
        openAiMotionProof(
          context,
          ref,
          race,
          routeAction: 'move_screen_to_submit_proof',
        ).then((_) {
          ref.read(raceControllerProvider.notifier).loadRaces();
        }),
      );
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
          // Gutters live on the children, not the ListView — the Ready
          // segment's ice queue field runs to the screen edges, and each
          // segment owns its own bottom clearance.
          padding: const EdgeInsets.only(top: 32),
          children: [
            // ── Action header ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: _VerifyHeader(
                readyCount: readyRaces.length,
                onHistory: () => _setSegment(_VerifySegment.recent),
              ),
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
              Padding(
                padding: EdgeInsets.fromLTRB(
                  22,
                  0,
                  22,
                  NuvoBottomNav.bottomPadding(context),
                ),
                child: NuvoErrorState(
                  message: "Couldn't load your races.",
                  onRetry: () =>
                      ref.read(raceControllerProvider.notifier).loadRaces(),
                ),
              )
            else if (allEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  22,
                  0,
                  22,
                  NuvoBottomNav.bottomPadding(context),
                ),
                child: _EmptyState(onStart: () => context.push('/races/new')),
              )
            // ── Segmented control + segment content ───────────────────
            else ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: _VerifyTabs(
                  segment: _segment,
                  readyCount: readyRaces.length,
                  completedCount: completedRaces.length,
                  recentCount: recentMoves.length,
                  onChanged: _setSegment,
                ),
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
                        onOpen: (race) => context.push('/race/${race.id}'),
                        onStartRace: () => context.go('/compete'),
                      ),
                      _VerifySegment.completed => Padding(
                        padding: EdgeInsets.fromLTRB(
                          22,
                          0,
                          22,
                          NuvoBottomNav.bottomPadding(context),
                        ),
                        child: _CompletedSegment(
                          races: completedRaces,
                          userId: uid,
                          expanded: _completedExpanded,
                          cap: _completedCap,
                          onToggleExpand: () => setState(
                            () => _completedExpanded = !_completedExpanded,
                          ),
                          onOpen: (race) => context.push('/race/${race.id}'),
                        ),
                      ),
                      _VerifySegment.recent => Padding(
                        padding: EdgeInsets.fromLTRB(
                          22,
                          0,
                          22,
                          NuvoBottomNav.bottomPadding(context),
                        ),
                        child: _RecentSegment(
                          entries: recentMoves,
                          userId: uid,
                          expanded: _recentExpanded,
                          cap: _recentCap,
                          onToggleExpand: () => setState(
                            () => _recentExpanded = !_recentExpanded,
                          ),
                          onOpen: (race) => context.push('/race/${race.id}'),
                        ),
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
              child: Text('Make your move.', style: AppTextStyles.screenTitle),
            ),
            NuvoPressable(
              onTap: onHistory,
              haptic: false,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.history_rounded, size: 21, color: c.inkMuted),
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
          // Fixed-width slots: filter chrome, so the label scale is pinned
          // — a third of 320px cannot take "Completed 12" scaled up, and a
          // truncated tab reads as broken, not dense.
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.0,
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
    required this.onOpen,
    required this.onStartRace,
  });

  final List<Race> races;
  final String? userId;
  final bool expanded;
  final int cap;
  final VoidCallback onToggleExpand;
  final ValueChanged<Race> onVerify;
  final ValueChanged<Race> onOpen;
  final VoidCallback onStartRace;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
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
    final hasMore = alsoReady.length > cap;

    // Gutters are applied per-child (the ListView carries none) so the
    // queue field below can run to the screen edges.
    final hero = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: NuvoStateMorph(
        stateKey: upNext.id,
        // Paint room for the board's 7px offset shadow — the morph's
        // AnimatedSize hard-clips to its child bounds, so the shadow's
        // room must live inside them.
        child: Padding(
          padding: const EdgeInsets.only(right: 7, bottom: 7),
          child: _UpNextHero(
            race: upNext,
            userId: userId,
            onVerify: () => onVerify(upNext),
            onOpen: () => onOpen(upNext),
          ),
        ),
      ),
    );

    if (alsoReady.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(bottom: NuvoBottomNav.bottomPadding(context)),
        child: hero,
      );
    }

    return _QueueBehindHero(
      hero: hero,
      // Ice-blue queue field: the races waiting behind the hero live on
      // one tinted band that runs edge-to-edge and under the scroll — a
      // field, not another card on the canvas. The header and "See all"
      // belong to the field — they label the layer, not any one strip.
      // The field is a shallow SHELF, not a list region: header + a
      // horizontal ticket carousel, then it ends. The full listing only
      // appears when the user asks for it — See all swaps the shelf for
      // the existing queue board inside the same field.
      queue: Container(
        padding: EdgeInsets.only(
          top: 30,
          bottom: 18 + NuvoBottomNav.bottomPadding(context),
        ),
        // The field's top boundary curves so the hero's silhouette settles
        // onto the plane instead of the plane cutting in behind it as a
        // hard horizontal band.
        decoration: BoxDecoration(
          color: c.panelLight,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Ready next',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.labelMedium.copyWith(
                        fontSize: 14.5,
                        color: c.inkMuted,
                        fontWeight: FontWeight.w800,
                      ),
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
                          expanded
                              ? 'Show less'
                              : 'See all ${alsoReady.length}',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: c.ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (expanded)
              // The existing full listing — one shared white board of
              // hairline-separated rows, on the same ice field.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 36),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(NuvoRadii.lg),
                    border: Border.all(color: c.divider, width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: c.inkShadow.withValues(alpha: 0.10),
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < alsoReady.length; i++) ...[
                        _ReadyRow(
                          race: alsoReady[i],
                          userId: userId,
                          first: i == 0,
                          onTap: () => onVerify(alsoReady[i]),
                        ),
                        if (i < alsoReady.length - 1)
                          Divider(height: 1, thickness: 1, color: c.divider),
                      ],
                    ],
                  ),
                ),
              )
            else
              // NOW → hero · NEXT → the wide ticket · LATER → the peek.
              _TicketCarousel(
                races: alsoReady,
                userId: userId,
                onVerify: onVerify,
              ),
          ],
        ),
      ),
    );
  }
}

/// The hero floats in front of the queue: the ice field's top edge begins
/// ~16px behind the board's bottom edge, so waiting races read as behind
/// the action rather than stacked after it.
///
/// The hero's height is dynamic (wrapped titles, absent lanes, the
/// finish-morph), so the field's offset is measured — the hero paints
/// last and always wins the overlap.
class _QueueBehindHero extends StatefulWidget {
  const _QueueBehindHero({required this.hero, required this.queue});

  final Widget hero;
  final Widget queue;

  /// How far the field's top edge tucks under the board's bottom edge.
  static const double _overlap = 16;

  @override
  State<_QueueBehindHero> createState() => _QueueBehindHeroState();
}

class _QueueBehindHeroState extends State<_QueueBehindHero> {
  double? _heroHeight;

  @override
  Widget build(BuildContext context) {
    final heroHeight = _heroHeight ?? 390;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Field first — it loses the overlap by paint order alone.
        Padding(
          padding: EdgeInsets.only(
            top: (heroHeight - _QueueBehindHero._overlap).clamp(
              0.0,
              double.infinity,
            ),
          ),
          child: widget.queue,
        ),
        _SizeReporting(
          onSize: (size) {
            if (size.height != _heroHeight) {
              setState(() => _heroHeight = size.height);
            }
          },
          child: widget.hero,
        ),
      ],
    );
  }
}

/// Reports its child's laid-out size after each frame — the one-way feed
/// [_QueueBehindHero] needs to track a morphing hero.
class _SizeReporting extends StatefulWidget {
  const _SizeReporting({required this.onSize, required this.child});

  final ValueChanged<Size> onSize;
  final Widget child;

  @override
  State<_SizeReporting> createState() => _SizeReportingState();
}

class _SizeReportingState extends State<_SizeReporting> {
  Size? _last;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final size = context.size;
      if (size != null && size != _last) {
        _last = size;
        widget.onSize(size);
      }
    });
    return widget.child;
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
    required this.onOpen,
    this.userId,
  });

  final Race race;
  final String? userId;
  final VoidCallback onVerify;

  /// Finished-race action — opens the leaderboard room instead of the
  /// proof flow.
  final VoidCallback onOpen;

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
        // Hold ~1s, then settle — a takeover is a moment, not a mood.
        Future.delayed(const Duration(milliseconds: 1000), () {
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
    final others =
        race.participants.where((p) => p.userId != widget.userId).toList()
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

    // Canonical lane geometry — a real finish target gives literal
    // share-of-distance fractions; best-attempt and lower-wins races get
    // the relative-competition lane (no invented goal ring).
    final geo = raceLaneGeometry(race, widget.userId);
    final rivalMark = rival == null
        ? null
        : geo.rivals.where((r) => r.racer.userId == rival.userId).firstOrNull;
    final showLane = geo.hasGoal || geo.viewer != null || rivalMark != null;

    // The stakes line is an artifact hanging off the lane's bottom edge —
    // uppercase, arrowed, colored by standing. A finished race drops the
    // chase copy entirely.
    final stakes = mood == _VerifyMood.finished
        ? (raceIsCompleted(race)
              ? 'RACE FINISHED'
              : 'GOAL REACHED — your proof is in')
        : _contextLine(rank, myValue, rival, leader).toUpperCase();
    final stakesColor = mood == _VerifyMood.startLine
        ? c.ink
        : _moodText(mood, c);

    return Stack(
      // The board's offset shadow paints past its bounds — this decorative
      // stack must not clip it.
      clipBehavior: Clip.none,
      children: [
        // The race board — one physical object: navy edge, offset depth,
        // white surface. WHAT → WHERE I AM → WHO I'M CHASING → WHAT I
        // NEED → DO IT, top to bottom.
        Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(NuvoRadii.lg),
            border: Border.all(color: c.border, width: 2),
            boxShadow: AppShadows.hardOffset(
              c.inkShadow,
              offset: const Offset(7, 7),
            ),
          ),
          child: Column(
            key: const Key('verify-up-next-hero'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
                child: Column(
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
                            child: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                              style: AppTextStyles.placementLabel(
                                size: 14,
                                // Rank color is state: gold only during the takeover
                                // flash or a finished win, restrained green while
                                // leading, navy when tied, muted while chasing.
                                color: _rankTint(
                                  mood,
                                  earnedRank,
                                  _leadFlash,
                                  c,
                                ),
                              ),
                              child: Text(
                                _ordinalLabel(earnedRank).toLowerCase(),
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
                    const SizedBox(height: 10),
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
                    if (showLane) ...[
                      const SizedBox(height: 4),
                      // The lane IS the rivalry — hero scale: you, the racer you're
                      // chasing, the finish ring. Tied gives the rival the viewer's
                      // physical mark size; leading wraps the viewer in a green
                      // halo; the takeover earns a hard gold ring for its moment.
                      RaceMarkerTrack(
                        hero: true,
                        fillColor: _moodMarker(mood),
                        goalReached: mood == _VerifyMood.finished,
                        hasGoal: geo.hasGoal,
                        goalLabel: geo.hasGoal
                            ? 'Goal ${_anchorFormat(race.targetValue!)}'
                            : null,
                        markers: [
                          if (rival != null && rivalMark != null)
                            RaceTrackMarker(
                              fraction: rivalMark.fraction,
                              label:
                                  '${_firstName(rival.displayName)} '
                                  '${_anchorFormat(rival.progressValue)}',
                              color: c.ink,
                              size: mood == _VerifyMood.tied ? 20 : null,
                            ),
                          if (geo.viewer != null)
                            RaceTrackMarker(
                              fraction: geo.viewer!,
                              label: 'You ${_anchorFormat(myValue)}',
                              color: _moodMarker(mood),
                              isViewer: true,
                              haloColor:
                                  (mood == _VerifyMood.leading
                                          ? NuvoColors.success
                                          : NuvoColors.blue)
                                      .withValues(alpha: 0.28),
                              ringColor: _leadFlash ? NuvoColors.gold : null,
                            ),
                        ],
                      ),
                    ] else ...[
                      const SizedBox(height: 10),
                    ],
                    // The stakes tab hangs off the lane's bottom edge — attached to
                    // the visualization, not floating copy.
                    Transform.translate(
                      offset: Offset(0, showLane ? -10 : 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(left: 12),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: c.surface,
                            borderRadius: BorderRadius.circular(9),
                            // Semantic standing color on the artifact edge, not
                            // just the copy.
                            border: Border.all(color: stakesColor, width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                color: c.inkShadow,
                                offset: const Offset(2, 2),
                                blurRadius: 0,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                mood == _VerifyMood.finished
                                    ? Icons.flag_rounded
                                    : Icons.north_rounded,
                                size: 11,
                                color: stakesColor,
                              ),
                              const SizedBox(width: 5),
                              Flexible(
                                child: AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeOutCubic,
                                  style: AppTextStyles.labelUppercase(10.5)
                                      .copyWith(
                                        color: stakesColor,
                                        fontWeight: FontWeight.w800,
                                      ),
                                  child: Text(
                                    stakes,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: showLane ? 4 : 12),
              // DO IT — the board's one action band: full-bleed foot
              // separated by the structural hairline so the proof action
              // reads as part of the race object, not a card inside a card.
              // The proof method IS the label; a finished race swaps to the
              // room itself.
              Container(
                padding: const EdgeInsets.fromLTRB(18, 13, 18, 15),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: c.inkShadow.withValues(alpha: 0.14),
                      width: 1.5,
                    ),
                  ),
                ),
                child: NuvoPrimaryButton(
                  key: const Key('verify-hero-cta'),
                  label: mood == _VerifyMood.finished
                      ? 'View race'
                      : raceProofCta(race).label,
                  onPressed: mood == _VerifyMood.finished
                      ? widget.onOpen
                      : widget.onVerify,
                  leadingWidget: _ctaKeycap(
                    mood == _VerifyMood.finished
                        ? Icons.flag_rounded
                        : raceProofCta(race).icon,
                  ),
                  expand: true,
                  height: 48,
                ),
              ),
            ],
          ),
        ),
        // Lead-takeover flash — a tag pinned on the board's top rail:
        // straddling the edge keeps the title readable under it instead of
        // stamping over the headline. Idle stays calm.
        Positioned(
          top: -13,
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
                      style: AppTextStyles.labelUppercase(
                        11,
                      ).copyWith(color: NuvoColors.navy),
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
    final numberColor = hasResult && moodColor != c.inkSubtle
        ? moodColor
        : c.ink;
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
        hasResult &&
        unit.isNotEmpty &&
        unit != 'percent' &&
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
                  style: AppTextStyles.labelUppercase(
                    10.5,
                  ).copyWith(color: c.inkMuted),
                ),
              Text(
                resultLabel,
                style: AppTextStyles.labelUppercase(
                  10.5,
                ).copyWith(color: hasResult ? accent : c.inkDim),
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
/// `finished` is the viewer's own finish line crossed while the race is
/// still live (or the race itself closed): green, and no chase copy.
enum _VerifyMood { startLine, chasing, tied, leading, finished }

_VerifyMood _moodFor(Race race, String? userId) {
  final myPart = userId != null ? race.participantFor(userId) : null;
  final myValue = myPart?.progressValue ?? 0;
  if (raceIsCompleted(race) || raceProgressPercent(race, myPart) >= 100) {
    return _VerifyMood.finished;
  }
  if (myValue <= 0) return _VerifyMood.startLine;
  final rank = rankForUser(race, userId);
  if (rank == null) return _VerifyMood.chasing;
  if (race.viewerContext?.isTied == true) return _VerifyMood.tied;
  if (rank == 1) return _VerifyMood.leading;
  return _VerifyMood.chasing;
}

/// Marker/track color — the state is carried by the track and dots.
/// Palette is state-based only: blue = racing/chasing (a tie is still a
/// chase), green = leading/finished. Gold is reserved for the win payoff.
Color _moodMarker(_VerifyMood m) => switch (m) {
  _VerifyMood.startLine => NuvoColors.blue,
  _VerifyMood.chasing => NuvoColors.blue,
  _VerifyMood.tied => NuvoColors.blue,
  _VerifyMood.leading => NuvoColors.success,
  _VerifyMood.finished => NuvoColors.success,
};

/// Text color for mood statements — the *_On variants keep contrast on
/// light surfaces; on dark they stay readable since they sit on ink text.
Color _moodText(_VerifyMood m, NuvoThemeColors c) => switch (m) {
  _VerifyMood.startLine => c.inkSubtle,
  _VerifyMood.chasing => NuvoColors.blue,
  _VerifyMood.tied => NuvoColors.blue,
  _VerifyMood.leading => NuvoColors.successOn,
  _VerifyMood.finished => NuvoColors.successOn,
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

/// The hero rank's tint, by state — gold is the payoff only (takeover
/// flash or a finished win), green reads "in front", navy "level", and a
/// chasing rank stays quiet.
Color _rankTint(_VerifyMood mood, int rank, bool leadFlash, NuvoThemeColors c) {
  if (leadFlash) return NuvoColors.gold;
  return switch (mood) {
    _VerifyMood.tied => c.ink,
    _VerifyMood.leading => NuvoColors.successOn,
    _VerifyMood.finished => rank == 1 ? NuvoColors.position1 : c.inkSubtle,
    _ => c.inkSubtle,
  };
}

/// The CTA's proof-method icon as a navy keycap — reads as a specific
/// physical action on the blue band, not a generic arrow.
Widget _ctaKeycap(IconData icon) => Container(
  width: 28,
  height: 28,
  decoration: BoxDecoration(
    color: NuvoColors.navy,
    borderRadius: BorderRadius.circular(9),
  ),
  child: Icon(icon, size: 16, color: Colors.white),
);

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
    this.first = false,
  });

  final Race race;
  final String? userId;
  final VoidCallback onTap;

  /// True only for the queue board's first row — the NEXT race: a pill
  /// plus a little more air and a stronger title, all on the board's
  /// shared surface. Hierarchy inside the object, never a second card.
  final bool first;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      scale: 0.98,
      child: Padding(
        padding: first
            ? const EdgeInsets.fromLTRB(14, 12, 12, 13)
            : const EdgeInsets.fromLTRB(14, 11, 12, 11),
        child: _QueueRowBody(race: race, userId: userId, first: first),
      ),
    );
  }
}

// ── Race ticket shelf — the horizontal Ready-next queue ─────────────────────

/// The shelf's page geometry: tickets run ~80% of the viewport so the next
/// race visibly peeks from the right at rest — the swipe affordance is the
/// peek itself, no dots needed to explain it.
const double _ticketFraction = 0.8;

/// Fixed slot height — one silhouette for every race state so the shelf
/// reads as a stack of identical tickets, not a masonry feed. Content is
/// top-anchored; start-line tickets simply carry more air at the bottom.
const double _ticketSlotHeight = 158;

/// A horizontal snap-carousel of race tickets on the ice shelf. PageView
/// supplies the snapping; scale/opacity quieten the peeking pages. With a
/// single race the shelf centers one ticket — no fake peek.
class _TicketCarousel extends StatefulWidget {
  const _TicketCarousel({
    required this.races,
    required this.userId,
    required this.onVerify,
  });

  final List<Race> races;
  final String? userId;
  final ValueChanged<Race> onVerify;

  @override
  State<_TicketCarousel> createState() => _TicketCarouselState();
}

class _TicketCarouselState extends State<_TicketCarousel> {
  late final PageController _controller = PageController(
    viewportFraction: _ticketFraction,
  );
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final races = widget.races;
    if (races.length == 1) {
      // One upcoming race — centered, no fake peek.
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: SizedBox(
          height: _ticketSlotHeight,
          child: _RaceTicket(
            race: races[0],
            userId: widget.userId,
            isNext: true,
            onTap: () => widget.onVerify(races[0]),
          ),
        ),
      );
    }
    return Column(
      children: [
        SizedBox(
          height: _ticketSlotHeight,
          child: PageView.builder(
            controller: _controller,
            padEnds: false,
            onPageChanged: (i) => setState(() => _index = i),
            itemCount: races.length,
            itemBuilder: (context, i) {
              final selected = i == _index;
              return Padding(
                padding: EdgeInsets.only(
                  left: i == 0 ? 28 : 7,
                  right: i == races.length - 1 ? 28 : 7,
                ),
                child: AnimatedScale(
                  scale: selected ? 1 : 0.97,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  child: AnimatedOpacity(
                    opacity: selected ? 1 : 0.94,
                    duration: const Duration(milliseconds: 180),
                    child: _RaceTicket(
                      race: races[i],
                      userId: widget.userId,
                      isNext: i == 0,
                      onTap: () => widget.onVerify(races[i]),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        if (races.length <= 7)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < races.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 2.5),
                  width: i == _index ? 14 : 5,
                  height: 5,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: i == _index
                        ? NuvoColors.blue
                        : c.inkDim.withValues(alpha: 0.35),
                  ),
                ),
            ],
          )
        else
          Text(
            '${_index + 1} of ${races.length}',
            style: AppTextStyles.labelSmall.copyWith(
              fontSize: 11,
              color: c.inkMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }
}

/// One ticket on the shelf: white surface, 18px radius, a thin navy
/// structural edge and a restrained bottom/right plate — a real Nuvo
/// object, but several weights below the hero (2px edge, 7px plate).
/// The NEXT race carries a small edge-attached tab, not a nested card.
class _RaceTicket extends StatelessWidget {
  const _RaceTicket({
    required this.race,
    required this.onTap,
    this.userId,
    this.isNext = false,
  });

  final Race race;
  final String? userId;
  final VoidCallback onTap;
  final bool isNext;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          // Room for the tab's overhang and the plate's offset.
          top: 9,
          right: 3,
          bottom: 3,
          child: PressableScale(
            onTap: onTap,
            scale: 0.98,
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 13, 12, 12),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(NuvoRadii.md),
                border: Border.all(color: c.border, width: 1.5),
                boxShadow: AppShadows.hardOffset(
                  c.inkShadow,
                  offset: const Offset(2, 3),
                ),
              ),
              child: _QueueRowBody(race: race, userId: userId),
            ),
          ),
        ),
        if (isNext) const Positioned(top: 0, left: 18, child: _NextTab()),
      ],
    );
  }
}

/// The NEXT artifact: a small navy-edged tab docked to the ticket's top
/// edge — attached hardware, not a floating badge.
class _NextTab extends StatelessWidget {
  const _NextTab();

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: c.panelLight,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: c.border, width: 1.2),
      ),
      child: Text(
        'NEXT',
        style: AppTextStyles.labelSmall.copyWith(
          fontSize: 9.5,
          color: c.ink,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

/// A queued race's content, shared between the shelf's tickets and the
/// expanded board's rows: title + earned rank, canonical result/meta, a
/// thin lane when a denominator exists, and one context line. No surface,
/// no chrome — callers own the object it lives on.
class _QueueRowBody extends StatelessWidget {
  const _QueueRowBody({required this.race, this.userId, this.first = false});

  final Race race;
  final String? userId;
  final bool first;

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

    // Canonical lane geometry for the strip's compact race lane.
    final geo = raceLaneGeometry(race, userId);
    final stripRival = raceNearestRival(race, userId);
    final stripRivalMark = stripRival == null
        ? null
        : geo.rivals
              .where((r) => r.racer.userId == stripRival.userId)
              .firstOrNull;
    final showLane =
        geo.hasGoal || geo.viewer != null || stripRivalMark != null;

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
    if (mood == _VerifyMood.finished) {
      contextLine = raceIsCompleted(race) ? 'Race finished' : 'Goal reached';
    } else if (hasResult && hasDenominator) {
      final remaining = race.targetValue! - myValue;
      if (remaining > 0) {
        contextLine = '${_scoreText(race, remaining)} left';
      }
    } else if (hasResult && race.participantCount > 1) {
      final others = race.participants.where((p) => p.userId != userId).toList()
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
          rival = others.firstWhere(
            (p) => p.rank == rank - 1,
            orElse: () => others.first,
          );
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

    final arrow = Icon(Icons.arrow_forward_rounded, color: c.inkDim, size: 16);

    // No chrome — the caller owns the surface. `first` earns a NEXT pill;
    // a start-line row stays shorter by docking its arrow on the meta
    // line instead of spending a fourth line on it.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (first)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: c.panelLight,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'NEXT',
                style: AppTextStyles.labelSmall.copyWith(
                  fontSize: 9.5,
                  color: c.ink,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.3,
                ),
              ),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: Text(
                race.displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.raceRowTitle.copyWith(
                  fontSize: first ? 15.5 : 15,
                  fontWeight: first ? FontWeight.w800 : FontWeight.w700,
                ),
              ),
            ),
            if (earnedRank != null) ...[
              const SizedBox(width: 8),
              Text(
                _ordinalLabel(earnedRank).toLowerCase(),
                style: AppTextStyles.placementLabel(
                  size: 12.5,
                  // Same state language as the hero: gold only on a
                  // finished win — a live lead reads green.
                  color: _rankTint(mood, earnedRank, false, c),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            Expanded(
              child: Text(
                meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.raceRowMeta.copyWith(
                  fontSize: 12.5,
                  color: c.inkSubtle,
                ),
              ),
            ),
            if (contextLine == null) arrow,
          ],
        ),
        if (showLane) ...[
          const SizedBox(height: 9),
          // The same canonical marks as the hero, at strip scale —
          // unlabeled compact lane, viewer bead + rival dot + goal ring.
          RaceMarkerTrack(
            compact: true,
            fillColor: _moodMarker(mood),
            goalReached: mood == _VerifyMood.finished,
            hasGoal: geo.hasGoal,
            markers: [
              if (stripRivalMark != null)
                RaceTrackMarker(
                  fraction: stripRivalMark.fraction,
                  label: '',
                  color: c.ink,
                  size: mood == _VerifyMood.tied ? 9 : null,
                ),
              if (geo.viewer != null)
                RaceTrackMarker(
                  fraction: geo.viewer!,
                  label: '',
                  color: _moodMarker(mood),
                  isViewer: true,
                ),
            ],
          ),
        ],
        if (contextLine != null) ...[
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                child: Text(
                  contextLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelSmall.copyWith(
                    fontSize: 12,
                    color: mood != _VerifyMood.startLine
                        ? _moodText(mood, c)
                        : c.inkSubtle,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              arrow,
            ],
          ),
        ],
      ],
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
    final myPart = userId != null ? race.participantFor(userId!) : null;
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
    final ago = completed != null ? notificationRelativeTime(completed) : null;
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
                won ? Icons.emoji_events_rounded : Icons.flag_outlined,
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
            Icon(Icons.arrow_forward_rounded, color: c.inkDim, size: 17),
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
                  style: AppTextStyles.labelUppercase(
                    11,
                  ).copyWith(color: context.themeColors.inkDim),
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
      'MONDAY',
      'TUESDAY',
      'WEDNESDAY',
      'THURSDAY',
      'FRIDAY',
      'SATURDAY',
      'SUNDAY',
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
        : raceIsAccumulating(race)
        ? '+${_scoreText(race, value)}'
        : _scoreText(race, value);

    final actorName = proof.userId == userId ? 'You' : proof.displayName;

    // "What changed because I proved it" — accepted amount, the rank move
    // it caused when the server recorded one, verification state.
    final metaParts = [statusLabel, ?rankDelta];

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
      body: 'Join a race or start one, then your next move shows up here.',
      ctaLabel: 'Create a race',
      onCta: onStart,
    );
  }
}

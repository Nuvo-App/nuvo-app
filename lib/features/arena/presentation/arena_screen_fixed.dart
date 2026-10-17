import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_geometry.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/bottom_nav.dart';
import '../../../core/widgets/nuvo_avatar.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_error_state.dart';
import '../../../core/widgets/nuvo_motion.dart';
import '../../../core/widgets/nuvo_race_components.dart';
import '../../../core/widgets/nuvo_race_path.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../races/data/race_models.dart';
import '../../races/domain/race_display.dart';
import '../../races/presentation/ai_motion_proof_entry.dart';
import '../../races/presentation/race_controller.dart';
import '../data/arena_models.dart';
import 'arena_controller.dart';

// Structural chrome (page/surface/ink/muted) resolves through
// `context.themeColors` at each call site — module-level consts can't
// follow dark mode. Only the semantic accents stay constant.
const _arenaBlue = NuvoColors.blue;
const _arenaGreen = NuvoColors.success;

class ArenaScreen extends ConsumerStatefulWidget {
  const ArenaScreen({super.key, this.preview = false, this.debugSnapshot});

  final bool preview;

  /// Test seam: when provided, this snapshot is rendered verbatim instead
  /// of the arena controller's — lets widget tests drive specific boards
  /// (solo, head-to-head, full podium) without stubbing providers.
  final ArenaSnapshot? debugSnapshot;

  @override
  ConsumerState<ArenaScreen> createState() => _ArenaScreenState();
}

class _ArenaScreenState extends ConsumerState<ArenaScreen>
    with SingleTickerProviderStateMixin {
  final PageController _boardsController = PageController(viewportFraction: 1);
  int _boardPage = 0;

  /// 0 = leaderboard folded to the top 3, 1 = curtain fully dropped.
  late final AnimationController _curtain;

  @override
  void initState() {
    super.initState();
    _curtain = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
  }

  bool get _unfolded =>
      _curtain.status == AnimationStatus.forward ||
      _curtain.status == AnimationStatus.completed;

  void _setUnfolded(bool open) {
    if (open == _unfolded && !_curtain.isAnimating) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _curtain.value = open ? 1 : 0;
      setState(() {});
      return;
    }
    if (open) {
      _curtain.forward();
    } else {
      _curtain.reverse();
    }
    setState(() {});
  }

  @override
  void dispose() {
    _curtain.dispose();
    _boardsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = widget.preview ? null : ref.watch(authControllerProvider);
    final user = authState?.user;
    final isOffline =
        !widget.preview && authState?.status == AuthStatus.offline;
    final arenaState = widget.preview
        ? null
        : ref.watch(arenaControllerProvider);
    final raceState = widget.preview ? null : ref.watch(raceControllerProvider);
    final snapshot = widget.preview
        ? (widget.debugSnapshot ?? _previewSnapshot())
        : (widget.debugSnapshot ?? arenaState?.snapshot);
    final raceById = {
      for (final race in raceState?.races ?? const <Race>[]) race.id: race,
    };
    final boards = _boardsFor(snapshot);
    final activeBoard = boards.isEmpty
        ? null
        : boards[_boardPage.clamp(0, boards.length - 1)];

    // First-composition budget. The first screen is the header, the next-move
    // card, its actions and the TOP 3 of the leaderboard with the control that
    // unfolds the rest (the curtain). Everything else is folded away, so the
    // page does not scroll until the curtain is dropped.
    //
    // heroHeight: whatever the usable viewport leaves after the header, label,
    // dots, actions and the leaderboard peek. The fold is the dock's TOP EDGE.
    // The card has exactly two legal compositions — compact (~296px) and tall
    // (>=324px). When even compact won't fit the page scrolls; the card never
    // renders shorter than its content.
    final media = MediaQuery.of(context);
    final dockReserve = _dockReserve(media);
    final dockTop = media.size.height - dockReserve;
    // The shell strips the top inset from this context; the status bar still
    // occupies it, so read it from the view.
    final topInset = math.max(
      media.padding.top,
      MediaQueryData.fromView(View.of(context)).padding.top,
    );
    final usableViewport =
        dockTop - topInset - 10; // breathing unit above the dock
    final tight = usableViewport < 560;
    final roomy = usableViewport >= 760; // room for the section label
    final heroBase = switch (usableViewport) {
      < 560 => 300.0, // compact phones
      < 800 => 340.0, // standard
      _ => 400.0, // large
    };
    final entries = activeBoard == null
        ? const <_LbEntry>[]
        : _leaderboardEntries(
            board: activeBoard,
            race: raceById[activeBoard.id],
            currentUserId: user?.id,
            initials: user?.avatarInitials ?? '?',
            photoUrl: user?.profilePhotoUrl,
          );
    final peek = _PeekMetrics.of(entries, tight: tight);
    final fixedElsewhere =
        (tight ? 86.0 : 110.0) +
        (roomy ? 6 + 20 + 8 : 4) +
        (boards.length > 1 ? 20 : 0) +
        (tight ? 4 : 8) +
        (tight ? 56 : 64) +
        peek.height;
    final allowance = usableViewport - fixedElsewhere;
    // Content floor: the shared PageView slot must fit the WORST board in
    // the carousel — a two-line title is ~32px taller than a one-liner and
    // the slot can't grow per page. Measured with TextPainter at the
    // card's real text width so long race names never clip.
    final cardTextWidth =
        media.size.width - NuvoSpacing.pageHorizontal * 2 - 12 - 40;
    var heroHeight = allowance >= 300 ? math.min(heroBase, allowance) : 0.0;
    for (var pass = 0; pass < 2; pass++) {
      var need = 0.0;
      for (final board in boards) {
        need = math.max(
          need,
          _heroContentHeight(
            board,
            cardTextWidth,
            media.textScaler,
            tall: heroHeight >= 300,
            race: raceById[board.id],
            viewerId: user?.id,
          ),
        );
      }
      if (need <= heroHeight) break;
      heroHeight = need;
    }
    final firstScreenOverflows = fixedElsewhere + heroHeight > usableViewport;
    final greeting =
        user?.fullName?.trim().split(RegExp(r'\s+')).first ?? 'there';
    final loading =
        !widget.preview && ((arenaState?.loading ?? false) && snapshot == null);

    void retryConnection() =>
        ref.read(authControllerProvider.notifier).retryRestore();

    return Scaffold(
      backgroundColor: context.themeColors.page,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: context.themeColors.accent,
          backgroundColor: context.themeColors.surface,
          onRefresh: widget.preview
              ? () async {}
              : () => ref.read(arenaControllerProvider.notifier).loadSnapshot(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (loading ||
                  (isOffline && snapshot == null) ||
                  (arenaState?.error != null && snapshot == null) ||
                  activeBoard == null) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
                    child: _ArenaHeader(greeting: greeting),
                  ),
                ),
                // Cached content exists but the connection is down — keep the
                // board visible (it's still real data) and say so quietly
                // instead of replacing it with a generic error.
                if (isOffline && snapshot != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
                      child: NuvoOfflineBanner(onRetry: retryConnection),
                    ),
                  ),
                if (loading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _LoadingState(),
                  )
                else if (isOffline && snapshot == null)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: NuvoErrorState(
                      title: 'No connection',
                      message:
                          "Nuvo couldn't load your races. Check your connection and try again.",
                      retryLabel: 'Try again',
                      onRetry: retryConnection,
                    ),
                  )
                else if (arenaState?.error != null && snapshot == null)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _ErrorState(
                      message: arenaState!.error!,
                      onRetry: () => ref
                          .read(arenaControllerProvider.notifier)
                          .loadSnapshot(),
                    ),
                  )
                else
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _FirstRunState(
                      onStart: () => context.push('/races/new'),
                      onIdea: (idea) => context.push(
                        '/races/new',
                        extra: RaceCreatePrefill(idea: idea),
                      ),
                      onJoin: () => context.push('/races/join'),
                    ),
                  ),
              ] else ...[
                SliverToBoxAdapter(
                  child: AnimatedBuilder(
                    animation: _curtain,
                    builder: (context, _) {
                      final t = Curves.easeOutCubic.transform(_curtain.value);
                      final open = _unfolded;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              22,
                              tight ? 12 : 18,
                              22,
                              0,
                            ),
                            child: _ArenaHeader(greeting: greeting),
                          ),
                          if (isOffline)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
                              child: NuvoOfflineBanner(
                                onRetry: retryConnection,
                              ),
                            ),
                          if (!roomy)
                            const SizedBox(height: 4)
                          else ...[
                            const SizedBox(height: 6),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: NuvoSpacing.pageHorizontal,
                              ),
                              child: _SectionLabel(
                                title: 'Your next move',
                                trailing: boards.length > 1
                                    ? '${_boardPage + 1} / ${boards.length}'
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: NuvoSpacing.pageHorizontal,
                            ),
                            child: SizedBox(
                              height: heroHeight,
                              child: PageView.builder(
                                controller: _boardsController,
                                clipBehavior: Clip.hardEdge,
                                itemCount: boards.length,
                                onPageChanged: (page) {
                                  _curtain.value = 0;
                                  setState(() => _boardPage = page);
                                },
                                padEnds: false,
                                itemBuilder: (context, index) =>
                                    _BoardCarouselItem(
                                      controller: _boardsController,
                                      index: index,
                                      board: boards[index],
                                      race: raceById[boards[index].id],
                                      viewerId: user?.id,
                                      heroHeight: heroHeight,
                                      onOpen: () =>
                                          _openBoard(context, boards[index]),
                                    ),
                              ),
                            ),
                          ),
                          if (boards.length > 1) ...[
                            const SizedBox(height: 6),
                            Center(
                              child: _PageDots(
                                count: boards.length,
                                selected: _boardPage,
                              ),
                            ),
                          ],
                          SizedBox(height: tight ? 4 : 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: NuvoSpacing.pageHorizontal,
                            ),
                            child: _QuickActions(
                              height: tight ? 56 : 64,
                              onSubmit: activeBoard.isResult
                                  ? null
                                  : () => _handlePrimaryAction(
                                      context,
                                      activeBoard,
                                      raceById,
                                    ),
                              onStart: () => context.push('/races/new'),
                              onJoin: () => context.push('/races/join'),
                            ),
                          ),
                          KeyedSubtree(
                            key: ValueKey('board-sections-${activeBoard.id}'),
                            child: _LeaderboardPeek(
                              entries: entries,
                              metrics: peek,
                              tight: tight,
                              unfolded: open,
                              t: t,
                              raw: _curtain.value,
                              onToggle: () => _setUnfolded(!open),
                              onFlingUp: () => _setUnfolded(true),
                              onFlingDown: () => _setUnfolded(false),
                            ),
                          ),
                          SizedBox(
                            // Clear the dock once the curtain is down — or while
                            // folded when the first screen can't fit at all
                            // (smallest phones), so the control is reachable.
                            height:
                                NuvoBottomNav.bottomPadding(context) *
                                (firstScreenOverflows ? 1.0 : t),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<ArenaBoard> _boardsFor(ArenaSnapshot? snapshot) {
    if (snapshot == null) return const [];
    final result = <ArenaBoard>[];
    if (snapshot.focusBoard != null) result.add(snapshot.focusBoard!);
    for (final board in snapshot.liveBoards) {
      if (result.every((existing) => existing.id != board.id)) {
        result.add(board);
      }
    }
    if (result.isEmpty) result.addAll(snapshot.results);
    return result;
  }

  void _handlePrimaryAction(
    BuildContext context,
    ArenaBoard board,
    Map<String, Race> races,
  ) {
    if (board.isDemo) return _demoSnack(context);
    final race = races[board.id];
    switch (board.primaryActionType) {
      case 'start_race':
        context.push('/races/new');
      // A live race I can prove in right now goes straight to the proof
      // entry (camera races: motion setup / AI Motion Proof behind the
      // camera primer; others: the proof chooser). Anything else (finished,
      // not loaded) opens the race page — the leaderboard room.
      default:
        if (race != null && race.status == 'active' && !board.isResult) {
          openAiMotionProof(
            context,
            ref,
            race,
            routeAction: 'arena_primary_action_${board.primaryActionType}',
            fromPreview: true,
          );
        } else {
          context.push('/race/${board.id}');
        }
    }
  }

  void _openBoard(BuildContext context, ArenaBoard board) {
    if (board.isDemo) return _demoSnack(context);
    context.push('/race/${board.id}');
  }

  void _demoSnack(BuildContext context) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: Text('Demo board preview')));
}

class _ArenaHeader extends StatelessWidget {
  const _ArenaHeader({required this.greeting});
  final String greeting;

  static String _timeGreeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Arena',
        // Same scale as every other tab title (Compete/Verify/Crew/Profile
        // all use screenTitle) — Arena used to run a bespoke 44px override
        // that made it feel like a different app section.
        style: AppTextStyles.screenTitle,
      ),
      const SizedBox(height: 6),
      Text(
        '${_timeGreeting()}, $greeting',
        style: AppTextStyles.titleLarge.copyWith(
          color: context.themeColors.inkSubtle,
          fontWeight: FontWeight.w500,
        ),
      ),
    ],
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title, this.trailing});
  final String title;
  final String? trailing;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      // Sentence case, not tracked all-caps — Arena used to be the one
      // screen running "YOUR NEXT MOVE" style labels, which read as a
      // different design system rather than the same app. Kept at the same
      // size/weight as before (titleMedium, not the smaller shared
      // sectionTitle) — this screen's first-viewport composition is
      // pixel-budgeted (test/arena/arena_first_viewport_test.dart).
      Expanded(
        child: Text(
          title,
          style: AppTextStyles.titleMedium.copyWith(
            color: context.themeColors.ink,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      if (trailing != null)
        Text(
          trailing!,
          style: AppTextStyles.labelMedium.copyWith(
            color: context.themeColors.accent,
          ),
        ),
    ],
  );
}

class _BoardCarouselItem extends StatelessWidget {
  const _BoardCarouselItem({
    required this.controller,
    required this.index,
    required this.board,
    required this.heroHeight,
    required this.onOpen,
    this.race,
    this.viewerId,
  });

  final PageController controller;
  final int index;
  final ArenaBoard board;
  final double heroHeight;
  final VoidCallback onOpen;

  /// The authoritative race behind this board, when loaded — gives the
  /// hero canonical target/direction/participants for the marker lane.
  final Race? race;
  final String? viewerId;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, child) {
      final page = controller.hasClients
          ? (controller.page ?? index.toDouble())
          : index.toDouble();
      final delta = (page - index).clamp(-1.0, 1.0);
      final distance = delta.abs();
      final arcOffset = distance * distance * 34;
      return Transform.translate(
        offset: Offset(0, arcOffset),
        child: Transform.rotate(
          angle: -delta * 0.05,
          child: Transform.scale(
            scale: 1 - distance * 0.045,
            child: Padding(
              // Uniform on every page: the 12px gap separates cards mid-
              // swipe AND covers the hard shadow's 7px right offset —
              // the last page used to drop it, so its shadow was sliced
              // by the PageView's hardEdge clip at the screen edge.
              padding: const EdgeInsets.only(right: 12, bottom: 10),
              child: child,
            ),
          ),
        ),
      );
    },
    child: _NextMoveHero(
      board: board,
      race: race,
      viewerId: viewerId,
      heroHeight: heroHeight,
      onOpen: onOpen,
    ),
  );
}

class _NextMoveHero extends StatelessWidget {
  const _NextMoveHero({
    required this.board,
    required this.heroHeight,
    required this.onOpen,
    this.race,
    this.viewerId,
  });
  final ArenaBoard board;
  final double heroHeight;
  final VoidCallback onOpen;
  final Race? race;
  final String? viewerId;
  @override
  Widget build(BuildContext context) {
    final pct = (board.progressPercent ?? 0).clamp(0, 100);
    // A taller card gets a bigger progress numeral and a bit more air; a
    // floored card on a small phone stays compact.
    final tall = heroHeight >= 300;
    final progressFontSize = tall ? 66.0 : 56.0;
    final footerAvatars = board.miniLeaderboard
        .map(
          (row) =>
              (initials: _initials(row.label), photoUrl: row.profilePhotoUrl),
        )
        .toList();
    final footerTotal = board.racerCount ?? footerAvatars.length;
    final c = context.themeColors;
    final lane = _heroLane(board, race, viewerId);
    final heroSurface = arenaHeroSurface(
      Theme.of(context).brightness,
      c.surface,
    );
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: heroSurface,
        borderRadius: BorderRadius.circular(NuvoRadii.hero),
        border: Border.all(color: c.border, width: 2),
        boxShadow: AppShadows.hardOffset(
          c.inkShadow,
          offset: const Offset(7, 7),
        ),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(NuvoRadii.hero),
        border: Border.all(color: c.border, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                tall ? 12 : 10,
                20,
                tall ? 8 : 4,
              ),
              // Anchored to the top with a fixed gap before the participant
              // context — not spaceBetween, which used to stretch to fill
              // whatever height the card happened to get and left a large
              // blank gap above "N racers" on anything but the smallest
              // phones.
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Title + progress + track — the group that anchors the top.
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              board.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.headlineMedium.copyWith(
                                color: context.themeColors.ink,
                                fontSize: tall ? 30 : 28,
                                height: 1.05,
                                letterSpacing: 0,
                              ),
                            ),
                          ),
                          // The standing belongs to the title line — the
                          // card's verdict reads before the lane does.
                          if (board.myRank != null) ...[
                            const SizedBox(width: 10),
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                raceOrdinal(board.myRank!),
                                style: AppTextStyles.placementLabel(
                                  size: 15,
                                  color: _arenaPlacement(board.myRank!, c),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      SizedBox(height: tall ? 8 : 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _progressValue(board.progressLabel, pct),
                            style: AppTextStyles.displayMedium.copyWith(
                              color: context.themeColors.accent,
                              fontSize: progressFontSize,
                              height: .85,
                              letterSpacing: 0,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Text(
                                _progressSuffix(board.progressLabel),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.headlineMedium.copyWith(
                                  color: context.themeColors.ink,
                                  fontSize: 24,
                                  letterSpacing: 0,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: tall ? 8 : 4),
                      // The hero's race PATH — the seeded curved course,
                      // not a straight lane: this is the world of the race,
                      // where Verify is its control board. Canonical marks
                      // ride the same course — your bead, the racer you're
                      // chasing, the finish flag — positions from
                      // raceLaneGeometry, so lower-wins/best-attempt races
                      // still get the honest relative lane (no fake goal).
                      NuvoRacePath(
                        key: ValueKey('progress-${board.id}'),
                        raceId: board.id,
                        progress: lane?.viewerFraction ?? pct / 100,
                        rivalFraction: lane?.rivalFraction,
                        viewerLabel: lane?.viewerLabel,
                        rivalLabel: lane?.rivalLabel,
                        goalLabel: lane?.goalLabel,
                        hasGoal: lane?.hasGoal ?? true,
                        progressColor: (lane?.leading ?? false)
                            ? _arenaGreen
                            : _arenaBlue,
                        completedColor: _arenaGreen,
                      ),
                      // Stakes — what the next proof changes, straight from
                      // the server's chase copy.
                      if (board.chaseCopy != null &&
                          board.chaseCopy!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          board.chaseCopy!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.labelMedium.copyWith(
                            color: (lane?.leading ?? false)
                                ? _arenaGreen
                                : _arenaBlue,
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          NuvoPressable(
            onTap: onOpen,
            // Nearly-full scale: the band lives inside the card's clip, so a
            // big shrink would reveal white slivers at the edges — a small
            // sink reads as pressed without breaking the silhouette.
            scale: 0.99,
            translateY: 2,
            haptic: false,
            child: Container(
              // The chunky blue footer — a real tappable band, sized up with
              // the card.
              height: tall ? 54 : 50,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              color: _arenaBlue,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      board.isResult ? 'Open race board' : 'See race board',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.buttonLabel.copyWith(
                        color: NuvoColors.white,
                      ),
                    ),
                  ),
                  if (footerAvatars.isNotEmpty) ...[
                    NuvoAvatarStack(
                      avatars: footerAvatars,
                      total: footerTotal,
                      size: 25,
                      max: 3,
                      borderColor: _arenaBlue,
                    ),
                    const SizedBox(width: 12),
                  ],
                  const Icon(
                    Icons.arrow_forward_rounded,
                    color: NuvoColors.white,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.selected});
  final int count;
  final int selected;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (var i = 0; i < count; i++)
        AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: i == selected ? 20 : 6,
          height: i == selected ? 8 : 6,
          decoration: BoxDecoration(
            color: i == selected ? _arenaBlue : Colors.transparent,
            border: Border.all(
              color: context.themeColors.border,
              width: i == selected ? 1.5 : 1.25,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
    ],
  );
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    this.height = 64,
    required this.onSubmit,
    required this.onStart,
    required this.onJoin,
  });
  final double height;
  final VoidCallback? onSubmit;
  final VoidCallback onStart;
  final VoidCallback onJoin;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        // Was 4:2:2 — the two labeled secondaries need a bit more than a
        // bare icon did to fit icon + text without crowding.
        flex: 3,
        child: NuvoPrimaryButton(
          leadingWidget: const Icon(
            Icons.camera_alt_outlined,
            color: NuvoColors.white,
          ),
          label: 'Submit proof',
          onPressed: onSubmit,
          expand: true,
          height: height,
          horizontalPadding: 16,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        flex: 2,
        // Labeled, not icon-only — a bare "+" glyph read as an unclear
        // secondary action with no text to anchor its meaning.
        child: NuvoOutlineButton(
          icon: Icons.add_rounded,
          label: 'New',
          onPressed: onStart,
          expand: true,
          height: height,
          horizontalPadding: 8,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        flex: 2,
        child: NuvoOutlineButton(
          icon: Icons.group_add_outlined,
          label: 'Join',
          onPressed: onJoin,
          expand: true,
          height: height,
          horizontalPadding: 8,
        ),
      ),
    ],
  );
}

/// Dark-mode surface of the Arena next-move hero: one step lighter than the
/// page/surface ladder (surface 0xFF14171D) so the card lifts off the page.
const Color _arenaHeroSurfaceDark = Color(0xFF262D37);

/// The hero card's surface — light mode unchanged (the shared surface).
@visibleForTesting
Color arenaHeroSurface(Brightness brightness, Color lightSurface) =>
    brightness == Brightness.dark ? _arenaHeroSurfaceDark : lightSurface;

/// The part of the scroll view's bottom edge covered by the floating dock.
/// Inside MainShell the Scaffold already reports dock + safe inset through
/// `padding.bottom`; if a host reports only the raw inset, add the dock.
double _dockReserve(MediaQueryData media) {
  final bottom = media.padding.bottom;
  return bottom >= 48 ? bottom : bottom + NuvoBottomNav.navDockHeight;
}

/// Entries of the active board, in rank order. When the real race is loaded
/// they come from serverRankedParticipants so the Arena shows the exact same
/// standings (people, order, scores) as the race page; otherwise the arena
/// snapshot's mini leaderboard.
List<_LbEntry> _leaderboardEntries({
  required ArenaBoard board,
  required Race? race,
  required String? currentUserId,
  required String initials,
  required String? photoUrl,
}) {
  final r = race;
  return [
    if (r != null && r.participants.isNotEmpty)
      for (final (i, p) in serverRankedParticipants(r).indexed)
        _LbEntry(
          rank: i + 1,
          name: p.userId == currentUserId ? 'You' : p.displayName,
          stat: raceProgressLabel(r, p),
          photoUrl: p.userId == currentUserId ? photoUrl : p.profilePhotoUrl,
          initials: p.userId == currentUserId ? initials : null,
          seed: p.userId,
          isMe: p.userId == currentUserId,
        )
    else
      for (final (i, row) in board.miniLeaderboard.indexed)
        _LbEntry(
          rank: i + 1,
          name: row.isCurrentUser ? 'You' : row.label,
          stat: row.value,
          photoUrl: row.isCurrentUser ? photoUrl : row.profilePhotoUrl,
          initials: row.isCurrentUser ? initials : null,
          seed: row.label,
          isMe: row.isCurrentUser,
        ),
  ];
}

String _ordinal(int n) {
  final mod100 = n % 100;
  if (mod100 >= 11 && mod100 <= 13) return '${n}th';
  return switch (n % 10) {
    1 => '${n}st',
    2 => '${n}nd',
    3 => '${n}rd',
    _ => '${n}th',
  };
}

/// Heights of the first-screen leaderboard peek (top 3 [+ pinned You] + the
/// unfold control). Feeds the hero budget, so the layout is guaranteed rather
/// than hoped for.
class _PeekMetrics {
  const _PeekMetrics({
    required this.rowHeight,
    required this.showLabel,
    required this.pinned,
    required this.hasControl,
    required this.height,
  });
  final double rowHeight;
  final bool showLabel;
  final bool pinned;
  final bool hasControl;
  final double height;

  static const double controlHeight = 32;

  factory _PeekMetrics.of(List<_LbEntry> entries, {required bool tight}) {
    final hasControl = entries.length >= 4;
    final pinned = entries.length > 3 && entries.skip(3).any((e) => e.isMe);
    if (entries.isEmpty) {
      return const _PeekMetrics(
        rowHeight: 0,
        showLabel: false,
        pinned: false,
        hasControl: false,
        height: 8 + 64.0 + 8,
      );
    }
    if (tight) {
      // Small phones: the top 3 sit side by side in one strip; the viewer's
      // own place (when outside the top 3) rides the control row.
      return _PeekMetrics(
        rowHeight: stripHeight,
        showLabel: false,
        pinned: pinned,
        hasControl: hasControl,
        height: 2 + stripHeight + 2 + (hasControl ? controlHeight : 0) + 6,
      );
    }
    const rowHeight = 36.0;
    final rows = math.min(entries.length, 3) + (pinned ? 1 : 0);
    return _PeekMetrics(
      rowHeight: rowHeight,
      showLabel: false,
      pinned: pinned,
      hasControl: hasControl,
      height: 8 + rows * rowHeight + 2 + (hasControl ? controlHeight : 0) + 8,
    );
  }

  static const double stripHeight = 48;
}

/// The first-screen leaderboard: top 3 (plus a pinned "You · 7th" row when the
/// viewer is further down), the unfold control, and the curtain that holds
/// rank 4+ and drops down from the seam under the control.
class _LeaderboardPeek extends StatelessWidget {
  const _LeaderboardPeek({
    required this.entries,
    required this.metrics,
    required this.tight,
    required this.unfolded,
    required this.t,
    required this.raw,
    required this.onToggle,
    required this.onFlingUp,
    required this.onFlingDown,
  });
  final List<_LbEntry> entries;
  final _PeekMetrics metrics;
  final bool tight;
  final bool unfolded;

  /// Eased curtain progress 0..1; [raw] is the linear controller value.
  final double t;
  final double raw;
  final VoidCallback onToggle;
  final VoidCallback onFlingUp;
  final VoidCallback onFlingDown;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final top = entries.take(3).toList();
    final rest = entries.length > 3 ? entries.sublist(3) : const <_LbEntry>[];
    _LbEntry? pinned;
    if (metrics.pinned) pinned = rest.firstWhere((e) => e.isMe);
    // While the curtain is dropping (or down) the pinned row is redundant —
    // the real row is in the curtain — so it folds away with it.
    final showPinned = pinned != null && raw == 0;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: NuvoSpacing.pageHorizontal,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (metrics.showLabel) ...[
            const _SectionLabel(title: 'Leaderboard'),
            const SizedBox(height: 6),
          ] else
            SizedBox(height: tight ? 2 : 8),
          if (entries.isEmpty)
            _OutlinedSheet(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  'Your crew will appear here as they join the start line.',
                  style: AppTextStyles.bodySmall.copyWith(color: c.inkSubtle),
                ),
              ),
            )
          else if (tight)
            _OutlinedSheet(
              child: Column(
                children: [
                  SizedBox(
                    height: _PeekMetrics.stripHeight,
                    child: Row(
                      children: [
                        for (var i = 0; i < top.length; i++) ...[
                          if (i > 0)
                            VerticalDivider(
                              width: 1,
                              thickness: 1,
                              color: c.divider,
                            ),
                          Expanded(child: _StripCell(entry: top[i])),
                        ],
                      ],
                    ),
                  ),
                  if (raw > 0 && rest.isNotEmpty)
                    _Curtain(rest: rest, t: t, raw: raw),
                ],
              ),
            )
          else
            _OutlinedSheet(
              child: Column(
                children: [
                  for (var i = 0; i < top.length; i++) ...[
                    _PeekRow(entry: top[i], height: metrics.rowHeight),
                    if (i < top.length - 1 || showPinned) _rowDivider(c),
                  ],
                  if (showPinned)
                    _PeekRow(
                      entry: pinned,
                      height: metrics.rowHeight,
                      pinnedLabel: 'You · ${_ordinal(pinned.rank)}',
                    ),
                  // The curtain: rank 4+ drops from the seam under the top 3,
                  // inside the same sheet so it reads as one folding card.
                  if (raw > 0 && rest.isNotEmpty)
                    _Curtain(rest: rest, t: t, raw: raw),
                ],
              ),
            ),
          if (metrics.hasControl)
            _UnfoldControl(
              pinnedLabel: tight && showPinned
                  ? 'You · ${_ordinal(pinned.rank)}'
                  : null,
              unfolded: unfolded,
              turns: t * 0.5,
              onToggle: onToggle,
              onFlingUp: onFlingUp,
              onFlingDown: onFlingDown,
            ),
        ],
      ),
    );
  }

  static Widget _rowDivider(NuvoThemeColors c) => Divider(
    height: 1,
    thickness: 1,
    color: c.divider,
    indent: 14,
    endIndent: 14,
  );
}

/// Rows 4+, revealed by a clip that grows from the seam (ClipRect +
/// Align.heightFactor), each row fading and sliding down a little with a
/// stagger, and a soft shadow riding the moving bottom edge.
class _Curtain extends StatelessWidget {
  const _Curtain({required this.rest, required this.t, required this.raw});
  final List<_LbEntry> rest;
  final double t;
  final double raw;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final moving = raw < 1;
    final rows = <Widget>[
      for (var i = 0; i < rest.length; i++)
        Builder(
          builder: (context) {
            // Stagger by position, capped so long lists still land together.
            final delay = math.min(i, 6) * 0.07;
            final local = ((raw - delay) / (1 - delay)).clamp(0.0, 1.0);
            final eased = Curves.easeOutCubic.transform(local);
            return Opacity(
              opacity: eased,
              child: Transform.translate(
                offset: Offset(0, -10 * (1 - eased)),
                child: Column(
                  children: [
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: c.divider,
                      indent: 14,
                      endIndent: 14,
                    ),
                    _StandingRow(entry: rest[i]),
                  ],
                ),
              ),
            );
          },
        ),
    ];
    return Stack(
      children: [
        ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: t,
            child: Column(children: rows),
          ),
        ),
        if (moving)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 14,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(
                        alpha: 0.16 * math.sin(math.pi * raw),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// "See full leaderboard" / "Show less": a button with an animated chevron.
/// Swiping up on it unfolds the curtain (down folds it back).
class _UnfoldControl extends StatelessWidget {
  const _UnfoldControl({
    this.pinnedLabel,
    required this.unfolded,
    required this.turns,
    required this.onToggle,
    required this.onFlingUp,
    required this.onFlingDown,
  });
  final String? pinnedLabel;
  final bool unfolded;
  final double turns;
  final VoidCallback onToggle;
  final VoidCallback onFlingUp;
  final VoidCallback onFlingDown;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final label = unfolded ? 'Show less' : 'See full leaderboard';
    return Semantics(
      button: true,
      expanded: unfolded,
      label: label,
      onTap: onToggle,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onToggle,
          onVerticalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v < -200) onFlingUp();
            if (v > 200) onFlingDown();
          },
          child: SizedBox(
            height: _PeekMetrics.controlHeight,
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (pinnedLabel != null) ...[
                    Text(
                      pinnedLabel!,
                      style: AppTextStyles.labelMedium.copyWith(
                        color: c.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(width: 1, height: 14, color: c.divider),
                    const SizedBox(width: 12),
                  ],
                  Text(
                    label,
                    style: AppTextStyles.labelMedium.copyWith(
                      color: c.accent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Transform.rotate(
                    angle: turns * 2 * math.pi,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 24,
                      color: c.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One of the top 3 in the small-phone strip: rank, avatar, name over stat.
class _StripCell extends StatelessWidget {
  const _StripCell({required this.entry});
  final _LbEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final me = entry.isMe;
    return Container(
      color: me ? c.panel : null,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Text(
            '${entry.rank}',
            style: AppTextStyles.labelMedium.copyWith(
              color: entry.rank == 1 ? c.accent : c.inkSubtle,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 5),
          NuvoAvatar(
            initials: entry.initials ?? _initials(entry.name),
            photoUrl: entry.photoUrl,
            size: 26,
            bgColor: nuvoAvatarColorFor(entry.seed),
            textColor: NuvoColors.white,
            borderColor: me ? _arenaBlue : c.border,
            borderWidth: me ? 2 : 1.5,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.titleMedium.copyWith(
                    fontSize: 12,
                    color: c.ink,
                  ),
                ),
                Text(
                  entry.stat,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.raceRowMeta.copyWith(
                    fontSize: 10.5,
                    color: me ? c.accent : c.inkSubtle,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact top-3 row.
class _PeekRow extends StatelessWidget {
  const _PeekRow({required this.entry, required this.height, this.pinnedLabel});
  final _LbEntry entry;
  final double height;
  final String? pinnedLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final me = entry.isMe;
    final avatar = height >= 44 ? 30.0 : 26.0;
    return Container(
      height: height,
      color: me ? c.panel : null,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              pinnedLabel != null ? '' : '${entry.rank}',
              style: AppTextStyles.labelMedium.copyWith(
                color: entry.rank == 1 ? c.accent : c.inkSubtle,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 4),
          NuvoAvatar(
            initials: entry.initials ?? _initials(entry.name),
            photoUrl: entry.photoUrl,
            size: avatar,
            bgColor: nuvoAvatarColorFor(entry.seed),
            textColor: NuvoColors.white,
            borderColor: me ? _arenaBlue : c.border,
            borderWidth: me ? 2 : 1.5,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              pinnedLabel ?? entry.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.titleMedium.copyWith(
                fontSize: 14,
                color: c.ink,
              ),
            ),
          ),
          Text(
            entry.stat,
            style: AppTextStyles.raceRowMeta.copyWith(
              color: me ? c.accent : c.inkSubtle,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _LbEntry {
  const _LbEntry({
    required this.rank,
    required this.name,
    required this.stat,
    required this.seed,
    required this.isMe,
    this.photoUrl,
    this.initials,
  });
  final int rank;
  final String name;
  final String stat;
  final String seed;
  final bool isMe;
  final String? photoUrl;
  final String? initials;
}

/// Outlined container whose child is clipped *inside* the 2 px ink edge, so the
/// border corners stay crisp (a plain `Container(border, clipBehavior)` clips
/// the outer half of the border at each corner).
class _OutlinedSheet extends StatelessWidget {
  const _OutlinedSheet({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.themeColors.surface,
        borderRadius: BorderRadius.circular(NuvoRadii.lg),
        border: Border.all(color: context.themeColors.border, width: 1.25),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(NuvoRadii.lg - 1),
        child: child,
      ),
    );
  }
}

class _StandingRow extends StatelessWidget {
  const _StandingRow({required this.entry});
  final _LbEntry entry;
  @override
  Widget build(BuildContext context) {
    final me = entry.isMe;
    return Container(
      color: me ? context.themeColors.panel : null,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '${entry.rank}',
              style: AppTextStyles.labelMedium.copyWith(
                color: context.themeColors.inkSubtle,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 4),
          NuvoAvatar(
            initials: entry.initials ?? _initials(entry.name),
            photoUrl: entry.photoUrl,
            size: 34,
            bgColor: nuvoAvatarColorFor(entry.seed),
            textColor: NuvoColors.white,
            borderColor: me ? _arenaBlue : context.themeColors.border,
            borderWidth: me ? 2 : 1.5,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              entry.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.titleMedium.copyWith(
                fontSize: 15,
                color: context.themeColors.ink,
              ),
            ),
          ),
          Text(
            entry.stat,
            style: AppTextStyles.raceRowMeta.copyWith(
              color: me
                  ? context.themeColors.accent
                  : context.themeColors.inkSubtle,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ArenaButton extends StatelessWidget {
  const _ArenaButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return NuvoSecondaryButton(
      label: label,
      icon: icon,
      expand: true,
      onPressed: onTap,
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 70),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            strokeWidth: 2,
            color: context.themeColors.accent,
          ),
          const SizedBox(height: 18),
          Text(
            'Loading your arena',
            style: AppTextStyles.bodySmall.copyWith(
              color: context.themeColors.inkSubtle,
            ),
          ),
        ],
      ),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: context.themeColors.inkSubtle,
            ),
          ),
          const SizedBox(height: 16),
          _ArenaButton(
            label: 'Retry',
            icon: Icons.refresh_rounded,
            onTap: onRetry,
          ),
        ],
      ),
    ),
  );
}

/// The zero-board state IS the first-run pitch — Arena owns the one guided
/// action ("create your first race"), with example finish lines as
/// inspiration prefills, not fake races.
class _FirstRunState extends StatelessWidget {
  const _FirstRunState({
    required this.onStart,
    required this.onIdea,
    required this.onJoin,
  });
  final VoidCallback onStart;
  final ValueChanged<String> onIdea;
  final VoidCallback onJoin;

  static const _ideas = [
    'First to 100 pushups',
    'Highest math grade',
    'First to finish 5 books',
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 32),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.panel,
              border: Border.all(color: c.ink, width: 2),
            ),
            child: Icon(Icons.flag_rounded, color: c.accent, size: 30),
          ),
          const SizedBox(height: 24),
          Text(
            'Ready for your first race?',
            style: AppTextStyles.headlineLarge.copyWith(color: c.ink),
          ),
          const SizedBox(height: 12),
          Text(
            'Pick something real.\nSet the finish line.\nBring someone in.',
            style: AppTextStyles.bodyLarge.copyWith(
              color: c.inkMuted,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 26),
          NuvoPrimaryButton(
            label: 'Create your first race',
            icon: Icons.flag_rounded,
            expand: true,
            onPressed: onStart,
          ),
          const SizedBox(height: 26),
          Text(
            'OR START FROM AN IDEA',
            style: AppTextStyles.labelUppercase(10.5, color: c.inkSubtle),
          ),
          const SizedBox(height: 10),
          for (final idea in _ideas) ...[
            _IdeaRow(label: idea, onTap: () => onIdea(idea)),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 8),
          Center(
            child: NuvoPressable(
              onTap: onJoin,
              haptic: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Text(
                  'Join with a code',
                  style: AppTextStyles.labelMedium.copyWith(
                    color: c.accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One tappable example finish line — inspiration that prefills the
/// composer, never a fake race on the board.
class _IdeaRow extends StatelessWidget {
  const _IdeaRow({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    return NuvoPressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(NuvoRadii.md),
          border: Border.all(color: c.border, width: 1.5),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: c.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(Icons.arrow_forward_rounded, size: 16, color: c.inkSubtle),
          ],
        ),
      ),
    );
  }
}

String _progressValue(String label, int fallback) {
  final match = RegExp(r'^(\d+)').firstMatch(label);
  return match?.group(1) ?? '$fallback';
}

String _progressSuffix(String label) {
  final match = RegExp(r'^\d+\s*(.*)$').firstMatch(label);
  final suffix = match?.group(1)?.trim() ?? '';
  return suffix.isEmpty ? '%' : suffix;
}

/// Worst-case rendered height of [_NextMoveHero] for [board] at
/// [textWidth] (the card's inner text width), in the composition the card
/// will actually render: [tall] matches the card's own
/// `heroHeight >= 300` switch.
double _heroContentHeight(
  ArenaBoard board,
  double textWidth,
  TextScaler scaler, {
  required bool tall,
  Race? race,
  String? viewerId,
}) {
  double measure(
    String text,
    TextStyle style, {
    int maxLines = 1,
    double? width,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: maxLines,
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout(maxWidth: width ?? textWidth);
    return painter.height;
  }

  final pct = (board.progressPercent ?? 0).clamp(0, 100);
  // The title shares its row with the rank ordinal — measure it against the
  // width it actually gets, or a just-fits one-liner measures as 1 line and
  // renders as 2, silently overflowing the card. The rank itself is a small
  // raised label; the title's two lines always exceed its height.
  final rankExtent = board.myRank == null
      ? 0.0
      : 10.0 +
            measure(
              raceOrdinal(board.myRank!),
              AppTextStyles.placementLabel(size: 15),
            );
  final title = measure(
    board.title,
    AppTextStyles.headlineMedium.copyWith(
      fontSize: tall ? 30 : 28,
      height: 1.05,
    ),
    maxLines: 2,
    width: textWidth - rankExtent,
  );
  final progress = measure(
    _progressValue(board.progressLabel, pct),
    AppTextStyles.displayMedium.copyWith(fontSize: tall ? 66 : 56, height: .85),
  );
  final suffix = measure(
    _progressSuffix(board.progressLabel),
    AppTextStyles.headlineMedium.copyWith(fontSize: 24),
  );
  // Mirror of the card's column: pads (top, title gap, progress gap,
  // racer-row pad, bottom pad) + lane + stakes + racer row + footer + the
  // carousel's 10px shadow pad + 4px card border inset (2px each side —
  // the border lays out inside the child's bounds). The hero's curved
  // course with its caption band is 60 tall.
  const laneHeight = 60.0;
  final hasStakes = board.chaseCopy != null && board.chaseCopy!.isNotEmpty;
  // Measured, not assumed — labelMedium's line-height multiplier makes the
  // stakes line ~19-20px at 13.5pt, and the racer row is the taller of the
  // 26px avatar stack and its label.
  final stakes = hasStakes
      ? 4.0 +
            measure(
              board.chaseCopy!,
              AppTextStyles.labelMedium.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
            )
      : 0.0;
  return (tall ? 12.0 : 10.0) +
      title +
      (tall ? 8.0 : 6.0) +
      math.max(progress, suffix) +
      (tall ? 8.0 : 4.0) +
      laneHeight +
      stakes +
      (tall ? 8.0 : 4.0) +
      (tall ? 54.0 : 50.0) +
      10 +
      4;
}

/// Podium color for the hero's rank numeral — gold on the win, ink
/// otherwise. Quiet like [RacePlacement], not a badge.
Color _arenaPlacement(int rank, NuvoThemeColors c) => switch (rank) {
  1 => NuvoColors.gold,
  2 => NuvoColors.position2,
  3 => NuvoColors.position3,
  _ => c.inkSubtle,
};

/// The hero's course data — the canonical fractions + captions that ride
/// the curved race path. With the authoritative [race] loaded, marks come
/// from the shared canonical geometry (goal lane vs relative-competition
/// lane for lower-wins/best-attempt). Without it, "v / t" leaderboard
/// values still give an honest goal course. Null → the path draws bare.
({
  double? viewerFraction,
  double? rivalFraction,
  String? viewerLabel,
  String? rivalLabel,
  String? goalLabel,
  bool hasGoal,
  bool leading,
})?
_heroLane(ArenaBoard board, Race? race, String? viewerId) {
  final leading = board.myRank == 1;
  if (race != null) {
    final geo = raceLaneGeometry(race, viewerId);
    final rival = raceNearestRival(race, viewerId);
    final rivalMark = rival == null
        ? null
        : geo.rivals.where((r) => r.racer.userId == rival.userId).firstOrNull;
    if (geo.viewer == null && rivalMark == null) return null;
    final me = viewerId == null ? null : race.participantFor(viewerId);
    return (
      viewerFraction: geo.viewer,
      rivalFraction: rivalMark?.fraction,
      viewerLabel: geo.viewer != null ? 'You ${me?.progressValue ?? 0}' : null,
      rivalLabel: rivalMark != null
          ? '${_firstOf(rival!.displayName)} ${rival.progressValue}'
          : null,
      goalLabel: geo.hasGoal
          ? 'Goal ${raceScoreLabel(race, race.targetValue!)}'
          : null,
      hasGoal: geo.hasGoal,
      leading: leading,
    );
  }

  // Fallback lane — parse the board's own "v / t" strings so demo and
  // unloaded boards still draw marks instead of an anonymous path.
  final targetMatch = RegExp(r'/\s*(\d+)').firstMatch(board.progressLabel);
  final target = targetMatch == null
      ? null
      : int.tryParse(targetMatch.group(1)!);
  if (target == null || target <= 0) return null;
  (String label, int value, bool isMe)? rivalRow;
  (String label, int value, bool isMe)? viewerRow;
  for (final row in board.miniLeaderboard) {
    final m = RegExp(r'^\s*(\d+)').firstMatch(row.value);
    if (m == null) continue;
    final parsed = (row.label, int.parse(m.group(1)!), row.isCurrentUser);
    if (parsed.$3) {
      viewerRow = parsed;
    } else if (rivalRow == null || parsed.$2 > rivalRow.$2) {
      rivalRow = parsed;
    }
  }
  if (viewerRow == null && rivalRow == null) return null;
  return (
    viewerFraction: viewerRow == null ? null : viewerRow.$2 / target,
    rivalFraction: rivalRow == null ? null : rivalRow.$2 / target,
    viewerLabel: viewerRow == null ? null : 'You ${viewerRow.$2}',
    rivalLabel: rivalRow == null ? null : '${rivalRow.$1} ${rivalRow.$2}',
    goalLabel: 'Goal $target',
    hasGoal: true,
    leading: leading,
  );
}

String _firstOf(String name) {
  final first = name.trim().split(RegExp(r'\s+')).firstOrNull ?? '';
  return first.isEmpty ? 'Rival' : first;
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  final trimmed = name.trim();
  return trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
}

ArenaSnapshot _previewSnapshot() => const ArenaSnapshot(
  mode: 'real',
  headerPulse: '3 racers are moving',
  focusBoard: ArenaBoard(
    id: 'preview-race',
    source: 'demo',
    title: 'First to 100 Pushups',
    proofLabel: 'AI Motion Proof',
    progressLabel: '65 / 100 reps',
    boardContext: 'Three racers are moving toward the finish line.',
    primaryActionLabel: 'Submit proof',
    primaryActionType: 'submit_proof',
    progressPercent: 65,
    racerCount: 3,
    isResult: false,
    myRank: 1,
    daysLeft: 4,
    chaseCopy: 'You lead Alex by 17 reps.',
    miniLeaderboard: [
      ArenaMiniLeaderboardRow(
        label: 'You',
        value: '65 / 100',
        isCurrentUser: true,
      ),
      ArenaMiniLeaderboardRow(label: 'Alex R.', value: '48 / 100'),
      ArenaMiniLeaderboardRow(label: 'Maya L.', value: '31 / 100'),
    ],
  ),
  activity: [
    ArenaActivity(
      id: 'preview-1',
      actorName: 'Maya L.',
      text: 'submitted 20 pushups',
      timeLabel: '2m ago',
      type: 'proof_submitted',
    ),
  ],
);

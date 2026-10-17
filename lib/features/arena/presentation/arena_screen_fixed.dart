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
import '../../../core/widgets/nuvo_podium.dart';
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

class _ArenaScreenState extends ConsumerState<ArenaScreen> {
  final PageController _boardsController = PageController(viewportFraction: 1);
  int _boardPage = 0;

  @override
  void dispose() {
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

    // First-composition budget. The first screen is the header plus the
    // next-move card and its actions — the standings begin BELOW the visible
    // area and appear only on scroll (see the first-screen block below, which
    // is given a min height equal to the visible viewport, so the fold is
    // guaranteed by layout, not by a magic number).
    //
    // heroHeight: the card's ceiling is whatever the usable viewport leaves
    // after the header, section label, dots, the action row and the scroll
    // cue. The fold is the dock's TOP EDGE. Height is density-tier driven,
    // never raw width: the card has exactly two legal compositions — compact
    // (~296px, smaller type/pads) and tall (>=324px). When even compact won't
    // fit the page scrolls; the card never renders shorter than its content.
    final media = MediaQuery.of(context);
    final dockReserve = _dockReserve(media);
    final dockTop = media.size.height - dockReserve;
    final usableViewport =
        dockTop - media.padding.top - 10; // breathing unit above the dock
    final heroBase = switch (usableViewport) {
      < 560 => 300.0, // compact phones
      < 800 => 340.0, // standard
      _ => 400.0, // large
    };
    // What the usable viewport already spent before the hero: the screen
    // header (~110), then in the list: top pad + label + hero gap + [dots] +
    // action gap + actions + the scroll cue.
    final fixedElsewhere =
        110.0 +
        6 +
        20 +
        8 +
        (boards.length > 1 ? 20 : 0) +
        8 +
        64 +
        _scrollCueHeight;
    final allowance = usableViewport - fixedElsewhere;
    // Content floor: the shared PageView slot must fit the WORST board in
    // the carousel — a two-line title is ~32px taller than a one-liner and
    // the slot can't grow per page. Measured with TextPainter at the
    // card's real text width so long race names never clip. The measurement
    // uses whichever composition (compact <300 / tall) the resulting slot
    // will actually render — two passes settle the mode flip.
    final cardTextWidth =
        media.size.width - NuvoSpacing.pageHorizontal * 2 - 12 - 40;
    var heroHeight = allowance >= 324 ? math.min(heroBase, allowance) : 296.0;
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
                // First screen: header + next-move card + actions, given a
                // min height equal to the visible viewport (scroll view
                // height minus the dock). The standings sliver below can
                // therefore never start inside the first viewport.
                SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final visibleHeight = math.max(
                      0.0,
                      constraints.viewportMainAxisExtent - dockReserve,
                    );
                    return SliverToBoxAdapter(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: visibleHeight),
                        child: Stack(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: _scrollCueHeight,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      22,
                                      18,
                                      22,
                                      0,
                                    ),
                                    child: _ArenaHeader(greeting: greeting),
                                  ),
                                  if (isOffline)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        22,
                                        14,
                                        22,
                                        0,
                                      ),
                                      child: NuvoOfflineBanner(
                                        onRetry: retryConnection,
                                      ),
                                    ),
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
                                        onPageChanged: (page) =>
                                            setState(() => _boardPage = page),
                                        padEnds: false,
                                        itemBuilder: (context, index) =>
                                            _BoardCarouselItem(
                                              controller: _boardsController,
                                              index: index,
                                              board: boards[index],
                                              race: raceById[boards[index].id],
                                              viewerId: user?.id,
                                              heroHeight: heroHeight,
                                              onOpen: () => _openBoard(
                                                context,
                                                boards[index],
                                              ),
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
                                  const SizedBox(height: 8),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: NuvoSpacing.pageHorizontal,
                                    ),
                                    child: _QuickActions(
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
                                ],
                              ),
                            ),
                            // Calm breathing room under the actions: a quiet
                            // cue that the standings live below the fold.
                            const Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              height: _scrollCueHeight,
                              child: _ScrollCue(),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    NuvoSpacing.pageHorizontal,
                    20,
                    NuvoSpacing.pageHorizontal,
                    NuvoBottomNav.bottomPadding(context),
                  ),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      KeyedSubtree(
                        key: ValueKey('board-sections-${activeBoard.id}'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _SectionLabel(title: 'Leaderboard'),
                            const SizedBox(height: 10),
                            _Standings(
                              board: activeBoard,
                              // Prefer the authoritative race so this shows the
                              // exact same standings as the race page.
                              race: raceById[activeBoard.id],
                              currentUserId: user?.id,
                              initials: user?.avatarInitials ?? '?',
                              photoUrl: user?.profilePhotoUrl,
                            ),
                          ],
                        ),
                      ),
                    ]),
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
                  // Participant context — a fixed gap below the track,
                  // never a stretch-to-fill blank area.
                  Padding(
                    padding: EdgeInsets.only(top: tall ? 6 : 8),
                    child: _RaceDetails(board: board),
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

class _RaceDetails extends StatelessWidget {
  const _RaceDetails({required this.board});
  final ArenaBoard board;

  @override
  Widget build(BuildContext context) {
    final avatars = board.miniLeaderboard
        .map(
          (row) =>
              (initials: _initials(row.label), photoUrl: row.profilePhotoUrl),
        )
        .toList();
    final total = board.racerCount ?? board.miniLeaderboard.length;

    return Row(
      children: [
        if (avatars.isNotEmpty) ...[
          NuvoAvatarStack(
            avatars: avatars,
            total: total,
            size: 26,
            max: 3,
            borderColor: arenaHeroSurface(
              Theme.of(context).brightness,
              context.themeColors.surface,
            ),
          ),
          const SizedBox(width: 9),
        ],
        Expanded(
          child: Text(
            // One clean participant line — the card already shows progress
            // ("0 / 6 reps") prominently, so this is just "N racers", not a
            // compound restatement of the same facts.
            total == 1 ? '1 racer' : '$total racers',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.labelSmall.copyWith(
              // inkMuted, not inkSubtle: keeps >= 4.5:1 on the lighter dark
              // hero surface.
              color: context.themeColors.inkMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
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
    required this.onSubmit,
    required this.onStart,
    required this.onJoin,
  });
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
          height: 64,
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
          height: 64,
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
          height: 64,
          horizontalPadding: 8,
        ),
      ),
    ],
  );
}

/// Height reserved at the bottom of the first screen for the quiet
/// "standings below" cue; part of the hero budget.
const double _scrollCueHeight = 36;

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
  return bottom >= NuvoBottomNav.navDockHeight
      ? bottom
      : bottom + NuvoBottomNav.navDockHeight;
}

class _ScrollCue extends StatelessWidget {
  const _ScrollCue();
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Center(
      child: Icon(
        Icons.keyboard_arrow_down_rounded,
        size: 26,
        color: context.themeColors.inkSubtle,
      ),
    ),
  );
}

class _Standings extends StatelessWidget {
  const _Standings({
    required this.board,
    required this.currentUserId,
    required this.initials,
    this.race,
    this.photoUrl,
  });
  final ArenaBoard board;
  final Race? race;
  final String? currentUserId;
  final String initials;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    // When the real race is loaded, build from serverRankedParticipants so the
    // Arena shows the *exact* same standings (people, order, scores) as the
    // race page. Fall back to the arena snapshot's mini leaderboard.
    final r = race;
    final entries = <_LbEntry>[
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

    if (entries.isEmpty) {
      return _OutlinedSheet(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          child: Text(
            'Your crew will appear here as they join the start line.',
            style: AppTextStyles.bodySmall.copyWith(
              color: context.themeColors.inkSubtle,
            ),
          ),
        ),
      );
    }

    // Small fields use the same podium composition as the race room — a
    // 1- or 2-person race still shows a podium (empty places simply don't
    // render), never the generic rows reserved for ranks 4+.
    final rest = entries.length > 3 ? entries.sublist(3) : const <_LbEntry>[];

    return NuvoPodium(
      top: [
        for (final e in entries.take(3))
          NuvoPodiumEntry(
            rank: e.rank,
            name: e.name,
            statLabel: e.stat,
            photoUrl: e.photoUrl,
            initials: e.initials,
            avatarSeedId: e.seed,
            isCurrentUser: e.isMe,
          ),
      ],
      // Rank 4+ is ordinary scroll content — the shorter card is what keeps
      // it below the first viewport now, not an artificial spacer here.
      rest: rest.isEmpty
          ? null
          : _OutlinedSheet(
              child: Column(
                children: [
                  for (var i = 0; i < rest.length; i++) ...[
                    _StandingRow(entry: rest[i]),
                    if (i < rest.length - 1)
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: context.themeColors.divider,
                        indent: 16,
                        endIndent: 16,
                      ),
                  ],
                ],
              ),
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
  final racerRow = math.max(
    26.0,
    measure(
      '${board.racerCount ?? board.miniLeaderboard.length} racers',
      AppTextStyles.labelSmall.copyWith(fontWeight: FontWeight.w600),
    ),
  );
  return (tall ? 12.0 : 10.0) +
      title +
      (tall ? 8.0 : 6.0) +
      math.max(progress, suffix) +
      (tall ? 8.0 : 4.0) +
      laneHeight +
      stakes +
      (tall ? 6.0 : 8.0) +
      racerRow +
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

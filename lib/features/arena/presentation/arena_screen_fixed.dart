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
import '../../../core/widgets/nuvo_empty_state.dart';
import '../../../core/widgets/nuvo_error_state.dart';
import '../../../core/widgets/nuvo_motion.dart';
import '../../../core/widgets/nuvo_podium.dart';
import '../../../core/widgets/nuvo_race_path.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../races/data/race_models.dart';
import '../../races/domain/camera_verification_resolver.dart';
import '../../races/domain/race_display.dart';
import '../../races/presentation/race_controller.dart';
import '../data/arena_models.dart';
import 'arena_controller.dart';

const _arenaBackground = NuvoColors.page;
const _arenaSurface = NuvoColors.surface;
const _arenaText = NuvoColors.navy;
const _arenaMuted = NuvoColors.textMuted;
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

    // First-composition budget — computed once, used twice:
    //   1. heroHeight: "Your Next Move" is the primary object, but the
    //      leaderboard below it owns real estate too. The card's ceiling is
    //      whatever the usable viewport leaves after the header, section
    //      labels, the action row, and the full standings unit. Budgeting
    //      against the standings — not a bare viewport fraction — keeps the
    //      whole board above the dock instead of its useful half.
    //   2. seamGap: the gap before "Recent activity" grows until that
    //      section starts at or below the dock's top edge — nothing from
    //      the next section peeks above the dock at rest.
    //
    // The fold is the dock's TOP EDGE, not bottomPadding (that's a scroll
    // clearance contract and can end inside the dock zone). Height is
    // density-tier driven, never raw width: two phones in the same tier
    // get the same card. The card has exactly two legal compositions —
    // compact (~296px, smaller type/pads) and tall (≥324px) — nothing in
    // between, or it clips its own content. When even compact won't fit
    // the page scrolls; the card never renders shorter than its content.
    final media = MediaQuery.of(context);
    final dockTop = media.size.height -
        NuvoBottomNav.navDockHeight -
        media.padding.bottom;
    final usableViewport =
        dockTop - media.padding.top - 10; // breathing unit above the dock
    final heroBase = switch (usableViewport) {
      < 560 => 300.0, // compact phones
      < 800 => 340.0, // standard
      _ => 400.0, // large
    };
    final standingsCount = activeBoard == null
        ? 0
        : _standingsCount(activeBoard, raceById[activeBoard.id]);
    // Standings extents as they actually render — the flat solo leader
    // state, two head-to-head rows, the flat podium. Measured extents,
    // not upper bounds: over-reserving starves the hero while the floor
    // forces it back.
    final leaderboardReserve = switch (standingsCount) {
      0 => 0.0,
      1 => 150.0, // flat leader state
      2 => 120.0, // two head-to-head rows
      _ => 140.0, // three-place podium
    };
    // What the usable viewport already spent before the hero: the screen
    // header (~110 — Arena + greeting sliver above the list), then in the
    // list: top pad + label + hero gap + [dots] + actions + section beat +
    // leaderboard label + its gap.
    final fixedElsewhere = 110.0 + 6 + 20 + 8 +
        (boards.length > 1 ? 20 : 0) +
        8 + 64 + 20 + 20 + 10;
    final allowance =
        usableViewport - fixedElsewhere - leaderboardReserve;
    // Content floor: the shared PageView slot must fit the WORST board in
    // the carousel — a two-line title is ~32px taller than a one-liner and
    // the slot can't grow per page. Measured with TextPainter at the
    // card's real text width so long race names never clip. When this
    // exceeds the standings allowance the hero wins — below-fold
    // standings scroll (occluded behind the dock, not painted through).
    // The measurement uses whichever composition (compact <300 / tall)
    // the resulting slot will actually render — two passes settle the
    // mode flip when compact content pushes the slot past 300.
    final cardTextWidth =
        media.size.width - NuvoSpacing.pageHorizontal * 2 - 12 - 40;
    var heroHeight =
        allowance >= 324 ? math.min(heroBase, allowance) : 296.0;
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
          ),
        );
      }
      if (need <= heroHeight) break;
      heroHeight = need;
    }
    // The seam uses LOWER-bound extents (a deliberately under-counted
    // header/labels/standings total) so the gap can only overshoot — the
    // next section always starts at or below the dock's top edge, never
    // peeking above it at rest. 30px is the normal section gap.
    final seamGap = math.max(
      30.0,
      (usableViewport + 10) -
          (240.0 + (boards.length > 1 ? 20 : 0)) -
          heroHeight -
          switch (standingsCount) {
            0 => 0.0,
            1 => 130.0,
            2 => 105.0,
            _ => 120.0,
          },
    );
    final greeting =
        user?.fullName?.trim().split(RegExp(r'\s+')).first ?? 'there';
    final loading =
        !widget.preview && ((arenaState?.loading ?? false) && snapshot == null);

    void retryConnection() =>
        ref.read(authControllerProvider.notifier).retryRestore();

    return Scaffold(
      backgroundColor: _arenaBackground,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: _arenaBlue,
          backgroundColor: _arenaSurface,
          onRefresh: widget.preview
              ? () async {}
              : () => ref.read(arenaControllerProvider.notifier).loadSnapshot(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
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
              else if (activeBoard == null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyState(
                    onStart: () => context.push('/races/new'),
                    onJoin: () => context.push('/races/join'),
                  ),
                )
              else
                SliverPadding(
                  // Compressed from NuvoSpacing.xxxl (32) — the first
                  // viewport needs to fit the full top-three leaderboard
                  // above the nav; see the tightened gaps below.
                  padding: EdgeInsets.fromLTRB(
                    NuvoSpacing.pageHorizontal,
                    6,
                    NuvoSpacing.pageHorizontal,
                    NuvoBottomNav.bottomPadding(context),
                  ),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _SectionLabel(
                        title: 'Your next move',
                        trailing: boards.length > 1
                            ? '${_boardPage + 1} / ${boards.length}'
                            : null,
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: heroHeight,
                        child: PageView.builder(
                          controller: _boardsController,
                          clipBehavior: Clip.hardEdge,
                          itemCount: boards.length,
                          onPageChanged: (page) =>
                              setState(() => _boardPage = page),
                          padEnds: false,
                          itemBuilder: (context, index) => _BoardCarouselItem(
                            controller: _boardsController,
                            index: index,
                            board: boards[index],
                            heroHeight: heroHeight,
                            onOpen: () => _openBoard(context, boards[index]),
                          ),
                        ),
                      ),
                      if (boards.length > 1) ...[
                        const SizedBox(height: 6),
                        _PageDots(count: boards.length, selected: _boardPage),
                      ],
                      const SizedBox(height: 8),
                      KeyedSubtree(
                        key: ValueKey('board-sections-${activeBoard.id}'),
                        child: Column(
                          children: [
                            _QuickActions(
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
                            // Moderate section beat — the leaderboard
                            // section owns real estate below the actions
                            // (20px floor: never glued to the buttons).
                            const SizedBox(height: 20),
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
                      SizedBox(height: seamGap),
                      _SectionLabel(
                        title: 'Recent activity',
                        trailing: snapshot!.activity.isEmpty
                            ? null
                            : 'View all',
                      ),
                      const SizedBox(height: 12),
                      _ActivityStream(items: snapshot.activity),
                    ]),
                  ),
                ),
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
    if (race != null) {
      debugLogCameraVerificationDecision(
        race,
        resolveCameraVerification(race),
        routeAction: 'arena_primary_action_${board.primaryActionType}',
      );
    }
    switch (board.primaryActionType) {
      case 'start_race':
        context.push('/races/new');
      // Both "submit proof" and "open board" land on the race page — the
      // leaderboard. Verifying is the pinned action there, so every race tap
      // in the app opens the same screen.
      default:
        context.push('/race/${board.id}');
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
          color: _arenaMuted,
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
      // pixel-budgeted (test/arena/arena_first_viewport_test.dart) and a
      // smaller label here pushes "Recent activity" back above the fold.
      Expanded(
        child: Text(
          title,
          style: AppTextStyles.titleMedium.copyWith(
            color: _arenaText,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      if (trailing != null)
        Text(
          trailing!,
          style: AppTextStyles.labelMedium.copyWith(color: _arenaBlue),
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
  });

  final PageController controller;
  final int index;
  final ArenaBoard board;
  final double heroHeight;
  final VoidCallback onOpen;

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
  });
  final ArenaBoard board;
  final double heroHeight;
  final VoidCallback onOpen;
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
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _arenaSurface,
        borderRadius: BorderRadius.circular(NuvoRadii.hero),
        border: Border.all(color: NuvoColors.navy, width: 2),
        boxShadow: AppShadows.hardLarge,
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(NuvoRadii.hero),
        border: Border.all(color: NuvoColors.navy, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, tall ? 18 : 12, 20, tall ? 14 : 4),
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
                      Text(
                        board.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.headlineMedium.copyWith(
                          color: _arenaText,
                          fontSize: tall ? 30 : 28,
                          height: 1.05,
                          letterSpacing: 0,
                        ),
                      ),
                      SizedBox(height: tall ? 10 : 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _progressValue(board.progressLabel, pct),
                            style: AppTextStyles.displayMedium.copyWith(
                              color: _arenaBlue,
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
                                  color: _arenaText,
                                  fontSize: 24,
                                  letterSpacing: 0,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: tall ? 14 : 6),
                      NuvoRacePath(
                        key: ValueKey('progress-${board.id}'),
                        raceId: board.id,
                        progress: pct / 100,
                      ),
                    ],
                  ),
                  // Participant context — a fixed gap below the track,
                  // never a stretch-to-fill blank area.
                  Padding(
                    padding: EdgeInsets.only(top: tall ? 8 : 10),
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
              height: tall ? 58 : 52,
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
            borderColor: NuvoColors.white,
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
              color: _arenaMuted,
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
              color: NuvoColors.navy,
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

/// How many racers the standings unit will present — decides how much of
/// the first viewport the leaderboard reserves for the hero budget.
int _standingsCount(ArenaBoard board, Race? race) {
  if (race != null && race.participants.isNotEmpty) {
    return race.participants.length;
  }
  return board.miniLeaderboard.length;
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
            style: AppTextStyles.bodySmall.copyWith(color: _arenaMuted),
          ),
        ),
      );
    }

    // One racer is a valid state — a designed leader panel, not a lonely
    // podium slot: rank, avatar, identity, score, and the board's own
    // context line ("Solo · add crew from the race room") as the pull.
    if (entries.length == 1) {
      return _SoloLeaderState(entry: entries.first, board: board);
    }

    // Two racers is a head-to-head — rows, not a three-slot podium with an
    // empty seat. Same row treatment as ranks 4+: rank, avatar, name, score,
    // the viewer's row carrying the blue surface.
    if (entries.length == 2) {
      return _OutlinedSheet(
        child: Column(
          children: [
            _StandingRow(entry: entries[0]),
            const Divider(
              height: 1,
              thickness: 1,
              color: NuvoColors.divider,
              indent: 16,
              endIndent: 16,
            ),
            _StandingRow(entry: entries[1]),
          ],
        ),
      );
    }

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
                      const Divider(
                        height: 1,
                        thickness: 1,
                        color: NuvoColors.divider,
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

/// The one-racer leaderboard: a deliberate leader state, not a lonely podium
/// slot and NOT a second card — the same flat treatment the podium uses
/// (badge, avatar, identity, score) so one racer reads as *leading* rather
/// than boxed in. The board's own context line — "Solo · add crew from the
/// race room" — reads as the pull, not a caveat. All real data.
class _SoloLeaderState extends StatelessWidget {
  const _SoloLeaderState({required this.entry, required this.board});
  final _LbEntry entry;
  final ArenaBoard board;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Placement badge — the same gold '1' the podium stamps on its
        // raised slot.
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: NuvoColors.gold,
            borderRadius: BorderRadius.circular(NuvoRadii.badge),
            border: Border.all(color: NuvoColors.navy, width: 1.5),
          ),
          child: Text(
            '${entry.rank}',
            style: AppTextStyles.labelSmall.copyWith(
              color: NuvoColors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 4),
        NuvoAvatar(
          initials: entry.initials ?? _initials(entry.name),
          photoUrl: entry.photoUrl,
          size: 52,
          bgColor: nuvoAvatarColorFor(entry.seed),
          textColor: NuvoColors.white,
          borderColor: entry.isMe ? _arenaBlue : NuvoColors.navy,
          borderWidth: 2.5,
        ),
        const SizedBox(height: 6),
        Text(
          entry.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.titleMedium.copyWith(
            color: _arenaText,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          entry.stat,
          style: AppTextStyles.raceRowMeta.copyWith(
            color: _arenaBlue,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (board.boardContext.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            board.boardContext,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodySmall.copyWith(color: _arenaMuted),
          ),
        ],
      ],
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
        color: _arenaSurface,
        borderRadius: BorderRadius.circular(NuvoRadii.lg),
        border: NuvoBorders.quiet,
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
      color: me ? NuvoColors.blueSurface : null,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '${entry.rank}',
              style: AppTextStyles.labelMedium.copyWith(
                color: _arenaMuted,
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
            borderColor: me ? _arenaBlue : NuvoColors.navy,
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
                color: _arenaText,
              ),
            ),
          ),
          Text(
            entry.stat,
            style: AppTextStyles.raceRowMeta.copyWith(
              color: me ? _arenaBlue : _arenaMuted,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityStream extends StatelessWidget {
  const _ActivityStream({required this.items});
  final List<ArenaActivity> items;
  @override
  Widget build(BuildContext context) => items.isEmpty
      ? Text(
          'No updates yet. Your crew activity will appear here.',
          style: AppTextStyles.bodySmall.copyWith(color: _arenaMuted),
        )
      : Column(
          children: [
            for (var i = 0; i < items.length && i < 4; i++)
              _ActivityRow(item: items[i]),
          ],
        );
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.item});
  final ArenaActivity item;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: const BoxDecoration(
            color: _arenaSurface,
            shape: BoxShape.circle,
          ),
          child: Icon(_activityIcon(item.type), color: _arenaGreen, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            item.text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodySmall.copyWith(color: _arenaText),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          item.timeLabel,
          style: AppTextStyles.labelSmall.copyWith(color: _arenaMuted),
        ),
      ],
    ),
  );
}

IconData _activityIcon(String type) => switch (type) {
  'joined' => Icons.group_add_outlined,
  'leader_changed' => Icons.trending_up_rounded,
  'finished' => Icons.flag_outlined,
  _ => Icons.check_circle_outline_rounded,
};

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
          const CircularProgressIndicator(strokeWidth: 2, color: _arenaBlue),
          const SizedBox(height: 18),
          Text(
            'Loading your arena',
            style: AppTextStyles.bodySmall.copyWith(color: _arenaMuted),
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
            style: AppTextStyles.bodyMedium.copyWith(color: _arenaMuted),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onStart, required this.onJoin});
  final VoidCallback onStart;
  final VoidCallback onJoin;
  @override
  Widget build(BuildContext context) => NuvoEmptyState(
    icon: Icons.flag_rounded,
    title: 'Nothing on the board yet',
    body: 'Create a race and pull in your crew — this is where your next move '
        'shows up once one is live.',
    ctaLabel: 'Create a race',
    onCta: onStart,
    secondaryLabel: 'Join with a code',
    onSecondary: onJoin,
    align: TextAlign.center,
  );
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
}) {
  double measure(String text, TextStyle style, {int maxLines = 1}) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: maxLines,
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout(maxWidth: textWidth);
    return painter.height;
  }

  final pct = (board.progressPercent ?? 0).clamp(0, 100);
  final title = measure(
    board.title,
    AppTextStyles.headlineMedium.copyWith(
      fontSize: tall ? 30 : 28,
      height: 1.05,
    ),
    maxLines: 2,
  );
  final progress = measure(
    _progressValue(board.progressLabel, pct),
    AppTextStyles.displayMedium.copyWith(
      fontSize: tall ? 66 : 56,
      height: .85,
    ),
  );
  final suffix = measure(
    _progressSuffix(board.progressLabel),
    AppTextStyles.headlineMedium.copyWith(fontSize: 24),
  );
  // Mirror of the card's column: pads (top, title gap, progress gap,
  // racer-row pad, bottom pad) + track + racer row + footer + the
  // carousel's 10px shadow pad + 4px card border inset (2px each side —
  // the border lays out inside the child's bounds).
  return (tall ? 18.0 : 12.0) +
      title +
      (tall ? 10.0 : 8.0) +
      math.max(progress, suffix) +
      (tall ? 14.0 : 6.0) +
      42 +
      (tall ? 8.0 : 10.0) +
      26 +
      (tall ? 14.0 : 4.0) +
      (tall ? 58.0 : 52.0) +
      10 +
      4;
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

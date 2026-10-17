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
import 'arena_podium.dart';
import 'arena_rest_board.dart';

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
  final ScrollController _scroll = ScrollController();
  int _boardPage = 0;
  bool _moreBelow = false;

  @override
  void dispose() {
    _boardsController.dispose();
    _scroll.dispose();
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

    // First-composition budget. The first screen is the header, the
    // next-move card, its actions and the top-3 podium — and it fits one
    // viewport: the podium is given whatever the hero leaves, down to a
    // readable floor. The fold is the floating nav's top edge, expressed
    // through NuvoBottomNav.bottomPadding (never a hard-coded dock height).
    //
    // The hero has three legal compositions by height: tall (>=324),
    // compact (~296) and micro (~205: no racer row / stakes, smaller type)
    // for short phones. When even micro + the podium floor can't fit, the
    // page scrolls; nothing renders shorter than its content.
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
        child: LayoutBuilder(
          builder: (context, viewport) {
            final viewportHeight = viewport.maxHeight;
            final media = MediaQuery.of(context);
            final bottomPad = NuvoBottomNav.bottomPadding(context);
            final podiumData = activeBoard == null
                ? null
                : _podiumFor(
                    activeBoard,
                    raceById[activeBoard.id],
                    user?.id,
                    user?.avatarInitials ?? '?',
                    user?.profilePhotoUrl,
                  );
            final hasPodium =
                podiumData != null && podiumData.entries.isNotEmpty;
            final podiumMin = hasPodium
                ? ArenaPodium.minHeight(media.textScaler, withChip: false)
                : 70.0;
            final hasRest = hasPodium && podiumData.rest.isNotEmpty;
            // With a rest list the first screen ends on the caret, which can
            // sit right above the nav — the usual clearance under the last
            // row isn't needed there, so the podium takes it.
            final avail =
                viewportHeight -
                bottomPad +
                (hasRest ? NuvoBottomNav.navScrollClearance + 6 : 0);
            final arrowH = hasRest ? ArenaRestArrow.height : 0.0;
            final dots = boards.length > 1 ? 20.0 : 0.0;
            double chromeFor(bool micro) =>
                (micro ? _microHeaderHeight : 120.0) +
                6 +
                (micro ? 0 : 28) +
                dots +
                arrowH +
                8 +
                (micro ? 56 : 64) +
                12;
            final usableViewport = avail - 10;
            final heroBase = switch (usableViewport + podiumMin) {
              < 640 => 300.0, // compact phones
              < 880 => 340.0, // standard
              _ => 400.0, // large
            };
            final cardTextWidth =
                media.size.width - NuvoSpacing.pageHorizontal * 2 - 12 - 40;
            // Pick the richest composition whose measured content fits the room the
            // podium floor leaves; micro is the last resort (the page then scrolls
            // only if even micro + the floor can't fit).
            var heroHeight = 190.0;
            for (final mode in _HeroMode.values.reversed) {
              var need = 0.0;
              for (final board in boards) {
                need = math.max(
                  need,
                  _heroContentHeight(
                    board,
                    cardTextWidth,
                    media.textScaler,
                    mode: mode,
                    race: raceById[board.id],
                    viewerId: user?.id,
                  ),
                );
              }
              final room =
                  avail - chromeFor(mode == _HeroMode.micro) - podiumMin;
              if (mode == _HeroMode.tall) {
                if (need <= room && math.min(heroBase, room) >= 300) {
                  heroHeight = math.max(need, math.min(heroBase, room));
                  break;
                }
              } else if (mode == _HeroMode.compact) {
                if (need <= room && need < 300) {
                  heroHeight = math.max(296.0, need);
                  break;
                }
              } else {
                heroHeight = math.max(190.0, need);
              }
            }
            final micro = _heroModeFor(heroHeight) == _HeroMode.micro;
            // The podium takes everything the hero leaves, down to the fold
            // (just the caret below it), so the first screen has no dead air.
            final podiumHeight = math.max(
              podiumMin,
              avail - chromeFor(micro) - heroHeight,
            );
            final scroller = RefreshIndicator(
              color: context.themeColors.accent,
              backgroundColor: context.themeColors.surface,
              onRefresh: widget.preview
                  ? () async {}
                  : () => ref
                        .read(arenaControllerProvider.notifier)
                        .loadSnapshot(),
              child: CustomScrollView(
                controller: _scroll,
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
                            child: _ArenaHeader(
                              greeting: greeting,
                              compact: micro,
                            ),
                          ),
                          if (isOffline)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
                              child: NuvoOfflineBanner(
                                onRetry: retryConnection,
                              ),
                            ),
                          const SizedBox(height: 6),
                          if (!micro) ...[
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
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: NuvoSpacing.pageHorizontal,
                            ),
                            child: _QuickActions(
                              compact: micro,
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
                          const SizedBox(height: 12),
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              NuvoSpacing.pageHorizontal,
                              0,
                              NuvoSpacing.pageHorizontal,
                              hasRest ? 0 : bottomPad,
                            ),
                            child: hasPodium
                                ? Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ArenaPodium(
                                        key: ValueKey(
                                          'arena-podium-${activeBoard.id}',
                                        ),
                                        entries: podiumData.entries,
                                        height: podiumHeight,
                                        onTap: () =>
                                            _openBoard(context, activeBoard),
                                      ),
                                      if (hasRest)
                                        ArenaRestArrow(
                                          onTap: () => _scroll.animateTo(
                                            math.min(
                                              _scroll.position.maxScrollExtent,
                                              _scroll.offset + avail * 0.6,
                                            ),
                                            duration: const Duration(
                                              milliseconds: 520,
                                            ),
                                            curve: Curves.easeOutCubic,
                                          ),
                                        ),
                                    ],
                                  )
                                : _EmptyPodium(),
                          ),
                        ],
                      ),
                    ),
                    if (hasRest)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            NuvoSpacing.pageHorizontal,
                            0,
                            NuvoSpacing.pageHorizontal,
                            // Room under the last row so it can finish fading in.
                            bottomPad +
                                ArenaRestList.tailRoom(media.textScaler),
                          ),
                          child: ArenaRestList(
                            entries: podiumData.rest,
                            foldInset: bottomPad,
                            onTap: () => _openBoard(context, activeBoard),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            );
            // When even the micro composition can't fit (very short phones),
            // the page scrolls: a soft fade ending at the nav's top edge keeps
            // anything passing under the nav from being sliced.
            return NotificationListener<ScrollMetricsNotification>(
              onNotification: (n) {
                final more =
                    n.metrics.axis == Axis.vertical &&
                    n.metrics.extentAfter > 0.5 &&
                    (!hasRest || n.metrics.pixels > 4);
                if (more != _moreBelow) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _moreBelow = more);
                  });
                }
                return false;
              },
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n.depth == 0 && n.metrics.axis == Axis.vertical) {
                    final more =
                        n.metrics.extentAfter > 0.5 &&
                        (!hasRest || n.metrics.pixels > 4);
                    if (more != _moreBelow) setState(() => _moreBelow = more);
                  }
                  return false;
                },
                child: Stack(
                  children: [
                    Positioned.fill(child: scroller),
                    if (_moreBelow)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: bottomPad,
                        height: 28,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            key: const ValueKey('nuvo-bottom-fade'),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  context.themeColors.page.withValues(alpha: 0),
                                  context.themeColors.page,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  ({
    List<ArenaPodiumEntry> entries,
    ArenaPodiumEntry? viewer,
    List<ArenaPodiumEntry> rest,
  })
  _podiumFor(
    ArenaBoard board,
    Race? race,
    String? viewerId,
    String initials,
    String? photoUrl,
  ) {
    // With the authoritative race loaded, rank from serverRankedParticipants
    // so the podium matches the race room exactly; otherwise fall back to
    // the snapshot's mini leaderboard.
    final all = <ArenaPodiumEntry>[];
    if (race != null && race.participants.isNotEmpty) {
      for (final (i, p) in serverRankedParticipants(race).indexed) {
        final me = p.userId == viewerId;
        all.add(
          ArenaPodiumEntry(
            rank: i + 1,
            name: me ? 'You' : _firstOf(p.displayName),
            score: '${p.progressValue}',
            photoUrl: me ? photoUrl : p.profilePhotoUrl,
            initials: me ? initials : null,
            seed: p.userId,
            isMe: me,
          ),
        );
      }
    } else {
      for (final (i, row) in board.miniLeaderboard.indexed) {
        all.add(
          ArenaPodiumEntry(
            rank: i + 1,
            name: row.isCurrentUser ? 'You' : _firstOf(row.label),
            score:
                RegExp(r'^\s*(\d+)').firstMatch(row.value)?.group(1) ??
                row.value,
            photoUrl: row.isCurrentUser ? photoUrl : row.profilePhotoUrl,
            initials: row.isCurrentUser ? initials : null,
            seed: row.label,
            isMe: row.isCurrentUser,
          ),
        );
      }
    }
    final top = all.take(3).toList();
    final outside = all.skip(3).where((e) => e.isMe).firstOrNull;
    return (entries: top, viewer: outside, rest: all.skip(3).toList());
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

/// Header heights the budget assumes (top pad included).
const double _microHeaderHeight = 56;

enum _HeroMode { micro, compact, tall }

_HeroMode _heroModeFor(double height) => height < 250
    ? _HeroMode.micro
    : (height >= 300 ? _HeroMode.tall : _HeroMode.compact);

class _EmptyPodium extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: context.themeColors.surface,
      borderRadius: BorderRadius.circular(NuvoRadii.lg),
      border: Border.all(color: context.themeColors.border, width: 1.25),
    ),
    child: Text(
      'Your friends will appear here as they join the start line.',
      style: AppTextStyles.bodySmall.copyWith(
        color: context.themeColors.inkSubtle,
      ),
    ),
  );
}

class _ArenaHeader extends StatelessWidget {
  const _ArenaHeader({required this.greeting, this.compact = false});
  final String greeting;

  /// Short phones: title and greeting share one row.
  final bool compact;

  static String _timeGreeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) => compact
      ? Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('Arena', style: AppTextStyles.screenTitle),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${_timeGreeting()}, $greeting',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.titleMedium.copyWith(
                  color: context.themeColors.inkSubtle,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        )
      : _full(context);

  Widget _full(BuildContext context) => Column(
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
    final mode = _heroModeFor(heroHeight);
    final tall = mode == _HeroMode.tall;
    final micro = mode == _HeroMode.micro;
    final progressFontSize = micro ? 40.0 : (tall ? 66.0 : 56.0);
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
                micro ? 8 : (tall ? 12 : 10),
                20,
                micro ? 4 : (tall ? 8 : 4),
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
                              maxLines: micro ? 1 : 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.headlineMedium.copyWith(
                                color: context.themeColors.ink,
                                fontSize: micro ? 24 : (tall ? 30 : 28),
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
                      SizedBox(height: micro ? 4 : (tall ? 8 : 6)),
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
                                  fontSize: micro ? 20 : 24,
                                  letterSpacing: 0,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: micro ? 4 : (tall ? 8 : 4)),
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
                      if (!micro &&
                          board.chaseCopy != null &&
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
                  if (!micro)
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
              height: micro ? 46 : (tall ? 54 : 50),
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
    this.compact = false,
  });
  final bool compact;
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
          height: compact ? 56 : 64,
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
          height: compact ? 56 : 64,
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
          height: compact ? 56 : 64,
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
  required _HeroMode mode,
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

  final tall = mode == _HeroMode.tall;
  final micro = mode == _HeroMode.micro;
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
      fontSize: micro ? 24 : (tall ? 30 : 28),
      height: 1.05,
    ),
    maxLines: micro ? 1 : 2,
    width: textWidth - rankExtent,
  );
  final progress = measure(
    _progressValue(board.progressLabel, pct),
    AppTextStyles.displayMedium.copyWith(
      fontSize: micro ? 40 : (tall ? 66 : 56),
      height: .85,
    ),
  );
  final suffix = measure(
    _progressSuffix(board.progressLabel),
    AppTextStyles.headlineMedium.copyWith(fontSize: micro ? 20 : 24),
  );
  // Mirror of the card's column: pads (top, title gap, progress gap,
  // racer-row pad, bottom pad) + lane + stakes + racer row + footer + the
  // carousel's 10px shadow pad + 4px card border inset (2px each side —
  // the border lays out inside the child's bounds). The hero's curved
  // course with its caption band is 60 tall.
  const laneHeight = 60.0;
  final hasStakes =
      !micro && board.chaseCopy != null && board.chaseCopy!.isNotEmpty;
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
  final racerRow = micro
      ? 0.0
      : math.max(
          26.0,
          measure(
            '${board.racerCount ?? board.miniLeaderboard.length} racers',
            AppTextStyles.labelSmall.copyWith(fontWeight: FontWeight.w600),
          ),
        );
  return (micro ? 8.0 : (tall ? 12.0 : 10.0)) +
      title +
      (micro ? 4.0 : (tall ? 8.0 : 6.0)) +
      math.max(progress, suffix) +
      (micro ? 4.0 : (tall ? 8.0 : 4.0)) +
      laneHeight +
      stakes +
      (micro ? 0.0 : (tall ? 6.0 : 8.0)) +
      racerRow +
      (micro ? 4.0 : (tall ? 8.0 : 4.0)) +
      (micro ? 46.0 : (tall ? 54.0 : 50.0)) +
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

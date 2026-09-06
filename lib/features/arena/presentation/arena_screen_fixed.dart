import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_geometry.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/nuvo_responsive.dart';
import '../../../core/widgets/bottom_nav.dart';
import '../../../core/widgets/nuvo_avatar.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_empty_state.dart';
import '../../../core/widgets/nuvo_podium.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../races/data/race_models.dart';
import '../../races/domain/camera_verification_resolver.dart';
import '../../races/domain/race_display.dart';
import '../../races/presentation/race_controller.dart';
import '../data/arena_models.dart';
import 'arena_controller.dart';

const _arenaBackground = NuvoColors.page;
const _arenaSurface = NuvoColors.surface;
const _arenaLine = NuvoColors.border;
const _arenaText = NuvoColors.navy;
const _arenaMuted = NuvoColors.textMuted;
const _arenaBlue = NuvoColors.blue;
const _arenaGreen = NuvoColors.success;

class ArenaScreen extends ConsumerStatefulWidget {
  const ArenaScreen({super.key, this.preview = false});

  final bool preview;

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
    final user = widget.preview ? null : ref.watch(authControllerProvider).user;
    final arenaState = widget.preview
        ? null
        : ref.watch(arenaControllerProvider);
    final raceState = widget.preview ? null : ref.watch(raceControllerProvider);
    final snapshot = widget.preview ? _previewSnapshot() : arenaState?.snapshot;
    final raceById = {
      for (final race in raceState?.races ?? const <Race>[]) race.id: race,
    };
    final boards = _boardsFor(snapshot);
    final activeBoard = boards.isEmpty
        ? null
        : boards[_boardPage.clamp(0, boards.length - 1)];
    final greeting =
        user?.fullName?.trim().split(RegExp(r'\s+')).first ?? 'there';
    final loading =
        !widget.preview && ((arenaState?.loading ?? false) && snapshot == null);

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
              if (loading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _LoadingState(),
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
                    16,
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
                      const SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          // Sized to the card's actual content (title ->
                          // "0 / 6 reps" -> progress line -> avatar+racer
                          // row -> footer — the chase-copy line is gone, see
                          // _NextMoveHero), not used as a page-composition
                          // spacer. A short margin over the 1-line-title
                          // minimum covers a 2-line title/OS text scaling;
                          // the hero Container's rounded-corner clip is the
                          // fallback for anything past that, same as before.
                          final heroHeight = constraints.maxWidth < 360
                              ? 258.0
                              : 250.0;
                          return SizedBox(
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
                                    isLast: index == boards.length - 1,
                                    onOpen: () =>
                                        _openBoard(context, boards[index]),
                                  ),
                            ),
                          );
                        },
                      ),
                      if (boards.length > 1) ...[
                        const SizedBox(height: 6),
                        _PageDots(count: boards.length, selected: _boardPage),
                      ],
                      const SizedBox(height: 14),
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
                            // Shorter card reclaims real room here — the
                            // leaderboard section gets to breathe instead of
                            // rank 4+ getting exposed to fill the space.
                            const SizedBox(height: 28),
                            const _SectionLabel(title: 'Leaderboard'),
                            const SizedBox(height: 16),
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
                      const SizedBox(height: 30),
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
        style: AppTextStyles.displayMedium.copyWith(
          color: _arenaText,
          fontSize: context.rs(44),
          height: .98,
          letterSpacing: 0,
        ),
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
      Expanded(
        child: Text(
          title.toUpperCase(),
          style: AppTextStyles.titleMedium.copyWith(
            color: _arenaText,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
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
    required this.isLast,
    required this.onOpen,
  });

  final PageController controller;
  final int index;
  final ArenaBoard board;
  final bool isLast;
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
              padding: EdgeInsets.only(
                right: isLast ? 0 : 12,
                bottom: 10,
              ),
              child: child,
            ),
          ),
        ),
      );
    },
    child: _NextMoveHero(board: board, onOpen: onOpen),
  );
}

class _NextMoveHero extends StatelessWidget {
  const _NextMoveHero({required this.board, required this.onOpen});
  final ArenaBoard board;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) {
    final pct = (board.progressPercent ?? 0).clamp(0, 100);
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
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              // Centered so the card's content reads as intentionally
              // balanced in the available height instead of top-aligned
              // with dead white space collecting below _RaceDetails.
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    board.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.headlineMedium.copyWith(
                      color: _arenaText,
                      fontSize: 28,
                      height: 1.05,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _progressValue(board.progressLabel, pct),
                        style: AppTextStyles.displayMedium.copyWith(
                          color: _arenaBlue,
                          fontSize: 58,
                          height: .85,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8),
                          // The racer count lived here too, duplicating
                          // _RaceDetails' avatar-cluster line below — removed
                          // rather than shown twice in the same card.
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
                  const SizedBox(height: 6),
                  _RaceProgressTrack(
                    key: ValueKey('progress-${board.id}'),
                    progress: pct / 100,
                  ),
                  // The chase-copy/board-context line is gone entirely — the
                  // card already states progress prominently ("0 / 6 reps")
                  // and _RaceDetails states the participant count once,
                  // below. A third restatement in prose added height without
                  // adding information.
                  const SizedBox(height: 10),
                  _RaceDetails(board: board),
                ],
              ),
            ),
          ),
          GestureDetector(
            onTap: onOpen,
            child: Container(
              // A real tappable footer, not squeezed — trimmed from 58 only
              // enough to stay a footer, not a control.
              height: 52,
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

class _RaceProgressTrack extends StatelessWidget {
  const _RaceProgressTrack({super.key, required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween<double>(begin: 0, end: progress),
    duration: const Duration(milliseconds: 700),
    curve: Curves.easeOutCubic,
    builder: (context, animatedProgress, child) => SizedBox(
      // Left at 42 — the flag-pole artwork in _RaceProgressPainter uses
      // absolute pixel offsets (not size-relative), so shrinking this
      // risks clipping it. The gap/padding trims above and heroHeight
      // reduction below carry the height savings instead.
      height: 42,
      child: CustomPaint(
        painter: _RaceProgressPainter(progress: animatedProgress),
        child: child,
      ),
    ),
    child: const SizedBox.expand(),
  );
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

class _RaceProgressPainter extends CustomPainter {
  const _RaceProgressPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final start = Offset(14, size.height / 2);
    final finish = Offset(size.width - 36, size.height / 2);
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..quadraticBezierTo(
        size.width * .52,
        size.height * .38,
        finish.dx,
        finish.dy,
      );
    final track = Paint()
      ..color = NuvoColors.navy
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, track);
    final metric = path.computeMetrics().first;
    if (progress > 0 && metric.length > 0) {
      final progressPaint = Paint()
        ..color = NuvoColors.blue
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawPath(
        metric.extractPath(0, metric.length * progress.clamp(0, 1)),
        progressPaint,
      );
    }
    final marker = Paint()
      ..color = NuvoColors.blue
      ..style = PaintingStyle.fill;
    final markerRadius = progress <= 0 ? 7.0 : 10.0;
    canvas.drawCircle(start, markerRadius, marker);
    final flagPaint = Paint()..color = _arenaText;
    final flagX = finish.dx + 12;
    canvas.drawRect(
      Rect.fromLTWH(flagX, 5, 2, 28),
      Paint()..color = _arenaLine,
    );
    canvas.drawPath(
      Path()
        ..moveTo(flagX + 2, 5)
        ..lineTo(size.width - 3, 10)
        ..lineTo(flagX + 2, 16)
        ..close(),
      flagPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RaceProgressPainter oldDelegate) =>
      oldDelegate.progress != progress;
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
        flex: 4,
        child: NuvoPrimaryButton(
          leadingWidget: const Icon(
            Icons.camera_alt_outlined,
            color: NuvoColors.white,
          ),
          label: 'Submit proof',
          onPressed: onSubmit,
          expand: true,
          height: 64,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        flex: 2,
        child: NuvoOutlineButton(
          icon: Icons.add_rounded,
          label: 'New race',
          iconOnly: true,
          onPressed: onStart,
          expand: true,
          height: 64,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        flex: 2,
        child: NuvoOutlineButton(
          icon: Icons.group_add_outlined,
          label: 'Join',
          iconOnly: true,
          onPressed: onJoin,
          expand: true,
          height: 64,
        ),
      ),
    ],
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
            style: AppTextStyles.bodySmall.copyWith(color: _arenaMuted),
          ),
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
        border: Border.all(color: NuvoColors.navy, width: 2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(NuvoRadii.lg - 2),
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

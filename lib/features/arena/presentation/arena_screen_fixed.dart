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
import '../../auth/presentation/auth_controller.dart';
import '../../races/data/race_models.dart';
import '../../races/domain/camera_verification_resolver.dart';
import '../../races/presentation/race_controller.dart';
import '../data/arena_models.dart';
import 'arena_controller.dart';

const _arenaBackground = NuvoColors.page;
const _arenaSurface = NuvoColors.surface;
const _arenaSurfaceRaised = NuvoColors.panelLight;
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
                  padding: EdgeInsets.fromLTRB(
                    NuvoSpacing.pageHorizontal,
                    NuvoSpacing.xxxl,
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
                          final heroHeight = constraints.maxWidth < 360
                              ? 344.0
                              : 336.0;
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
                        const SizedBox(height: 12),
                        _PageDots(count: boards.length, selected: _boardPage),
                      ],
                      const SizedBox(height: 28),
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
                            const SizedBox(height: 30),
                            const _SectionLabel(title: 'Leaderboard'),
                            const SizedBox(height: 12),
                            _Standings(
                              board: activeBoard,
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
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                  const SizedBox(height: 12),
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _progressSuffix(board.progressLabel),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.headlineMedium.copyWith(
                                  color: _arenaText,
                                  fontSize: 24,
                                  letterSpacing: 0,
                                ),
                              ),
                              Text(
                                '${board.racerCount ?? 1} racing',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: _arenaMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _RaceProgressTrack(
                    key: ValueKey('progress-${board.id}'),
                    progress: pct / 100,
                  ),
                  const SizedBox(height: 8),
                  // Flexible so the hero absorbs a two-line chase line, a long
                  // title, or a larger OS text size by shrinking here instead
                  // of overflowing the fixed hero height.
                  Flexible(
                    child: Text(
                      board.chaseCopy ?? board.boardContext,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: _arenaMuted,
                        height: 1.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _RaceDetails(board: board),
                ],
              ),
            ),
          ),
          GestureDetector(
            onTap: onOpen,
            child: Container(
              height: 58,
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
    final detail = board.daysLeft != null
        ? '${board.daysLeft} days to finish'
        : board.proofLabel ?? 'Keep moving toward the finish line';

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
            total > 0 ? '$total on the board · $detail' : detail,
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
          small: false,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        flex: 2,
        child: NuvoOutlineButton(
          icon: Icons.add_rounded,
          label: '',
          iconOnly: true,
          onPressed: onStart,
          expand: true,
          small: false,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        flex: 2,
        child: NuvoOutlineButton(
          icon: Icons.group_add_outlined,
          label: '',
          iconOnly: true,
          onPressed: onJoin,
          expand: true,
          small: false,
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
    this.photoUrl,
  });
  final ArenaBoard board;
  final String? currentUserId;
  final String initials;
  final String? photoUrl;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: _arenaSurface,
      borderRadius: BorderRadius.circular(NuvoRadii.lg),
      border: Border.all(color: NuvoColors.navy, width: 2),
    ),
    clipBehavior: Clip.antiAlias,
    child: board.miniLeaderboard.isEmpty
        ? Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            child: Text(
              'Your crew will appear here as they join the start line.',
              style: AppTextStyles.bodySmall.copyWith(color: _arenaMuted),
            ),
          )
        : Column(
            children: [
              for (var i = 0; i < board.miniLeaderboard.length; i++) ...[
                _StandingRow(
                  row: board.miniLeaderboard[i],
                  rank: i + 1,
                  initials: board.miniLeaderboard[i].isCurrentUser
                      ? initials
                      : null,
                  photoUrl: board.miniLeaderboard[i].isCurrentUser
                      ? photoUrl
                      : null,
                ),
                if (i < board.miniLeaderboard.length - 1)
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
  );
}

class _StandingRow extends StatelessWidget {
  const _StandingRow({
    required this.row,
    required this.rank,
    this.initials,
    this.photoUrl,
  });
  final ArenaMiniLeaderboardRow row;
  final int rank;
  final String? initials;
  final String? photoUrl;
  @override
  Widget build(BuildContext context) {
    final me = row.isCurrentUser;
    return Container(
      color: me ? NuvoColors.blueSurface : null,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '$rank',
              style: AppTextStyles.labelMedium.copyWith(
                color: _arenaMuted,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 4),
          NuvoAvatar(
            initials: initials ?? _initials(row.label),
            photoUrl: photoUrl ?? row.profilePhotoUrl,
            size: 34,
            bgColor: _arenaSurfaceRaised,
            textColor: _arenaText,
            borderColor: me ? _arenaBlue : NuvoColors.navy,
            borderWidth: me ? 2 : 1.5,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              me ? 'You' : row.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.titleMedium.copyWith(
                fontSize: 15,
                color: _arenaText,
              ),
            ),
          ),
          Text(
            row.value,
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
    this.filled = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;
  @override
  Widget build(BuildContext context) {
    if (filled) {
      return NuvoPrimaryButton(
        label: label,
        icon: icon,
        expand: true,
        onPressed: onTap,
      );
    }
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
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 30, 24, 120),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'A clear start line.',
            style: AppTextStyles.headlineMedium.copyWith(color: _arenaText),
          ),
          const SizedBox(height: 8),
          Text(
            'Start a race or join your crew to put something on the board.',
            style: AppTextStyles.bodyMedium.copyWith(color: _arenaMuted),
          ),
          const SizedBox(height: 22),
          _ArenaButton(
            label: 'Start a race',
            icon: Icons.arrow_forward_rounded,
            onTap: onStart,
            filled: true,
          ),
          const SizedBox(height: 10),
          _ArenaButton(
            label: 'Join with code',
            icon: Icons.login_rounded,
            onTap: onJoin,
          ),
        ],
      ),
    ),
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

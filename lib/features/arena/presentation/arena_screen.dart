import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_avatar.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_shared_components.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../races/data/race_models.dart';
import '../../races/domain/chase_context.dart';
import '../../races/presentation/race_controller.dart';
import '../data/arena_models.dart';
import 'arena_controller.dart';

const _kResultStatuses = {
  'completed',
  'complete',
  'finished',
  'archived',
  'cancelled',
};

const _kBlack = Color(0xFF02050B);
const _kCard = Color(0xFF08172F);
const _kCardBorder = Color(0x20FFFFFF);
const _kBlueBorder = Color(0x99075BFF);
const _kDivider = Color(0x12FFFFFF);
const _kSkel = Color(0x22FFFFFF);
const _kSub = Color(0xB3FFFFFF);
const _kMuted = Color(0x66FFFFFF);

class ArenaScreen extends ConsumerStatefulWidget {
  const ArenaScreen({super.key});

  @override
  ConsumerState<ArenaScreen> createState() => _ArenaScreenState();
}

class _ArenaScreenState extends ConsumerState<ArenaScreen> {
  String? _selectedBoardId;
  ArenaBoard? _scoreCenterBoard;
  bool _isLoadingBoardDetail = false;

  @override
  void initState() {
    super.initState();
    _selectedBoardId = ref
        .read(arenaControllerProvider)
        .snapshot
        ?.focusBoard
        ?.id;
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final arenaState = ref.watch(arenaControllerProvider);
    final snapshot = arenaState.snapshot;

    ref.listen<ArenaState>(arenaControllerProvider, (prev, next) {
      if (next.snapshot != null && next.snapshot != prev?.snapshot) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _selectedBoardId = next.snapshot!.focusBoard?.id;
            _scoreCenterBoard = null;
            _isLoadingBoardDetail = false;
          });
        });
      }
    });

    final firstName = user?.fullName?.split(' ').first ?? 'there';
    final initials = user?.avatarInitials ?? '?';

    final allBoards = snapshot == null
        ? <ArenaBoard>[]
        : <ArenaBoard>[
            if (snapshot.focusBoard != null) snapshot.focusBoard!,
            ...snapshot.liveBoards,
            ...snapshot.results,
          ];

    final resolvedId = _selectedBoardId ?? snapshot?.focusBoard?.id;
    final activeBoard = _scoreCenterBoard ?? snapshot?.focusBoard;
    final otherBoards = allBoards.where((b) => b.id != resolvedId).toList();

    return Scaffold(
      backgroundColor: _kBlack,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: NuvoColors.blue,
          backgroundColor: _kCard,
          onRefresh: () =>
              ref.read(arenaControllerProvider.notifier).loadSnapshot(),
          child: CustomScrollView(
            slivers: [
              // ── Header ─────────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ARENA',
                              style: AppTextStyles.brandLabel.copyWith(
                                color: NuvoColors.blue2,
                                letterSpacing: 0,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              firstName,
                              style: AppTextStyles.displayMedium.copyWith(
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PressableScale(
                        onTap: () => _showNotificationsSheet(context),
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.07),
                            shape: BoxShape.circle,
                            border: Border.all(color: _kCardBorder, width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                color: NuvoColors.blue.withValues(alpha: 0.22),
                                blurRadius: 22,
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            initials,
                            style: AppTextStyles.labelMedium.copyWith(
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Content ────────────────────────────────────────────────────
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 26, 20, 120),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    if (arenaState.loading && snapshot == null)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: NuvoColors.blue,
                          ),
                        ),
                      )
                    else if (arenaState.error != null && snapshot == null)
                      _ErrorState(
                        message: arenaState.error!,
                        onRetry: () => ref
                            .read(arenaControllerProvider.notifier)
                            .loadSnapshot(),
                      )
                    else if (snapshot == null || snapshot.isEmpty)
                      _EmptyState(
                        onStart: () => context.push('/races/new'),
                        onJoin: () => context.push('/races/join'),
                      )
                    else ...[
                      // ── Focus board ─────────────────────────────────────────
                      if (activeBoard != null)
                        _FocusBoardCard(
                          board: activeBoard,
                          isLoading: _isLoadingBoardDetail,
                          onLogMove: () =>
                              _handlePrimaryAction(context, activeBoard),
                          onOpen: () => _openBoard(context, activeBoard),
                        ),

                      // ── Race chips ──────────────────────────────────────────
                      if (allBoards.length > 1) ...[
                        const SizedBox(height: 20),
                        _RaceChipRow(
                          boards: allBoards,
                          selectedId: resolvedId,
                          onTap: (b) => _onChipTap(b, snapshot, user?.id),
                        ),
                      ],

                      // ── Other races ─────────────────────────────────────────
                      if (otherBoards.isNotEmpty) ...[
                        const SizedBox(height: 28),
                        Text(
                          'OTHER RACES',
                          style: AppTextStyles.brandLabel.copyWith(
                            color: _kMuted,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 10),
                        for (final b in otherBoards) ...[
                          _CompactBoardRow(
                            board: b,
                            onTap: () => _onChipTap(b, snapshot, user?.id),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ],
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onChipTap(
    ArenaBoard board,
    ArenaSnapshot snapshot,
    String? userId,
  ) async {
    final resolvedId = _selectedBoardId ?? snapshot.focusBoard?.id;
    if (board.id == resolvedId) return;

    if (board.id == snapshot.focusBoard?.id) {
      setState(() {
        _selectedBoardId = board.id;
        _scoreCenterBoard = null;
        _isLoadingBoardDetail = false;
      });
      return;
    }

    setState(() {
      _selectedBoardId = board.id;
      _scoreCenterBoard = board;
      _isLoadingBoardDetail = true;
    });

    try {
      final race = await ref
          .read(raceControllerProvider.notifier)
          .getRaceDetail(board.id);
      if (!mounted) return;
      setState(() {
        _scoreCenterBoard = _boardFromRace(race, userId);
        _isLoadingBoardDetail = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingBoardDetail = false);
    }
  }

  ArenaBoard _boardFromRace(Race race, String? userId) {
    final sorted = [...race.participants]
      ..sort((a, b) => b.progressPercent.compareTo(a.progressPercent));
    final miniLeaderboard = sorted.take(5).map((p) {
      final isUser = userId != null && p.userId == userId;
      final valueStr = race.targetValue != null
          ? '${p.progressValue} / ${race.targetValue}'
          : '${p.progressPercent}%';
      return ArenaMiniLeaderboardRow(
        label: isUser ? 'You' : p.displayName,
        value: valueStr,
        isCurrentUser: isUser,
        profilePhotoUrl: p.profilePhotoUrl,
      );
    }).toList();

    final myPart = userId != null ? race.participantFor(userId) : null;
    final myProgress = myPart?.progressPercent ?? 0;
    final isResult =
        _kResultStatuses.contains(race.status) || myProgress >= 100;
    final count = race.participantCount;
    final boardContext = isResult
        ? '$count ${count == 1 ? 'racer' : 'racers'} finished'
        : count <= 1
        ? 'Solo · add crew from the race room'
        : '$count ${count == 1 ? 'racer' : 'racers'} on the board';

    final chase = ChaseContext.compute(race, userId ?? '');

    return ArenaBoard(
      id: race.id,
      source: 'real',
      title: race.title,
      proofLabel: race.isAiMotionRace ? 'AI MoveCheck' : 'Manual logging',
      progressLabel: myPart != null
          ? (race.targetValue != null
                ? 'You ${myPart.progressValue} / ${race.targetValue}'
                : 'You $myProgress%')
          : '',
      boardContext: boardContext,
      primaryActionLabel: isResult ? 'Open board' : 'Log move',
      primaryActionType: isResult ? 'open_board' : 'submit_proof',
      progressPercent: myProgress,
      racerCount: count,
      isResult: isResult,
      badgeLabel: race.isAiMotionRace ? 'AI' : null,
      miniLeaderboard: miniLeaderboard,
      myRank: chase.myRank,
      chaseCopy: chase.chaseCopy,
      leaderName: chase.leaderName,
      leaderPhotoUrl: chase.leaderPhotoUrl,
      daysLeft: chase.daysLeft,
    );
  }

  void _openBoard(BuildContext context, ArenaBoard board) {
    if (board.isDemo) {
      _demoSnack(context);
      return;
    }
    context.push('/race/${board.id}');
  }

  void _handlePrimaryAction(BuildContext context, ArenaBoard board) {
    if (board.isDemo) {
      _demoSnack(context);
      return;
    }
    switch (board.primaryActionType) {
      case 'submit_proof':
        context.push('/race/${board.id}/proof');
      case 'start_race':
        context.push('/races/new');
      default:
        context.push('/race/${board.id}');
    }
  }

  void _demoSnack(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Demo board preview'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

// ── Focus board card ──────────────────────────────────────────────────────────

class _FocusBoardCard extends StatelessWidget {
  const _FocusBoardCard({
    required this.board,
    required this.isLoading,
    required this.onLogMove,
    required this.onOpen,
  });

  final ArenaBoard board;
  final bool isLoading;
  final VoidCallback onLogMove;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final isResult = board.isResult;
    final pct = board.progressPercent ?? 0;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF102A58), _kCard, _kBlack],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _kBlueBorder),
        boxShadow: [
          BoxShadow(
            color: NuvoColors.blue.withValues(alpha: 0.26),
            blurRadius: 34,
            offset: const Offset(0, 14),
          ),
          const BoxShadow(
            color: Color(0x90000000),
            blurRadius: 28,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Loading bar
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: isLoading ? 2 : 0,
            width: double.infinity,
            margin: EdgeInsets.only(bottom: isLoading ? 16 : 0),
            decoration: BoxDecoration(
              color: NuvoColors.blue,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Title + badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  board.title,
                  style: AppTextStyles.headlineMedium.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (board.badgeLabel != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: NuvoColors.blue,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    board.badgeLabel!,
                    style: AppTextStyles.labelSmall.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 6),
          Text(
            board.boardContext,
            style: AppTextStyles.bodySmall.copyWith(color: _kSub, height: 1.35),
          ),

          // Crew strip
          const SizedBox(height: 16),
          Row(
            children: [
              if (board.miniLeaderboard.isNotEmpty)
                NuvoAvatarStack(
                  avatars: board.miniLeaderboard
                      .map(
                        (r) => (initials: r.label, photoUrl: r.profilePhotoUrl),
                      )
                      .toList(),
                  total: board.racerCount ?? board.miniLeaderboard.length,
                  size: 24,
                  max: 4,
                  borderColor: _kCard,
                ),
              const Spacer(),
              if (board.daysLeft != null)
                Text(
                  '${board.daysLeft}d left',
                  style: AppTextStyles.labelSmall.copyWith(color: _kMuted),
                ),
            ],
          ),

          // Rank + chase
          if (board.myRank != null && !isResult) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _kBlueBorder.withValues(alpha: 0.55)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '#${board.myRank}',
                        style: AppTextStyles.displaySmall.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'of ${board.racerCount ?? 1}',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: _kMuted,
                        ),
                      ),
                    ],
                  ),
                  if (board.chaseCopy != null) ...[
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        board.chaseCopy!,
                        style: AppTextStyles.bodySmall.copyWith(color: _kSub),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],

          const SizedBox(height: 18),

          // Progress number + lane
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$pct',
                style: AppTextStyles.displaySmall.copyWith(
                  color: isResult ? NuvoColors.success : Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 5, left: 3),
                child: Text(
                  '%',
                  style: AppTextStyles.titleLarge.copyWith(color: _kMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          NuvoRaceLane(progressPercent: pct, onDark: true),

          // Mini leaderboard
          if (isLoading || board.miniLeaderboard.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(height: 1, color: _kDivider),
            const SizedBox(height: 14),
            if (isLoading)
              ..._buildSkeletonRows()
            else
              for (var i = 0; i < board.miniLeaderboard.length; i++) ...[
                _DarkMiniRow(
                  rank: i + 1,
                  label: board.miniLeaderboard[i].label,
                  value: board.miniLeaderboard[i].value,
                  isCurrentUser: board.miniLeaderboard[i].isCurrentUser,
                  photoUrl: board.miniLeaderboard[i].profilePhotoUrl,
                ),
                if (i < board.miniLeaderboard.length - 1)
                  const SizedBox(height: 10),
              ],
          ],

          const SizedBox(height: 22),

          // CTA
          isResult
              ? _DarkOutlineButton(
                  label: 'Open board',
                  icon: Icons.arrow_forward_rounded,
                  onTap: onOpen,
                )
              : NuvoBlueButton(
                  label: 'Log move',
                  expand: true,
                  onPressed: onLogMove,
                ),
        ],
      ),
    );
  }

  static List<Widget> _buildSkeletonRows() {
    return [
      for (var i = 0; i < 3; i++) ...[
        const Row(
          children: [
            _Skel(width: 26, height: 26, radius: 13),
            SizedBox(width: 8),
            _Skel(width: 26, height: 26, radius: 13),
            SizedBox(width: 10),
            _Skel(width: 80, height: 12, radius: 4),
            Spacer(),
            _Skel(width: 40, height: 12, radius: 4),
          ],
        ),
        if (i < 2) const SizedBox(height: 10),
      ],
    ];
  }
}

// ── Dark mini leaderboard row ─────────────────────────────────────────────────

class _DarkMiniRow extends StatelessWidget {
  const _DarkMiniRow({
    required this.rank,
    required this.label,
    required this.value,
    required this.isCurrentUser,
    this.photoUrl,
  });

  final int rank;
  final String label;
  final String value;
  final bool isCurrentUser;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final accent = isCurrentUser ? NuvoColors.blue : Colors.white;
    final rankBg = isCurrentUser
        ? NuvoColors.blue.withValues(alpha: 0.18)
        : Colors.white.withValues(alpha: 0.08);
    final avatarBg = isCurrentUser
        ? NuvoColors.blue.withValues(alpha: 0.22)
        : Colors.white.withValues(alpha: 0.10);

    return Row(
      children: [
        // Rank circle
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(color: rankBg, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(
            '$rank',
            style: AppTextStyles.labelSmall.copyWith(
              color: accent,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Avatar
        photoUrl != null
            ? NuvoAvatar(
                initials: _initials(label),
                photoUrl: photoUrl,
                size: 26,
                bgColor: avatarBg,
                textColor: accent,
              )
            : Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: avatarBg,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  _initials(label),
                  style: AppTextStyles.labelSmall.copyWith(
                    color: accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
        const SizedBox(width: 10),
        // Name
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: isCurrentUser ? Colors.white : _kSub,
              fontWeight: isCurrentUser ? FontWeight.w700 : FontWeight.normal,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // Value
        Text(
          value,
          style: AppTextStyles.labelSmall.copyWith(
            color: isCurrentUser ? NuvoColors.blue : _kMuted,
            fontWeight: isCurrentUser ? FontWeight.w700 : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}

// ── Dark outline ghost button ─────────────────────────────────────────────────

class _DarkOutlineButton extends StatelessWidget {
  const _DarkOutlineButton({
    required this.label,
    required this.onTap,
    this.icon,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        height: 52,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _kCardBorder),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: AppTextStyles.labelLarge.copyWith(color: Colors.white),
            ),
            if (icon != null) ...[
              const SizedBox(width: 8),
              Icon(icon, color: Colors.white, size: 18),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Skeleton bar ──────────────────────────────────────────────────────────────

class _Skel extends StatelessWidget {
  const _Skel({this.width, required this.height, this.radius = 4});
  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: _kSkel,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

// ── Race chip row ─────────────────────────────────────────────────────────────

class _RaceChipRow extends StatelessWidget {
  const _RaceChipRow({
    required this.boards,
    required this.selectedId,
    required this.onTap,
  });

  final List<ArenaBoard> boards;
  final String? selectedId;
  final ValueChanged<ArenaBoard> onTap;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final b in boards) ...[
            _RaceChip(
              board: b,
              selected: b.id == selectedId,
              onTap: () => onTap(b),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _RaceChip extends StatelessWidget {
  const _RaceChip({
    required this.board,
    required this.selected,
    required this.onTap,
  });

  final ArenaBoard board;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? NuvoColors.blue
              : Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? NuvoColors.blue : _kCardBorder),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: NuvoColors.blue.withValues(alpha: 0.30),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Text(
          board.title,
          style: AppTextStyles.labelMedium.copyWith(
            color: selected ? Colors.white : _kSub,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
          maxLines: 1,
        ),
      ),
    );
  }
}

// ── Compact board row (other races) ──────────────────────────────────────────

class _CompactBoardRow extends StatelessWidget {
  const _CompactBoardRow({required this.board, required this.onTap});

  final ArenaBoard board;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pct = board.progressPercent ?? 0;
    final count = board.racerCount ?? 0;
    final isComplete = pct >= 100;

    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _kCardBorder),
          boxShadow: const [
            BoxShadow(
              color: Color(0x50000000),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    board.title,
                    style: AppTextStyles.titleMedium.copyWith(
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    board.boardContext,
                    style: AppTextStyles.bodySmall.copyWith(color: _kSub),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (board.miniLeaderboard.isNotEmpty) ...[
              const SizedBox(width: 10),
              NuvoAvatarStack(
                avatars: board.miniLeaderboard
                    .map(
                      (r) => (
                        initials: _initials(r.label),
                        photoUrl: r.profilePhotoUrl,
                      ),
                    )
                    .toList(),
                total: count,
                size: 26,
                max: 3,
                borderColor: _kCard,
              ),
            ],
            const SizedBox(width: 10),
            Text(
              '$pct%',
              style: AppTextStyles.labelMedium.copyWith(
                color: isComplete ? NuvoColors.success : _kMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, color: _kMuted, size: 16),
          ],
        ),
      ),
    );
  }
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
  final trimmed = name.trim();
  return trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
}

// ── Empty / error states ──────────────────────────────────────────────────────

class _ArenaEmptyState extends StatelessWidget {
  const _ArenaEmptyState({required this.onStart, required this.onJoin});

  final VoidCallback onStart;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(
          'No active races.',
          style: AppTextStyles.headlineMedium.copyWith(color: Colors.white),
        ),
        const SizedBox(height: 8),
        Text(
          'Set a finish line, pull in your crew, and move the leaderboard.',
          style: AppTextStyles.bodyMedium.copyWith(color: _kSub),
        ),
        const SizedBox(height: 20),
        // Crew invite prompt
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kBlueBorder.withValues(alpha: 0.45)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 68,
                height: 26,
                child: Stack(
                  children: [
                    for (var i = 0; i < 3; i++)
                      Positioned(
                        left: i * 16.0,
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(
                              alpha: 0.08 + i * 0.06,
                            ),
                            shape: BoxShape.circle,
                            border: Border.all(color: _kCardBorder, width: 1.5),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Invite crew to race against you.',
                  style: AppTextStyles.bodySmall.copyWith(color: _kSub),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        NuvoBlueButton(label: 'Start a race', expand: true, onPressed: onStart),
        const SizedBox(height: 10),
        _DarkOutlineButton(label: 'Join with code', onTap: onJoin),
      ],
    );
  }
}

typedef _EmptyState = _ArenaEmptyState;

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(message, style: AppTextStyles.bodyMedium.copyWith(color: _kSub)),
        const SizedBox(height: 16),
        _DarkOutlineButton(label: 'Retry', onTap: onRetry),
      ],
    );
  }
}

// ── Notifications sheet ───────────────────────────────────────────────────────

void _showNotificationsSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: _kCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: _kCardBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'UPDATES',
              style: AppTextStyles.brandLabel.copyWith(
                color: NuvoColors.blue,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'No updates yet.',
              style: AppTextStyles.headlineMedium.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              'When your crew joins or crosses the finish line, you will see it here.',
              style: AppTextStyles.bodyMedium.copyWith(color: _kSub),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_avatar.dart';
import '../../../core/widgets/nuvo_board_components.dart';
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
      backgroundColor: NuvoColors.page,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
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
                                color: NuvoColors.blue,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(firstName, style: AppTextStyles.displayMedium),
                          ],
                        ),
                      ),
                      PressableScale(
                        onTap: () => _showNotificationsSheet(context),
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: NuvoColors.navy,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: NuvoColors.divider,
                              width: 2,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            initials,
                            style: AppTextStyles.labelMedium.copyWith(
                              color: NuvoColors.white,
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
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 120),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    if (arenaState.loading && snapshot == null)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: CircularProgressIndicator(strokeWidth: 2),
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
                            color: NuvoColors.muted,
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
//
// Loading strategy: keep the outer container and primary content (title,
// progress %, race lane, CTA) visible at all times — they come from snapshot
// data and are available immediately. Only the mini leaderboard section uses
// skeleton bars while the full race detail is fetching.

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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: NuvoColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: NuvoColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Loading bar — thin blue accent at top, invisible when idle ───
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

          // ── Race title + badge ─────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  board.title,
                  style: AppTextStyles.headlineMedium,
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
                      color: NuvoColors.white,
                    ),
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 6),
          Text(
            board.boardContext,
            style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
          ),

          // ── Crew strip ────────────────────────────────────────────────
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
                ),
              const Spacer(),
              if (board.daysLeft != null)
                Text(
                  '${board.daysLeft}d left',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: NuvoColors.muted,
                  ),
                ),
            ],
          ),

          // ── Rank + chase ──────────────────────────────────────────────
          if (board.myRank != null && !isResult) ...[
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '#${board.myRank}',
                      style: AppTextStyles.displaySmall.copyWith(
                        color: NuvoColors.navy,
                      ),
                    ),
                    Text(
                      'of ${board.racerCount ?? 1}',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: NuvoColors.muted,
                      ),
                    ),
                  ],
                ),
                if (board.chaseCopy != null) ...[
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      board.chaseCopy!,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: NuvoColors.muted,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],

          const SizedBox(height: 16),

          // ── Progress number + lane ─────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$pct',
                style: AppTextStyles.displaySmall.copyWith(
                  color: isResult ? NuvoColors.success : NuvoColors.navy,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 5, left: 2),
                child: Text(
                  '%',
                  style: AppTextStyles.titleLarge.copyWith(
                    color: NuvoColors.muted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          NuvoRaceLane(progressPercent: pct),

          // ── Mini leaderboard — real or skeleton ────────────────────────
          if (isLoading || board.miniLeaderboard.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(height: 1, color: NuvoColors.divider),
            const SizedBox(height: 12),

            if (isLoading)
              // Skeleton rows — same height as real rows, no layout jump
              ..._buildSkeletonRows()
            else
              for (var i = 0; i < board.miniLeaderboard.length; i++) ...[
                NuvoBoardLane(
                  participant: NuvoBoardParticipant(
                    rank: i + 1,
                    name: board.miniLeaderboard[i].label,
                    initials: _initials(board.miniLeaderboard[i].label),
                    progressPercent: _progressFromValue(
                      board.miniLeaderboard[i].value,
                    ),
                    progressLabel: board.miniLeaderboard[i].value,
                    photoUrl: board.miniLeaderboard[i].profilePhotoUrl,
                    isCurrentUser: board.miniLeaderboard[i].isCurrentUser,
                  ),
                ),
                if (i < board.miniLeaderboard.length - 1)
                  const SizedBox(height: 8),
              ],
          ],

          const SizedBox(height: 20),

          // ── CTA ────────────────────────────────────────────────────────
          isResult
              ? NuvoGhostButton(
                  label: 'Open board',
                  icon: Icons.arrow_forward_rounded,
                  expand: true,
                  onPressed: onOpen,
                )
              : NuvoPrimaryButton(
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
            _Skel(width: 22, height: 22, radius: 11),
            SizedBox(width: 8),
            _Skel(width: 14, height: 14, radius: 4),
            SizedBox(width: 8),
            _Skel(width: 90, height: 12, radius: 4),
            Spacer(),
            _Skel(width: 44, height: 12, radius: 4),
          ],
        ),
        if (i < 2) const SizedBox(height: 8),
      ],
    ];
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
      color: NuvoColors.trackBg,
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? NuvoColors.navy : NuvoColors.panel,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? NuvoColors.navy : NuvoColors.divider,
          ),
        ),
        child: Text(
          board.title,
          style: AppTextStyles.labelMedium.copyWith(
            color: selected ? NuvoColors.white : NuvoColors.muted,
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

    return NuvoRaceRow(
      title: board.title,
      subtitle: board.boardContext,
      progressPercent: pct,
      avatars: board.miniLeaderboard
          .map(
            (r) => (initials: _initials(r.label), photoUrl: r.profilePhotoUrl),
          )
          .toList(),
      total: count,
      onTap: onTap,
    );
  }
}

int _progressFromValue(String value) {
  final ratio = RegExp(r'(\d+)\s*/\s*(\d+)').firstMatch(value);
  if (ratio != null) {
    final current = int.tryParse(ratio.group(1) ?? '');
    final total = int.tryParse(ratio.group(2) ?? '');
    if (current != null && total != null && total > 0) {
      return ((current / total) * 100).round().clamp(0, 100);
    }
  }
  final pct = RegExp(r'(\d+)\s*%').firstMatch(value);
  if (pct != null) {
    return (int.tryParse(pct.group(1) ?? '') ?? 0).clamp(0, 100);
  }
  return 0;
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
        Text('No active races.', style: AppTextStyles.headlineMedium),
        const SizedBox(height: 8),
        Text(
          'Set a finish line, pull in your crew, and move the leaderboard.',
          style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
        ),
        const SizedBox(height: 20),
        // Crew invite prompt
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: NuvoColors.panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: NuvoColors.divider),
          ),
          child: Row(
            children: [
              // Placeholder crew avatars
              SizedBox(
                width: 68,
                height: 24,
                child: Stack(
                  children: [
                    for (var i = 0; i < 3; i++)
                      Positioned(
                        left: i * 15.0,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: NuvoColors.navy.withValues(
                              alpha: 0.15 + i * 0.12,
                            ),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: NuvoColors.white,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Invite crew to race against you.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: NuvoColors.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        NuvoPrimaryButton(
          label: 'Start a race',
          expand: true,
          onPressed: onStart,
        ),
        const SizedBox(height: 10),
        NuvoOutlineButton(
          label: 'Join with code',
          expand: true,
          onPressed: onJoin,
        ),
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
        Text(
          message,
          style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
        ),
        const SizedBox(height: 16),
        NuvoGhostButton(label: 'Retry', onPressed: onRetry, small: true),
      ],
    );
  }
}

// ── Notifications sheet ───────────────────────────────────────────────────────

void _showNotificationsSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: NuvoColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                width: 32,
                height: 3,
                decoration: BoxDecoration(
                  color: NuvoColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'UPDATES',
              style: AppTextStyles.brandLabel.copyWith(color: NuvoColors.blue),
            ),
            const SizedBox(height: 12),
            Text('No updates yet.', style: AppTextStyles.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'When your crew joins or crosses the finish line, you will see it here.',
              style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}

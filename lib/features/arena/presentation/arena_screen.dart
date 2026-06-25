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

    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () =>
              ref.read(arenaControllerProvider.notifier).loadSnapshot(),
          child: CustomScrollView(
            slivers: [
              // ── Compact header ──────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'NUVO',
                        style: AppTextStyles.brandLabel.copyWith(
                          color: NuvoColors.navy,
                          fontSize: 13,
                          letterSpacing: 3.0,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Spacer(),
                      NuvoIconAction(
                        icon: Icons.notifications_outlined,
                        onTap: () => _showNotificationsSheet(context),
                      ),
                      const SizedBox(width: 10),
                      PressableScale(
                        onTap: () => context.push('/profile'),
                        child: NuvoAvatar(
                          initials: initials,
                          photoUrl: user?.profilePhotoUrl,
                          size: 36,
                          bgColor: NuvoColors.navy,
                          textColor: NuvoColors.white,
                          borderColor: NuvoColors.divider,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Content ─────────────────────────────────────────────────
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 120),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    if (arenaState.loading && snapshot == null)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 60),
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
                        onBuild: () => context.push('/races/new'),
                        onJoin: () => context.push('/races/join'),
                      )
                    else ...[
                      // ── Race chip switcher (above hero) ──────────────────
                      if (allBoards.length > 1) ...[
                        _RaceChipRow(
                          boards: allBoards,
                          selectedId: resolvedId,
                          onTap: (b) => _onChipTap(b, snapshot, user?.id),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // ── START surface ─────────────────────────────────────
                      if (activeBoard != null)
                        _StartSurface(
                          board: activeBoard,
                          loading: _isLoadingBoardDetail,
                          onStart: () =>
                              _handlePrimaryAction(context, activeBoard),
                        ),
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

    // Rich type/unit line for boards loaded via chip tap
    final typeContext = isResult
        ? '$count ${count == 1 ? 'racer' : 'racers'} finished'
        : race.targetValue != null
        ? 'First to ${race.targetValue} ${race.unit ?? 'reps'}'
        : race.finishLineAt != null
        ? 'Most by time · ${race.unit ?? 'reps'}'
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
                ? '${myPart.progressValue} / ${race.targetValue} ${race.unit ?? 'reps'}'
                : '$myProgress%')
          : '',
      boardContext: typeContext,
      primaryActionLabel: isResult ? 'View Board' : 'START',
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

// ── START surface ─────────────────────────────────────────────────────────────
// The main action module on Home. Shows the selected race, progress context,
// and a dominant START button. No board list. No stats grid.

class _StartSurface extends StatelessWidget {
  const _StartSurface({
    required this.board,
    required this.loading,
    required this.onStart,
  });

  final ArenaBoard board;
  final bool loading;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final pct = board.progressPercent ?? 0;
    final isResult = board.isResult;
    final ctaLabel = isResult ? 'View Board' : 'START';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Race title ─────────────────────────────────────────────────
        Text(
          board.title,
          style: AppTextStyles.headlineLarge,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 5),
        // ── Type / context line ────────────────────────────────────────
        Text(
          board.boardContext,
          style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),

        const SizedBox(height: 20),

        // ── Progress block ─────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          decoration: BoxDecoration(
            color: NuvoColors.panel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: NuvoColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Progress number
              if (board.progressLabel.isNotEmpty)
                Text(
                  board.progressLabel,
                  style: AppTextStyles.titleLarge.copyWith(
                    color: NuvoColors.navy,
                    fontWeight: FontWeight.w800,
                  ),
                ),

              // Human chase line
              if (board.chaseCopy != null) ...[
                const SizedBox(height: 4),
                Text(
                  board.chaseCopy!,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: NuvoColors.muted,
                  ),
                ),
              ],

              // Progress lane
              const SizedBox(height: 14),
              NuvoRaceLane(progressPercent: pct),

              // Crew strip + rank
              if (board.miniLeaderboard.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    NuvoAvatarStack(
                      avatars: board.miniLeaderboard
                          .map((r) => (
                                initials: _initials(r.label),
                                photoUrl: r.profilePhotoUrl,
                              ))
                          .toList(),
                      total: board.racerCount ?? board.miniLeaderboard.length,
                      size: 22,
                      max: 4,
                    ),
                    const SizedBox(width: 8),
                    if (board.myRank != null && !isResult)
                      Text(
                        '#${board.myRank} of ${board.racerCount ?? 1}',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: NuvoColors.muted,
                        ),
                      ),
                    if (board.daysLeft != null) ...[
                      const Spacer(),
                      Text(
                        '${board.daysLeft}d left',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: NuvoColors.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ── START — dominant CTA ───────────────────────────────────────
        _StartButton(label: ctaLabel, loading: loading, onTap: onStart),
      ],
    );
  }
}

// ── START button ──────────────────────────────────────────────────────────────
// Larger than standard buttons — the primary action on Home.

class _StartButton extends StatelessWidget {
  const _StartButton({
    required this.label,
    required this.onTap,
    this.loading = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: loading ? null : onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: loading ? 0.7 : 1.0,
        child: Container(
          height: 62,
          width: double.infinity,
          decoration: BoxDecoration(
            color: NuvoColors.blue,
            borderRadius: BorderRadius.circular(18),
          ),
          alignment: Alignment.center,
          child: loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(NuvoColors.white),
                  ),
                )
              : Text(
                  label,
                  style: AppTextStyles.headlineMedium.copyWith(
                    color: NuvoColors.white,
                    letterSpacing: 0.5,
                  ),
                ),
        ),
      ),
    );
  }
}

// ── Race chip switcher ────────────────────────────────────────────────────────

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

// ── Helpers ───────────────────────────────────────────────────────────────────

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
  final trimmed = name.trim();
  return trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onBuild, required this.onJoin});

  final VoidCallback onBuild;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text('Start a race.', style: AppTextStyles.headlineLarge),
        const SizedBox(height: 8),
        Text(
          'Set the unit, invite your crew, and race to the finish line.',
          style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
        ),
        const SizedBox(height: 32),
        // Crew visual
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: NuvoColors.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: NuvoColors.divider),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 72,
                height: 28,
                child: Stack(
                  children: [
                    for (var i = 0; i < 3; i++)
                      Positioned(
                        left: i * 16.0,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: NuvoColors.navy.withValues(
                              alpha: 0.10 + i * 0.10,
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
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Invite your crew and race toward a finish line.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: NuvoColors.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _StartButton(label: 'BUILD', onTap: onBuild),
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

// ── Error state ───────────────────────────────────────────────────────────────

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

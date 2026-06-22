import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_error_state.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../races/data/race_models.dart';
import '../../races/presentation/race_controller.dart';
import '../data/arena_models.dart';
import 'arena_controller.dart';
import 'widgets/arena_v2_components.dart';

// Matches isResultRace() in arena.ts
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

    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    final firstName = user?.fullName?.split(' ').first ?? 'there';
    final initials = user?.avatarInitials ?? '?';

    // All boards for the race selector chip row
    final allBoards = snapshot == null
        ? <ArenaBoard>[]
        : <ArenaBoard>[
            if (snapshot.focusBoard != null) snapshot.focusBoard!,
            ...snapshot.liveBoards,
            ...snapshot.results,
          ];

    // Which board is displayed in the main card
    final activeBoard = _scoreCenterBoard ?? snapshot?.focusBoard;

    // Selector-resolved selected id (default to focusBoard if state not yet set)
    final resolvedSelectedId = _selectedBoardId ?? snapshot?.focusBoard?.id;

    // Other boards for "More boards" grid
    final otherBoards = allBoards
        .where((b) => b.id != resolvedSelectedId)
        .toList();

    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(arenaControllerProvider.notifier).loadSnapshot(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 120),
          children: [
            // ── Greeting header ───────────────────────────────────────────────
            ArenaGreetingHeader(
              greeting: greeting,
              firstName: firstName,
              headerPulse: snapshot?.headerPulse ?? '',
              initials: initials,
              onNotifications: () => _showNotificationsSheet(context),
            ),

            const SizedBox(height: 22),

            // ── Loading ───────────────────────────────────────────────────────
            if (arenaState.loading && snapshot == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: CircularProgressIndicator(),
                ),
              )
            // ── Error ─────────────────────────────────────────────────────────
            else if (arenaState.error != null && snapshot == null)
              NuvoErrorState(
                message: arenaState.error!,
                onRetry: () =>
                    ref.read(arenaControllerProvider.notifier).loadSnapshot(),
              )
            // ── Empty ─────────────────────────────────────────────────────────
            else if (snapshot == null || snapshot.isEmpty)
              _ArenaEmptyState(
                onStart: () => context.push('/races/new'),
                onJoin: () => context.push('/races/join'),
              )
            // ── Content ───────────────────────────────────────────────────────
            else ...[
              // Race selector chips (horizontal scroll)
              if (allBoards.isNotEmpty) ...[
                ArenaRaceSelector(
                  boards: allBoards,
                  selectedBoardId: resolvedSelectedId,
                  onTap: (board) => _onChipTap(board, snapshot, user?.id),
                ),
                const SizedBox(height: 18),
              ],

              // Main selected-race board card
              if (activeBoard != null) ...[
                ArenaFocusBoardCard(
                  board: activeBoard,
                  isLoadingDetail: _isLoadingBoardDetail,
                  userName: firstName,
                  userInitials: initials,
                  onSubmitProof: () => _handleSubmitProof(context, activeBoard),
                  onOpenBoard: () => _openBoard(context, activeBoard),
                ),
                const SizedBox(height: 28),
              ],

              // More boards 2-column grid (section header is inside the widget)
              if (otherBoards.isNotEmpty)
                ArenaMoreBoardsGrid(
                  boards: otherBoards,
                  onTap: (board) => _onChipTap(board, snapshot, user?.id),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _onChipTap(
    ArenaBoard board,
    ArenaSnapshot snapshot,
    String? userId,
  ) async {
    if (board.id == resolvedSelectedId(snapshot)) return;

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
      if (!mounted) return;
      setState(() {
        _isLoadingBoardDetail = false;
      });
    }
  }

  // Returns the resolved selected id (falls back to focusBoard if state unset).
  String? resolvedSelectedId(ArenaSnapshot snapshot) =>
      _selectedBoardId ?? snapshot.focusBoard?.id;

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

    return ArenaBoard(
      id: race.id,
      source: 'real',
      title: race.title,
      proofLabel: race.isAiMotionRace ? 'AI Motion' : 'Manual',
      progressLabel: myPart != null
          ? (race.targetValue != null
                ? 'You ${myPart.progressValue} / ${race.targetValue}'
                : 'You $myProgress%')
          : '',
      boardContext: boardContext,
      primaryActionLabel: isResult ? 'Open board' : 'Submit proof',
      primaryActionType: isResult ? 'open_board' : 'submit_proof',
      progressPercent: myProgress,
      racerCount: count,
      isResult: isResult,
      badgeLabel: race.isAiMotionRace ? 'AI' : null,
      miniLeaderboard: miniLeaderboard,
    );
  }

  void _openBoard(BuildContext context, ArenaBoard board) {
    if (board.isDemo) {
      _showDemoSnackbar(context);
      return;
    }
    context.push('/race/${board.id}');
  }

  void _handleSubmitProof(BuildContext context, ArenaBoard board) {
    if (board.isDemo) {
      _showDemoSnackbar(context);
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

  void _showDemoSnackbar(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Demo board preview'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _ArenaEmptyState extends StatelessWidget {
  const _ArenaEmptyState({required this.onStart, required this.onJoin});

  final VoidCallback onStart;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: NuvoColors.icyBlue,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: NuvoColors.navy, width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1407152B),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
          BoxShadow(
            color: Color(0x0B07152B),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(Icons.flag_rounded, color: NuvoColors.blue, size: 36),
          const SizedBox(height: 12),
          Text('Start with a finish line.', style: AppTextStyles.titleLarge),
          const SizedBox(height: 6),
          Text(
            'Set a finish line, pull in your crew, and move the leaderboard.',
            style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: PressableScale(
                  onTap: onStart,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: NuvoColors.blue,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x5007152B),
                          blurRadius: 0,
                          offset: Offset(3, 4),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Start a race',
                      style: AppTextStyles.labelMedium.copyWith(
                        color: NuvoColors.white,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PressableScale(
                  onTap: onJoin,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: NuvoColors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: NuvoColors.border),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Join with code',
                      style: AppTextStyles.labelMedium.copyWith(
                        color: NuvoColors.navy,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Notifications sheet ───────────────────────────────────────────────────────

void _showNotificationsSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: NuvoColors.page,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: NuvoColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            const Icon(
              Icons.notifications_none_rounded,
              color: NuvoColors.blue,
              size: 44,
            ),
            const SizedBox(height: 16),
            Text('No race updates yet.', style: AppTextStyles.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'When your crew joins, submits proof, or crosses the finish line, updates will appear here.',
              style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}

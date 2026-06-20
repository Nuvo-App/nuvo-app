import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_error_state.dart';
import '../../../core/widgets/nuvo_shared_components.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/arena_models.dart';
import 'arena_controller.dart';

class ArenaScreen extends ConsumerWidget {
  const ArenaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final arenaState = ref.watch(arenaControllerProvider);
    final snapshot = arenaState.snapshot;

    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    final firstName = user?.fullName?.split(' ').first ?? 'there';
    final initials = user?.avatarInitials ?? '?';

    final headerPulse = snapshot?.headerPulse ?? '';

    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(arenaControllerProvider.notifier).loadSnapshot(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
          children: [
            // ── Header ────────────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$greeting, $firstName',
                        style: AppTextStyles.headlineLarge,
                      ),
                      const SizedBox(height: 4),
                      if (headerPulse.isNotEmpty)
                        Text(
                          headerPulse,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: NuvoColors.muted,
                          ),
                        ),
                    ],
                  ),
                ),
                PressableScale(
                  onTap: () => _showNotificationsSheet(context),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: NuvoColors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: NuvoColors.border),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x1207152B),
                          blurRadius: 0,
                          offset: Offset(2, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.notifications_none_rounded,
                      color: NuvoColors.navy,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: NuvoColors.navy,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initials,
                    style: AppTextStyles.labelMedium.copyWith(
                      color: NuvoColors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 22),

            // ── Loading ──────────────────────────────────────────────────────
            if (arenaState.loading && snapshot == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: CircularProgressIndicator(),
                ),
              )
            // ── Error ────────────────────────────────────────────────────────
            else if (arenaState.error != null && snapshot == null)
              NuvoErrorState(
                message: arenaState.error!,
                onRetry: () =>
                    ref.read(arenaControllerProvider.notifier).loadSnapshot(),
              )
            // ── Empty ────────────────────────────────────────────────────────
            else if (snapshot == null || snapshot.isEmpty)
              _EmptyState(onStart: () => context.push('/races/new'))
            else ...[
              // ── Focus board ───────────────────────────────────────────────
              if (snapshot.focusBoard != null) ...[
                _FocusBoardCard(
                  board: snapshot.focusBoard!,
                  onTap: (board) => _handleBoardTap(context, board),
                ),
                const SizedBox(height: 20),
              ],

              // ── Activity (demo or future real feed) ───────────────────────
              if (snapshot.activity.isNotEmpty) ...[
                const NuvoSectionHeader(title: 'Activity', bottomPadding: 10),
                for (final event in snapshot.activity) ...[
                  _ActivityRow(event: event),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 12),
              ],

              // ── Live boards ───────────────────────────────────────────────
              if (snapshot.liveBoards.isNotEmpty) ...[
                const NuvoSectionHeader(
                  title: 'Live boards',
                  bottomPadding: 10,
                ),
                for (final board in snapshot.liveBoards) ...[
                  _buildBoardRow(context, board),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 10),
              ],

              // ── Results ───────────────────────────────────────────────────
              if (snapshot.results.isNotEmpty) ...[
                const NuvoSectionHeader(title: 'Results', bottomPadding: 10),
                for (final board in snapshot.results) ...[
                  _buildBoardRow(context, board),
                  const SizedBox(height: 10),
                ],
              ],
            ],
          ],
        ),
      ),
    );
  }

  // Safe board tap handler.
  // Demo boards never navigate to real routes — they show a preview snackbar.
  void _handleBoardTap(BuildContext context, ArenaBoard board) {
    if (board.isDemo) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Demo board preview'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    switch (board.primaryActionType) {
      case 'submit_proof':
        context.push('/race/${board.id}/proof');
      case 'open_board':
        context.push('/race/${board.id}');
      case 'start_race':
        context.push('/races/new');
      default:
        context.push('/race/${board.id}');
    }
  }

  Widget _buildBoardRow(BuildContext context, ArenaBoard board) {
    return NuvoDenseRaceRow(
      title: board.title,
      subtitle: board.proofLabel ?? board.progressLabel,
      progressPercent: board.progressPercent,
      isComplete: board.isResult,
      isAiMotion: board.badgeLabel == 'AI',
      onTap: () => _handleBoardTap(context, board),
    );
  }
}

// ── Focus board card (hero) ───────────────────────────────────────────────────

class _FocusBoardCard extends StatelessWidget {
  const _FocusBoardCard({required this.board, required this.onTap});

  final ArenaBoard board;
  final void Function(ArenaBoard) onTap;

  @override
  Widget build(BuildContext context) {
    final isAi = board.badgeLabel == 'AI';
    final progress = board.progressPercent ?? 0;

    return PressableScale(
      onTap: () => onTap(board),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: NuvoColors.navy,
          borderRadius: BorderRadius.all(Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Color(0xC007152B),
              blurRadius: 0,
              offset: Offset(5, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row — AI pill inline when applicable.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    board.title,
                    style: AppTextStyles.headlineMedium.copyWith(
                      color: NuvoColors.white,
                    ),
                  ),
                ),
                if (isAi && !board.isResult) ...[
                  const SizedBox(width: 10),
                  const NuvoPill(
                    label: 'AI Motion',
                    color: NuvoColors.blue,
                    onDark: true,
                  ),
                ],
              ],
            ),
            // Progress label (state line).
            const SizedBox(height: 6),
            Text(
              board.progressLabel,
              style: AppTextStyles.bodySmall.copyWith(
                color: NuvoColors.white.withValues(alpha: 0.60),
              ),
            ),
            // Progress bar — only when there is measurable progress.
            if (!board.isResult && progress > 0) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress / 100,
                        backgroundColor: NuvoColors.white.withValues(
                          alpha: 0.15,
                        ),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          NuvoColors.blue,
                        ),
                        minHeight: 5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '$progress%',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: NuvoColors.white.withValues(alpha: 0.70),
                    ),
                  ),
                ],
              ),
            ],
            // Mini leaderboard — when the backend sends rows.
            if (board.miniLeaderboard.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: NuvoColors.white.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    for (int i = 0; i < board.miniLeaderboard.length; i++) ...[
                      _MiniLeaderboardRow(
                        row: board.miniLeaderboard[i],
                        rank: i + 1,
                      ),
                      if (i < board.miniLeaderboard.length - 1)
                        Divider(
                          height: 10,
                          thickness: 0.5,
                          color: NuvoColors.white.withValues(alpha: 0.10),
                        ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            // Footer: board context + primary CTA.
            Row(
              children: [
                Expanded(
                  child: Text(
                    board.boardContext,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: NuvoColors.white.withValues(alpha: 0.55),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => onTap(board),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: board.isResult
                          ? NuvoColors.success
                          : NuvoColors.blue,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x4007152B),
                          blurRadius: 0,
                          offset: Offset(2, 3),
                        ),
                      ],
                    ),
                    child: Text(
                      board.primaryActionLabel,
                      style: AppTextStyles.labelMedium.copyWith(
                        color: NuvoColors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Mini leaderboard row ──────────────────────────────────────────────────────

class _MiniLeaderboardRow extends StatelessWidget {
  const _MiniLeaderboardRow({required this.row, required this.rank});

  final ArenaMiniLeaderboardRow row;
  final int rank;

  @override
  Widget build(BuildContext context) {
    final isUser = row.isCurrentUser;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            child: Text(
              '$rank',
              style: AppTextStyles.labelSmall.copyWith(
                color: NuvoColors.white.withValues(alpha: 0.45),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              row.label,
              style: AppTextStyles.labelMedium.copyWith(
                color: isUser
                    ? NuvoColors.white
                    : NuvoColors.white.withValues(alpha: 0.80),
                fontWeight: isUser ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          Text(
            row.value,
            style: AppTextStyles.labelSmall.copyWith(
              color: NuvoColors.white.withValues(alpha: 0.65),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Activity row ──────────────────────────────────────────────────────────────

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.event});

  final ArenaActivity event;

  @override
  Widget build(BuildContext context) {
    final initial = event.actorName.isNotEmpty
        ? event.actorName[0].toUpperCase()
        : '?';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: NuvoColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NuvoColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C07152B),
            blurRadius: 0,
            offset: Offset(2, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              color: NuvoColors.navy,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: AppTextStyles.labelSmall.copyWith(
                color: NuvoColors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${event.actorName} ${event.text}',
                  style: AppTextStyles.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (event.raceTitle != null)
                  Text(
                    event.raceTitle!,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: NuvoColors.muted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            event.timeLabel,
            style: AppTextStyles.labelSmall.copyWith(color: NuvoColors.muted),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: NuvoColors.icyBlue,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: NuvoColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1007152B),
            blurRadius: 0,
            offset: Offset(3, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(Icons.flag_rounded, color: NuvoColors.blue, size: 36),
          const SizedBox(height: 12),
          Text('No races yet', style: AppTextStyles.titleLarge),
          const SizedBox(height: 6),
          Text(
            'Set a finish line, pull in your crew, and move the leaderboard.',
            style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          PressableScale(
            onTap: onStart,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
              child: Text(
                'Start a race',
                style: AppTextStyles.labelMedium.copyWith(
                  color: NuvoColors.white,
                ),
              ),
            ),
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

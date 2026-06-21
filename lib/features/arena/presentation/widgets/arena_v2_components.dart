import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../data/arena_models.dart';

// Double shadow — used on main board card, More-boards cards, bottom nav.
const _kCardShadow = [
  BoxShadow(color: Color(0x1407152B), blurRadius: 20, offset: Offset(0, 8)),
  BoxShadow(color: Color(0x0B07152B), blurRadius: 4, offset: Offset(0, 2)),
];

// ── Helpers ───────────────────────────────────────────────────────────────────

String _participantInitials(String label) {
  if (label == 'You') return 'ME';
  final parts = label.trim().split(' ');
  if (parts.length >= 2 && parts[1].isNotEmpty) {
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
  return label.substring(0, label.length.clamp(0, 2)).toUpperCase();
}

// Extract "FIRST TO 50" label from miniLeaderboard or progressLabel.
String? _finishLinePill(ArenaBoard board) {
  // progressLabel is "You 8 / 50" — split on '/'
  if (board.progressLabel.contains('/')) {
    final raw = board.progressLabel.split('/').last.trim().split(' ').first;
    final n = int.tryParse(raw);
    if (n != null) return 'FIRST TO $n';
  }
  for (final row in board.miniLeaderboard) {
    if (row.value.contains('/')) {
      final raw = row.value.split('/').last.trim();
      final n = int.tryParse(raw);
      if (n != null) return 'FIRST TO $n';
    }
  }
  return null;
}

// ── ArenaGreetingHeader ───────────────────────────────────────────────────────
// Large greeting + header pulse status + notification bell + initials circle.

class ArenaGreetingHeader extends StatelessWidget {
  const ArenaGreetingHeader({
    super.key,
    required this.greeting,
    required this.firstName,
    required this.headerPulse,
    required this.initials,
    required this.onNotifications,
  });

  final String greeting;
  final String firstName;
  final String headerPulse;
  final String initials;
  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$greeting,\n$firstName',
                style: AppTextStyles.headlineLarge.copyWith(height: 1.15),
              ),
              if (headerPulse.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  headerPulse,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: NuvoColors.muted,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 10),
        // Notification bell
        PressableScale(
          onTap: onNotifications,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: NuvoColors.white,
              shape: BoxShape.circle,
              border: Border.all(color: NuvoColors.border),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0E07152B),
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
        // Profile initials
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
    );
  }
}

// ── ArenaRaceSelector ─────────────────────────────────────────────────────────
// Horizontal scrollable row of race chips. Selected = filled navy; others white.

class ArenaRaceSelector extends StatelessWidget {
  const ArenaRaceSelector({
    super.key,
    required this.boards,
    required this.selectedBoardId,
    required this.onTap,
  });

  final List<ArenaBoard> boards;
  final String? selectedBoardId;
  final void Function(ArenaBoard) onTap;

  @override
  Widget build(BuildContext context) {
    if (boards.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: boards.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final board = boards[i];
          final isSelected = board.id == selectedBoardId;
          return _ArenaRaceChip(
            board: board,
            isSelected: isSelected,
            onTap: () => onTap(board),
          );
        },
      ),
    );
  }
}

class _ArenaRaceChip extends StatelessWidget {
  const _ArenaRaceChip({
    required this.board,
    required this.isSelected,
    required this.onTap,
  });

  final ArenaBoard board;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        constraints: const BoxConstraints(minWidth: 130, maxWidth: 180),
        decoration: BoxDecoration(
          color: isSelected ? NuvoColors.navy : NuvoColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? NuvoColors.navy : NuvoColors.border,
            width: 1.5,
          ),
          boxShadow: isSelected
              ? _kCardShadow
              : [
                  const BoxShadow(
                    color: Color(0x0907152B),
                    blurRadius: 0,
                    offset: Offset(2, 3),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              board.title,
              style: AppTextStyles.titleMedium.copyWith(
                color: isSelected ? NuvoColors.white : NuvoColors.navy,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            Text(
              board.boardContext,
              style: AppTextStyles.labelSmall.copyWith(
                color: isSelected
                    ? NuvoColors.white.withValues(alpha: 0.60)
                    : NuvoColors.muted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ── ArenaFocusBoardCard ───────────────────────────────────────────────────────
// Main selected-race card. White/icy surface, thick navy outline, double shadow.

class ArenaFocusBoardCard extends StatelessWidget {
  const ArenaFocusBoardCard({
    super.key,
    required this.board,
    required this.isLoadingDetail,
    required this.onSubmitProof,
    required this.onOpenBoard,
  });

  final ArenaBoard board;
  final bool isLoadingDetail;
  final VoidCallback onSubmitProof;
  final VoidCallback onOpenBoard;

  @override
  Widget build(BuildContext context) {
    final pillLabel = _finishLinePill(board);

    return Container(
      decoration: BoxDecoration(
        color: NuvoColors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: NuvoColors.navy, width: 1.5),
        boxShadow: _kCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Pill + (optional AI badge inline)
                Row(
                  children: [
                    if (pillLabel != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: NuvoColors.icyBlue,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          pillLabel,
                          style: AppTextStyles.labelSmall.copyWith(
                            color: NuvoColors.blue,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
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
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          board.badgeLabel!.toUpperCase(),
                          style: AppTextStyles.labelSmall.copyWith(
                            color: NuvoColors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                // Race title (uppercase bold)
                Text(
                  board.title.toUpperCase(),
                  style: AppTextStyles.headlineMedium.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.3,
                  ),
                ),
                // Subtitle from pill target
                if (pillLabel != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    pillLabel
                        .split(' ')
                        .sublist(2)
                        .fold('First to ', (acc, s) => '$acc$s'),
                    style: AppTextStyles.bodySmall.copyWith(
                      color: NuvoColors.muted,
                    ),
                  ),
                ],
                const SizedBox(height: 16),

                // Leaderboard rows
                if (isLoadingDetail)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: NuvoColors.blue,
                        ),
                      ),
                    ),
                  )
                else if (board.miniLeaderboard.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      board.boardContext,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: NuvoColors.muted,
                      ),
                    ),
                  )
                else ...[
                  for (int i = 0; i < board.miniLeaderboard.length; i++) ...[
                    _FocusBoardLeaderboardRow(
                      row: board.miniLeaderboard[i],
                      rank: i + 1,
                    ),
                    if (i < board.miniLeaderboard.length - 1)
                      const SizedBox(height: 6),
                  ],
                  const SizedBox(height: 16),
                ],
              ],
            ),
          ),

          // Footer: racer count + divider + action buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
            child: Text(
              board.boardContext,
              style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
            ),
          ),
          const SizedBox(height: 12),
          const Divider(
            height: 1,
            thickness: 0.5,
            color: NuvoColors.border,
            indent: 18,
            endIndent: 18,
          ),
          const SizedBox(height: 14),

          // Submit proof button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: PressableScale(
              onTap: onSubmitProof,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  color: NuvoColors.blue,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x3007152B),
                      blurRadius: 0,
                      offset: Offset(3, 4),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  board.isResult ? board.primaryActionLabel : 'Submit proof',
                  style: AppTextStyles.titleMedium.copyWith(
                    color: NuvoColors.white,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Open board secondary button
          GestureDetector(
            onTap: onOpenBoard,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Center(
                child: Text(
                  'Open board',
                  style: AppTextStyles.labelMedium.copyWith(
                    color: NuvoColors.blue,
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

// ── _FocusBoardLeaderboardRow ─────────────────────────────────────────────────

class _FocusBoardLeaderboardRow extends StatelessWidget {
  const _FocusBoardLeaderboardRow({required this.row, required this.rank});

  final ArenaMiniLeaderboardRow row;
  final int rank;

  @override
  Widget build(BuildContext context) {
    final isUser = row.isCurrentUser;
    final initials = _participantInitials(row.label);

    Widget rowContent = Row(
      children: [
        // Rank badge or number
        if (isUser)
          Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              color: NuvoColors.blue,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$rank',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: NuvoColors.white,
              ),
            ),
          )
        else
          SizedBox(
            width: 24,
            child: Text(
              '$rank',
              style: AppTextStyles.labelSmall.copyWith(color: NuvoColors.muted),
              textAlign: TextAlign.center,
            ),
          ),
        const SizedBox(width: 8),
        // Initials circle
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: isUser ? NuvoColors.icyBlue : NuvoColors.border,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            initials,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: isUser ? NuvoColors.blue : NuvoColors.navy,
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Name
        Expanded(
          child: Text(
            row.label,
            style: AppTextStyles.bodyMedium.copyWith(
              color: NuvoColors.navy,
              fontWeight: isUser ? FontWeight.w700 : FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // Value
        Text(
          row.value,
          style: AppTextStyles.bodyMedium.copyWith(
            color: isUser ? NuvoColors.blue : NuvoColors.muted,
            fontWeight: isUser ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );

    if (isUser) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: NuvoColors.icyBlue,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: NuvoColors.blue, width: 1.5),
        ),
        child: rowContent,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 0),
      child: rowContent,
    );
  }
}

// ── ArenaMoreBoardsGrid ───────────────────────────────────────────────────────
// 2-column grid of smaller race cards for non-selected boards.

class ArenaMoreBoardsGrid extends StatelessWidget {
  const ArenaMoreBoardsGrid({
    super.key,
    required this.boards,
    required this.onTap,
  });

  final List<ArenaBoard> boards;
  final void Function(ArenaBoard) onTap;

  @override
  Widget build(BuildContext context) {
    final visible = boards.take(4).toList();
    final rows = <Widget>[];

    for (int i = 0; i < visible.length; i += 2) {
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _MoreBoardCard(
                  board: visible[i],
                  onTap: () => onTap(visible[i]),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: i + 1 < visible.length
                    ? _MoreBoardCard(
                        board: visible[i + 1],
                        onTap: () => onTap(visible[i + 1]),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
      if (i + 2 < visible.length) rows.add(const SizedBox(height: 12));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

class _MoreBoardCard extends StatelessWidget {
  const _MoreBoardCard({required this.board, required this.onTap});

  final ArenaBoard board;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final progress = (board.progressPercent ?? 0) / 100;

    return PressableScale(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: NuvoColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: NuvoColors.border, width: 1.5),
          boxShadow: _kCardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    board.title,
                    style: AppTextStyles.titleMedium.copyWith(
                      color: NuvoColors.navy,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    board.boardContext,
                    style: AppTextStyles.labelSmall.copyWith(
                      color: NuvoColors.muted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // Blue progress line at bottom
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(15),
              ),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                backgroundColor: NuvoColors.border,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  NuvoColors.blue,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

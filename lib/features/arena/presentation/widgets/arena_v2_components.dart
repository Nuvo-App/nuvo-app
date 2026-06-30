import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../data/arena_models.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────

const _kNavy = NuvoColors.navy;
const _kBlue = NuvoColors.blue;
const _kMuted = Color(0xFF66728A);
const _kBorder = Color(0xFFDCE5F2);
const _kIcy = Color(0xFFEEF5FF);

const _kCardShadow = [
  BoxShadow(color: Color(0x0D07152B), blurRadius: 12, offset: Offset(0, 4)),
  BoxShadow(color: Color(0x0607152B), blurRadius: 3, offset: Offset(0, 1)),
];

// ── Helpers ───────────────────────────────────────────────────────────────────

String? _finishLinePill(ArenaBoard board) {
  if (board.progressLabel.contains('/')) {
    final raw = board.progressLabel.split('/').last.trim().split(' ').first;
    final n = int.tryParse(raw);
    if (n != null) return 'FIRST TO $n';
  }
  for (final row in board.miniLeaderboard) {
    if (row.value.contains('/')) {
      final raw = row.value.split('/').last.trim().split(' ').first;
      final n = int.tryParse(raw);
      if (n != null) return 'FIRST TO $n';
    }
  }
  return null;
}

int? _parseValueInt(String value) {
  final clean = value.split('/').first.replaceAll('%', '').trim();
  return int.tryParse(clean);
}

String _proofPressureText(ArenaBoard board) {
  final rows = board.miniLeaderboard;
  if (rows.isEmpty) return 'Log a move to move the board.';
  final userIdx = rows.indexWhere((r) => r.isCurrentUser);
  if (userIdx < 0) return 'Log a move to move the board.';
  if (userIdx == 0) return "You're leading — keep it moving.";
  final above = rows[userIdx - 1];
  final userVal = _parseValueInt(rows[userIdx].value);
  final aboveVal = _parseValueInt(above.value);
  if (userVal != null && aboveVal != null) {
    final gap = aboveVal - userVal;
    if (gap <= 0) return "You're tied — push ahead.";
    final aboveName = above.label == 'You' ? 'the leader' : above.label;
    return "You're $gap behind $aboveName — step it up!";
  }
  return 'Log a move to move up.';
}

String _dotInitials(String label) {
  final parts = label.trim().split(' ');
  if (parts.length >= 2 && parts[1].isNotEmpty) {
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
  if (label.isNotEmpty) return label[0].toUpperCase();
  return '?';
}

// ── ArenaGreetingHeader ───────────────────────────────────────────────────────

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
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$greeting, $firstName',
                style: AppTextStyles.titleLarge.copyWith(color: _kNavy),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (headerPulse.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  headerPulse,
                  style: AppTextStyles.bodySmall.copyWith(color: _kMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: onNotifications,
          child: Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: _kNavy,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              initials,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── ArenaRaceSelector (text tabs with underline) ──────────────────────────────

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
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: boards.length,
        separatorBuilder: (_, _) => const SizedBox(width: 16),
        itemBuilder: (context, i) {
          final board = boards[i];
          return _RaceTab(
            title: board.title,
            isSelected: board.id == selectedBoardId,
            onTap: () => onTap(board),
          );
        },
      ),
    );
  }
}

class _RaceTab extends StatelessWidget {
  const _RaceTab({
    required this.title,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? _kNavy : _kMuted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 160),
              opacity: isSelected ? 1.0 : 0.0,
              child: Container(
                height: 2,
                decoration: BoxDecoration(
                  color: _kBlue,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── ArenaFocusBoardCard ───────────────────────────────────────────────────────

class ArenaFocusBoardCard extends StatelessWidget {
  const ArenaFocusBoardCard({
    super.key,
    required this.board,
    required this.isLoadingDetail,
    required this.userName,
    required this.userInitials,
    required this.onSubmitProof,
    required this.onOpenBoard,
  });

  final ArenaBoard board;
  final bool isLoadingDetail;
  final String userName;
  final String userInitials;
  final VoidCallback onSubmitProof;
  final VoidCallback onOpenBoard;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: NuvoColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kNavy, width: 1.5),
        boxShadow: _kCardShadow,
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _RaceBoardTitleBlock(board: board, userInitials: userInitials),
            const SizedBox(height: 16),
            if (isLoadingDetail)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (board.miniLeaderboard.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  board.boardContext,
                  style: AppTextStyles.bodySmall.copyWith(color: _kMuted),
                ),
              )
            else ...[
              for (int i = 0; i < board.miniLeaderboard.length; i++) ...[
                _LeaderboardRow(
                  row: board.miniLeaderboard[i],
                  rank: i + 1,
                  userName: userName,
                ),
                if (i < board.miniLeaderboard.length - 1)
                  const SizedBox(height: 5),
              ],
            ],
            if (!isLoadingDetail && board.miniLeaderboard.isNotEmpty) ...[
              const SizedBox(height: 14),
              _PressureLine(board: board),
            ],
            const SizedBox(height: 16),
            const Divider(height: 1, thickness: 0.5, color: _kBorder),
            const SizedBox(height: 14),
            _BlueButton(
              label: board.isResult ? board.primaryActionLabel : 'Log move',
              onTap: onSubmitProof,
            ),
            const SizedBox(height: 4),
            GestureDetector(
              onTap: onOpenBoard,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                child: Text(
                  'Open board',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: _kMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Blue submit button ────────────────────────────────────────────────────────

class _BlueButton extends StatelessWidget {
  const _BlueButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: _kBlue,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
              color: Color(0x28075BFF),
              blurRadius: 0,
              offset: Offset(0, 3),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: AppTextStyles.titleMedium.copyWith(color: Colors.white),
        ),
      ),
    );
  }
}

// ── RaceBoardTitleBlock ───────────────────────────────────────────────────────

class _RaceBoardTitleBlock extends StatelessWidget {
  const _RaceBoardTitleBlock({required this.board, required this.userInitials});

  final ArenaBoard board;
  final String userInitials;

  @override
  Widget build(BuildContext context) {
    final pillLabel = _finishLinePill(board);
    final participants = board.miniLeaderboard;
    final showDots = participants.length >= 2;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (pillLabel != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F1F3),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    pillLabel,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: _kNavy,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  Expanded(
                    child: Text(
                      board.title.toUpperCase(),
                      style: AppTextStyles.headlineMedium.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.3,
                        color: _kNavy,
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
                        color: _kBlue,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        board.badgeLabel!.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 3),
              Text(
                pillLabel != null
                    ? 'First to ${pillLabel.split(' ').last}'
                    : board.boardContext,
                style: AppTextStyles.bodySmall.copyWith(color: _kMuted),
              ),
            ],
          ),
        ),
        if (showDots) ...[
          const SizedBox(width: 10),
          _CrewDots(board: board, userInitials: userInitials),
        ],
      ],
    );
  }
}

// ── Overlapping crew dots ─────────────────────────────────────────────────────

class _CrewDots extends StatelessWidget {
  const _CrewDots({required this.board, required this.userInitials});

  final ArenaBoard board;
  final String userInitials;

  @override
  Widget build(BuildContext context) {
    final participants = board.miniLeaderboard;
    if (participants.length < 2) return const SizedBox.shrink();

    const maxVisible = 3;
    const dotSize = 28.0;
    const overlap = 10.0;
    const step = dotSize - overlap; // 18px

    final visible = participants.take(maxVisible).toList();
    final total = board.racerCount ?? participants.length;
    final overflowCount = total > maxVisible ? total - maxVisible : 0;

    final dotCount = visible.length + (overflowCount > 0 ? 1 : 0);
    final totalWidth = dotSize + (dotCount - 1) * step;

    return SizedBox(
      width: totalWidth,
      height: dotSize,
      child: Stack(
        children: [
          // Render in reverse so leftmost dot is on top.
          for (int i = visible.length - 1; i >= 0; i--)
            Positioned(
              left: i * step,
              child: _DotCircle(
                label: visible[i].isCurrentUser
                    ? userInitials
                    : _dotInitials(visible[i].label),
                isCurrentUser: visible[i].isCurrentUser,
              ),
            ),
          if (overflowCount > 0)
            Positioned(
              left: visible.length * step,
              child: Container(
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F1F3),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                alignment: Alignment.center,
                child: Text(
                  '+$overflowCount',
                  style: const TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: _kNavy,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DotCircle extends StatelessWidget {
  const _DotCircle({required this.label, required this.isCurrentUser});

  final String label;
  final bool isCurrentUser;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: isCurrentUser ? _kIcy : const Color(0xFFE8ECF2),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: isCurrentUser ? _kBlue : _kNavy,
        ),
      ),
    );
  }
}

// ── LeaderboardRow ────────────────────────────────────────────────────────────

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({
    required this.row,
    required this.rank,
    required this.userName,
  });

  final ArenaMiniLeaderboardRow row;
  final int rank;
  final String userName;

  @override
  Widget build(BuildContext context) {
    final isUser = row.isCurrentUser;
    final displayName = isUser ? userName : row.label;

    final rowContent = Row(
      children: [
        SizedBox(
          width: 20,
          child: isUser
              ? Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    color: _kBlue,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$rank',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                )
              : Text(
                  '$rank',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: _kMuted,
                  ),
                  textAlign: TextAlign.center,
                ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            displayName,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isUser ? FontWeight.w700 : FontWeight.w500,
              color: isUser ? _kBlue : _kNavy,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          row.value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isUser ? FontWeight.w700 : FontWeight.w400,
            color: isUser ? _kBlue : _kMuted,
          ),
        ),
      ],
    );

    if (isUser) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: _kIcy,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _kBlue, width: 1.5),
        ),
        child: rowContent,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: rowContent,
    );
  }
}

// ── PressureLine ──────────────────────────────────────────────────────────────

class _PressureLine extends StatelessWidget {
  const _PressureLine({required this.board});

  final ArenaBoard board;

  @override
  Widget build(BuildContext context) {
    final text = _proofPressureText(board);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 3,
            decoration: BoxDecoration(
              color: _kBlue,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.bodySmall.copyWith(
                color: _kNavy,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── ArenaMoreBoardsGrid ───────────────────────────────────────────────────────

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
    final gridRows = <Widget>[];

    for (int i = 0; i < visible.length; i += 2) {
      gridRows.add(
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
      if (i + 2 < visible.length) gridRows.add(const SizedBox(height: 12));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'More Boards',
              style: AppTextStyles.titleMedium.copyWith(color: _kNavy),
            ),
            const Spacer(),
            Text(
              'View all',
              style: AppTextStyles.bodySmall.copyWith(
                color: _kMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...gridRows,
      ],
    );
  }
}

class _MoreBoardCard extends StatelessWidget {
  const _MoreBoardCard({required this.board, required this.onTap});

  final ArenaBoard board;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final progress = (board.progressPercent ?? 0) / 100.0;

    return PressableScale(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: NuvoColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _kBorder, width: 1),
          boxShadow: _kCardShadow,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                board.title.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: _kNavy,
                  letterSpacing: 0.5,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (board.racerCount != null) ...[
                const SizedBox(height: 5),
                Text(
                  '${board.racerCount} ${board.racerCount == 1 ? 'Racer' : 'Racers'}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: _kMuted,
                  ),
                ),
              ],
              if (board.progressPercent != null) ...[
                const SizedBox(height: 2),
                Text(
                  '${board.progressPercent}%',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _kNavy,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor: _kIcy,
                  valueColor: const AlwaysStoppedAnimation<Color>(_kBlue),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

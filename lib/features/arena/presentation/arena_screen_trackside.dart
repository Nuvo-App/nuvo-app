import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_avatar.dart';
import '../../../core/widgets/track_side_orbit.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../races/data/race_models.dart';
import '../../races/presentation/race_controller.dart';
import '../data/arena_models.dart';
import 'arena_controller.dart';

const _kNavy = Color(0xFF071B35);
const _kBlue = Color(0xFF2F7CFF);
const _kWhite = Color(0xFFF8FAFD);
const _kMuted = Color(0xFFC5CBD5);
const _kWarmWhite = Color(0xFFFAF9F6);
const _kDarkText = Color(0xFF152238);
const _kMutedText = Color(0xFF7F8795);
const _kSeparator = Color(0xFFDDE1E6);
const _kDarkProgress = Color(0xFF414A59);

const bool _kPreviewMode = bool.fromEnvironment('NUVO_TRACKSIDE_PREVIEW');

class ArenaScreen extends ConsumerStatefulWidget {
  const ArenaScreen({super.key, this.preview = false});

  final bool preview;

  @override
  ConsumerState<ArenaScreen> createState() => _ArenaScreenState();
}

class _ArenaScreenState extends ConsumerState<ArenaScreen> {
  String? _selectedParticipantId;
  var _selectedBoardIndex = 0;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final arenaState = ref.watch(arenaControllerProvider);
    final raceState = ref.watch(raceControllerProvider);
    final width = MediaQuery.of(context).size.width;
    final scale = width / 390.0;
    final bottomPad = 75.0 * scale;

    final snapshot = widget.preview || _kPreviewMode
        ? _previewSnapshot()
        : arenaState.snapshot ??
              const ArenaSnapshot(mode: 'real', headerPulse: '');
    final cameraRaceById = {for (final race in raceState.races) race.id: race};

    final boards = <ArenaBoard>[
      if (snapshot.focusBoard != null) snapshot.focusBoard!,
      ...snapshot.liveBoards,
      ...snapshot.results,
    ];
    final selectedIndex = boards.isEmpty
        ? 0
        : _selectedBoardIndex.clamp(0, boards.length - 1);
    final activeBoard = boards.isEmpty ? null : boards[selectedIndex];
    final race = activeBoard != null ? cameraRaceById[activeBoard.id] : null;

    if (activeBoard == null) {
      return _EmptyTrackSide(scale: scale, bottomPad: bottomPad);
    }

    final myUserId = user?.id ?? '';
    final participants = race?.participants ?? [];
    final myPart = participants.where((p) => p.userId == myUserId).firstOrNull;
    final progressParts = _parseValue(activeBoard.progressLabel);
    final totalGoal = race?.targetValue ?? progressParts.$2;
    final currentValue = myPart?.progressValue ?? progressParts.$1;
    final currentRank = myPart?.rank ?? activeBoard.myRank ?? 1;
    final orbitParticipants = _buildOrbitParticipants(
      participants: participants,
      miniLeaderboard: activeBoard.miniLeaderboard,
      myUserId: myUserId,
    );

    return Scaffold(
      backgroundColor: _kNavy,
      body: SafeArea(
        top: false,
        bottom: false,
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TrackSideHero(
                scale: scale,
                raceIndex: selectedIndex,
                raceCount: boards.length,
                totalGoal: totalGoal,
                currentValue: currentValue,
                currentRank: currentRank,
                subtitle: activeBoard.boardContext.isNotEmpty
                    ? activeBoard.boardContext
                    : 'First to $totalGoal Pushups',
                participants: orbitParticipants,
                selectedId: _selectedParticipantId,
                onParticipantTap: (id) =>
                    setState(() => _selectedParticipantId = id),
                onPreviousRace: selectedIndex > 0
                    ? () => setState(() {
                        _selectedBoardIndex = selectedIndex - 1;
                        _selectedParticipantId = null;
                      })
                    : null,
                onNextRace: selectedIndex < boards.length - 1
                    ? () => setState(() {
                        _selectedBoardIndex = selectedIndex + 1;
                        _selectedParticipantId = null;
                      })
                    : null,
                onSubmit: () => _handlePrimaryAction(activeBoard, race),
              ),
              _StandingsAndActivityPanel(
                scale: scale,
                board: activeBoard,
                race: race,
                myUserId: myUserId,
                activity: snapshot.activity,
              ),
              SizedBox(height: bottomPad),
            ],
          ),
        ),
      ),
    );
  }

  List<TrackSideOrbitParticipant> _buildOrbitParticipants({
    required List<RaceParticipant> participants,
    required List<ArenaMiniLeaderboardRow> miniLeaderboard,
    required String myUserId,
  }) {
    final source = participants.isNotEmpty
        ? participants
        : miniLeaderboard.map((r) {
            final parts = _parseValue(r.value);
            return RaceParticipant(
              id: r.label,
              userId: r.isCurrentUser ? myUserId : r.label,
              displayName: r.label,
              progressValue: parts.$1,
              progressPercent: parts.$2,
              rank: 0,
              joinedAt: '',
              profilePhotoUrl: r.profilePhotoUrl,
            );
          }).toList();

    final ranked = [...source]
      ..sort((a, b) {
        final ra = a.rank ?? 0;
        final rb = b.rank ?? 0;
        if (ra == 0 && rb == 0) return b.progressValue - a.progressValue;
        return ra.compareTo(rb);
      });

    return ranked.asMap().entries.map((e) {
      final p = e.value;
      final rank = p.rank ?? e.key + 1;
      return TrackSideOrbitParticipant(
        id: p.userId.isNotEmpty ? p.userId : p.id,
        name: p.displayName,
        initials: _initials(p.displayName),
        rank: rank,
        progressValue: p.progressValue,
        photoUrl: p.profilePhotoUrl,
        isCurrentUser: p.userId == myUserId || p.id == myUserId,
      );
    }).toList();
  }

  (int, int) _parseValue(String value) {
    final parts = value.split('/').map((s) => int.tryParse(s.trim())).toList();
    final a = parts.isNotEmpty ? parts[0] ?? 0 : 0;
    final b = parts.length > 1 ? parts[1] ?? 100 : 100;
    final pct = b == 0 ? 0 : ((a / b) * 100).round();
    return (a, pct);
  }

  void _handlePrimaryAction(ArenaBoard board, Race? race) {
    if (board.isDemo) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Demo board preview')));
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

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts.isNotEmpty && parts[0].isNotEmpty
        ? parts[0][0].toUpperCase()
        : '?';
  }
}

class _TrackSideHero extends StatelessWidget {
  const _TrackSideHero({
    required this.scale,
    required this.raceIndex,
    required this.raceCount,
    required this.totalGoal,
    required this.currentValue,
    required this.currentRank,
    required this.subtitle,
    required this.participants,
    this.selectedId,
    this.onParticipantTap,
    this.onPreviousRace,
    this.onNextRace,
    required this.onSubmit,
  });

  final double scale;
  final int raceIndex;
  final int raceCount;
  final int totalGoal;
  final int currentValue;
  final int currentRank;
  final String subtitle;
  final List<TrackSideOrbitParticipant> participants;
  final String? selectedId;
  final ValueChanged<String>? onParticipantTap;
  final VoidCallback? onPreviousRace;
  final VoidCallback? onNextRace;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final remaining = (totalGoal - currentValue).clamp(0, totalGoal);

    return SizedBox(
      height: 500 * scale,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _HeroBackground(scale: scale),
          Positioned(
            left: 26 * scale,
            top: 31 * scale,
            child: Image.asset(
              'assets/branding/nuvo_logo.png',
              height: 28 * scale,
              errorBuilder: (context, error, stackTrace) =>
                  SizedBox(height: 28 * scale),
            ),
          ),
          Positioned(
            right: 26 * scale,
            top: 34 * scale,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'ARENA',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: _kBlue,
                    fontSize: 12 * scale,
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (raceCount > 1) ...[
                  SizedBox(height: 12 * scale),
                  _RaceSwitcher(
                    scale: scale,
                    index: raceIndex,
                    count: raceCount,
                    onPrevious: onPreviousRace,
                    onNext: onNextRace,
                  ),
                ],
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 94 * scale,
            child: Text(
              'Your next move',
              textAlign: TextAlign.center,
              style: AppTextStyles.headlineLarge.copyWith(
                color: _kWhite,
                fontSize: 28 * scale,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 132 * scale,
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyMedium.copyWith(
                color: _kMuted,
                fontSize: 15 * scale,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 168 * scale,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '$currentValue',
                  style: AppTextStyles.displayLarge.copyWith(
                    color: _kBlue,
                    fontSize: 64 * scale,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                  ),
                ),
                Text(
                  ' / ',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: _kMuted,
                    fontSize: 24 * scale,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                Text(
                  '$totalGoal',
                  style: AppTextStyles.displayLarge.copyWith(
                    color: _kWhite,
                    fontSize: 56 * scale,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 242 * scale,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$remaining',
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: _kBlue,
                      fontSize: 15 * scale,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(
                    text: ' to the finish line',
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: _kMuted,
                      fontSize: 15 * scale,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Positioned(
            left: -30 * scale,
            top: 274 * scale,
            child: ClipRect(
              child: SizedBox(
                height: 138 * scale,
                width: 450 * scale,
                child: TrackSideOrbit(
                  scale: scale * 0.72,
                  totalGoal: totalGoal,
                  currentUserValue: currentValue,
                  currentUserRank: currentRank,
                  participants: participants,
                  selectedParticipantId: selectedId,
                  onParticipantTap: onParticipantTap,
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 424 * scale,
            child: Center(
              child: GestureDetector(
                onTap: onSubmit,
                child: Container(
                  width: 241 * scale,
                  height: 51 * scale,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8 * scale),
                    gradient: const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [Color(0xFF1A63D8), _kBlue],
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'Submit proof',
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: _kWhite,
                      fontSize: 16 * scale,
                      fontWeight: FontWeight.w600,
                    ),
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

class _HeroBackground extends StatelessWidget {
  const _HeroBackground({required this.scale});
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kNavy,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.75, -0.55),
                radius: 0.9,
                colors: [const Color(0xFF123A6D).withValues(alpha: 1), _kNavy],
                stops: const [0.0, 0.85],
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.15,
                colors: [_kNavy.withValues(alpha: 0.0), _kNavy],
                stops: const [0.55, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RaceSwitcher extends StatelessWidget {
  const _RaceSwitcher({
    required this.scale,
    required this.index,
    required this.count,
    required this.onPrevious,
    required this.onNext,
  });

  final double scale;
  final int index;
  final int count;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 33 * scale,
      constraints: BoxConstraints(minWidth: 118 * scale),
      decoration: BoxDecoration(
        color: const Color(0x1A1264FF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x663D7BFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RaceSwitchButton(
            scale: scale,
            icon: Icons.chevron_left_rounded,
            onPressed: onPrevious,
          ),
          SizedBox(
            width: 48 * scale,
            child: Text(
              '${index + 1} / $count',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: const Color(0xFFE8F1FF),
                fontSize: 12 * scale,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          _RaceSwitchButton(
            scale: scale,
            icon: Icons.chevron_right_rounded,
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

class _RaceSwitchButton extends StatelessWidget {
  const _RaceSwitchButton({
    required this.scale,
    required this.icon,
    required this.onPressed,
  });

  final double scale;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 33 * scale,
      height: 33 * scale,
      child: IconButton(
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        iconSize: 21 * scale,
        color: onPressed == null
            ? const Color(0x557D8CA3)
            : const Color(0xFFF4F8FF),
        icon: Icon(icon),
      ),
    );
  }
}

class _StandingsAndActivityPanel extends StatelessWidget {
  const _StandingsAndActivityPanel({
    required this.scale,
    required this.board,
    this.race,
    required this.myUserId,
    required this.activity,
  });

  final double scale;
  final ArenaBoard board;
  final Race? race;
  final String myUserId;
  final List<ArenaActivity> activity;

  @override
  Widget build(BuildContext context) {
    final rows = board.miniLeaderboard;
    final firstActivity = activity.isNotEmpty ? activity.first : null;

    return Container(
      color: _kWarmWhite,
      constraints: BoxConstraints(minHeight: (844 - 500 - 75) * scale),
      padding: EdgeInsets.fromLTRB(
        26 * scale,
        16 * scale,
        26 * scale,
        10 * scale,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'CREW STANDINGS',
                style: AppTextStyles.labelSmall.copyWith(
                  color: _kMutedText,
                  fontSize: 11 * scale,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => context.push('/race/${board.id}'),
                child: Text(
                  'VIEW ALL',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: _kBlue,
                    fontSize: 11 * scale,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8 * scale),
          for (var i = 0; i < rows.length; i++) ...[
            _StandingRow(
              scale: scale,
              row: rows[i],
              rank: i + 1,
              myUserId: myUserId,
            ),
            if (i < rows.length - 1)
              Container(height: 0.5 * scale, color: _kSeparator),
          ],
          if (firstActivity != null) ...[
            SizedBox(height: 24 * scale),
            Text(
              'RECENT ACTIVITY',
              style: AppTextStyles.labelSmall.copyWith(
                color: _kMutedText,
                fontSize: 11 * scale,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
            SizedBox(height: 6 * scale),
            _ActivityRow(
              scale: scale,
              activity: firstActivity,
              myUserId: myUserId,
            ),
          ],
        ],
      ),
    );
  }
}

class _StandingRow extends StatelessWidget {
  const _StandingRow({
    required this.scale,
    required this.row,
    required this.rank,
    required this.myUserId,
  });

  final double scale;
  final ArenaMiniLeaderboardRow row;
  final int rank;
  final String myUserId;

  @override
  Widget build(BuildContext context) {
    final isUser = row.isCurrentUser || row.label == 'You';
    final displayName = isUser ? 'You' : row.label;
    final parts = row.value.split('/').map((s) => s.trim()).toList();
    final valueNum = int.tryParse(parts.first) ?? 0;
    final totalPart = parts.length > 1 ? parts[1] : '100';
    final totalLabel = totalPart.replaceAll(RegExp(r'[^0-9]'), '');
    final valueLabel = parts.length == 2
        ? '${parts[0]} / $totalLabel'
        : row.value;
    final totalNum = int.tryParse(totalLabel) ?? 100;
    final progress = totalNum == 0 ? 0.0 : valueNum / totalNum;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 1 * scale),
      child: Row(
        children: [
          SizedBox(
            width: 24 * scale,
            child: Text(
              '$rank',
              style: AppTextStyles.bodyMedium.copyWith(
                color: isUser ? _kBlue : _kMutedText,
                fontSize: 13 * scale,
                fontWeight: isUser ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          SizedBox(width: 8 * scale),
          NuvoAvatar(
            initials: _initials(displayName),
            photoUrl: row.profilePhotoUrl,
            size: 36 * scale,
            bgColor: nuvoAvatarColorFor(row.label),
            textColor: _kWhite,
            borderColor: isUser ? _kBlue : NuvoColors.white,
            borderWidth: isUser ? 2.0 : 1.5,
          ),
          SizedBox(width: 12 * scale),
          Expanded(
            child: Text(
              displayName,
              style: AppTextStyles.bodyMedium.copyWith(
                color: isUser ? _kBlue : _kDarkText,
                fontSize: 15 * scale,
                fontWeight: isUser ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          SizedBox(width: 8 * scale),
          Text(
            valueLabel,
            style: AppTextStyles.bodyMedium.copyWith(
              color: isUser ? _kBlue : _kMutedText,
              fontSize: 14 * scale,
              fontWeight: isUser ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          SizedBox(width: 16 * scale),
          ClipRRect(
            borderRadius: BorderRadius.circular(3 * scale),
            child: SizedBox(
              width: 70 * scale,
              height: 6 * scale,
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: _kSeparator,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isUser ? _kBlue : _kDarkProgress,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts.isNotEmpty && parts[0].isNotEmpty
        ? parts[0][0].toUpperCase()
        : '?';
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.scale,
    required this.activity,
    required this.myUserId,
  });

  final double scale;
  final ArenaActivity activity;
  final String myUserId;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        NuvoAvatar(
          initials: _initials(activity.actorName),
          photoUrl: null,
          size: 28 * scale,
          bgColor: nuvoAvatarColorFor(activity.actorName),
          textColor: _kWhite,
          borderColor: NuvoColors.white,
          borderWidth: 1.5,
        ),
        SizedBox(width: 10 * scale),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: activity.actorName,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: _kDarkText,
                    fontSize: 14 * scale,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(
                  text: ' ${activity.text}',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: _kMutedText,
                    fontSize: 14 * scale,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
        Text(
          activity.timeLabel,
          style: AppTextStyles.bodySmall.copyWith(
            color: _kMutedText,
            fontSize: 12 * scale,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts.isNotEmpty && parts[0].isNotEmpty
        ? parts[0][0].toUpperCase()
        : '?';
  }
}

class _EmptyTrackSide extends StatelessWidget {
  const _EmptyTrackSide({required this.scale, required this.bottomPad});

  final double scale;
  final double bottomPad;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kNavy,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'No active race on the board',
              style: AppTextStyles.titleLarge.copyWith(color: _kWhite),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16 * scale),
            ElevatedButton(
              onPressed: () => context.push('/races/new'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kBlue,
                foregroundColor: _kWhite,
                padding: EdgeInsets.symmetric(
                  horizontal: 24 * scale,
                  vertical: 12 * scale,
                ),
              ),
              child: const Text('Start a race'),
            ),
            SizedBox(height: bottomPad),
          ],
        ),
      ),
    );
  }
}

ArenaSnapshot _previewSnapshot() {
  return const ArenaSnapshot(
    mode: 'real',
    headerPulse: '',
    focusBoard: ArenaBoard(
      id: 'preview-race',
      source: 'real',
      title: 'Pushups',
      progressLabel: '65 / 100',
      boardContext: 'First to 100 Pushups',
      primaryActionLabel: 'Submit proof',
      primaryActionType: 'submit_proof',
      progressPercent: 65,
      racerCount: 3,
      isResult: false,
      myRank: 1,
      miniLeaderboard: [
        ArenaMiniLeaderboardRow(
          label: 'You',
          value: '65 / 100',
          isCurrentUser: true,
        ),
        ArenaMiniLeaderboardRow(
          label: 'Alex R.',
          value: '48 / 100',
          isCurrentUser: false,
        ),
        ArenaMiniLeaderboardRow(
          label: 'Maya L.',
          value: '31 / 100',
          isCurrentUser: false,
        ),
      ],
    ),
    liveBoards: [
      ArenaBoard(
        id: 'preview-squats',
        source: 'real',
        title: 'Squats',
        progressLabel: '28 / 60',
        boardContext: 'First to 60 Squats',
        primaryActionLabel: 'Submit proof',
        primaryActionType: 'submit_proof',
        progressPercent: 47,
        racerCount: 3,
        isResult: false,
        myRank: 2,
        miniLeaderboard: [
          ArenaMiniLeaderboardRow(
            label: 'Riley Pace',
            value: '34 / 60',
            isCurrentUser: false,
          ),
          ArenaMiniLeaderboardRow(
            label: 'You',
            value: '28 / 60',
            isCurrentUser: true,
          ),
          ArenaMiniLeaderboardRow(
            label: 'Jordan',
            value: '19 / 60',
            isCurrentUser: false,
          ),
        ],
      ),
      ArenaBoard(
        id: 'preview-lunges',
        source: 'real',
        title: 'Lunges',
        progressLabel: '0 / 40',
        boardContext: 'First to 40 Lunges',
        primaryActionLabel: 'Submit proof',
        primaryActionType: 'submit_proof',
        progressPercent: 0,
        racerCount: 3,
        isResult: false,
        myRank: 3,
        miniLeaderboard: [
          ArenaMiniLeaderboardRow(
            label: 'Jordan',
            value: '15 / 40',
            isCurrentUser: false,
          ),
          ArenaMiniLeaderboardRow(
            label: 'Maya Sprint',
            value: '8 / 40',
            isCurrentUser: false,
          ),
          ArenaMiniLeaderboardRow(
            label: 'You',
            value: '0 / 40',
            isCurrentUser: true,
          ),
        ],
      ),
    ],
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
}

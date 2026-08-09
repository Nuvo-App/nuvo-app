import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/animated_race_track.dart';
import '../../../core/widgets/nuvo_avatar.dart';
import '../../../core/widgets/nuvo_leaderboard.dart';
import '../../../core/widgets/nuvo_race_strip.dart';
import '../../../core/widgets/trackside_layout_diagnostics.dart';
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

const bool _kPreviewMode = bool.fromEnvironment('NUVO_TRACKSIDE_PREVIEW');

class ArenaScreen extends ConsumerStatefulWidget {
  const ArenaScreen({super.key, this.preview = false});

  final bool preview;

  @override
  ConsumerState<ArenaScreen> createState() => _ArenaScreenState();
}

class _ArenaScreenState extends ConsumerState<ArenaScreen> {
  var _selectedBoardIndex = 0;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _selectedBoardIndex);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.bottom],
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final arenaState = ref.watch(arenaControllerProvider);
    final raceState = ref.watch(raceControllerProvider);
    final viewport = MediaQuery.sizeOf(context);
    final scale = viewport.width / 390.0;
    final bottomPad = 75.0 * scale;
    final canvasHeight = viewport.height > 844.0 * scale
        ? viewport.height
        : 844.0 * scale;
    final panelMinHeight = canvasHeight - 464.0 * scale - bottomPad;

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
    final raceStrips = _buildRaceStripData(boards);
    final pageChildren = List<Widget>.generate(boards.length, (index) {
      final board = boards[index];
      final boardRace = cameraRaceById[board.id];
      final boardParticipants = boardRace?.participants ?? [];
      final boardParts = _parseValue(board.progressLabel);
      final boardTotalGoal = boardRace?.targetValue ?? boardParts.$2;
      final boardMyPart = boardParticipants
          .where((p) => p.userId == myUserId)
          .firstOrNull;
      final boardCurrentValue = boardMyPart?.progressValue ?? boardParts.$1;
      final boardCurrentRank = boardMyPart?.rank ?? board.myRank ?? 1;
      final competitors = _buildRaceCompetitors(
        participants: boardParticipants,
        miniLeaderboard: board.miniLeaderboard,
        myUserId: myUserId,
        totalGoal: boardTotalGoal,
      );
      return Center(
        child: NuvoRaceTrack(
          competitors: competitors,
          totalGoal: boardTotalGoal,
          currentValue: boardCurrentValue,
          currentRank: boardCurrentRank,
          size: 220 * scale,
        ),
      );
    });

    return Scaffold(
      key: TrackSideLayoutKeys.arenaScreen,
      backgroundColor: _kNavy,
      body: SafeArea(
        top: false,
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (trackSideLayoutDiagnosticsEnabled) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                TrackSideLayoutDiagnostics.report({
                  ...TrackSideLayoutDiagnostics.viewData(context),
                  'arenaScreenConstraints': constraints.toString(),
                  'trackSideCanvasConstraints':
                      'minHeight=${constraints.maxHeight > canvasHeight ? constraints.maxHeight.toStringAsFixed(1) : canvasHeight.toStringAsFixed(1)}',
                  'widthScale': scale.toStringAsFixed(4),
                  'baselineCanvasHeight': (844.0 * scale).toStringAsFixed(1),
                  'calculatedCanvasHeight': canvasHeight.toStringAsFixed(1),
                  'calculatedHeroHeight': (464.0 * scale).toStringAsFixed(1),
                  'calculatedPanelMinHeight': panelMinHeight.toStringAsFixed(1),
                  'calculatedNavigationHeight':
                      (75.0 * scale + MediaQuery.paddingOf(context).bottom)
                          .toStringAsFixed(1),
                  'calculatedBottomReserve': bottomPad.toStringAsFixed(1),
                  'arenaScreen': TrackSideLayoutDiagnostics.box(
                    TrackSideLayoutKeys.arenaScreen,
                  ),
                  'trackSideCanvas': TrackSideLayoutDiagnostics.box(
                    TrackSideLayoutKeys.canvas,
                  ),
                  'hero': TrackSideLayoutDiagnostics.box(
                    TrackSideLayoutKeys.hero,
                  ),
                  'whitePanel': TrackSideLayoutDiagnostics.box(
                    TrackSideLayoutKeys.panel,
                  ),
                  'recentActivity': TrackSideLayoutDiagnostics.box(
                    TrackSideLayoutKeys.recentActivity,
                  ),
                  'navigationBackground': TrackSideLayoutDiagnostics.box(
                    TrackSideLayoutKeys.navigation,
                  ),
                  'navigationIconRow': TrackSideLayoutDiagnostics.box(
                    TrackSideLayoutKeys.navigationRow,
                  ),
                });
              });
            }
            return SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: ConstrainedBox(
                key: TrackSideLayoutKeys.canvas,
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight > canvasHeight
                      ? constraints.maxHeight
                      : canvasHeight,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        16 * scale,
                        12 * scale,
                        16 * scale,
                        8 * scale,
                      ),
                      child: NuvoRaceStripRail(
                        races: raceStrips,
                        selectedId: activeBoard.id,
                        onTap: (data) {
                          final index = boards.indexWhere(
                            (b) => b.id == data.id,
                          );
                          if (index >= 0 && index != selectedIndex) {
                            _pageController.animateToPage(
                              index,
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOutCubic,
                            );
                          }
                        },
                      ),
                    ),
                    _TrackSideHero(
                      scale: scale,
                      pageController: _pageController,
                      pageCount: boards.length,
                      pageBuilder: (index) => pageChildren[index],
                      onPageChanged: (index) => setState(() {
                        _selectedBoardIndex = index;
                      }),
                      totalGoal: totalGoal,
                      currentValue: currentValue,
                      currentRank: currentRank,
                      subtitle: 'First to $totalGoal Pushups',
                      onSubmit: () => _handlePrimaryAction(activeBoard, race),
                    ),
                    _StandingsAndActivityPanel(
                      scale: scale,
                      minHeight: panelMinHeight,
                      board: activeBoard,
                      race: race,
                      myUserId: myUserId,
                      activity: snapshot.activity,
                    ),
                    SizedBox(height: bottomPad),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  List<RaceCompetitor> _buildRaceCompetitors({
    required List<RaceParticipant> participants,
    required List<ArenaMiniLeaderboardRow> miniLeaderboard,
    required String myUserId,
    required int totalGoal,
  }) {
    final source = participants.isNotEmpty
        ? participants
        : miniLeaderboard.map((r) {
            final parts = _parseValue(r.value);
            final total = parts.$2;
            final progressPercent = total == 0
                ? 0
                : ((parts.$1 / total) * 100).round();
            return RaceParticipant(
              id: r.label,
              userId: r.isCurrentUser ? myUserId : r.label,
              displayName: r.label,
              progressValue: parts.$1,
              progressPercent: progressPercent,
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
      final progress = totalGoal == 0
          ? 0.0
          : (p.progressValue / totalGoal).clamp(0.0, 1.0);
      return RaceCompetitor(
        id: p.userId.isNotEmpty ? p.userId : p.id,
        name: p.displayName,
        initials: _initials(p.displayName),
        progress: progress,
        rank: rank,
        avatarImageUrl: p.profilePhotoUrl,
        isCurrentUser: p.userId == myUserId || p.id == myUserId,
        isLeader: rank == 1,
      );
    }).toList();
  }

  List<NuvoRaceStripData> _buildRaceStripData(List<ArenaBoard> boards) {
    return boards
        .map(
          (board) => NuvoRaceStripData(
            id: board.id,
            title: board.title,
            rank: board.myRank,
            progressPercent: board.progressPercent,
          ),
        )
        .toList();
  }

  (int, int) _parseValue(String value) {
    final parts = value.split('/').map((s) => int.tryParse(s.trim())).toList();
    final a = parts.isNotEmpty ? parts[0] ?? 0 : 0;
    final b = parts.length > 1 ? parts[1] ?? 100 : 100;
    return (a, b);
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
    required this.pageController,
    required this.pageCount,
    required this.pageBuilder,
    required this.onPageChanged,
    required this.totalGoal,
    required this.currentValue,
    required this.currentRank,
    required this.subtitle,
    required this.onSubmit,
  });

  final double scale;
  final PageController pageController;
  final int pageCount;
  final Widget Function(int index) pageBuilder;
  final ValueChanged<int> onPageChanged;
  final int totalGoal;
  final int currentValue;
  final int currentRank;
  final String subtitle;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: TrackSideLayoutKeys.hero,
      height: 464 * scale,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _HeroBackground(scale: scale),
          Positioned(
            left: 26 * scale,
            top: 31 * scale,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 20 * scale,
                  height: 20 * scale,
                  child: ClipRect(
                    child: OverflowBox(
                      maxWidth: 40 * scale,
                      maxHeight: 40 * scale,
                      child: Image.asset(
                        'assets/branding/trans.png',
                        height: 40 * scale,
                        errorBuilder: (context, error, stackTrace) =>
                            SizedBox(height: 20 * scale),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 7 * scale),
                Text(
                  'NUVO',
                  style: AppTextStyles.labelLarge.copyWith(
                    color: _kWhite,
                    fontSize: 11 * scale,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.8,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            right: 26 * scale,
            top: 38 * scale,
            child: Text(
              'ARENA',
              style: AppTextStyles.labelSmall.copyWith(
                color: _kBlue,
                fontSize: 12 * scale,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 83 * scale,
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
            top: 119 * scale,
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
            top: 150 * scale,
            height: 230 * scale,
            child: PageView.builder(
              controller: pageController,
              onPageChanged: onPageChanged,
              itemCount: pageCount,
              itemBuilder: (context, index) => pageBuilder(index),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 389 * scale,
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
                      fontSize: 14 * scale,
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
                center: const Alignment(0.0, 1.0),
                radius: 1.35,
                colors: [
                  const Color(0xFF154E91).withValues(alpha: 0.38),
                  _kNavy,
                ],
                stops: const [0.0, 0.70],
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

class _StandingsAndActivityPanel extends StatelessWidget {
  const _StandingsAndActivityPanel({
    required this.scale,
    required this.minHeight,
    required this.board,
    this.race,
    required this.myUserId,
    required this.activity,
  });

  final double scale;
  final double minHeight;
  final ArenaBoard board;
  final Race? race;
  final String myUserId;
  final List<ArenaActivity> activity;

  @override
  Widget build(BuildContext context) {
    final firstActivity = activity.isNotEmpty ? activity.first : null;

    return Container(
      key: TrackSideLayoutKeys.panel,
      color: _kWarmWhite,
      constraints: BoxConstraints(minHeight: minHeight),
      padding: EdgeInsets.fromLTRB(
        26 * scale,
        26 * scale,
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
          SizedBox(height: 16 * scale),
          NuvoLeaderboard(entries: _buildLeaderboardEntries(board)),
          SizedBox(height: 30 * scale),
          KeyedSubtree(
            key: TrackSideLayoutKeys.recentActivity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'RECENT ACTIVITY',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: _kMutedText,
                    fontSize: 11 * scale,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                SizedBox(height: 12 * scale),
                if (firstActivity != null)
                  _ActivityRow(
                    scale: scale,
                    activity: firstActivity,
                    myUserId: myUserId,
                  )
                else
                  SizedBox(
                    height: 28 * scale,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'No proof submitted yet',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: _kMutedText,
                          fontSize: 14 * scale,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<NuvoLeaderboardEntry> _buildLeaderboardEntries(ArenaBoard board) {
    final rows = board.miniLeaderboard;
    return rows.asMap().entries.map((e) {
      final row = e.value;
      final rank = e.key + 1;
      final isUser = row.isCurrentUser || row.label == 'You';
      return NuvoLeaderboardEntry(
        id: row.label,
        rank: rank,
        name: isUser ? 'You' : row.label,
        value: row.value,
        initials: _initials(isUser ? 'You' : row.label),
        photoUrl: row.profilePhotoUrl,
        isCurrentUser: isUser,
        isLeader: rank == 1,
      );
    }).toList();
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

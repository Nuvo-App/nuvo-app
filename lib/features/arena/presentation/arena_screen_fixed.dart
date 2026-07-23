import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/nuvo_preview_style.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_avatar.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_icons.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../../core/widgets/race_ring.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../races/data/race_models.dart';
import '../../races/domain/chase_context.dart';
import '../../races/domain/camera_verification_resolver.dart';
import '../../races/domain/race_display.dart';
import '../../races/presentation/race_controller.dart';
import '../data/arena_models.dart';
import 'arena_controller.dart';

/// Fixed-data visual QA wrapper for the compile-time conference preview.
///
/// It renders the real focus-board implementation and is not referenced by
/// production routing.
class ArenaStylePreview extends StatelessWidget {
  const ArenaStylePreview({super.key});

  static const _board = ArenaBoard(
    id: 'conference-preview',
    source: 'demo',
    title: 'First to 100 Pushups',
    proofLabel: 'Camera verified',
    progressLabel: '65 / 100 reps',
    boardContext: '4 racers on the board',
    primaryActionLabel: 'Submit proof',
    primaryActionType: 'submit_proof',
    progressPercent: 65,
    racerCount: 4,
    isResult: false,
    myRank: 1,
    chaseCopy: 'Alex is 7 behind',
    daysLeft: 4,
    miniLeaderboard: [
      ArenaMiniLeaderboardRow(
        label: 'You',
        value: '65 / 100',
        isCurrentUser: true,
      ),
      ArenaMiniLeaderboardRow(label: 'Alex R.', value: '58 / 100'),
      ArenaMiniLeaderboardRow(label: 'Jordan K.', value: '42 / 100'),
    ],
  );
  static const _participants = [
    RaceParticipant(
      id: 'preview-you',
      userId: 'preview-you',
      displayName: 'You',
      progressValue: 65,
      progressPercent: 65,
      rank: 1,
      joinedAt: '2026-07-23T00:00:00Z',
    ),
    RaceParticipant(
      id: 'preview-alex',
      userId: 'preview-alex',
      displayName: 'Alex R.',
      progressValue: 58,
      progressPercent: 58,
      rank: 2,
      joinedAt: '2026-07-23T00:00:00Z',
    ),
    RaceParticipant(
      id: 'preview-jordan',
      userId: 'preview-jordan',
      displayName: 'Jordan K.',
      progressValue: 42,
      progressPercent: 42,
      rank: 3,
      joinedAt: '2026-07-23T00:00:00Z',
    ),
    RaceParticipant(
      id: 'preview-maya',
      userId: 'preview-maya',
      displayName: 'Maya L.',
      progressValue: 31,
      progressPercent: 31,
      rank: 4,
      joinedAt: '2026-07-23T00:00:00Z',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final visual = NuvoVisualTheme.of(context);
    final horizontal = visual.style == NuvoPreviewStyle.trackside ? 0.0 : 22.0;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontal),
            child: const _FocusBoardCard(
              board: _board,
              isLoading: false,
              currentUserId: 'preview-you',
              currentUserInitials: 'SP',
              participants: _participants,
              onLogMove: _noop,
              onOpen: _noop,
            ),
          ),
        ],
      ),
    );
  }

  static void _noop() {}
}

class ArenaScreen extends ConsumerStatefulWidget {
  const ArenaScreen({super.key});

  @override
  ConsumerState<ArenaScreen> createState() => _ArenaScreenState();
}

class _ArenaScreenState extends ConsumerState<ArenaScreen> {
  String? _selectedBoardId;
  ArenaBoard? _scoreCenterBoard;
  List<RaceParticipant>? _scoreCenterParticipants;
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
    final visual = NuvoVisualTheme.of(context);
    final user = ref.watch(authControllerProvider).user;
    final arenaState = ref.watch(arenaControllerProvider);
    final raceState = ref.watch(raceControllerProvider);
    final snapshot = arenaState.snapshot;
    final cameraRaceById = {
      for (final race in raceState.races)
        if (resolveCameraVerification(race).isCameraVerifiable) race.id: race,
    };

    ref.listen<ArenaState>(arenaControllerProvider, (prev, next) {
      if (next.snapshot != null && next.snapshot != prev?.snapshot) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _selectedBoardId = next.snapshot!.focusBoard?.id;
            _scoreCenterBoard = null;
            _scoreCenterParticipants = null;
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
          ].where((board) => cameraRaceById.containsKey(board.id)).toList();

    final resolvedId =
        _selectedBoardId ?? (allBoards.isEmpty ? null : allBoards.first.id);
    final activeBoard =
        (_scoreCenterBoard != null &&
            cameraRaceById.containsKey(_scoreCenterBoard!.id))
        ? _scoreCenterBoard
        : (allBoards.isEmpty ? null : allBoards.first);
    final otherBoards = allBoards
        .where((board) => board.id != resolvedId)
        .toList();
    final focusPadding = visual.style == NuvoPreviewStyle.trackside
        ? const EdgeInsets.fromLTRB(0, 0, 0, 128)
        : const EdgeInsets.fromLTRB(22, 0, 22, 128);
    return Scaffold(
      backgroundColor: visual.page,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: NuvoColors.blue,
          backgroundColor: NuvoColors.surface,
          displacement: 20,
          onRefresh: () =>
              ref.read(arenaControllerProvider.notifier).loadSnapshot(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if ((arenaState.loading && snapshot == null) ||
                  (raceState.loading && raceState.races.isEmpty))
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _LoadingState(),
                )
              else if (arenaState.error != null && snapshot == null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
                    child: _ErrorState(
                      message: arenaState.error!,
                      onRetry: () => ref
                          .read(arenaControllerProvider.notifier)
                          .loadSnapshot(),
                    ),
                  ),
                )
              else if (snapshot == null ||
                  snapshot.isEmpty ||
                  allBoards.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
                    child: _EmptyState(
                      onStart: () => context.push('/races/new'),
                      onJoin: () => context.push('/races/join'),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: focusPadding,
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      if (activeBoard != null)
                        AnimatedSize(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topCenter,
                          clipBehavior: Clip.none,
                          child: _FocusBoardCard(
                            key: ValueKey(activeBoard.id),
                            board: activeBoard,
                            isLoading: _isLoadingBoardDetail,
                            currentUserId: user?.id,
                            currentUserPhotoUrl: user?.profilePhotoUrl,
                            currentUserInitials: initials,
                            participants:
                                _scoreCenterParticipants ??
                                cameraRaceById[activeBoard.id]?.participants,
                            onLogMove: () => _handlePrimaryAction(
                              context,
                              activeBoard,
                              cameraRaceById,
                            ),
                            onOpen: () => _openBoard(context, activeBoard),
                          ),
                        ),
                      if (allBoards.length > 1) ...[
                        const SizedBox(height: 20),
                        _RaceChipRow(
                          boards: allBoards,
                          selectedId: resolvedId,
                          onTap: (b) => _onChipTap(b, snapshot, user?.id),
                        ),
                      ],
                      if (otherBoards.isNotEmpty) ...[
                        const SizedBox(height: 32),
                        const _SectionLabel(label: 'More races'),
                        const SizedBox(height: 14),
                        for (final board in otherBoards) ...[
                          _CompactBoardRow(
                            board: board,
                            onTap: () => _onChipTap(board, snapshot, user?.id),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ],
                      if (snapshot.activity.isNotEmpty) ...[
                        const SizedBox(height: 34),
                        const _SectionLabel(label: 'Around your crew'),
                        const SizedBox(height: 14),
                        _ActivityFeed(activity: snapshot.activity),
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
        _scoreCenterParticipants = null;
        _isLoadingBoardDetail = false;
      });
      return;
    }

    setState(() {
      _selectedBoardId = board.id;
      _scoreCenterBoard = board;
      _scoreCenterParticipants = null;
      _isLoadingBoardDetail = true;
    });

    try {
      final race = await ref
          .read(raceControllerProvider.notifier)
          .getRaceDetail(board.id);
      if (!mounted) return;
      final eligibility = resolveCameraVerification(race);
      debugLogCameraVerificationDecision(
        race,
        eligibility,
        routeAction: 'arena_chip_select',
      );
      if (!eligibility.isCameraVerifiable) {
        setState(() {
          _scoreCenterBoard = null;
          _scoreCenterParticipants = null;
          _isLoadingBoardDetail = false;
        });
        return;
      }
      setState(() {
        _scoreCenterBoard = _boardFromRace(race, userId);
        _scoreCenterParticipants = race.participants;
        _isLoadingBoardDetail = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingBoardDetail = false);
    }
  }

  ArenaBoard _boardFromRace(Race race, String? userId) {
    final sorted = serverRankedParticipants(race);
    final miniLeaderboard = sorted.take(5).map((p) {
      final isUser = userId != null && p.userId == userId;
      return ArenaMiniLeaderboardRow(
        label: isUser ? 'You' : p.displayName,
        value: raceProgressLabel(race, p),
        isCurrentUser: isUser,
        profilePhotoUrl: p.profilePhotoUrl,
      );
    }).toList();

    final myPart = userId != null ? race.participantFor(userId) : null;
    final myProgress = raceProgressPercent(race, myPart);
    final isResult = raceIsCompleted(race);
    final count = race.participantCount;
    final boardContext = isResult
        ? '$count ${count == 1 ? 'racer' : 'racers'} finished'
        : count <= 1
        ? 'Solo · add crew from the race room'
        : '$count ${count == 1 ? 'racer' : 'racers'} on the board';

    final eligibility = resolveCameraVerification(race);
    final chase = ChaseContext.compute(race, userId ?? '');

    return ArenaBoard(
      id: race.id,
      source: 'real',
      title: race.title,
      proofLabel: eligibility.movementDefinition?.title ?? 'Camera',
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
      badgeLabel: eligibility.movementDefinition?.title,
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

  void _handlePrimaryAction(
    BuildContext context,
    ArenaBoard board,
    Map<String, Race> cameraRaceById,
  ) {
    if (board.isDemo) {
      _demoSnack(context);
      return;
    }
    final race = cameraRaceById[board.id];
    if (race != null) {
      debugLogCameraVerificationDecision(
        race,
        resolveCameraVerification(race),
        routeAction: 'arena_primary_action_${board.primaryActionType}',
      );
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

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final visual = NuvoVisualTheme.of(context);
    return Text(
      label,
      style: AppTextStyles.titleMedium.copyWith(
        color: visual.ink,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.25,
      ),
    );
  }
}

// ── Focus board card ──────────────────────────────────────────────────────────

class _FocusBoardCard extends StatelessWidget {
  const _FocusBoardCard({
    super.key,
    required this.board,
    required this.isLoading,
    required this.onLogMove,
    required this.onOpen,
    this.currentUserId,
    this.currentUserPhotoUrl,
    this.currentUserInitials,
    this.participants,
  });

  final ArenaBoard board;
  final bool isLoading;
  final VoidCallback onLogMove;
  final VoidCallback onOpen;
  final String? currentUserId;
  final String? currentUserPhotoUrl;
  final String? currentUserInitials;
  final List<RaceParticipant>? participants;

  @override
  Widget build(BuildContext context) {
    final visual = NuvoVisualTheme.of(context);
    final isResult = board.isResult;
    final pct = board.progressPercent ?? 0;
    final ringRacers = (participants ?? const <RaceParticipant>[]).map((p) {
      final isMe = currentUserId != null && p.userId == currentUserId;
      return RingRacer(
        id: p.userId,
        initials: isMe && (currentUserInitials?.isNotEmpty ?? false)
            ? currentUserInitials!
            : _initials(p.displayName),
        progress: p.progressPercent / 100,
        isCurrentUser: isMe,
        photoUrl: isMe
            ? (currentUserPhotoUrl ?? p.profilePhotoUrl)
            : p.profilePhotoUrl,
      );
    }).toList();

    if (visual.style == NuvoPreviewStyle.startingLine) {
      return _StartingLineFocusBoard(
        board: board,
        isLoading: isLoading,
        onLogMove: onLogMove,
        onOpen: onOpen,
        currentUserPhotoUrl: currentUserPhotoUrl,
        currentUserInitials: currentUserInitials,
      );
    }
    if (visual.style == NuvoPreviewStyle.trackside) {
      return _TracksideFocusBoard(
        board: board,
        isLoading: isLoading,
        ringRacers: ringRacers,
        onLogMove: onLogMove,
        onOpen: onOpen,
        currentUserPhotoUrl: currentUserPhotoUrl,
        currentUserInitials: currentUserInitials,
      );
    }
    if (visual.style == NuvoPreviewStyle.crewMomentum) {
      return _CrewFocusBoard(
        board: board,
        isLoading: isLoading,
        ringRacers: ringRacers,
        onLogMove: onLogMove,
        onOpen: onOpen,
        currentUserPhotoUrl: currentUserPhotoUrl,
        currentUserInitials: currentUserInitials,
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
      decoration: BoxDecoration(
        color: visual.surface,
        borderRadius: BorderRadius.circular(visual.cardRadius),
        border: Border.all(color: visual.border),
        boxShadow: null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isLoading)
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: const LinearProgressIndicator(
                color: NuvoColors.blue,
                backgroundColor: NuvoColors.panel,
                minHeight: 3,
              ),
            ),
          if (isLoading) const SizedBox(height: 18),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: isResult ? NuvoColors.success : NuvoColors.blue,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isResult
                          ? Icons.check_rounded
                          : Icons.arrow_outward_rounded,
                      color: NuvoColors.white,
                      size: 13,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isResult ? 'FINISHED' : 'ACTIVE RACE',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: NuvoColors.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.75,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (board.proofLabel case final proof?)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: NuvoColors.surface.withValues(alpha: 0.90),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: NuvoColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.motion_photos_on_outlined,
                        color: NuvoColors.blue,
                        size: 13,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        proof,
                        style: AppTextStyles.labelSmall.copyWith(
                          color: NuvoColors.navy,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Hero(
            tag: 'race-title-${board.id}',
            child: Material(
              color: Colors.transparent,
              child: Text(
                board.title,
                style: AppTextStyles.headlineLarge.copyWith(
                  color: NuvoColors.navy,
                  fontSize: 28,
                  height: 1.08,
                  letterSpacing: -0.7,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            board.boardContext,
            style: AppTextStyles.bodyMedium.copyWith(
              color: NuvoColors.muted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          if (!isResult && !isLoading)
            Row(
              children: [
                RaceRing(
                  progress: pct / 100,
                  centerValue: '$pct%',
                  size: 128,
                  strokeWidth: 11,
                  delay: const Duration(milliseconds: 160),
                  racers: ringRacers,
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your position',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: NuvoColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        board.myRank == null
                            ? 'On the board'
                            : '${_ordinal(board.myRank!)} place',
                        style: AppTextStyles.titleLarge.copyWith(
                          color: NuvoColors.navy,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: pct.clamp(0, 100) / 100,
                          minHeight: 7,
                          color: NuvoColors.actionBlue,
                          backgroundColor: NuvoColors.trackBg,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        board.progressLabel,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: NuvoColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$pct%',
                  style: AppTextStyles.displayMedium.copyWith(
                    color: NuvoColors.navy,
                    fontSize: 46,
                    letterSpacing: -1.5,
                  ),
                ),
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(
                    isResult ? 'complete' : 'your progress',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: NuvoColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          if (board.chaseCopy case final chase?) ...[
            const SizedBox(height: 12),
            Text(
              chase,
              style: AppTextStyles.bodySmall.copyWith(
                color: NuvoColors.textMuted,
              ),
            ),
          ],
          if (board.miniLeaderboard.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                NuvoAvatarStack(
                  avatars: board.miniLeaderboard.map((row) {
                    final initials = row.isCurrentUser
                        ? (currentUserInitials ?? _initials(row.label))
                        : _initials(row.label);
                    final photo = row.isCurrentUser
                        ? (currentUserPhotoUrl ?? row.profilePhotoUrl)
                        : row.profilePhotoUrl;
                    return (initials: initials, photoUrl: photo);
                  }).toList(),
                  total: board.racerCount ?? board.miniLeaderboard.length,
                  size: 25,
                  max: 4,
                  borderColor: NuvoColors.surface,
                ),
                const SizedBox(width: 10),
                Text(
                  '${board.racerCount ?? board.miniLeaderboard.length} on the start line',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: NuvoColors.textMuted,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 26),
          Row(
            children: [
              Text(
                'Leaderboard',
                style: AppTextStyles.titleMedium.copyWith(
                  color: NuvoColors.navy,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (board.daysLeft != null)
                Text(
                  '${board.daysLeft} days left',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: NuvoColors.textMuted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: visual.surfaceMuted.withValues(alpha: 0.62),
              borderRadius: BorderRadius.circular(visual.cardRadius),
              border: Border.all(color: visual.border),
            ),
            child: Column(
              children: [
                if (isLoading)
                  ..._buildSkeletonRows()
                else
                  for (var i = 0; i < board.miniLeaderboard.length; i++) ...[
                    _LeaderboardRow(
                      rank: i + 1,
                      label: board.miniLeaderboard[i].label,
                      value: board.miniLeaderboard[i].value,
                      isCurrentUser: board.miniLeaderboard[i].isCurrentUser,
                      photoUrl: board.miniLeaderboard[i].isCurrentUser
                          ? (currentUserPhotoUrl ??
                                board.miniLeaderboard[i].profilePhotoUrl)
                          : board.miniLeaderboard[i].profilePhotoUrl,
                      initialsOverride: board.miniLeaderboard[i].isCurrentUser
                          ? currentUserInitials
                          : null,
                    ),
                    if (i < board.miniLeaderboard.length - 1)
                      const SizedBox(height: 3),
                  ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          isResult
              ? NuvoOutlineButton(
                  label: 'Open board',
                  icon: Icons.arrow_forward_rounded,
                  expand: true,
                  onPressed: onOpen,
                )
              : NuvoPrimaryButton(
                  label: board.primaryActionLabel,
                  icon: Icons.arrow_forward_rounded,
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
            _Skel(width: 24, height: 24, radius: 12),
            SizedBox(width: 8),
            _Skel(width: 24, height: 24, radius: 12),
            SizedBox(width: 10),
            _Skel(width: 80, height: 10, radius: 4),
            Spacer(),
            _Skel(width: 36, height: 10, radius: 4),
          ],
        ),
        if (i < 2) const SizedBox(height: 8),
      ],
    ];
  }
}

class _StartingLineFocusBoard extends StatelessWidget {
  const _StartingLineFocusBoard({
    required this.board,
    required this.isLoading,
    required this.onLogMove,
    required this.onOpen,
    this.currentUserPhotoUrl,
    this.currentUserInitials,
  });

  final ArenaBoard board;
  final bool isLoading;
  final VoidCallback onLogMove;
  final VoidCallback onOpen;
  final String? currentUserPhotoUrl;
  final String? currentUserInitials;

  @override
  Widget build(BuildContext context) {
    final visual = NuvoVisualTheme.of(context);
    final pct = board.progressPercent ?? 0;
    final score = _ProgressScore.parse(board.progressLabel, fallback: pct);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 22, 0, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _NuvoLockup(),
          const SizedBox(height: 34),
          Text(
            'Your next move',
            style: AppTextStyles.headlineLarge.copyWith(
              color: visual.ink,
              fontSize: 31,
              letterSpacing: -0.9,
            ),
          ),
          const SizedBox(height: 34),
          Text(
            board.isResult ? 'FINISH LINE' : 'ACTIVE RACE',
            style: AppTextStyles.labelUppercase(10, color: visual.mutedInk),
          ),
          const SizedBox(height: 14),
          Text(
            board.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.headlineLarge.copyWith(
              color: visual.ink,
              fontSize: 29,
            ),
          ),
          const SizedBox(height: 16),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: score.current,
                  style: AppTextStyles.number(
                    44,
                    color: visual.action,
                    weight: FontWeight.w700,
                  ),
                ),
                TextSpan(
                  text: ' / ${score.goal}',
                  style: AppTextStyles.number(
                    44,
                    color: visual.ink,
                    weight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 11),
          Text(
            score.remainingLabel,
            style: AppTextStyles.bodyMedium.copyWith(color: visual.mutedInk),
          ),
          const SizedBox(height: 30),
          _StartingTrack(progress: pct / 100),
          const SizedBox(height: 27),
          board.isResult
              ? NuvoOutlineButton(
                  label: 'Open board',
                  expand: true,
                  onPressed: onOpen,
                )
              : _SourceActionButton(
                  label: board.primaryActionLabel,
                  onTap: onLogMove,
                ),
          const SizedBox(height: 31),
          Row(
            children: [
              Text(
                'LEADERBOARD',
                style: AppTextStyles.labelUppercase(10, color: visual.mutedInk),
              ),
              const Spacer(),
              Text(
                'Top ${math.min(3, board.miniLeaderboard.length)}',
                style: AppTextStyles.labelSmall.copyWith(
                  color: visual.mutedInk,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _FlatLeaderboard(
            board: board,
            isLoading: isLoading,
            currentUserPhotoUrl: currentUserPhotoUrl,
            currentUserInitials: currentUserInitials,
            title: 'Leaderboard',
            contentPadding: EdgeInsets.zero,
            showTitle: false,
            highlightCurrentUser: false,
            scoreOnly: true,
          ),
          if (board.isDemo) ...[
            const SizedBox(height: 20),
            Divider(color: visual.border),
            const SizedBox(height: 13),
            Text(
              'RECENT ACTIVITY',
              style: AppTextStyles.labelUppercase(10, color: visual.mutedInk),
            ),
            const SizedBox(height: 12),
            _SourceActivityRow(
              initials: currentUserInitials ?? 'YOU',
              text: 'You logged 20 pushups',
            ),
          ],
        ],
      ),
    );
  }
}

class _StartingTrack extends StatelessWidget {
  const _StartingTrack({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final visual = NuvoVisualTheme.of(context);
    return SizedBox(
      height: 28,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final lineWidth = constraints.maxWidth - 24;
          return Stack(
            alignment: Alignment.centerLeft,
            children: [
              Positioned(
                left: 3,
                right: 20,
                child: Container(height: 2, color: visual.border),
              ),
              Positioned(
                left: 3,
                width: lineWidth * progress.clamp(0, 1),
                child: Container(height: 3, color: visual.action),
              ),
              for (var i = 0; i < 7; i++)
                Positioned(
                  left: 3 + (lineWidth * (i / 6)) - 4,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: (i / 6) <= progress
                          ? visual.action
                          : visual.border,
                      border: i == (progress * 6).round()
                          ? Border.all(color: visual.surface, width: 2)
                          : null,
                    ),
                  ),
                ),
              Positioned(right: 0, child: _FinishLine(color: visual.mutedInk)),
            ],
          );
        },
      ),
    );
  }
}

class _FinishLine extends StatelessWidget {
  const _FinishLine({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 22,
      child: CustomPaint(painter: _FinishLinePainter(color)),
    );
  }
}

class _FinishLinePainter extends CustomPainter {
  const _FinishLinePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final pole = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    canvas.drawLine(const Offset(2, 1), Offset(2, size.height), pole);
    final cell = size.width / 4;
    final paint = Paint();
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 3; col++) {
        paint.color = (row + col).isEven
            ? color
            : color.withValues(alpha: 0.10);
        canvas.drawRect(
          Rect.fromLTWH(3 + col * cell, 1 + row * cell, cell, cell),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FinishLinePainter oldDelegate) =>
      color != oldDelegate.color;
}

class _TracksideFocusBoard extends StatelessWidget {
  const _TracksideFocusBoard({
    required this.board,
    required this.isLoading,
    required this.ringRacers,
    required this.onLogMove,
    required this.onOpen,
    this.currentUserPhotoUrl,
    this.currentUserInitials,
  });

  final ArenaBoard board;
  final bool isLoading;
  final List<RingRacer> ringRacers;
  final VoidCallback onLogMove;
  final VoidCallback onOpen;
  final String? currentUserPhotoUrl;
  final String? currentUserInitials;

  @override
  Widget build(BuildContext context) {
    final visual = NuvoVisualTheme.of(context);
    final pct = board.progressPercent ?? 0;
    final score = _ProgressScore.parse(board.progressLabel, fallback: pct);
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: visual.hero,
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
          child: Column(
            children: [
              _NuvoLockup(
                inverse: true,
                trailing: 'ARENA',
                trailingColor: visual.action,
              ),
              const SizedBox(height: 28),
              Text(
                'Your next move',
                style: AppTextStyles.headlineLarge.copyWith(
                  color: visual.onHero,
                  fontSize: 27,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                board.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: visual.onHero.withValues(alpha: 0.68),
                ),
              ),
              const SizedBox(height: 16),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: score.current,
                      style: AppTextStyles.number(
                        54,
                        color: visual.action,
                        weight: FontWeight.w700,
                      ),
                    ),
                    TextSpan(
                      text: ' / ${score.goal}',
                      style: AppTextStyles.number(
                        54,
                        color: visual.onHero,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 7),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${score.remaining}',
                      style: AppTextStyles.titleMedium.copyWith(
                        color: visual.action,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextSpan(
                      text: ' to the finish line',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: visual.onHero.withValues(alpha: 0.72),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              _TracksideRaceCourse(progress: pct / 100, racers: ringRacers),
              const SizedBox(height: 10),
              board.isResult
                  ? NuvoOutlineButton(
                      label: 'Open board',
                      expand: true,
                      onPressed: onOpen,
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 52),
                      child: _SourceActionButton(
                        label: board.primaryActionLabel,
                        onTap: onLogMove,
                      ),
                    ),
            ],
          ),
        ),
        Container(
          color: visual.surface,
          padding: const EdgeInsets.fromLTRB(22, 21, 22, 18),
          child: Column(
            children: [
              Row(
                children: [
                  Text(
                    'CREW STANDINGS',
                    style: AppTextStyles.labelUppercase(
                      10,
                      color: visual.mutedInk,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'VIEW ALL',
                    style: AppTextStyles.labelUppercase(
                      9,
                      color: visual.action,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              _FlatLeaderboard(
                board: board,
                isLoading: isLoading,
                currentUserPhotoUrl: currentUserPhotoUrl,
                currentUserInitials: currentUserInitials,
                title: 'Crew standings',
                contentPadding: EdgeInsets.zero,
                showTitle: false,
                highlightCurrentUser: false,
                showProgressLines: true,
              ),
              if (board.isDemo) ...[
                const SizedBox(height: 16),
                Divider(color: visual.border),
                const SizedBox(height: 13),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'RECENT ACTIVITY',
                    style: AppTextStyles.labelUppercase(
                      10,
                      color: visual.mutedInk,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const _SourceActivityRow(
                  initials: 'ML',
                  text: 'Maya L. submitted 20 pushups',
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _CrewFocusBoard extends StatelessWidget {
  const _CrewFocusBoard({
    required this.board,
    required this.isLoading,
    required this.ringRacers,
    required this.onLogMove,
    required this.onOpen,
    this.currentUserPhotoUrl,
    this.currentUserInitials,
  });

  final ArenaBoard board;
  final bool isLoading;
  final List<RingRacer> ringRacers;
  final VoidCallback onLogMove;
  final VoidCallback onOpen;
  final String? currentUserPhotoUrl;
  final String? currentUserInitials;

  @override
  Widget build(BuildContext context) {
    final visual = NuvoVisualTheme.of(context);
    final pct = board.progressPercent ?? 0;
    final score = _ProgressScore.parse(board.progressLabel, fallback: pct);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 20, 0, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _NuvoLockup(trailing: 'Arena'),
          const SizedBox(height: 12),
          Divider(color: visual.border),
          const SizedBox(height: 20),
          Text(
            board.isResult ? 'FINISH LINE' : 'YOUR NEXT MOVE',
            style: AppTextStyles.labelUppercase(10, color: visual.mutedInk),
          ),
          const SizedBox(height: 8),
          Text(
            board.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.headlineLarge.copyWith(color: visual.ink),
          ),
          const SizedBox(height: 20),
          Center(
            child: _CrewProgressOrbit(
              progress: pct / 100,
              current: score.current,
              goal: score.goal,
              remainingLabel: score.remainingLabel,
              racers: ringRacers,
              size: 320,
            ),
          ),
          const SizedBox(height: 30),
          board.isResult
              ? NuvoOutlineButton(
                  label: 'Open board',
                  expand: true,
                  onPressed: onOpen,
                )
              : _SourceActionButton(
                  label: board.primaryActionLabel,
                  onTap: onLogMove,
                ),
          const SizedBox(height: 17),
          Divider(color: visual.border),
          const SizedBox(height: 8),
          _FlatLeaderboard(
            board: board,
            isLoading: isLoading,
            currentUserPhotoUrl: currentUserPhotoUrl,
            currentUserInitials: currentUserInitials,
            title: 'Leaderboard',
            contentPadding: EdgeInsets.zero,
            showProgressLines: true,
            highlightCurrentUser: false,
            dense: true,
            showTitle: false,
          ),
          if (board.isDemo) ...[
            const SizedBox(height: 14),
            Divider(color: visual.border),
            const SizedBox(height: 12),
            const _SourceActivityRow(
              initials: 'AR',
              text: 'Alex submitted 20 pushups',
            ),
          ],
        ],
      ),
    );
  }
}

class _SourceActionButton extends StatelessWidget {
  const _SourceActionButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visual = NuvoVisualTheme.of(context);
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: visual.action,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        child: Text(
          label,
          style: AppTextStyles.labelLarge.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _NuvoLockup extends StatelessWidget {
  const _NuvoLockup({this.inverse = false, this.trailing, this.trailingColor});

  final bool inverse;
  final String? trailing;
  final Color? trailingColor;

  @override
  Widget build(BuildContext context) {
    final visual = NuvoVisualTheme.of(context);
    final ink = inverse ? visual.onHero : visual.ink;
    return Row(
      children: [
        SizedBox.square(
          dimension: 29,
          child: ClipRect(
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(ink, BlendMode.srcIn),
              child: Transform.scale(
                scale: 2,
                child: Image.asset(
                  'assets/branding/trans.png',
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 7),
        Text(
          'NUVO',
          style: AppTextStyles.labelLarge.copyWith(
            color: ink,
            fontWeight: FontWeight.w800,
            letterSpacing: 3.2,
          ),
        ),
        const Spacer(),
        if (trailing != null)
          Text(
            trailing!,
            style: AppTextStyles.labelSmall.copyWith(
              color: trailingColor ?? ink,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }
}

class _ProgressScore {
  const _ProgressScore({required this.current, required this.goal});

  final String current;
  final String goal;

  int get _currentNumber => int.tryParse(current) ?? 0;
  int get _goalNumber => int.tryParse(goal) ?? 100;
  int get remaining => math.max(0, _goalNumber - _currentNumber);
  String get remainingLabel => '$remaining to the finish line';

  static _ProgressScore parse(String raw, {required int fallback}) {
    final matches = RegExp(r'\d+').allMatches(raw).toList();
    if (matches.length >= 2) {
      return _ProgressScore(
        current: matches[0].group(0)!,
        goal: matches[1].group(0)!,
      );
    }
    return _ProgressScore(current: '$fallback', goal: '100');
  }
}

class _TracksideRaceCourse extends StatelessWidget {
  const _TracksideRaceCourse({required this.progress, required this.racers});

  final double progress;
  final List<RingRacer> racers;

  @override
  Widget build(BuildContext context) {
    final visible = racers.take(3).toList();
    return Semantics(
      label:
          'Race track. Your progress is ${(progress * 100).round()} percent.',
      child: Transform.translate(
        offset: const Offset(0, -42),
        child: SizedBox(
          height: 141,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final placements = <Offset>[
                Offset(constraints.maxWidth * 0.50, 147),
                Offset(constraints.maxWidth * 0.18, 86),
                Offset(constraints.maxWidth * 0.82, 86),
              ];
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _TracksideCoursePainter(progress),
                    ),
                  ),
                  for (var i = 0; i < visible.length; i++)
                    Positioned(
                      left: placements[i].dx - 20,
                      top: placements[i].dy - 20,
                      child: _TrackRacerMarker(racer: visible[i], rank: i + 1),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TracksideCoursePainter extends CustomPainter {
  const _TracksideCoursePainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final neutral = Paint()
      ..color = Colors.white.withValues(alpha: 0.13)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (var i = 0; i < 5; i++) {
      final inset = i * 13.0;
      final rect = Rect.fromLTWH(
        7 + inset,
        -180 + inset * 0.25,
        size.width - 14 - inset * 2,
        360 - inset * 0.55,
      );
      canvas.drawArc(rect, 0, math.pi, false, neutral);
    }

    final outer = Rect.fromLTWH(7, -180, size.width - 14, 360);
    final active = Paint()
      ..color = const Color(0xFF327BFF)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt
      ..strokeWidth = 13;
    final sweep = math.pi * progress.clamp(0.0, 1.0);
    canvas.drawArc(outer, 0, sweep, false, active);
  }

  @override
  bool shouldRepaint(covariant _TracksideCoursePainter oldDelegate) =>
      progress != oldDelegate.progress;
}

class _TrackRacerMarker extends StatelessWidget {
  const _TrackRacerMarker({required this.racer, required this.rank});

  final RingRacer racer;
  final int rank;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        NuvoAvatar(
          initials: racer.initials,
          photoUrl: racer.photoUrl,
          size: 40,
          bgColor: nuvoAvatarColorFor(racer.id),
          textColor: Colors.white,
          borderColor: Colors.white,
          borderWidth: 2,
        ),
        Transform.translate(
          offset: const Offset(0, -4),
          child: Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFF327BFF),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$rank',
              style: AppTextStyles.labelSmall.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 9,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CrewProgressOrbit extends StatelessWidget {
  const _CrewProgressOrbit({
    required this.progress,
    required this.current,
    required this.goal,
    required this.remainingLabel,
    required this.racers,
    required this.size,
  });

  final double progress;
  final String current;
  final String goal;
  final String remainingLabel;
  final List<RingRacer> racers;
  final double size;

  @override
  Widget build(BuildContext context) {
    final visual = NuvoVisualTheme.of(context);
    final visible = racers.take(4).toList();
    final center = size / 2;
    final placements = <Offset>[
      Offset(center, 35),
      Offset(31, center),
      Offset(size - 31, center),
      Offset(center, size - 31),
    ];
    return Semantics(
      label:
          'Crew progress. $current of $goal. $remainingLabel. ${visible.length} crew members shown.',
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _CrewOrbitPainter(
                  progress: progress,
                  active: visual.action,
                  inactive: visual.border,
                ),
              ),
            ),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: current,
                    style: AppTextStyles.number(
                      48,
                      color: visual.ink,
                      weight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(
                    text: ' / $goal',
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: visual.mutedInk,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: center + 28,
              child: Text(
                remainingLabel,
                style: AppTextStyles.bodySmall.copyWith(
                  color: visual.mutedInk,
                  fontSize: 11,
                ),
              ),
            ),
            for (var i = 0; i < visible.length; i++)
              Positioned(
                left: placements[i].dx - 27,
                top: placements[i].dy - 27,
                child: _OrbitRacerMarker(
                  racer: visible[i],
                  rank: i + 1,
                  top: i == 0,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CrewOrbitPainter extends CustomPainter {
  const _CrewOrbitPainter({
    required this.progress,
    required this.active,
    required this.inactive,
  });

  final double progress;
  final Color active;
  final Color inactive;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * 0.33;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2,
      false,
      Paint()
        ..color = inactive
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      -math.pi * 2 * progress.clamp(0.0, 1.0),
      false,
      Paint()
        ..color = active
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 5,
    );
  }

  @override
  bool shouldRepaint(covariant _CrewOrbitPainter oldDelegate) =>
      progress != oldDelegate.progress ||
      active != oldDelegate.active ||
      inactive != oldDelegate.inactive;
}

class _OrbitRacerMarker extends StatelessWidget {
  const _OrbitRacerMarker({
    required this.racer,
    required this.rank,
    required this.top,
  });

  final RingRacer racer;
  final int rank;
  final bool top;

  @override
  Widget build(BuildContext context) {
    final visual = NuvoVisualTheme.of(context);
    return SizedBox(
      width: 54,
      height: 70,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          NuvoAvatar(
            initials: racer.initials,
            photoUrl: racer.photoUrl,
            size: 54,
            bgColor: nuvoAvatarColorFor(racer.id),
            textColor: Colors.white,
            borderColor: top ? visual.action : visual.surface,
            borderWidth: top ? 2 : 1.5,
          ),
          Positioned(
            bottom: 3,
            child: Container(
              height: 22,
              constraints: const BoxConstraints(minWidth: 22),
              padding: const EdgeInsets.symmetric(horizontal: 5),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: top ? visual.action : visual.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: visual.border),
              ),
              child: Text(
                top ? '${(racer.progress * 100).round()}' : '$rank',
                style: AppTextStyles.labelSmall.copyWith(
                  color: top ? Colors.white : visual.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 9,
                ),
              ),
            ),
          ),
          if (top)
            Positioned(
              top: -18,
              child: Text(
                'You',
                style: AppTextStyles.labelSmall.copyWith(
                  color: visual.action,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SourceActivityRow extends StatelessWidget {
  const _SourceActivityRow({required this.initials, required this.text});

  final String initials;
  final String text;

  @override
  Widget build(BuildContext context) {
    final visual = NuvoVisualTheme.of(context);
    return Row(
      children: [
        NuvoAvatar(
          initials: initials,
          size: 28,
          bgColor: nuvoAvatarColorFor(initials),
          textColor: Colors.white,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodySmall.copyWith(color: visual.ink),
          ),
        ),
        Text(
          '2m ago',
          style: AppTextStyles.labelSmall.copyWith(color: visual.mutedInk),
        ),
      ],
    );
  }
}

class _FlatLeaderboard extends StatelessWidget {
  const _FlatLeaderboard({
    required this.board,
    required this.isLoading,
    required this.currentUserPhotoUrl,
    required this.currentUserInitials,
    required this.title,
    this.contentPadding = const EdgeInsets.fromLTRB(18, 18, 18, 16),
    this.showTitle = true,
    this.highlightCurrentUser = true,
    this.showProgressLines = false,
    this.dense = false,
    this.scoreOnly = false,
  });

  final ArenaBoard board;
  final bool isLoading;
  final String? currentUserPhotoUrl;
  final String? currentUserInitials;
  final String title;
  final EdgeInsets contentPadding;
  final bool showTitle;
  final bool highlightCurrentUser;
  final bool showProgressLines;
  final bool dense;
  final bool scoreOnly;

  @override
  Widget build(BuildContext context) {
    final visual = NuvoVisualTheme.of(context);
    return Padding(
      padding: contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showTitle) ...[
            Text(
              title.toUpperCase(),
              style: AppTextStyles.labelUppercase(10, color: visual.mutedInk),
            ),
            const SizedBox(height: 10),
          ],
          if (isLoading)
            ..._FocusBoardCard._buildSkeletonRows()
          else
            for (var i = 0; i < board.miniLeaderboard.length; i++) ...[
              _LeaderboardRow(
                rank: i + 1,
                label: board.miniLeaderboard[i].label,
                value: board.miniLeaderboard[i].value,
                isCurrentUser: board.miniLeaderboard[i].isCurrentUser,
                photoUrl: board.miniLeaderboard[i].isCurrentUser
                    ? (currentUserPhotoUrl ??
                          board.miniLeaderboard[i].profilePhotoUrl)
                    : board.miniLeaderboard[i].profilePhotoUrl,
                initialsOverride: board.miniLeaderboard[i].isCurrentUser
                    ? currentUserInitials
                    : null,
                highlightCurrentUser: highlightCurrentUser,
                showProgressLine: showProgressLines,
                dense: dense,
                scoreOnly: scoreOnly,
              ),
              if (i < board.miniLeaderboard.length - 1)
                Divider(height: dense ? 2 : 8, color: visual.border),
            ],
        ],
      ),
    );
  }
}

// ── Leaderboard row ───────────────────────────────────────────────────────────

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({
    required this.rank,
    required this.label,
    required this.value,
    required this.isCurrentUser,
    this.photoUrl,
    this.initialsOverride,
    this.highlightCurrentUser = true,
    this.showProgressLine = false,
    this.dense = false,
    this.scoreOnly = false,
  });

  final int rank;
  final String label;
  final String value;
  final bool isCurrentUser;
  final String? photoUrl;
  final String? initialsOverride;
  final bool highlightCurrentUser;
  final bool showProgressLine;
  final bool dense;
  final bool scoreOnly;

  Color? get _rankTierColor => switch (rank) {
    1 => NuvoColors.gold,
    2 => NuvoColors.silver,
    3 => NuvoColors.bronze,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final visual = NuvoVisualTheme.of(context);
    final tierColor = _rankTierColor;
    final avatarColor = isCurrentUser
        ? NuvoColors.navy
        : nuvoAvatarColorFor(label);
    final initials = (initialsOverride != null && initialsOverride!.isNotEmpty)
        ? initialsOverride!
        : _initials(label);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: dense ? 3 : 7),
      decoration: isCurrentUser && highlightCurrentUser
          ? BoxDecoration(
              color: visual.action.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: visual.action.withValues(alpha: 0.18)),
            )
          : null,
      child: Row(
        children: [
          SizedBox(
            width: 18,
            child: Text(
              '$rank',
              style: AppTextStyles.labelMedium.copyWith(
                color: isCurrentUser
                    ? visual.action
                    : tierColor ?? visual.mutedInk,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 8),
          NuvoAvatar(
            initials: initials,
            photoUrl: photoUrl,
            size: 30,
            bgColor: avatarColor,
            textColor: Colors.white,
            borderColor: visual.surface,
            borderWidth: 1.5,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                color: isCurrentUser ? visual.action : visual.ink,
                fontWeight: isCurrentUser ? FontWeight.w700 : FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            scoreOnly ? _scoreFromValue(value) : value,
            style: AppTextStyles.labelSmall.copyWith(
              color: isCurrentUser ? visual.action : visual.ink,
              fontWeight: isCurrentUser ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
          if (showProgressLine) ...[
            const SizedBox(width: 12),
            SizedBox(
              width: 50,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: _progressFromValue(value),
                  minHeight: 3,
                  color: visual.action,
                  backgroundColor: visual.border,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  double _progressFromValue(String raw) {
    final matches = RegExp(r'\d+').allMatches(raw).toList();
    if (matches.length < 2) return 0;
    final current = double.tryParse(matches[0].group(0)!) ?? 0;
    final goal = double.tryParse(matches[1].group(0)!) ?? 100;
    return goal <= 0 ? 0 : (current / goal).clamp(0.0, 1.0);
  }

  String _scoreFromValue(String raw) =>
      RegExp(r'\d+').firstMatch(raw)?.group(0) ?? raw;
}

// ── Skeleton ──────────────────────────────────────────────────────────────────

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
      color: NuvoColors.panel,
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
      clipBehavior: Clip.none,
      padding: const EdgeInsets.only(top: 2, bottom: 6, right: 4),
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
      scale: 0.97,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? NuvoColors.navy : NuvoColors.surface,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: selected ? NuvoColors.navy : NuvoColors.border,
          ),
        ),
        child: Text(
          board.title,
          style: AppTextStyles.labelMedium.copyWith(
            color: selected ? NuvoColors.surface : NuvoColors.navy,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
        ),
      ),
    );
  }
}

class _CompactBoardRow extends StatelessWidget {
  const _CompactBoardRow({required this.board, required this.onTap});

  final ArenaBoard board;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final progress = board.progressPercent ?? 0;
    final accent = board.isResult ? NuvoColors.success : NuvoColors.blue;

    return PressableScale(
      onTap: onTap,
      scale: 0.985,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 15, 14, 15),
        decoration: BoxDecoration(
          color: NuvoColors.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: NuvoColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '$progress%',
                style: AppTextStyles.labelMedium.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    board.title,
                    style: AppTextStyles.titleMedium.copyWith(
                      color: NuvoColors.navy,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    board.boardContext,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: NuvoColors.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              color: NuvoColors.textDim,
              size: 14,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Crew activity feed ────────────────────────────────────────────────────────

class _ActivityFeed extends StatelessWidget {
  const _ActivityFeed({required this.activity});

  final List<ArenaActivity> activity;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 126,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: activity.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) => _ActivityCard(item: activity[i]),
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.item});

  final ArenaActivity item;

  NuvoIconType get _icon => switch (item.type) {
    'proof_submitted' => NuvoIconType.checkCircle,
    'joined' => NuvoIconType.users,
    'leader_changed' => NuvoIconType.trendUp,
    'finished' => NuvoIconType.flag,
    _ => NuvoIconType.bell,
  };

  @override
  Widget build(BuildContext context) {
    final avatarColor = nuvoAvatarColorFor(item.actorName);
    return Container(
      width: 166,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: NuvoColors.border.withValues(alpha: 0.72)),
        boxShadow: AppShadows.hardShadow3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              NuvoAvatar(
                initials: _initials(item.actorName),
                size: 24,
                bgColor: avatarColor,
                textColor: Colors.white,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  item.timeLabel,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: NuvoColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            item.text,
            style: AppTextStyles.bodySmall.copyWith(
              color: NuvoColors.navy,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          Row(
            children: [
              NuvoIcon(_icon, size: 12, color: NuvoColors.actionBlue),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  item.raceTitle ?? '',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: NuvoColors.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
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

String _ordinal(int n) {
  if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
  return switch (n % 10) {
    1 => '${n}st',
    2 => '${n}nd',
    3 => '${n}rd',
    _ => '${n}th',
  };
}

// ── Loading state ─────────────────────────────────────────────────────────────

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 64),
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: NuvoColors.blue,
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onStart, required this.onJoin});
  final VoidCallback onStart;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: NuvoColors.actionBlue.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: NuvoColors.border),
          ),
          child: const NuvoIcon(
            NuvoIconType.bolt,
            color: NuvoColors.actionBlue,
            size: 24,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Your arena is empty.',
          style: AppTextStyles.headlineMedium.copyWith(color: NuvoColors.navy),
        ),
        const SizedBox(height: 8),
        Text(
          'Set a finish line, pull in your crew, and move the leaderboard together.',
          style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
        ),
        const SizedBox(height: 24),
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
        const SizedBox(height: 16),
        Text(
          message,
          style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
        ),
        const SizedBox(height: 16),
        NuvoOutlineButton(label: 'Retry', expand: true, onPressed: onRetry),
      ],
    );
  }
}

// ── Notification row ──────────────────────────────────────────────────────────

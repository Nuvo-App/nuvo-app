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

  static const _crewBoard = ArenaBoard(
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
      ArenaMiniLeaderboardRow(label: 'Alex', value: '58 / 100'),
      ArenaMiniLeaderboardRow(label: 'Jordan K.', value: '42 / 100'),
    ],
  );
  static const _tracksideBoard = ArenaBoard(
    id: 'conference-preview',
    source: 'demo',
    title: 'First to 100 Pushups',
    proofLabel: 'Camera verified',
    progressLabel: '65 / 100 reps',
    boardContext: '3 racers on the board',
    primaryActionLabel: 'Submit proof',
    primaryActionType: 'submit_proof',
    progressPercent: 65,
    racerCount: 3,
    isResult: false,
    myRank: 1,
    chaseCopy: 'Alex is 7 behind',
    daysLeft: 4,
    miniLeaderboard: [
      ArenaMiniLeaderboardRow(
        label: 'You',
        value: '65 / 100',
        isCurrentUser: true,
        profilePhotoUrl: 'https://i.pravatar.cc/150?img=12',
      ),
      ArenaMiniLeaderboardRow(
        label: 'Alex R.',
        value: '48 / 100',
        profilePhotoUrl: 'https://i.pravatar.cc/150?img=33',
      ),
      ArenaMiniLeaderboardRow(
        label: 'Maya L.',
        value: '31 / 100',
        profilePhotoUrl: 'https://i.pravatar.cc/150?img=47',
      ),
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
      profilePhotoUrl: 'https://i.pravatar.cc/150?img=12',
    ),
    RaceParticipant(
      id: 'preview-alex',
      userId: 'preview-alex',
      displayName: 'Alex R.',
      progressValue: 58,
      progressPercent: 58,
      rank: 2,
      joinedAt: '2026-07-23T00:00:00Z',
      profilePhotoUrl: 'https://i.pravatar.cc/150?img=33',
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
      progressValue: 28,
      progressPercent: 28,
      rank: 4,
      joinedAt: '2026-07-23T00:00:00Z',
      profilePhotoUrl: 'https://i.pravatar.cc/150?img=47',
    ),
  ];
  static const _activity = ArenaActivity(
    id: 'preview-activity',
    actorName: 'Maya L.',
    text: 'Maya L. submitted 20 pushups',
    timeLabel: '2m ago',
    type: 'proof_submitted',
    actorPhotoUrl: 'https://i.pravatar.cc/150?img=47',
  );

  @override
  Widget build(BuildContext context) {
    final visual = NuvoVisualTheme.of(context);
    final trackside = visual.style == NuvoPreviewStyle.trackside;
    final board = trackside ? _tracksideBoard : _crewBoard;
    final participants = trackside
        ? [_participants[0], _participants[1], _participants[3]]
        : _participants;
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final designInset = math.max(0.0, (viewportWidth - 390) / 2);
    final horizontal = visual.style == NuvoPreviewStyle.trackside
        ? 0.0
        : designInset + 22.0;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontal),
            child: _FocusBoardCard(
              board: board,
              isLoading: false,
              currentUserId: 'preview-you',
              currentUserInitials: 'SP',
              participants: participants,
              activity: _activity,
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
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final designInset = math.max(0.0, (viewportWidth - 390) / 2);
    final focusPadding = visual.style == NuvoPreviewStyle.trackside
        ? const EdgeInsets.fromLTRB(0, 0, 0, 128)
        : EdgeInsets.fromLTRB(designInset + 22, 0, designInset + 22, 128);
    return Scaffold(
      backgroundColor: visual.page,
      body: SafeArea(
        top: visual.style != NuvoPreviewStyle.trackside,
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
                                serverRankedParticipants(
                                  cameraRaceById[activeBoard.id]!,
                                ),
                            activity: snapshot.activity.isEmpty
                                ? null
                                : snapshot.activity.first,
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
        _scoreCenterParticipants = serverRankedParticipants(race);
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
    this.activity,
  });

  final ArenaBoard board;
  final bool isLoading;
  final VoidCallback onLogMove;
  final VoidCallback onOpen;
  final String? currentUserId;
  final String? currentUserPhotoUrl;
  final String? currentUserInitials;
  final List<RaceParticipant>? participants;
  final ArenaActivity? activity;

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
        activity: activity,
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
    this.activity,
  });

  final ArenaBoard board;
  final bool isLoading;
  final List<RingRacer> ringRacers;
  final VoidCallback onLogMove;
  final VoidCallback onOpen;
  final String? currentUserPhotoUrl;
  final String? currentUserInitials;
  final ArenaActivity? activity;

  @override
  Widget build(BuildContext context) {
    final visual = NuvoVisualTheme.of(context);
    final pct = board.progressPercent ?? 0;
    final score = _ProgressScore.parse(board.progressLabel, fallback: pct);
    final screenSize = MediaQuery.sizeOf(context);
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final availableBoardHeight =
        screenSize.height - viewPadding.top - viewPadding.bottom - 74;
    final layoutScale = math.min(
      1.0,
      math.max(0.0, availableBoardHeight) / 770,
    );
    const standingsDesignHeight = 305.0;
    return Column(
      children: [
        ColoredBox(
          color: visual.hero,
          child: Column(
            children: [
              SizedBox(height: viewPadding.top),
              SizedBox(
                height: 465 * layoutScale,
                width: double.infinity,
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      width: 390,
                      height: 465,
                      child: Stack(
                        children: [
                          Positioned(
                            left: 25,
                            right: 25,
                            top: 29,
                            child: _NuvoLockup(
                              inverse: true,
                              trailing: 'ARENA',
                              trailingColor: visual.action,
                              markSize: 24,
                              brandFontSize: 10.5,
                              brandLetterSpacing: 3,
                              trailingFontSize: 9,
                            ),
                          ),
                          Positioned(
                            top: 78,
                            left: 0,
                            right: 0,
                            child: Text(
                              'Your next move',
                              textAlign: TextAlign.center,
                              style: AppTextStyles.headlineLarge.copyWith(
                                color: visual.onHero,
                                fontSize: 27,
                                fontWeight: FontWeight.w800,
                                height: 1.05,
                              ),
                            ),
                          ),
                          Positioned(
                            top: 116,
                            left: 40,
                            right: 40,
                            child: Text(
                              board.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: visual.onHero.withValues(alpha: 0.72),
                                fontSize: 14,
                                height: 1,
                              ),
                            ),
                          ),
                          Positioned(
                            top: 153,
                            left: 0,
                            right: 0,
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: score.current,
                                    style: AppTextStyles.number(
                                      56,
                                      color: visual.action,
                                      weight: FontWeight.w700,
                                    ),
                                  ),
                                  TextSpan(
                                    text: ' / ',
                                    style: AppTextStyles.number(
                                      56,
                                      color: visual.onHero.withValues(
                                        alpha: 0.62,
                                      ),
                                      weight: FontWeight.w500,
                                    ),
                                  ),
                                  TextSpan(
                                    text: score.goal,
                                    style: AppTextStyles.number(
                                      56,
                                      color: visual.onHero,
                                      weight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          Positioned(
                            top: 233,
                            left: 0,
                            right: 0,
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: '${score.remaining}',
                                    style: AppTextStyles.titleMedium.copyWith(
                                      color: visual.action,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 18,
                                      height: 1,
                                    ),
                                  ),
                                  TextSpan(
                                    text: ' to the finish line',
                                    style: AppTextStyles.bodyMedium.copyWith(
                                      color: visual.onHero.withValues(
                                        alpha: 0.78,
                                      ),
                                      fontSize: 14,
                                      height: 1,
                                    ),
                                  ),
                                ],
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          Positioned(
                            left: 22,
                            top: 176,
                            width: 346,
                            height: 180,
                            child: _TracksideRaceCourse(
                              progress: pct / 100,
                              racers: ringRacers,
                            ),
                          ),
                          Positioned(
                            left: 30,
                            top: 389,
                            width: 330,
                            child: board.isResult
                                ? NuvoOutlineButton(
                                    label: 'Open board',
                                    expand: true,
                                    onPressed: onOpen,
                                  )
                                : _SourceActionButton(
                                    label: board.primaryActionLabel,
                                    onTap: onLogMove,
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          height: standingsDesignHeight * layoutScale,
          width: double.infinity,
          color: visual.surface,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: SizedBox(
                width: 390,
                height: standingsDesignHeight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(25, 21, 25, 0),
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
                          Semantics(
                            button: true,
                            label: 'View full crew standings',
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: onOpen,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Text(
                                  'VIEW ALL',
                                  style: AppTextStyles.labelUppercase(
                                    9,
                                    color: visual.action,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
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
                        rowHeight: 54,
                        dividerHeight: 1,
                        avatarSize: 40,
                        rankWidth: 12,
                        rankAvatarGap: 20,
                        avatarLabelGap: 14,
                        progressLineWidth: 70,
                        currentUserAccentOnly: true,
                      ),
                      if (activity != null) ...[
                        const SizedBox(height: 8),
                        Divider(height: 1, color: visual.border),
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
                        const SizedBox(height: 7),
                        _SourceActivityRow(
                          initials: _initials(activity!.actorName),
                          text: activity!.text,
                          timeLabel: activity!.timeLabel,
                          photoUrl: activity!.actorPhotoUrl,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
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
      padding: const EdgeInsets.fromLTRB(0, 19, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _NuvoLockup(
            trailing: 'Arena',
            markSize: 29,
            brandFontSize: 16,
            brandLetterSpacing: 3.1,
            trailingFontSize: 13,
          ),
          const SizedBox(height: 13),
          Divider(height: 1, color: visual.border),
          const SizedBox(height: 19),
          Text(
            board.isResult ? 'FINISH LINE' : 'YOUR NEXT MOVE',
            style: AppTextStyles.labelUppercase(
              10,
              color: visual.mutedInk,
            ).copyWith(height: 1),
          ),
          const SizedBox(height: 6),
          Text(
            board.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.headlineLarge.copyWith(
              color: visual.ink,
              fontSize: 26,
              height: 1.08,
            ),
          ),
          const SizedBox(height: 22),
          Center(
            child: _CrewProgressOrbit(
              progress: pct / 100,
              current: score.current,
              goal: score.goal,
              remainingLabel: score.remainingLabel,
              chaseLabel: board.chaseCopy,
              racers: ringRacers,
              size: 344,
            ),
          ),
          const SizedBox(height: 27),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: board.isResult
                ? NuvoOutlineButton(
                    label: 'Open board',
                    expand: true,
                    onPressed: onOpen,
                  )
                : _SourceActionButton(
                    label: board.primaryActionLabel,
                    onTap: onLogMove,
                    height: 44,
                    shadow: true,
                    labelSize: 14,
                    labelWeight: FontWeight.w500,
                  ),
          ),
          const SizedBox(height: 19),
          Divider(height: 1, color: visual.border),
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
            rowHeight: 44.33,
            dividerHeight: 1,
            rankAvatarGap: 11,
            avatarLabelGap: 11,
            progressLineWidth: 92,
          ),
          if (board.isDemo) ...[
            Divider(height: 1, color: visual.border),
            const SizedBox(height: 9),
            const _SourceActivityRow(
              initials: 'AR',
              text: 'Alex submitted 20 pushups',
              name: 'Alex',
              detail: 'submitted 20 pushups',
              stacked: true,
              avatarSize: 32,
              gap: 15,
            ),
          ],
        ],
      ),
    );
  }
}

class _SourceActionButton extends StatelessWidget {
  const _SourceActionButton({
    required this.label,
    required this.onTap,
    this.height = 52,
    this.shadow = false,
    this.labelSize = 15,
    this.labelWeight = FontWeight.w600,
  });

  final String label;
  final VoidCallback onTap;
  final double height;
  final bool shadow;
  final double labelSize;
  final FontWeight labelWeight;

  @override
  Widget build(BuildContext context) {
    final visual = NuvoVisualTheme.of(context);
    return Container(
      width: double.infinity,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        boxShadow: shadow
            ? [
                BoxShadow(
                  color: visual.action.withValues(alpha: 0.16),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
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
            fontSize: labelSize,
            fontWeight: labelWeight,
          ),
        ),
      ),
    );
  }
}

class _NuvoLockup extends StatelessWidget {
  const _NuvoLockup({
    this.inverse = false,
    this.trailing,
    this.trailingColor,
    this.markSize = 29,
    this.brandFontSize = 15,
    this.brandLetterSpacing = 3.2,
    this.trailingFontSize = 11,
  });

  final bool inverse;
  final String? trailing;
  final Color? trailingColor;
  final double markSize;
  final double brandFontSize;
  final double brandLetterSpacing;
  final double trailingFontSize;

  @override
  Widget build(BuildContext context) {
    final visual = NuvoVisualTheme.of(context);
    final ink = inverse ? visual.onHero : visual.ink;
    return Row(
      children: [
        SizedBox.square(
          dimension: markSize,
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
            fontSize: brandFontSize,
            letterSpacing: brandLetterSpacing,
            height: 1,
          ),
        ),
        const Spacer(),
        if (trailing != null)
          Text(
            trailing!,
            style: AppTextStyles.labelSmall.copyWith(
              color: trailingColor ?? ink,
              fontWeight: FontWeight.w700,
              fontSize: trailingFontSize,
              height: 1,
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final reduceMotion = MediaQuery.disableAnimationsOf(context);
          const targetSlots = <double>[0, -1, 1];
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(painter: _TracksideCoursePainter(progress)),
              ),
              for (var i = 0; i < visible.length; i++)
                Positioned.fill(
                  child: _AnimatedTrackRacerMarker(
                    key: ValueKey(visible[i].id),
                    racer: visible[i],
                    rank: i + 1,
                    targetSlot: targetSlots[i],
                    trackWidth: constraints.maxWidth,
                    reduceMotion: reduceMotion,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _AnimatedTrackRacerMarker extends StatelessWidget {
  const _AnimatedTrackRacerMarker({
    super.key,
    required this.racer,
    required this.rank,
    required this.targetSlot,
    required this.trackWidth,
    required this.reduceMotion,
  });

  final RingRacer racer;
  final int rank;
  final double targetSlot;
  final double trackWidth;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 620);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: targetSlot),
      duration: duration,
      curve: Curves.easeInOutCubic,
      builder: (context, slot, _) {
        // The three source positions lie on the shallow lower track edge.
        // Interpolating this parabola keeps rank changes on that edge instead
        // of sending members through the center of the course.
        final centerX = trackWidth * 0.50;
        final x = centerX + (trackWidth * 0.33 * slot);
        final y = 161 - (57 * slot * slot);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: x - 17,
              top: y - 17,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.84, end: 1),
                duration: duration,
                curve: Curves.easeOutCubic,
                builder: (context, entry, child) => Opacity(
                  opacity: entry,
                  child: Transform.scale(scale: entry, child: child),
                ),
                child: _TrackRacerMarker(racer: racer, rank: rank),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TracksideCoursePainter extends CustomPainter {
  const _TracksideCoursePainter(this.progress);

  final double progress;

  static const _guideOffsets = [6.0, 12.0, 18.0, 24.0];
  static const _guideOpacities = [0.25, 0.20, 0.15, 0.10];
  static const _maxSweep = math.pi * 0.847; // sweep at progress == 1.0

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Rect.fromLTWH(0, -88, size.width, 255);

    // Guide lines share the exact same arc geometry as the progress arc
    // below (same rect shape, same start/sweep angles), just inflated
    // outward — never a separate closed oval — so they can never visually
    // diverge from the track's actual curvature.
    final guidePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.butt;
    for (var i = 0; i < _guideOffsets.length; i++) {
      guidePaint.color = Colors.white.withValues(alpha: _guideOpacities[i]);
      canvas.drawArc(
        outer.inflate(_guideOffsets[i]),
        0,
        _maxSweep,
        false,
        guidePaint,
      );
    }

    final active = Paint()
      ..color = const Color(0xFF327BFF)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt
      ..strokeWidth = 13;
    final sweep = math.pi * (0.427 + progress.clamp(0.0, 1.0) * 0.42);
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
    final visual = NuvoVisualTheme.of(context);
    return Column(
      children: [
        NuvoAvatar(
          initials: racer.initials,
          photoUrl: racer.photoUrl,
          size: 34,
          bgColor: NuvoColors.border,
          textColor: Colors.white,
          useIconFallback: true,
          borderColor: racer.isCurrentUser ? visual.action : Colors.white,
          borderWidth: racer.isCurrentUser ? 3 : 2,
        ),
        Transform.translate(
          offset: const Offset(0, -4),
          child: Container(
            width: 18,
            height: 18,
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
                fontSize: 8,
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
    required this.chaseLabel,
    required this.racers,
    required this.size,
  });

  final double progress;
  final String current;
  final String goal;
  final String remainingLabel;
  final String? chaseLabel;
  final List<RingRacer> racers;
  final double size;

  @override
  Widget build(BuildContext context) {
    final visual = NuvoVisualTheme.of(context);
    final visible = racers.take(4).toList();
    final center = size / 2;
    final placements = <Offset>[
      Offset(center, 47),
      const Offset(31, 179),
      Offset(size - 35, 179),
      Offset(center + 1, 309),
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
                      50,
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
                left: placements[i].dx - 35,
                top: placements[i].dy - 42,
                child: _OrbitRacerMarker(
                  racer: visible[i],
                  rank: i + 1,
                  position: i,
                ),
              ),
            if (chaseLabel != null && chaseLabel!.isNotEmpty)
              Positioned(
                left: 0,
                top: 221,
                width: 95,
                child: Text(
                  chaseLabel!,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: visual.ink,
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                  ),
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
    const radius = 92.0;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(
      rect,
      -math.pi * 0.31,
      math.pi * 2,
      false,
      Paint()
        ..color = inactive
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );
    canvas.drawArc(
      rect,
      -math.pi * 0.24,
      -math.pi * 2 * progress.clamp(0.0, 1.0) * 0.86,
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
    required this.position,
  });

  final RingRacer racer;
  final int rank;
  final int position;

  @override
  Widget build(BuildContext context) {
    final visual = NuvoVisualTheme.of(context);
    final top = position == 0;
    final avatarSize = position == 1 || position == 2 ? 58.0 : 54.0;
    return SizedBox(
      width: 70,
      height: 84,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            top: 15,
            child: NuvoAvatar(
              initials: racer.initials,
              photoUrl: racer.photoUrl,
              size: avatarSize,
              bgColor: nuvoAvatarColorFor(racer.id),
              textColor: Colors.white,
              borderColor: top ? visual.action : visual.surface,
              borderWidth: top ? 2 : 1.5,
            ),
          ),
          Positioned(
            top: 61,
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
                '${(racer.progress * 100).round()}',
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
              top: -5,
              child: Text(
                'You',
                style: AppTextStyles.labelSmall.copyWith(
                  color: visual.action,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (!top)
            Positioned(
              top: position == 3 ? -4 : -14,
              child: Text(
                '$rank',
                style: AppTextStyles.titleMedium.copyWith(
                  color: visual.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SourceActivityRow extends StatelessWidget {
  const _SourceActivityRow({
    required this.initials,
    required this.text,
    this.name,
    this.detail,
    this.stacked = false,
    this.avatarSize = 28,
    this.gap = 10,
    this.timeLabel = '2m ago',
    this.photoUrl,
  });

  final String initials;
  final String text;
  final String? name;
  final String? detail;
  final bool stacked;
  final double avatarSize;
  final double gap;
  final String timeLabel;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final visual = NuvoVisualTheme.of(context);
    return Row(
      children: [
        NuvoAvatar(
          initials: initials,
          photoUrl: photoUrl,
          size: avatarSize,
          bgColor: nuvoAvatarColorFor(initials),
          textColor: Colors.white,
        ),
        SizedBox(width: gap),
        Expanded(
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name ?? text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: visual.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      detail ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.labelSmall.copyWith(
                        color: visual.mutedInk,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                )
              : Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: name == null ? text : '$name ',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: visual.ink,
                          fontWeight: name == null
                              ? FontWeight.w500
                              : FontWeight.w700,
                        ),
                      ),
                      if (name != null)
                        TextSpan(
                          text: detail ?? '',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: visual.mutedInk,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
        ),
        Text(
          timeLabel,
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
    this.rowHeight,
    this.dividerHeight,
    this.avatarSize = 30,
    this.rankWidth = 18,
    this.rankAvatarGap = 8,
    this.avatarLabelGap = 10,
    this.progressLineWidth = 50,
    this.currentUserAccentOnly = false,
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
  final double? rowHeight;
  final double? dividerHeight;
  final double avatarSize;
  final double rankWidth;
  final double rankAvatarGap;
  final double avatarLabelGap;
  final double progressLineWidth;

  /// When true, only the current user's row is accented (blue rank, blue bar
  /// fill, blue avatar ring). Every other row uses neutral/muted styling
  /// regardless of leaderboard rank. When false (default), preserves the
  /// existing rank-tiered styling used by Starting Line / Crew Momentum.
  final bool currentUserAccentOnly;

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
                currentUserAccentOnly: currentUserAccentOnly,
                rowHeight: rowHeight,
                avatarSize: avatarSize,
                rankWidth: rankWidth,
                rankAvatarGap: rankAvatarGap,
                avatarLabelGap: avatarLabelGap,
                progressLineWidth: progressLineWidth,
              ),
              if (i < board.miniLeaderboard.length - 1)
                Divider(
                  height: dividerHeight ?? (dense ? 2 : 8),
                  color: visual.border,
                ),
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
    this.rowHeight,
    this.avatarSize = 30,
    this.rankWidth = 18,
    this.rankAvatarGap = 8,
    this.avatarLabelGap = 10,
    this.progressLineWidth = 50,
    this.currentUserAccentOnly = false,
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
  final double? rowHeight;
  final double avatarSize;
  final double rankWidth;
  final double rankAvatarGap;
  final double avatarLabelGap;
  final double progressLineWidth;
  final bool currentUserAccentOnly;

  static const _neutralRank = Color(0xFF9CA3AF);
  static const _neutralBarFill = Color(0xFF5A5F72);

  Color? get _rankTierColor => switch (rank) {
    1 => NuvoColors.gold,
    2 => NuvoColors.silver,
    3 => NuvoColors.bronze,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final visual = NuvoVisualTheme.of(context);
    final tierColor = currentUserAccentOnly ? null : _rankTierColor;
    final avatarColor = currentUserAccentOnly
        ? NuvoColors.border
        : (isCurrentUser ? NuvoColors.navy : nuvoAvatarColorFor(label));
    final initials = (initialsOverride != null && initialsOverride!.isNotEmpty)
        ? initialsOverride!
        : _initials(label);

    return Container(
      height: rowHeight,
      padding: EdgeInsets.symmetric(
        horizontal: 0,
        vertical: rowHeight == null ? (dense ? 3 : 7) : 0,
      ),
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
            width: rankWidth,
            child: Text(
              '$rank',
              style: AppTextStyles.labelMedium.copyWith(
                color: isCurrentUser
                    ? visual.action
                    : (currentUserAccentOnly
                          ? _neutralRank
                          : tierColor ?? visual.mutedInk),
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(width: rankAvatarGap),
          NuvoAvatar(
            initials: initials,
            photoUrl: photoUrl,
            size: avatarSize,
            bgColor: avatarColor,
            textColor: Colors.white,
            useIconFallback: currentUserAccentOnly,
            borderColor: currentUserAccentOnly && isCurrentUser
                ? visual.action
                : visual.surface,
            borderWidth: currentUserAccentOnly && isCurrentUser ? 2 : 1.5,
          ),
          SizedBox(width: avatarLabelGap),
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
              width: progressLineWidth,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: _progressFromValue(value),
                  minHeight: 3,
                  color: currentUserAccentOnly && !isCurrentUser
                      ? _neutralBarFill
                      : visual.action,
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

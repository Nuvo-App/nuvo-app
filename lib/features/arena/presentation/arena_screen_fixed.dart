import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_geometry.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/bottom_nav.dart';
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
    return Scaffold(
      backgroundColor: NuvoColors.pageIce,
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
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
                  child: _ArenaHeader(
                    initials: initials,
                    photoUrl: user?.profilePhotoUrl,
                    hasActivity: snapshot?.activity.isNotEmpty ?? false,
                    onProfileTap: () => context.go('/profile'),
                    onNotificationsTap: () => _showNotificationsSheet(
                      context,
                      snapshot?.activity ?? const [],
                    ),
                  ),
                ),
              ),
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
                  padding: EdgeInsets.fromLTRB(
                    18,
                    22,
                    18,
                    NuvoBottomNav.bottomPadding(context) + 16,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      if (activeBoard != null) ...[
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
                        const SizedBox(height: 18),
                        _LeaderboardPreview(
                          board: activeBoard,
                          isLoading: _isLoadingBoardDetail,
                          currentUserPhotoUrl: user?.profilePhotoUrl,
                          currentUserInitials: initials,
                          onOpen: () => _openBoard(context, activeBoard),
                        ),
                      ],
                      if (allBoards.length > 1) ...[
                        const SizedBox(height: 18),
                        _RaceChipRow(
                          boards: allBoards,
                          selectedId: resolvedId,
                          onTap: (b) => _onChipTap(b, snapshot, user?.id),
                        ),
                      ],
                      if (otherBoards.isNotEmpty) ...[
                        const SizedBox(height: 26),
                        const _SectionLabel(label: 'More races'),
                        const SizedBox(height: 10),
                        _MoreRacesBoard(
                          boards: otherBoards,
                          onTap: (board) =>
                              _onChipTap(board, snapshot, user?.id),
                        ),
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

// ── Arena header ──────────────────────────────────────────────────────────────

class _ArenaHeader extends StatelessWidget {
  const _ArenaHeader({
    required this.initials,
    required this.onProfileTap,
    required this.onNotificationsTap,
    this.photoUrl,
    this.hasActivity = false,
  });

  final String initials;
  final String? photoUrl;
  final VoidCallback onProfileTap;
  final VoidCallback onNotificationsTap;
  final bool hasActivity;

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
                'Arena',
                style: AppTextStyles.headlineLarge.copyWith(
                  color: NuvoColors.navy,
                  fontSize: 32,
                  letterSpacing: -0.9,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Your next move, at a glance.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: NuvoColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        PressableScale(
          onTap: onNotificationsTap,
          scale: 0.94,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: NuvoColors.surface.withValues(alpha: 0.72),
              shape: BoxShape.circle,
              border: Border.all(color: NuvoColors.border),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(
                  Icons.notifications_none_rounded,
                  color: NuvoColors.navy,
                  size: 20,
                ),
                if (hasActivity)
                  Positioned(
                    top: 9,
                    right: 9,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: NuvoColors.coral,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        PressableScale(
          onTap: onProfileTap,
          scale: 0.94,
          child: NuvoAvatar(
            initials: initials,
            photoUrl: photoUrl,
            size: 42,
            bgColor: NuvoColors.navy,
            textColor: NuvoColors.white,
            borderColor: NuvoColors.surface,
            borderWidth: 2,
          ),
        ),
      ],
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: AppTextStyles.titleMedium.copyWith(
        color: NuvoColors.navy,
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

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(NuvoRadii.lg),
        border: Border.all(color: NuvoColors.navy, width: 2),
        boxShadow: const [
          BoxShadow(
            color: NuvoColors.navy,
            blurRadius: 0,
            offset: Offset(4, 4),
          ),
        ],
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
          if (isLoading) const SizedBox(height: 14),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
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
                      isResult ? 'FINISHED' : 'NEXT MOVE',
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
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: NuvoColors.icyBlue,
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
          const SizedBox(height: 16),
          Hero(
            tag: 'race-title-${board.id}',
            child: Material(
              color: Colors.transparent,
              child: Text(
                board.title,
                style: AppTextStyles.headlineLarge.copyWith(
                  color: NuvoColors.navy,
                  fontSize: 26,
                  height: 1.06,
                  letterSpacing: 0,
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
          const SizedBox(height: 20),
          if (!isResult && !isLoading)
            Row(
              children: [
                RaceRing(
                  progress: pct / 100,
                  centerValue: '$pct%',
                  size: 104,
                  strokeWidth: 9,
                  delay: const Duration(milliseconds: 160),
                  racers: ringRacers,
                ),
                const SizedBox(width: 16),
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: pct.clamp(0, 100) / 100,
                          minHeight: 6,
                          color: NuvoColors.actionBlue,
                          backgroundColor: NuvoColors.trackBg,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        board.progressLabel,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: NuvoColors.textMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                    fontSize: 42,
                    letterSpacing: 0,
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
          const SizedBox(height: 14),
          if (board.chaseCopy != null || board.miniLeaderboard.isNotEmpty)
            Row(
              children: [
                Expanded(
                  child: Text(
                    board.chaseCopy ??
                        '${board.racerCount ?? board.miniLeaderboard.length} on the start line',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: NuvoColors.textMuted,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (board.miniLeaderboard.isNotEmpty) ...[
                  const SizedBox(width: 12),
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
                    size: 24,
                    max: 4,
                    borderColor: NuvoColors.surface,
                  ),
                ],
              ],
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

// ── Leaderboard preview ──────────────────────────────────────────────────────

class _LeaderboardPreview extends StatelessWidget {
  const _LeaderboardPreview({
    required this.board,
    required this.isLoading,
    required this.onOpen,
    this.currentUserPhotoUrl,
    this.currentUserInitials,
  });

  final ArenaBoard board;
  final bool isLoading;
  final VoidCallback onOpen;
  final String? currentUserPhotoUrl;
  final String? currentUserInitials;

  @override
  Widget build(BuildContext context) {
    final previewIndexes = _leaderboardPreviewIndexes(board.miniLeaderboard);

    if (!isLoading && previewIndexes.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _SectionLabel(label: 'Leaderboard'),
            const Spacer(),
            if (board.daysLeft != null) ...[
              Text(
                '${board.daysLeft} days left',
                style: AppTextStyles.labelSmall.copyWith(
                  color: NuvoColors.textMuted,
                ),
              ),
              const SizedBox(width: 10),
            ],
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onOpen,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Text(
                  'View all',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: NuvoColors.actionBlue,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            color: NuvoColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: NuvoColors.border, width: 1.25),
          ),
          child: Column(
            children: [
              if (isLoading)
                ..._FocusBoardCard._buildSkeletonRows()
              else
                for (var i = 0; i < previewIndexes.length; i++) ...[
                  _LeaderboardRow(
                    rank: previewIndexes[i] + 1,
                    label: board.miniLeaderboard[previewIndexes[i]].label,
                    value: board.miniLeaderboard[previewIndexes[i]].value,
                    isCurrentUser:
                        board.miniLeaderboard[previewIndexes[i]].isCurrentUser,
                    photoUrl:
                        board.miniLeaderboard[previewIndexes[i]].isCurrentUser
                        ? (currentUserPhotoUrl ??
                              board
                                  .miniLeaderboard[previewIndexes[i]]
                                  .profilePhotoUrl)
                        : board
                              .miniLeaderboard[previewIndexes[i]]
                              .profilePhotoUrl,
                    initialsOverride:
                        board.miniLeaderboard[previewIndexes[i]].isCurrentUser
                        ? currentUserInitials
                        : null,
                  ),
                  if (i < previewIndexes.length - 1)
                    const Divider(
                      height: 5,
                      thickness: 1,
                      color: NuvoColors.divider,
                    ),
                ],
            ],
          ),
        ),
      ],
    );
  }

  static List<int> _leaderboardPreviewIndexes(
    List<ArenaMiniLeaderboardRow> rows,
  ) {
    final selected = <int>[];

    void addIndex(int index) {
      if (index >= 0 && index < rows.length && !selected.contains(index)) {
        selected.add(index);
      }
    }

    addIndex(0);
    addIndex(rows.indexWhere((row) => row.isCurrentUser));

    for (var i = 0; i < rows.length && selected.length < 3; i++) {
      addIndex(i);
    }

    return selected.take(3).toList();
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
  });

  final int rank;
  final String label;
  final String value;
  final bool isCurrentUser;
  final String? photoUrl;
  final String? initialsOverride;

  Color? get _rankTierColor => switch (rank) {
    1 => NuvoColors.gold,
    2 => NuvoColors.silver,
    3 => NuvoColors.bronze,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final tierColor = _rankTierColor;
    final avatarColor = isCurrentUser
        ? NuvoColors.navy
        : nuvoAvatarColorFor(label);
    final initials = (initialsOverride != null && initialsOverride!.isNotEmpty)
        ? initialsOverride!
        : _initials(label);

    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: isCurrentUser
          ? BoxDecoration(
              color: NuvoColors.icyBlue,
              borderRadius: BorderRadius.circular(12),
            )
          : null,
      child: Row(
        children: [
          SizedBox(
            width: 18,
            child: Text(
              '$rank',
              style: AppTextStyles.labelMedium.copyWith(
                color: tierColor ?? NuvoColors.textMuted,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 8),
          Stack(
            clipBehavior: Clip.none,
            children: [
              NuvoAvatar(
                initials: initials,
                photoUrl: photoUrl,
                size: 28,
                bgColor: avatarColor,
                textColor: Colors.white,
                borderColor: tierColor,
                borderWidth: tierColor != null ? 2 : 1.5,
              ),
              if (rank == 1)
                const Positioned(
                  top: -10,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: NuvoIcon(
                      NuvoIconType.crown,
                      size: 12,
                      color: NuvoColors.gold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                color: isCurrentUser ? NuvoColors.navy : NuvoColors.muted,
                fontWeight: isCurrentUser ? FontWeight.w700 : FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            value,
            style: AppTextStyles.labelSmall.copyWith(
              color: isCurrentUser
                  ? NuvoColors.actionBlue
                  : NuvoColors.textMuted,
              fontWeight: isCurrentUser ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
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
      padding: const EdgeInsets.only(top: 1, bottom: 4, right: 4),
      child: Row(
        children: [
          for (final b in boards) ...[
            _RaceChip(
              board: b,
              selected: b.id == selectedId,
              onTap: () => onTap(b),
            ),
            const SizedBox(width: 6),
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 168, minHeight: 40),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? NuvoColors.navy : NuvoColors.surface,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: selected ? NuvoColors.navy : NuvoColors.border,
              width: selected ? 1.5 : 1.25,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            board.title,
            style: AppTextStyles.labelMedium.copyWith(
              color: selected ? NuvoColors.surface : NuvoColors.navy,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

class _MoreRacesBoard extends StatelessWidget {
  const _MoreRacesBoard({required this.boards, required this.onTap});

  final List<ArenaBoard> boards;
  final ValueChanged<ArenaBoard> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: NuvoColors.border, width: 1.25),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < boards.length; i++) ...[
            _CompactBoardRow(board: boards[i], onTap: () => onTap(boards[i])),
            if (i < boards.length - 1)
              const Divider(
                height: 1,
                thickness: 1,
                indent: 76,
                color: NuvoColors.divider,
              ),
          ],
        ],
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
    final isImportant = !board.isResult && progress >= 80;

    return PressableScale(
      onTap: onTap,
      scale: 0.985,
      child: Container(
        constraints: BoxConstraints(minHeight: board.isResult ? 70 : 76),
        color: isImportant ? NuvoColors.icyBlue : NuvoColors.surface,
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: board.isResult
                    ? NuvoColors.success.withValues(alpha: 0.10)
                    : NuvoColors.icyBlue,
                shape: BoxShape.circle,
                border: Border.all(color: accent.withValues(alpha: 0.18)),
              ),
              alignment: Alignment.center,
              child: Text(
                '$progress%',
                style: AppTextStyles.labelMedium.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    board.title,
                    style: AppTextStyles.titleMedium.copyWith(
                      color: NuvoColors.navy,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    board.isResult ? 'Finished' : board.boardContext,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: NuvoColors.textMuted,
                      height: 1.25,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (board.myRank != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  color: NuvoColors.panel,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  _ordinal(board.myRank!),
                  style: AppTextStyles.labelSmall.copyWith(
                    color: NuvoColors.navy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
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
        boxShadow: [
          BoxShadow(
            color: NuvoColors.navy.withValues(alpha: 0.05),
            blurRadius: 18,
            spreadRadius: -10,
            offset: const Offset(0, 8),
          ),
        ],
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

class _NotifRow extends StatelessWidget {
  const _NotifRow({required this.item});

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
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: NuvoColors.divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              color: NuvoColors.panel,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: NuvoIcon(_icon, size: 15, color: NuvoColors.actionBlue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.text,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: NuvoColors.navy,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.timeLabel,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: NuvoColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Notifications sheet ───────────────────────────────────────────────────────

void _showNotificationsSheet(
  BuildContext context,
  List<ArenaActivity> activity,
) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: NuvoColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: NuvoColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: NuvoColors.actionBlue.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const NuvoIcon(
                    NuvoIconType.bell,
                    color: NuvoColors.actionBlue,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Activity', style: AppTextStyles.titleLarge),
                    Text(
                      'From your crew and races',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: NuvoColors.muted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (activity.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: NuvoColors.panel,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: NuvoColors.border),
                ),
                child: Column(
                  children: [
                    const NuvoIcon(
                      NuvoIconType.bell,
                      color: NuvoColors.textMuted,
                      size: 28,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No updates yet',
                      style: AppTextStyles.titleMedium.copyWith(
                        color: NuvoColors.navy,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "When your crew joins or crosses the finish line, you'll see it here.",
                      style: AppTextStyles.bodySmall.copyWith(
                        color: NuvoColors.muted,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else
              for (var i = 0; i < activity.length; i++) ...[
                _NotifRow(item: activity[i]),
                if (i < activity.length - 1) const SizedBox(height: 2),
              ],
          ],
        ),
      ),
    ),
  );
}

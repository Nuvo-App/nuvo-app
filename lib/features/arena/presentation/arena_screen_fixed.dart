import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_avatar.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_icons.dart';
import '../../../core/widgets/nuvo_shared_components.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../../core/widgets/race_ring.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../races/data/race_models.dart';
import '../../races/domain/chase_context.dart';
import '../../races/domain/camera_verification_resolver.dart';
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

  /// Real per-racer progress for the Race Ring, populated only once the full
  /// race detail has loaded (the arena snapshot's mini-leaderboard doesn't
  /// carry per-racer percent, only a formatted display value).
  List<RaceParticipant>? _scoreCenterParticipants;

  @override
  void initState() {
    super.initState();
    _selectedBoardId =
        ref.read(arenaControllerProvider).snapshot?.focusBoard?.id;
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
    final otherBoards = allBoards.where((b) => b.id != resolvedId).toList();

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
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
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
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
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
                            participants: _scoreCenterParticipants,
                            onLogMove: () => _handlePrimaryAction(
                              context,
                              activeBoard,
                              cameraRaceById,
                            ),
                            onOpen: () => _openBoard(context, activeBoard),
                          ),
                        ),
                      if (snapshot.activity.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        const _SectionLabel(label: 'Crew activity'),
                        const SizedBox(height: 12),
                        _ActivityFeed(activity: snapshot.activity),
                      ],
                      if (allBoards.length > 1) ...[
                        const SizedBox(height: 16),
                        _RaceChipRow(
                          boards: allBoards,
                          selectedId: resolvedId,
                          onTap: (b) => _onChipTap(b, snapshot, user?.id),
                        ),
                      ],
                      if (otherBoards.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        const _SectionLabel(label: 'Other races'),
                        const SizedBox(height: 12),
                        for (final b in otherBoards) ...[
                          _CompactBoardRow(
                            board: b,
                            onTap: () => _onChipTap(b, snapshot, user?.id),
                          ),
                          const SizedBox(height: 8),
                        ],
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
      final race =
          await ref.read(raceControllerProvider.notifier).getRaceDetail(board.id);
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
      primaryActionLabel: isResult ? 'Open board' : 'Log Move',
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
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 6, 10, 6),
        decoration: BoxDecoration(
          color: NuvoColors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: NuvoColors.border),
          boxShadow: AppShadows.hardShadow3,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PressableScale(
              onTap: onProfileTap,
              child: NuvoAvatar(
                initials: initials,
                photoUrl: photoUrl,
                size: 34,
                bgColor: NuvoColors.navy,
                textColor: NuvoColors.white,
                borderColor: NuvoColors.border,
                borderWidth: 1,
              ),
            ),
            const SizedBox(width: 8),
            PressableScale(
              onTap: onNotificationsTap,
              child: SizedBox(
                width: 34,
                height: 34,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(
                      Icons.notifications_none_rounded,
                      color: NuvoColors.navy,
                      size: 22,
                    ),
                    if (hasActivity)
                      Positioned(
                        top: 5,
                        right: 5,
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: NuvoColors.actionBlue,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: NuvoColors.white,
                              width: 1.2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
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
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: NuvoColors.actionBlue,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: AppTextStyles.labelMedium.copyWith(
            color: NuvoColors.navy,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
      ],
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

    final ringRacers = (participants ?? const []).map((p) {
      final isMe = currentUserId != null && p.userId == currentUserId;
      final photo =
          isMe ? (currentUserPhotoUrl ?? p.profilePhotoUrl) : p.profilePhotoUrl;
      final initials = isMe && (currentUserInitials?.isNotEmpty ?? false)
          ? currentUserInitials!
          : _initials(p.displayName);
      return RingRacer(
        id: p.userId,
        initials: initials,
        progress: p.progressPercent / 100.0,
        isCurrentUser: isMe,
        photoUrl: photo,
      );
    }).toList();

    return Container(
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: NuvoColors.inkNavy, width: 2),
        boxShadow: AppShadows.hardShadow5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isLoading)
            const LinearProgressIndicator(
              color: NuvoColors.blue,
              backgroundColor: Color(0x1A075BFF),
              minHeight: 2,
            ),
          Padding(
            // Extra bottom room so hard-offset button shadow isn't clipped
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Hero(
                  tag: 'race-title-${board.id}',
                  flightShuttleBuilder: (context, anim, direction, from, to) {
                    return FadeTransition(
                      opacity: anim,
                      child: Text(
                        board.title,
                        style: AppTextStyles.headlineMedium.copyWith(
                          color: NuvoColors.navy,
                          fontSize: 22,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  },
                  child: Text(
                    board.title,
                    style: AppTextStyles.headlineMedium.copyWith(
                      color: NuvoColors.navy,
                      fontSize: 22,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  board.boardContext,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: NuvoColors.muted,
                    height: 1.35,
                  ),
                ),
                if (!isResult && !isLoading) ...[
                  const SizedBox(height: 14),
                  Center(
                    child: RaceRing(
                      progress: pct / 100.0,
                      centerValue: '$pct%',
                      size: 132,
                      strokeWidth: 14,
                      delay: const Duration(milliseconds: 180),
                      racers: ringRacers,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (board.miniLeaderboard.isNotEmpty)
                      NuvoAvatarStack(
                        avatars: board.miniLeaderboard.map((r) {
                          final photo = r.isCurrentUser
                              ? (currentUserPhotoUrl ?? r.profilePhotoUrl)
                              : r.profilePhotoUrl;
                          final label = r.isCurrentUser &&
                                  (currentUserInitials?.isNotEmpty ?? false)
                              ? currentUserInitials!
                              : r.label;
                          return (initials: label, photoUrl: photo);
                        }).toList(),
                        total: board.racerCount ?? board.miniLeaderboard.length,
                        size: 22,
                        max: 4,
                        borderColor: NuvoColors.surface,
                      ),
                    const Spacer(),
                    if (board.daysLeft != null)
                      Text(
                        '${board.daysLeft}d left',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: NuvoColors.textMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    if (board.myRank != null && !isResult) ...[
                      if (board.daysLeft != null) const SizedBox(width: 10),
                      Text(
                        _ordinal(board.myRank!),
                        style: AppTextStyles.labelSmall.copyWith(
                          color: NuvoColors.actionBlue,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Container(height: 1, color: NuvoColors.divider),
                const SizedBox(height: 10),
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
                      const SizedBox(height: 6),
                  ],
                const SizedBox(height: 14),
                isResult
                    ? NuvoOutlineButton(
                        label: 'Open board',
                        icon: Icons.arrow_forward_rounded,
                        expand: true,
                        onPressed: onOpen,
                      )
                    : NuvoPrimaryButton(
                        label: board.primaryActionLabel,
                        expand: true,
                        onPressed: onLogMove,
                      ),
              ],
            ),
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
    final avatarColor =
        isCurrentUser ? NuvoColors.navy : nuvoAvatarColorFor(label);
    final initials = (initialsOverride != null && initialsOverride!.isNotEmpty)
        ? initialsOverride!
        : _initials(label);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: isCurrentUser
          ? BoxDecoration(
              color: NuvoColors.panel,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: NuvoColors.border),
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
              color:
                  isCurrentUser ? NuvoColors.actionBlue : NuvoColors.textMuted,
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
    const offset = 3.0;
    final face = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? NuvoColors.actionBlue : NuvoColors.surface,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: selected ? NuvoColors.inkNavy : NuvoColors.border,
          width: selected ? 2 : 1,
        ),
      ),
      child: Text(
        board.title,
        style: AppTextStyles.labelMedium.copyWith(
          color: selected ? NuvoColors.white : NuvoColors.navy,
          fontWeight: FontWeight.w800,
        ),
        maxLines: 1,
      ),
    );

    return PressableScale(
      onTap: onTap,
      child: selected
          ? Padding(
              padding: const EdgeInsets.only(right: offset, bottom: offset),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: offset,
                    top: offset,
                    right: 0,
                    bottom: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: NuvoColors.inkNavy,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  face,
                ],
              ),
            )
          : face,
    );
  }
}

// ── Compact board row ─────────────────────────────────────────────────────────

class _CompactBoardRow extends StatelessWidget {
  const _CompactBoardRow({required this.board, required this.onTap});

  final ArenaBoard board;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pct = board.progressPercent ?? 0;
    final count = board.racerCount ?? 0;
    final isComplete = pct >= 100;

    final plate = isComplete ? NuvoColors.success : NuvoColors.offsetGrey;

    return PressableScale(
      onTap: onTap,
      child: NuvoHardOffset(
        offset: 3,
        radius: 18,
        plateColor: plate,
        faceColor: NuvoColors.white,
        borderColor: plate,
        borderWidth: 1.5,
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    board.title,
                    style: AppTextStyles.titleMedium.copyWith(
                      color: NuvoColors.navy,
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    board.boardContext,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: NuvoColors.muted,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (board.miniLeaderboard.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    NuvoAvatarStack(
                      avatars: board.miniLeaderboard
                          .map(
                            (r) => (
                              initials: _initials(r.label),
                              photoUrl: r.profilePhotoUrl,
                            ),
                          )
                          .toList(),
                      total: count,
                      size: 22,
                      max: 3,
                      borderColor: NuvoColors.white,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: isComplete
                        ? NuvoColors.success.withValues(alpha: 0.10)
                        : NuvoColors.actionBlue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: isComplete
                          ? NuvoColors.success
                          : NuvoColors.actionBlue,
                      width: 1.3,
                    ),
                  ),
                  child: Text(
                    '$pct%',
                    style: AppTextStyles.labelMedium.copyWith(
                      color: isComplete
                          ? NuvoColors.success
                          : NuvoColors.actionBlue,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const NuvoIcon(
                  NuvoIconType.arrow,
                  color: NuvoColors.textMuted,
                  size: 14,
                ),
              ],
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
      height: 120,
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
      width: 148,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NuvoColors.border),
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

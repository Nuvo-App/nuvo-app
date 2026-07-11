import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/animations.dart' hide PressableScale;
import '../../../core/widgets/nuvo_avatar.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_icons.dart';
import '../../../core/widgets/count_up_text.dart';
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

    final firstName = user?.fullName?.split(' ').first ?? 'there';
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
      backgroundColor: const Color(0xFFF8FBFF),
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
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: _ArenaHeader(
                    firstName: firstName,
                    initials: initials,
                    liveCount: snapshot?.liveBoards.length ?? 0,
                    rank: activeBoard?.myRank,
                    rankBoardTitle: activeBoard?.title,
                    chaseCopy: activeBoard?.chaseCopy,
                    hasActivity: (snapshot?.activity.isNotEmpty ?? false),
                    onAvatarTap: () => _showNotificationsSheet(
                      context,
                      snapshot?.activity ?? const [],
                    ),
                  ),
                ),
              ),

              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    if ((arenaState.loading && snapshot == null) ||
                        (raceState.loading && raceState.races.isEmpty))
                      const _LoadingState()
                    else if (arenaState.error != null && snapshot == null)
                      _ErrorState(
                        message: arenaState.error!,
                        onRetry: () => ref
                            .read(arenaControllerProvider.notifier)
                            .loadSnapshot(),
                      )
                    else if (snapshot == null ||
                        snapshot.isEmpty ||
                        allBoards.isEmpty)
                      _EmptyState(
                        onStart: () => context.push('/races/new'),
                        onJoin: () => context.push('/races/join'),
                      )
                    else ...[
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
                        const SizedBox(height: 28),
                        const _SectionLabel(label: 'Crew activity'),
                        const SizedBox(height: 12),
                        _ActivityFeed(activity: snapshot.activity),
                      ],

                      if (allBoards.length > 1) ...[
                        const SizedBox(height: 20),
                        _RaceChipRow(
                          boards: allBoards,
                          selectedId: resolvedId,
                          onTap: (b) => _onChipTap(b, snapshot, user?.id),
                        ),
                      ],

                      if (otherBoards.isNotEmpty) ...[
                        const SizedBox(height: 28),
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
    required this.firstName,
    required this.initials,
    required this.liveCount,
    required this.onAvatarTap,
    this.rank,
    this.rankBoardTitle,
    this.chaseCopy,
    this.hasActivity = false,
  });

  final String firstName;
  final String initials;
  final int liveCount;
  final VoidCallback onAvatarTap;
  final int? rank;
  final String? rankBoardTitle;
  final String? chaseCopy;
  final bool hasActivity;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 20, 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [NuvoColors.blue, NuvoColors.blue2],
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: NuvoColors.blue.withValues(alpha: 0.28),
            blurRadius: 32,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: NuvoColors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _BlinkingDot(color: NuvoColors.white),
                    const SizedBox(width: 6),
                    Text(
                      '$liveCount live',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: NuvoColors.white,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              PressableScale(
                onTap: onAvatarTap,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: NuvoColors.white.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const NuvoIcon(
                        NuvoIconType.bell,
                        color: NuvoColors.white,
                        size: 16,
                      ),
                      if (hasActivity)
                        Positioned(
                          top: -1,
                          right: -1,
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: NuvoColors.amber,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: NuvoColors.blue2,
                                width: 1.4,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: NuvoColors.white.withValues(alpha: 0.22),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: NuvoColors.white.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  initials,
                  style: AppTextStyles.labelMedium.copyWith(
                    color: NuvoColors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Hi, $firstName.',
            style: AppTextStyles.headlineLarge.copyWith(
              color: NuvoColors.white,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            chaseCopy ?? 'Your crew is waiting. Move the leaderboard.',
            style: AppTextStyles.bodyMedium.copyWith(
              color: NuvoColors.white.withValues(alpha: 0.82),
            ),
          ),
          if (rank != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                _HeroStat(
                  icon: NuvoIconType.trendUp,
                  rank: rank,
                  rankBoardTitle: rankBoardTitle,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _BlinkingDot extends StatefulWidget {
  const _BlinkingDot({required this.color});
  final Color color;

  @override
  State<_BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<_BlinkingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 1.0, end: 0.35).animate(_ctrl),
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.icon,
    this.rank,
    this.rankBoardTitle,
  });
  final NuvoIconType icon;
  final int? rank;
  final String? rankBoardTitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        color: NuvoColors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          NuvoIcon(icon, size: 12, color: NuvoColors.white),
          const SizedBox(width: 7),
          if (rank != null)
            CountUpText(
              value: rank!,
              prefix: '#',
              style: AppTextStyles.labelMedium.copyWith(
                color: NuvoColors.white,
                fontWeight: FontWeight.w800,
              ),
            )
          else
            Text(
              rankBoardTitle != null
                  ? '#$rank in $rankBoardTitle'
                  : '#$rank',
              style: AppTextStyles.labelMedium.copyWith(
                color: NuvoColors.white,
              ),
            ),
        ],
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
            color: NuvoColors.blue,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: AppTextStyles.labelMedium.copyWith(
            color: NuvoColors.muted,
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
    this.participants,
  });

  final ArenaBoard board;
  final bool isLoading;
  final VoidCallback onLogMove;
  final VoidCallback onOpen;
  final String? currentUserId;

  /// Real per-racer progress when the full race detail has loaded — drives
  /// the Race Ring's other-racer markers. Null until then (ring shows only
  /// your own arc, no fabricated markers).
  final List<RaceParticipant>? participants;

  @override
  Widget build(BuildContext context) {
    final isResult = board.isResult;
    final pct = board.progressPercent ?? 0;
    final ringRacers = (participants ?? const [])
        .map(
          (p) => RingRacer(
            id: p.userId,
            initials: _initials(p.displayName),
            progress: p.progressPercent / 100.0,
            isCurrentUser: currentUserId != null && p.userId == currentUserId,
            photoUrl: p.profilePhotoUrl,
          ),
        )
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF07152B),
          width: 2,
        ),
        boxShadow: const [
          // getnuvo.net hard offset
          BoxShadow(
            color: Color(0xFF07152B),
            blurRadius: 0,
            offset: Offset(5, 5),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Progress stripe — clipped by parent container's borderRadius
          if (isLoading)
            LinearProgressIndicator(
              color: NuvoColors.blue,
              backgroundColor: NuvoColors.blue.withValues(alpha: 0.10),
              minHeight: 2,
            )
          else if (pct > 0)
            LinearProgressIndicator(
              value: pct / 100,
              color: isResult ? NuvoColors.success : NuvoColors.blue,
              backgroundColor: NuvoColors.blue.withValues(alpha: 0.08),
              minHeight: 3,
            ),

          Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (board.badgeLabel != null)
                            Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: NuvoColors.blue.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                board.badgeLabel!,
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: NuvoColors.blue,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          Hero(
                            tag: 'race-title-${board.id}',
                            flightShuttleBuilder:
                                (context, anim, direction, from, to) {
                              return FadeTransition(
                                opacity: anim,
                                child: Text(
                                  board.title,
                                  style: AppTextStyles.headlineMedium.copyWith(
                                    color: NuvoColors.navy,
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
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: isResult
                            ? NuvoColors.success.withValues(alpha: 0.10)
                            : NuvoColors.blue.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        '$pct%',
                        style: AppTextStyles.labelLarge.copyWith(
                          color: isResult
                              ? NuvoColors.success
                              : NuvoColors.blue,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),
                Text(
                  board.boardContext,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: NuvoColors.muted,
                    height: 1.4,
                  ),
                ),

                if (!isResult && !isLoading) ...[
                  const SizedBox(height: 18),
                  Center(
                    child: RaceRing(
                      progress: pct / 100.0,
                      centerValue: '$pct',
                      centerLabel: '%',
                      delay: const Duration(milliseconds: 180),
                      racers: ringRacers,
                    ),
                  ),
                ],

                // Crew strip
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (board.miniLeaderboard.isNotEmpty)
                      NuvoAvatarStack(
                        avatars: board.miniLeaderboard
                            .map(
                              (r) => (
                                initials: r.label,
                                photoUrl: r.profilePhotoUrl,
                              ),
                            )
                            .toList(),
                        total: board.racerCount ?? board.miniLeaderboard.length,
                        size: 24,
                        max: 4,
                        borderColor: NuvoColors.surface,
                      ),
                    const Spacer(),
                    if (board.daysLeft != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.schedule_rounded,
                            size: 12,
                            color: NuvoColors.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${board.daysLeft}d left',
                            style: AppTextStyles.labelSmall.copyWith(
                              color: NuvoColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),

                // Rank + chase
                if (board.myRank != null && !isResult) ...[
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    decoration: BoxDecoration(
                      color: NuvoColors.panel,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: NuvoColors.blue.withValues(alpha: 0.14),
                      ),
                    ),
                    child: Row(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '#${board.myRank}',
                              style: AppTextStyles.displaySmall.copyWith(
                                color: NuvoColors.blue,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'of ${board.racerCount ?? 1}',
                              style: AppTextStyles.labelSmall.copyWith(
                                color: NuvoColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                        if (board.chaseCopy != null) ...[
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              board.chaseCopy!,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: NuvoColors.muted,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // Divider
                Container(height: 1, color: NuvoColors.divider),
                const SizedBox(height: 16),

                // Mini leaderboard
                if (isLoading)
                  ..._buildSkeletonRows()
                else
                  for (var i = 0; i < board.miniLeaderboard.length; i++) ...[
                    _LeaderboardRow(
                      rank: i + 1,
                      label: board.miniLeaderboard[i].label,
                      value: board.miniLeaderboard[i].value,
                      isCurrentUser: board.miniLeaderboard[i].isCurrentUser,
                      photoUrl: board.miniLeaderboard[i].profilePhotoUrl,
                    ),
                    if (i < board.miniLeaderboard.length - 1)
                      const SizedBox(height: 10),
                  ],

                const SizedBox(height: 20),

                // CTA
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
        if (i < 2) const SizedBox(height: 10),
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
  });

  final int rank;
  final String label;
  final String value;
  final bool isCurrentUser;
  final String? photoUrl;

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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: isCurrentUser
          ? BoxDecoration(
              color: NuvoColors.panel,
              borderRadius: BorderRadius.circular(12),
            )
          : null,
      child: Row(
        children: [
          SizedBox(
            width: 20,
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
                initials: _initials(label),
                photoUrl: photoUrl,
                size: 30,
                bgColor: avatarColor,
                textColor: Colors.white,
                borderColor: tierColor,
                borderWidth: tierColor != null ? 2 : 1.5,
              ),
              if (rank == 1)
                const Positioned(
                  top: -11,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: NuvoIcon(
                      NuvoIconType.crown,
                      size: 13,
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
                fontWeight: isCurrentUser ? FontWeight.w600 : FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            value,
            style: AppTextStyles.labelSmall.copyWith(
              color: isCurrentUser ? NuvoColors.blue : NuvoColors.textMuted,
              fontWeight: isCurrentUser ? FontWeight.w700 : FontWeight.w500,
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? NuvoColors.blue : NuvoColors.surface,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: selected ? NuvoColors.blue : NuvoColors.border,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: NuvoColors.blue.withValues(alpha: 0.28),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ]
              : null,
        ),
        child: Text(
          board.title,
          style: AppTextStyles.labelMedium.copyWith(
            color: selected ? NuvoColors.white : NuvoColors.navy,
          ),
          maxLines: 1,
        ),
      ),
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

    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: NuvoColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: NuvoColors.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x08050B14),
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    board.title,
                    style: AppTextStyles.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    board.boardContext,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: NuvoColors.muted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (board.miniLeaderboard.isNotEmpty) ...[
              const SizedBox(width: 10),
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
                borderColor: NuvoColors.surface,
              ),
            ],
            const SizedBox(width: 12),
            Text(
              '$pct%',
              style: AppTextStyles.labelMedium.copyWith(
                color: isComplete ? NuvoColors.success : NuvoColors.blue,
              ),
            ),
            const SizedBox(width: 4),
            const NuvoIcon(
              NuvoIconType.arrow,
              color: NuvoColors.textMuted,
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
      height: 128,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: activity.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) => FadeSlideIn(
          delay: Duration(milliseconds: 60 * i),
          child: _ActivityCard(item: activity[i]),
        ),
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
      width: 152,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NuvoColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08050B14),
            blurRadius: 18,
            offset: Offset(0, 8),
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
                size: 26,
                bgColor: avatarColor,
                textColor: Colors.white,
              ),
              const SizedBox(width: 7),
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
              NuvoIcon(_icon, size: 13, color: NuvoColors.blue),
              const SizedBox(width: 5),
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
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: NuvoColors.blue.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const NuvoIcon(
            NuvoIconType.bolt,
            color: NuvoColors.blue,
            size: 26,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Your arena is empty.',
          style: AppTextStyles.headlineMedium.copyWith(color: NuvoColors.navy),
        ),
        const SizedBox(height: 8),
        Text(
          'Set a finish line, pull in your crew, and move the leaderboard together.',
          style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
        ),
        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: NuvoColors.panel,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: NuvoColors.blue.withValues(alpha: 0.15)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 62,
                height: 26,
                child: Stack(
                  children: [
                    for (var i = 0; i < 3; i++)
                      Positioned(
                        left: i * 16.0,
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: NuvoColors.blue.withValues(
                              alpha: 0.08 + i * 0.06,
                            ),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: NuvoColors.surface,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Invite your crew to race against you.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: NuvoColors.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
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
            child: NuvoIcon(_icon, size: 15, color: NuvoColors.blue),
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
                    color: NuvoColors.blue.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const NuvoIcon(
                    NuvoIconType.bell,
                    color: NuvoColors.blue,
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
                      'When your crew joins or crosses the finish line, you\'ll see it here.',
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

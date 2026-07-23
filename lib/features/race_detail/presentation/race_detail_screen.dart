import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_geometry.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/competition_ring.dart';
import '../../../core/widgets/nuvo_board_components.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_icons.dart';
import '../../../core/widgets/nuvo_move_log_item.dart';
import '../../../core/widgets/nuvo_shared_components.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../auth/data/auth_api.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../races/data/race_models.dart';
import '../../races/domain/chase_context.dart';
import '../../races/domain/camera_verification_resolver.dart';
import '../../races/domain/race_display.dart';
import '../../races/presentation/race_controller.dart';

// ── Screen ────────────────────────────────────────────────────────────────────

class RaceDetailScreen extends ConsumerStatefulWidget {
  const RaceDetailScreen({super.key, required this.id});
  final String id;

  @override
  ConsumerState<RaceDetailScreen> createState() => _RaceDetailScreenState();
}

class _RaceDetailScreenState extends ConsumerState<RaceDetailScreen> {
  Race? _race;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _silentRefresh(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _silentRefresh() async {
    if (_loading) return;
    try {
      final race = await ref
          .read(raceControllerProvider.notifier)
          .getRaceDetail(widget.id);
      if (mounted) setState(() => _race = race);
    } catch (_) {}
  }

  Future<void> _load() async {
    // Use cached race from controller first to prevent stale 0% flash
    final cachedRaces = ref.read(raceControllerProvider).races;
    final cached = cachedRaces.where((r) => r.id == widget.id).firstOrNull;
    if (cached != null && _race == null) {
      setState(() {
        _race = cached;
        _loading = false;
      });
      // Still refresh from network in the background
      _silentRefresh();
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final race = await ref
          .read(raceControllerProvider.notifier)
          .getRaceDetail(widget.id);
      if (mounted) {
        setState(() {
          _race = race;
          _loading = false;
        });
        debugLogCameraVerificationDecision(
          race,
          resolveCameraVerification(race),
          routeAction: 'race_detail_loaded',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _race = null;
          _error = 'Could not load race.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _copyInviteCode() async {
    final race = _race;
    if (race == null) return;
    var code = race.inviteCode;
    if (code == null &&
        race.creatorId == ref.read(authControllerProvider).user?.id) {
      setState(() => _busy = true);
      try {
        code = await ref
            .read(raceControllerProvider.notifier)
            .createInviteCode(race.id);
        final fresh = await ref
            .read(raceControllerProvider.notifier)
            .getRaceDetail(race.id);
        if (mounted) setState(() => _race = fresh);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not create invite code.')),
          );
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
    if (code == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ask the race creator for an invite code.'),
        ),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invite code copied.')));
    }
  }

  Future<void> _joinRace() async {
    final race = _race;
    if (race == null) return;
    setState(() => _busy = true);
    try {
      final joined = await ref
          .read(raceControllerProvider.notifier)
          .joinRace(race.id);
      if (mounted) {
        setState(() {
          _race = joined;
          _busy = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not join this race.')),
        );
      }
    }
  }

  Future<void> _leaveRace() async {
    final race = _race;
    if (race == null) return;
    final confirmed = await _confirm(
      title: 'Leave race?',
      message:
          'You will leave this leaderboard. You can rejoin later with an invite code.',
      confirmLabel: 'Leave',
    );
    if (!confirmed) return;
    setState(() => _busy = true);
    try {
      await ref.read(raceControllerProvider.notifier).leaveRace(race.id);
      if (mounted) context.go('/arena');
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not leave this race.')),
        );
      }
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    return NuvoConfirmSheet.show(
      context,
      title: title,
      message: message,
      confirmLabel: confirmLabel,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const Center(
          child: CircularProgressIndicator(
            color: NuvoColors.blue,
            strokeWidth: 2,
          ),
        ),
      );
    }

    if (_race == null) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: NuvoBackButton(
                  onPressed: () => safePopOrGo(context, '/arena'),
                ),
              ),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _error ?? 'Race not found.',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: NuvoColors.muted,
                        ),
                      ),
                      const SizedBox(height: 16),
                      NuvoGhostButton(
                        label: 'Retry',
                        onPressed: _load,
                        small: true,
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

    final race = _race!;
    final user = ref.watch(authControllerProvider).user;
    final isOwner = user != null && race.isCreator(user.id);
    final isParticipant = user != null && race.isParticipant(user.id);
    final eligibility = resolveCameraVerification(race);
    final canVerify =
        raceIsActive(race) &&
        (isOwner || isParticipant) &&
        eligibility.isCameraVerifiable;
    final canJoin = raceIsActive(race) && !isOwner && !isParticipant;
    final myPart = isParticipant ? race.participantFor(user.id) : null;
    final myProgress = raceProgressPercent(race, myPart);
    final myRaceComplete = raceIsCompleted(race);

    final sorted = serverRankedParticipants(race);
    final chase = user == null ? null : ChaseContext.compute(race, user.id);
    final rank = rankForUser(race, user?.id);
    final heroChaseCopy = myRaceComplete
        ? (rank != null
              ? 'Finish line crossed · you placed #$rank.'
              : 'Finish line crossed.')
        : chase?.chaseCopy;
    final boardParticipants = [
      for (var i = 0; i < sorted.length; i++)
        NuvoBoardParticipant(
          rank: sorted[i].rank ?? i + 1,
          name: sorted[i].displayName,
          initials: _initials(sorted[i].displayName),
          progressPercent: raceProgressPercent(race, sorted[i]),
          progressLabel: raceProgressLabel(race, sorted[i]),
          photoUrl: sorted[i].profilePhotoUrl,
          isCurrentUser: user != null && sorted[i].userId == user.id,
        ),
    ];
    final heroAvatars = sorted
        .map(
          (p) =>
              (initials: _initials(p.displayName), photoUrl: p.profilePhotoUrl),
        )
        .toList();
    final movementAvatars = race.recentProofs
        .map(
          (p) =>
              (initials: _initials(p.displayName), photoUrl: p.profilePhotoUrl),
        )
        .toList();
    final recentMoveCount = race.recentProofs.length;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          // ── Race header ─────────────────────────────────────────────────────
          _NavyHeader(
            race: race,
            myProgress: myProgress,
            isParticipant: isParticipant,
            userId: user?.id,
            onBack: () => safePopOrGo(context, '/arena'),
            onSettings: isOwner
                ? () => context.push('/race/${race.id}/settings')
                : null,
          ),

          // ── Scrollable white body ───────────────────────────────────────────
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 28, 22, 56),
                children: [
                  NuvoRaceHero(
                    title: null,
                    contextLine: null,
                    rankLabel: raceRankLabel(race, user?.id),
                    chaseCopy: heroChaseCopy,
                    subcopy: _heroSubcopy(
                      race: race,
                      userId: user?.id,
                      recentMoveCount: recentMoveCount,
                    ),
                    avatars: heroAvatars,
                    racerCount: race.participantCount,
                    daysLeft: myRaceComplete
                        ? null
                        : _daysLeft(race.finishLineAt),
                    badgeLabel: eligibility.movementDefinition?.title,
                    progressPercent: myRaceComplete ? myProgress : null,
                    isComplete: myRaceComplete,
                    ringParticipants: race.participants
                        .map(
                          (p) => CompetitionRingParticipant(
                            userId: p.userId,
                            displayName: p.displayName,
                            photoUrl: p.profilePhotoUrl,
                            progressPercent: raceProgressPercent(race, p),
                          ),
                        )
                        .toList(),
                    currentUserId: user?.id,
                    primaryLabel: canJoin
                        ? 'Join race'
                        : myRaceComplete
                        ? 'Start another race'
                        : eligibility.isCameraVerifiable
                        ? 'Submit proof'
                        : 'Unsupported',
                    loading: _busy,
                    onPrimary: _busy
                        ? null
                        : canJoin
                        ? _joinRace
                        : myRaceComplete
                        ? () => context.push('/races/new')
                        : canVerify
                        ? () async {
                            debugLogCameraVerificationDecision(
                              race,
                              eligibility,
                              routeAction: 'race_detail_to_submit_proof',
                            );
                            await context.push('/race/${race.id}/proof');
                            _load();
                          }
                        : null,
                  ),

                  if (raceIsActive(race) &&
                      !eligibility.isCameraVerifiable) ...[
                    const SizedBox(height: 12),
                    _UnsupportedVerificationNotice(
                      message: eligibility.unsupportedMessage,
                    ),
                  ],

                  if (isParticipant && myRaceComplete) ...[
                    const SizedBox(height: 12),
                    _CompleteCallout(
                      race: race,
                      participant: myPart,
                      rank: rank,
                    ),
                  ],

                  if (isParticipant && !myRaceComplete) ...[
                    const SizedBox(height: 24),
                    const _SectionLabel(label: 'Path to goal'),
                    const SizedBox(height: 12),
                    _CheckpointPath(
                      progressPercent: myProgress,
                      progressValue: myPart?.progressValue,
                      targetValue: race.targetValue,
                      unit: raceMetricLabel(race),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // ── Final standings (completed races only) ──────────────
                  if (myRaceComplete && race.finalStandings.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const _SectionLabel(label: 'Final standings'),
                    const SizedBox(height: 12),
                    for (var i = 0; i < race.finalStandings.length; i++) ...[
                      _FinalStandingRow(
                        standing: race.finalStandings[i],
                        isCurrentUser:
                            user != null &&
                            race.finalStandings[i].userId == user.id,
                        race: race,
                      ),
                      if (i < race.finalStandings.length - 1)
                        const SizedBox(height: 6),
                    ],
                  ],

                  // ── Board ──────────────────────────────────────────────────
                  const _SectionLabel(label: 'The board'),
                  const SizedBox(height: 12),
                  if (sorted.isEmpty)
                    Text(
                      'No one on the board yet. Invite crew to race.',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: NuvoColors.muted,
                      ),
                    )
                  else
                    for (var i = 0; i < boardParticipants.length; i++) ...[
                      NuvoBoardLane(participant: boardParticipants[i]),
                      if (i < boardParticipants.length - 1)
                        const SizedBox(height: 6),
                    ],

                  if (race.participantCount > 1) ...[
                    const SizedBox(height: 14),
                    NuvoBoardMovementStrip(
                      label: recentMoveCount == 0
                          ? 'Board is waiting for the first move.'
                          : 'Board moved ${recentMoveCount == 1 ? 'once' : '$recentMoveCount times'} recently',
                      movers: movementAvatars.take(3).toList(),
                    ),
                  ],

                  if (canVerify && isOwner && !myRaceComplete) ...[
                    const SizedBox(height: 18),
                    NuvoOutlineButton(
                      label: 'Invite crew',
                      expand: true,
                      onPressed: _busy
                          ? null
                          : () => context.push('/race/${race.id}/invite'),
                    ),
                  ],

                  const SizedBox(height: 30),

                  // ── Move log ────────────────────────────────────────────────
                  const _SectionLabel(label: 'Move log'),
                  const SizedBox(height: 12),
                  if (race.recentProofs.isEmpty)
                    Text(
                      'No moves logged yet.',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: NuvoColors.muted,
                      ),
                    )
                  else
                    for (final proof in race.recentProofs.take(8))
                      NuvoMoveLogItem(
                        displayName: proof.displayName,
                        profilePhotoUrl: proof.profilePhotoUrl,
                        actionLine: _moveActionLine(proof, race),
                        createdAt: proof.createdAt,
                        valueLabel: proof.value != null
                            ? '+${raceScoreLabel(race, proof.value!)}'
                            : null,
                        isPositive:
                            proof.verificationStatus == 'accepted' ||
                            proof.verificationStatus == 'ai_verified',
                        onTap: isOwner
                            ? () => context.push(
                                '/race/${race.id}/proofs/${proof.id}',
                              )
                            : null,
                      ),

                  const SizedBox(height: 28),

                  // ── Rules (hidden on completed races) ────────────────────
                  if (!myRaceComplete) ...[
                    const _SectionLabel(label: 'Rules'),
                    const SizedBox(height: 10),
                    Text(
                      race.rules?.isNotEmpty == true
                          ? race.rules!
                          : _rulesCopy(race),
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: NuvoColors.muted,
                      ),
                    ),
                  ],

                  // ── Owner manage section ────────────────────────────────────
                  if (isOwner) ...[
                    const SizedBox(height: 28),
                    const _SectionLabel(label: 'Manage'),
                    const SizedBox(height: 12),
                    _ManageRow(
                      icon: Icons.edit_rounded,
                      label: 'Edit race',
                      onTap: () => context.push('/race/${race.id}/edit'),
                    ),
                    const SizedBox(height: 8),
                    _ManageRow(
                      icon: Icons.tune_rounded,
                      label: 'Race settings',
                      onTap: () => context.push('/race/${race.id}/settings'),
                    ),
                    const SizedBox(height: 8),
                    _ManageRow(
                      icon: Icons.ios_share_rounded,
                      label: 'Share race',
                      onTap: () =>
                          Share.share('Racing "${race.title}" on Nuvo.'),
                    ),
                    const SizedBox(height: 8),
                    _ManageRow(
                      icon: Icons.copy_rounded,
                      label: 'Copy invite code',
                      onTap: _copyInviteCode,
                    ),
                  ],

                  // ── Leave (non-owner participant) ───────────────────────────
                  if (isParticipant && !isOwner) ...[
                    const SizedBox(height: 28),
                    NuvoDangerButton(
                      label: 'Leave race',
                      expand: true,
                      onPressed: _busy ? null : _leaveRace,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Race header ───────────────────────────────────────────────────────────────

class _NavyHeader extends StatelessWidget {
  const _NavyHeader({
    required this.race,
    required this.myProgress,
    required this.isParticipant,
    required this.onBack,
    this.userId,
    this.onSettings,
  });

  final Race race;
  final int myProgress;
  final bool isParticipant;
  final String? userId;
  final VoidCallback onBack;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    final safeTop = MediaQuery.paddingOf(context).top;
    final isActive = race.status == 'active';
    final isComplete = raceIsCompleted(race);
    final me = userId == null ? null : race.participantFor(userId!);
    final score = me == null
        ? '$myProgress% verified'
        : raceProgressLabel(race, me);
    final firstSpace = score.indexOf(' ');
    final scoreNumber = firstSpace == -1
        ? score
        : score.substring(0, firstSpace);
    final scoreUnit = firstSpace == -1
        ? 'verified'
        : score.substring(firstSpace + 1);
    const navy = NuvoColors.border;
    const brightBlue = NuvoColors.actionBlue;

    return Container(
      color: NuvoColors.pageIce,
      padding: EdgeInsets.fromLTRB(22, safeTop + 16, 22, 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        decoration: BoxDecoration(
          color: NuvoColors.surface,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: isComplete
                ? NuvoColors.success.withValues(alpha: 0.24)
                : navy,
          ),
          boxShadow: AppShadows.hardShadow3,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PressableScale(
                  onTap: onBack,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: NuvoColors.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: navy),
                    ),
                    child: const NuvoIcon(
                      NuvoIconType.back,
                      color: NuvoColors.navy,
                      size: 18,
                    ),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: isComplete
                        ? NuvoColors.success.withValues(alpha: 0.12)
                        : isActive
                        ? brightBlue.withValues(alpha: 0.10)
                        : NuvoColors.panel,
                    borderRadius: BorderRadius.circular(NuvoRadii.pill),
                    border: Border.all(
                      color: isComplete
                          ? NuvoColors.success
                          : isActive
                          ? brightBlue
                          : navy,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    isComplete
                        ? 'Finish line'
                        : isActive
                        ? 'Live'
                        : race.status.toUpperCase(),
                    style: AppTextStyles.labelSmall.copyWith(
                      color: isComplete
                          ? NuvoColors.success
                          : isActive
                          ? brightBlue
                          : NuvoColors.navy,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (onSettings != null) ...[
                  const SizedBox(width: 8),
                  PressableScale(
                    onTap: onSettings,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: NuvoColors.surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: navy),
                      ),
                      child: const Icon(
                        Icons.tune_rounded,
                        color: NuvoColors.navy,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ],
            ),

            const SizedBox(height: 16),

            // Race title — Hero matches arena card for shared-element transition
            Hero(
              tag: 'race-title-${race.id}',
              child: Material(
                color: Colors.transparent,
                child: Text(
                  race.displayTitle,
                  style: AppTextStyles.headlineLarge.copyWith(
                    color: NuvoColors.navy,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final chip in _headerChips(race))
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: brightBlue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: brightBlue.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Text(
                      chip,
                      style: AppTextStyles.labelSmall.copyWith(
                        color: brightBlue,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),

            // My progress — only shown when participant
            if (isParticipant) ...[
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    scoreNumber,
                    style: AppTextStyles.displaySmall.copyWith(
                      color: isComplete ? NuvoColors.success : brightBlue,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4, left: 3),
                    child: Text(
                      scoreUnit,
                      style: AppTextStyles.titleLarge.copyWith(
                        color: isComplete
                            ? NuvoColors.success.withValues(alpha: 0.8)
                            : brightBlue.withValues(alpha: 0.75),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      isComplete ? 'Finish line crossed' : 'Your progress',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: NuvoColors.muted,
                        letterSpacing: 0,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              NuvoRaceLane(
                progressPercent: myProgress,
                trackHeight: 5,
                dotDiameter: 16,
                onDark: false,
              ),
              Builder(
                builder: (context) {
                  if (userId == null) return const SizedBox.shrink();
                  final chase = ChaseContext.compute(race, userId!);
                  final copy = isComplete
                      ? 'Pull in your crew and move the board again.'
                      : chase.chaseCopy;
                  if (copy == null || copy.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      copy,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: NuvoColors.navy,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<String> _headerChips(Race race) {
    final chips = <String>[];
    final eligibility = resolveCameraVerification(race);
    if (eligibility.isCameraVerifiable) {
      chips.add('Camera verified');
    } else {
      chips.add('Proof needed');
    }
    if (race.targetValue != null) {
      chips.add('First to ${raceTargetLabel(race)}');
    }
    return chips;
  }
}

String _rulesCopy(Race race) {
  if (race.format == 'first_to_goal') {
    return 'Every verified session adds to your total. First racer to the finish line wins.';
  }
  return 'Submit verified proof before the finish line. Nuvo updates the leaderboard.';
}

// ── Checkpoint path ────────────────────────────────────────────────────────────

enum _NodeState { done, current, todo }

class _Checkpoint {
  const _Checkpoint({
    required this.label,
    required this.sub,
    required this.state,
    required this.marker,
  });
  final String label;
  final String sub;
  final _NodeState state;
  final String marker;
}

/// Duolingo-style vertical checkpoint path toward the race goal. Checkpoints
/// are derived from real progress (25/50/75/100% of the actual target or,
/// for percent-only races, of 100%) — never invented milestone content.
class _CheckpointPath extends StatelessWidget {
  const _CheckpointPath({
    required this.progressPercent,
    required this.progressValue,
    required this.targetValue,
    required this.unit,
  });

  final int progressPercent;
  final int? progressValue;
  final int? targetValue;
  final String? unit;

  static const _fractions = [0.25, 0.5, 0.75, 1.0];
  static const _labels = [
    'Quarter way',
    'Halfway',
    'Three quarters',
    'Finish line',
  ];

  @override
  Widget build(BuildContext context) {
    var currentAssigned = false;
    final checkpoints = <_Checkpoint>[];
    for (var i = 0; i < _fractions.length; i++) {
      final fraction = _fractions[i];
      final reached = progressPercent >= (fraction * 100).round();
      final marker = targetValue != null
          ? '${(targetValue! * fraction).round()}'
          : '${(fraction * 100).round()}%';

      _NodeState state;
      String sub;
      if (reached) {
        state = _NodeState.done;
        sub = 'Verified';
      } else if (!currentAssigned) {
        state = _NodeState.current;
        currentAssigned = true;
        sub = targetValue != null
            ? '$progressValue / $targetValue ${unit ?? ''}'.trim()
            : '$progressPercent% verified';
      } else {
        state = _NodeState.todo;
        sub = 'Not reached yet';
      }
      checkpoints.add(
        _Checkpoint(label: _labels[i], sub: sub, state: state, marker: marker),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: NuvoColors.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < checkpoints.length; i++)
            _CheckpointRow(
              checkpoint: checkpoints[i],
              isFirst: i == 0,
              isLast: i == checkpoints.length - 1,
            ),
        ],
      ),
    );
  }
}

class _CheckpointRow extends StatelessWidget {
  const _CheckpointRow({
    required this.checkpoint,
    required this.isFirst,
    required this.isLast,
  });
  final _Checkpoint checkpoint;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final c = checkpoint;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                if (!isFirst)
                  Positioned(
                    top: -10,
                    child: Container(
                      width: 2,
                      height: 10,
                      color: NuvoColors.divider,
                    ),
                  ),
                if (!isLast)
                  Positioned(
                    bottom: -10,
                    child: Container(
                      width: 2,
                      height: 10,
                      color: NuvoColors.divider,
                    ),
                  ),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: switch (c.state) {
                      _NodeState.done => NuvoColors.blue,
                      _NodeState.current => NuvoColors.navy,
                      _NodeState.todo => NuvoColors.surface,
                    },
                    border: c.state == _NodeState.todo
                        ? Border.all(color: NuvoColors.divider, width: 2)
                        : null,
                    boxShadow: c.state == _NodeState.current
                        ? const [
                            BoxShadow(
                              color: NuvoColors.panel,
                              blurRadius: 0,
                              spreadRadius: 5,
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    c.marker,
                    style: AppTextStyles.number(
                      12,
                      color: c.state == _NodeState.todo
                          ? NuvoColors.paleSlate
                          : Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.state == _NodeState.current ? 'You are here' : c.label,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: NuvoColors.navy,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  c.sub,
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

// ── Complete callout ──────────────────────────────────────────────────────────

class _UnsupportedVerificationNotice extends StatelessWidget {
  const _UnsupportedVerificationNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: NuvoColors.icyBlue,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NuvoColors.border),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.videocam_off_rounded,
            color: NuvoColors.navy,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.navy),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompleteCallout extends StatelessWidget {
  const _CompleteCallout({
    required this.race,
    required this.participant,
    this.rank,
  });
  final Race race;
  final RaceParticipant? participant;
  final int? rank;

  @override
  Widget build(BuildContext context) {
    final scoreText = raceProgressLabel(race, participant);
    final rankText = rank != null ? ' · #$rank' : '';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: NuvoColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NuvoColors.success.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const NuvoIcon(
            NuvoIconType.checkCircle,
            color: NuvoColors.success,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$scoreText$rankText', style: AppTextStyles.titleMedium),
                const SizedBox(height: 2),
                Text(
                  'Start another race with your crew.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: NuvoColors.muted,
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

// ── Move action line helper ───────────────────────────────────────────────────

String _moveActionLine(RaceProof proof, Race race) {
  final verb = proof.value != null
      ? 'logged ${raceScoreLabel(race, proof.value!)}'
      : 'logged a move';
  return switch (proof.verificationStatus) {
    'accepted' || 'ai_verified' => '$verb · Camera verified',
    'ai_failed' || 'rejected' => "$verb · Move didn't count",
    'needs_review' => '$verb · Under review',
    _ => verb,
  };
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
  final s = name.trim();
  return s.isEmpty ? '?' : s[0].toUpperCase();
}

String _heroSubcopy({
  required Race race,
  required String? userId,
  required int recentMoveCount,
}) {
  final sorted = serverRankedParticipants(race);
  final leader = sorted.isEmpty ? null : sorted.first;
  final me = userId == null ? null : race.participantFor(userId);
  if (me != null && raceIsCompleted(race)) {
    return 'You hit the finish line. Pull in your crew and move the board again.';
  }
  final parts = <String>[];

  if (leader != null && me != null && leader.userId != me.userId) {
    final gap = race.targetValue != null
        ? leader.progressValue - me.progressValue
        : leader.progressPercent - me.progressPercent;
    if (gap > 0) {
      parts.add(
        '${leader.displayName.split(' ').first} leads by ${raceScoreLabel(race, gap)}.',
      );
    }
  } else if (leader != null) {
    parts.add('${leader.displayName.split(' ').first} leads the board.');
  }

  if (recentMoveCount > 0) {
    parts.add(
      '$recentMoveCount ${recentMoveCount == 1 ? 'move' : 'moves'} logged recently.',
    );
  } else {
    parts.add('No moves logged yet.');
  }

  return parts.join(' ');
}

int? _daysLeft(String? finishLineAt) {
  if (finishLineAt == null || finishLineAt.isEmpty) return null;
  final finish = DateTime.tryParse(finishLineAt);
  if (finish == null) return null;
  final now = DateTime.now();
  final diff = finish.difference(now).inDays;
  return diff < 0 ? 0 : diff + 1;
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
        letterSpacing: -0.2,
      ),
    );
  }
}

// ── Final standing row ────────────────────────────────────────────────────────

class _FinalStandingRow extends StatelessWidget {
  const _FinalStandingRow({
    required this.standing,
    required this.isCurrentUser,
    required this.race,
  });

  final RaceFinalStanding standing;
  final bool isCurrentUser;
  final Race race;

  @override
  Widget build(BuildContext context) {
    final rankLabel = '#${standing.rank}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isCurrentUser
            ? NuvoColors.success.withValues(alpha: 0.08)
            : NuvoColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCurrentUser
              ? NuvoColors.success.withValues(alpha: 0.4)
              : NuvoColors.border,
          width: isCurrentUser ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              rankLabel,
              style: AppTextStyles.labelLarge.copyWith(
                color: standing.rank == 1
                    ? NuvoColors.success
                    : NuvoColors.muted,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              standing.displayName,
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: isCurrentUser ? FontWeight.w700 : FontWeight.w500,
                color: NuvoColors.navy,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          if (standing.scoreValue > 0)
            Text(
              raceScoreLabel(race, standing.scoreValue),
              style: AppTextStyles.labelMedium.copyWith(
                color: NuvoColors.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}

// ── Manage row ────────────────────────────────────────────────────────────────

class _ManageRow extends StatelessWidget {
  const _ManageRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: NuvoColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: NuvoColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, color: NuvoColors.navy, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const NuvoIcon(
              NuvoIconType.arrow,
              color: NuvoColors.muted,
              size: 14,
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
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
      return const Scaffold(
        backgroundColor: NuvoColors.page,
        body: Center(
          child: CircularProgressIndicator(
            color: NuvoColors.blue,
            strokeWidth: 2,
          ),
        ),
      );
    }

    if (_race == null) {
      return Scaffold(
        backgroundColor: NuvoColors.page,
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
        race.status == 'active' &&
        (isOwner || isParticipant) &&
        eligibility.isCameraVerifiable;
    final canJoin = race.status == 'active' && !isOwner && !isParticipant;
    final myPart = isParticipant ? race.participantFor(user.id) : null;
    final myProgress = myPart?.progressPercent ?? 0;
    final myRaceComplete = myPart != null && myProgress >= 100;

    // Sorted participants for leaderboard
    final sorted = [...race.participants]
      ..sort((a, b) => b.progressPercent.compareTo(a.progressPercent));
    final chase = user == null ? null : ChaseContext.compute(race, user.id);
    final rank = chase?.myRank;
    final heroChaseCopy = myRaceComplete
        ? (rank != null ? 'You finished #$rank.' : 'You finished.')
        : chase?.chaseCopy;
    final boardParticipants = [
      for (var i = 0; i < sorted.length; i++)
        NuvoBoardParticipant(
          rank: i + 1,
          name: sorted[i].displayName,
          initials: _initials(sorted[i].displayName),
          progressPercent: sorted[i].progressPercent,
          progressLabel: race.targetValue != null
              ? '${sorted[i].progressValue}/${race.targetValue}'
              : '${sorted[i].progressPercent}%',
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
      backgroundColor: NuvoColors.page,
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
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 48),
                children: [
                  NuvoRaceHero(
                    title: race.displayTitle,
                    contextLine: _contextLine(race),
                    rankLabel: rank == null ? '--' : '#$rank',
                    chaseCopy: heroChaseCopy,
                    subcopy: _heroSubcopy(
                      race: race,
                      userId: user?.id,
                      recentMoveCount: recentMoveCount,
                    ),
                    avatars: heroAvatars,
                    racerCount: race.participantCount,
                    daysLeft: _daysLeft(race.finishLineAt),
                    primaryLabel: canJoin
                        ? 'Join race'
                        : myRaceComplete
                        ? 'Start another race'
                        : eligibility.isCameraVerifiable
                        ? 'Log Move'
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

                  if (race.status == 'active' &&
                      !eligibility.isCameraVerifiable) ...[
                    const SizedBox(height: 12),
                    _UnsupportedVerificationNotice(
                      message: eligibility.unsupportedMessage,
                    ),
                  ],

                  if (canVerify && myRaceComplete) ...[
                    const SizedBox(height: 12),
                    _CompleteCallout(progress: myProgress)
                        .animate()
                        .fadeIn(duration: 220.ms, curve: Curves.easeOut)
                        .slideY(
                          begin: 0.08,
                          end: 0,
                          duration: 260.ms,
                          curve: Curves.easeOutCubic,
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
                      unit: race.unit,
                    ),
                  ],

                  const SizedBox(height: 24),

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
                      NuvoBoardLane(participant: boardParticipants[i])
                          .animate(delay: Duration(milliseconds: 60 * i))
                          .fadeIn(duration: 200.ms, curve: Curves.easeOut)
                          .slideX(
                            begin: 0.03,
                            end: 0,
                            duration: 240.ms,
                            curve: Curves.easeOutCubic,
                          ),
                      if (i < boardParticipants.length - 1)
                        const SizedBox(height: 8),
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
                        actionLine: _moveActionLine(proof, race.unit),
                        createdAt: proof.createdAt,
                        valueLabel: proof.value != null
                            ? '+${proof.value} ${race.unit ?? 'reps'}'
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
                          : 'Log moves before the finish line. Highest verified progress wins.',
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

    return Container(
      decoration: const BoxDecoration(
        color: NuvoColors.white,
        border: Border(bottom: BorderSide(color: NuvoColors.divider)),
      ),
      padding: EdgeInsets.fromLTRB(20, safeTop + 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back row
          Row(
            children: [
              PressableScale(
                onTap: onBack,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: NuvoColors.panel,
                    shape: BoxShape.circle,
                    border: Border.all(color: NuvoColors.border),
                  ),
                  child: const NuvoIcon(
                    NuvoIconType.back,
                    color: NuvoColors.navy,
                    size: 18,
                  ),
                ),
              ),
              const Spacer(),
              // Status pill
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: isActive ? NuvoColors.blue : NuvoColors.panel,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  isActive ? 'Active' : race.status.toUpperCase(),
                  style: AppTextStyles.labelSmall.copyWith(
                    color: isActive ? NuvoColors.white : NuvoColors.navy,
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
                      color: NuvoColors.panel,
                      shape: BoxShape.circle,
                      border: Border.all(color: NuvoColors.border),
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

          const SizedBox(height: 20),

          // Race title — Hero matches arena card for shared-element transition
          Hero(
            tag: 'race-title-${race.id}',
            child: Material(
              color: Colors.transparent,
              child: Text(
                race.displayTitle,
                style: AppTextStyles.headlineLarge.copyWith(color: NuvoColors.navy),
                maxLines: 2,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _contextLine(race),
            style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
          ),

          // My progress — only shown when participant
          if (isParticipant) ...[
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$myProgress',
                  style: AppTextStyles.displaySmall.copyWith(
                    color: myProgress >= 100
                        ? NuvoColors.success
                        : NuvoColors.blue,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4, left: 3),
                  child: Text(
                    '%',
                    style: AppTextStyles.titleLarge.copyWith(
                      color: NuvoColors.muted,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'Your progress',
              style: AppTextStyles.labelSmall.copyWith(
                color: NuvoColors.muted,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 14),
            NuvoRaceLane(progressPercent: myProgress, trackHeight: 5, dotDiameter: 16),
            // Chase context
            Builder(
              builder: (context) {
                if (userId == null) return const SizedBox.shrink();
                final chase = ChaseContext.compute(race, userId!);
                if (chase.chaseCopy == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    chase.chaseCopy!,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: NuvoColors.muted,
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  String _contextLine(Race race) {
    final parts = <String>[];
    final eligibility = resolveCameraVerification(race);
    if (eligibility.isCameraVerifiable) {
      parts.add('Camera verified');
    } else {
      parts.add(eligibility.unsupportedMessage);
    }
    if (race.targetValue != null) {
      parts.add('${race.targetValue} ${race.unit ?? 'reps'}');
    }
    return parts.join(' · ');
  }
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
        sub = 'Locked';
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

class _CompletedMilestones extends StatelessWidget {
  const _CompletedMilestones({
    required this.progressPercent,
    required this.progressValue,
    required this.targetValue,
    required this.unit,
  });

  final int progressPercent;
  final int? progressValue;
  final int? targetValue;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: NuvoColors.border),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
          initiallyExpanded: false,
          title: Text('Show completed path', style: AppTextStyles.titleMedium),
          subtitle: Text(
            'Finish line reached',
            style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
          ),
          children: [
            _CheckpointPath(
              progressPercent: progressPercent,
              progressValue: progressValue,
              targetValue: targetValue,
              unit: unit,
            ),
          ],
        ),
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
  const _CompleteCallout({required this.progress});
  final int progress;

  @override
  Widget build(BuildContext context) {
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
                Text(
                  '$progress% complete',
                  style: AppTextStyles.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  'Challenge your crew to beat your score.',
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

String _moveActionLine(RaceProof proof, String? unit) {
  final verb = proof.value != null
      ? 'logged ${proof.value} ${unit ?? 'reps'}'
      : 'logged a move';
  return switch (proof.verificationStatus) {
    'accepted' || 'ai_verified' => '$verb · Camera verified',
    'ai_failed' || 'rejected' => "$verb · Move didn't count",
    'needs_review' => '$verb · Under review',
    _ => verb,
  };
}

String _contextLine(Race race) {
  final parts = <String>[];
  final eligibility = resolveCameraVerification(race);
  if (eligibility.isCameraVerifiable) {
    parts.add('Camera verified');
  } else {
    parts.add(eligibility.unsupportedMessage);
  }
  if (race.targetValue != null) {
    parts.add('${race.targetValue} ${race.unit ?? 'reps'}');
  }
  return parts.join(' · ');
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
  final sorted = [...race.participants]
    ..sort((a, b) => b.progressPercent.compareTo(a.progressPercent));
  final leader = sorted.isEmpty ? null : sorted.first;
  final me = userId == null ? null : race.participantFor(userId);
  if (me != null && me.progressPercent >= 100) {
    return 'See if your crew can beat your finish.';
  }
  final parts = <String>[];

  if (leader != null && me != null && leader.userId != me.userId) {
    final gap = race.targetValue != null
        ? leader.progressValue - me.progressValue
        : leader.progressPercent - me.progressPercent;
    if (gap > 0) {
      parts.add('${leader.displayName.split(' ').first} leads by $gap.');
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
          color: NuvoColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: NuvoColors.divider),
        ),
        child: Row(
          children: [
            Icon(icon, color: NuvoColors.navy, size: 18),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: AppTextStyles.bodyMedium)),
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

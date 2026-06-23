import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_board_components.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_move_log_item.dart';
import '../../../core/widgets/nuvo_shared_components.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../auth/data/auth_api.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../races/data/race_models.dart';
import '../../races/domain/chase_context.dart';
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
        backgroundColor: NuvoColors.navy,
        body: Center(
          child: CircularProgressIndicator(
            color: NuvoColors.white,
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
    final canSubmit = race.status == 'active' && (isOwner || isParticipant);
    final canJoin = race.status == 'active' && !isOwner && !isParticipant;
    final myPart = isParticipant ? race.participantFor(user.id) : null;
    final myProgress = myPart?.progressPercent ?? 0;
    final myRaceComplete = myPart != null && myProgress >= 100;

    // Sorted participants for leaderboard
    final sorted = [...race.participants]
      ..sort((a, b) => b.progressPercent.compareTo(a.progressPercent));
    final chase = user == null ? null : ChaseContext.compute(race, user.id);
    final rank = chase?.myRank;
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
          // ── Navy header ─────────────────────────────────────────────────────
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
                    chaseCopy: chase?.chaseCopy,
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
                        ? 'Log more moves'
                        : 'Log move',
                    loading: _busy,
                    onPrimary: _busy
                        ? null
                        : canJoin
                        ? _joinRace
                        : canSubmit
                        ? () async {
                            await context.push('/race/${race.id}/proof');
                            _load();
                          }
                        : null,
                  ),

                  if (canSubmit && myRaceComplete) ...[
                    const SizedBox(height: 12),
                    _CompleteCallout(progress: myProgress),
                  ],

                  const SizedBox(height: 24),

                  // ── Board ──────────────────────────────────────────────────
                  Text(
                    'THE BOARD',
                    style: AppTextStyles.brandLabel.copyWith(
                      color: NuvoColors.muted,
                    ),
                  ),
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
                        const SizedBox(height: 8),
                    ],

                  const SizedBox(height: 14),
                  NuvoBoardMovementStrip(
                    label: recentMoveCount == 0
                        ? 'Board is waiting for the first move.'
                        : 'Board moved ${recentMoveCount == 1 ? 'once' : '$recentMoveCount times'} recently',
                    movers: movementAvatars.take(3).toList(),
                  ),

                  if (canSubmit && myRaceComplete) ...[
                    const SizedBox(height: 18),
                    NuvoGhostButton(
                      label: 'Start another race',
                      expand: true,
                      onPressed: () => context.push('/races/new'),
                    ),
                  ] else if (canSubmit && isOwner) ...[
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
                  Text(
                    'MOVE LOG',
                    style: AppTextStyles.brandLabel.copyWith(
                      color: NuvoColors.muted,
                    ),
                  ),
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

                  // ── Rules ───────────────────────────────────────────────────
                  Text(
                    'RULES',
                    style: AppTextStyles.brandLabel.copyWith(
                      color: NuvoColors.muted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    race.rules?.isNotEmpty == true
                        ? race.rules!
                        : 'Log moves before the finish line. Highest verified progress wins.',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: NuvoColors.muted,
                    ),
                  ),

                  // ── Owner manage section ────────────────────────────────────
                  if (isOwner) ...[
                    const SizedBox(height: 28),
                    Text(
                      'MANAGE',
                      style: AppTextStyles.brandLabel.copyWith(
                        color: NuvoColors.muted,
                      ),
                    ),
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

// ── Navy header ───────────────────────────────────────────────────────────────

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
      color: NuvoColors.navy,
      padding: EdgeInsets.fromLTRB(20, safeTop + 16, 20, 28),
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
                    color: Colors.white.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_back_rounded,
                    color: NuvoColors.white,
                    size: 20,
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
                  color: isActive
                      ? NuvoColors.blue
                      : Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  isActive ? 'Active' : race.status.toUpperCase(),
                  style: AppTextStyles.labelSmall.copyWith(
                    color: NuvoColors.white,
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
                      color: Colors.white.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.tune_rounded,
                      color: NuvoColors.white,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 20),

          // Race title
          Text(
            race.displayTitle,
            style: AppTextStyles.headlineLarge.copyWith(
              color: NuvoColors.white,
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 4),
          Text(
            _contextLine(race),
            style: AppTextStyles.bodySmall.copyWith(
              color: NuvoColors.white.withValues(alpha: 0.55),
            ),
          ),

          // My progress — only shown when participant
          if (isParticipant) ...[
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$myProgress',
                  style: AppTextStyles.displayLarge.copyWith(
                    color: myProgress >= 100
                        ? NuvoColors.success
                        : NuvoColors.white,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8, left: 3),
                  child: Text(
                    '%',
                    style: AppTextStyles.headlineMedium.copyWith(
                      color: NuvoColors.white.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'Your progress',
              style: AppTextStyles.labelSmall.copyWith(
                color: NuvoColors.white.withValues(alpha: 0.45),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 14),
            NuvoRaceLane(
              progressPercent: myProgress,
              onDark: true,
              dotDiameter: 14,
            ),
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
                      color: NuvoColors.white.withValues(alpha: 0.60),
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
    if (race.isSupportedAiMotionRace) {
      parts.add('AI MoveCheck');
    } else {
      parts.add(switch (race.proofRequirement) {
        'photo_video' => 'Photo / video move',
        'ai_check' => 'AI MoveCheck',
        _ => 'Manual logging',
      });
    }
    if (race.targetValue != null) {
      parts.add('${race.targetValue} ${race.unit ?? 'reps'}');
    }
    return parts.join(' · ');
  }
}

// ── Complete callout ──────────────────────────────────────────────────────────

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
          const Icon(
            Icons.check_circle_rounded,
            color: NuvoColors.success,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Race complete', style: AppTextStyles.titleMedium),
                const SizedBox(height: 2),
                Text(
                  '$progress% — you crossed the finish line.',
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
    'accepted' || 'ai_verified' => '$verb · Move checked',
    'ai_failed' || 'rejected' => "$verb · Move didn't count",
    'needs_review' => '$verb · Under review',
    _ => verb,
  };
}

String _contextLine(Race race) {
  final parts = <String>[];
  if (race.isSupportedAiMotionRace) {
    parts.add('AI MoveCheck');
  } else {
    parts.add(switch (race.proofRequirement) {
      'photo_video' => 'Photo / video move',
      'ai_check' => 'AI MoveCheck',
      _ => 'Manual logging',
    });
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
            const Icon(
              Icons.chevron_right_rounded,
              color: NuvoColors.muted,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_error_state.dart';
import '../../../core/widgets/nuvo_shared_components.dart';
import '../../auth/data/auth_api.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../races/data/race_models.dart';
import '../../races/presentation/race_controller.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

String _raceContextLine(Race race) {
  final parts = <String>[];
  if (race.isSupportedAiMotionRace) {
    parts.add('AI Motion Proof');
  } else {
    final method = switch (race.proofRequirement) {
      'photo_video' => 'Photo/video proof',
      'ai_check' => 'AI Motion Proof',
      _ => 'Manual proof',
    };
    parts.add(method);
  }
  if (race.targetValue != null) {
    final unit = race.unit ?? 'reps';
    parts.add('${race.targetValue} $unit');
  }
  return parts.join(' · ');
}

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
    } catch (e) {
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
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep race'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: NuvoColors.page,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_race == null) {
      return Scaffold(
        backgroundColor: NuvoColors.page,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: NuvoBackNavRow(
                  onBack: () => safePopOrGo(context, '/arena'),
                ),
              ),
              Expanded(
                child: NuvoErrorState(
                  message: _error ?? 'Race not found.',
                  onRetry: _load,
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
    final myParticipant = isParticipant ? race.participantFor(user.id) : null;
    final myRaceComplete =
        myParticipant != null && myParticipant.progressPercent >= 100;

    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 36),
            children: [
              // ── Back nav row ───────────────────────────────────────────────
              NuvoBackNavRow(
                onBack: () => safePopOrGo(context, '/arena'),
                trailing: _StatusPill(status: race.status),
              ),

              const SizedBox(height: 14),

              // ── Race title + context ────────────────────────────────────────
              Text(race.displayTitle, style: AppTextStyles.headlineLarge),
              const SizedBox(height: 4),
              Text(
                _raceContextLine(race),
                style: AppTextStyles.bodyMedium.copyWith(
                  color: NuvoColors.muted,
                ),
              ),
              if (race.description != null) ...[
                const SizedBox(height: 4),
                Text(
                  race.description!,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: NuvoColors.muted,
                  ),
                ),
              ],

              const SizedBox(height: 18),

              // ── My progress card ────────────────────────────────────────────
              if (myParticipant != null && race.targetValue != null) ...[
                _MyProgressCard(participant: myParticipant, race: race),
                const SizedBox(height: 12),
              ],

              // ── Primary CTAs ────────────────────────────────────────────────
              if (canJoin)
                NuvoPrimaryButton(
                  label: 'Join race',
                  icon: Icons.group_add_rounded,
                  expand: true,
                  loading: _busy,
                  onPressed: _busy ? null : _joinRace,
                ),
              if (canSubmit) ...[
                if (myRaceComplete) ...[
                  _RaceCompleteCard(participant: myParticipant),
                  const SizedBox(height: 10),
                  NuvoPrimaryButton(
                    label: 'Start another race',
                    icon: Icons.add_rounded,
                    expand: true,
                    onPressed: () => context.push('/races/new'),
                  ),
                  const SizedBox(height: 8),
                  NuvoGhostButton(
                    label: 'Submit more proof',
                    icon: Icons.check_rounded,
                    expand: true,
                    onPressed: () async {
                      await context.push('/race/${race.id}/proof');
                      _load();
                    },
                  ),
                ] else ...[
                  NuvoPrimaryButton(
                    label: 'Submit proof',
                    icon: Icons.arrow_forward_rounded,
                    expand: true,
                    onPressed: _busy
                        ? null
                        : () async {
                            await context.push('/race/${race.id}/proof');
                            _load();
                          },
                  ),
                  const SizedBox(height: 10),
                ],
              ],
              if (isOwner)
                NuvoOutlineButton(
                  label: 'Invite crew',
                  icon: Icons.group_add_rounded,
                  expand: true,
                  onPressed: _busy
                      ? null
                      : () => context.push('/race/${race.id}/invite'),
                ),

              const SizedBox(height: 22),

              // ── Leaderboard card (Arena board style) ─────────────────────
              _LeaderboardCard(race: race, userId: user?.id),

              // ── Proof method ────────────────────────────────────────────────
              _Section(
                title: 'Proof method',
                child: _ProofMethodCard(race: race),
              ),

              // ── Recent proofs ───────────────────────────────────────────────
              _Section(
                title: 'Recent proofs',
                child: race.recentProofs.isEmpty
                    ? const _CompactInfoRow(
                        icon: Icons.fact_check_outlined,
                        text:
                            'No proof submitted yet. Submit proof to move the leaderboard.',
                      )
                    : Column(
                        children: [
                          for (final proof in race.recentProofs.take(5))
                            _ProofRow(
                              proof: proof,
                              unit: race.unit,
                              onTap: isOwner
                                  ? () => context.push(
                                      '/race/${race.id}/proofs/${proof.id}',
                                    )
                                  : null,
                            ),
                        ],
                      ),
              ),

              // ── Rules ───────────────────────────────────────────────────────
              _Section(
                title: 'Rules',
                child: _CompactInfoRow(
                  icon: Icons.rule_rounded,
                  text: race.rules?.isNotEmpty == true
                      ? race.rules!
                      : 'Submit proof before the finish line. Highest verified progress wins.',
                ),
              ),

              // ── Manage race (owner only) ────────────────────────────────────
              if (isOwner) ...[
                _ManageRaceSection(
                  race: race,
                  busy: _busy,
                  onEdit: () => context.push('/race/${race.id}/edit'),
                  onSettings: () => context.push('/race/${race.id}/settings'),
                  onShareRace: () => Share.share(
                    'Racing "${race.title}" on Nuvo. Open Nuvo and join the start line.',
                  ),
                  onCopyCode: _copyInviteCode,
                ),
              ],

              // ── Leave race (non-owner participant) ──────────────────────────
              if (isParticipant && !isOwner) ...[
                const SizedBox(height: 8),
                NuvoGhostButton(
                  label: 'Leave race',
                  icon: Icons.logout_rounded,
                  expand: true,
                  onPressed: _busy ? null : _leaveRace,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Status pill ───────────────────────────────────────────────────────────────

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      'active' => 'Active',
      'archived' => 'Archived',
      'cancelled' => 'Cancelled',
      'completed' => 'Completed',
      _ => status,
    };
    final bgColor = switch (status) {
      'active' => NuvoColors.blue,
      'archived' => NuvoColors.muted,
      'cancelled' => const Color(0xFFE5484D),
      _ => NuvoColors.muted,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppTextStyles.labelSmall.copyWith(
          color: NuvoColors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

// ── My progress card ──────────────────────────────────────────────────────────

class _MyProgressCard extends StatelessWidget {
  const _MyProgressCard({required this.participant, required this.race});

  final RaceParticipant participant;
  final Race race;

  @override
  Widget build(BuildContext context) {
    final target = race.targetValue!;
    final unit = race.unit ?? 'reps';
    final progress = (participant.progressPercent / 100).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: NuvoColors.white,
        borderRadius: BorderRadius.all(Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Color(0x1A07152B),
            blurRadius: 0,
            offset: Offset(3, 4),
          ),
          BoxShadow(
            color: Color(0x0C07152B),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Your progress',
                style: AppTextStyles.labelMedium.copyWith(
                  color: NuvoColors.muted,
                ),
              ),
              const Spacer(),
              Text(
                '${participant.progressValue} / $target $unit',
                style: AppTextStyles.labelMedium.copyWith(
                  color: NuvoColors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: NuvoColors.border,
              valueColor: const AlwaysStoppedAnimation<Color>(NuvoColors.blue),
              minHeight: 7,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${participant.progressPercent}% complete',
            style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
          ),
        ],
      ),
    );
  }
}

// ── Leaderboard card (Arena board style) ─────────────────────────────────────

class _LeaderboardCard extends StatelessWidget {
  const _LeaderboardCard({required this.race, this.userId});

  final Race race;
  final String? userId;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: NuvoColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: NuvoColors.navy, width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1407152B),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
          BoxShadow(
            color: Color(0x0B07152B),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Text('Leaderboard', style: AppTextStyles.titleLarge),
          ),
          const Divider(
            height: 1,
            thickness: 0.5,
            color: NuvoColors.border,
            indent: 18,
            endIndent: 18,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
            child: race.participants.isEmpty
                ? const _CompactInfoRow(
                    icon: Icons.people_outline_rounded,
                    text:
                        'Your crew is waiting at the start line. Invite people with a code until direct race links are ready.',
                  )
                : Column(
                    children: [
                      for (var i = 0; i < race.participants.length; i++) ...[
                        _ParticipantRow(
                          participant: race.participants[i],
                          rank: i + 1,
                          showTarget: race.targetValue != null,
                          targetValue: race.targetValue,
                          unit: race.unit,
                          isCurrentUser:
                              userId != null &&
                              userId == race.participants[i].userId,
                        ),
                        if (i < race.participants.length - 1)
                          const Divider(
                            height: 14,
                            thickness: 0.5,
                            color: NuvoColors.border,
                          ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Participant row ───────────────────────────────────────────────────────────

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({
    required this.participant,
    required this.rank,
    required this.showTarget,
    required this.isCurrentUser,
    this.targetValue,
    this.unit,
  });

  final RaceParticipant participant;
  final int rank;
  final bool showTarget;
  final bool isCurrentUser;
  final int? targetValue;
  final String? unit;

  String _initials(String name) {
    final parts = name.trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final initials = _initials(participant.displayName);
    final valueText = showTarget && targetValue != null
        ? '${participant.progressValue} / $targetValue'
        : '${participant.progressPercent}%';

    if (isCurrentUser) {
      return NuvoCurrentUserRow(
        rank: rank,
        name: participant.displayName,
        value: valueText,
        initials: initials,
      );
    }

    // Flat non-user row — no border, no shadow, no background
    return Row(
      children: [
        SizedBox(
          width: 24,
          child: Text(
            '$rank',
            style: AppTextStyles.labelSmall.copyWith(color: NuvoColors.muted),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 30,
          height: 30,
          decoration: const BoxDecoration(
            color: NuvoColors.border,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            initials,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: NuvoColors.navy,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            participant.displayName,
            style: AppTextStyles.bodyMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          valueText,
          style: AppTextStyles.labelMedium.copyWith(color: NuvoColors.muted),
        ),
      ],
    );
  }
}

// ── Proof method card ─────────────────────────────────────────────────────────

class _ProofMethodCard extends StatelessWidget {
  const _ProofMethodCard({required this.race});

  final Race race;

  @override
  Widget build(BuildContext context) {
    if (race.isSupportedAiMotionRace) {
      return const _CompactInfoRow(
        icon: Icons.directions_run_rounded,
        text:
            'AI Motion Proof · Live camera · Auto verified\nNuvo checks movement using your iPhone camera.',
      );
    }

    final method = switch (race.proofRequirement) {
      'photo_video' => 'Photo or video',
      'ai_check' => 'AI Motion Proof',
      _ => 'Manual proof',
    };
    final mode = switch (race.proofReviewMode) {
      'owner_review' => 'Owner review',
      'ai_review' => 'AI review',
      _ => 'Auto-accepted',
    };

    return _CompactInfoRow(
      icon: Icons.verified_rounded,
      text: '$method · $mode',
    );
  }
}

// ── Recent proof row ──────────────────────────────────────────────────────────

class _ProofRow extends StatelessWidget {
  const _ProofRow({required this.proof, this.unit, this.onTap});

  final RaceProof proof;
  final String? unit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isAiMotion = proof.proofType == 'ai_motion';
    final valueLabel = proof.value != null
        ? unit != null
              ? '+${proof.value} $unit'
              : '+${proof.value}'
        : null;
    final title = isAiMotion ? 'AI Motion Proof' : proof.displayName;
    final subtitle = isAiMotion ? _aiProofSubtitle(proof) : proof.note;
    final statusLabel = _proofStatusLabel(proof.verificationStatus);
    final isSuccess =
        proof.verificationStatus == 'ai_verified' ||
        proof.verificationStatus == 'accepted';
    final isDanger =
        proof.verificationStatus == 'ai_failed' ||
        proof.verificationStatus == 'rejected';

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: NuvoColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: NuvoColors.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0C07152B),
              blurRadius: 0,
              offset: Offset(2, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: isDanger ? const Color(0xFFFFEEF1) : NuvoColors.icyBlue,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(
                isAiMotion
                    ? Icons.directions_run_rounded
                    : Icons.check_circle_outline_rounded,
                color: isDanger ? const Color(0xFFE8304A) : NuvoColors.blue,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.titleMedium),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: NuvoColors.muted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (valueLabel != null)
                  Text(
                    valueLabel,
                    style: AppTextStyles.labelMedium.copyWith(
                      color: NuvoColors.blue,
                    ),
                  ),
                const SizedBox(height: 3),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: isSuccess
                        ? NuvoColors.success.withValues(alpha: 0.12)
                        : isDanger
                        ? const Color(0xFFE8304A).withValues(alpha: 0.10)
                        : NuvoColors.icyBlue,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    statusLabel,
                    style: AppTextStyles.labelSmall.copyWith(
                      color: isSuccess
                          ? NuvoColors.success
                          : isDanger
                          ? const Color(0xFFE8304A)
                          : NuvoColors.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String? _aiProofSubtitle(RaceProof proof) {
    final activity = proof.aiActivityType == 'jumping_jacks'
        ? 'jumping jacks'
        : proof.aiActivityType?.replaceAll('_', ' ');
    final detected = proof.detectedValue ?? proof.value;
    final target = proof.targetValue;
    final confidence = proof.confidence;
    final count = detected != null && target != null
        ? '$detected / $target ${activity ?? 'reps'} detected'
        : proof.verificationSummary;
    if (confidence == null) return count;
    return '$count · ${(confidence * 100).round()}% confidence';
  }

  String _proofStatusLabel(String status) => switch (status) {
    'ai_verified' => 'Verified',
    'ai_failed' => 'Try again',
    'needs_review' => 'Needs review',
    'submitted' => 'Submitted',
    'accepted' => 'Accepted',
    'rejected' => 'Rejected',
    _ => status.replaceAll('_', ' '),
  };
}

// ── Manage race section (owner only, bottom) ──────────────────────────────────

class _ManageRaceSection extends StatelessWidget {
  const _ManageRaceSection({
    required this.race,
    required this.busy,
    required this.onEdit,
    required this.onSettings,
    required this.onShareRace,
    required this.onCopyCode,
  });

  final Race race;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onSettings;
  final VoidCallback onShareRace;
  final VoidCallback onCopyCode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Manage race',
          style: AppTextStyles.titleLarge.copyWith(color: NuvoColors.muted),
        ),
        const SizedBox(height: 10),
        NuvoActionTile(
          icon: Icons.edit_rounded,
          title: 'Edit race',
          iconColor: NuvoColors.blue,
          iconBg: NuvoColors.icyBlue,
          onTap: busy ? null : onEdit,
        ),
        const SizedBox(height: 8),
        NuvoActionTile(
          icon: Icons.tune_rounded,
          title: 'Race settings',
          iconColor: NuvoColors.blue,
          iconBg: NuvoColors.icyBlue,
          onTap: busy ? null : onSettings,
        ),
        const SizedBox(height: 8),
        NuvoActionTile(
          icon: Icons.ios_share_rounded,
          title: 'Share race',
          iconColor: NuvoColors.navy,
          iconBg: NuvoColors.icyBlue,
          onTap: busy ? null : onShareRace,
        ),
        const SizedBox(height: 8),
        NuvoActionTile(
          icon: Icons.copy_rounded,
          title: 'Copy invite code',
          iconColor: NuvoColors.navy,
          iconBg: NuvoColors.icyBlue,
          onTap: busy ? null : onCopyCode,
        ),
        const SizedBox(height: 8),
        Text(
          'Lifecycle and danger actions are in Race settings.',
          style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ── Shared helpers ────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.titleLarge),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

// ── Race complete card ────────────────────────────────────────────────────────

class _RaceCompleteCard extends StatelessWidget {
  const _RaceCompleteCard({required this.participant});

  final RaceParticipant participant;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FBF5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x5916C784)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1816C784),
            blurRadius: 0,
            offset: Offset(3, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFE8FAF2),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.check_circle_rounded,
              color: NuvoColors.success,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Race complete', style: AppTextStyles.titleMedium),
                const SizedBox(height: 2),
                Text(
                  '${participant.progressPercent}% — you crossed the finish line.',
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

/// Compact single-surface info row — tighter than the old _InfoRow.
class _CompactInfoRow extends StatelessWidget {
  const _CompactInfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: NuvoColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NuvoColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C07152B),
            blurRadius: 0,
            offset: Offset(2, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: NuvoColors.blue, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.bodySmall.copyWith(
                color: NuvoColors.navy,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

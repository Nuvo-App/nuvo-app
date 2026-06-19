import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_error_state.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../auth/data/auth_api.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../races/data/race_models.dart';
import '../../races/presentation/race_controller.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
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

  Future<void> _ownerLifecycle(
    String action, {
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final race = _race;
    if (race == null) return;
    final confirmed = await _confirm(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
    );
    if (!confirmed) return;
    setState(() => _busy = true);
    try {
      if (action == 'archive') {
        final updated = await ref
            .read(raceControllerProvider.notifier)
            .archiveRace(race.id);
        if (mounted) setState(() => _race = updated);
      } else if (action == 'cancel') {
        final updated = await ref
            .read(raceControllerProvider.notifier)
            .cancelRace(race.id);
        if (mounted) setState(() => _race = updated);
      } else if (action == 'delete') {
        await ref.read(raceControllerProvider.notifier).deleteRace(race.id);
        if (mounted) context.go('/arena');
        return;
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update this race.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
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
                child: IconButton.filledTonal(
                  onPressed: () => safePopOrGo(context, '/arena'),
                  icon: const Icon(Icons.arrow_back_rounded),
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
    final proofLabel = race.goalType == 'photo' ? 'Photo proof' : 'Self report';

    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton.filledTonal(
                onPressed: () => safePopOrGo(context, '/arena'),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            ),
            const SizedBox(height: 12),
            Text(race.title, style: AppTextStyles.headlineLarge),
            if (race.description != null) ...[
              const SizedBox(height: 8),
              Text(
                race.description!,
                style: AppTextStyles.bodyLarge.copyWith(
                  color: NuvoColors.muted,
                ),
              ),
            ],

            const SizedBox(height: 18),
            _ActionPanel(
              race: race,
              isOwner: isOwner,
              isParticipant: isParticipant,
              busy: _busy,
              onSubmitProof: () async {
                await context.push('/race/${race.id}/proof');
                _load();
              },
              onEdit: () => context.push('/race/${race.id}/edit'),
              onSettings: () => context.push('/race/${race.id}/settings'),
              onInvite: () => context.push('/race/${race.id}/invite'),
              onCopyInviteCode: _copyInviteCode,
              onJoinRace: _joinRace,
              onLeaveRace: _leaveRace,
              onShareRace: () => Share.share(
                'Racing "${race.title}" on Nuvo. Open Nuvo and join the start line.',
              ),
              onArchive: () => _ownerLifecycle(
                'archive',
                title: 'Archive race?',
                message:
                    'Archived races leave active competition but stay in race history.',
                confirmLabel: 'Archive',
              ),
              onCancel: () => _ownerLifecycle(
                'cancel',
                title: 'Cancel race?',
                message:
                    'Cancel this race only if the start line or rules no longer apply.',
                confirmLabel: 'Cancel race',
              ),
              onDelete: () => _ownerLifecycle(
                'delete',
                title: 'Delete race?',
                message:
                    'This hides the race from your arena. Proof history is preserved.',
                confirmLabel: 'Delete',
              ),
            ),

            const SizedBox(height: 24),

            // ── Leaderboard ─────────────────────────────────────────────────
            _Section(
              title: 'Leaderboard',
              child: race.participants.isEmpty
                  ? const _InfoRow(
                      icon: Icons.people_outline_rounded,
                      text:
                          'Your crew is waiting at the start line. Invite friends to turn this into a race.',
                    )
                  : Column(
                      children: [
                        for (var i = 0; i < race.participants.length; i++)
                          _ParticipantRow(
                            participant: race.participants[i],
                            rank: i + 1,
                            showTarget: race.targetValue != null,
                            targetValue: race.targetValue,
                            unit: race.unit,
                          ),
                      ],
                    ),
            ),

            // ── Goal ────────────────────────────────────────────────────────
            if (race.targetValue != null)
              _Section(
                title: 'Goal',
                child: _InfoRow(
                  icon: Icons.flag_rounded,
                  text: race.unit != null
                      ? '${race.targetValue} ${race.unit}'
                      : '${race.targetValue}',
                ),
              ),

            // ── Proof method ────────────────────────────────────────────────
            _Section(
              title: 'Proof method',
              child: _InfoRow(
                icon: Icons.verified_rounded,
                text:
                    '$proofLabel · ${race.proofRequirement.replaceAll('_', ' ')} · ${race.proofReviewMode.replaceAll('_', ' ')}',
              ),
            ),

            // ── Recent proofs ───────────────────────────────────────────────
            _Section(
              title: 'Recent proofs',
              child: race.recentProofs.isEmpty
                  ? const _InfoRow(
                      icon: Icons.fact_check_outlined,
                      text:
                          'No proof submitted yet. Submit your first proof to move the leaderboard.',
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

            _Section(
              title: 'Rules',
              child: _InfoRow(
                icon: Icons.rule_rounded,
                text: race.rules?.isNotEmpty == true
                    ? race.rules!
                    : 'Submit proof before the finish line. Highest verified progress wins.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Participant row with inline progress ──────────────────────────────────────

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({
    required this.participant,
    required this.rank,
    required this.showTarget,
    this.targetValue,
    this.unit,
  });

  final RaceParticipant participant;
  final int rank;
  final bool showTarget;
  final int? targetValue;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    final progress = participant.progressPercent / 100;
    final valueLabel = unit != null
        ? '${participant.progressValue} $unit'
        : '${participant.progressValue}';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NuvoColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NuvoColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: rank == 1 ? NuvoColors.blue : NuvoColors.icyBlue,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$rank',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: rank == 1 ? NuvoColors.white : NuvoColors.navy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  participant.displayName,
                  style: AppTextStyles.titleMedium,
                ),
              ),
              Text(
                showTarget ? valueLabel : '${participant.progressPercent}%',
                style: AppTextStyles.bodySmall.copyWith(
                  color: NuvoColors.muted,
                ),
              ),
            ],
          ),
          if (showTarget && targetValue != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                backgroundColor: NuvoColors.border,
                valueColor: AlwaysStoppedAnimation<Color>(
                  rank == 1 ? NuvoColors.blue : NuvoColors.navy,
                ),
                minHeight: 5,
              ),
            ),
          ],
        ],
      ),
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

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: NuvoColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: NuvoColors.border),
        ),
        child: Row(
          children: [
            Icon(
              isAiMotion
                  ? Icons.directions_run_rounded
                  : Icons.check_circle_outline_rounded,
              color: proof.verificationStatus == 'ai_failed'
                  ? const Color(0xFFE8304A)
                  : NuvoColors.blue,
              size: 21,
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
                const SizedBox(height: 4),
                Text(
                  statusLabel,
                  style: AppTextStyles.labelSmall.copyWith(
                    color:
                        proof.verificationStatus == 'ai_failed' ||
                            proof.verificationStatus == 'rejected'
                        ? const Color(0xFFE8304A)
                        : NuvoColors.muted,
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
    return '$count · Confidence: ${(confidence * 100).round()}%';
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

class _ActionPanel extends StatelessWidget {
  const _ActionPanel({
    required this.race,
    required this.isOwner,
    required this.isParticipant,
    required this.busy,
    required this.onSubmitProof,
    required this.onEdit,
    required this.onSettings,
    required this.onInvite,
    required this.onCopyInviteCode,
    required this.onJoinRace,
    required this.onLeaveRace,
    required this.onShareRace,
    required this.onArchive,
    required this.onCancel,
    required this.onDelete,
  });

  final Race race;
  final bool isOwner;
  final bool isParticipant;
  final bool busy;
  final VoidCallback onSubmitProof;
  final VoidCallback onEdit;
  final VoidCallback onSettings;
  final VoidCallback onInvite;
  final VoidCallback onCopyInviteCode;
  final VoidCallback onJoinRace;
  final VoidCallback onLeaveRace;
  final VoidCallback onShareRace;
  final VoidCallback onArchive;
  final VoidCallback onCancel;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final canSubmit = race.status == 'active' && (isOwner || isParticipant);
    final canJoin = race.status == 'active' && !isOwner && !isParticipant;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NuvoColors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: NuvoColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Race actions', style: AppTextStyles.titleLarge),
          const SizedBox(height: 12),
          if (canJoin)
            NuvoPrimaryButton(
              label: 'Join race',
              icon: Icons.group_add_rounded,
              expand: true,
              loading: busy,
              onPressed: busy ? null : onJoinRace,
            ),
          if (canSubmit) ...[
            NuvoPrimaryButton(
              label: 'Submit proof',
              icon: Icons.arrow_forward_rounded,
              expand: true,
              onPressed: busy ? null : onSubmitProof,
            ),
            const SizedBox(height: 10),
          ],
          if (isOwner) ...[
            Row(
              children: [
                Expanded(
                  child: NuvoOutlineButton(
                    label: 'Edit race',
                    icon: Icons.edit_rounded,
                    onPressed: busy ? null : onEdit,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: NuvoOutlineButton(
                    label: 'Race settings',
                    icon: Icons.tune_rounded,
                    onPressed: busy ? null : onSettings,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            NuvoPrimaryButton(
              label: 'Invite crew',
              icon: Icons.group_add_rounded,
              expand: true,
              onPressed: busy ? null : onInvite,
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: NuvoOutlineButton(
                  label: 'Share race',
                  icon: Icons.ios_share_rounded,
                  onPressed: busy ? null : onShareRace,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: NuvoOutlineButton(
                  label: 'Copy invite code',
                  icon: Icons.copy_rounded,
                  onPressed: busy ? null : onCopyInviteCode,
                ),
              ),
            ],
          ),
          if (isParticipant && !isOwner) ...[
            const SizedBox(height: 10),
            NuvoGhostButton(
              label: 'Leave race',
              icon: Icons.logout_rounded,
              expand: true,
              onPressed: busy ? null : onLeaveRace,
            ),
          ],
          if (isOwner) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _LifecycleChip(
                  label: 'Archive',
                  onTap: busy ? null : onArchive,
                ),
                _LifecycleChip(label: 'Cancel', onTap: busy ? null : onCancel),
                _LifecycleChip(
                  label: 'Delete',
                  danger: true,
                  onTap: busy ? null : onDelete,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LifecycleChip extends StatelessWidget {
  const _LifecycleChip({
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: onTap,
      labelStyle: AppTextStyles.labelSmall.copyWith(
        color: danger ? const Color(0xFFE5484D) : NuvoColors.navy,
      ),
      backgroundColor: danger ? const Color(0xFFFFEEF1) : NuvoColors.icyBlue,
      side: BorderSide(
        color: danger ? const Color(0xFFE5484D) : NuvoColors.border,
      ),
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
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.titleLarge),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NuvoColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: NuvoColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: NuvoColors.blue),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: AppTextStyles.bodyMedium)),
        ],
      ),
    );
  }
}

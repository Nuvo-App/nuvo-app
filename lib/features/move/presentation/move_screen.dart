import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/animations.dart' hide PressableScale;
import '../../../core/widgets/nuvo_avatar.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_icons.dart';
import '../../../core/widgets/nuvo_shared_components.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../races/data/race_models.dart';
import '../../races/domain/camera_verification_resolver.dart';
import '../../races/presentation/race_controller.dart';

class MoveScreen extends ConsumerWidget {
  const MoveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final raceState = ref.watch(raceControllerProvider);
    final user = ref.watch(authControllerProvider).user;
    final uid = user?.id;

    final activeRaces = raceState.races
        .where(
          (race) =>
              race.status == 'active' &&
              resolveCameraVerification(race).isCameraVerifiable,
        )
        .toList();

    final recentMoves = raceState.races
        .where((race) => resolveCameraVerification(race).isCameraVerifiable)
        .expand((r) => r.recentProofs.map((p) => (race: r, proof: p)))
        .take(10)
        .toList();

    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
          children: [
            // ── Header ───────────────────────────────────────────────────────
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: NuvoColors.navy,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Center(
                    child: NuvoIcon(
                      NuvoIconType.plus,
                      color: NuvoColors.white,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Verify a move',
                        style: AppTextStyles.headlineMedium,
                      ),
                      Text(
                        'Pick a race and use camera verification.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: NuvoColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),

            // ── Active races ─────────────────────────────────────────────────
            if (raceState.loading && activeRaces.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: NuvoColors.blue,
                  ),
                ),
              )
            else if (activeRaces.isEmpty)
              _EmptyState(onStart: () => context.push('/races/new'))
            else ...[
              const _SectionLabel(label: 'Your races'),
              const SizedBox(height: 12),
              for (var i = 0; i < activeRaces.length; i++) ...[
                FadeSlideIn(
                  delay: Duration(milliseconds: 60 * i),
                  child: _RaceLogRow(
                    race: activeRaces[i],
                    userId: uid,
                    onLog: () {
                      final race = activeRaces[i];
                      debugLogCameraVerificationDecision(
                        race,
                        resolveCameraVerification(race),
                        routeAction: 'move_screen_to_submit_proof',
                      );
                      context.push('/race/${race.id}/proof').then((_) {
                        ref.read(raceControllerProvider.notifier).loadRaces();
                      });
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],

            // ── Recent moves ─────────────────────────────────────────────────
            if (recentMoves.isNotEmpty) ...[
              const SizedBox(height: 28),
              const _SectionLabel(label: 'Recent moves'),
              const SizedBox(height: 12),
              for (final entry in recentMoves)
                _RecentMoveRow(proof: entry.proof, race: entry.race),
            ],
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

// ── Race log row ──────────────────────────────────────────────────────────────

class _RaceLogRow extends StatelessWidget {
  const _RaceLogRow({required this.race, required this.onLog, this.userId});

  final Race race;
  final String? userId;
  final VoidCallback onLog;

  @override
  Widget build(BuildContext context) {
    final myPart = userId != null ? race.participantFor(userId!) : null;
    final pct = myPart?.progressPercent ?? 0;
    final isComplete = pct >= 100;

    final others = race.participants
        .where((p) => p.userId != userId)
        .take(4)
        .toList();
    final othersCount = race.participantCount - (myPart != null ? 1 : 0);

    return PressableScale(
      onTap: isComplete ? null : onLog,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(
          color: NuvoColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isComplete
                ? NuvoColors.success.withValues(alpha: 0.25)
                : NuvoColors.border,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x08050B14),
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    race.displayTitle,
                    style: AppTextStyles.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 10),
                if (!isComplete)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: NuvoColors.blue,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: NuvoColors.blue.withValues(alpha: 0.28),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Text(
                      'Verify',
                      style: AppTextStyles.labelMedium.copyWith(
                        color: NuvoColors.white,
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: NuvoColors.success.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const NuvoIcon(
                          NuvoIconType.check,
                          color: NuvoColors.success,
                          size: 12,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Done',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: NuvoColors.success,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            NuvoRaceLane(progressPercent: pct, trackHeight: 3, dotDiameter: 10),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    isComplete
                        ? 'Complete'
                        : myPart != null
                        ? '$pct% · ${race.unit ?? 'reps'} logged'
                        : 'Not started',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: isComplete ? NuvoColors.success : NuvoColors.muted,
                    ),
                  ),
                ),
                if (othersCount > 0)
                  _ParticipantPill(others: others, total: othersCount),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Participant pill ──────────────────────────────────────────────────────────

class _ParticipantPill extends StatelessWidget {
  const _ParticipantPill({required this.others, required this.total});
  final List<RaceParticipant> others;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        NuvoAvatarStack(
          avatars: others
              .map(
                (p) => (initials: p.displayName, photoUrl: p.profilePhotoUrl),
              )
              .toList(),
          total: total,
          size: 18,
          max: 3,
        ),
        const SizedBox(width: 5),
        Text(
          '$total racing',
          style: AppTextStyles.labelSmall.copyWith(color: NuvoColors.textMuted),
        ),
      ],
    );
  }
}

// ── Recent move row ───────────────────────────────────────────────────────────

class _RecentMoveRow extends StatelessWidget {
  const _RecentMoveRow({required this.proof, required this.race});

  final RaceProof proof;
  final Race race;

  @override
  Widget build(BuildContext context) {
    final isChecked =
        proof.verificationStatus == 'ai_verified' ||
        proof.verificationStatus == 'accepted';
    final isRejected =
        proof.verificationStatus == 'ai_failed' ||
        proof.verificationStatus == 'rejected';

    final statusLabel = switch (proof.verificationStatus) {
      'ai_verified' => 'Verified',
      'accepted' => 'Verified',
      'ai_failed' => 'Not counted',
      'rejected' => 'Not counted',
      'needs_review' => 'Under review',
      _ => 'Logged',
    };

    final statusColor = isChecked
        ? NuvoColors.success
        : isRejected
        ? NuvoColors.danger
        : NuvoColors.muted;

    final valueStr = proof.value != null
        ? '+${proof.value} ${race.unit ?? 'reps'}'
        : null;

    final initial = proof.displayName.isNotEmpty
        ? proof.displayName[0].toUpperCase()
        : '?';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: NuvoColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060A1A33),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              NuvoAvatar(
                initials: initial,
                photoUrl: proof.profilePhotoUrl,
                size: 36,
                bgColor: NuvoColors.panel,
                textColor: NuvoColors.navy,
              ),
              Positioned(
                bottom: -2,
                right: -2,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: NuvoColors.surface, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  proof.displayName,
                  style: AppTextStyles.titleMedium.copyWith(fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        race.displayTitle,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: NuvoColors.muted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        statusLabel,
                        style: AppTextStyles.labelSmall.copyWith(
                          color: statusColor,
                          fontSize: 9,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (valueStr != null) ...[
            const SizedBox(width: 8),
            Text(
              valueStr,
              style: AppTextStyles.labelMedium.copyWith(color: NuvoColors.navy),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: NuvoColors.blue.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(
            Icons.directions_run_rounded,
            color: NuvoColors.blue,
            size: 24,
          ),
        ),
        const SizedBox(height: 20),
        Text('No active races yet.', style: AppTextStyles.titleLarge),
        const SizedBox(height: 6),
        Text(
          'Start a race to begin logging moves.',
          style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
        ),
        const SizedBox(height: 20),
        NuvoPrimaryButton(
          label: 'Start a race',
          expand: true,
          onPressed: onStart,
        ),
      ],
    );
  }
}

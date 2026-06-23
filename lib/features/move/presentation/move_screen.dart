import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_avatar.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../races/data/race_models.dart';
import '../../races/presentation/race_controller.dart';

class MoveScreen extends ConsumerWidget {
  const MoveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final raceState = ref.watch(raceControllerProvider);
    final user = ref.watch(authControllerProvider).user;
    final uid = user?.id;

    final activeRaces = raceState.races.where((r) => r.status == 'active').toList();

    final recentMoves = raceState.races
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
            Text('MOVE', style: AppTextStyles.brandLabel.copyWith(color: NuvoColors.blue)),
            const SizedBox(height: 6),
            Text('Log a move.', style: AppTextStyles.headlineLarge),
            const SizedBox(height: 4),
            Text(
              'Pick a race and record your progress.',
              style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
            ),
            const SizedBox(height: 28),

            // ── Active races ─────────────────────────────────────────────────
            if (raceState.loading && activeRaces.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (activeRaces.isEmpty)
              _EmptyState(onStart: () => context.push('/races/new'))
            else ...[
              Text(
                'YOUR RACES',
                style: AppTextStyles.brandLabel.copyWith(color: NuvoColors.muted),
              ),
              const SizedBox(height: 12),
              for (final race in activeRaces) ...[
                _RaceLogRow(
                  race: race,
                  userId: uid,
                  onLog: () => context.push('/race/${race.id}/proof').then((_) {
                    ref.read(raceControllerProvider.notifier).loadRaces();
                  }),
                ),
                const SizedBox(height: 8),
              ],
            ],

            // ── Recent moves ─────────────────────────────────────────────────
            if (recentMoves.isNotEmpty) ...[
              const SizedBox(height: 28),
              Text(
                'RECENT MOVES',
                style: AppTextStyles.brandLabel.copyWith(color: NuvoColors.muted),
              ),
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
    final progress = (pct / 100).clamp(0.0, 1.0);
    final isComplete = pct >= 100;

    final others = race.participants
        .where((p) => p.userId != userId)
        .take(4)
        .toList();
    final othersCount = race.participantCount - (myPart != null ? 1 : 0);

    return PressableScale(
      onTap: isComplete ? null : onLog,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: NuvoColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: NuvoColors.divider),
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
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: NuvoColors.navy,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Log',
                      style: AppTextStyles.labelMedium.copyWith(
                        color: NuvoColors.white,
                      ),
                    ),
                  )
                else
                  const Icon(Icons.check_circle_rounded, color: NuvoColors.success, size: 22),
              ],
            ),
            const SizedBox(height: 10),
            _MiniRaceLane(progress: progress),
            const SizedBox(height: 8),
            // Progress label + crew avatars
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
// Shows overlapping avatars + "N racing" for social context.

class _ParticipantPill extends StatelessWidget {
  const _ParticipantPill({required this.others, required this.total});
  final List<RaceParticipant> others;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        NuvoAvatarStack(
          avatars: others
              .map((p) => (initials: p.displayName, photoUrl: p.profilePhotoUrl))
              .toList(),
          total: total,
          size: 18,
          max: 3,
        ),
        const SizedBox(width: 5),
        Text(
          '$total racing',
          style: AppTextStyles.labelSmall.copyWith(color: NuvoColors.muted),
        ),
      ],
    );
  }
}

// ── Mini race lane ────────────────────────────────────────────────────────────

class _MiniRaceLane extends StatelessWidget {
  const _MiniRaceLane({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        const trackH = 3.0;
        const dotD = 10.0;
        final fill = (width * progress).clamp(0.0, width);

        return SizedBox(
          height: dotD,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: trackH,
                decoration: BoxDecoration(
                  color: NuvoColors.trackBg,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              if (progress > 0)
                Container(
                  width: fill,
                  height: trackH,
                  decoration: BoxDecoration(
                    color: progress >= 1 ? NuvoColors.success : NuvoColors.blue,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              if (progress > 0 && progress < 1)
                Positioned(
                  left: (fill - dotD / 2).clamp(0.0, width - dotD),
                  child: Container(
                    width: dotD,
                    height: dotD,
                    decoration: const BoxDecoration(
                      color: NuvoColors.blue,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              if (progress >= 1)
                Positioned(
                  right: 0,
                  child: Container(
                    width: dotD,
                    height: dotD,
                    decoration: const BoxDecoration(
                      color: NuvoColors.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
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
    final isChecked = proof.verificationStatus == 'ai_verified' ||
        proof.verificationStatus == 'accepted';
    final isRejected = proof.verificationStatus == 'ai_failed' ||
        proof.verificationStatus == 'rejected';

    final statusLabel = switch (proof.verificationStatus) {
      'ai_verified'  => 'Move checked',
      'accepted'     => 'Move checked',
      'ai_failed'    => 'Move not counted',
      'rejected'     => 'Move not counted',
      'needs_review' => 'Under review',
      _              => 'Logged',
    };

    final dotColor = isChecked
        ? NuvoColors.success
        : isRejected
        ? NuvoColors.danger
        : NuvoColors.muted;

    final valueStr = proof.value != null
        ? '+${proof.value} ${race.unit ?? 'reps'}'
        : null;

    final initial = proof.displayName.isNotEmpty ? proof.displayName[0].toUpperCase() : '?';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: NuvoColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NuvoColors.divider),
      ),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              NuvoAvatar(
                initials: initial,
                photoUrl: proof.profilePhotoUrl,
                size: 34,
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: NuvoColors.white, width: 1.5),
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
                Text(
                  '${race.displayTitle} · $statusLabel',
                  style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
        const SizedBox(height: 8),
        Text('No active races yet.', style: AppTextStyles.titleLarge),
        const SizedBox(height: 6),
        Text(
          'Start a race to begin logging moves.',
          style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
        ),
        const SizedBox(height: 20),
        NuvoPrimaryButton(label: 'Start a race', expand: true, onPressed: onStart),
      ],
    );
  }
}

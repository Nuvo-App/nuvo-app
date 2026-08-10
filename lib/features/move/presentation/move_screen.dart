import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_geometry.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/bottom_nav.dart';
import '../../../core/widgets/nuvo_avatar.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_error_state.dart';
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

    final cameraRaces = raceState.races
        .where((race) => resolveCameraVerification(race).isCameraVerifiable)
        .toList();

    final readyRaces = cameraRaces.where((race) {
      final myPart = uid != null ? race.participantFor(uid) : null;
      return race.status == 'active' && (myPart?.progressPercent ?? 0) < 100;
    }).toList();

    final completedRaces = cameraRaces.where((race) {
      final myPart = uid != null ? race.participantFor(uid) : null;
      return (myPart?.progressPercent ?? 0) >= 100;
    }).toList();

    final recentMoves = cameraRaces
        .expand((r) => r.recentProofs.map((p) => (race: r, proof: p)))
        .take(10)
        .toList();
    void openVerification(Race race) {
      debugLogCameraVerificationDecision(
        race,
        resolveCameraVerification(race),
        routeAction: 'move_screen_to_submit_proof',
      );
      context.push('/race/${race.id}/proof').then((_) {
        ref.read(raceControllerProvider.notifier).loadRaces();
      });
    }

    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            22,
            22,
            22,
            NuvoBottomNav.bottomPadding(context),
          ),
          children: [
            // ── Hero ─────────────────────────────────────────────────────────
            _MoveHero(readyCount: readyRaces.length),
            const SizedBox(height: 28),

            // ── Ready to move ────────────────────────────────────────────────
            if (raceState.loading &&
                readyRaces.isEmpty &&
                completedRaces.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: NuvoColors.blue,
                  ),
                ),
              )
            else if (raceState.error != null &&
                readyRaces.isEmpty &&
                completedRaces.isEmpty)
              NuvoErrorState(
                message: "Couldn't load your races.",
                onRetry: () =>
                    ref.read(raceControllerProvider.notifier).loadRaces(),
              )
            else if (readyRaces.isEmpty && completedRaces.isEmpty)
              _EmptyState(onStart: () => context.push('/races/new'))
            else if (readyRaces.isNotEmpty) ...[
              _ReadyNowModule(
                race: readyRaces.first,
                userId: uid,
                onVerify: () => openVerification(readyRaces.first),
              ),
              if (readyRaces.length > 1) ...[
                const SizedBox(height: 20),
                const _SectionLabel(label: 'Ready to move'),
                const SizedBox(height: 10),
                _MoveRaceGroup(
                  races: readyRaces.skip(1).toList(),
                  userId: uid,
                  onVerify: openVerification,
                ),
              ],
            ],

            // ── Completed races ──────────────────────────────────────────────
            if (completedRaces.isNotEmpty) ...[
              const SizedBox(height: 20),
              _CompletedSection(completedRaces: completedRaces, uid: uid),
            ],

            // ── Recent moves ─────────────────────────────────────────────────
            if (recentMoves.isNotEmpty) ...[
              const SizedBox(height: 20),
              const _SectionLabel(label: 'Recent moves'),
              const SizedBox(height: 10),
              _RecentMoveGroup(entries: recentMoves),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Hero ──────────────────────────────────────────────────────────────────────

class _MoveHero extends StatelessWidget {
  const _MoveHero({required this.readyCount});
  final int readyCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: NuvoColors.border),
        boxShadow: AppShadows.hardShadow4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 58,
                decoration: BoxDecoration(
                  color: NuvoColors.blue,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Move',
                      style: AppTextStyles.headlineLarge.copyWith(
                        color: NuvoColors.navy,
                        height: 1.05,
                        fontSize: 32,
                        letterSpacing: -0.9,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Choose a race, then verify your move.',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: NuvoColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (readyCount > 0) ...[
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: NuvoColors.panel,
                    borderRadius: BorderRadius.circular(NuvoRadii.pill),
                    border: NuvoBorders.quiet,
                  ),
                  child: Text(
                    '$readyCount ready',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: NuvoColors.navy,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ── Completed races section ───────────────────────────────────────────────────

class _CompletedSection extends StatefulWidget {
  const _CompletedSection({required this.completedRaces, this.uid});

  final List<Race> completedRaces;
  final String? uid;

  @override
  State<_CompletedSection> createState() => _CompletedSectionState();
}

class _CompletedSectionState extends State<_CompletedSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        PressableScale(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Row(
            children: [
              Text(
                'Completed',
                style: AppTextStyles.titleMedium.copyWith(
                  color: NuvoColors.navy,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: NuvoColors.success.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '${widget.completedRaces.length}',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: NuvoColors.success,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              AnimatedRotation(
                turns: _expanded ? 0.25 : 0,
                duration: const Duration(milliseconds: 200),
                child: const Icon(
                  Icons.chevron_right_rounded,
                  color: NuvoColors.muted,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 12),
          _MoveRaceGroup(
            races: widget.completedRaces,
            userId: widget.uid,
            onVerify: (_) {},
          ),
        ],
      ],
    );
  }
}

// ── Ready now module ──────────────────────────────────────────────────────────

class _ReadyNowModule extends StatelessWidget {
  const _ReadyNowModule({
    required this.race,
    required this.onVerify,
    this.userId,
  });

  final Race race;
  final String? userId;
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    final myPart = userId != null ? race.participantFor(userId!) : null;
    final pct = myPart?.progressPercent ?? 0;
    final others = race.participants
        .where((p) => p.userId != userId)
        .take(3)
        .toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: NuvoColors.icyBlue,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: NuvoColors.actionBlue.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: const BoxDecoration(
              color: NuvoColors.navy,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$pct%',
              style: AppTextStyles.labelMedium.copyWith(
                color: NuvoColors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  race.displayTitle,
                  style: AppTextStyles.titleMedium.copyWith(
                    color: NuvoColors.navy,
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        others.isEmpty
                            ? 'Solo race · make the next move'
                            : '${race.participantCount} racers · move the leaderboard',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: NuvoColors.textMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (others.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      NuvoAvatarStack(
                        avatars: others
                            .map(
                              (p) => (
                                initials: p.displayName,
                                photoUrl: p.profilePhotoUrl,
                              ),
                            )
                            .toList(),
                        total: race.participantCount,
                        size: 22,
                        max: 3,
                        borderColor: NuvoColors.icyBlue,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _VerifyAction(onTap: onVerify),
        ],
      ),
    );
  }
}

class _MoveRaceGroup extends StatelessWidget {
  const _MoveRaceGroup({
    required this.races,
    required this.onVerify,
    this.userId,
  });

  final List<Race> races;
  final String? userId;
  final ValueChanged<Race> onVerify;

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
          for (var i = 0; i < races.length; i++) ...[
            _RaceLogRow(
              race: races[i],
              userId: userId,
              onLog: () => onVerify(races[i]),
            ),
            if (i < races.length - 1)
              const Divider(
                height: 1,
                thickness: 1,
                indent: 72,
                color: NuvoColors.divider,
              ),
          ],
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
        constraints: const BoxConstraints(minHeight: 76),
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        color: isComplete
            ? NuvoColors.success.withValues(alpha: 0.05)
            : NuvoColors.surface,
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
                  _VerifyAction(onTap: onLog)
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
            const SizedBox(height: 10),
            NuvoRaceLane(progressPercent: pct, trackHeight: 3, dotDiameter: 10),
            const SizedBox(height: 8),
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

class _VerifyAction extends StatelessWidget {
  const _VerifyAction({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: NuvoColors.actionBlue,
          borderRadius: BorderRadius.circular(NuvoRadii.pill),
          border: Border.all(color: NuvoColors.navy, width: 1.5),
        ),
        child: Text(
          'Verify',
          style: AppTextStyles.labelSmall.copyWith(
            color: NuvoColors.white,
            fontWeight: FontWeight.w900,
          ),
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

class _RecentMoveGroup extends StatelessWidget {
  const _RecentMoveGroup({required this.entries});

  final List<({Race race, RaceProof proof})> entries;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: NuvoColors.border, width: 1.25),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            _RecentMoveRow(proof: entries[i].proof, race: entries[i].race),
            if (i < entries.length - 1)
              const Divider(
                height: 1,
                thickness: 1,
                indent: 64,
                color: NuvoColors.divider,
              ),
          ],
        ],
      ),
    );
  }
}

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
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      color: NuvoColors.surface,
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
      mainAxisSize: MainAxisSize.min,
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

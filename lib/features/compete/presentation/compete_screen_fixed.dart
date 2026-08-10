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
import '../../races/domain/race_display.dart';
import '../../races/presentation/create_race_screen.dart';
import '../../races/presentation/race_controller.dart';

class CompeteScreen extends ConsumerWidget {
  const CompeteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final raceState = ref.watch(raceControllerProvider);
    final user = ref.watch(authControllerProvider).user;
    final uid = user?.id;

    final cameraRaces = raceState.races
        .where((race) => resolveCameraVerification(race).isCameraVerifiable)
        .toList();
    final active = cameraRaces.where(raceIsActive).toList();
    final waiting = active.where((race) => race.participantCount <= 1).toList();
    final inMotion = active.where((race) => race.participantCount > 1).toList();
    final needsAttention = inMotion.isNotEmpty
        ? inMotion.first
        : active.isNotEmpty
        ? active.first
        : null;
    final inMotionRows = inMotion
        .where((race) => race.id != needsAttention?.id)
        .toList();
    final finished = raceState.races
        .where(raceIsCompleted)
        .where((race) => resolveCameraVerification(race).isCameraVerifiable)
        .toList();

    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: NuvoColors.blue,
          backgroundColor: NuvoColors.surface,
          onRefresh: () =>
              ref.read(raceControllerProvider.notifier).loadRaces(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: _CompeteHero(
                  activeCount: active.length,
                  finishedCount: finished.length,
                  onStart: () => context.push('/races/new'),
                  onJoin: () => context.push('/races/join'),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  28,
                  20,
                  NuvoBottomNav.bottomPadding(context),
                ),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    if (raceState.loading && raceState.races.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: NuvoColors.blue,
                          ),
                        ),
                      )
                    else if (raceState.error != null && raceState.races.isEmpty)
                      NuvoErrorState(
                        message: "Couldn't load your races.",
                        onRetry: () => ref
                            .read(raceControllerProvider.notifier)
                            .loadRaces(),
                      )
                    else if (raceState.races.isEmpty || cameraRaces.isEmpty)
                      _EmptyState(onStart: () => context.push('/races/new'))
                    else ...[
                      if (needsAttention != null) ...[
                        const _SectionLabel(label: 'Needs attention'),
                        const SizedBox(height: 12),
                        _NeedsAttentionModule(
                          race: needsAttention,
                          userId: uid,
                          onOpen: () =>
                              context.push('/race/${needsAttention.id}'),
                          onVerify: () =>
                              context.push('/race/${needsAttention.id}/proof'),
                        ),
                      ],
                      if (inMotionRows.isNotEmpty) ...[
                        SizedBox(height: needsAttention == null ? 0 : 24),
                        const _SectionLabel(label: 'In motion'),
                        const SizedBox(height: 12),
                        _ActiveLaneSection(races: inMotionRows, userId: uid),
                      ],
                      if (waiting.isNotEmpty) ...[
                        SizedBox(
                          height: needsAttention == null && inMotionRows.isEmpty
                              ? 0
                              : 24,
                        ),
                        const _SectionLabel(label: 'Waiting for crew'),
                        const SizedBox(height: 12),
                        _WaitingRail(races: waiting),
                      ],
                      if (finished.isNotEmpty) ...[
                        SizedBox(
                          height: active.isEmpty && needsAttention == null
                              ? 0
                              : 24,
                        ),
                        const _SectionLabel(label: 'Finished'),
                        const SizedBox(height: 12),
                        _FinishedRail(races: finished, userId: uid),
                      ],
                      const SizedBox(height: 24),
                      const _SectionLabel(label: 'Quick starts'),
                      const SizedBox(height: 12),
                      _QuickStartRow(
                        icon: Icons.fitness_center_rounded,
                        label: 'First to 100 Pushups',
                        sublabel: 'Editable camera race',
                        onTap: () => context.push(
                          '/races/new',
                          extra: RaceCreatePrefill.pushups,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _QuickStartRow(
                        icon: Icons.person_outline_rounded,
                        label: 'First to 15 Squats',
                        sublabel: 'Editable camera race',
                        onTap: () => context.push(
                          '/races/new',
                          extra: RaceCreatePrefill.squats,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _QuickStartRow(
                        icon: Icons.accessibility_new_rounded,
                        label: 'First to 500 Jumping Jacks',
                        sublabel: 'Editable camera race',
                        onTap: () => context.push(
                          '/races/new',
                          extra: RaceCreatePrefill.jumpingJacks,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _QuickStartRow(
                        icon: Icons.directions_walk_rounded,
                        label: 'First to 40 Lunges',
                        sublabel: 'Editable camera race',
                        onTap: () => context.push(
                          '/races/new',
                          extra: RaceCreatePrefill.lunges,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _QuickStartRow(
                        icon: Icons.timer_outlined,
                        label: 'First to 300 Plank Seconds',
                        sublabel: 'Editable camera race',
                        onTap: () => context.push(
                          '/races/new',
                          extra: RaceCreatePrefill.plank,
                        ),
                      ),
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
}

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

class _CompeteHero extends StatelessWidget {
  const _CompeteHero({
    required this.activeCount,
    required this.finishedCount,
    required this.onStart,
    required this.onJoin,
  });

  final int activeCount;
  final int finishedCount;
  final VoidCallback onStart;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(22, 22, 22, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [NuvoColors.icyBlue, NuvoColors.surface, NuvoColors.surface],
          stops: [0, 0.42, 1],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: NuvoColors.border),
        boxShadow: AppShadows.surfaceShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: NuvoColors.blue,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                finishedCount == 0
                    ? 'A fresh start line'
                    : '$finishedCount ${finishedCount == 1 ? 'race' : 'races'} finished',
                style: AppTextStyles.labelMedium.copyWith(
                  color: NuvoColors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Compete',
                      style: AppTextStyles.headlineLarge.copyWith(
                        color: NuvoColors.navy,
                        height: 1.05,
                        fontSize: 32,
                        letterSpacing: -0.9,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Set a finish line and pull in your crew.',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: NuvoColors.muted,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _CountPill(value: '$activeCount', label: 'active'),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: NuvoPrimaryButton(
                  label: 'Start race',
                  expand: true,
                  onPressed: onStart,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: NuvoOutlineButton(
                  label: 'Join',
                  expand: true,
                  onPressed: onJoin,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          value,
          style: AppTextStyles.number(
            24,
            color: NuvoColors.actionBlue,
            weight: FontWeight.w800,
          ),
        ),
        Text(
          label,
          style: AppTextStyles.labelSmall.copyWith(
            color: NuvoColors.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _NeedsAttentionModule extends StatelessWidget {
  const _NeedsAttentionModule({
    required this.race,
    required this.onOpen,
    required this.onVerify,
    this.userId,
  });

  final Race race;
  final String? userId;
  final VoidCallback onOpen;
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    final myPart = userId != null ? race.participantFor(userId!) : null;
    final pct = raceProgressPercent(race, myPart);
    final rank = rankForUser(race, userId);
    final others = race.participants
        .where((p) => p.userId != userId)
        .take(3)
        .toList();

    return PressableScale(
      onTap: onOpen,
      child: Container(
        constraints: const BoxConstraints(minHeight: 118),
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        decoration: BoxDecoration(
          color: NuvoColors.icyBlue,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: NuvoColors.actionBlue.withValues(alpha: 0.22),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
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
                      fontSize: 18,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    rank == null
                        ? '${race.participantCount} ${race.participantCount == 1 ? 'racer' : 'racers'} on the start line'
                        : 'You are #$rank · ${raceProgressLabel(race, myPart)}',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: NuvoColors.textMuted,
                      height: 1.25,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  NuvoRaceLane(
                    progressPercent: pct,
                    trackHeight: 4,
                    dotDiameter: 11,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (others.isNotEmpty)
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
                      if (others.isNotEmpty) const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          others.isEmpty
                              ? 'Needs crew or your first move'
                              : 'Ready to move the leaderboard',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: NuvoColors.muted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            NuvoPrimaryButton(
              label: 'Verify',
              small: true,
              onPressed: onVerify,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveLaneSection extends StatelessWidget {
  const _ActiveLaneSection({required this.races, this.userId});

  final List<Race> races;
  final String? userId;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: NuvoColors.white.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Column(
          children: [
            for (var i = 0; i < races.length; i++) ...[
              _ActiveRaceLane(
                race: races[i],
                userId: userId,
                highlighted: i < 2 && _isCloseRace(races[i], userId),
                onOpen: () => context.push('/race/${races[i].id}'),
                onVerify: () => context.push('/race/${races[i].id}/proof'),
              ),
              if (i < races.length - 1)
                const Divider(
                  height: 1,
                  thickness: 1,
                  indent: 64,
                  color: NuvoColors.divider,
                ),
            ],
          ],
        ),
      ),
    );
  }

  static bool _isCloseRace(Race race, String? userId) {
    if (userId == null || race.participants.length < 2) return false;
    final me = race.participantFor(userId);
    if (me == null) return false;
    final sorted = serverRankedParticipants(race);
    final leader = sorted.isEmpty ? null : sorted.first;
    if (leader == null || leader.userId == me.userId) return false;
    return (leader.progressPercent - me.progressPercent).abs() <= 15;
  }
}

class _ActiveRaceLane extends StatelessWidget {
  const _ActiveRaceLane({
    required this.race,
    required this.onOpen,
    required this.onVerify,
    required this.highlighted,
    this.userId,
  });

  final Race race;
  final String? userId;
  final VoidCallback onOpen;
  final VoidCallback onVerify;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final myPart = userId != null ? race.participantFor(userId!) : null;
    final pct = raceProgressPercent(race, myPart);
    final rank = rankForUser(race, userId);
    final others = race.participants
        .where((p) => p.userId != userId)
        .take(3)
        .toList();

    return Semantics(
      button: true,
      label: race.displayTitle,
      child: PressableScale(
        onTap: onOpen,
        scale: 0.985,
        child: Container(
          constraints: const BoxConstraints(minHeight: 82),
          padding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
          decoration: BoxDecoration(
            color: highlighted ? NuvoColors.icyBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 3,
                height: 54,
                decoration: BoxDecoration(
                  color: highlighted
                      ? NuvoColors.actionBlue
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            race.displayTitle,
                            style: AppTextStyles.titleMedium.copyWith(
                              color: NuvoColors.navy,
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (rank != null) ...[
                          const SizedBox(width: 8),
                          _RankBadge(rank: rank, leading: rank == 1),
                        ],
                        const SizedBox(width: 8),
                        const NuvoIcon(
                          NuvoIconType.arrow,
                          color: NuvoColors.textMuted,
                          size: 14,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    NuvoRaceLane(
                      progressPercent: pct,
                      trackHeight: 4,
                      dotDiameter: 10,
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        if (others.isNotEmpty)
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
                            size: 20,
                            max: 3,
                            borderColor: highlighted
                                ? NuvoColors.icyBlue
                                : NuvoColors.white,
                          ),
                        if (others.isNotEmpty) const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            _laneStatus(race, myPart, highlighted),
                            style: AppTextStyles.bodySmall.copyWith(
                              color: NuvoColors.textMuted,
                              height: 1.1,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _VerifyIconButton(
                label: 'Verify ${race.displayTitle}',
                onTap: onVerify,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _laneStatus(Race race, RaceParticipant? myPart, bool highlighted) {
    if (highlighted) return 'Close race · ${raceProgressLabel(race, myPart)}';
    return '${race.participantCount} ${race.participantCount == 1 ? 'racer' : 'racers'} · ${raceProgressLabel(race, myPart)}';
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank, required this.leading});

  final int rank;
  final bool leading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: leading
            ? NuvoColors.actionBlue.withValues(alpha: 0.10)
            : NuvoColors.panel,
        borderRadius: BorderRadius.circular(NuvoRadii.pill),
      ),
      child: Text(
        '#$rank',
        style: AppTextStyles.labelSmall.copyWith(
          color: leading ? NuvoColors.actionBlue : NuvoColors.navy,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _VerifyIconButton extends StatelessWidget {
  const _VerifyIconButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: PressableScale(
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: NuvoColors.actionBlue,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: NuvoColors.navy, width: 1.5),
            boxShadow: AppShadows.hardSmall,
          ),
          child: const Icon(
            Icons.camera_alt_rounded,
            color: NuvoColors.white,
            size: 19,
          ),
        ),
      ),
    );
  }
}

class _WaitingRail extends StatelessWidget {
  const _WaitingRail({required this.races});

  final List<Race> races;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (var i = 0; i < races.length; i++) ...[
            _WaitingTile(
              race: races[i],
              onOpen: () => context.push('/race/${races[i].id}'),
              onInvite: () => context.push('/race/${races[i].id}/invite'),
            ),
            if (i < races.length - 1) const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }
}

class _WaitingTile extends StatelessWidget {
  const _WaitingTile({
    required this.race,
    required this.onOpen,
    required this.onInvite,
  });

  final Race race;
  final VoidCallback onOpen;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onOpen,
      child: Container(
        width: 226,
        constraints: const BoxConstraints(minHeight: 118),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: NuvoColors.icyBlue,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: NuvoColors.border, width: 1.25),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.group_add_rounded,
                  color: NuvoColors.actionBlue,
                  size: 18,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Needs crew',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: NuvoColors.actionBlue,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onInvite,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text(
                      'Invite',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: NuvoColors.navy,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              race.displayTitle,
              style: AppTextStyles.titleMedium.copyWith(
                color: NuvoColors.navy,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              '${race.participantCount} ${race.participantCount == 1 ? 'racer' : 'racers'} at the start line',
              style: AppTextStyles.bodySmall.copyWith(
                color: NuvoColors.textMuted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _FinishedRail extends StatelessWidget {
  const _FinishedRail({required this.races, this.userId});

  final List<Race> races;
  final String? userId;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (var i = 0; i < races.length; i++) ...[
            _FinishedTile(
              race: races[i],
              userId: userId,
              onTap: () => context.push('/race/${races[i].id}'),
            ),
            if (i < races.length - 1) const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }
}

class _FinishedTile extends StatelessWidget {
  const _FinishedTile({required this.race, required this.onTap, this.userId});

  final Race race;
  final String? userId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rank = rankForUser(race, userId);

    return PressableScale(
      onTap: onTap,
      child: Container(
        width: 166,
        constraints: const BoxConstraints(minHeight: 96),
        padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
        decoration: BoxDecoration(
          color: NuvoColors.success.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: NuvoColors.success.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: NuvoColors.success,
              size: 18,
            ),
            const SizedBox(height: 8),
            Text(
              race.displayTitle,
              style: AppTextStyles.bodyMedium.copyWith(
                color: NuvoColors.navy,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              rank == null ? 'Finished' : 'Finished · #$rank',
              style: AppTextStyles.labelSmall.copyWith(
                color: NuvoColors.success,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickStartRow extends StatelessWidget {
  const _QuickStartRow({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String sublabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: NuvoHardOffset(
        offset: 3,
        radius: NuvoRadii.lg,
        plateColor: NuvoColors.offsetGrey,
        faceColor: NuvoColors.white,
        borderColor: NuvoColors.offsetGrey,
        borderWidth: 1.5,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: NuvoColors.panel,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: NuvoColors.border, width: 1.2),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: NuvoColors.navy, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: AppTextStyles.titleMedium.copyWith(
                      color: NuvoColors.navy,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sublabel,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: NuvoColors.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: NuvoColors.textMuted,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

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
          child: const NuvoIcon(
            NuvoIconType.flag,
            color: NuvoColors.blue,
            size: 22,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'No races yet.',
          style: AppTextStyles.headlineMedium.copyWith(color: NuvoColors.navy),
        ),
        const SizedBox(height: 8),
        Text(
          'Start a race, set a finish line, and pull in your crew.',
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

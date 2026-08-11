import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/bottom_nav.dart';
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

/// Compete — Variant B IA.
///
/// Screen question: "What competition matters to me right now, and how do I
/// start or join something?"
///
/// Structure:
/// 1. Compact header (title + active/finished summary + Start/Join)
/// 2. ONE loud "Continue competing" navy surface
/// 3. "Your races" compact list (capped at 3, inline See all)
/// 4. Waiting-for-crew summary row (inline expansion)
/// 5. Finished summary row (inline expansion)
/// 6. Quick Starts in a compact 2-column wrap
class CompeteScreen extends ConsumerStatefulWidget {
  const CompeteScreen({super.key});

  @override
  ConsumerState<CompeteScreen> createState() => _CompeteScreenState();
}

class _CompeteScreenState extends ConsumerState<CompeteScreen> {
  bool _racesExpanded = false;
  bool _waitingExpanded = false;
  bool _finishedExpanded = false;

  static const _racesCap = 3;

  @override
  Widget build(BuildContext context) {
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
                child: _CompactHeader(
                  activeCount: active.length,
                  finishedCount: finished.length,
                  onStart: () => context.push('/races/new'),
                  onJoin: () => context.push('/races/join'),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  22,
                  16,
                  22,
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
                        _ContinueCompetingCard(
                          race: needsAttention,
                          userId: uid,
                          onOpen: () =>
                              context.push('/race/${needsAttention.id}'),
                        ),
                        const SizedBox(height: 24),
                      ],
                      if (inMotionRows.isNotEmpty) ...[
                        _CappedRaceList(
                          races: inMotionRows,
                          userId: uid,
                          expanded: _racesExpanded,
                          cap: _racesCap,
                          onToggleExpand: () =>
                              setState(() => _racesExpanded = !_racesExpanded),
                          onOpen: (race) => context.push('/race/${race.id}'),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (waiting.isNotEmpty) ...[
                        _SummaryRow(
                          icon: Icons.group_add_rounded,
                          iconBg: NuvoColors.amberTint,
                          iconColor: NuvoColors.warning,
                          title: 'Waiting for crew',
                          subtitle:
                              '${waiting.length} ${waiting.length == 1 ? 'race' : 'races'} need crew',
                          expanded: _waitingExpanded,
                          onToggle: () => setState(
                            () => _waitingExpanded = !_waitingExpanded,
                          ),
                          children: [
                            const SizedBox(height: 10),
                            _SummaryExpansionList(
                              races: waiting,
                              userId: uid,
                              onOpen: (race) =>
                                  context.push('/race/${race.id}'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (finished.isNotEmpty) ...[
                        _SummaryRow(
                          icon: Icons.check_circle_rounded,
                          iconBg: NuvoColors.success.withValues(alpha: 0.10),
                          iconColor: NuvoColors.success,
                          title: 'Finished',
                          subtitle:
                              '${finished.length} ${finished.length == 1 ? 'race' : 'races'} · ${_wonCount(finished, uid)} won',
                          expanded: _finishedExpanded,
                          onToggle: () => setState(
                            () => _finishedExpanded = !_finishedExpanded,
                          ),
                          children: [
                            const SizedBox(height: 10),
                            _SummaryExpansionList(
                              races: finished,
                              userId: uid,
                              onOpen: (race) =>
                                  context.push('/race/${race.id}'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ],
                      const SizedBox(height: 8),
                      _QuickStartsBento(
                        onStart: (prefill) =>
                            context.push('/races/new', extra: prefill),
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

  int _wonCount(List<Race> races, String? uid) {
    if (uid == null) return 0;
    var count = 0;
    for (final race in races) {
      final rank = rankForUser(race, uid);
      if (rank == 1) count++;
    }
    return count;
  }
}

// ── Compact header ────────────────────────────────────────────────────────────

class _CompactHeader extends StatelessWidget {
  const _CompactHeader({
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
    final summary = finishedCount > 0
        ? '$activeCount active · $finishedCount finished'
        : '$activeCount ${activeCount == 1 ? 'race' : 'races'} active';

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Compete',
                  style: AppTextStyles.headlineLarge.copyWith(
                    color: NuvoColors.navy,
                    fontSize: 30,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  summary,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: NuvoColors.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: NuvoPrimaryButton(
              label: 'Start race',
              small: true,
              onPressed: onStart,
              expand: true,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 1,
            child: NuvoOutlineButton(
              label: 'Join',
              small: true,
              onPressed: onJoin,
              expand: true,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Continue competing (ONE loud surface) ─────────────────────────────────────

class _ContinueCompetingCard extends StatelessWidget {
  const _ContinueCompetingCard({
    required this.race,
    required this.onOpen,
    this.userId,
  });

  final Race race;
  final String? userId;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final myPart = userId != null ? race.participantFor(userId!) : null;
    final pct = raceProgressPercent(race, myPart);
    final rank = rankForUser(race, userId);
    final activity = raceActivityTitle(race);
    final target = raceTargetLabel(race);

    final rankStr = rank != null ? ' · You\'re ${_ordinal(rank)}' : '';
    final metaLine =
        '${race.participantCount} ${race.participantCount == 1 ? 'racer' : 'racers'}$rankStr · $pct%';

    return PressableScale(
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: NuvoColors.navy,
          borderRadius: BorderRadius.circular(24),
          boxShadow: AppShadows.hardMedium,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$activity · $target',
              style: AppTextStyles.labelSmall.copyWith(
                color: NuvoColors.blue,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              race.displayTitle,
              style: AppTextStyles.headlineMedium.copyWith(
                color: NuvoColors.white,
                fontSize: 20,
                height: 1.15,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              metaLine,
              style: AppTextStyles.bodySmall.copyWith(
                color: NuvoColors.white.withValues(alpha: 0.65),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            NuvoRaceLane(
              progressPercent: pct,
              onDark: true,
              trackHeight: 6,
              dotDiameter: 12,
            ),
            const SizedBox(height: 16),
            NuvoPrimaryButton(
              label: 'View leaderboard',
              expand: true,
              small: true,
              onPressed: onOpen,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Capped race list with inline See all ──────────────────────────────────────

class _CappedRaceList extends StatelessWidget {
  const _CappedRaceList({
    required this.races,
    required this.userId,
    required this.expanded,
    required this.cap,
    required this.onToggleExpand,
    required this.onOpen,
  });

  final List<Race> races;
  final String? userId;
  final bool expanded;
  final int cap;
  final VoidCallback onToggleExpand;
  final ValueChanged<Race> onOpen;

  @override
  Widget build(BuildContext context) {
    final visible = expanded ? races : races.take(cap).toList();
    final hasMore = races.length > cap;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Your races · ${races.length} active',
              style: AppTextStyles.labelSmall.copyWith(
                color: NuvoColors.textMuted,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
            const Spacer(),
            if (hasMore)
              GestureDetector(
                onTap: onToggleExpand,
                child: Text(
                  expanded ? 'Show less' : 'See all',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: NuvoColors.blue,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: NuvoColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: NuvoColors.divider),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < visible.length; i++) ...[
                _CompactRaceRow(
                  race: visible[i],
                  index: i + 1,
                  userId: userId,
                  onTap: () => onOpen(visible[i]),
                ),
                if (i < visible.length - 1)
                  const Divider(
                    height: 1,
                    thickness: 1,
                    indent: 54,
                    color: NuvoColors.divider,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ── Compact race row (quiet, tappable → Race Detail) ──────────────────────────

class _CompactRaceRow extends StatelessWidget {
  const _CompactRaceRow({
    required this.race,
    required this.index,
    required this.onTap,
    this.userId,
  });

  final Race race;
  final int index;
  final String? userId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final myPart = userId != null ? race.participantFor(userId!) : null;
    final pct = raceProgressPercent(race, myPart);

    return Semantics(
      button: true,
      label: race.displayTitle,
      child: PressableScale(
        onTap: onTap,
        scale: 0.985,
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: NuvoColors.panel,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$index',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: NuvoColors.navy,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      race.displayTitle,
                      style: AppTextStyles.titleMedium.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${race.participantCount} ${race.participantCount == 1 ? 'racer' : 'racers'} · $pct%',
                      style: AppTextStyles.bodySmall.copyWith(
                        fontSize: 12,
                        color: NuvoColors.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const NuvoIcon(
                NuvoIconType.arrow,
                color: NuvoColors.textMuted,
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Summary row (Waiting / Finished) with inline expansion ────────────────────

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.expanded,
    required this.onToggle,
    required this.children,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool expanded;
  final VoidCallback onToggle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PressableScale(
          onTap: onToggle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: NuvoColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: NuvoColors.divider),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, color: iconColor, size: 16),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTextStyles.titleMedium.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: AppTextStyles.bodySmall.copyWith(
                          fontSize: 12,
                          color: NuvoColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: expanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(
                    Icons.chevron_right_rounded,
                    color: NuvoColors.textMuted,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded) ...children,
      ],
    );
  }
}

/// List of compact race rows used inside an expanded summary section.
class _SummaryExpansionList extends StatelessWidget {
  const _SummaryExpansionList({
    required this.races,
    required this.userId,
    required this.onOpen,
  });

  final List<Race> races;
  final String? userId;
  final ValueChanged<Race> onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NuvoColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < races.length; i++) ...[
            _CompactRaceRow(
              race: races[i],
              index: i + 1,
              userId: userId,
              onTap: () => onOpen(races[i]),
            ),
            if (i < races.length - 1)
              const Divider(
                height: 1,
                thickness: 1,
                indent: 54,
                color: NuvoColors.divider,
              ),
          ],
        ],
      ),
    );
  }
}

// ── Quick Starts (compact 2-column wrap) ──────────────────────────────────────

class _QuickStartsBento extends StatelessWidget {
  const _QuickStartsBento({required this.onStart});
  final ValueChanged<RaceCreatePrefill> onStart;

  static const _items = [
    (
      icon: Icons.fitness_center_rounded,
      label: '100 Pushups',
      prefill: RaceCreatePrefill.pushups,
    ),
    (
      icon: Icons.person_outline_rounded,
      label: '15 Squats',
      prefill: RaceCreatePrefill.squats,
    ),
    (
      icon: Icons.accessibility_new_rounded,
      label: '500 Jumping Jacks',
      prefill: RaceCreatePrefill.jumpingJacks,
    ),
    (
      icon: Icons.directions_walk_rounded,
      label: '40 Lunges',
      prefill: RaceCreatePrefill.lunges,
    ),
    (
      icon: Icons.timer_outlined,
      label: '300 Plank Seconds',
      prefill: RaceCreatePrefill.plank,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick starts',
          style: AppTextStyles.labelSmall.copyWith(
            color: NuvoColors.textMuted,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in _items)
              _QuickStartChip(
                icon: item.icon,
                label: item.label,
                onTap: () => onStart(item.prefill),
              ),
          ],
        ),
      ],
    );
  }
}

class _QuickStartChip extends StatelessWidget {
  const _QuickStartChip({
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
        constraints: const BoxConstraints(minWidth: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: NuvoColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: NuvoColors.border, width: 1.25),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: NuvoColors.panel,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: NuvoColors.border, width: 1),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: NuvoColors.navy, size: 16),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                style: AppTextStyles.labelMedium.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
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

// ── Helpers ───────────────────────────────────────────────────────────────────

String _ordinal(int n) {
  if (n >= 11 && n <= 13) return '${n}th';
  switch (n % 10) {
    case 1:
      return '${n}st';
    case 2:
      return '${n}nd';
    case 3:
      return '${n}rd';
    default:
      return '${n}th';
  }
}

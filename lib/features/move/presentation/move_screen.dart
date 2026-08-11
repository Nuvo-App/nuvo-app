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
import '../../races/presentation/race_controller.dart';

/// Verify — Variant B IA.
///
/// Screen question: "What should I act on next, and how do I get into
/// verification immediately?"
///
/// Structure:
/// 1. Compact Verify header ("Verify" + "N ready to move")
/// 2. Ready / Completed / Recent segmented state
/// 3. ONE loud "Up next" verification card (Ready segment only)
/// 4. "Also ready" compact rows (capped, inline See all)
/// 5. No repeated full-width Verify buttons
/// 6. Completed/Recent shown through the segmented state
class MoveScreen extends ConsumerStatefulWidget {
  const MoveScreen({super.key});

  @override
  ConsumerState<MoveScreen> createState() => _MoveScreenState();
}

enum _VerifySegment { ready, completed, recent }

class _MoveScreenState extends ConsumerState<MoveScreen> {
  _VerifySegment _segment = _VerifySegment.ready;
  bool _readyExpanded = false;
  bool _completedExpanded = false;
  bool _recentExpanded = false;

  static const _readyCap = 3;
  static const _completedCap = 5;
  static const _recentCap = 5;

  @override
  Widget build(BuildContext context) {
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
        .take(20)
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

    final allEmpty =
        readyRaces.isEmpty && completedRaces.isEmpty && recentMoves.isEmpty;

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
            // ── Compact header ────────────────────────────────────────────────
            _CompactVerifyHeader(readyCount: readyRaces.length),
            const SizedBox(height: NuvoSpacing.xl),

            // ── Loading / error / empty ───────────────────────────────────────
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
            else if (allEmpty)
              _EmptyState(onStart: () => context.push('/races/new'))
            // ── Segmented control + segment content ───────────────────────────
            else ...[
              _SegmentedControl(
                segment: _segment,
                readyCount: readyRaces.length,
                completedCount: completedRaces.length,
                recentCount: recentMoves.length,
                onChanged: (s) => setState(() {
                  _segment = s;
                  _readyExpanded = false;
                  _completedExpanded = false;
                  _recentExpanded = false;
                }),
              ),
              const SizedBox(height: NuvoSpacing.xl),

              switch (_segment) {
                _VerifySegment.ready => _ReadySegment(
                  races: readyRaces,
                  userId: uid,
                  expanded: _readyExpanded,
                  cap: _readyCap,
                  onToggleExpand: () =>
                      setState(() => _readyExpanded = !_readyExpanded),
                  onVerify: openVerification,
                  onStartRace: () => context.push('/races/new'),
                ),
                _VerifySegment.completed => _CompletedSegment(
                  races: completedRaces,
                  userId: uid,
                  expanded: _completedExpanded,
                  cap: _completedCap,
                  onToggleExpand: () =>
                      setState(() => _completedExpanded = !_completedExpanded),
                  onOpen: (race) => context.push('/race/${race.id}'),
                ),
                _VerifySegment.recent => _RecentSegment(
                  entries: recentMoves,
                  expanded: _recentExpanded,
                  cap: _recentCap,
                  onToggleExpand: () =>
                      setState(() => _recentExpanded = !_recentExpanded),
                  onOpen: (race) => context.push('/race/${race.id}'),
                ),
              },
            ],
          ],
        ),
      ),
    );
  }
}

// ── Compact header ────────────────────────────────────────────────────────────

class _CompactVerifyHeader extends StatelessWidget {
  const _CompactVerifyHeader({required this.readyCount});
  final int readyCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Verify',
          style: AppTextStyles.headlineLarge.copyWith(
            color: NuvoColors.navy,
            fontSize: 30,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: NuvoSpacing.xs),
        Text(
          readyCount > 0
              ? '$readyCount ${readyCount == 1 ? 'race' : 'races'} ready to move'
              : 'No races ready to move',
          style: AppTextStyles.bodySmall.copyWith(
            color: NuvoColors.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ── Segmented control ─────────────────────────────────────────────────────────

class _SegmentedControl extends StatelessWidget {
  const _SegmentedControl({
    required this.segment,
    required this.readyCount,
    required this.completedCount,
    required this.recentCount,
    required this.onChanged,
  });

  final _VerifySegment segment;
  final int readyCount;
  final int completedCount;
  final int recentCount;
  final ValueChanged<_VerifySegment> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: NuvoColors.panelLight,
        borderRadius: BorderRadius.circular(NuvoRadii.card),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _SegmentTab(
            label: 'Ready',
            count: readyCount,
            selected: segment == _VerifySegment.ready,
            onTap: () => onChanged(_VerifySegment.ready),
          ),
          _SegmentTab(
            label: 'Completed',
            count: completedCount,
            selected: segment == _VerifySegment.completed,
            onTap: () => onChanged(_VerifySegment.completed),
          ),
          _SegmentTab(
            label: 'Recent',
            count: recentCount,
            selected: segment == _VerifySegment.recent,
            onTap: () => onChanged(_VerifySegment.recent),
          ),
        ],
      ),
    );
  }
}

class _SegmentTab extends StatelessWidget {
  const _SegmentTab({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? NuvoColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(NuvoRadii.xs),
            border: selected
                ? Border.all(color: NuvoColors.border, width: 1)
                : null,
            boxShadow: selected ? AppShadows.hardSmall : null,
          ),
          child: Column(
            children: [
              Text(
                label,
                style: AppTextStyles.labelMedium.copyWith(
                  fontSize: 13,
                  color: selected ? NuvoColors.navy : NuvoColors.textMuted,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$count',
                style: AppTextStyles.labelSmall.copyWith(
                  fontSize: 10,
                  color: selected ? NuvoColors.muted : NuvoColors.textDim,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Ready segment ─────────────────────────────────────────────────────────────

class _ReadySegment extends StatelessWidget {
  const _ReadySegment({
    required this.races,
    required this.userId,
    required this.expanded,
    required this.cap,
    required this.onToggleExpand,
    required this.onVerify,
    required this.onStartRace,
  });

  final List<Race> races;
  final String? userId;
  final bool expanded;
  final int cap;
  final VoidCallback onToggleExpand;
  final ValueChanged<Race> onVerify;
  final VoidCallback onStartRace;

  @override
  Widget build(BuildContext context) {
    if (races.isEmpty) {
      return _SegmentEmptyState(
        icon: Icons.directions_run_rounded,
        title: 'No races ready to verify.',
        subtitle: 'Start or join a race to begin logging moves.',
        actionLabel: 'Start a race',
        onAction: onStartRace,
      );
    }

    final upNext = races.first;
    final alsoReady = races.skip(1).toList();
    final visibleAlsoReady = expanded
        ? alsoReady
        : alsoReady.take(cap).toList();
    final hasMore = alsoReady.length > cap;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Up next (ONE loud surface) ────────────────────────────────────────
        Text(
          'Up next',
          style: AppTextStyles.labelSmall.copyWith(
            color: NuvoColors.textMuted,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        _UpNextCard(
          race: upNext,
          userId: userId,
          onVerify: () => onVerify(upNext),
        ),
        if (alsoReady.isNotEmpty) ...[
          const SizedBox(height: NuvoSpacing.xl),
          Row(
            children: [
              Text(
                'Also ready',
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
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Text(
                      expanded ? 'Show less' : 'See all ${alsoReady.length}',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: NuvoColors.blue,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: NuvoColors.surface,
              borderRadius: BorderRadius.circular(NuvoRadii.card),
              border: Border.all(color: NuvoColors.divider),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < visibleAlsoReady.length; i++) ...[
                  _VerifyRaceRow(
                    race: visibleAlsoReady[i],
                    userId: userId,
                    onTap: () => onVerify(visibleAlsoReady[i]),
                  ),
                  if (i < visibleAlsoReady.length - 1)
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
      ],
    );
  }
}

// ── Up next card (ONE loud surface) ───────────────────────────────────────────

class _UpNextCard extends StatelessWidget {
  const _UpNextCard({required this.race, required this.onVerify, this.userId});

  final Race race;
  final String? userId;
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    final myPart = userId != null ? race.participantFor(userId!) : null;
    final pct = raceProgressPercent(race, myPart);
    final activity = raceActivityTitle(race);
    final target = raceTargetLabel(race);
    final rank = rankForUser(race, userId);

    final rankStr = rank != null ? ' · You\'re ${_ordinal(rank)}' : '';
    final metaLine =
        '${race.participantCount} ${race.participantCount == 1 ? 'racer' : 'racers'}$rankStr · $pct%';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: NuvoColors.navy,
        borderRadius: BorderRadius.circular(NuvoRadii.button),
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
          const SizedBox(height: NuvoSpacing.lg),
          NuvoRaceLane(
            progressPercent: pct,
            onDark: true,
            trackHeight: 6,
            dotDiameter: 12,
          ),
          const SizedBox(height: NuvoSpacing.lg),
          NuvoPrimaryButton(
            label: 'Start verification',
            icon: Icons.camera_alt_rounded,
            expand: true,
            small: true,
            onPressed: onVerify,
          ),
        ],
      ),
    );
  }
}

// ── Verify race row (quiet, tappable → verification flow) ─────────────────────

class _VerifyRaceRow extends StatelessWidget {
  const _VerifyRaceRow({required this.race, required this.onTap, this.userId});

  final Race race;
  final String? userId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final myPart = userId != null ? race.participantFor(userId!) : null;
    final pct = raceProgressPercent(race, myPart);
    final activity = raceActivityTitle(race);

    return Semantics(
      button: true,
      label: 'Verify ${race.displayTitle}',
      child: PressableScale(
        onTap: onTap,
        scale: 0.985,
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: NuvoColors.panel,
                  borderRadius: BorderRadius.circular(NuvoRadii.badge),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.camera_alt_outlined,
                  color: NuvoColors.navy,
                  size: 16,
                ),
              ),
              const SizedBox(width: NuvoSpacing.md),
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
                      '$activity · $pct%',
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
              const SizedBox(width: NuvoSpacing.sm),
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

// ── Completed segment ─────────────────────────────────────────────────────────

class _CompletedSegment extends StatelessWidget {
  const _CompletedSegment({
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
    if (races.isEmpty) {
      return const _SegmentEmptyState(
        icon: Icons.check_circle_outline_rounded,
        title: 'No completed races yet.',
        subtitle: 'Races you finish will show up here.',
      );
    }

    final visible = expanded ? races : races.take(cap).toList();
    final hasMore = races.length > cap;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasMore)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GestureDetector(
                onTap: onToggleExpand,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Text(
                    expanded ? 'Show less' : 'See all ${races.length}',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: NuvoColors.blue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: NuvoColors.surface,
            borderRadius: BorderRadius.circular(NuvoRadii.card),
            border: Border.all(color: NuvoColors.divider),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < visible.length; i++) ...[
                _CompletedRaceRow(
                  race: visible[i],
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

class _CompletedRaceRow extends StatelessWidget {
  const _CompletedRaceRow({
    required this.race,
    required this.onTap,
    this.userId,
  });

  final Race race;
  final String? userId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rank = rankForUser(race, userId);
    final activity = raceActivityTitle(race);

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
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: NuvoColors.success.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(NuvoRadii.badge),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.check_rounded,
                  color: NuvoColors.success,
                  size: 16,
                ),
              ),
              const SizedBox(width: NuvoSpacing.md),
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
                      rank != null
                          ? '$activity · Finished #${_ordinal(rank)}'
                          : '$activity · Finished',
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
              const SizedBox(width: NuvoSpacing.sm),
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

// ── Recent segment ────────────────────────────────────────────────────────────

class _RecentSegment extends StatelessWidget {
  const _RecentSegment({
    required this.entries,
    required this.expanded,
    required this.cap,
    required this.onToggleExpand,
    required this.onOpen,
  });

  final List<({Race race, RaceProof proof})> entries;
  final bool expanded;
  final int cap;
  final VoidCallback onToggleExpand;
  final ValueChanged<Race> onOpen;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const _SegmentEmptyState(
        icon: Icons.history_rounded,
        title: 'No recent moves.',
        subtitle: 'Proofs you submit will appear here.',
      );
    }

    final visible = expanded ? entries : entries.take(cap).toList();
    final hasMore = entries.length > cap;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasMore)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GestureDetector(
                onTap: onToggleExpand,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Text(
                    expanded ? 'Show less' : 'See all ${entries.length}',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: NuvoColors.blue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: NuvoColors.surface,
            borderRadius: BorderRadius.circular(NuvoRadii.card),
            border: Border.all(color: NuvoColors.divider),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < visible.length; i++) ...[
                _RecentProofRow(
                  proof: visible[i].proof,
                  race: visible[i].race,
                  onTap: () => onOpen(visible[i].race),
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

class _RecentProofRow extends StatelessWidget {
  const _RecentProofRow({
    required this.proof,
    required this.race,
    required this.onTap,
  });

  final RaceProof proof;
  final Race race;
  final VoidCallback onTap;

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

    return Semantics(
      button: true,
      label: '${proof.displayName} · ${race.displayTitle}',
      child: PressableScale(
        onTap: onTap,
        scale: 0.985,
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              NuvoAvatar(
                initials: initial,
                photoUrl: proof.profilePhotoUrl,
                size: 34,
                bgColor: NuvoColors.panel,
                textColor: NuvoColors.navy,
              ),
              const SizedBox(width: NuvoSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      proof.displayName,
                      style: AppTextStyles.titleMedium.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
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
                              fontSize: 12,
                              color: NuvoColors.textMuted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            statusLabel,
                            style: AppTextStyles.labelSmall.copyWith(
                              fontSize: 10,
                              color: statusColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (valueStr != null) ...[
                const SizedBox(width: NuvoSpacing.sm),
                Text(
                  valueStr,
                  style: AppTextStyles.labelMedium.copyWith(
                    fontSize: 12,
                    color: NuvoColors.navy,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Segment empty state ───────────────────────────────────────────────────────

class _SegmentEmptyState extends StatelessWidget {
  const _SegmentEmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: NuvoColors.panelLight,
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: NuvoColors.muted, size: 22),
        ),
        const SizedBox(height: NuvoSpacing.lg),
        Text(
          title,
          style: AppTextStyles.titleMedium.copyWith(
            color: NuvoColors.navy,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: NuvoSpacing.xs),
        Text(
          subtitle,
          style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: NuvoSpacing.lg),
          NuvoPrimaryButton(
            label: actionLabel!,
            small: true,
            onPressed: onAction,
          ),
        ],
      ],
    );
  }
}

// ── Empty state (all segments empty) ──────────────────────────────────────────

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
            borderRadius: BorderRadius.circular(NuvoRadii.card),
          ),
          child: const Icon(
            Icons.directions_run_rounded,
            color: NuvoColors.blue,
            size: 24,
          ),
        ),
        const SizedBox(height: NuvoSpacing.xl),
        Text('No active races yet.', style: AppTextStyles.titleLarge),
        const SizedBox(height: 6),
        Text(
          'Start a race to begin logging moves.',
          style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
        ),
        const SizedBox(height: NuvoSpacing.xl),
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

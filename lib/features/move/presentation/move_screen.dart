import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_geometry.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/bottom_nav.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_empty_state.dart';
import '../../../core/widgets/nuvo_error_state.dart';
import '../../../core/widgets/nuvo_loading_indicator.dart';
import '../../../core/widgets/nuvo_motion.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../races/data/race_models.dart';
import '../../races/domain/motion_activity.dart';
import '../../races/domain/race_display.dart';
import '../../races/presentation/ai_motion_proof_entry.dart';
import '../../races/presentation/race_controller.dart';

/// Verify — do the move, live.
///
/// Verification happens AS the person does the move: it is not an approval
/// queue and not a dashboard. The screen opens on the READY moment — one race
/// already chosen (the one Arena pointed at via `?race=`, else the active race
/// closest to its finish line), the move in plain words, one big Start. The
/// other active races are small chips. History lives on Compete and Race
/// Detail, never here.
///
/// Start routes by the race's canonical proof capability through
/// [openAiMotionProof]: camera races go straight to the live verifier, every
/// other race to the proof screen (`/race/:id/proof`).
class MoveScreen extends ConsumerStatefulWidget {
  const MoveScreen({super.key, this.preselectedRaceId});

  /// The race Arena (or any deep link) wants Verify to open on.
  final String? preselectedRaceId;

  @override
  ConsumerState<MoveScreen> createState() => _MoveScreenState();
}

class _MoveScreenState extends ConsumerState<MoveScreen> {
  /// A chip the person tapped. Wins over the preselected / default pick.
  String? _chosenId;

  @override
  void didUpdateWidget(MoveScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Arena pointed at a different race while this tab stayed mounted.
    if (widget.preselectedRaceId != oldWidget.preselectedRaceId) {
      _chosenId = null;
    }
  }

  /// Active races, closest to the finish line first. A race where the goal is
  /// already reached trails the ones that still need proof. Decorated-index
  /// sort keeps the server's order on ties.
  List<Race> _activeRaces(List<Race> races, String? userId) {
    final active = races.where((r) => r.status == 'active').toList();
    final sorted = active.indexed.toList()
      ..sort((a, b) {
        var pa = _remainingToGoal(a.$2, userId);
        var pb = _remainingToGoal(b.$2, userId);
        if (pa <= 0) pa = 1 << 21;
        if (pb <= 0) pb = 1 << 21;
        return pa != pb ? pa.compareTo(pb) : a.$1.compareTo(b.$1);
      });
    return [for (final e in sorted) e.$2];
  }

  Race _pick(List<Race> active) {
    for (final id in [_chosenId, widget.preselectedRaceId]) {
      if (id == null) continue;
      for (final r in active) {
        if (r.id == id) return r;
      }
    }
    return active.first;
  }

  void _start(Race race) {
    openAiMotionProof(
      context,
      ref,
      race,
      routeAction: 'verify_start',
      fromPreview: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final raceState = ref.watch(raceControllerProvider);
    final userId = ref.watch(authControllerProvider).user?.id;
    final active = _activeRaces(raceState.races, userId);
    final bottom = NuvoBottomNav.bottomPadding(context);

    Widget body;
    if (active.isEmpty && raceState.loading) {
      body = const Center(child: NuvoLoadingIndicator());
    } else if (active.isEmpty && raceState.error != null) {
      body = Padding(
        padding: EdgeInsets.fromLTRB(22, 0, 22, bottom),
        child: NuvoErrorState(
          message: "Couldn't load your races.",
          onRetry: () => ref.read(raceControllerProvider.notifier).loadRaces(),
        ),
      );
    } else if (active.isEmpty) {
      body = Padding(
        padding: EdgeInsets.fromLTRB(22, 0, 22, bottom),
        child: NuvoEmptyState(
          icon: Icons.flag_outlined,
          title: 'Start a race first.',
          body: 'Verify opens once you have a live race.',
          ctaLabel: 'Go to Compete',
          onCta: () => context.go('/compete'),
        ),
      );
    } else {
      final race = _pick(active);
      body = _ReadyMoment(
        race: race,
        userId: userId,
        others: [if (active.length > 1) ...active],
        onPick: (r) => setState(() => _chosenId = r.id),
        onStart: () => _start(race),
        bottomPadding: bottom,
      );
    }

    return Scaffold(
      backgroundColor: context.themeColors.page,
      // bottom:false — the shell's own SafeArea + nav already account for the
      // bottom inset (see MainShell's doc-comment).
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 32, 22, NuvoSpacing.lg),
              child: _VerifyHeader(),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

/// Distance to the finish line — the canonical `viewerContext.goalRemaining`
/// when the server sends it, else `target − progress`. Races without a
/// measurable goal sort last.
int _remainingToGoal(Race race, String? userId) {
  final vc = race.viewerContext;
  if (vc?.goalRemaining != null) return vc!.goalRemaining!;
  final myPart = userId != null ? race.participantFor(userId) : null;
  final target = race.targetValue;
  if (target != null && target > 0 && myPart != null) {
    return (target - myPart.progressValue).clamp(0, target);
  }
  return 1 << 20;
}

class _VerifyHeader extends StatelessWidget {
  const _VerifyHeader();

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Verify', style: AppTextStyles.screenTitle),
        const SizedBox(height: NuvoSpacing.xs),
        Text(
          'Make your move.',
          style: AppTextStyles.bodySmall.copyWith(
            color: c.inkMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ── Ready moment ─────────────────────────────────────────────────────────────

class _ReadyMoment extends StatelessWidget {
  const _ReadyMoment({
    required this.race,
    required this.userId,
    required this.others,
    required this.onPick,
    required this.onStart,
    required this.bottomPadding,
  });

  final Race race;
  final String? userId;

  /// Every active race (chips shown when there is more than one).
  final List<Race> others;
  final ValueChanged<Race> onPick;
  final VoidCallback onStart;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final cta = raceProofCta(race);
    final isCamera = raceProofAction(race) == RaceProofAction.motion;
    final strip = _contextStrip(race, userId);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(22, 0, 22, bottomPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            race.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.labelMedium.copyWith(
              color: c.inkMuted,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: NuvoSpacing.sm),
          Text(
            _moveSentence(race),
            key: const ValueKey('verify-move'),
            style: AppTextStyles.headlineMedium.copyWith(color: c.ink),
          ),
          const SizedBox(height: NuvoSpacing.sm),
          Text(
            isCamera
                ? 'Prop your phone about 6 feet away, full body in the frame.'
                : 'Finish the move, then add your result.',
            style: AppTextStyles.bodyMedium.copyWith(color: c.inkMuted),
          ),
          if (strip != null) ...[
            const SizedBox(height: NuvoSpacing.lg),
            Container(
              key: const ValueKey('verify-context'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: c.panelLight,
                borderRadius: BorderRadius.circular(NuvoRadii.md),
              ),
              child: Text(
                strip,
                style: AppTextStyles.labelMedium.copyWith(
                  color: c.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          const SizedBox(height: NuvoSpacing.xl),
          NuvoPrimaryButton(
            key: const Key('verify-hero-cta'),
            label: isCamera ? 'Start' : cta.label,
            icon: cta.icon,
            expand: true,
            onPressed: onStart,
          ),
          if (others.length > 1) ...[
            const SizedBox(height: NuvoSpacing.xl),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final r in others) ...[
                    _RaceChip(
                      race: r,
                      selected: r.id == race.id,
                      onTap: () => onPick(r),
                    ),
                    const SizedBox(width: NuvoSpacing.sm),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RaceChip extends StatelessWidget {
  const _RaceChip({
    required this.race,
    required this.selected,
    required this.onTap,
  });

  final Race race;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    return Semantics(
      button: true,
      selected: selected,
      label: race.title,
      child: NuvoPressable(
        onTap: onTap,
        haptic: false,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 200, minHeight: 40),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? NuvoColors.blue : c.surface,
            borderRadius: BorderRadius.circular(NuvoRadii.pill),
            border: Border.all(
              color: selected ? NuvoColors.blue : c.border,
              width: 1.5,
            ),
          ),
          child: Text(
            race.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.labelMedium.copyWith(
              color: selected ? Colors.white : c.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Plain-words helpers ──────────────────────────────────────────────────────

String _firstName(String displayName) {
  final parts = displayName.trim().split(RegExp(r'\s+'));
  return parts.isEmpty ? 'Racer' : parts.first;
}

/// Compact target text — timed races read "2:00", everything else uses the
/// canonical target label.
String _targetText(Race race) {
  final target = race.targetValue ?? 0;
  return raceMetric(race) == RaceMetric.seconds
      ? formatClock(target)
      : raceTargetLabel(race);
}

/// The move in plain words — how this race is won, canonical.
String _moveSentence(Race race) {
  final target = race.targetValue;
  final hasTarget = target != null && target > 0;
  if (race.format == 'first_to_goal' || race.format == 'most_in_window') {
    return hasTarget
        ? 'First to ${_targetText(race)}'
        : 'Most ${raceDisplayUnit(race)} wins';
  }
  if (race.format == 'timed_attempt') {
    return hasTarget ? 'Beat ${_targetText(race)}' : 'Best time wins';
  }
  return race.scoreDirection == 'lower'
      ? 'Lowest score wins'
      : 'Highest score wins';
}

/// Compact score text — percent races carry their glyph, a value of 1 never
/// reads "1 reps".
String _scoreText(Race race, int value) {
  if (raceDisplayUnit(race) == 'percent') return '$value%';
  final label = raceScoreLabel(race, value);
  if (value == 1 && label.endsWith('s')) {
    return label.substring(0, label.length - 1);
  }
  return label;
}

/// One thin line: my place, what's left, and who is out front. Null when
/// there is nothing to say yet (no result, no goal, no rival).
String? _contextStrip(Race race, String? userId) {
  final me = userId != null ? race.participantFor(userId) : null;
  final myValue = me?.progressValue ?? 0;
  final rank = rankForUser(race, userId);
  final others = race.participants.where((p) => p.userId != userId).toList()
    ..sort((a, b) {
      final ar = a.rank;
      final br = b.rank;
      if (ar != null && br != null) return ar.compareTo(br);
      if (ar != null) return -1;
      if (br != null) return 1;
      return race.scoreDirection == 'lower'
          ? a.progressValue.compareTo(b.progressValue)
          : b.progressValue.compareTo(a.progressValue);
    });
  final leader = others.isEmpty ? null : others.first;

  final parts = <String>[];
  if (myValue > 0) {
    parts.add(
      rank == null
          ? _scoreText(race, myValue)
          : '${raceOrdinal(rank)} · ${_scoreText(race, myValue)}',
    );
  }
  final remaining = _remainingToGoal(race, userId);
  if ((race.targetValue ?? 0) > 0 && remaining > 0 && remaining < 1 << 20) {
    parts.add('${_scoreText(race, remaining)} to go');
  } else if ((race.targetValue ?? 0) > 0 && myValue > 0 && remaining <= 0) {
    parts.add('Goal reached');
  }
  if (leader != null && leader.progressValue > 0 && rank != 1) {
    parts.add(
      '${_firstName(leader.displayName)} '
      '${_scoreText(race, leader.progressValue)}',
    );
  } else if (leader != null && rank == 1 && myValue > 0) {
    parts.add("You're in front");
  }
  return parts.isEmpty ? null : parts.join(' · ');
}

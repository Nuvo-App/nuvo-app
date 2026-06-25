import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_avatar.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../races/data/race_models.dart';
import '../../races/presentation/race_controller.dart';

// ── Action Dock ───────────────────────────────────────────────────────────────
// Two dominant choices: START (begin a race attempt) and BUILD (create a race).
// Race picker appears only after the user taps START with 2+ active races.

class MoveScreen extends ConsumerStatefulWidget {
  const MoveScreen({super.key});

  @override
  ConsumerState<MoveScreen> createState() => _MoveScreenState();
}

class _MoveScreenState extends ConsumerState<MoveScreen> {
  bool _showPicker = false;

  @override
  Widget build(BuildContext context) {
    final raceState = ref.watch(raceControllerProvider);
    final user = ref.watch(authControllerProvider).user;
    final uid = user?.id;

    final activeRaces =
        raceState.races.where((r) => r.status == 'active').toList();

    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 100),
          children: [
            // ── Header ───────────────────────────────────────────────────
            Text(
              'NUVO',
              style: AppTextStyles.brandLabel.copyWith(
                color: NuvoColors.navy,
                fontSize: 13,
                letterSpacing: 3.0,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Start or build.',
              style: AppTextStyles.headlineLarge,
            ),
            const SizedBox(height: 32),

            if (raceState.loading && activeRaces.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else ...[
              // ── START ────────────────────────────────────────────────
              _DockAction(
                label: 'START',
                description: 'Choose a race and begin the next one.',
                isPrimary: true,
                onTap: () => _handleStart(context, activeRaces, uid, ref),
              ),

              // ── Race picker — only after tapping START ────────────────
              if (_showPicker && activeRaces.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'PICK A RACE',
                  style: AppTextStyles.brandLabel.copyWith(
                    color: NuvoColors.muted,
                  ),
                ),
                const SizedBox(height: 10),
                for (final race in activeRaces) ...[
                  _PickerRaceRow(
                    race: race,
                    userId: uid,
                    onTap: () {
                      setState(() => _showPicker = false);
                      context
                          .push('/race/${race.id}/proof')
                          .then((_) {
                            ref
                                .read(raceControllerProvider.notifier)
                                .loadRaces();
                          });
                    },
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 8),
              ],

              const SizedBox(height: 14),

              // ── BUILD ─────────────────────────────────────────────────
              _DockAction(
                label: 'BUILD',
                description: 'Create a race, set the unit, invite your crew.',
                isPrimary: false,
                onTap: () => context.push('/races/new'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _handleStart(
    BuildContext context,
    List<Race> activeRaces,
    String? uid,
    WidgetRef ref,
  ) {
    if (activeRaces.isEmpty) {
      context.push('/races/new');
      return;
    }
    if (activeRaces.length == 1) {
      context.push('/race/${activeRaces.first.id}/proof').then((_) {
        ref.read(raceControllerProvider.notifier).loadRaces();
      });
      return;
    }
    // Multiple races — reveal the inline picker
    setState(() => _showPicker = !_showPicker);
  }
}

// ── Dock action block ─────────────────────────────────────────────────────────
// Large pressable choice — primary (navy fill) or secondary (panel).

class _DockAction extends StatelessWidget {
  const _DockAction({
    required this.label,
    required this.description,
    required this.onTap,
    this.isPrimary = false,
  });

  final String label;
  final String description;
  final VoidCallback onTap;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final bg = isPrimary ? NuvoColors.navy : NuvoColors.panel;
    final labelColor = isPrimary ? NuvoColors.white : NuvoColors.navy;
    final descColor = isPrimary
        ? NuvoColors.white.withValues(alpha: 0.55)
        : NuvoColors.muted;

    return PressableScale(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: isPrimary ? null : Border.all(color: NuvoColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AppTextStyles.headlineMedium.copyWith(
                color: labelColor,
                letterSpacing: isPrimary ? 0.5 : 0,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              description,
              style: AppTextStyles.bodySmall.copyWith(color: descColor),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Race picker row ───────────────────────────────────────────────────────────
// Compact lane row shown inside the picker after tapping START.

class _PickerRaceRow extends StatelessWidget {
  const _PickerRaceRow({
    required this.race,
    required this.onTap,
    this.userId,
  });

  final Race race;
  final String? userId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final myPart = userId != null ? race.participantFor(userId!) : null;
    final val = myPart?.progressValue ?? 0;
    final unit = race.unit ?? race.targetUnit ?? 'reps';
    final pct = myPart?.progressPercent ?? 0;

    final others = race.participants
        .where((p) => p.userId != userId)
        .take(3)
        .toList();

    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: NuvoColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: NuvoColors.divider),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    race.displayTitle,
                    style: AppTextStyles.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    myPart != null ? '$val $unit logged' : 'Not started',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: NuvoColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (others.isNotEmpty)
              NuvoAvatarStack(
                avatars: others
                    .map((p) => (
                          initials: p.displayName.isNotEmpty
                              ? p.displayName[0].toUpperCase()
                              : '?',
                          photoUrl: p.profilePhotoUrl,
                        ))
                    .toList(),
                total: race.participantCount,
                size: 20,
                max: 3,
              ),
            const SizedBox(width: 10),
            Text(
              '$pct%',
              style: AppTextStyles.labelMedium.copyWith(
                color: pct >= 100 ? NuvoColors.success : NuvoColors.muted,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.arrow_forward_rounded,
              size: 14,
              color: NuvoColors.blue,
            ),
          ],
        ),
      ),
    );
  }
}

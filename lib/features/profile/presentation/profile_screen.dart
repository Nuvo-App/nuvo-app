import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_empty_state.dart';
import '../../../core/widgets/nuvo_error_state.dart';
import '../../../core/widgets/nuvo_shared_components.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../races/presentation/race_controller.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final displayName = user?.fullName ?? user?.email ?? '—';
    final username = user?.username != null ? '@${user!.username}' : '—';
    final initials = user?.avatarInitials ?? '?';
    final uid = user?.id;

    final raceState = ref.watch(raceControllerProvider);
    final activeRaceCount = raceState.races
        .where((race) => race.status == 'active')
        .length;
    final finishedRaceCount = raceState.races
        .where((race) => race.status != 'active')
        .length;
    final proofCount = raceState.races.fold<int>(
      0,
      (sum, race) => sum + race.recentProofs.length,
    );
    final progressValues = raceState.races
        .expand((race) => race.participants)
        .map((participant) => participant.progressPercent)
        .toList();
    final averageProgress = progressValues.isEmpty
        ? 0
        : (progressValues.fold<int>(0, (sum, value) => sum + value) /
                  progressValues.length)
              .round();
    final raceLoadFailed = raceState.error != null && raceState.races.isEmpty;

    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        children: [
          // ── Identity block ─────────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: const BoxDecoration(
                  color: NuvoColors.navy,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  initials,
                  style: AppTextStyles.titleLarge.copyWith(
                    color: NuvoColors.white,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayName, style: AppTextStyles.headlineMedium),
                    Text(
                      username.toLowerCase(),
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: NuvoColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              PressableScale(
                onTap: () => context.push('/profile/edit'),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: NuvoColors.icyBlue,
                    shape: BoxShape.circle,
                    border: Border.all(color: NuvoColors.border),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1207152B),
                        blurRadius: 0,
                        offset: Offset(2, 3),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.edit_rounded,
                    color: NuvoColors.navy,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 22),

          // ── Stats board ────────────────────────────────────────────────────
          if (raceState.loading && raceState.races.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: CircularProgressIndicator(),
              ),
            )
          else if (raceState.error != null && raceState.races.isEmpty)
            NuvoErrorState(
              message: raceState.error!,
              onRetry: () =>
                  ref.read(raceControllerProvider.notifier).loadRaces(),
            )
          else
            _StatsBoard(
              activeRaceCount: activeRaceCount,
              finishedRaceCount: finishedRaceCount,
              proofCount: proofCount,
              averageProgress: averageProgress,
            ),

          const SizedBox(height: 24),

          // ── Races ──────────────────────────────────────────────────────────
          const NuvoSectionHeader(title: 'Races', bottomPadding: 10),
          if (raceLoadFailed)
            const _RaceHistoryLoadError()
          else if (raceState.races.isEmpty)
            const NuvoEmptyState(
              icon: Icons.flag_rounded,
              title:
                  'Your race history will appear here once you start competing.',
              body: 'Create a race and submit proof to build real stats.',
            )
          else
            for (final race in raceState.races.take(5)) ...[
              NuvoDenseRaceRow(
                title: race.title,
                subtitle: race.status != 'active'
                    ? _statusLabel(race.status)
                    : null,
                onTap: () => context.push('/race/${race.id}'),
                isComplete: race.status != 'active',
                isAiMotion: race.isSupportedAiMotionRace,
                progressPercent: uid == null
                    ? null
                    : race.participantFor(uid)?.progressPercent,
              ),
              const SizedBox(height: 8),
            ],

          const SizedBox(height: 24),

          // ── Account ────────────────────────────────────────────────────────
          const NuvoSectionHeader(title: 'Account', bottomPadding: 10),
          NuvoActionTile(
            icon: Icons.badge_rounded,
            title: 'Member pass',
            subtitle: 'Share your identity',
            iconColor: NuvoColors.blue,
            iconBg: NuvoColors.icyBlue,
            onTap: () => context.go('/pass'),
          ),
          const SizedBox(height: 8),
          NuvoActionTile(
            icon: Icons.edit_rounded,
            title: 'Edit profile',
            iconColor: NuvoColors.blue,
            iconBg: NuvoColors.icyBlue,
            onTap: () => context.push('/profile/edit'),
          ),
          const SizedBox(height: 8),
          NuvoActionTile(
            icon: Icons.notifications_rounded,
            title: 'Notifications',
            iconColor: NuvoColors.blue,
            iconBg: NuvoColors.icyBlue,
            onTap: () => _showNotificationsSheet(context),
          ),
          const SizedBox(height: 8),
          NuvoActionTile(
            icon: Icons.logout_rounded,
            title: 'Sign out',
            iconColor: const Color(0xFFE5484D),
            iconBg: const Color(0xFFFFEEF1),
            onTap: () async {
              await ref.read(authControllerProvider.notifier).logout();
            },
          ),
        ],
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _statusLabel(String status) => switch (status) {
  'completed' || 'complete' || 'finished' => 'Finished',
  'archived' => 'Archived',
  'cancelled' => 'Cancelled',
  _ => status.replaceAll('_', ' '),
};

// ── Stats board ───────────────────────────────────────────────────────────────

class _StatsBoard extends StatelessWidget {
  const _StatsBoard({
    required this.activeRaceCount,
    required this.finishedRaceCount,
    required this.proofCount,
    required this.averageProgress,
  });

  final int activeRaceCount;
  final int finishedRaceCount;
  final int proofCount;
  final int averageProgress;

  @override
  Widget build(BuildContext context) {
    return Container(
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
        children: [
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _StatCell(
                    value: '$activeRaceCount',
                    label: 'Active races',
                  ),
                ),
                const VerticalDivider(
                  width: 1,
                  thickness: 0.5,
                  color: NuvoColors.border,
                ),
                Expanded(
                  child: _StatCell(
                    value: '$finishedRaceCount',
                    label: 'Finished races',
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 0.5, color: NuvoColors.border),
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _StatCell(value: '$proofCount', label: 'Proofs'),
                ),
                const VerticalDivider(
                  width: 1,
                  thickness: 0.5,
                  color: NuvoColors.border,
                ),
                Expanded(
                  child: _StatCell(
                    value: '$averageProgress%',
                    label: 'Avg progress',
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

class _StatCell extends StatelessWidget {
  const _StatCell({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: AppTextStyles.headlineMedium.copyWith(
              color: NuvoColors.blue,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Error state ───────────────────────────────────────────────────────────────

class _RaceHistoryLoadError extends StatelessWidget {
  const _RaceHistoryLoadError();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NuvoColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NuvoColors.border),
      ),
      child: Text(
        'Race history could not load. Use Try again above to refresh your real stats.',
        style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
      ),
    );
  }
}

// ── Sheets ────────────────────────────────────────────────────────────────────

void _showNotificationsSheet(BuildContext context) {
  _showComingSoonSheet(
    context,
    'No race updates yet.',
    'When your crew joins, submits proof, or crosses the finish line, updates will appear here.',
  );
}

void _showComingSoonSheet(BuildContext context, String title, String body) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: NuvoColors.page,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: NuvoColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            const Icon(
              Icons.notifications_none_rounded,
              color: NuvoColors.blue,
              size: 44,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: AppTextStyles.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
  );
}

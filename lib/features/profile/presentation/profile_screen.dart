import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_empty_state.dart';
import '../../../core/widgets/nuvo_error_state.dart';
import '../../../core/widgets/nuvo_shared_components.dart';
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
          // ── Profile header ────────────────────────────────────────────────
          Row(
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
            ],
          ),

          const SizedBox(height: 20),

          // ── Stats 2×2 grid ────────────────────────────────────────────────
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
            GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 2.1,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                NuvoStatTile(value: '$activeRaceCount', label: 'Active races'),
                NuvoStatTile(
                  value: '$finishedRaceCount',
                  label: 'Finished races',
                ),
                NuvoStatTile(value: '$proofCount', label: 'Proofs submitted'),
                NuvoStatTile(
                  value: '$averageProgress%',
                  label: 'Average progress',
                ),
              ],
            ),

          const SizedBox(height: 22),

          // ── Race history ──────────────────────────────────────────────────
          const NuvoSectionHeader(title: 'Race history', bottomPadding: 10),
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
            for (final race in raceState.races.take(3)) ...[
              _RaceHistoryRow(title: race.title, status: race.status),
              const SizedBox(height: 8),
            ],

          const SizedBox(height: 22),

          // ── Settings ──────────────────────────────────────────────────────
          const NuvoSectionHeader(title: 'Settings', bottomPadding: 10),
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

class _RaceHistoryRow extends StatelessWidget {
  const _RaceHistoryRow({required this.title, required this.status});

  final String title;
  final String status;

  @override
  Widget build(BuildContext context) {
    final isActive = status == 'active';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: NuvoColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NuvoColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C07152B),
            blurRadius: 0,
            offset: Offset(2, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: isActive ? NuvoColors.icyBlue : NuvoColors.softBlue,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.flag_rounded,
              color: NuvoColors.blue,
              size: 17,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: AppTextStyles.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          NuvoPill(
            label: status,
            color: isActive ? NuvoColors.blue : NuvoColors.muted,
          ),
        ],
      ),
    );
  }
}

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

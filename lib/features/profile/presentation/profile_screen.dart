import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_empty_state.dart';
import '../../../core/widgets/nuvo_error_state.dart';
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
          Row(
            children: [
              CircleAvatar(
                radius: 34,
                backgroundColor: NuvoColors.navy,
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
          const SizedBox(height: 24),
          if (raceState.loading && raceState.races.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
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
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.55,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _StatTile(value: '$activeRaceCount', label: 'Active races'),
                _StatTile(value: '$finishedRaceCount', label: 'Finished races'),
                _StatTile(value: '$proofCount', label: 'Proofs submitted'),
                _StatTile(
                  value: '$averageProgress%',
                  label: 'Average progress',
                ),
              ],
            ),
          const SizedBox(height: 26),
          Text('Race history', style: AppTextStyles.titleLarge),
          const SizedBox(height: 12),
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
              const SizedBox(height: 10),
            ],
          const SizedBox(height: 26),
          Text('Settings', style: AppTextStyles.titleLarge),
          const SizedBox(height: 12),
          _SettingsRow(
            icon: Icons.edit_rounded,
            label: 'Edit profile',
            onTap: () => context.push('/profile/edit'),
          ),
          _SettingsRow(
            icon: Icons.notifications_rounded,
            label: 'Notifications',
            onTap: () => _showNotificationsSheet(context),
          ),
          _SettingsRow(
            icon: Icons.lock_rounded,
            label: 'Privacy',
            onTap: () => _showComingSoonSheet(
              context,
              'Privacy settings are coming soon.',
              'Your profile details are controlled by the backend profile settings already active in Nuvo.',
            ),
          ),
          _SettingsRow(
            icon: Icons.logout_rounded,
            label: 'Sign out',
            onTap: () async {
              await ref.read(authControllerProvider.notifier).logout();
              // Router guard redirects to /welcome after state updates.
            },
          ),
          const SizedBox(height: 28),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NuvoColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: NuvoColors.border),
      ),
      child: Text(
        'Race history could not load. Use Try again above to refresh your real stats.',
        style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NuvoColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: NuvoColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: AppTextStyles.headlineMedium.copyWith(
              color: NuvoColors.blue,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
          ),
        ],
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
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: NuvoColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: NuvoColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.flag_rounded, color: NuvoColors.blue),
          const SizedBox(width: 12),
          Expanded(child: Text(title, style: AppTextStyles.titleMedium)),
          Text(
            status,
            style: AppTextStyles.labelSmall.copyWith(color: NuvoColors.muted),
          ),
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: NuvoColors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: NuvoColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, color: NuvoColors.blue),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: AppTextStyles.bodyMedium)),
            if (onTap != null)
              const Icon(Icons.chevron_right_rounded, color: NuvoColors.muted),
          ],
        ),
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

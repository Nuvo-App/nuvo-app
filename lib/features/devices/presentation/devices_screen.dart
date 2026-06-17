import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/glass_container.dart';

class DevicesScreen extends StatelessWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/profile'),
        ),
        title: const Text('Connected Devices'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Text(
            'Connected With The\nDevices You Already Use.',
            style: AppTextStyles.headlineLarge,
          ),
          const SizedBox(height: 10),
          Text(
            'Physical performance meets digital competition. Your wearables, your data, your proof.',
            style: AppTextStyles.bodyMedium,
          ),
          const SizedBox(height: 32),
          const _DeviceCard(
            icon: Icons.watch_rounded,
            name: 'Apple Watch',
            description:
                'Sync workouts, heart rate, and activity rings directly to your challenges.',
            comingSoon: true,
            gradient: AppGradients.brand,
          ),
          const SizedBox(height: 16),
          const _DeviceCard(
            icon: Icons.directions_run_rounded,
            name: 'Garmin',
            description:
                'Import GPS runs, swimming, and endurance data for verified performance challenges.',
            comingSoon: true,
            gradient: AppGradients.victory,
          ),
          const SizedBox(height: 16),
          const _DeviceCard(
            icon: Icons.favorite_rounded,
            name: 'Fitbit',
            description:
                'Step counts, sleep data, and daily activity logs verified on-chain.',
            comingSoon: true,
            gradient: AppGradients.hot,
          ),
          const SizedBox(height: 16),
          const _DeviceCard(
            icon: Icons.monitor_heart_rounded,
            name: 'WHOOP',
            description:
                'Recovery scores and strain data for elite-level performance tracking.',
            comingSoon: true,
            gradient: AppGradients.brand,
          ),
          const SizedBox(height: 16),
          const _DeviceCard(
            icon: Icons.camera_rounded,
            name: 'Camera AI Verification',
            description:
                'Rep counting, form analysis, and time-stamped proof via your smartphone camera.',
            comingSoon: false,
            gradient: AppGradients.victory,
          ),
          const SizedBox(height: 32),
          GlassContainer(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.security_rounded,
                    color: AppColors.electricBlue, size: 28),
                const SizedBox(height: 12),
                Text(
                  'Tamper-Proof Verification',
                  style: AppTextStyles.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Device data is cryptographically signed at the source. No screenshots. No edits. Nuvo proves it.',
                  style: AppTextStyles.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.icon,
    required this.name,
    required this.description,
    required this.comingSoon,
    required this.gradient,
  });

  final IconData icon;
  final String name;
  final String description;
  final bool comingSoon;
  final LinearGradient gradient;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: Colors.black87, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(name, style: AppTextStyles.titleLarge),
                    const Spacer(),
                    if (comingSoon)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(
                          'Soon',
                          style: AppTextStyles.labelSmall,
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          gradient: AppGradients.victory,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Live',
                          style: AppTextStyles.labelSmall
                              .copyWith(color: Colors.black87),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(description, style: AppTextStyles.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

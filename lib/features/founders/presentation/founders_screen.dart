import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/glass_container.dart';

class FoundersScreen extends StatelessWidget {
  const FoundersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/profile'),
        ),
        title: const Text('The Team'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Text(
            'Built by competitors,\nfor competitors.',
            style: AppTextStyles.headlineLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'We built Nuvo because we needed it. Three founders who compete on everything.',
            style: AppTextStyles.bodyMedium,
          ),
          const SizedBox(height: 32),
          const _FounderCard(
            initials: 'AD',
            name: 'Akaash Deepak',
            role: 'CEO',
            bio:
                'Visionary builder. Obsessed with the intersection of competition and self-improvement. Former athlete turned founder.',
            linkedInLabel: 'akaashdeepak',
            instagramLabel: '@akaash',
          ),
          const SizedBox(height: 20),
          const _FounderCard(
            initials: 'SK',
            name: 'Shivmanas Kamarasu',
            role: 'CTO',
            bio:
                'Full-stack engineer and systems thinker. Shipped production apps at scale. Builds fast, ships faster.',
            linkedInLabel: 'shivmanas',
            instagramLabel: '@shivmanas',
          ),
          const SizedBox(height: 20),
          const _FounderCard(
            initials: 'SS',
            name: 'Shaurya Shinde',
            role: 'CFO',
            bio:
                'Finance background, growth mindset. Keeps the machine running. Wins at everything he touches — including spreadsheets.',
            linkedInLabel: 'shauryashinde',
            instagramLabel: '@shaurya',
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppGradients.brand,
              borderRadius: BorderRadius.circular(20),
              boxShadow: AppShadows.brandGlow(intensity: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Join the mission.',
                  style: AppTextStyles.headlineMedium
                      .copyWith(color: Colors.black87),
                ),
                const SizedBox(height: 8),
                Text(
                  'We\'re building the future of competitive self-improvement. If that excites you, reach out.',
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: Colors.black54),
                ),
                const SizedBox(height: 16),
                Text(
                  'joinnuvo@gmail.com',
                  style: AppTextStyles.titleLarge
                      .copyWith(color: Colors.black87),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FounderCard extends StatelessWidget {
  const _FounderCard({
    required this.initials,
    required this.name,
    required this.role,
    required this.bio,
    required this.linkedInLabel,
    required this.instagramLabel,
  });

  final String initials;
  final String name;
  final String role;
  final String bio;
  final String linkedInLabel;
  final String instagramLabel;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppGradients.brand,
                ),
                alignment: Alignment.center,
                child: Text(
                  initials,
                  style: AppTextStyles.headlineMedium
                      .copyWith(color: Colors.black87),
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: AppTextStyles.titleLarge),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: AppGradients.brand,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      role,
                      style: AppTextStyles.labelSmall
                          .copyWith(color: Colors.black87),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(bio, style: AppTextStyles.bodyMedium),
          const SizedBox(height: 16),
          Row(
            children: [
              _SocialButton(
                icon: Icons.work_outline_rounded,
                label: 'LinkedIn',
                onTap: () {},
              ),
              const SizedBox(width: 10),
              _SocialButton(
                icon: Icons.camera_alt_outlined,
                label: 'Instagram',
                onTap: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppColors.electricBlue),
            const SizedBox(width: 6),
            Text(label, style: AppTextStyles.labelMedium),
          ],
        ),
      ),
    );
  }
}

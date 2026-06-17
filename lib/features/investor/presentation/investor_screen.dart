import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/glass_container.dart';
import '../../../core/widgets/gradient_button.dart';

class InvestorScreen extends StatelessWidget {
  const InvestorScreen({super.key});

  static const _email = 'joinnuvo@gmail.com';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/profile'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 60),
        children: [
          const SizedBox(height: 16),
          ShaderMask(
            shaderCallback: (bounds) =>
                AppGradients.brand.createShader(bounds),
            child: Text(
              'Building The Future\nOf Competitive\nSelf Improvement.',
              style: AppTextStyles.displayMedium
                  .copyWith(color: Colors.white, height: 1.15),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Nuvo is turning personal growth into the world\'s most competitive sport. We\'re at the beginning — and we\'re moving fast.',
            style: AppTextStyles.bodyLarge
                .copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 40),
          _MetricRow(),
          const SizedBox(height: 40),
          Text(
            'WHO WE\'RE LOOKING FOR',
            style: AppTextStyles.labelSmall
                .copyWith(letterSpacing: 1.6, color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          const _AudienceChip(
            icon: Icons.trending_up_rounded,
            label: 'Investors',
            detail: 'Early-stage, pre-seed & seed',
          ),
          const SizedBox(height: 10),
          const _AudienceChip(
            icon: Icons.handshake_rounded,
            label: 'Partnerships',
            detail: 'Fitness brands, platforms, apps',
          ),
          const SizedBox(height: 10),
          const _AudienceChip(
            icon: Icons.psychology_rounded,
            label: 'Advisors',
            detail: 'Consumer, sports tech, fintech',
          ),
          const SizedBox(height: 10),
          const _AudienceChip(
            icon: Icons.group_rounded,
            label: 'Collaborators',
            detail: 'Athletes, creators, builders',
          ),
          const SizedBox(height: 40),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: AppGradients.brand,
              borderRadius: BorderRadius.circular(24),
              boxShadow: AppShadows.brandGlow(intensity: 0.6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Let\'s talk.',
                  style: AppTextStyles.headlineLarge
                      .copyWith(color: Colors.black87),
                ),
                const SizedBox(height: 8),
                Text(
                  'We respond to everyone. No pitch deck required for the first conversation.',
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: Colors.black54),
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  onLongPress: () {
                    Clipboard.setData(const ClipboardData(text: _email));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Email copied!')),
                    );
                  },
                  child: Text(
                    _email,
                    style: AppTextStyles.headlineMedium
                        .copyWith(color: Colors.black87),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          GradientButton(
            label: 'Send Email',
            icon: Icons.mail_outline_rounded,
            expand: true,
            onPressed: () async {
              final uri = Uri(
                scheme: 'mailto',
                path: _email,
                query: 'subject=Nuvo — Let\'s Connect',
              );
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri);
              }
            },
          ),
          const SizedBox(height: 32),
          GlassContainer(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Our Thesis', style: AppTextStyles.titleLarge),
                const SizedBox(height: 12),
                const _BulletPoint(
                  'The \$100B+ fitness industry has no competitive layer.'),
                const SizedBox(height: 8),
                const _BulletPoint(
                  'Social accountability is the most powerful behavior change tool — we\'re productizing it.'),
                const SizedBox(height: 8),
                const _BulletPoint(
                  'Gen Z competes. We\'re the platform built for them.'),
                const SizedBox(height: 8),
                const _BulletPoint(
                  'AI verification eliminates the honesty problem.'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(
          child: _MetricCard(label: 'Target Market', value: '\$100B+'),
        ),
        SizedBox(width: 12),
        Expanded(
          child: _MetricCard(label: 'Launch Stage', value: 'V1'),
        ),
        SizedBox(width: 12),
        Expanded(
          child: _MetricCard(label: 'Team', value: '3 Founders'),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      child: Column(
        children: [
          ShaderMask(
            shaderCallback: (b) => AppGradients.brand.createShader(b),
            child: Text(
              value,
              style: AppTextStyles.titleLarge.copyWith(color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppTextStyles.labelSmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _AudienceChip extends StatelessWidget {
  const _AudienceChip({
    required this.icon,
    required this.label,
    required this.detail,
  });

  final IconData icon;
  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppGradients.brand,
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: Colors.black87, size: 20),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTextStyles.titleLarge),
              Text(detail, style: AppTextStyles.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _BulletPoint extends StatelessWidget {
  const _BulletPoint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(top: 6, right: 10),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppGradients.brand,
          ),
        ),
        Expanded(
          child: Text(text, style: AppTextStyles.bodyMedium),
        ),
      ],
    );
  }
}

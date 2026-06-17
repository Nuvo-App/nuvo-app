import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/gradient_button.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: ListView(
            children: [
              const SizedBox(height: 48),
              Text('Set up your\nprofile.', style: AppTextStyles.displayMedium),
              const SizedBox(height: 12),
              Text(
                'Your crew will see this when you challenge them.',
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 48),
              const Center(child: _AvatarPicker()),
              const SizedBox(height: 40),
              Text('NAME', style: _labelStyle),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                style: AppTextStyles.bodyLarge,
                decoration: const InputDecoration(hintText: 'Akaash Deepak'),
              ),
              const SizedBox(height: 24),
              Text('USERNAME', style: _labelStyle),
              const SizedBox(height: 8),
              TextField(
                controller: _usernameController,
                style: AppTextStyles.bodyLarge,
                decoration: const InputDecoration(hintText: '@akaash'),
              ),
              const SizedBox(height: 48),
              GradientButton(
                label: 'Enter the Arena',
                icon: Icons.arrow_forward_rounded,
                expand: true,
                onPressed: () => context.go('/arena'),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  TextStyle get _labelStyle => AppTextStyles.labelSmall.copyWith(
        letterSpacing: 1.6,
        color: AppColors.textMuted,
      );
}

class _AvatarPicker extends StatefulWidget {
  const _AvatarPicker();

  @override
  State<_AvatarPicker> createState() => _AvatarPickerState();
}

class _AvatarPickerState extends State<_AvatarPicker> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {},
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppGradients.brand,
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.person_rounded, size: 48, color: Colors.black54),
          ),
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.background, width: 2),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.camera_alt_rounded,
                size: 16, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

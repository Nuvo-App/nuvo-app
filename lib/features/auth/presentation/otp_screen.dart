import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/otp_input.dart';

class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  late final List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(6, (_) => TextEditingController());
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 44, 20, 28),
          children: [
            Text('Enter your code', style: AppTextStyles.headlineLarge),
            const SizedBox(height: 10),
            Text(
              'We sent a 6-digit code to your phone.',
              style: AppTextStyles.bodyLarge.copyWith(color: NuvoColors.muted),
            ),
            const SizedBox(height: 34),
            OtpInput(controllers: _controllers),
            const SizedBox(height: 28),
            NuvoPrimaryButton(
              label: 'Verify',
              icon: Icons.arrow_forward_rounded,
              expand: true,
              onPressed: () => context.go('/onboarding/profile'),
            ),
            const SizedBox(height: 14),
            const TextButton(onPressed: null, child: Text('Resend code')),
          ],
        ),
      ),
    );
  }
}

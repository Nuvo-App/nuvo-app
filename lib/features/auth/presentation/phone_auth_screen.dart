import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';

class PhoneAuthScreen extends StatefulWidget {
  const PhoneAuthScreen({super.key});

  @override
  State<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends State<PhoneAuthScreen> {
  final _phoneController = TextEditingController();

  @override
  void dispose() {
    _phoneController.dispose();
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
            Text(
              'Create your Nuvo account',
              style: AppTextStyles.headlineLarge,
            ),
            const SizedBox(height: 10),
            Text(
              'We will send a code to verify your number.',
              style: AppTextStyles.bodyLarge.copyWith(color: NuvoColors.muted),
            ),
            const SizedBox(height: 34),
            Text('PHONE NUMBER', style: AppTextStyles.brandLabel),
            const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  height: 58,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: NuvoColors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: NuvoColors.border),
                  ),
                  child: Text('+1', style: AppTextStyles.titleMedium),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    style: AppTextStyles.titleMedium,
                    decoration: const InputDecoration(hintText: '555 014 2048'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            NuvoPrimaryButton(
              label: 'Send code',
              icon: Icons.arrow_forward_rounded,
              expand: true,
              onPressed: () => context.go('/auth/otp'),
            ),
          ],
        ),
      ),
    );
  }
}

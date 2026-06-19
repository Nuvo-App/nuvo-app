import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/otp_input.dart';
import 'auth_controller.dart';

class EmailVerifyScreen extends ConsumerStatefulWidget {
  const EmailVerifyScreen({super.key, required this.email});
  final String email;

  @override
  ConsumerState<EmailVerifyScreen> createState() => _EmailVerifyScreenState();
}

class _EmailVerifyScreenState extends ConsumerState<EmailVerifyScreen> {
  late final List<TextEditingController> _controllers;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(6, (_) => TextEditingController());
    for (final c in _controllers) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  String get _code => _controllers.map((c) => c.text).join();

  bool get _canVerify => _code.length == 6 && !_loading;

  Future<void> _verify() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .verifyEmailCode(widget.email, _code);
      // Router guard takes over navigation once auth state updates.
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Invalid or expired code. Please try again.';
          _loading = false;
          for (final c in _controllers) {
            c.clear();
          }
        });
      }
    }
  }

  Future<void> _resend() async {
    try {
      await ref
          .read(authControllerProvider.notifier)
          .startEmailAuth(widget.email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Code sent!')),
        );
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 44, 20, 28),
          children: [
            GestureDetector(
              onTap: () => safePopOrGo(context, '/auth/email'),
              child: const Icon(Icons.arrow_back_rounded, size: 24),
            ),
            const SizedBox(height: 28),
            Text('Enter your code', style: AppTextStyles.headlineLarge),
            const SizedBox(height: 10),
            Text(
              'We sent a 6-digit code to ${widget.email}.',
              style: AppTextStyles.bodyLarge.copyWith(color: NuvoColors.muted),
            ),
            const SizedBox(height: 34),
            OtpInput(controllers: _controllers),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: AppTextStyles.bodySmall.copyWith(color: Colors.red),
              ),
            ],
            const SizedBox(height: 28),
            NuvoPrimaryButton(
              label: 'Verify',
              icon: Icons.arrow_forward_rounded,
              expand: true,
              loading: _loading,
              onPressed: _canVerify ? _verify : null,
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: _resend,
              child: const Text('Resend code'),
            ),
          ],
        )
            .animate()
            .fadeIn(duration: 280.ms, curve: Curves.easeOut)
            .slideY(begin: 0.04, end: 0, duration: 320.ms, curve: Curves.easeOutCubic),
      ),
    );
  }
}

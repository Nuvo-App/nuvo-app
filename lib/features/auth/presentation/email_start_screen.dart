import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import 'auth_controller.dart';

class EmailStartScreen extends ConsumerStatefulWidget {
  const EmailStartScreen({super.key});

  @override
  ConsumerState<EmailStartScreen> createState() => _EmailStartScreenState();
}

class _EmailStartScreenState extends ConsumerState<EmailStartScreen> {
  final _emailController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _emailController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _emailController.text.trim().contains('@') && !_loading;

  Future<void> _submit() async {
    final email = _emailController.text.trim().toLowerCase();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).startEmailAuth(email);
      if (mounted) context.push('/auth/verify', extra: email);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not send code. Please try again.';
          _loading = false;
        });
      }
    }
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
              onTap: () => safePopOrGo(context, '/welcome'),
              child: const Icon(Icons.arrow_back_rounded, size: 24),
            ),
            const SizedBox(height: 28),
            Text('Sign in with email', style: AppTextStyles.headlineLarge),
            const SizedBox(height: 10),
            Text(
              "We'll send a 6-digit code to verify your address.",
              style: AppTextStyles.bodyLarge.copyWith(color: NuvoColors.muted),
            ),
            const SizedBox(height: 34),
            Text(
              'EMAIL',
              style: AppTextStyles.brandLabel.copyWith(color: NuvoColors.muted),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autocorrect: false,
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) {
                if (_canSubmit) _submit();
              },
              decoration: const InputDecoration(hintText: 'your@email.com'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: AppTextStyles.bodySmall.copyWith(color: Colors.red),
              ),
            ],
            const SizedBox(height: 28),
            NuvoPrimaryButton(
              label: 'Send code',
              icon: Icons.arrow_forward_rounded,
              expand: true,
              loading: _loading,
              onPressed: _canSubmit ? _submit : null,
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

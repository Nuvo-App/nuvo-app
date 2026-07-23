import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_shared_components.dart';
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
      debugPrint('[EmailStart] startEmailAuth failed (${e.runtimeType}): $e');
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Scrollable content ───────────────────────────────────────────
            Expanded(
              child:
                  SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(22, 22, 22, 28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            NuvoBackButton(
                              onPressed: () => safePopOrGo(context, '/welcome'),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'Enter your email',
                              style: AppTextStyles.headlineLarge.copyWith(
                                fontSize: 32,
                                letterSpacing: -0.9,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              "We'll send a sign-in code for your Nuvo race pass.",
                              style: AppTextStyles.bodyLarge.copyWith(
                                color: NuvoColors.muted,
                              ),
                            ),
                            const SizedBox(height: 30),
                            NuvoTextInput(
                              controller: _emailController,
                              label: 'Email',
                              hint: 'your@email.com',
                              keyboardType: TextInputType.emailAddress,
                              onChanged: (_) => setState(() => _error = null),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 10),
                              Text(
                                _error!,
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: NuvoColors.danger,
                                ),
                              ),
                            ],
                          ],
                        ),
                      )
                      .animate()
                      .fadeIn(duration: 280.ms, curve: Curves.easeOut)
                      .slideY(
                        begin: 0.04,
                        end: 0,
                        duration: 320.ms,
                        curve: Curves.easeOutCubic,
                      ),
            ),

            // ── Pinned CTA ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: NuvoPrimaryButton(
                label: 'Send code',
                icon: Icons.arrow_forward_rounded,
                expand: true,
                loading: _loading,
                onPressed: _canSubmit ? _submit : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

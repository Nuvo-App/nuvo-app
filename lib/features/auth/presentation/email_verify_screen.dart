import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/otp_input.dart';
import '../data/auth_api.dart';
import 'auth_controller.dart';

class EmailVerifyScreen extends ConsumerStatefulWidget {
  const EmailVerifyScreen({super.key, required this.email});
  final String email;

  @override
  ConsumerState<EmailVerifyScreen> createState() => _EmailVerifyScreenState();
}

class _EmailVerifyScreenState extends ConsumerState<EmailVerifyScreen> {
  /// Resend cooldown matching the worker's per-email send throttle — the
  /// countdown the reviewer sees ("Resend code in 30s") is the real server
  /// window, so an early tap can never be silently swallowed.
  static const int _resendCooldownSeconds = 30;

  late final List<TextEditingController> _controllers;
  bool _loading = false;
  bool _resending = false;
  String? _error;
  Timer? _resendTimer;
  int _resendCooldownLeft = _resendCooldownSeconds;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(6, (_) => TextEditingController());
    for (final c in _controllers) {
      c.addListener(() => setState(() {}));
    }
    // The screen only exists because a code was just sent — the cooldown
    // starts armed rather than letting a second send fire immediately.
    _startResendCooldown();
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendCooldownLeft = _resendCooldownSeconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCooldownLeft <= 1) {
        timer.cancel();
        setState(() => _resendCooldownLeft = 0);
      } else {
        setState(() => _resendCooldownLeft -= 1);
      }
    });
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
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = isNetworkAuthError(e)
              ? "Can't reach Nuvo. Check your connection and try again."
              : e.statusCode == 401
              ? 'Invalid or expired code. Use the newest code from your email.'
              : e.statusCode >= 500
              ? 'Nuvo hit a snag. Try again.'
              : 'Could not verify your code. Try again.';
          if (!isNetworkAuthError(e)) {
            for (final c in _controllers) {
              c.clear();
            }
          }
        });
      }
    } catch (e) {
      debugPrint('[EmailVerify] finish sign-in failed (${e.runtimeType}): $e');
      if (mounted) {
        setState(() {
          _error = isNetworkAuthError(e)
              ? "Can't reach Nuvo. Check your connection and try again."
              : 'Code accepted, but Nuvo could not finish sign-in. Refresh and try again.';
        });
      }
    } finally {
      // Success navigates away via the route guard; every failure leaves the
      // button usable — and so does a Back that returns to this screen.
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _resend() async {
    if (_resending || _resendCooldownLeft > 0) return;
    setState(() {
      _resending = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .startEmailAuth(widget.email);
      if (mounted) {
        // A fresh code supersedes the one already typed (the worker verifies
        // the newest unused code) — clear the stale digits, not the screen.
        for (final c in _controllers) {
          c.clear();
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('New code sent')));
        _startResendCooldown();
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(
          () => _error = isNetworkAuthError(e)
              ? "Can't reach Nuvo. Check your connection and try again."
              : e.message,
        );
      }
    } catch (e) {
      debugPrint('[EmailVerify] resend failed (${e.runtimeType}): $e');
      if (mounted) {
        setState(() => _error = 'Could not send a new code. Try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _resending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NuvoColors.page,
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
                              onPressed: () =>
                                  safePopOrGo(context, '/auth/email'),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'Check your email',
                              style: AppTextStyles.headlineLarge.copyWith(
                                fontSize: 32,
                                letterSpacing: -0.9,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Enter the 6-digit code we sent to ${widget.email}.',
                              style: AppTextStyles.bodyLarge.copyWith(
                                color: NuvoColors.muted,
                              ),
                            ),
                            const SizedBox(height: 32),
                            OtpInput(controllers: _controllers),
                            if (_error != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                _error!,
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: NuvoColors.danger,
                                ),
                              ),
                            ],
                            const SizedBox(height: 22),
                            Center(
                              child: Text(
                                "Didn't get a code?",
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: NuvoColors.muted,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            GestureDetector(
                              onTap: (_resending || _resendCooldownLeft > 0)
                                  ? null
                                  : _resend,
                              behavior: HitTestBehavior.opaque,
                              child: Center(
                                child: Text(
                                  _resending
                                      ? 'Sending...'
                                      : _resendCooldownLeft > 0
                                      ? 'Resend code in ${_resendCooldownLeft}s'
                                      : 'Resend code',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color:
                                        (_resending || _resendCooldownLeft > 0)
                                        ? NuvoColors.muted
                                        : NuvoColors.blue,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
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
                label: 'Verify code',
                icon: Icons.arrow_forward_rounded,
                expand: true,
                loading: _loading,
                onPressed: _canVerify ? _verify : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

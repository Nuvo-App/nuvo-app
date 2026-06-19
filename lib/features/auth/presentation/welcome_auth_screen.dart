import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/constants/asset_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import 'auth_controller.dart';

enum _AuthMode { signup, login }

final _googleSignIn = GoogleSignIn();

class WelcomeAuthScreen extends ConsumerStatefulWidget {
  const WelcomeAuthScreen({super.key});

  @override
  ConsumerState<WelcomeAuthScreen> createState() => _WelcomeAuthScreenState();
}

class _WelcomeAuthScreenState extends ConsumerState<WelcomeAuthScreen> {
  _AuthMode _mode = _AuthMode.signup;
  bool _googleLoading = false;
  String? _error;

  Future<void> _signInWithGoogle() async {
    setState(() {
      _googleLoading = true;
      _error = null;
    });
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) {
        if (mounted) setState(() => _googleLoading = false);
        return;
      }
      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null) throw Exception('No ID token from Google');
      await ref.read(authControllerProvider.notifier).signInWithGoogle(idToken);
      // Router guard handles navigation once auth state updates.
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Google sign-in failed. Please try again.';
          _googleLoading = false;
        });
      }
    }
  }

  void _toggleMode() {
    setState(() {
      _mode = _mode == _AuthMode.signup ? _AuthMode.login : _AuthMode.signup;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = _mode == _AuthMode.signup
        ? 'Start your\nNuvo race'
        : 'Log in\nto Nuvo';

    final subtitle = _mode == _AuthMode.signup
        ? 'Create your member pass, pull in your crew, and make progress visible.'
        : 'Jump back into your arena and keep your progress moving.';

    final toggleLabel = _mode == _AuthMode.signup
        ? 'Already have an account? Log in'
        : 'New to Nuvo? Create an account';

    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Scrollable top area ──────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
                child:
                    Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Compact brand mark — dark navy container keeps logo correct
                            const _BrandMark(),
                            const SizedBox(height: 32),

                            // Title + subtitle animate when mode switches
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 240),
                              transitionBuilder: (child, animation) =>
                                  FadeTransition(
                                    opacity: animation,
                                    child: SlideTransition(
                                      position: Tween(
                                        begin: const Offset(0, 0.04),
                                        end: Offset.zero,
                                      ).animate(animation),
                                      child: child,
                                    ),
                                  ),
                              child: _TitleBlock(
                                key: ValueKey(_mode),
                                title: title,
                                subtitle: subtitle,
                              ),
                            ),

                            // Race preview only on signup — gives new users context
                            if (_mode == _AuthMode.signup) ...[
                              const SizedBox(height: 24),
                              const _RaceLoopCard(),
                            ],
                          ],
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
            ),

            // ── Pinned bottom CTA — always visible, never clips ─────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) ...[
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: Colors.red,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  NuvoPrimaryButton(
                    label: 'Continue with Google',
                    expand: true,
                    loading: _googleLoading,
                    onPressed: _googleLoading ? null : _signInWithGoogle,
                    leadingWidget: const _GoogleGIcon(),
                  ),
                  const SizedBox(height: 12),

                  NuvoOutlineButton(
                    label: 'Continue with Email',
                    expand: true,
                    onPressed: () => context.push('/auth/email'),
                    leadingWidget: const Icon(
                      Icons.mail_outline_rounded,
                      size: 18,
                      color: NuvoColors.navy,
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Signup ↔ login toggle
                  GestureDetector(
                    onTap: _toggleMode,
                    behavior: HitTestBehavior.opaque,
                    child: Center(
                      child: Text(
                        toggleLabel,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: NuvoColors.blue,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Terms — always in view, never clips
                  Center(
                    child: Text(
                      'By continuing you agree to our Terms & Privacy Policy.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.labelSmall.copyWith(
                        color: NuvoColors.muted.withValues(alpha: 0.65),
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Private helpers ──────────────────────────────────────────────────────────

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // trans.png is white — must stay on dark background
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: NuvoColors.navy,
            borderRadius: BorderRadius.circular(13),
          ),
          padding: const EdgeInsets.all(7),
          child: Image.asset(AssetPaths.nuvoLogo, fit: BoxFit.contain),
        ),
        const SizedBox(width: 10),
        Text('Nuvo', style: AppTextStyles.titleLarge),
      ],
    );
  }
}

class _RaceLoopCard extends StatelessWidget {
  const _RaceLoopCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: NuvoColors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: NuvoColors.navy, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A07152B),
            blurRadius: 18,
            offset: Offset(8, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'START LINE',
            style: AppTextStyles.brandLabel.copyWith(color: NuvoColors.blue),
          ),
          const SizedBox(height: 10),
          Text(
            'Compete on anything. With anyone.',
            style: AppTextStyles.headlineMedium,
          ),
          const SizedBox(height: 10),
          Text(
            'Create race -> pull in crew -> submit proof -> track progress -> leaderboard',
            style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
          ),
        ],
      ),
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTextStyles.headlineLarge),
        const SizedBox(height: 10),
        Text(
          subtitle,
          style: AppTextStyles.bodyLarge.copyWith(color: NuvoColors.muted),
        ),
      ],
    );
  }
}

// White circle with Google-blue "G" — correct on the primary blue button bg.
class _GoogleGIcon extends StatelessWidget {
  const _GoogleGIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: const Text(
        'G',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: Color(0xFF4285F4),
          height: 1,
        ),
      ),
    );
  }
}

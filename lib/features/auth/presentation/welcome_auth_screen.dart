import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_geometry.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_shared_components.dart';
import 'auth_controller.dart';
import 'welcome_onboarding_state.dart';
import '../../onboarding/presentation/first_use_guide.dart';
import '../../races/domain/motion_activity.dart';

enum _AuthMode { signup, login }

// Flip to true once the two external steps in GOOGLE_OAUTH_FIX_PLAN.md are done:
// 1. Google Cloud Console iOS OAuth client registered for com.example.nuvo
// 2. GOOGLE_IOS_CLIENT_ID set in Cloudflare Worker secrets via wrangler secret put
const _kGoogleEnabled = true;

class WelcomeAuthScreen extends ConsumerStatefulWidget {
  const WelcomeAuthScreen({super.key});

  @override
  ConsumerState<WelcomeAuthScreen> createState() => _WelcomeAuthScreenState();
}

class _WelcomeAuthScreenState extends ConsumerState<WelcomeAuthScreen> {
  // Constructed lazily: on web with no client ID configured the GoogleSignIn()
  // constructor asserts, so we must not touch it until the button is tapped.
  // With _kGoogleEnabled = false the button is hidden and this is never accessed.
  late final _googleSignIn = GoogleSignIn();
  _AuthMode _mode = _AuthMode.signup;
  bool _googleLoading = false;
  String? _googleError;
  bool _appleLoading = false;
  String? _appleError;

  Future<void> _openLegalUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _toggleMode() {
    setState(() {
      _mode = _mode == _AuthMode.signup ? _AuthMode.login : _AuthMode.signup;
      _googleError = null;
    });
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _googleLoading = true;
      _googleError = null;
      _appleError = null;
    });
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) {
        if (mounted) setState(() => _googleLoading = false);
        return;
      }
      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null) {
        if (mounted) {
          setState(() {
            _googleError = 'Google sign-in failed. Please try again.';
            _googleLoading = false;
          });
        }
        return;
      }
      await ref.read(authControllerProvider.notifier).signInWithGoogle(idToken);
    } catch (_) {
      if (mounted) {
        setState(() {
          _googleError = 'Google sign-in failed. Please try again.';
          _googleLoading = false;
        });
      }
    }
  }

  Future<void> _signInWithApple() async {
    setState(() {
      _appleLoading = true;
      _appleError = null;
      _googleError = null;
    });
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final idToken = credential.identityToken;
      if (idToken == null || idToken.isEmpty) {
        throw Exception('Apple did not return an identity token');
      }

      final fullName = _formatAppleFullName(
        credential.givenName,
        credential.familyName,
      );

      await ref
          .read(authControllerProvider.notifier)
          .signInWithApple(idToken, fullName: fullName);
    } catch (e) {
      debugPrint('[AppleSignIn] error: $e');
      if (mounted) {
        setState(() {
          _appleError = 'Apple Sign In was cancelled or failed.';
          _appleLoading = false;
        });
      }
    }
  }

  String? _formatAppleFullName(String? given, String? family) {
    final parts = [given, family]
        .where((s) => s != null && s.trim().isNotEmpty)
        .map((s) => s!.trim())
        .toList();
    if (parts.isEmpty) return null;
    return parts.join(' ');
  }

  void _continueDemo() {
    ref.read(demoReplayProvider.notifier).state = false;
    ref.read(firstRaceGuideProvider.notifier).state =
        FirstRaceGuideStep.competeStart;
    context.go('/compete');
  }

  @override
  Widget build(BuildContext context) {
    final isSignup = _mode == _AuthMode.signup;
    final replayingDemo = ref.watch(demoReplayProvider);
    final builderState = ref.watch(welcomeOnboardingStateProvider);
    final hasBuiltRace =
        !replayingDemo && isSignup && builderState.canProceedToAuth;

    final toggleLabel = isSignup
        ? 'Already have an account? Log in'
        : 'New to Nuvo? Create an account';

    final emailLabel = hasBuiltRace
        ? 'Create account & start this race'
        : replayingDemo
        ? 'Continue demo'
        : 'Continue with Email';

    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 52,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _BrandMark(),
                  const SizedBox(height: 48),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    child: hasBuiltRace
                        ? _RacePreview(
                            key: const ValueKey('preview'),
                            state: builderState,
                          )
                        : _AuthHero(
                            key: ValueKey(
                              '${_mode}_${builderState.fitnessGoal}',
                            ),
                            isSignup: isSignup,
                            goal: builderState.fitnessGoal,
                          ),
                  ),
                  const Spacer(),
                  const SizedBox(height: 42),
                  NuvoPrimaryButton(
                    label: emailLabel,
                    expand: true,
                    leadingWidget: const Icon(
                      Icons.mail_outline_rounded,
                      size: 18,
                      color: NuvoColors.white,
                    ),
                    onPressed: replayingDemo
                        ? _continueDemo
                        : () => context.push('/auth/email'),
                  ),
                  const SizedBox(height: 12),
                  _AppleButton(
                    loading: _appleLoading,
                    error: _appleError,
                    onPressed: _signInWithApple,
                  ),
                  const SizedBox(height: 12),
                  if (_kGoogleEnabled)
                    _GoogleButton(
                      loading: _googleLoading,
                      error: _googleError,
                      onPressed: _signInWithGoogle,
                    ),
                  const SizedBox(height: 18),
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
                  const SizedBox(height: 16),
                  _LegalCopy(onOpen: _openLegalUrl),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Private components ────────────────────────────────────────────────────────

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/branding/nuvotext.png',
      width: 116,
      height: 34,
      alignment: Alignment.centerLeft,
      fit: BoxFit.contain,
    );
  }
}

class _AuthHero extends StatelessWidget {
  const _AuthHero({super.key, required this.isSignup, this.goal});

  final bool isSignup;
  final FitnessGoal? goal;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        isSignup ? 'Put your first race\non the board.' : 'Welcome\nback.',
        style: AppTextStyles.displayMedium.copyWith(
          color: NuvoColors.navy,
          height: .96,
          letterSpacing: -1.3,
        ),
      ),
      const SizedBox(height: 18),
      Text(
        isSignup
            ? 'Set a finish line, pull in your crew, and start moving together.'
            : 'Jump back into your arena and keep your crew moving.',
        style: AppTextStyles.bodyLarge.copyWith(
          color: NuvoColors.muted,
          height: 1.35,
        ),
      ),
      if (isSignup && goal != null) ...[
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
          decoration: BoxDecoration(
            color: NuvoColors.icyBlue,
            borderRadius: BorderRadius.circular(NuvoRadii.md),
            border: Border.all(color: NuvoColors.navy, width: 1.3),
          ),
          child: Row(
            children: [
              Icon(goal!.icon, color: NuvoColors.blue, size: 20),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Training for: ${goal!.title}',
                  style: AppTextStyles.labelMedium.copyWith(
                    color: NuvoColors.navy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ],
  );
}

class _RacePreview extends StatelessWidget {
  const _RacePreview({super.key, required this.state});

  final WelcomeOnboardingState state;

  @override
  Widget build(BuildContext context) {
    final option = state.selectedOption!;
    final target = state.target!;
    final isCamera = state.proofLabel == 'ai_check';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'One more step.',
          style: AppTextStyles.displayMedium.copyWith(
            color: NuvoColors.navy,
            height: .96,
            letterSpacing: -1.3,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Create your account to start this race and pull in your crew.',
          style: AppTextStyles.bodyLarge.copyWith(
            color: NuvoColors.muted,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 28),
        NuvoBackplateCard(
          radius: 28,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      state.generatedTitle,
                      style: AppTextStyles.titleMedium,
                    ),
                  ),
                  const SizedBox(width: 10),
                  NuvoIconBadge(icon: option.icon, size: 42, iconSize: 21),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                option.description,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: NuvoColors.muted,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  NuvoPill(
                    label: state.recurrence == RaceRecurrence.none
                        ? 'One time'
                        : state.recurrence.label,
                    color: NuvoColors.navy,
                  ),
                  const SizedBox(width: 8),
                  NuvoPill(
                    label: isCamera
                        ? 'Camera'
                        : _proofDisplayName(state.proofLabel),
                    color: isCamera ? NuvoColors.actionBlue : NuvoColors.navy,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: NuvoColors.icyBlue,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: NuvoColors.border),
                ),
                child: Text(
                  'Finish line: $target ${option.unit}',
                  style: AppTextStyles.labelMedium.copyWith(
                    color: NuvoColors.navy,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _proofDisplayName(String proof) => switch (proof) {
  'ai_check' => 'Camera',
  'manual' => 'Manual',
  'photo' => 'Photo',
  'note' => 'Note',
  'link' => 'Link',
  'daily_check' => 'Daily check-in',
  _ => proof,
};

/// One shared shell for every third-party provider button so Apple, Google
/// (and email above) read as the same control — same height, border, shadow,
/// Manrope label — only the leading glyph differs.
class _ProviderButton extends StatelessWidget {
  const _ProviderButton({
    required this.label,
    required this.glyph,
    required this.loading,
    required this.error,
    required this.onPressed,
  });

  final String label;
  final Widget glyph;
  final bool loading;
  final String? error;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              error!,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.danger),
            ),
          ),
        GestureDetector(
          onTap: loading ? null : onPressed,
          behavior: HitTestBehavior.opaque,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 160),
            opacity: loading ? 0.55 : 1,
            child: Container(
              height: 54,
              width: double.infinity,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: NuvoColors.surface,
                borderRadius: BorderRadius.circular(NuvoRadii.button),
                border: Border.all(color: NuvoColors.navy, width: 2),
                boxShadow: AppShadows.hardSmall,
              ),
              child: loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        glyph,
                        const SizedBox(width: 10),
                        Text(
                          label,
                          style: AppTextStyles.buttonLabel.copyWith(
                            color: NuvoColors.navy,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AppleButton extends StatelessWidget {
  const _AppleButton({
    required this.loading,
    required this.error,
    required this.onPressed,
  });

  final bool loading;
  final String? error;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => _ProviderButton(
    label: 'Continue with Apple',
    glyph: const Icon(Icons.apple, size: 22, color: NuvoColors.navy),
    loading: loading,
    error: error,
    onPressed: onPressed,
  );
}

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({
    required this.loading,
    required this.error,
    required this.onPressed,
  });
  final bool loading;
  final String? error;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => _ProviderButton(
    label: 'Continue with Google',
    glyph: const _GoogleGIcon(),
    loading: loading,
    error: error,
    onPressed: onPressed,
  );
}

class _LegalCopy extends StatelessWidget {
  const _LegalCopy({required this.onOpen});
  final Future<void> Function(String) onOpen;

  @override
  Widget build(BuildContext context) => Center(
    child: RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: AppTextStyles.labelSmall.copyWith(
          color: NuvoColors.muted.withValues(alpha: .65),
          height: 1.5,
        ),
        children: [
          const TextSpan(text: 'By continuing you agree to our '),
          TextSpan(
            text: 'Terms',
            style: AppTextStyles.labelSmall.copyWith(
              color: NuvoColors.blue,
              fontWeight: FontWeight.w700,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () => onOpen('https://getnuvo.net/terms'),
          ),
          const TextSpan(text: ' & '),
          TextSpan(
            text: 'Privacy Policy',
            style: AppTextStyles.labelSmall.copyWith(
              color: NuvoColors.blue,
              fontWeight: FontWeight.w700,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () => onOpen('https://getnuvo.net/privacy'),
          ),
          const TextSpan(text: '.'),
        ],
      ),
    ),
  );
}

class _GoogleGIcon extends StatelessWidget {
  const _GoogleGIcon();

  // nuvo-lint-ignore: brand-color — Google's official "G" mark colors, not a
  // Nuvo palette literal. Never recolor to match NuvoColors; that's a
  // platform brand requirement, not a design choice.
  static const _googleG = Color(0xFF4285F4);
  static const _googleGBackdrop = Color(0xFFF0F0F0);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: const BoxDecoration(
        color: _googleGBackdrop,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: const Text(
        'G',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: _googleG,
          height: 1,
        ),
      ),
    );
  }
}

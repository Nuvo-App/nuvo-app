import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/constants/asset_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_geometry.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import 'auth_controller.dart';

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

  @override
  Widget build(BuildContext context) {
    final isSignup = _mode == _AuthMode.signup;

    final toggleLabel = isSignup
        ? 'Already have an account? Log in'
        : 'New to Nuvo? Create an account';

    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Scrollable hero area ─────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
                child:
                    Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _BrandMark(),
                            const SizedBox(height: 22),

                            // Hero — animates when mode switches
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
                              child: _HeroBlock(
                                key: ValueKey(_mode),
                                isSignup: isSignup,
                              ),
                            ),

                            // Product preview card — signup only
                            if (isSignup) ...[
                              const SizedBox(height: 22),
                              const _ProductPreviewCard(),
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

            // ── Pinned CTA zone — never clips ───────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  NuvoPrimaryButton(
                    label: 'Continue with Email',
                    expand: true,
                    leadingWidget: const Icon(
                      Icons.mail_outline_rounded,
                      size: 18,
                      color: NuvoColors.white,
                    ),
                    onPressed: () => context.push('/auth/email'),
                  ),
                  const SizedBox(height: 12),

                  // Google — interactive when _kGoogleEnabled, else needs-setup row
                  if (_kGoogleEnabled) ...[
                    if (_googleError != null) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _googleError!,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: NuvoColors.danger,
                          ),
                        ),
                      ),
                    ],
                    GestureDetector(
                      onTap: _googleLoading ? null : _signInWithGoogle,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 180),
                        opacity: _googleLoading ? 0.55 : 1.0,
                        child: Container(
                          height: 52,
                          decoration: BoxDecoration(
                            color: NuvoColors.white,
                            borderRadius: BorderRadius.circular(NuvoRadii.md),
                            border: NuvoBorders.quiet,
                          ),
                          alignment: Alignment.center,
                          child: _googleLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const _GoogleGIcon(),
                                    const SizedBox(width: 10),
                                    Text(
                                      'Continue with Google',
                                      style: AppTextStyles.labelLarge.copyWith(
                                        color: NuvoColors.navy,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ],

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

                  // Terms — always in view
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

// ── Private components ────────────────────────────────────────────────────────

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // trans.png is white — must stay inside dark container
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: NuvoColors.navy,
            borderRadius: BorderRadius.circular(NuvoRadii.sm),
            border: NuvoBorders.action,
            boxShadow: AppShadows.actionShadow,
          ),
          padding: const EdgeInsets.all(7),
          child: Image.asset(AssetPaths.nuvoLogo, fit: BoxFit.contain),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nuvo', style: AppTextStyles.titleLarge),
            const SizedBox(height: 1),
            Text(
              'RACE WITH YOUR CREW',
              style: AppTextStyles.labelSmall.copyWith(
                color: NuvoColors.blue,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StartLineChip extends StatelessWidget {
  const _StartLineChip({this.label = 'START LINE OPEN'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: NuvoColors.white,
        borderRadius: BorderRadius.circular(NuvoRadii.pill),
        border: Border.all(color: NuvoColors.border, width: 1.1),
      ),
      child: Text(
        label,
        style: AppTextStyles.labelSmall.copyWith(
          color: NuvoColors.navy,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _LoopStrip extends StatelessWidget {
  const _LoopStrip();

  @override
  Widget build(BuildContext context) {
    const steps = ['Finish line', 'Crew', 'Proof', 'Leaderboard'];
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (final step in steps)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: step == 'Proof' ? NuvoColors.blue : NuvoColors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: step == 'Proof' ? NuvoColors.blueInk : NuvoColors.border,
              ),
            ),
            child: Text(
              step,
              style: AppTextStyles.labelSmall.copyWith(
                color: step == 'Proof' ? NuvoColors.white : NuvoColors.navy,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
      ],
    );
  }
}

class _HeroBlock extends StatelessWidget {
  const _HeroBlock({super.key, required this.isSignup});

  final bool isSignup;

  @override
  Widget build(BuildContext context) {
    if (isSignup) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _StartLineChip(),
          const SizedBox(height: 16),
          RichText(
            text: TextSpan(
              style: AppTextStyles.displayMedium.copyWith(
                color: NuvoColors.navy,
              ),
              children: const [
                TextSpan(text: 'Turn real life\ninto a '),
                TextSpan(
                  text: 'race.',
                  style: TextStyle(color: NuvoColors.blue),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Pick a finish line, pull in your crew, and submit proof to move the leaderboard.',
            style: AppTextStyles.bodyLarge.copyWith(color: NuvoColors.muted),
          ),
          const SizedBox(height: 16),
          const _LoopStrip(),
        ],
      );
    } else {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _StartLineChip(label: 'BACK IN THE ARENA'),
          const SizedBox(height: 16),
          RichText(
            text: TextSpan(
              style: AppTextStyles.displayMedium,
              children: const [
                TextSpan(text: 'Welcome\n'),
                TextSpan(
                  text: 'back.',
                  style: TextStyle(color: NuvoColors.blue),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Jump back into your arena and keep your crew competing.',
            style: AppTextStyles.bodyLarge.copyWith(color: NuvoColors.muted),
          ),
        ],
      );
    }
  }
}

// Static race preview card — marketing illustration, not wired to real user data.
class _ProductPreviewCard extends StatelessWidget {
  const _ProductPreviewCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: NuvoColors.white,
        borderRadius: BorderRadius.circular(NuvoRadii.lg),
        border: Border.all(color: NuvoColors.border, width: 1.2),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Race header row
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: NuvoColors.blue,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.directions_run_rounded,
                  color: NuvoColors.white,
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '10 Jumping Jacks',
                      style: AppTextStyles.titleMedium.copyWith(
                        color: NuvoColors.navy,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Camera verified · 10 reps',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: NuvoColors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              // Active status pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0x2216C784),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0x5516C784)),
                ),
                child: Text(
                  'Live',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: NuvoColors.navy,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Progress bar
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: SizedBox(
                    height: 5,
                    child: Stack(
                      children: [
                        Container(color: NuvoColors.trackBg),
                        FractionallySizedBox(
                          widthFactor: 0.6,
                          alignment: Alignment.centerLeft,
                          child: Container(
                            decoration: const BoxDecoration(
                              color: NuvoColors.blue,
                              borderRadius: BorderRadius.all(
                                Radius.circular(99),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '6 / 10',
                style: AppTextStyles.labelMedium.copyWith(
                  color: NuvoColors.navy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Crew bubbles + move CTA
          Row(
            children: [
              const _CrewBubble('A', Color(0xFF8B9CFF)),
              const SizedBox(width: 4),
              const _CrewBubble('J', Color(0xFF16C784)),
              const SizedBox(width: 4),
              const _CrewBubble('M', Color(0xFFFF8B6B)),
              const SizedBox(width: 8),
              Text(
                '3 crew',
                style: AppTextStyles.labelSmall.copyWith(
                  color: NuvoColors.muted,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: NuvoColors.blue,
                  borderRadius: BorderRadius.circular(999),
                  border: NuvoBorders.action,
                  boxShadow: AppShadows.actionShadow,
                ),
                child: Text(
                  'Log move',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: NuvoColors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CrewBubble extends StatelessWidget {
  const _CrewBubble(this.initial, this.color);

  final String initial;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: NuvoColors.white, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: AppTextStyles.labelSmall.copyWith(
          color: NuvoColors.white,
          fontWeight: FontWeight.w800,
          fontSize: 10,
        ),
      ),
    );
  }
}

class _GoogleGIcon extends StatelessWidget {
  const _GoogleGIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: const BoxDecoration(
        color: Color(0xFFF0F0F0),
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

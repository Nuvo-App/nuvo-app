import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/navigation/nuvo_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_flip_text.dart';
import 'auth_controller.dart';
import 'email_start_screen.dart';
import '../../onboarding/presentation/first_use_guide.dart';

enum _AuthMode { signup, login }

// Flip to true once the two external steps in GOOGLE_OAUTH_FIX_PLAN.md are done:
// 1. Google Cloud Console iOS OAuth client registered for com.example.nuvo
// 2. GOOGLE_IOS_CLIENT_ID set in Cloudflare Worker secrets via wrangler secret put
const _kGoogleEnabled = true;

class WelcomeAuthScreen extends ConsumerStatefulWidget {
  const WelcomeAuthScreen({
    super.key,
    this.initialLogin = false,
    this.embedded = false,
  });

  final bool initialLogin;
  final bool embedded;

  @override
  ConsumerState<WelcomeAuthScreen> createState() => _WelcomeAuthScreenState();
}

class _WelcomeAuthScreenState extends ConsumerState<WelcomeAuthScreen> {
  // Constructed lazily: on web with no client ID configured the GoogleSignIn()
  // constructor asserts, so we must not touch it until the button is tapped.
  // With _kGoogleEnabled = false the button is hidden and this is never accessed.
  late final _googleSignIn = GoogleSignIn();
  late _AuthMode _mode = widget.initialLogin
      ? _AuthMode.login
      : _AuthMode.signup;
  final _scrollController = ScrollController();
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

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _toggleMode() {
    FocusScope.of(context).unfocus();
    setState(() {
      _mode = _mode == _AuthMode.signup ? _AuthMode.login : _AuthMode.signup;
      _googleError = null;
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
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
    } catch (e) {
      if (mounted) {
        setState(() {
          _googleError = isNetworkAuthError(e)
              ? "Can't reach Nuvo. Check your connection and try again."
              : 'Google sign-in failed. Please try again.';
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

      // The authorization code is exchanged server-side for an Apple
      // refresh token so account deletion can revoke the grant — Apple
      // requires this when an app offers in-app account deletion. It may be
      // absent on some re-auth paths; the server tolerates that.
      final authorizationCode = credential.authorizationCode;

      final fullName = _formatAppleFullName(
        credential.givenName,
        credential.familyName,
      );

      await ref
          .read(authControllerProvider.notifier)
          .signInWithApple(
            idToken,
            fullName: fullName,
            authorizationCode: authorizationCode,
          );
    } catch (e) {
      debugPrint('[AppleSignIn] error: $e');
      if (mounted) {
        setState(() {
          _appleError = isNetworkAuthError(e)
              ? "Can't reach Nuvo. Check your connection and try again."
              : 'Apple Sign In was cancelled or failed.';
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
    final content = LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 600;
        final verticalPadding = compact ? 16.0 : 28.0;
        return SingleChildScrollView(
          key: const ValueKey('auth-scroll'),
          controller: _scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.symmetric(
            horizontal: 24,
            vertical: verticalPadding,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - verticalPadding * 2).clamp(
                0,
                double.infinity,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!widget.embedded && context.canPop()) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: NuvoBackButton(
                      onPressed: () => safePopOrGo(context, '/welcome'),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                NuvoFlipText(
                  isSignup
                      ? 'Ready to start\nyour first race?'
                      : 'Welcome back.',
                  style: AppTextStyles.displayMedium.copyWith(
                    color: NuvoColors.navy,
                    fontSize: constraints.maxWidth < 360 ? 30 : 36,
                    height: 1.08,
                    letterSpacing: -1.1,
                  ),
                  delay: const Duration(milliseconds: 200),
                  duration: const Duration(milliseconds: 1500),
                ),
                const SizedBox(height: 12),
                Text(
                  isSignup
                      ? 'Create an account to save your races, invite your crew, and keep your progress.'
                      : 'Log in to keep your races, progress, and crew synced.',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: NuvoColors.muted,
                  ),
                ),
                SizedBox(height: compact ? 24 : 28),
                if (isSignup || replayingDemo)
                  NuvoPrimaryButton(
                    label: replayingDemo ? 'Continue demo' : 'Create account',
                    expand: true,
                    onPressed: replayingDemo
                        ? _continueDemo
                        : () => context.push('/auth/email'),
                  )
                else
                  const EmailStartScreen(embedded: true),
                const SizedBox(height: 12),
                _AppleButton(
                  loading: _appleLoading,
                  error: _appleError,
                  onPressed: _signInWithApple,
                ),
                if (_kGoogleEnabled) ...[
                  const SizedBox(height: 12),
                  _GoogleButton(
                    loading: _googleLoading,
                    error: _googleError,
                    onPressed: _signInWithGoogle,
                  ),
                ],
                const SizedBox(height: 20),
                // Plain inline text action — not a fourth auth button. A real
                // TextButton picks up the app's chip-like textButtonTheme
                // (gray fill + border + shadow), which read as a disabled
                // pill; GestureDetector keeps the 44px target invisible.
                GestureDetector(
                  key: const ValueKey('auth-mode-toggle'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleMode,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 10,
                    ),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: isSignup
                                ? 'Already have an account? '
                                : "Don't have an account? ",
                          ),
                          TextSpan(
                            text: isSignup ? 'Log in' : 'Sign up',
                            style: const TextStyle(
                              color: NuvoColors.blue,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: NuvoColors.muted,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: compact ? 14 : 22),
                _LegalCopy(onOpen: _openLegalUrl),
              ],
            ),
          ),
        );
      },
    );
    if (widget.embedded) return content;
    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: SafeArea(child: content),
    );
  }
}

// ── Private components ────────────────────────────────────────────────────────

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
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      NuvoOutlineButton(
        label: label,
        expand: true,
        height: 52,
        // Fixed-width leading slot so the Apple and Google labels sit at the
        // same x position regardless of glyph width — the row still centers
        // as a unit inside the button.
        leadingWidget: SizedBox(
          width: 22,
          height: 22,
          child: Center(
            child: loading
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: NuvoColors.navy,
                    ),
                  )
                : glyph,
          ),
        ),
        onPressed: loading ? null : onPressed,
      ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Semantics(
            liveRegion: true,
            child: Text(
              error!,
              style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.danger),
            ),
          ),
        ),
    ],
  );
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
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        'By continuing, you agree to our',
        textAlign: TextAlign.center,
        style: AppTextStyles.bodySmall.copyWith(
          color: NuvoColors.muted,
          fontSize: 12,
        ),
      ),
      Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _link('Terms', 'https://getnuvo.net/terms'),
          Text(
            ' & ',
            style: AppTextStyles.bodySmall.copyWith(
              color: NuvoColors.muted,
              fontSize: 12,
            ),
          ),
          _link('Privacy Policy', 'https://getnuvo.net/privacy'),
        ],
      ),
    ],
  );

  // Inline text links — GestureDetector, never TextButton: the app-level
  // textButtonTheme paints a filled, bordered, shadowed chip behind every
  // TextButton, which is what made the legal links render as mini pills.
  Widget _link(String label, String url) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => onOpen(url),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
      child: Text(
        label,
        style: AppTextStyles.bodySmall.copyWith(
          color: NuvoColors.blue,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    ),
  );
}

/// The official Google "G" mark, drawn from the published vector geometry
/// (viewBox 0 0 48 48). No Google logo asset ships in the bundle and pubspec
/// has no icon/SVG package, so a CustomPainter keeps the real four-colour
/// mark crisp at any size without a new dependency — and it is the actual
/// mark, not a styled-text stand-in.
class _GoogleGIcon extends StatelessWidget {
  const _GoogleGIcon();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 20,
    height: 20,
    child: CustomPaint(painter: _GoogleGPainter()),
  );
}

class _GoogleGPainter extends CustomPainter {
  const _GoogleGPainter();

  // nuvo-lint-ignore: brand-color — Google's official mark colours, not Nuvo
  // palette literals. Never recolor to match NuvoColors; that is a platform
  // brand requirement, not a design choice.
  static const _red = Color(0xFFEA4335);
  static const _blue = Color(0xFF4285F4);
  static const _yellow = Color(0xFFFBBC05);
  static const _green = Color(0xFF34A853);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 48, size.height / 48);

    final red = Path()
      ..moveTo(24, 9.5)
      ..relativeCubicTo(3.54, 0, 6.71, 1.22, 9.21, 3.6)
      ..relativeLineTo(6.85, -6.85)
      ..cubicTo(35.9, 2.38, 30.47, 0, 24, 0)
      ..cubicTo(14.62, 0, 6.51, 5.38, 2.56, 13.22)
      ..relativeLineTo(7.98, 6.19)
      ..cubicTo(12.43, 13.72, 17.74, 9.5, 24, 9.5)
      ..close();

    final blue = Path()
      ..moveTo(46.98, 24.55)
      ..relativeCubicTo(0, -1.57, -0.15, -3.09, -0.38, -4.55)
      ..lineTo(24, 20)
      ..relativeLineTo(0, 9.02)
      ..relativeLineTo(12.94, 0)
      ..relativeCubicTo(-0.58, 2.96, -2.26, 5.48, -4.78, 7.18)
      ..relativeLineTo(7.73, 6)
      ..relativeCubicTo(4.51, -4.18, 7.09, -10.36, 7.09, -17.65)
      ..close();

    final yellow = Path()
      ..moveTo(10.53, 28.59)
      ..relativeCubicTo(-0.48, -1.45, -0.76, -2.99, -0.76, -4.59)
      // SVG 's' (smooth cubic): first control point is the reflection of the
      // previous segment's second control point — (0.76, 2.99) here.
      ..relativeCubicTo(0.76, 2.99, 0.27, -3.14, 0.76, -4.59)
      ..relativeLineTo(-7.98, -6.19)
      ..cubicTo(0.92, 16.46, 0, 20.12, 0, 24)
      ..relativeCubicTo(0, 3.88, 0.92, 7.54, 2.56, 10.78)
      ..relativeLineTo(7.97, -6.19)
      ..close();

    final green = Path()
      ..moveTo(24, 48)
      ..relativeCubicTo(6.48, 0, 11.93, -2.13, 15.89, -5.81)
      ..relativeLineTo(-7.73, -6)
      ..relativeCubicTo(-2.15, 1.45, -4.92, 2.3, -8.16, 2.3)
      ..relativeCubicTo(-6.26, 0, -11.57, -4.22, -13.47, -9.91)
      ..relativeLineTo(-7.98, 6.19)
      ..cubicTo(6.51, 42.62, 14.62, 48, 24, 48)
      ..close();

    canvas.drawPath(red, Paint()..color = _red);
    canvas.drawPath(blue, Paint()..color = _blue);
    canvas.drawPath(yellow, Paint()..color = _yellow);
    canvas.drawPath(green, Paint()..color = _green);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GoogleGPainter oldDelegate) => false;
}

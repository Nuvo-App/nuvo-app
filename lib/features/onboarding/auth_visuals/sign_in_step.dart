import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics_service.dart';
import '../../../core/config/legal_links.dart';
import '../../../core/motion/motion.dart';
import '../../../core/widgets/google_g_logo.dart';
import '../../../core/v13/tokens.dart';
import '../../auth/presentation/auth_controller.dart';
import '../flow/onboarding_copy.dart';
import '../flow/onboarding_flow_controller.dart';
import '../flow/onboarding_step.dart';
import '../shell/onboarding_shell.dart' show obAdvance;
import 'login_hero.dart';
import '../shell/onboarding_shell_controller.dart';
import 'ob_shake.dart';
import 'social_sign_in.dart';

enum _Busy { none, apple, google }

/// S4 — "Save your spot." A white bottom sheet rising over the (frozen,
/// blurred) leaderboard hero. Apple / Google run the existing sign-in
/// calls; "Use email instead" continues to S5. A social sign-in verifies the
/// account, so it settles the email + code steps and lands the same +10.
class ObSignInStep extends ConsumerStatefulWidget {
  const ObSignInStep({super.key});

  @override
  ConsumerState<ObSignInStep> createState() => _ObSignInStepState();
}

class _ObSignInStepState extends ConsumerState<ObSignInStep>
    with SingleTickerProviderStateMixin {
  final _shake = GlobalKey<ObShakeState>();
  late final AnimationController _rise = AnimationController(
    vsync: this,
    duration: NuvoMotion.enter,
  );
  _Busy _busy = _Busy.none;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (NuvoMotion.reduceMotionOf(context)) {
        _rise.value = 1;
      } else {
        _rise.forward();
      }
    });
  }

  @override
  void dispose() {
    _rise.dispose();
    super.dispose();
  }

  Future<void> _social(_Busy which) async {
    if (_busy != _Busy.none) return;
    final method = which == _Busy.apple ? 'apple' : 'google';
    final analytics = ref.read(analyticsProvider);
    final auth = ref.read(authControllerProvider.notifier);
    final social = ref.read(obSocialSignInProvider);
    final flow = ref.read(onboardingFlowProvider.notifier);
    final shell = OnboardingShellScope.of(context);
    analytics.signupStarted(method: method);
    setState(() {
      _busy = which;
      _error = null;
    });
    try {
      if (which == _Busy.apple) {
        await social.apple(auth);
      } else if (!await social.google(auth)) {
        analytics.signupFailed(method: method, reason: 'cancelled');
        if (mounted) setState(() => _busy = _Busy.none);
        return;
      }
    } catch (e) {
      debugPrint('[ObSignIn] $method failed (${e.runtimeType})');
      analytics.signupFailed(method: method, reason: 'error');
      if (!mounted) return;
      setState(() {
        _busy = _Busy.none;
        _error = isNetworkAuthError(e)
            ? ObCopy.authOffline
            : which == _Busy.apple
            ? ObCopy.signInAppleFailed
            : ObCopy.signInGoogleFailed;
      });
      _shake.currentState?.shake();
      NuvoHaptics.heavy();
      return;
    }
    // Signed in. Settle the account first, then complete code and email
    // BEFORE signIn: completing a step other than the current one does not
    // move the pointer, so the flow goes straight to S7 with no flash of
    // the email screen (and no keyboard pop).
    final email = ref.read(authControllerProvider).user?.email;
    if (email != null) await flow.attachAccount(email);
    final awarded = await flow.completeStep(OnboardingStep.code);
    await flow.completeStep(OnboardingStep.email);
    await flow.completeStep(OnboardingStep.signIn);
    if (awarded > 0) shell.award(awarded);
  }

  Future<void> _useEmail() async {
    if (_busy != _Busy.none) return;
    await obAdvance(context, ref, OnboardingStep.signIn);
  }

  @override
  Widget build(BuildContext context) {
    final short = MediaQuery.sizeOf(context).height < 640;
    final sheetH =
        (short ? 300.0 : 316.0) + MediaQuery.paddingOf(context).bottom;
    return ColoredBox(
      // Full-bleed brand coral from the top edge through the sheet.
      color: V13.coral,
      child: Stack(
        children: [
          Positioned.fill(
            bottom: sheetH,
            child: const SafeArea(
              bottom: false,
              child: ObLoginHero(key: ValueKey('ob-login-hero')),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0, 1),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(parent: _rise, curve: NuvoMotion.spring),
                  ),
              child: ObShake(
                key: _shake,
                child: _SignInSheet(
                  busy: _busy,
                  error: _error,
                  onApple: () => _social(_Busy.apple),
                  onGoogle: () => _social(_Busy.google),
                  onEmail: _useEmail,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignInSheet extends StatelessWidget {
  const _SignInSheet({
    required this.busy,
    required this.error,
    required this.onApple,
    required this.onGoogle,
    required this.onEmail,
  });

  final _Busy busy;
  final String? error;
  final VoidCallback onApple;
  final VoidCallback onGoogle;
  final VoidCallback onEmail;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      key: const ValueKey('ob-signin-sheet'),
      padding: EdgeInsets.fromLTRB(24, 24, 24, 16 + bottom),
      decoration: const BoxDecoration(
        color: V13.card,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(V13.radiusCardLg),
        ),
        border: Border(
          top: BorderSide(color: V13.navy, width: V13.outlineThick),
          left: BorderSide(color: V13.navy, width: V13.outlineThick),
          right: BorderSide(color: V13.navy, width: V13.outlineThick),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(ObCopy.signInTitle, style: V13.cardTitle),
          const SizedBox(height: 16),
          AnimatedOpacity(
            duration: NuvoMotion.ctaFade,
            opacity: busy == _Busy.google ? 0.4 : 1,
            child: _AuthButton(
              key: const ValueKey('ob-apple'),
              label: ObCopy.signInApple,
              icon: Icons.apple,
              fill: V13.navy,
              ink: V13.white,
              loading: busy == _Busy.apple,
              onTap: busy == _Busy.none ? onApple : null,
            ),
          ),
          const SizedBox(height: V13.gapMd),
          AnimatedOpacity(
            duration: NuvoMotion.ctaFade,
            opacity: busy == _Busy.apple ? 0.4 : 1,
            child: _AuthButton(
              key: const ValueKey('ob-google'),
              label: ObCopy.signInGoogle,
              leading: const GoogleGLogo(size: 22),
              fill: V13.card,
              ink: V13.navy,
              loading: busy == _Busy.google,
              onTap: busy == _Busy.none ? onGoogle : null,
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: V13.gapMd),
            Text(
              error!,
              key: const ValueKey('ob-signin-error'),
              textAlign: TextAlign.center,
              style: V13.bodyStrong.copyWith(color: V13.danger),
            ),
          ],
          const SizedBox(height: V13.gapSm),
          NuvoPressable(
            onTap: busy == _Busy.none ? onEmail : null,
            enabled: busy == _Busy.none,
            semanticLabel: ObCopy.signInEmailLink,
            child: Container(
              key: const ValueKey('ob-email-link'),
              height: 48,
              alignment: Alignment.center,
              child: Text(
                ObCopy.signInEmailLink,
                style: V13.bodyStrong.copyWith(color: V13.navy),
              ),
            ),
          ),
          const _LegalLine(),
        ],
      ),
    );
  }
}

class _AuthButton extends StatelessWidget {
  const _AuthButton({
    super.key,
    required this.label,
    this.icon,
    this.leading,
    required this.fill,
    required this.ink,
    required this.loading,
    required this.onTap,
  });

  final String label;
  final IconData? icon;
  final Widget? leading;
  final Color fill;
  final Color ink;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return NuvoPressable(
      onTap: onTap,
      enabled: onTap != null,
      borderRadius: BorderRadius.circular(V13.radiusButton),
      shadow: V13.shadow4,
      semanticLabel: label,
      child: Container(
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(V13.radiusButton),
          border: Border.all(color: V13.navy, width: V13.outlineThick),
        ),
        child: loading
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 3, color: ink),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  leading ?? Icon(icon, color: ink, size: 26),
                  const SizedBox(width: V13.gapSm),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: V13.buttonLabel.copyWith(color: ink),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// "By continuing you agree to the Terms and Privacy Policy" with both
/// names opening the real legal pages.
class _LegalLine extends StatefulWidget {
  const _LegalLine();

  @override
  State<_LegalLine> createState() => _LegalLineState();
}

class _LegalLineState extends State<_LegalLine> {
  late final TapGestureRecognizer _terms = TapGestureRecognizer()
    ..onTap = () => openLegalLink(context, LegalLinks.termsUri);
  late final TapGestureRecognizer _privacy = TapGestureRecognizer()
    ..onTap = () => openLegalLink(context, LegalLinks.privacyUri);

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final link = V13.caption.copyWith(
      fontSize: 12,
      color: V13.navy,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
    );
    return Text.rich(
      TextSpan(
        style: V13.caption.copyWith(fontSize: 12, color: V13.muted),
        children: [
          const TextSpan(text: 'By continuing you agree to the '),
          TextSpan(text: 'Terms', style: link, recognizer: _terms),
          const TextSpan(text: ' and '),
          TextSpan(text: 'Privacy Policy', style: link, recognizer: _privacy),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

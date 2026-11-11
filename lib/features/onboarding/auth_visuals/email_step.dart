import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics_service.dart';
import '../../../core/motion/motion.dart';
import '../../../core/v13/tokens.dart';
import '../../../core/v13/widgets/v13_text_input.dart';
import '../../auth/data/auth_api.dart';
import '../../auth/presentation/auth_controller.dart';
import '../flow/onboarding_copy.dart';
import '../flow/onboarding_flow_controller.dart';
import '../flow/onboarding_step.dart';
import '../shell/onboarding_shell.dart';
import '../shell/onboarding_shell_controller.dart';
import 'auth_layout.dart';
import 'email_utils.dart';

/// S5 — "What's your email?" The player-pass ticket fills as you type; the
/// CTA is live on any valid address, errors sit inline under the field.
/// Sending uses the existing `startEmailAuth` (same call as the v1 screen).
class ObEmailStep extends ConsumerStatefulWidget {
  const ObEmailStep({super.key});

  @override
  ConsumerState<ObEmailStep> createState() => _ObEmailStepState();
}

class _ObEmailStepState extends ConsumerState<ObEmailStep> {
  late final TextEditingController _ctrl = TextEditingController(
    text: ref.read(onboardingFlowProvider).email ?? '',
  );
  final _pw = TextEditingController();
  final _focus = FocusNode();
  final _pwFocus = FocusNode();
  bool _sending = false;
  bool _wasValid = false;
  String? _error;

  bool get _valid => ObEmail.isValid(_ctrl.text);

  // The store-review credential signs in with a password through
  // /auth/reviewer (same call as the v1 email screen), never an inbox code.
  bool get _reviewer => isNuvoStoreDemoEmail(ObEmail.normalize(_ctrl.text));

  @override
  void initState() {
    super.initState();
    _wasValid = _valid;
    _ctrl.addListener(_onChanged);
    _pw.addListener(() => setState(() => _error = null));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _pw.dispose();
    _focus.dispose();
    _pwFocus.dispose();
    super.dispose();
  }

  void _onChanged() {
    final valid = _valid;
    if (valid && !_wasValid) NuvoHaptics.light();
    _wasValid = valid;
    setState(() => _error = null);
  }

  void _insertDomain(String domain) {
    NuvoHaptics.select();
    final next = ObEmail.withDomain(_ctrl.text, domain);
    _ctrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  Future<void> _reviewerSignIn() async {
    if (_sending || _pw.text.isEmpty) return;
    final email = ObEmail.normalize(_ctrl.text);
    final auth = ref.read(authControllerProvider.notifier);
    final flow = ref.read(onboardingFlowProvider.notifier);
    final shell = OnboardingShellScope.of(context);
    final intent = ref.read(authIntentProvider);
    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await auth.signInReviewer(email, _pw.text, intent: intent);
    } catch (e) {
      debugPrint('[ObEmail] reviewer sign-in failed (${e.runtimeType})');
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = isNetworkAuthError(e)
            ? ObCopy.authOffline
            : ObCopy.reviewerSignInFailed;
      });
      return;
    }
    // Signed in: settle the account, then complete code (+XP) and email.
    final signedIn = ref.read(authControllerProvider).user?.email;
    if (signedIn != null) await flow.attachAccount(signedIn);
    final awarded = await flow.completeStep(OnboardingStep.code);
    await flow.completeStep(OnboardingStep.email);
    if (awarded > 0) shell.award(awarded);
  }

  Future<void> _send() async {
    if (!_valid || _sending) return;
    if (_reviewer) return _reviewerSignIn();
    final email = ObEmail.normalize(_ctrl.text);
    final analytics = ref.read(analyticsProvider);
    final auth = ref.read(authControllerProvider.notifier);
    final flow = ref.read(onboardingFlowProvider.notifier);
    FocusScope.of(context).unfocus();
    analytics.signupStarted(method: 'email');
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await auth.startEmailAuth(email);
    } catch (e) {
      debugPrint('[ObEmail] startEmailAuth failed (${e.runtimeType})');
      analytics.signupFailed(
        method: 'email',
        reason: e is ApiException ? 'http_${e.statusCode}' : 'error',
      );
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = isNetworkAuthError(e)
            ? ObCopy.authOffline
            : e is ApiException && e.statusCode == 429
            ? ObCopy.emailRateLimited
            : ObCopy.emailSendFailed;
      });
      return;
    }
    await flow.setEmail(email);
    if (!mounted) return;
    await obAdvance(context, ref, OnboardingStep.email);
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.read(onboardingFlowProvider.notifier);
    final text = _ctrl.text;
    final valid = _valid;
    final typo = ObEmail.typoSuggestion(text);
    final chips = ObEmail.domainChips(text);
    final tight = obTightScreen(context);
    // The title already asks for the email: drop the field label and the
    // subtitle when the keyboard (or a short phone) takes the room.
    // Layout must NOT depend on the keyboard: resizing the hero/labels as it
    // rises made the page jump under the finger. Only short phones go lean.
    final lean = tight;

    return OnboardingShell(
      step: OnboardingStep.email,
      // Minimal chrome like the best sign-in screens: header, a big title,
      // one supporting line, one field, one button. No hero object.
      heroHeight: 0,
      hero: const SizedBox.shrink(),
      showRail: false,
      titleSize: tight ? 26 : 34,
      title: ObCopy.emailTitle,
      subtitle: lean ? null : ObCopy.emailSub,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The real v13 input (navy outline, blue focus ring) with the
          // signature hard shadow. Always child 0: the TextField must keep
          // the same Element across the keyboard opening.
          V13TextInput(
            key: const ValueKey('ob-email-field'),
            controller: _ctrl,
            focusNode: _focus,
            autofocus: true,
            hardShadow: true,
            keyboardType: TextInputType.emailAddress,
            textInputAction: _reviewer
                ? TextInputAction.next
                : TextInputAction.send,
            autofillHints: const [AutofillHints.email],
            autocorrect: false,
            enableSuggestions: false,
            hint: 'you@email.com',
            onSubmitted: (_) => _reviewer ? _pwFocus.requestFocus() : _send(),
          ),
          if (_reviewer) ...[
            const SizedBox(height: V13.gapMd),
            V13TextInput(
              key: const ValueKey('ob-email-password'),
              controller: _pw,
              focusNode: _pwFocus,
              hardShadow: true,
              obscureText: true,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              hint: ObCopy.reviewerPasswordLabel,
              onSubmitted: (_) => _reviewerSignIn(),
            ),
          ],
          const SizedBox(height: V13.gapSm),
          // One fixed slot for hint / error / typo / domain chips, so the
          // layout never jumps as the state changes.
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _statusSlotHeight),
            child: AnimatedSwitcher(
              duration: NuvoMotion.ctaFade,
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.centerLeft,
                children: [...previous, ?current],
              ),
              child: _status(typo, chips, valid),
            ),
          ),
          const _IntentToggle(),
        ],
      ),
      ctaLabel: _sending
          ? ObCopy.emailSending
          : _reviewer
          ? ObCopy.reviewerSignInCta
          : ObCopy.emailCta,
      ctaEnabled: valid && !_sending && (!_reviewer || _pw.text.isNotEmpty),
      onCta: _send,
      onBack: _sending ? null : flow.goBack,
    );
  }

  static const double _statusSlotHeight = 36;

  Widget _status(String? typo, List<String> chips, bool valid) {
    if (_error != null) {
      return Align(
        key: const ValueKey('status-error'),
        alignment: Alignment.centerLeft,
        child: Text(
          _error!,
          key: const ValueKey('ob-email-error'),
          style: V13.bodyStrong.copyWith(color: V13.danger),
        ),
      );
    }
    if (typo != null) {
      return Align(
        key: const ValueKey('status-typo'),
        alignment: Alignment.centerLeft,
        child: _TypoHint(domain: typo, onTap: () => _insertDomain(typo)),
      );
    }
    if (chips.isNotEmpty) {
      return Align(
        key: const ValueKey('status-chips'),
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: V13.gapSm,
          runSpacing: V13.gapSm,
          children: [
            for (final d in chips)
              _DomainChip(domain: d, onTap: () => _insertDomain(d)),
          ],
        ),
      );
    }
    if (!valid) {
      return Align(
        key: const ValueKey('status-hint'),
        alignment: Alignment.centerLeft,
        child: Text(
          ObCopy.emailDisabledHint,
          key: const ValueKey('ob-email-hint'),
          style: V13.caption,
        ),
      );
    }
    return const SizedBox.shrink(key: ValueKey('status-none'));
  }
}

class _DomainChip extends StatelessWidget {
  const _DomainChip({required this.domain, required this.onTap});

  final String domain;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return NuvoPressable(
      onTap: onTap,
      haptic: false,
      borderRadius: BorderRadius.circular(V13.radiusPill),
      shadow: V13.hardShadow(x: 0, y: 3),
      semanticLabel: domain,
      child: Container(
        key: ValueKey('ob-chip-$domain'),
        padding: const EdgeInsets.symmetric(
          horizontal: V13.gapLg,
          vertical: V13.gapSm,
        ),
        decoration: BoxDecoration(
          color: V13.card,
          borderRadius: BorderRadius.circular(V13.radiusPill),
          border: Border.all(color: V13.navy, width: V13.outline),
        ),
        child: Text(domain, style: V13.bodyStrong),
      ),
    );
  }
}

class _TypoHint extends StatelessWidget {
  const _TypoHint({required this.domain, required this.onTap});

  final String domain;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return NuvoPressable(
      onTap: onTap,
      haptic: false,
      semanticLabel: ObCopy.emailTypoHintFor(domain),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: V13.gapXs),
        child: Text(
          ObCopy.emailTypoHintFor(domain),
          key: const ValueKey('ob-email-typo'),
          style: V13.bodyStrong.copyWith(color: V13.blue),
        ),
      ),
    );
  }
}

/// "Have an account? Sign in" / "New to Nuvo? Create an account": flips the
/// auth intent in place (no navigation, nothing re-created).
class _IntentToggle extends ConsumerWidget {
  const _IntentToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signUp = ref.watch(authIntentProvider) == AuthIntent.signUp;
    return NuvoPressable(
      onTap: () {
        ref.read(authIntentProvider.notifier).state = signUp
            ? AuthIntent.signIn
            : AuthIntent.signUp;
      },
      semanticLabel: signUp ? ObCopy.emailHaveAccount : ObCopy.emailNewHere,
      child: SizedBox(
        key: const ValueKey('ob-intent-toggle'),
        height: 44,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            signUp ? ObCopy.emailHaveAccount : ObCopy.emailNewHere,
            style: V13.bodyStrong.copyWith(
              color: V13.blue,
              decoration: TextDecoration.underline,
              decorationColor: V13.blue,
            ),
          ),
        ),
      ),
    );
  }
}

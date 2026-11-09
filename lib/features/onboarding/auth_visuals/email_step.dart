import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics_service.dart';
import '../../../core/motion/motion.dart';
import '../../../core/v13/tokens.dart';
import '../../auth/data/auth_api.dart';
import '../../auth/presentation/auth_controller.dart';
import '../flow/onboarding_copy.dart';
import '../flow/onboarding_flow_controller.dart';
import '../flow/onboarding_step.dart';
import '../shell/onboarding_shell.dart';
import '../shell/onboarding_shell_controller.dart';
import 'email_utils.dart';
import 'player_pass.dart';

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
  bool _sending = false;
  bool _wasValid = false;
  String? _error;

  bool get _valid => ObEmail.isValid(_ctrl.text);

  // The store-review credential signs in with a password through
  // /auth/reviewer (same call as the v1 email screen), never an inbox code.
  bool get _reviewer =>
      isNuvoStoreDemoEmail(ObEmail.normalize(_ctrl.text));

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
    final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;
    final text = _ctrl.text;
    final valid = _valid;
    final typo = ObEmail.typoSuggestion(text);
    final chips = ObEmail.domainChips(text);

    return OnboardingShell(
      step: OnboardingStep.email,
      heroHeight: keyboardUp ? 112 : 280,
      hero: Column(
        children: [
          if (!keyboardUp)
            Padding(
              padding: const EdgeInsets.only(bottom: V13.gapMd),
              child: Text(ObCopy.emailStepCounter, style: V13.caption),
            ),
          Expanded(
            child: ObPlayerPass(
              email: text.trim(),
              stamp: valid ? ObStampState.ready : ObStampState.none,
              compact: keyboardUp,
              printing: _sending,
            ),
          ),
        ],
      ),
      title: ObCopy.emailTitle,
      subtitle: ObCopy.emailSub,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(ObCopy.emailFieldLabel, style: V13.bodyStrong),
          const SizedBox(height: V13.gapSm),
          SizedBox(
            height: 60,
            child: TextField(
              key: const ValueKey('ob-email-field'),
              controller: _ctrl,
              focusNode: _focus,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.send,
              autofillHints: const [AutofillHints.email],
              autocorrect: false,
              enableSuggestions: false,
              onSubmitted: (_) => _send(),
              style: V13.bodyStrong.copyWith(fontSize: 16),
              decoration: InputDecoration(
                filled: true,
                fillColor: V13.card,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: V13.gapLg,
                  vertical: 18,
                ),
                enabledBorder: _border(V13.navy),
                focusedBorder: _border(V13.blue),
                border: _border(V13.navy),
              ),
            ),
          ),
          if (_reviewer) ...[
            const SizedBox(height: V13.gapMd),
            Text(ObCopy.reviewerPasswordLabel, style: V13.bodyStrong),
            const SizedBox(height: V13.gapSm),
            SizedBox(
              height: 60,
              child: TextField(
                key: const ValueKey('ob-email-password'),
                controller: _pw,
                obscureText: true,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                onSubmitted: (_) => _reviewerSignIn(),
                style: V13.bodyStrong.copyWith(fontSize: 16),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: V13.card,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: V13.gapLg,
                    vertical: 18,
                  ),
                  enabledBorder: _border(V13.navy),
                  focusedBorder: _border(V13.blue),
                  border: _border(V13.navy),
                ),
              ),
            ),
          ],
          const SizedBox(height: V13.gapSm),
          if (_error != null)
            Text(
              _error!,
              key: const ValueKey('ob-email-error'),
              style: V13.bodyStrong.copyWith(color: V13.danger),
            )
          else if (typo != null)
            _TypoHint(
              domain: typo,
              onTap: () => _insertDomain(typo),
            )
          else if (!valid)
            Text(
              ObCopy.emailDisabledHint,
              key: const ValueKey('ob-email-hint'),
              style: V13.caption,
            ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: V13.gapMd),
            Wrap(
              spacing: V13.gapSm,
              runSpacing: V13.gapSm,
              children: [
                for (final d in chips)
                  _DomainChip(domain: d, onTap: () => _insertDomain(d)),
              ],
            ),
          ],
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

  OutlineInputBorder _border(Color c) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(V13.radiusButton),
    borderSide: BorderSide(color: c, width: V13.outlineThick),
  );
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

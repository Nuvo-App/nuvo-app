import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/motion.dart';
import '../../../core/v13/tokens.dart';
import '../../auth/data/auth_api.dart';
import '../../auth/presentation/auth_controller.dart';
import '../flow/onboarding_copy.dart';
import '../flow/onboarding_flow_controller.dart';
import '../flow/onboarding_step.dart';
import '../shell/onboarding_shell.dart';
import '../shell/onboarding_shell_controller.dart';
import 'ob_shake.dart';
import 'player_pass.dart';

enum _Phase { idle, verifying, verified, error, locked }

/// Keeps digits only and caps at six — covers paste ("482 915"), SMS/email
/// autofill (`oneTimeCode`) and normal typing alike.
class ObCodeFormatter extends TextInputFormatter {
  const ObCodeFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > ObCodeStep.length) {
      digits = digits.substring(0, ObCodeStep.length);
    }
    return TextEditingValue(
      text: digits,
      selection: TextSelection.collapsed(offset: digits.length),
    );
  }
}

/// S6 — "Check your email." Six code boxes over one real text field (so
/// paste, autofill and backspace behave natively), auto-submit on the 6th
/// digit, error shake, VERIFIED stamp, 30 s resend countdown. The OTP calls
/// are the existing `verifyEmailCode` / `startEmailAuth`. A verified code
/// pays +10 through the flow controller.
class ObCodeStep extends ConsumerStatefulWidget {
  const ObCodeStep({super.key});

  static const int length = 6;

  @override
  ConsumerState<ObCodeStep> createState() => _ObCodeStepState();
}

class _ObCodeStepState extends ConsumerState<ObCodeStep>
    with WidgetsBindingObserver {
  static const int _maxWrong = 5;

  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  final _shake = GlobalKey<ObShakeState>();

  _Phase _phase = _Phase.idle;
  String? _error;
  String? _note;
  int _wrong = 0;
  int _resendLeft = NuvoMotion.resendCooldownSeconds;
  int _lockLeft = 0;
  bool _resending = false;
  Timer? _clock;
  String? _clipboardCode;
  // Index the current fill started at — paste staggers from here.
  int _fillFrom = 0;

  String get _code => _ctrl.text;
  bool get _busy => _phase == _Phase.verifying || _phase == _Phase.verified;
  String get _email => ref.read(onboardingFlowProvider).email ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startClock();
    _readClipboard();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _readClipboard();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ── Clock: resend countdown + lockout ─────────────────────────────────

  void _startClock() {
    _clock?.cancel();
    _clock = Timer.periodic(NuvoMotion.clockTick, (t) {
      if (!mounted) return;
      setState(() {
        if (_resendLeft > 0) _resendLeft--;
        if (_lockLeft > 0) {
          _lockLeft--;
          if (_lockLeft == 0) {
            _wrong = 0;
            _phase = _Phase.idle;
            _error = null;
          }
        }
      });
      if (_resendLeft == 0 && _lockLeft == 0) t.cancel();
    });
  }

  Future<void> _readClipboard() async {
    String? code;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text ?? '';
      if (RegExp(r'^[\d\s-]{6,12}$').hasMatch(text)) {
        final digits = text.replaceAll(RegExp(r'\D'), '');
        if (digits.length == ObCodeStep.length) code = digits;
      }
    } catch (_) {
      code = null;
    }
    if (mounted && code != _clipboardCode) {
      setState(() => _clipboardCode = code);
    }
  }

  // ── Input ─────────────────────────────────────────────────────────────

  void _onChanged(String value) {
    final previous = _lastLength;
    _lastLength = value.length;
    setState(() {
      _error = null;
      _note = null;
      _fillFrom = value.length - previous > 1 ? previous : value.length - 1;
      if (_fillFrom < 0) _fillFrom = 0;
    });
    if (value.length == ObCodeStep.length) _verify();
  }

  int _lastLength = 0;

  void _fill(String code) {
    _ctrl.value = TextEditingValue(
      text: code,
      selection: TextSelection.collapsed(offset: code.length),
    );
    _onChanged(code);
  }

  // ── Verify ────────────────────────────────────────────────────────────

  Future<void> _verify() async {
    if (_busy || _phase == _Phase.locked || _code.length != ObCodeStep.length) {
      return;
    }
    final code = _code;
    final auth = ref.read(authControllerProvider.notifier);
    final flow = ref.read(onboardingFlowProvider.notifier);
    final shell = OnboardingShellScope.of(context);
    setState(() {
      _phase = _Phase.verifying;
      _error = null;
      _note = null;
    });
    try {
      await auth.verifyEmailCode(_email, code);
    } catch (e) {
      debugPrint('[ObCode] verify failed (${e.runtimeType})');
      if (!mounted) return;
      await _onVerifyFailed(e);
      return;
    }
    if (!mounted) return;
    setState(() => _phase = _Phase.verified);
    NuvoHaptics.medium();
    unawaited(NuvoHaptics.success());
    final account = ref.read(authControllerProvider).user?.email;
    if (account != null) await flow.attachAccount(account);
    await Future<void>.delayed(NuvoMotion.verifiedHold);
    final awarded = await flow.completeStep(OnboardingStep.code);
    if (awarded > 0) shell.award(awarded);
  }

  Future<void> _onVerifyFailed(Object e) async {
    if (isNetworkAuthError(e)) {
      setState(() {
        _phase = _Phase.idle;
        _error = ObCopy.authOffline;
      });
      return;
    }
    if (e is ApiException && e.statusCode >= 500) {
      setState(() {
        _phase = _Phase.idle;
        _error = ObCopy.codeServerSnag;
      });
      return;
    }
    if (e is! ApiException) {
      // The code was accepted but finishing sign-in failed.
      setState(() {
        _phase = _Phase.idle;
        _error = ObCopy.codeVerifyFailed;
      });
      return;
    }
    _wrong++;
    final lock = _wrong >= _maxWrong || e.statusCode == 429;
    setState(() {
      _phase = _Phase.error;
      _error = lock ? ObCopy.codeTooManyTries : ObCopy.codeError;
    });
    _shake.currentState?.shake();
    NuvoHaptics.heavy();
    await Future<void>.delayed(NuvoMotion.errorFlash);
    if (!mounted) return;
    _ctrl.clear();
    _lastLength = 0;
    setState(() {
      _phase = lock ? _Phase.locked : _Phase.idle;
      if (lock) _lockLeft = NuvoMotion.lockoutSeconds;
    });
    if (lock) _startClock();
  }

  // ── Resend / tips ─────────────────────────────────────────────────────

  Future<void> _resend() async {
    if (_resending || _resendLeft > 0 || _busy) return;
    final auth = ref.read(authControllerProvider.notifier);
    setState(() {
      _resending = true;
      _error = null;
    });
    try {
      await auth.startEmailAuth(_email);
      if (!mounted) return;
      _ctrl.clear();
      _lastLength = 0;
      setState(() {
        _note = ObCopy.codeNewSent;
        _resendLeft = NuvoMotion.resendCooldownSeconds;
      });
      _startClock();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = isNetworkAuthError(e)
            ? ObCopy.authOffline
            : e is ApiException && e.statusCode == 429
            ? ObCopy.emailRateLimited
            : ObCopy.codeResendFailed;
      });
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  void _change() {
    if (_busy) return;
    ref.read(onboardingFlowProvider.notifier).goTo(OnboardingStep.email);
  }

  Future<void> _showTips() async {
    final flow = ref.read(onboardingFlowProvider.notifier);
    final pick = await showModalBottomSheet<OnboardingStep>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _TipsSheet(),
    );
    if (pick != null) flow.goTo(pick);
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final flow = ref.read(onboardingFlowProvider.notifier);
    final email = ref.watch(onboardingFlowProvider.select((s) => s.email));
    final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;
    final locked = _phase == _Phase.locked;

    return OnboardingShell(
      step: OnboardingStep.code,
      heroHeight: keyboardUp ? 112 : 240,
      hero: ObPlayerPass(
        email: email ?? '',
        stamp: _phase == _Phase.verified
            ? ObStampState.verified
            : ObStampState.none,
        compact: keyboardUp,
      ),
      title: ObCopy.codeTitle,
      subtitle: ObCopy.codeSub,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  ObCopy.codeSentTo(email ?? 'your email'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: V13.caption,
                ),
              ),
              _TextAction(
                key: const ValueKey('ob-code-change'),
                label: ObCopy.codeChange,
                onTap: _busy ? null : _change,
              ),
            ],
          ),
          const SizedBox(height: V13.gapMd),
          ObShake(
            key: _shake,
            count: 3,
            child: _CodeBoxes(
              controller: _ctrl,
              focusNode: _focus,
              phase: _phase,
              readOnly: _busy || locked,
              fillFrom: _fillFrom,
              onChanged: _onChanged,
            ),
          ),
          const SizedBox(height: V13.gapMd),
          _StatusLine(
            verifying: _phase == _Phase.verifying,
            error: _error,
            note: _note,
            lockLeft: _lockLeft,
          ),
          if (_clipboardCode != null &&
              _code.isEmpty &&
              !_busy &&
              !locked) ...[
            const SizedBox(height: V13.gapSm),
            Align(
              alignment: Alignment.centerLeft,
              child: _PasteChip(
                code: _clipboardCode!,
                onTap: () => _fill(_clipboardCode!),
              ),
            ),
          ],
          const SizedBox(height: V13.gapLg),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _TextAction(
                key: const ValueKey('ob-code-tips'),
                label: ObCopy.codeResendLink,
                onTap: _showTips,
              ),
              _resendLeft > 0
                  ? Text(
                      ObCopy.codeResendIn(_resendLeft),
                      key: const ValueKey('ob-code-countdown'),
                      style: V13.bodyStrong.copyWith(color: V13.muted),
                    )
                  : _TextAction(
                      key: const ValueKey('ob-code-resend'),
                      label: ObCopy.codeResendNew,
                      onTap: _resending || _busy ? null : _resend,
                    ),
            ],
          ),
        ],
      ),
      ctaLabel: _phase == _Phase.verifying
          ? ObCopy.codeVerifying
          : ObCopy.codeVerifyCta,
      ctaEnabled: _code.length == ObCodeStep.length && !_busy && !locked,
      onCta: _verify,
      onBack: _busy ? null : flow.goBack,
    );
  }
}

class _CodeBoxes extends StatelessWidget {
  const _CodeBoxes({
    required this.controller,
    required this.focusNode,
    required this.phase,
    required this.readOnly,
    required this.fillFrom,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final _Phase phase;
  final bool readOnly;
  final int fillFrom;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([controller, focusNode]),
      builder: (context, _) {
        final code = controller.text;
        final active = focusNode.hasFocus && phase == _Phase.idle
            ? code.length.clamp(0, ObCodeStep.length - 1)
            : -1;
        return SizedBox(
          height: 64,
          child: Stack(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < ObCodeStep.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    _CodeBox(
                      index: i,
                      char: i < code.length ? code[i] : '',
                      active: i == active,
                      phase: phase,
                      delay: i >= fillFrom
                          ? NuvoMotion.pasteStagger * (i - fillFrom)
                          : Duration.zero,
                    ),
                  ],
                ],
              ),
              // The one real field: invisible, full-size, so taps focus it
              // and the OS keyboard/autofill/paste all target it.
              Positioned.fill(
                child: TextField(
                  key: const ValueKey('ob-code-field'),
                  controller: controller,
                  focusNode: focusNode,
                  autofocus: true,
                  readOnly: readOnly,
                  showCursor: false,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: const [ObCodeFormatter()],
                  onChanged: onChanged,
                  enableSuggestions: false,
                  autocorrect: false,
                  style: const TextStyle(color: Colors.transparent),
                  cursorColor: Colors.transparent,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    counterText: '',
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CodeBox extends StatelessWidget {
  const _CodeBox({
    required this.index,
    required this.char,
    required this.active,
    required this.phase,
    required this.delay,
  });

  final int index;
  final String char;
  final bool active;
  final _Phase phase;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final verified = phase == _Phase.verified;
    final error = phase == _Phase.error;
    final fill = verified
        ? V13.mint
        : error
        ? V13.coral.withValues(alpha: 0.35)
        : V13.card;
    final border = error
        ? V13.coral
        : active
        ? V13.blue
        : V13.navy;
    final Widget content = verified
        ? _Pop(
            key: ValueKey('check-$index'),
            delay: NuvoMotion.checkStagger * index,
            child: const Icon(Icons.check_rounded, size: 28, color: V13.navy),
          )
        : char.isEmpty
        ? const SizedBox.shrink()
        : _Pop(
            key: ValueKey('$index-$char'),
            delay: delay,
            child: Text(char, style: V13.hugeNumber.copyWith(fontSize: 28)),
          );
    return Flexible(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 52),
        child: Container(
          key: ValueKey('ob-code-box-$index'),
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(V13.radiusTile),
            border: Border.all(color: border, width: V13.outlineThick),
          ),
          child: content,
        ),
      ),
    );
  }
}

/// Scale-in (spring) with an optional timer-free start delay.
class _Pop extends StatefulWidget {
  const _Pop({super.key, required this.child, this.delay = Duration.zero});

  final Widget child;
  final Duration delay;

  @override
  State<_Pop> createState() => _PopState();
}

class _PopState extends State<_Pop> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: NuvoMotion.springDuration + widget.delay,
  );

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (NuvoMotion.reduceMotionOf(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = _c.duration!.inMicroseconds;
    final start = widget.delay.inMicroseconds / total;
    final curve = CurvedAnimation(
      parent: _c,
      curve: Interval(start, 1, curve: NuvoMotion.spring),
    );
    return AnimatedBuilder(
      animation: curve,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: curve.value.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.5 + 0.5 * curve.value, child: child),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.verifying,
    required this.error,
    required this.note,
    required this.lockLeft,
  });

  final bool verifying;
  final String? error;
  final String? note;
  final int lockLeft;

  @override
  Widget build(BuildContext context) {
    final String? text = verifying ? ObCopy.codeVerifying : error ?? note;
    final color = error != null
        ? V13.danger
        : verifying
        ? V13.muted
        : V13.blue;
    return SizedBox(
      height: 22,
      child: text == null
          ? null
          : Text(
              text,
              key: const ValueKey('ob-code-status'),
              textAlign: TextAlign.center,
              style: V13.bodyStrong.copyWith(color: color),
            ),
    );
  }
}

class _TextAction extends StatelessWidget {
  const _TextAction({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return NuvoPressable(
      onTap: onTap,
      enabled: onTap != null,
      semanticLabel: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: V13.gapSm),
        child: Text(
          label,
          style: V13.bodyStrong.copyWith(
            color: onTap == null ? V13.muted : V13.blue,
          ),
        ),
      ),
    );
  }
}

class _PasteChip extends StatelessWidget {
  const _PasteChip({required this.code, required this.onTap});

  final String code;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return NuvoPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(V13.radiusPill),
      shadow: V13.hardShadow(x: 0, y: 3),
      semanticLabel: ObCopy.codePaste(code),
      child: Container(
        key: const ValueKey('ob-paste-chip'),
        padding: const EdgeInsets.symmetric(
          horizontal: V13.gapLg,
          vertical: V13.gapSm,
        ),
        decoration: BoxDecoration(
          color: V13.card,
          borderRadius: BorderRadius.circular(V13.radiusPill),
          border: Border.all(color: V13.navy, width: V13.outline),
        ),
        child: Text(ObCopy.codePaste(code), style: V13.bodyStrong),
      ),
    );
  }
}

/// "Didn't get the code?" — tips plus the two escape hatches.
class _TipsSheet extends StatelessWidget {
  const _TipsSheet();

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    Widget tip(String t) => Padding(
      padding: const EdgeInsets.only(bottom: V13.gapSm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6, right: V13.gapSm),
            child: Icon(Icons.circle, size: 6, color: V13.navy),
          ),
          Expanded(child: Text(t, style: V13.body)),
        ],
      ),
    );
    return Container(
      padding: EdgeInsets.fromLTRB(
        V13.pagePad,
        V13.gapLg,
        V13.pagePad,
        V13.gapLg + bottom,
      ),
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
          Text(ObCopy.codeTipsTitle, style: V13.sectionHead),
          const SizedBox(height: V13.gapMd),
          tip(ObCopy.codeTipSpam),
          tip(ObCopy.codeTipEmail),
          const SizedBox(height: V13.gapSm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _TextAction(
                key: const ValueKey('ob-tip-change'),
                label: ObCopy.codeTipChangeEmail,
                onTap: () => Navigator.of(context).pop(OnboardingStep.email),
              ),
              _TextAction(
                key: const ValueKey('ob-tip-social'),
                label: ObCopy.codeTipSocial,
                onTap: () => Navigator.of(context).pop(OnboardingStep.signIn),
              ),
            ],
          ),
          const SizedBox(height: V13.gapSm),
          _TextAction(
            key: const ValueKey('ob-tip-done'),
            label: ObCopy.codeTipsDone,
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

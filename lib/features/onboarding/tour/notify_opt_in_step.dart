import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/motion.dart';
import '../../../core/v13/tokens.dart';
import '../../notifications/application/push_service.dart';
import '../flow/onboarding_copy.dart';
import '../flow/onboarding_flow_controller.dart';
import '../flow/onboarding_step.dart';
import '../shell/onboarding_shell_controller.dart';
import '../shell/xp_rail.dart';

/// Asks the OS for notification permission and reports whether alerts are
/// now allowed. Reuses the existing in-context permission code
/// ([PushService]); an undecided OS state prompts, an already-authorized one
/// counts as accepted, and denied / unavailable transports (simulator) count
/// as declined — declining costs nothing and never blocks the flow.
/// Overridable so tests never touch Firebase.
final notifyPermissionRequestProvider = Provider<Future<bool> Function()>((
  ref,
) {
  return () async {
    final push = ref.read(pushServiceProvider);
    try {
      final status = await push.notificationAuthorizationStatus();
      if (status == AuthorizationStatus.authorized ||
          status == AuthorizationStatus.provisional) {
        return true;
      }
      if (status == AuthorizationStatus.denied) return false;
      return await push.requestPermissionInContext();
    } catch (_) {
      return false;
    }
  };
});

/// S11 — Notification opt-in in context: a light bottom sheet (not a full
/// screen) over the nudge row the practice race just produced. "Turn on
/// notifications" triggers the iOS prompt (+5 XP when accepted); "Maybe
/// later" costs nothing and the ask returns after the first real race.
class ObNotifyOptInStep extends ConsumerStatefulWidget {
  const ObNotifyOptInStep({super.key});

  @override
  ConsumerState<ObNotifyOptInStep> createState() => _ObNotifyOptInStepState();
}

class _ObNotifyOptInStepState extends ConsumerState<ObNotifyOptInStep> {
  bool _busy = false;

  Future<void> _resolve({required bool ask}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final shell = OnboardingShellScope.of(context);
    final flow = ref.read(onboardingFlowProvider.notifier);
    var accepted = false;
    if (ask) {
      accepted = await ref.read(notifyPermissionRequestProvider)();
    }
    await flow.setNotifyOutcome(accepted ? 'accepted' : 'declined');
    final awarded = await flow.completeStep(OnboardingStep.notifyOptIn);
    if (awarded > 0) shell.award(awarded);
  }

  @override
  Widget build(BuildContext context) {
    final shell = OnboardingShellScope.of(context);
    return Scaffold(
      backgroundColor: V13.bg,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    V13.pagePad,
                    V13.gapMd,
                    V13.pagePad,
                    0,
                  ),
                  child: XpRail(controller: shell),
                ),
                const SizedBox(height: V13.gapSection),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: V13.pagePad),
                  child: NuvoFloat(child: _NudgeRow()),
                ),
              ],
            ),
          ),
          const Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(color: Color(0x5207152D)),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: NuvoEnter(
              child: _Sheet(busy: _busy, onResolve: _resolve),
            ),
          ),
        ],
      ),
    );
  }
}

/// The hero: the practice nudge row ("<racer> passed you"). Practice data,
/// labeled as such; never sent anywhere.
class _NudgeRow extends StatelessWidget {
  const _NudgeRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(V13.gapLg),
      decoration: BoxDecoration(
        color: V13.card,
        borderRadius: BorderRadius.circular(V13.radiusCard),
        border: Border.all(color: V13.navy, width: V13.outlineThick),
        boxShadow: V13.shadow6,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: V13.sky,
              shape: BoxShape.circle,
              border: Border.all(color: V13.navy, width: V13.outline),
            ),
            child: const Icon(Icons.person_rounded, color: V13.navy),
          ),
          const SizedBox(width: V13.gapMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ObCopy.arenaTourNudge(ObCopy.nuvoCrew),
                  style: V13.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  ObCopy.practiceTag,
                  style: V13.caption.copyWith(color: V13.muted),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: V13.gapMd,
              vertical: V13.gapSm,
            ),
            decoration: BoxDecoration(
              color: V13.coral,
              borderRadius: BorderRadius.circular(V13.radiusPill),
              border: Border.all(color: V13.navy, width: V13.outline),
            ),
            child: Text(ObCopy.arenaTourTakeBack, style: V13.label),
          ),
        ],
      ),
    );
  }
}

class _Sheet extends StatelessWidget {
  const _Sheet({required this.busy, required this.onResolve});

  final bool busy;
  final Future<void> Function({required bool ask}) onResolve;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        V13.pagePad,
        V13.gapXl,
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
          Text(ObCopy.notifyTitle, style: V13.title),
          const SizedBox(height: V13.gapXl),
          NuvoPressable(
            enabled: !busy,
            onTap: busy ? null : () => onResolve(ask: true),
            borderRadius: BorderRadius.circular(V13.radiusButton),
            shadow: V13.shadow4,
            semanticLabel: ObCopy.notifyCta,
            child: Container(
              key: const ValueKey('onboarding-cta'),
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: V13.blue,
                borderRadius: BorderRadius.circular(V13.radiusButton),
                border: Border.all(color: V13.navy, width: V13.outlineThick),
              ),
              child: Text(
                ObCopy.notifyCta,
                style: V13.buttonLabel.copyWith(color: V13.white),
              ),
            ),
          ),
          const SizedBox(height: V13.gapSm),
          TextButton(
            onPressed: busy ? null : () => onResolve(ask: false),
            child: Text(
              ObCopy.notifyLater,
              style: V13.bodyStrong.copyWith(color: V13.muted),
            ),
          ),
        ],
      ),
    );
  }
}

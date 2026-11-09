import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/motion.dart';
import '../../../core/v13/tokens.dart';
import '../flow/onboarding_copy.dart';
import '../flow/onboarding_flow_controller.dart';
import '../flow/onboarding_step.dart';
import 'cta_pop.dart';
import 'onboarding_shell_controller.dart';
import 'track_painter.dart';
import 'xp_rail.dart';

/// The one onboarding frame every step lives inside.
///
/// Spec (`docs/redesign/onboarding-v2-spec.md` §THE SHELL): the Track runs
/// behind everything, the XP rail (or 3 page dots pre-auth) rides the top,
/// one back square + Skip slot flank it, and the CTA is a fixed 56 px slot
/// with 16 px margins that NEVER moves — only its label changes — and it
/// docks above the keyboard with a spring.
///
/// Each step builds its own shell with its own hero/title/CTA; persistence
/// comes from [OnboardingShellController] (host-owned, scope-delivered), so
/// the track pan and rail fill continue across the swap instead of
/// restarting. Steps get XP into the rail with
/// `OnboardingShellScope.of(context).award(awarded)` after
/// `completeStep` returns the granted amount.
///
/// Public API (stable for Parts A–F):
/// ```dart
/// OnboardingShell(
///   step: OnboardingStep.email,
///   hero: ..., title: ..., subtitle: ..., body: ...,
///   ctaLabel: 'Send code', ctaEnabled: true, onCta: ...,
///   onBack: ..., onSkip: ...,
/// )
/// ```
class OnboardingShell extends StatelessWidget {
  const OnboardingShell({
    super.key,
    required this.step,
    required this.hero,
    required this.title,
    this.subtitle,
    this.body,
    required this.ctaLabel,
    this.ctaEnabled = true,
    this.onCta,
    this.onBack,
    this.onSkip,
    this.skipLabel = ObCopy.skip,
    this.background = V13.bg,
    this.titleColor,
    this.subtitleColor,
    this.showTrack = true,
    this.showRail,
    this.showDots,
    this.dotIndex,
    this.dotCount = 2,
    this.heroHeight = 320,
    this.fillHero = false,
  });

  /// The hero takes every pixel the title/body/CTA leave free (no scroll,
  /// no fixed [heroHeight]) — the pre-auth intros use it so the hero owns
  /// ~60% of the screen with no dead space under it.
  final bool fillHero;

  /// Height of the hero slot (Part B shrinks it while the keyboard is up).
  final double heroHeight;

  /// The step this frame renders — drives track/rail/dots defaults.
  final OnboardingStep step;

  /// The step's visual centerpiece (hero card, card fan, skeleton — the
  /// step owns it; the shell floats nothing itself).
  final Widget hero;

  final String title;
  final String? subtitle;

  /// Optional step content under the title (chips, fields, tiles).
  final Widget? body;

  /// The one obvious action — label-only changes across steps.
  final String ctaLabel;
  final bool ctaEnabled;
  final VoidCallback? onCta;

  /// Back square callback — null renders an empty 44 px slot (the layout
  /// never shifts whether back exists or not).
  final VoidCallback? onBack;

  /// Skip callback — null hides the slot entirely.
  final VoidCallback? onSkip;
  final String skipLabel;

  /// Page color — [V13.bg] everywhere except the full-bleed level-up.
  final Color background;

  /// Title/subtitle ink overrides — only the level-up step (blue canvas)
  /// needs them.
  final Color? titleColor;
  final Color? subtitleColor;

  /// Paint the Track. It only ever shows on post-auth XP-rail steps
  /// ([OnboardingStepX.showsTrack]) — pre-auth pages use dots or the bare
  /// rail, so no path runs behind their copy — and is off for the
  /// immersive level-up.
  final bool showTrack;

  /// Rail/dots overrides — defaults come from the step ([showsRail],
  /// [showsDots]) so a step only passes them to force chrome off.
  final bool? showRail;
  final bool? showDots;
  final int? dotIndex;
  final int dotCount;

  @override
  Widget build(BuildContext context) {
    final shell = OnboardingShellScope.of(context);
    final rail = showRail ?? step.showsRail;
    final dots = showDots ?? step.showsDots;
    final reduce = NuvoMotion.reduceMotionOf(context);

    return Scaffold(
      backgroundColor: background,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          if (showTrack && rail && step.showsTrack)
            TrackBackground(controller: shell),
          SafeArea(
            child: Column(
              children: [
                _TopBar(
                  step: step,
                  onBack: onBack,
                  onSkip: onSkip,
                  skipLabel: skipLabel,
                  rail: rail,
                  dots: dots,
                  dotIndex: dotIndex ?? step.dotIndex,
                  dotCount: dotCount,
                  shell: shell,
                ),
                Expanded(child: fillHero ? _filledBody() : _scrollBody(reduce)),
                _CtaDock(
                  label: ctaLabel,
                  enabled: ctaEnabled,
                  onTap: onCta,
                  reduce: reduce,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _text(int index, Widget child) => NuvoEnter(
    index: index,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: V13.pagePad),
      child: child,
    ),
  );

  List<Widget> _copyBlock() => [
    _text(1, Text(title, style: V13.title.copyWith(color: titleColor))),
    if (subtitle != null) ...[
      const SizedBox(height: V13.gapSm),
      _text(
        2,
        Text(
          subtitle!,
          style: V13.body.copyWith(color: subtitleColor ?? V13.muted),
        ),
      ),
    ],
  ];

  /// [fillHero] layout: the hero flexes to whatever the copy + CTA leave.
  Widget _filledBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _text(0, hero)),
        const SizedBox(height: V13.gapLg),
        ..._copyBlock(),
        if (body != null) ...[
          const SizedBox(height: V13.gapSm),
          _text(3, body!),
        ],
        const SizedBox(height: V13.gapSm),
      ],
    );
  }

  /// Default layout: fixed-height hero, copy, body, scrollable.
  Widget _scrollBody(bool reduce) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NuvoEnter(
            index: 0,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: V13.pagePad),
              child: AnimatedContainer(
                duration: reduce ? Duration.zero : NuvoMotion.springDuration,
                curve: NuvoMotion.spring,
                height: heroHeight,
                child: hero,
              ),
            ),
          ),
          const SizedBox(height: V13.gapXl),
          ..._copyBlock(),
          if (body != null) ...[
            const SizedBox(height: V13.gapLg),
            _text(3, body!),
          ],
          const SizedBox(height: V13.gapSection),
        ],
      ),
    );
  }
}

/// The step-advance idiom every stub uses: complete the step in the flow,
/// then send whatever XP it granted flying into the rail. The shell
/// controller is captured BEFORE the await — it outlives the step that's
/// about to be swapped out.
Future<void> obAdvance(
  BuildContext context,
  WidgetRef ref,
  OnboardingStep step,
) async {
  final shell = OnboardingShellScope.of(context);
  final awarded = await ref
      .read(onboardingFlowProvider.notifier)
      .completeStep(step);
  if (awarded > 0) shell.award(awarded);
}

/// Back square · rail/dots · Skip — the persistent chrome row.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.step,
    required this.onBack,
    required this.onSkip,
    required this.skipLabel,
    required this.rail,
    required this.dots,
    required this.dotIndex,
    required this.dotCount,
    required this.shell,
  });

  final OnboardingStep step;
  final VoidCallback? onBack;
  final VoidCallback? onSkip;
  final String skipLabel;
  final bool rail;
  final bool dots;
  final int dotIndex;
  final int dotCount;
  final OnboardingShellController shell;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        V13.gapLg,
        V13.gapMd,
        V13.gapLg,
        V13.gapSm,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: onBack == null ? null : _BackSquare(onTap: onBack!),
          ),
          Expanded(
            child: rail
                ? XpRail(controller: shell)
                : dots
                ? _Dots(index: dotIndex, count: dotCount)
                : const SizedBox.shrink(),
          ),
          SizedBox(
            width: 64,
            height: 44,
            child: onSkip == null
                ? null
                : Align(
                    alignment: Alignment.centerRight,
                    child: _SkipButton(label: skipLabel, onTap: onSkip!),
                  ),
          ),
        ],
      ),
    );
  }
}

class _BackSquare extends StatelessWidget {
  const _BackSquare({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return NuvoPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(V13.radiusTile),
      shadow: V13.hardShadow(x: 3, y: 3),
      semanticLabel: ObCopy.back,
      child: Container(
        decoration: BoxDecoration(
          color: V13.card,
          borderRadius: BorderRadius.circular(V13.radiusTile),
          border: Border.all(color: V13.navy, width: V13.outline),
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.arrow_back_rounded, size: 20, color: V13.navy),
      ),
    );
  }
}

class _SkipButton extends StatelessWidget {
  const _SkipButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return NuvoPressable(
      onTap: onTap,
      semanticLabel: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: V13.gapSm,
          vertical: V13.gapSm,
        ),
        child: Text(label, style: V13.bodyStrong.copyWith(color: V13.muted)),
      ),
    );
  }
}

/// The 3 pre-auth page dots — center of the chrome row where the rail sits
/// once it exists (spec: "Pre-auth: 3 page dots instead").
class _Dots extends StatelessWidget {
  const _Dots({required this.index, required this.count});

  final int index;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: NuvoMotion.springDuration,
            curve: NuvoMotion.spring,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == index ? 22 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == index ? V13.navy : V13.card,
              borderRadius: BorderRadius.circular(V13.radiusPill),
              border: Border.all(color: V13.navy, width: V13.outline),
            ),
          ),
      ],
    );
  }
}

/// The fixed CTA slot — 56 px high, 16 px side margins, identical geometry
/// on every step; docks above the keyboard with the spring. The label
/// cross-fades ([NuvoMotion.ctaFade]) — the slot itself never moves.
class _CtaDock extends StatelessWidget {
  const _CtaDock({
    required this.label,
    required this.enabled,
    required this.onTap,
    required this.reduce,
  });

  final String label;
  final bool enabled;
  final VoidCallback? onTap;
  final bool reduce;

  static const double height = 56;
  static const double sideMargin = 16;

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final interactive = enabled && onTap != null;
    return AnimatedPadding(
      duration: reduce ? Duration.zero : NuvoMotion.springDuration,
      curve: NuvoMotion.spring,
      padding: EdgeInsets.only(bottom: math.max(keyboard, 16.0)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: sideMargin),
        child: CtaPop(
          active: interactive,
          child: NuvoPressable(
            onTap: interactive ? onTap : null,
            enabled: interactive,
            borderRadius: BorderRadius.circular(V13.radiusButton),
            shadow: V13.shadow4,
            semanticLabel: label,
            child: Container(
              key: const ValueKey('onboarding-cta'),
              height: height,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: interactive ? V13.blue : V13.card,
                borderRadius: BorderRadius.circular(V13.radiusButton),
                border: Border.all(color: V13.navy, width: V13.outlineThick),
              ),
              child: AnimatedSwitcher(
                duration: NuvoMotion.ctaFade,
                child: Text(
                  label,
                  key: ValueKey(label),
                  style: V13.buttonLabel.copyWith(
                    color: interactive ? V13.white : V13.muted,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

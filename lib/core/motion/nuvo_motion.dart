import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// Onboarding-v2 motion language — every duration, curve and distance a
/// screen may need lives here so no onboarding file invents its own numbers.
///
/// Source: `docs/redesign/onboarding-v2-spec.md` §MOTION TOKENS.
///
/// NOTE: `lib/core/widgets/nuvo_motion.dart` is the older pre-v13 shell
/// motion file and defines a different `NuvoMotion`/`NuvoHaptics`/
/// `NuvoPressable`. The two libraries must never be imported into the same
/// file — onboarding v2 code uses this one only. (Where they overlap,
/// semantics come from `lib/core/v13/motion.dart`; see [NuvoHaptics].)
abstract final class NuvoMotion {
  // ── The one spring ────────────────────────────────────────────────────
  /// mass 1 · stiffness 380 · damping 22 → ~520 ms settle, 6–8% overshoot.
  /// Used for press release, toggles, number pops and entrances.
  static const SpringDescription springDescription = SpringDescription(
    mass: 1,
    stiffness: 380,
    damping: 22,
  );

  /// The spring as a Curve for tween/implicit animations — samples the real
  /// [springDescription] simulation over [springDuration].
  static const Curve spring = _NuvoSpringCurve();

  /// How long the spring is allowed to run when a Duration is required.
  static const Duration springDuration = Duration(milliseconds: 520);

  /// A live simulation for controllers that want real spring physics
  /// (`controller.animateWith(NuvoMotion.springSimulation(...))`).
  static SpringSimulation springSimulation({
    double start = 0,
    double end = 1,
    double velocity = 0,
  }) => SpringSimulation(springDescription, start, end, velocity);

  // ── Press down — every button/chip/tab/actionable row ─────────────────
  static const Duration pressDown = Duration(milliseconds: 90);
  static const Curve pressDownCurve = Curves.easeOut;

  /// Distance the surface sinks into its shadow plate.
  static const double pressSink = 3;

  /// Resting hard-shadow offset; on press it compresses to [pressShadowTo]
  /// (4 px plate − 3 px sink leaves 1 px showing).
  static const double pressShadowFrom = 4;
  static const double pressShadowTo = 1;

  // ── Entrance — spring from y+28, opacity 0 ────────────────────────────
  static const Duration enter = Duration(milliseconds: 480);
  static const double enterOffsetY = 28;
  static const Duration staggerStep = Duration(milliseconds: 70);
  static const int staggerMax = 5;

  /// Stagger delay for the [index]-th element, capped at [staggerMax].
  static Duration staggerFor(int index) =>
      staggerStep * index.clamp(0, staggerMax);

  // ── Exit ──────────────────────────────────────────────────────────────
  static const Duration exit = Duration(milliseconds: 260);
  static const Curve exitCurve = Curves.easeIn;
  static const double exitOffsetY = -12;
  static const double exitScale = 0.97;

  // ── Idle float — hero cards / avatar tokens / badges only ─────────────
  static const Duration floatPeriod = Duration(milliseconds: 3200);
  static const double floatAmplitude = 6;
  static const double floatRotationDeg = 1.2;

  /// Random phase window, in seconds (0–1.6) so floats don't synchronize.
  static const double floatPhaseMax = 1.6;

  /// Optional accelerometer parallax amplitude (px).
  static const double tiltParallax = 8;

  // ── XP fly — "+N" chip rises then curves into the rail ────────────────
  static const double xpFlyRise = 24;
  static const Duration xpFly = Duration(milliseconds: 600);
  static const Curve xpFlyCurve = Curves.easeInOutCubic;

  // ── Confetti — existing app confetti, brand colors ────────────────────
  static const Duration confetti = Duration(milliseconds: 1100);
  static const int confettiPieces = 40;

  // ── The Track — continuous background race path ───────────────────────
  /// Camera pan per step.
  static const Duration trackPan = Duration(milliseconds: 420);
  static const Curve trackPanCurve = Curves.easeInOutCubic;

  /// Foreground parallax factor vs the path's 1.0x.
  static const double trackParallax = 1.15;

  // ── Reduce motion ─────────────────────────────────────────────────────
  /// The one transition that survives reduce-motion: a plain cross-fade.
  static const Duration reduceMotionFade = Duration(milliseconds: 200);

  /// True when the OS wants motion off — drive every animation gate through
  /// this (MediaQuery.disableAnimations).
  static bool reduceMotionOf(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);

  // ── Misc onboarding timings ───────────────────────────────────────────
  /// CTA label-only cross-fade.
  static const Duration ctaFade = Duration(milliseconds: 180);

  /// S0: the launch logo holds before the flow takes over (Part A owns the
  /// real handoff; the stub uses this).
  static const Duration splashHold = Duration(milliseconds: 1200);

  // ── Auth visuals (Part B) — sheet, ticket, code boxes ─────────────────
  /// Error shake: [shakeDistance] px side to side over [shake].
  static const double shakeDistance = 6;
  static const Duration shake = Duration(milliseconds: 280);

  /// Coral error flash on the code boxes.
  static const Duration errorFlash = Duration(milliseconds: 600);

  /// Paste fills the six boxes with this stagger.
  static const Duration pasteStagger = Duration(milliseconds: 40);

  /// Success: boxes flip to checkmarks with this stagger.
  static const Duration checkStagger = Duration(milliseconds: 80);

  /// "VERIFIED" holds this long before the Track advances.
  static const Duration verifiedHold = Duration(milliseconds: 700);

  /// Ticket "print" lift while sending (px up, then back).
  static const double printLift = 12;

  /// Resend countdown: one tick, the server's send window, and the
  /// wrong-code lockout.
  static const Duration clockTick = Duration(seconds: 1);
  static const int resendCooldownSeconds = 30;
  static const int lockoutSeconds = 60;

  // ── Step transition (the flow host's AnimatedSwitcher builder) ────────
  /// Incoming content springs up from y+28 as it fades in; the outgoing
  /// child eases out upward (−12 px, scale .97). Under reduce-motion both
  /// directions collapse to the plain cross-fade. Direction is read from
  /// [animation.status] — the outgoing child's animation runs in reverse.
  static Widget stepTransition(Widget child, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, c) {
        final t = animation.value.clamp(0.0, 1.0);
        if (reduceMotionOf(context)) {
          return Opacity(opacity: t, child: c);
        }
        final leaving = animation.status == AnimationStatus.reverse;
        final dy = (leaving ? exitOffsetY : enterOffsetY) * (1 - t);
        final scale = leaving ? 1 - (1 - exitScale) * (1 - t) : 1.0;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, dy),
            child: Transform.scale(scale: scale, child: c),
          ),
        );
      },
    );
  }
}

/// The spec spring sampled as a curve: mass 1 / stiffness 380 / damping 22
/// integrated over [NuvoMotion.springDuration]. ~6–8% overshoot.
class _NuvoSpringCurve extends Curve {
  const _NuvoSpringCurve();

  static const double _seconds = 0.52;

  /// Stateless deterministic math — one shared simulation is safe to reuse.
  static final SpringSimulation _sim = SpringSimulation(
    NuvoMotion.springDescription,
    0,
    1,
    0,
  );

  @override
  double transform(double t) {
    if (t <= 0) return 0;
    if (t >= 1) return 1;
    return _sim.x(t * _seconds);
  }
}

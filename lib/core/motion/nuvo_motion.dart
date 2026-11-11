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

  /// Transition input lock: taps that would complete a freshly shown step are
  /// ignored this long (no accidental double-advance).
  static const Duration stepInputLock = Duration(milliseconds: 600);
  static const Curve exitCurve = Curves.easeIn;
  static const double exitOffsetY = -12;
  static const double exitScale = 0.97;

  // ── Idle float — hero cards / avatar tokens / badges only ─────────────
  static const Duration floatPeriod = Duration(milliseconds: 3200);
  // Hero art sits flat: no idle float anywhere (design rule, see AGENTS.md).
  static const double floatAmplitude = 0;
  // No tilt anywhere (design decision): float is vertical only.
  static const double floatRotationDeg = 0;

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

  // ── Level-up timeline (Part E, spec S15) ───────────────────────────────
  // Millisecond marks on one linear timeline; the screen derives every
  // segment from these so no timing is hard-coded in the step file.
  static const Duration levelUpScrim = Duration(milliseconds: 320);
  static const Curve levelUpScrimCurve = Curves.easeOut;
  static const Duration levelUpAvatarAt = Duration(milliseconds: 250);
  static const Duration levelUpFillAt = Duration(milliseconds: 600);
  static const Duration levelUpFill = Duration(milliseconds: 450);
  static const Curve levelUpFillCurve = Curves.easeIn;
  static const int levelUpFillTicks = 10;
  static const double levelUpRingStart = 0.96;
  static const Duration levelUpFlashAt = Duration(milliseconds: 1050);
  static const Duration levelUpShockwave = Duration(milliseconds: 600);
  static const Curve levelUpShockwaveCurve = Curves.easeOut;
  static const double levelUpShockwaveScale = 1.6;
  static const Duration levelUpNumberAt = Duration(milliseconds: 1100);
  static const Duration levelUpNumber = Duration(milliseconds: 700);
  static const Duration levelUpLettersAt = Duration(milliseconds: 1700);
  static const Duration levelUpLetterStagger = Duration(milliseconds: 40);
  static const Duration levelUpTilesAt = Duration(milliseconds: 2100);
  static const Duration levelUpCtaAt = Duration(milliseconds: 2600);

  /// The whole timeline (CTA has risen and settled).
  static const Duration levelUpTotal = Duration(milliseconds: 3200);

  /// Tap-anywhere speeds to the CTA only after this long (never a trap).
  static const Duration levelUpSkipAfter = Duration(milliseconds: 900);

  /// How fast a skip-ahead tap fast-forwards the timeline.
  static const Duration levelUpSkipRun = Duration(milliseconds: 360);

  /// Reward fetch ceiling — past it the spec constants render.
  static const Duration levelUpFetchTimeout = Duration(seconds: 8);

  /// CTA press: the blue floods out in a circle revealing the Arena.
  static const Duration levelUpFlood = Duration(milliseconds: 500);

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

  /// Typing pause before a live availability check fires (S7 username).
  static const Duration inputDebounce = Duration(milliseconds: 500);

  /// S9 "Your first race is ready" hold: no-input transition length.
  static const Duration firstRaceTransition = Duration(milliseconds: 2200);

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

  // ── Part A step timings (spec-mandated values, one name each) ─────────
  /// S1: the tap-duel race window (spec: "for 5s each tap moves your token").
  static const Duration duelWindow = Duration(seconds: 5);

  /// S1: pressing Next before the duel ends auto-plays it to the finish
  /// (spec: "the duel auto-plays and finishes in 1.5s").
  static const Duration duelAutoPlay = Duration(milliseconds: 1500);

  /// S1: the one-time hand pointer appears after this idle delay
  /// (spec: "Idle 3s: hand pointer taps once").
  static const Duration pointerIdle = Duration(seconds: 3);

  /// The hand pointer's single tap press length (spec: "700ms press" —
  /// shared with the tour engine's pointer).
  static const Duration pointerTap = Duration(milliseconds: 700);

  /// S2: one down-and-up rep of the skeleton squat loop.
  static const Duration squatRep = Duration(milliseconds: 1400);

  /// S3: cadence of the leaderboard points tick / row swap
  /// (spec: "every 2.4s points tick up").
  static const Duration boardTick = Duration(milliseconds: 2400);

  // ── Guided tour (lib/features/tour) ───────────────────────────────────
  /// "Skip tour" link appears after this long on a stop.
  static const Duration tourSkipAfter = Duration(seconds: 2);

  /// A target that never mounts within this window is skipped, never blocks.
  static const Duration tourTargetWait = Duration(milliseconds: 1500);

  /// Polling cadence while waiting for a target to mount / settle.
  static const Duration tourTargetPoll = Duration(milliseconds: 100);

  /// Hand pointer: taps once on arrival, then once more after this idle.
  static const Duration tourPointerIdle = Duration(seconds: 6);

  /// Off-screen target auto-scroll.
  static const Duration tourScroll = Duration(milliseconds: 400);
  static const Curve tourScrollCurve = Curves.easeInOutCubic;

  /// Pause between a finished stop and the next one appearing.
  static const Duration tourStopGap = Duration(milliseconds: 700);

  /// The scripted "passed you" beat after the first practice proof.
  static const Duration tourNudgeDelay = Duration(seconds: 3);

  /// How long an award / info chip stays on screen.
  static const Duration tourChipHold = Duration(milliseconds: 1800);

  /// Intro demos: one loop of a page's single animation.
  static const Duration introLoop = Duration(milliseconds: 4200);

  /// Login typewriter: type, hold, backspace, gap between phrases.
  static const Duration typeChar = Duration(milliseconds: 75);
  static const Duration deleteChar = Duration(milliseconds: 35);
  static const Duration typeHold = Duration(milliseconds: 2400);
  static const Duration typeGap = Duration(milliseconds: 350);
  static const Duration cursorBlink = Duration(milliseconds: 530);

  /// Login hero: one full race of the looping lane demo.
  static const Duration loginLoop = Duration(milliseconds: 6400);

  /// Scrim opacity (navy at 72%).
  static const double tourScrimOpacity = 0.72;

  /// Cutout padding around the target and the cutout's outline / shadow.
  static const double tourCutoutPad = 8;
  static const double tourCutoutOutline = 2.5;
  static const double tourCutoutShadow = 4;

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

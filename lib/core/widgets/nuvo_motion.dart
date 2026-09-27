import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Nuvo's shared motion language.
///
/// The goal is one physical feel everywhere: immediate response on touch,
/// a short confident move, a soft settle. Numbers, presses, tab switches,
/// and rank movement all read from these constants so screens don't each
/// invent their own timing.
abstract final class NuvoMotion {
  // ── Durations ─────────────────────────────────────────────────────────
  /// Finger-down response — fast enough to feel instant.
  static const Duration pressIn = Duration(milliseconds: 80);

  /// Release settle — soft return, not a snap.
  static const Duration pressOut = Duration(milliseconds: 220);

  /// Root tab switch between the five shell destinations.
  static const Duration tabSwitch = Duration(milliseconds: 250);

  /// Generic selection/activation settle (nav items, chips, toggles).
  static const Duration select = Duration(milliseconds: 200);

  /// Rank/row repositioning.
  static const Duration reorder = Duration(milliseconds: 300);

  // ── Travel ────────────────────────────────────────────────────────────
  /// Horizontal travel for a tab switch — subtle, subconscious.
  static const double tabTravel = 24;

  /// Vertical press translation for tappable surfaces. Sized to
  /// [AppShadows.hardSmall] (3px): a quiet surface drops exactly onto its
  /// shadow's resting spot, so the eye reads "pressed into place", never
  /// "shrunk".
  static const double pressTranslateY = 3;

  /// Depth a filled button travels on press — meets most of its 5px hard
  /// shadow (the residual stays visible via [shadowCompress]).
  static const double buttonPressDepth = 4;

  /// Fraction of a hard shadow's offset that disappears while pressed:
  /// offset × (1 − 0.6) — a 5px shadow keeps 2px of compressed depth, so the
  /// button visibly squeezes its shadow instead of flattening onto nothing.
  static const double shadowCompress = 0.6;

  /// Default press compression for cards and tappable surfaces.
  static const double pressScale = 0.97;

  // ── Curves ────────────────────────────────────────────────────────────
  /// The shared settle: strong ease-out — visibly moving by frame two,
  /// almost no bounce at the end. (Same curve as NuvoNumberFlow.)
  static const Curve settle = Cubic(0.22, 1, 0.36, 1);

  /// Restrained spring for selection moments — a hint of overshoot.
  static const Curve spring = Curves.easeOutBack;

  /// Quick in-curve for press-down response.
  static const Curve pressCurve = Curves.easeIn;
}

/// Centralized haptic vocabulary — call sites express intent, not platform
/// details. Intentionally short: haptics fire for meaningful physical
/// moments only, never on every tap.
abstract final class NuvoHaptics {
  /// Selection changes — nav destinations, chips, toggles.
  static void select() => HapticFeedback.selectionClick();

  /// Physical presses — primary CTAs, race start.
  static void press() => HapticFeedback.lightImpact();

  /// Meaningful confirmations — proof accepted, reaction landed,
  /// rank improvement.
  static void confirm() => HapticFeedback.mediumImpact();
}

/// The shared press interaction for buttons, cards, and chips.
///
/// Wraps any child in a tactile press: on finger-down the surface
/// translates down ([NuvoMotion.pressTranslateY]) and compresses slightly
/// ([NuvoMotion.pressScale]); on release it springs back. For surfaces with
/// a hard offset shadow, translating down reads as the shadow compressing —
/// the surface physically meets its shadow — without animating shadow
/// geometry (which is expensive to repaint).
///
/// Uses a controller rather than implicit animated widgets so a mid-press
/// cancel releases smoothly from the current position instead of jumping.
class NuvoPressable extends StatefulWidget {
  const NuvoPressable({
    super.key,
    required this.child,
    this.onTap,
    this.scale = NuvoMotion.pressScale,
    this.translateY = NuvoMotion.pressTranslateY,
    this.haptic = true,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// Pressed scale — use ~0.97 for cards, ~0.93 for chips/reactions.
  final double scale;

  /// How far the surface drops toward its shadow on press.
  final double translateY;

  /// Fire [NuvoHaptics.select] on tap.
  final bool haptic;

  final bool enabled;

  @override
  State<NuvoPressable> createState() => _NuvoPressableState();
}

class _NuvoPressableState extends State<NuvoPressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: NuvoMotion.pressIn,
    reverseDuration: NuvoMotion.pressOut,
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _down(TapDownDetails _) {
    if (!widget.enabled || widget.onTap == null) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _ctrl.value = 1;
    } else {
      _ctrl.forward();
    }
  }

  void _up() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _ctrl.value = 0;
      return;
    }
    // Release springs: easeOutBack dips the value just past 0 so the surface
    // lifts a hair above rest before settling — the "bounce off the floor".
    _ctrl.animateTo(
      0,
      duration: NuvoMotion.pressOut,
      curve: NuvoMotion.spring,
    );
  }

  void _tap() {
    if (widget.haptic) NuvoHaptics.select();
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final interactive = widget.enabled && widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: interactive ? _tap : null,
      onTapDown: interactive ? _down : null,
      onTapUp: (_) => _up(),
      onTapCancel: _up,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          final t = _ctrl.value;
          return Transform.translate(
            offset: Offset(0, widget.translateY * t),
            child: Transform.scale(
              scale: 1.0 - (1.0 - widget.scale) * t,
              child: child,
            ),
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// A short celebratory pop for small objects whose state just flipped —
/// reaction emoji, badges, check marks. Wraps [child] and plays
/// `1 → 1 + 0.2·intensity → 0.98 → 1` whenever [trigger] changes
/// (`Object?` — a bool for on/off, a value for count changes).
///
/// One-shot, ~260ms, no loop. Reduced motion: skips the pop entirely —
/// the state itself (color/count) already changed.
class NuvoPop extends StatefulWidget {
  const NuvoPop({
    super.key,
    required this.trigger,
    required this.child,
    this.intensity = 1.0,
  });

  /// Any value; the pop replays when it changes.
  final Object? trigger;

  final Widget child;

  /// Scales the pop's peak — 1.0 lands ~1.2, 0.5 lands ~1.1. Use a lower
  /// intensity for "undo" directions (removing a reaction).
  final double intensity;

  @override
  State<NuvoPop> createState() => _NuvoPopState();
}

class _NuvoPopState extends State<NuvoPop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: 1,
  );

  @override
  void didUpdateWidget(covariant NuvoPop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trigger == widget.trigger) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _ctrl.value = 1;
    } else {
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        // Two-phase: quick overshoot up to the peak (first 55%), then a
        // soft settle back through a hair of undershoot to rest.
        final t = _ctrl.value;
        final peak = 0.2 * widget.intensity;
        final scale = t < 0.55
            ? 1 + peak * Curves.easeOut.transform(t / 0.55)
            : 1 +
                peak -
                (peak + 0.02) *
                    NuvoMotion.settle.transform((t - 0.55) / 0.45);
        return Transform.scale(scale: scale, child: child);
      },
      child: widget.child,
    );
  }
}

/// Same-surface morph for stateful controls — `Add → Sent`,
/// `Accept → In crew`, `Join → Joined`. The slot animates its size while the
/// contents crossfade, so the transition reads as *one object changing
/// state* instead of widget A being replaced by widget B.
///
/// Key the morph on the semantic state ([stateKey]); children of different
/// states may be entirely different widgets (a button vs. a status chip) —
/// the footprint eases between their sizes rather than jumping.
class NuvoStateMorph extends StatelessWidget {
  const NuvoStateMorph({
    super.key,
    required this.stateKey,
    required this.child,
    this.duration = NuvoMotion.select,
  });

  final Object stateKey;
  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: duration,
      curve: NuvoMotion.settle,
      child: AnimatedSwitcher(
        duration: duration,
        switchInCurve: NuvoMotion.settle,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(animation),
            child: child,
          ),
        ),
        child: KeyedSubtree(key: ValueKey(stateKey), child: child),
      ),
    );
  }
}

/// A lightweight corrective nudge — "nope, not that way". Wraps [child]
/// and plays a short decaying horizontal wiggle whenever [trigger] changes
/// (same trigger contract as [NuvoPop]: an int counter or bool flip).
///
/// Use for low-level local corrections only — a stepper hitting its floor,
/// an impossible value, a failed lightweight validation. ~280ms, two and a
/// half damped cycles, never violent, no haptic. Reduced motion: skipped —
/// pair the same [trigger] with a border/color cue at the call site.
///
/// NOT for serious errors (backend failures need a message), not for
/// camera-readiness states (those must stay readable).
class NuvoShake extends StatefulWidget {
  const NuvoShake({
    super.key,
    required this.trigger,
    required this.child,
    this.amplitude = 5,
  });

  final Object? trigger;
  final Widget child;

  /// Peak horizontal displacement in px. 5 is the correction nudge; keep it
  /// small — the shake should read "refused", not "alarm".
  final double amplitude;

  @override
  State<NuvoShake> createState() => _NuvoShakeState();
}

class _NuvoShakeState extends State<NuvoShake>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    value: 1,
  );

  @override
  void didUpdateWidget(covariant NuvoShake oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trigger == widget.trigger) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _ctrl.value = 1;
    } else {
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final t = _ctrl.value;
        // Damped sine — two and a half wiggles decaying to zero.
        final dx =
            math.sin(t * math.pi * 5) * (1 - t) * widget.amplitude;
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: widget.child,
    );
  }
}

/// The root-tab container for the main shell.
///
/// Wired in `router.dart` as the `navigatorContainerBuilder` of the
/// `StatefulShellRoute` — [children] are the five branch Navigators, all of
/// which stay mounted (state-preserving: scroll offsets, carousels, text
/// input, and in-flight screen state survive switching away and back).
///
/// On an index change the incoming destination slides in from the
/// direction of travel (a rightward tab arrives from the right) while the
/// outgoing one slides off the opposite edge — a ~24px, 250ms move that
/// reads as physical continuity, not a page replacement. Hidden branches
/// are Offstage + TickerMode-disabled + excluded from focus, so they cost
/// no frames and can't hold the keyboard while invisible.
class NuvoTabStack extends StatefulWidget {
  const NuvoTabStack({
    super.key,
    required this.index,
    required this.children,
  });

  /// The visible branch index.
  final int index;

  /// One widget per branch, ordered to match the shell's destination order.
  final List<Widget> children;

  @override
  State<NuvoTabStack> createState() => _NuvoTabStackState();
}

class _NuvoTabStackState extends State<NuvoTabStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: NuvoMotion.tabSwitch,
    value: 1,
  );

  late int _current = widget.index;
  int _previous = -1;

  @override
  void didUpdateWidget(covariant NuvoTabStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index == widget.index) return;
    _previous = _current;
    _current = widget.index;
    if (MediaQuery.disableAnimationsOf(context)) {
      _ctrl.value = 1;
    } else {
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final direction = _previous < 0
        ? 0.0
        : (_current > _previous ? 1.0 : -1.0);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = NuvoMotion.settle.transform(_ctrl.value);
        final animating = _ctrl.isAnimating;
        return Stack(
          fit: StackFit.expand,
          children: [
            for (var i = 0; i < widget.children.length; i++)
              _slot(i, t, direction, animating),
          ],
        );
      },
    );
  }

  Widget _slot(int i, double t, double direction, bool animating) {
    final isCurrent = i == _current;
    final isLeaving = animating && i == _previous;
    final visible = isCurrent || isLeaving;

    Widget child = Focus(
      canRequestFocus: visible,
      child: Offstage(
        offstage: !visible,
        child: TickerMode(enabled: visible, child: widget.children[i]),
      ),
    );

    if (isCurrent && animating) {
      child = Transform.translate(
        offset: Offset(direction * NuvoMotion.tabTravel * (1 - t), 0),
        child: Opacity(opacity: 0.2 + 0.8 * t, child: child),
      );
    } else if (isLeaving) {
      // The outgoing tab fades early and slides opposite the direction of
      // travel; IgnorePointer keeps it from stealing taps mid-flight.
      child = IgnorePointer(
        child: Transform.translate(
          offset: Offset(-direction * NuvoMotion.tabTravel * t, 0),
          child: Opacity(
            opacity: (1 - t / 0.6).clamp(0.0, 1.0),
            child: child,
          ),
        ),
      );
    }
    return child;
  }
}

/// FLIP-style reorder primitive for leaderboard-style rows.
///
/// When the order of [children] changes (keys moving between positions),
/// each moved row slides from its old vertical position to the new one —
/// #3 → #2 visibly rises instead of teleporting. Children MUST carry a
/// [Key]; unkeyed children render statically.
///
/// Rows are laid out by a normal [Column] (any height, any content). After
/// every layout the widget records each child's position; on the next order
/// change it animates the delta to zero. Presentation only — it consumes
/// whatever order the parent passes; it never sorts or re-ranks.
///
/// Not yet wired into screens — Agents 2/3 should apply this where a list's
/// row order follows server truth (standings, crew lists).
class NuvoReorderColumn extends StatefulWidget {
  const NuvoReorderColumn({
    super.key,
    required this.children,
    this.duration = NuvoMotion.reorder,
    this.mainAxisSize = MainAxisSize.max,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  final List<Widget> children;
  final Duration duration;
  final MainAxisSize mainAxisSize;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  State<NuvoReorderColumn> createState() => _NuvoReorderColumnState();
}

class _NuvoReorderColumnState extends State<NuvoReorderColumn> {
  final Map<Key, GlobalKey> _slots = {};
  final Map<Key, double> _tops = {};
  final Map<Key, double> _deltas = {};
  final Set<Key> _entering = {};
  List<Key> _lastOrder = const [];

  GlobalKey _slotFor(Key key) => _slots.putIfAbsent(key, GlobalKey.new);

  void _capture() {
    for (final entry in _slots.entries) {
      final box = entry.value.currentContext?.findRenderObject();
      if (box is RenderBox && box.hasSize) {
        _tops[entry.key] = box.localToGlobal(Offset.zero).dy;
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _lastOrder = _orderOf(widget.children);
    WidgetsBinding.instance.addPostFrameCallback((_) => _capture());
  }

  List<Key> _orderOf(List<Widget> children) => [
        for (final w in children)
          if (w.key != null) w.key!,
      ];

  @override
  void didUpdateWidget(covariant NuvoReorderColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    final order = _orderOf(widget.children);
    if (order == _lastOrder) return;
    _lastOrder = order;
    final previous = Map<Key, double>.of(_tops);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _capture();
      var changed = false;
      for (final key in order) {
        final before = previous[key];
        final after = _tops[key];
        if (before != null && after != null && before != after) {
          _deltas[key] = before - after;
          changed = true;
        } else if (before == null && _lastOrder.isNotEmpty) {
          // Newly arrived key — it slides up and fades in instead of
          // materializing; the slots around it get a move delta above.
          _entering.add(key);
          changed = true;
        }
      }
      if (changed) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: widget.mainAxisSize,
      crossAxisAlignment: widget.crossAxisAlignment,
      children: [
        for (final child in widget.children)
          _ReorderShift(
            key: _slotFor(child.key ?? ValueKey(child)),
            delta: _deltas[child.key] ?? 0,
            entering: _entering.contains(child.key),
            duration: widget.duration,
            onSettled: () {
              _deltas.remove(child.key);
              _entering.remove(child.key);
            },
            child: child,
          ),
      ],
    );
  }
}

/// One row inside [NuvoReorderColumn]: starts translated by [delta]
/// (old − new position) and eases to zero. An [entering] row has no old
/// position — it rises 14px while fading in.
class _ReorderShift extends StatefulWidget {
  const _ReorderShift({
    super.key,
    required this.delta,
    required this.entering,
    required this.duration,
    required this.onSettled,
    required this.child,
  });

  final double delta;
  final bool entering;
  final Duration duration;
  final VoidCallback onSettled;
  final Widget child;

  @override
  State<_ReorderShift> createState() => _ReorderShiftState();
}

class _ReorderShiftState extends State<_ReorderShift>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1,
  );
  double _from = 0;
  bool _entering = false;
  bool _reducedMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Inherited widgets can't be read in initState; this runs right after
    // and still before the first build, so entering rows offset correctly
    // from their first frame.
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    _maybeRun();
  }

  @override
  void didUpdateWidget(covariant _ReorderShift oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeRun();
  }

  void _maybeRun() {
    if (_reducedMotion) {
      _ctrl.value = 1;
      widget.onSettled();
      return;
    }
    if (widget.entering) {
      if (!_entering) {
        _entering = true;
        _ctrl.forward(from: 0).whenComplete(widget.onSettled);
      }
      return;
    }
    if (widget.delta == 0 || widget.delta == _from) return;
    _from = widget.delta;
    _ctrl.forward(from: 0).whenComplete(widget.onSettled);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final eased = NuvoMotion.settle.transform(_ctrl.value);
        final dy = widget.entering
            ? 14 * (1 - eased)
            : _from * (1 - eased);
        final opacity = widget.entering ? eased : 1.0;
        return Transform.translate(
          offset: Offset(0, dy),
          child: Opacity(opacity: opacity, child: child),
        );
      },
      child: widget.child,
    );
  }
}

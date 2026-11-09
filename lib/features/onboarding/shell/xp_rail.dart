import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../core/motion/motion.dart';
import '../../../core/v13/tokens.dart';
import '../flow/xp_table.dart';
import 'onboarding_shell_controller.dart';

/// The XP rail — outlined bar between the Level 1 and Level 2 badges.
///
/// Spec (`docs/redesign/onboarding-v2-spec.md` §XP RAIL): outlined bar,
/// level badges at both ends, fill springs forward as XP lands. The rail
/// reads [OnboardingShellController.displayedXp] so its fill grows exactly
/// when a "+N" chip lands in it — [award] on the controller is the only way
/// XP is ever added (the +N flight IS the spec's XP moment).
class XpRail extends StatefulWidget {
  const XpRail({super.key, required this.controller});

  final OnboardingShellController controller;

  @override
  State<XpRail> createState() => _XpRailState();
}

class _XpRailState extends State<XpRail> {
  final GlobalKey _barKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _register();
  }

  @override
  void didUpdateWidget(XpRail old) {
    super.didUpdateWidget(old);
    _register();
  }

  @override
  void dispose() {
    if (widget.controller.railRect != null) {
      widget.controller.railRect = null;
    }
    super.dispose();
  }

  /// Hands the controller this rail's global bounds — the fly-chip's
  /// destination. Refreshed after every layout so rotations/resizes keep
  /// the flight target true.
  void _register() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ro = _barKey.currentContext?.findRenderObject() as RenderBox?;
      if (ro == null || !ro.hasSize) return;
      widget.controller.railRect = ro.localToGlobal(Offset.zero) & ro.size;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final xp = widget.controller.displayedXp;
        final frac = (xp / OnboardingXp.total).clamp(0.0, 1.0);
        return Row(
          children: [
            const _LevelBadge(label: '1', reached: true),
            const SizedBox(width: 8),
            Expanded(
              child: _RailBar(key: _barKey, fraction: frac, xp: xp),
            ),
            const SizedBox(width: 8),
            _LevelBadge(label: '2', reached: xp >= OnboardingXp.total),
          ],
        );
      },
    );
  }
}

class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.label, required this.reached});

  final String label;
  final bool reached;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: reached ? V13.navy : V13.card,
        shape: BoxShape.circle,
        border: Border.all(color: V13.navy, width: V13.outline),
      ),
      child: Text(
        label,
        style: V13.label.copyWith(color: reached ? V13.white : V13.muted),
      ),
    );
  }
}

class _RailBar extends StatelessWidget {
  const _RailBar({super.key, required this.fraction, required this.xp});

  final double fraction;
  final int xp;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 20,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: BoxDecoration(
              color: V13.card,
              borderRadius: BorderRadius.circular(V13.radiusPill),
              border: Border.all(color: V13.navy, width: V13.outline),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(3),
            child: Align(
              alignment: Alignment.centerLeft,
              // The spring fill — grows when a +N chip lands in the rail.
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(end: fraction),
                duration: NuvoMotion.springDuration,
                curve: NuvoMotion.spring,
                builder: (context, value, _) => FractionallySizedBox(
                  widthFactor: value,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: V13.blue,
                      borderRadius: BorderRadius.circular(V13.radiusPill),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Center(
            child: Text(
              '$xp XP',
              style: V13.label.copyWith(
                color: xp > 0 ? V13.navy : V13.muted,
                fontSize: 9,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The "+N" flight layer — mounted once by the flow host, above everything.
/// Consumes [OnboardingShellController]'s pending flights: a chip rises
/// 24 px off the CTA, then curves 600 ms into the rail (ease-in-out cubic);
/// on arrival the rail's fill grows. Reduce-motion skips the flight — the
/// XP just lands.
class XpFlyOverlay extends StatefulWidget {
  const XpFlyOverlay({super.key, required this.controller});

  final OnboardingShellController controller;

  @override
  State<XpFlyOverlay> createState() => _XpFlyOverlayState();
}

class _XpFlyOverlayState extends State<XpFlyOverlay>
    with TickerProviderStateMixin {
  final List<_Flight> _flights = [];

  /// Frames to keep waiting for a rail before giving the chip up — covers
  /// the step transition so the new step's rail is always the target.
  static const int _waitFrames = 90;
  int _waited = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_pump);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_pump);
    for (final f in _flights) {
      f.ctrl.dispose();
    }
    super.dispose();
  }

  void _pump() {
    if (NuvoMotion.reduceMotionOf(context)) {
      int? n;
      while ((n = widget.controller.nextPendingFly()) != null) {
        widget.controller.arriveXp(n!);
      }
      return;
    }
    if (widget.controller.pendingFlyCount == 0) {
      _waited = 0;
      return;
    }
    final target = widget.controller.railRect?.center;
    if (target == null) {
      // The rail that should catch this chip is still mounting — wait a
      // beat, then land the XP without a flight if it never shows.
      if (++_waited <= _waitFrames) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _pump());
      } else {
        _waited = 0;
        widget.controller.dropPendingFly();
      }
      return;
    }
    _waited = 0;
    final xp = widget.controller.nextPendingFly();
    if (xp == null) return;
    _launch(xp, target);
  }

  void _launch(int xp, Offset target) {
    final size = MediaQuery.sizeOf(context);
    final start = Offset(size.width / 2, size.height - 132);
    final ctrl = AnimationController(vsync: this, duration: NuvoMotion.xpFly);
    final flight = _Flight(ctrl: ctrl, xp: xp, start: start, target: target);
    ctrl.addStatusListener((status) {
      if (status != AnimationStatus.completed) return;
      widget.controller.arriveXp(xp);
      setState(() {
        _flights.remove(flight);
      });
      ctrl.dispose();
    });
    _flights.add(flight);
    ctrl.forward();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            for (final f in _flights)
              AnimatedBuilder(
                animation: f.ctrl,
                builder: (context, _) {
                  final t = NuvoMotion.xpFlyCurve.transform(f.ctrl.value);
                  // Phase 1 (first 20%): rise 24 px off the CTA. Phase 2:
                  // quadratic curve from the risen point into the rail.
                  final risen = f.start - const Offset(0, NuvoMotion.xpFlyRise);
                  final tt = ((t - 0.2) / 0.8).clamp(0.0, 1.0);
                  final pos = t < 0.2
                      ? Offset(
                          f.start.dx,
                          f.start.dy - NuvoMotion.xpFlyRise * (t / 0.2),
                        )
                      : _quad(risen, _control(risen, f.target), f.target, tt);
                  return Positioned(
                    left: pos.dx - 24,
                    top: pos.dy - 14,
                    child: _FlyChip(xp: f.xp),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  static Offset _control(Offset a, Offset b) =>
      Offset((a.dx + b.dx) / 2 + 40, math.min(a.dy, b.dy) - 60);

  static Offset _quad(Offset a, Offset c, Offset b, double t) {
    final mt = 1 - t;
    return Offset(
      mt * mt * a.dx + 2 * mt * t * c.dx + t * t * b.dx,
      mt * mt * a.dy + 2 * mt * t * c.dy + t * t * b.dy,
    );
  }
}

class _Flight {
  _Flight({
    required this.ctrl,
    required this.xp,
    required this.start,
    required this.target,
  });

  final AnimationController ctrl;
  final int xp;
  final Offset start;
  final Offset target;
}

class _FlyChip extends StatelessWidget {
  const _FlyChip({required this.xp});

  final int xp;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: V13.card,
        borderRadius: BorderRadius.circular(V13.radiusPill),
        border: Border.all(color: V13.navy, width: V13.outline),
        boxShadow: V13.hardShadow(x: 2, y: 2),
      ),
      child: Text('+$xp', style: V13.numberSm.copyWith(color: V13.blue)),
    );
  }
}

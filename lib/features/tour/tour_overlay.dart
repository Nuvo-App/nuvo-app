// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/motion.dart';
import '../../core/v13/tokens.dart';
import '../../core/v13/widgets/v13_tab_bar.dart';
import '../auth/presentation/auth_controller.dart';
import '../onboarding/data/onboarding_v2_store.dart';
import '../onboarding/tour/notify_opt_in_step.dart';
import 'tour_anchors.dart';
import 'tour_controller.dart';
import 'tour_engine.dart';
import 'tour_fixtures.dart' show kTourBotName;
import 'tour_flags.dart';
import 'tour_geometry.dart';
import 'tour_script.dart';

/// Mounts the tour above the Navigator (one line in the MaterialApp builder,
/// like FakeDataPillLayer). Renders only [child] unless the feature flag is
/// on; with it on, keeps the controller in step with auth + the router and
/// draws the stage while the tour is active.
class TourOverlayLayer extends ConsumerStatefulWidget {
  const TourOverlayLayer({super.key, required this.child, this.router});

  final Widget child;

  /// Followed for the current shell location. Tests omit it and drive
  /// [tourLocationProvider] directly.
  final GoRouter? router;

  @override
  ConsumerState<TourOverlayLayer> createState() => _TourOverlayLayerState();
}

class _TourOverlayLayerState extends ConsumerState<TourOverlayLayer> {
  @override
  void initState() {
    super.initState();
    widget.router?.routerDelegate.addListener(_pushLocation);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _pushLocation();
      _sync();
    });
  }

  @override
  void dispose() {
    widget.router?.routerDelegate.removeListener(_pushLocation);
    super.dispose();
  }

  void _pushLocation() {
    final router = widget.router;
    if (router == null || !mounted) return;
    String path;
    try {
      path = router.routerDelegate.currentConfiguration.uri.path;
    } catch (_) {
      return;
    }
    // Defer: the delegate can notify mid-build.
    scheduleMicrotask(() {
      if (mounted) ref.read(tourLocationProvider.notifier).state = path;
    });
  }

  Future<void> _sync() async {
    if (!ref.read(tourFeatureEnabledProvider)) return;
    final user = ref.read(authControllerProvider).user;
    final v2 = ref.read(onboardingV2StoreProvider);
    await v2.ensureLoaded();
    if (!mounted) return;
    final graduated =
        user != null &&
        user.onboardingComplete &&
        tourGraduatedV2(v2, user.email);
    await ref
        .read(tourControllerProvider.notifier)
        .sync(email: user?.email, graduated: graduated);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      authControllerProvider.select(
        (s) => '${s.user?.id}:${s.user?.onboardingComplete}',
      ),
      (_, _) => _sync(),
    );
    if (!ref.watch(tourFeatureEnabledProvider)) return widget.child;
    return Stack(
      children: [
        widget.child,
        const Positioned.fill(child: TourStage()),
      ],
    );
  }
}

/// The stage: scrim + cutout, bubble, hand pointer, skip link, chips and the
/// notification sheet. Draws nothing unless a beat is on stage.
class TourStage extends ConsumerStatefulWidget {
  const TourStage({super.key});

  @override
  ConsumerState<TourStage> createState() => _TourStageState();
}

class _TourStageState extends ConsumerState<TourStage>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  bool _live = true; // false while this element is deactivated

  Rect? _target; // overlay-local rect of the spotlighted widget
  Duration? _waitStart;
  String _viewKey = '';
  bool _scrolled = false;
  TourView _view = TourView.hidden;
  Timer? _skipTimer;
  bool _skipVisible = false;

  @override
  void initState() {
    super.initState();
    _ticker.muted = true;
    _ticker.start();
  }

  @override
  void deactivate() {
    _live = false;
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _live = true;
  }

  @override
  void dispose() {
    _skipTimer?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  Rect? _globalRect(TourView v) {
    if (v.phase == TourPhase.dock) {
      final key = TourAnchors.dockSlot(v.dockIndex ?? -1);
      return _rectOfKey(key);
    }
    final anchor = v.anchor;
    return anchor == null ? null : TourAnchors.rectOf(anchor);
  }

  Rect? _rectOfKey(GlobalKey? key) {
    final box = key?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _onTick(Duration elapsed) {
    if (!mounted || !_live || !_view.spotlights) return;
    final beat = ref.read(tourControllerProvider).beat;
    final global = _globalRect(_view);
    if (global == null) {
      _waitStart ??= elapsed;
      if (elapsed - _waitStart! >= NuvoMotion.tourTargetWait && beat != null) {
        _ticker.muted = true;
        ref.read(tourControllerProvider.notifier).targetMissing(beat);
      }
      if (_target != null) setState(() => _target = null);
      return;
    }
    _waitStart = null;
    final me = context.findRenderObject();
    if (me is! RenderBox || !me.hasSize) return;
    final local = me.globalToLocal(global.topLeft) & global.size;
    if (!_scrolled &&
        _view.phase == TourPhase.target &&
        tourTargetOffscreen(
          global,
          screen: me.size,
          top: MediaQuery.paddingOf(context).top,
          bottom: V13TabBar.bottomPadding(context),
        )) {
      _scrolled = true;
      final ctx = TourAnchors.keyOf(_view.anchor!).currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: NuvoMotion.reduceMotionOf(context)
              ? Duration.zero
              : NuvoMotion.tourScroll,
          curve: NuvoMotion.tourScrollCurve,
          alignment: 0.4,
        );
      }
    }
    if (_target != local) setState(() => _target = local);
  }

  void _armSkip() {
    if (_skipVisible || _skipTimer != null) return;
    _skipTimer = Timer(NuvoMotion.tourSkipAfter, () {
      if (mounted) setState(() => _skipVisible = true);
    });
  }

  void _disarmSkip() {
    _skipTimer?.cancel();
    _skipTimer = null;
    _skipVisible = false;
  }

  @override
  Widget build(BuildContext context) {
    final tour = ref.watch(tourControllerProvider);
    final location = ref.watch(tourLocationProvider);
    final enabled = ref.watch(tourFeatureEnabledProvider);
    final live = enabled && tour.active;
    final view = live ? resolveTourView(tour.beat, location) : TourView.hidden;

    final key = '${tour.beat}:${view.phase.name}';
    if (key != _viewKey) {
      _viewKey = key;
      _target = null;
      _waitStart = null;
      _scrolled = false;
    }
    _view = view;
    _ticker.muted = !view.spotlights;

    if (view.phase == TourPhase.hidden && !live) _disarmSkip();
    if (view.phase != TourPhase.hidden) _armSkip();

    final children = <Widget>[];
    final media = MediaQuery.of(context);
    final screen = media.size;

    if (view.spotlights) {
      final target = _target;
      if (target != null) {
        final radius = view.phase == TourPhase.dock
            ? target.height / 2
            : (view.stop?.targetRadius ?? 16);
        final cutout = tourCutout(target, targetRadius: radius);
        children.add(
          _SpotlightScrim(
            key: const ValueKey('tour-scrim'),
            hole: cutout,
            reduce: NuvoMotion.reduceMotionOf(context),
          ),
        );
        // Observes the one real tap on the target without taking it.
        children.add(
          Positioned.fromRect(
            rect: cutout.outerRect,
            child: Listener(
              key: const ValueKey('tour-target-listener'),
              behavior: HitTestBehavior.translucent,
              onPointerUp: (_) => _targetTapped(tour.beat, view),
            ),
          ),
        );
        children.add(_bubble(view, cutout, screen, media.padding, tour.beat));
        if (!NuvoMotion.reduceMotionOf(context)) {
          children.add(
            _HandPointer(
              key: ValueKey('tour-hand-$_viewKey'),
              at: target.center,
            ),
          );
        }
      }
    } else if (view.phase == TourPhase.done) {
      children.add(
        const _SpotlightScrim(key: ValueKey('tour-scrim'), hole: null),
      );
      children.add(_doneBubble());
    } else if (view.phase == TourPhase.sheet) {
      children.add(
        const _SpotlightScrim(
          key: ValueKey('tour-scrim'),
          hole: null,
          light: true,
        ),
      );
      children.add(
        const Align(
          alignment: Alignment.bottomCenter,
          child: TourNotifySheet(),
        ),
      );
    }

    if (view.phase != TourPhase.hidden &&
        view.phase != TourPhase.sheet &&
        view.phase != TourPhase.done &&
        _skipVisible) {
      children.add(
        Positioned(
          top: media.padding.top + V13.gapSm,
          right: V13.pagePad,
          child: NuvoEnter(child: _SkipLink(onTap: _skip)),
        ),
      );
    }

    final chip = live ? tour.chip : null;
    if (chip != null) {
      children.add(
        Positioned(
          top: media.padding.top + V13.gapLg,
          left: 0,
          right: 0,
          child: Center(
            child: _AwardChip(key: ValueKey('chip-${chip.id}'), chip: chip),
          ),
        ),
      );
    }

    if (children.isEmpty) return const SizedBox.shrink();
    return Material(
      type: MaterialType.transparency,
      child: Stack(fit: StackFit.expand, children: children),
    );
  }

  void _skip() => ref.read(tourControllerProvider.notifier).skip();

  void _targetTapped(String? beat, TourView view) {
    final stop = view.stop;
    if (stop == null || view.phase != TourPhase.target) return;
    if (stop.completeOnTap && beat == stop.id) {
      ref.read(tourControllerProvider.notifier).completeBeat(stop.id);
    }
  }

  Widget _bubble(
    TourView view,
    RRect cutout,
    Size screen,
    EdgeInsets safe,
    String? beat,
  ) {
    final width = math.min(screen.width - 2 * 16, 340.0);
    final placement = placeTourBubble(
      cutout: cutout.outerRect,
      screen: screen,
      bubble: Size(width, 190),
      safe: safe,
    );
    final stop = view.stop;
    final isButton =
        view.phase == TourPhase.target && stop?.advance == TourAdvance.button;
    return Positioned.fill(
      child: CustomSingleChildLayout(
        delegate: _BubbleDelegate(
          placement: placement,
          cutout: cutout.outerRect,
          safe: safe,
        ),
        child: TourBubble(
          key: ValueKey('tour-bubble-$_viewKey'),
          width: width,
          copy: view.copy,
          counter: view.counter,
          side: placement.side,
          tailX: placement.tailX,
          buttonLabel: isButton ? stop?.buttonLabel : null,
          onButton: isButton && stop != null
              ? () => ref
                    .read(tourControllerProvider.notifier)
                    .completeBeat(stop.id)
              : null,
          onClose: () => ref.read(tourControllerProvider.notifier).close(),
        ),
      ),
    );
  }

  Widget _doneBubble() {
    return Center(
      child: TourBubble(
        key: const ValueKey('tour-bubble-done'),
        width: 300,
        copy: kTourDone,
        side: null,
        buttonLabel: 'Done',
        onButton: () => ref.read(tourControllerProvider.notifier).finish(),
        onClose: () => ref.read(tourControllerProvider.notifier).finish(),
      ),
    );
  }
}

class _BubbleDelegate extends SingleChildLayoutDelegate {
  _BubbleDelegate({
    required this.placement,
    required this.cutout,
    required this.safe,
  });

  final TourBubblePlacement placement;
  final Rect cutout;
  final EdgeInsets safe;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final below = placement.side == TourBubbleSide.below;
    final y = below
        ? placement.rect.top
        : math.max(safe.top + 16, cutout.top - 14 - childSize.height);
    return Offset(placement.rect.left, y);
  }

  @override
  bool shouldRelayout(_BubbleDelegate old) =>
      old.placement.rect != placement.rect ||
      old.placement.side != placement.side ||
      old.cutout != cutout;
}

// ── Scrim ────────────────────────────────────────────────────────────────

/// Navy 72% scrim with a rounded cutout, 2.5px navy outline and a 4px hard
/// shadow. Absorbs every touch except inside the cutout, which falls through
/// to the real UI underneath.
class _SpotlightScrim extends StatelessWidget {
  const _SpotlightScrim({
    super.key,
    required this.hole,
    this.light = false,
    this.reduce = false,
  });

  final RRect? hole;
  final bool light;
  final bool reduce;

  @override
  Widget build(BuildContext context) {
    final hole = this.hole;
    if (hole == null) return _ScrimLeaf(hole: null, light: light);
    return TweenAnimationBuilder<RRect?>(
      tween: _RRectTween(end: hole),
      duration: reduce ? Duration.zero : NuvoMotion.trackPan,
      curve: NuvoMotion.trackPanCurve,
      builder: (context, value, _) => _ScrimLeaf(hole: value, light: light),
    );
  }
}

class _RRectTween extends Tween<RRect?> {
  _RRectTween({super.end}) : super(begin: end);

  @override
  RRect? lerp(double t) => RRect.lerp(begin, end, t) ?? end;
}

class _ScrimLeaf extends LeafRenderObjectWidget {
  const _ScrimLeaf({required this.hole, required this.light});
  final RRect? hole;
  final bool light;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderTourScrim(hole: hole, light: light);

  @override
  void updateRenderObject(BuildContext context, RenderTourScrim ro) {
    ro
      ..hole = hole
      ..light = light;
  }
}

@visibleForTesting
class RenderTourScrim extends RenderBox {
  RenderTourScrim({RRect? hole, bool light = false})
    : _hole = hole,
      _light = light;

  RRect? _hole;
  bool _light;

  RRect? get hole => _hole;
  set hole(RRect? v) {
    if (v == _hole) return;
    _hole = v;
    markNeedsPaint();
  }

  set light(bool v) {
    if (v == _light) return;
    _light = v;
    markNeedsPaint();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    final h = _hole;
    if (h != null && h.contains(position)) return false;
    result.add(BoxHitTestEntry(this, position));
    return true;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    final rect = offset & size;
    final alpha = _light ? 0.32 : NuvoMotion.tourScrimOpacity;
    final scrim = Paint()..color = V13.navy.withValues(alpha: alpha);
    final h = _hole?.shift(offset);
    if (h == null) {
      canvas.drawRect(rect, scrim);
      return;
    }
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(rect)
      ..addRRect(h);
    canvas.drawPath(path, scrim);
    // Hard 4px shadow under the cutout edge, then the outline.
    final shadow = Path.combine(
      PathOperation.difference,
      Path()..addRRect(h.shift(const Offset(0, NuvoMotion.tourCutoutShadow))),
      Path()..addRRect(h),
    );
    canvas.drawPath(shadow, Paint()..color = V13.navy);
    canvas.drawRRect(
      h,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = NuvoMotion.tourCutoutOutline
        ..color = V13.navy,
    );
  }
}

// ── Bubble ───────────────────────────────────────────────────────────────

/// White outlined bubble: coach chip, optional counter, max 3 lines of copy,
/// an optional button and a close square. [side] places the tail (null: none).
class TourBubble extends StatelessWidget {
  const TourBubble({
    super.key,
    required this.width,
    required this.copy,
    required this.side,
    this.tailX = 0,
    this.counter,
    this.buttonLabel,
    this.onButton,
    this.onClose,
  });

  final double width;
  final String copy;
  final int? counter;
  final TourBubbleSide? side;
  final double tailX;
  final String? buttonLabel;
  final VoidCallback? onButton;
  final VoidCallback? onClose;

  static const double tail = 10;

  @override
  Widget build(BuildContext context) {
    final reduce = NuvoMotion.reduceMotionOf(context);
    final dir = side == TourBubbleSide.above ? 1.0 : -1.0;
    final body = Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(
        V13.gapLg,
        V13.gapMd,
        V13.gapMd,
        V13.gapLg,
      ),
      decoration: BoxDecoration(
        color: V13.card,
        borderRadius: BorderRadius.circular(V13.radiusCard),
        border: Border.all(color: V13.navy, width: V13.outlineThick),
        boxShadow: V13.shadow4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _CoachChip(),
              const SizedBox(width: V13.gapSm),
              Expanded(
                child: counter == null
                    ? const SizedBox.shrink()
                    : Text(
                        tourCounterLabel(counter!),
                        key: const ValueKey('tour-counter'),
                        style: V13.caption,
                        maxLines: 1,
                      ),
              ),
              NuvoPressable(
                key: const ValueKey('tour-close'),
                onTap: onClose,
                semanticLabel: 'Close tour',
                child: const Padding(
                  padding: EdgeInsets.all(V13.gapXs),
                  child: Icon(Icons.close_rounded, size: 20, color: V13.navy),
                ),
              ),
            ],
          ),
          const SizedBox(height: V13.gapSm),
          Padding(
            padding: const EdgeInsets.only(right: V13.gapSm),
            child: Text(
              copy,
              key: const ValueKey('tour-copy'),
              style: V13.bodyStrong.copyWith(fontSize: 15, height: 1.35),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (buttonLabel != null) ...[
            const SizedBox(height: V13.gapMd),
            _BubbleButton(label: buttonLabel!, onTap: onButton),
          ],
        ],
      ),
    );
    final withTail = side == null
        ? body
        : Stack(
            clipBehavior: Clip.none,
            children: [
              body,
              Positioned(
                left: (tailX - tail).clamp(
                  V13.gapLg,
                  width - V13.gapLg - 2 * tail,
                ),
                top: side == TourBubbleSide.below ? -tail - 1 : null,
                bottom: side == TourBubbleSide.above ? -tail - 1 : null,
                child: CustomPaint(
                  size: const Size(2 * tail, tail),
                  painter: _TailPainter(pointsUp: side == TourBubbleSide.below),
                ),
              ),
            ],
          );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: reduce ? NuvoMotion.reduceMotionFade : NuvoMotion.enter,
      curve: reduce ? Curves.linear : NuvoMotion.spring,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(
            0,
            reduce ? 0 : dir * NuvoMotion.enterOffsetY * (1 - t),
          ),
          child: child,
        ),
      ),
      child: withTail,
    );
  }
}

class _CoachChip extends StatelessWidget {
  const _CoachChip();

  @override
  Widget build(BuildContext context) => Container(
    width: 28,
    height: 28,
    alignment: Alignment.center,
    decoration: const BoxDecoration(color: V13.navy, shape: BoxShape.circle),
    child: Text(
      'M',
      style: V13.bodyStrong.copyWith(
        color: V13.card,
        fontSize: 14,
        fontWeight: FontWeight.w800,
        height: 1,
      ),
    ),
  );
}

class _TailPainter extends CustomPainter {
  const _TailPainter({required this.pointsUp});
  final bool pointsUp;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    if (pointsUp) {
      path
        ..moveTo(0, size.height)
        ..lineTo(size.width / 2, 0)
        ..lineTo(size.width, size.height);
    } else {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width / 2, size.height)
        ..lineTo(size.width, 0);
    }
    canvas.drawPath(path, Paint()..color = V13.card);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = V13.outlineThick
        ..strokeJoin = StrokeJoin.round
        ..color = V13.navy,
    );
    // Hide the bubble outline where the tail joins it.
    final y = pointsUp ? size.height : 0.0;
    canvas.drawLine(
      Offset(V13.outlineThick, y),
      Offset(size.width - V13.outlineThick, y),
      Paint()
        ..strokeWidth = V13.outlineThick + 1
        ..color = V13.card,
    );
  }

  @override
  bool shouldRepaint(_TailPainter old) => old.pointsUp != pointsUp;
}

class _BubbleButton extends StatelessWidget {
  const _BubbleButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => NuvoPressable(
    key: const ValueKey('tour-bubble-button'),
    onTap: onTap,
    shadow: V13.shadow3,
    borderRadius: BorderRadius.circular(V13.radiusButton),
    semanticLabel: label,
    child: Container(
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: V13.blue,
        borderRadius: BorderRadius.circular(V13.radiusButton),
        border: Border.all(color: V13.navy, width: V13.outlineThick),
      ),
      child: Text(label, style: V13.bodyStrong.copyWith(color: V13.card)),
    ),
  );
}

class _SkipLink extends StatelessWidget {
  const _SkipLink({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => NuvoPressable(
    key: const ValueKey('tour-skip'),
    onTap: onTap,
    semanticLabel: 'Skip tour',
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: V13.gapSm,
        vertical: V13.gapSm,
      ),
      child: Text(
        'Skip tour',
        style: V13.bodyStrong.copyWith(
          color: V13.card,
          decoration: TextDecoration.underline,
          decorationColor: V13.card,
        ),
      ),
    ),
  );
}

// ── Hand pointer ─────────────────────────────────────────────────────────

/// A hand that taps its target once (700ms press), waits 6s, taps once more,
/// then goes away. No looping, no glow, no pulsing.
class _HandPointer extends StatefulWidget {
  const _HandPointer({super.key, required this.at});
  final Offset at;

  @override
  State<_HandPointer> createState() => _HandPointerState();
}

class _HandPointerState extends State<_HandPointer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: NuvoMotion.pointerTap,
  );
  Timer? _timer;
  int _taps = 0;
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    _ctrl; // build the controller now so dispose never creates it
    _timer = Timer(NuvoMotion.enter, _tap);
  }

  Future<void> _tap() async {
    if (!mounted) return;
    setState(() => _taps++);
    await _ctrl.forward(from: 0);
    if (!mounted) return;
    if (_taps >= 2) {
      setState(() => _gone = true);
      return;
    }
    _timer = Timer(NuvoMotion.tourPointerIdle, _tap);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_gone || _taps == 0) return const SizedBox.shrink();
    return Positioned(
      left: widget.at.dx - 10,
      top: widget.at.dy - 4,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, child) {
            final press = math.sin(math.pi * _ctrl.value);
            return Transform.scale(
              scale: 1 - 0.18 * press,
              alignment: Alignment.topLeft,
              child: child,
            );
          },
          child: const Icon(
            Icons.touch_app_rounded,
            key: ValueKey('tour-hand'),
            size: 44,
            color: V13.card,
            shadows: [Shadow(color: V13.navy, offset: Offset(0, 3))],
          ),
        ),
      ),
    );
  }
}

// ── Award chip ───────────────────────────────────────────────────────────

class _AwardChip extends StatefulWidget {
  const _AwardChip({super.key, required this.chip});
  final TourChip chip;

  @override
  State<_AwardChip> createState() => _AwardChipState();
}

class _AwardChipState extends State<_AwardChip> {
  bool _show = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(NuvoMotion.tourChipHold, () {
      if (mounted) setState(() => _show = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();
    final reduce = NuvoMotion.reduceMotionOf(context);
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: reduce ? NuvoMotion.reduceMotionFade : NuvoMotion.xpFly,
        curve: NuvoMotion.xpFlyCurve,
        builder: (context, t, child) => Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, reduce ? 0 : NuvoMotion.xpFlyRise * (t - 1)),
            child: child,
          ),
        ),
        child: Container(
          key: const ValueKey('tour-chip'),
          padding: const EdgeInsets.symmetric(
            horizontal: V13.gapLg,
            vertical: V13.gapSm,
          ),
          decoration: BoxDecoration(
            color: V13.navy,
            borderRadius: BorderRadius.circular(V13.radiusPill),
            border: Border.all(color: V13.card, width: V13.outline),
          ),
          child: Text(
            widget.chip.text,
            style: V13.bodyStrong.copyWith(color: V13.card),
          ),
        ),
      ),
    );
  }
}

// ── Notification sheet (S11) ─────────────────────────────────────────────

/// Light bottom sheet drawn by the stage (the overlay sits above the
/// Navigator, so it carries its own). Hero: the "passed you" nudge row.
class TourNotifySheet extends ConsumerStatefulWidget {
  const TourNotifySheet({super.key});

  @override
  ConsumerState<TourNotifySheet> createState() => _TourNotifySheetState();
}

class _TourNotifySheetState extends ConsumerState<TourNotifySheet> {
  bool _busy = false;

  Future<void> _resolve({required bool ask}) async {
    if (_busy) return;
    setState(() => _busy = true);
    var accepted = false;
    if (ask) accepted = await ref.read(notifyPermissionRequestProvider)();
    if (!mounted) return;
    await ref
        .read(tourControllerProvider.notifier)
        .notifyResolved(accepted: accepted);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return NuvoEnter(
      child: Container(
        key: const ValueKey('tour-notify-sheet'),
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(
          V13.pagePad,
          V13.gapMd,
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
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: V13.divider,
                  borderRadius: BorderRadius.circular(V13.radiusPill),
                ),
              ),
            ),
            const SizedBox(height: V13.gapLg),
            const _NudgeRow(),
            const SizedBox(height: V13.gapSm),
            Text(
              kTourLesson,
              style: V13.caption,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: V13.gapLg),
            Text(
              kTourNotifyTitle,
              key: const ValueKey('tour-notify-title'),
              style: V13.cardTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: V13.gapLg),
            NuvoPressable(
              key: const ValueKey('tour-notify-accept'),
              onTap: _busy ? null : () => _resolve(ask: true),
              shadow: V13.shadow3,
              borderRadius: BorderRadius.circular(V13.radiusButton),
              semanticLabel: 'Turn on notifications',
              child: Container(
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: V13.blue,
                  borderRadius: BorderRadius.circular(V13.radiusButton),
                  border: Border.all(color: V13.navy, width: V13.outlineThick),
                ),
                child: Text(
                  'Turn on notifications',
                  style: V13.bodyStrong.copyWith(color: V13.card),
                ),
              ),
            ),
            const SizedBox(height: V13.gapSm),
            NuvoPressable(
              key: const ValueKey('tour-notify-later'),
              onTap: _busy ? null : () => _resolve(ask: false),
              semanticLabel: 'Maybe later',
              child: Container(
                height: 44,
                alignment: Alignment.center,
                child: Text(
                  'Maybe later',
                  style: V13.bodyStrong.copyWith(color: V13.muted),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NudgeRow extends StatelessWidget {
  const _NudgeRow();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(V13.gapMd),
    decoration: BoxDecoration(
      color: V13.bg,
      borderRadius: BorderRadius.circular(V13.radiusTileLg),
      border: Border.all(color: V13.navy, width: V13.outline),
    ),
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
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
                '$kTourBotName passed you',
                style: V13.bodyStrong,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              Text('Practice', style: V13.caption),
            ],
          ),
        ),
        Text(
          'Take it back',
          style: V13.bodyStrong.copyWith(color: V13.blue, fontSize: 14),
        ),
      ],
    ),
  );
}

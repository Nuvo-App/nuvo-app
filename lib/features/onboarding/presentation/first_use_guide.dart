import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../auth/data/auth_models.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/first_use_store.dart';

enum FirstRaceGuideStep {
  idle,
  competeStart,
  composerName,
  composerActivity,
  composerGoal,
  composerRacers,
  composerReview,
  raceDetail,
  verifySetup,
  complete,
}

final firstRaceGuideProvider = StateProvider<FirstRaceGuideStep>(
  (ref) => FirstRaceGuideStep.idle,
);

/// Temporary in-session flag used by the demo account to replay the complete
/// first-launch experience without destroying its authenticated session.
final demoReplayProvider = StateProvider<bool>((ref) => false);

/// The one place the store-review demo experience is reset.
///
/// Called on every cold launch that restores the canonical App Review account
/// (splash) and on every fresh reviewer sign-in (email auth), so the account
/// always re-walks the deterministic first-use sequence: Nuvo story from
/// page 0 → notification education → Arena → first-race guide. Both call
/// sites funnel through here instead of scattering account checks across
/// screens.
///
/// Reset scope — Nuvo-owned EXPERIENCE state only: the replay flag (armed so
/// the route guard keeps the account inside the story), the armed guide
/// step, this account's persisted guide completion, and the install-scoped
/// education flags (notification prompt owed, camera primer, intro). Never
/// touched: the session, server-owned flags (onboardingComplete stays
/// complete — the replay drives the story via [demoReplayProvider], not by
/// un-completing the account), race data, and OS permission state, which
/// cannot be reset and is re-consulted live by the education step anyway.
/// [read] accepts `Ref.read`, `WidgetRef.read`, or `ProviderContainer.read` —
/// callers in the guard, splash, and auth screens all satisfy it.
Future<void> resetDemoExperienceForColdLaunch(
  T Function<T>(ProviderListenable<T>) read,
  AuthUser user,
) async {
  if (!isNuvoStoreDemoEmail(user.email)) return;
  // Provider flags first — the route guard can evaluate the moment auth
  // state publishes, so the replay must already be armed before the store
  // writes yield.
  read(demoReplayProvider.notifier).state = true;
  read(firstRaceGuideProvider.notifier).state = FirstRaceGuideStep.idle;
  final store = read(firstUseStoreProvider);
  await store.ensureLoaded();
  await store.resetDemoExperience(user.email);
}

abstract final class FirstRaceGuideKeys {
  static final competeStart = GlobalKey(debugLabel: 'guide-compete-start');
  static final composerName = GlobalKey(debugLabel: 'guide-composer-name');
  static final composerActivity = GlobalKey(
    debugLabel: 'guide-composer-activity',
  );
  static final composerGoal = GlobalKey(debugLabel: 'guide-composer-goal');
  static final composerRacers = GlobalKey(debugLabel: 'guide-composer-racers');
  static final composerReview = GlobalKey(debugLabel: 'guide-composer-review');

  /// The real continue CTA on each composer page — the coach retargets these
  /// once the page's input is satisfied.
  static final composerNameCta = GlobalKey(debugLabel: 'guide-name-cta');
  static final composerActivityCta = GlobalKey(
    debugLabel: 'guide-activity-cta',
  );
  static final composerGoalCta = GlobalKey(debugLabel: 'guide-goal-cta');
  static final composerRacersCta = GlobalKey(debugLabel: 'guide-racers-cta');
  static final racePrimary = GlobalKey(debugLabel: 'guide-race-primary');
  static final verifyBegin = GlobalKey(debugLabel: 'guide-verify-begin');
}

/// Which composer page the coach is reasoning about. Mapped from the
/// composer's internal stage — targets derive from the page actually on
/// screen plus live form state, not from how far the guide has progressed.
enum ComposerGuidePage { name, activity, train, goal, racers, review }

/// One resolved coach placement: which real control to spotlight and what to
/// say about it.
class CoachSpec {
  const CoachSpec({
    required this.targetKey,
    required this.eyebrow,
    required this.title,
    this.body,
  });

  final GlobalKey targetKey;
  final String eyebrow;
  final String title;
  final String? body;
}

/// Derives the coach spec for the composer's CURRENT page.
///
/// [inputReady] means the page's input action is already satisfied (name
/// typed, movement picked, goal set, racers chosen). When true the coach
/// retargets the page's real continue CTA — teaching WHAT to enter and then
/// HOW to continue. Back navigation re-derives the right substep for free:
/// return to a completed page and the coach points at its CTA again.
///
/// Returns null for `train` — Teach Nuvo owns that stage's guidance.
CoachSpec? composerCoachSpec(
  ComposerGuidePage page, {
  required bool inputReady,
  bool teachMode = false,
  bool manualGoal = false,
}) {
  return switch (page) {
    ComposerGuidePage.name =>
      inputReady
          ? CoachSpec(
              targetKey: FirstRaceGuideKeys.composerNameCta,
              eyebrow: 'NEXT',
              title: 'Pick the activity.',
              body: 'Tap Choose activity.',
            )
          : CoachSpec(
              targetKey: FirstRaceGuideKeys.composerName,
              eyebrow: 'NAME IT',
              title: 'Give your race a name.',
            ),
    ComposerGuidePage.activity =>
      inputReady
          ? CoachSpec(
              targetKey: FirstRaceGuideKeys.composerActivityCta,
              eyebrow: 'NEXT',
              title: teachMode
                  ? 'Teach it to Nuvo.'
                  : 'Set the finish line.',
              body: teachMode
                  ? 'Tap Continue to training.'
                  : manualGoal
                      ? 'Tap Set the finish line.'
                      : 'Tap Continue.',
            )
          : CoachSpec(
              targetKey: FirstRaceGuideKeys.composerActivity,
              eyebrow: 'PICK THE MOVE',
              title: 'Choose what you’re racing on.',
            ),
    ComposerGuidePage.train => null,
    ComposerGuidePage.goal =>
      inputReady
          ? CoachSpec(
              targetKey: FirstRaceGuideKeys.composerGoalCta,
              eyebrow: 'NEXT',
              title: 'Bring in your crew.',
              body: 'Tap Invite racers.',
            )
          : CoachSpec(
              targetKey: FirstRaceGuideKeys.composerGoal,
              eyebrow: 'SET THE FINISH',
              title: 'Choose the goal.',
            ),
    ComposerGuidePage.racers =>
      inputReady
          ? CoachSpec(
              targetKey: FirstRaceGuideKeys.composerRacersCta,
              eyebrow: 'NEXT',
              title: 'Review your race.',
              body: 'Tap Review race.',
            )
          : CoachSpec(
              targetKey: FirstRaceGuideKeys.composerRacers,
              eyebrow: 'BRING YOUR CREW',
              title: 'Choose who you’re racing.',
            ),
    ComposerGuidePage.review => CoachSpec(
      targetKey: FirstRaceGuideKeys.composerReview,
      eyebrow: 'START THE RACE',
      title: 'Everything looks good.',
      body: 'Tap Start race.',
    ),
  };
}

/// Whether the first-race coach may arm for [user] right now.
///
/// The store-review credential always re-arms — it is the demo identity whose
/// whole purpose is replaying the first-use flow. Every other eligible
/// (demo-flagged) identity is suppressed once its guide completion has been
/// persisted for that account.
bool firstRaceGuideAllowed(Ref ref, AuthUser user) {
  if (isNuvoStoreDemoEmail(user.email)) return true;
  return !ref.read(firstUseStoreProvider).isGuideDone(user.email);
}

/// Marks the guide complete for the signed-in account and persists the
/// completion under that account's canonical email — the flag survives
/// sign-out and relaunch but cannot leak into another account's guide state.
void completeFirstRaceGuide(WidgetRef ref) {
  final user = ref.read(authControllerProvider).user;
  ref.read(firstRaceGuideProvider.notifier).state = FirstRaceGuideStep.complete;
  if (user != null) {
    unawaited(ref.read(firstUseStoreProvider).markGuideDone(user.email));
  }
}

/// Spotlight coach overlay for one guide step.
///
/// The overlay never intercepts input: the scrim and highlight ring are
/// IgnorePointer and the bubble's only control is the small "Skip" action.
/// The user always drives the real app control the bubble points at — the
/// production tap itself is what advances the guide (the host screen owns the
/// provider transition; this widget only renders the current step).
class FirstRaceGuideCoach extends ConsumerStatefulWidget {
  const FirstRaceGuideCoach({
    super.key,
    required this.step,
    required this.targetKey,
    required this.eyebrow,
    required this.title,
    this.body,
    this.avoidKeys = const [],
  });

  final FirstRaceGuideStep step;
  final GlobalKey targetKey;
  final String eyebrow;
  final String title;
  final String? body;

  /// Content regions the bubble must never park on (e.g. the featured race
  /// card under the Compete header). Measured from real geometry, not
  /// hard-coded offsets.
  final List<GlobalKey> avoidKeys;

  @override
  ConsumerState<FirstRaceGuideCoach> createState() =>
      _FirstRaceGuideCoachState();
}

class _FirstRaceGuideCoachState extends ConsumerState<FirstRaceGuideCoach>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  Rect? _targetRect;
  List<Rect> _avoidRects = const [];
  Size _bubbleSize = const Size(280, 118);
  Size _overlaySize = Size.zero;
  GlobalKey? _scrolledForKey;
  bool _tracking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTracking();
  }

  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _locateTarget());
  }

  /// The spotlight tracks its target EVERY frame while mounted — the pulse
  /// ring repaints each frame anyway, so a fresh localToGlobal costs nothing.
  /// This is what keeps the highlight glued to the real control through route
  /// transitions, PageView swipes, scrolls, and keyboard opens instead of
  /// trusting a single measurement that goes stale mid-animation.
  void _startTracking() {
    if (_tracking) return;
    _tracking = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _locateTarget());
  }

  void _locateTarget() {
    if (!mounted) return;
    // The overlay is often inside a SafeArea (MainShell pads the tab body),
    // so its local origin is NOT the screen's (0,0). Positions must be in the
    // overlay's OWN coordinate space — globalToLocal against our render box —
    // or every spotlight lands one status-bar-height too low.
    final overlayBox = context.findRenderObject();
    final targetContext = widget.targetKey.currentContext;
    final renderObject = targetContext?.findRenderObject();
    if (overlayBox is RenderBox && overlayBox.hasSize) {
      _overlaySize = overlayBox.size;
    }
    if (renderObject is RenderBox &&
        renderObject.hasSize &&
        overlayBox is RenderBox &&
        overlayBox.hasSize) {
      final rect =
          overlayBox.globalToLocal(renderObject.localToGlobal(Offset.zero)) &
          renderObject.size;
      final viewport = Offset.zero & overlayBox.size;
      final visible = rect.overlaps(viewport.deflate(24));
      if (!visible) {
        if (targetContext != null && _scrolledForKey != widget.targetKey) {
          // One controlled scroll per target — never a fling, and only so the
          // bubble never points at something the user cannot see.
          _scrolledForKey = widget.targetKey;
          Scrollable.ensureVisible(
            targetContext,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            alignment: 0.5,
          );
        }
        if (_targetRect != null) setState(() => _targetRect = null);
      } else {
        final avoid = _measureAvoidRects(overlayBox);
        final rectsChanged =
            _avoidRects.length != avoid.length ||
            _avoidRects.asMap().entries.any((e) => e.value != avoid[e.key]);
        if (_targetRect != rect || rectsChanged) {
          setState(() {
            _targetRect = rect;
            _avoidRects = avoid;
          });
        }
      }
    } else if (_targetRect != null) {
      setState(() => _targetRect = null);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _locateTarget());
  }

  /// Obstacles the bubble must not cover, resolved in overlay-local
  /// coordinates (same space as [_targetRect]). Only on-screen rects count —
  /// off-screen siblings can't collide anyway.
  List<Rect> _measureAvoidRects(RenderBox overlayBox) {
    final viewport = Offset.zero & overlayBox.size;
    final rects = <Rect>[];
    for (final key in widget.avoidKeys) {
      final ro = key.currentContext?.findRenderObject();
      if (ro is RenderBox && ro.hasSize) {
        final r =
            overlayBox.globalToLocal(ro.localToGlobal(Offset.zero)) & ro.size;
        if (r.overlaps(viewport)) rects.add(r);
      }
    }
    return rects;
  }

  void _syncBubbleSize() {
    final size = _bubbleKey.currentContext?.size;
    if (size != null && size != _bubbleSize && mounted) {
      setState(() => _bubbleSize = size);
    }
  }

  final _bubbleKey = GlobalKey(debugLabel: 'guide-bubble');

  void _skip() => completeFirstRaceGuide(ref);

  @override
  void didUpdateWidget(covariant FirstRaceGuideCoach oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetKey != widget.targetKey) {
      // New target — allow one scroll-into-view for it.
      _scrolledForKey = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncBubbleSize());
    final targetRect = _targetRect;
    return Positioned.fill(
      child: Stack(
        children: [
          // Subtle dim with a hole cut around the target — the real control
          // stays fully bright while the rest of the screen recedes. The
          // IgnorePointer keeps every production control tappable.
          IgnorePointer(
            child: CustomPaint(
              painter: _CoachScrimPainter(
                hole: _targetRect?.inflate(8),
              ),
              child: const SizedBox.expand(),
            ),
          ),
          // Restrained pulse ring around the spotlight. Positioned must be a
          // direct Stack child — the IgnorePointer lives inside it.
          if (targetRect != null)
            Positioned(
              left: targetRect.left - 8,
              top: targetRect.top - 8,
              width: targetRect.width + 16,
              height: targetRect.height + 16,
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, _) => DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: NuvoColors.blue.withValues(
                          alpha: .55 + _pulse.value * .45,
                        ),
                        width: 2.5,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: NuvoColors.blue.withValues(
                            alpha: .10 + _pulse.value * .12,
                          ),
                          blurRadius: 14,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          _GuideCallout(
            bubbleKey: _bubbleKey,
            targetRect: _targetRect,
            avoidRects: _avoidRects,
            bubbleSize: _bubbleSize,
            overlaySize: _overlaySize,
            eyebrow: widget.eyebrow,
            title: widget.title,
            body: widget.body,
            onSkip: _skip,
          ),
        ],
      ),
    );
  }
}

/// Darkens everything except the spotlight hole. Even-odd fill keeps the
/// target's pixels completely untouched — no blur, no second surface.
class _CoachScrimPainter extends CustomPainter {
  const _CoachScrimPainter({required this.hole});

  final Rect? hole;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = NuvoColors.navy.withValues(alpha: .35);
    final hole = this.hole;
    if (hole == null) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = NuvoColors.navy.withValues(alpha: .10),
      );
      return;
    }
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(hole, const Radius.circular(16)));
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CoachScrimPainter oldDelegate) =>
      oldDelegate.hole != hole;
}

/// Which edge of the coach bubble carries the caret — always the edge facing
/// the target.
enum _CaretSide { top, bottom, left, right }

/// Compact coach bubble. Scores candidate placements (below, pushed below any
/// obstacle, above, then the sides) by how much of the bubble stays inside
/// the usable viewport and how cleanly it clears the target and declared
/// obstacles — never a hard-coded offset. Below/above win ties; sides are a
/// last resort. The keyboard shrinks the usable region so the bubble can
/// never slide under it.
class _GuideCallout extends StatelessWidget {
  const _GuideCallout({
    required this.bubbleKey,
    required this.targetRect,
    required this.avoidRects,
    required this.bubbleSize,
    required this.overlaySize,
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.onSkip,
  });

  final GlobalKey bubbleKey;
  final Rect? targetRect;
  final List<Rect> avoidRects;
  final Size bubbleSize;

  /// The overlay's real laid-out size. It can be smaller than the window —
  /// MainShell's SafeArea shaves the status bar off the top — so placements
  /// are computed against this, not MediaQuery.sizeOf.
  final Size overlaySize;
  final String eyebrow;
  final String title;
  final String? body;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    // Overlay-local space: top inset was already consumed by the SafeArea
    // wrapping us, so local (0,0) is the first usable row.
    final size =
        overlaySize.width <= 0 ? MediaQuery.sizeOf(context) : overlaySize;
    final padding = MediaQuery.paddingOf(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final usable = Rect.fromLTRB(
      16,
      12,
      size.width - 16,
      size.height - math.max(padding.bottom, keyboard) - 12,
    );
    final width = math.min(280.0, usable.width - 4);
    final height = bubbleSize.height;
    final rect = targetRect;

    double left;
    double top;
    var caret = _CaretSide.top;

    if (rect == null) {
      // Target not measured yet — anchor low so the bubble never blocks
      // whatever is about to be highlighted.
      left = (size.width - width) / 2;
      top = usable.bottom - height;
    } else {
      double clampX(double l) =>
          l.clamp(usable.left, math.max(usable.left, usable.right - width));
      double clampY(double t) =>
          t.clamp(usable.top, math.max(usable.top, usable.bottom - height));

      // Two below candidates: one hugging the target (16px gap), one pushed
      // fully past any declared obstacle (e.g. the featured race card under
      // the Compete header). The scorer trades overlap against distance, so
      // a huge obstacle doesn't drag the bubble halfway down the screen.
      const hugTop = 16.0;
      var belowTop = rect.bottom + hugTop;
      for (var i = 0; i <= avoidRects.length; i++) {
        final probe = Rect.fromLTWH(
          clampX(rect.center.dx - width / 2),
          belowTop,
          width,
          height,
        );
        Rect? hit;
        for (final a in avoidRects) {
          if (probe.overlaps(a) && (hit == null || a.bottom > hit.bottom)) {
            hit = a;
          }
        }
        if (hit == null) break;
        belowTop = hit.bottom + 12;
      }

      final centerX = clampX(rect.center.dx - width / 2);
      final centerY = clampY(rect.center.dy - height / 2);
      final belowBias = rect.center.dy < size.height * 0.45 ? 140.0 : 100.0;
      final candidates = <_Placement>[
        _Placement(
          Rect.fromLTWH(centerX, rect.bottom + hugTop, width, height),
          _CaretSide.top,
          // Top-half targets strongly prefer the coach reading underneath.
          bias: belowBias,
        ),
        _Placement(
          Rect.fromLTWH(centerX, belowTop, width, height),
          _CaretSide.top,
          bias: belowBias - 10,
        ),
        _Placement(
          Rect.fromLTWH(centerX, rect.top - 16 - height, width, height),
          _CaretSide.bottom,
          bias: 70,
        ),
        _Placement(
          Rect.fromLTWH(rect.right + 14, centerY, width, height),
          _CaretSide.left,
          bias: 30,
        ),
        _Placement(
          Rect.fromLTWH(rect.left - 14 - width, centerY, width, height),
          _CaretSide.right,
          bias: 20,
        ),
      ];

      var best = candidates.first;
      var bestScore = double.negativeInfinity;
      for (final c in candidates) {
        final visible = c.rect.intersect(usable);
        final visibleFrac = (visible.width * visible.height)
            .clamp(0.0, double.infinity) /
            (c.rect.width * c.rect.height);
        var score = visibleFrac * 1000 + c.bias;
        // Never cover the target — an overlap is near-fatal.
        if (c.rect.overlaps(rect.inflate(4))) score -= 2500;
        // Proximity: the coach reads as attached to its target, so drifting
        // hundreds of px away must lose to a modest overlap.
        score -= (c.rect.center - rect.center).distance;
        for (final a in avoidRects) {
          final over = c.rect.intersect(a);
          if (!over.isEmpty) {
            score -= 600 * (over.width * over.height) / (c.rect.width * c.rect.height);
          }
        }
        if (score > bestScore) {
          bestScore = score;
          best = c;
        }
      }

      left = best.rect.left;
      top = best.rect.top;
      caret = best.side;
    }

    final caretX = rect == null
        ? width / 2 - 7
        : (rect.center.dx - left - 7).clamp(14.0, width - 28);
    final caretY = rect == null
        ? height / 2 - 7
        : (rect.center.dy - top - 7).clamp(14.0, height - 28);

    return Positioned(
      left: left,
      top: top,
      width: width,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            key: bubbleKey,
            padding: const EdgeInsets.fromLTRB(14, 10, 12, 12),
            decoration: BoxDecoration(
              color: NuvoColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: NuvoColors.navy, width: 1.6),
              boxShadow: AppShadows.hardSmall,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        eyebrow,
                        style: AppTextStyles.brandLabel,
                      ),
                    ),
                    GestureDetector(
                      onTap: onSkip,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 2, 2, 2),
                        child: Text(
                          'Skip',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: NuvoColors.muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(title, style: AppTextStyles.titleMedium),
                if (body != null && body!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    body!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: NuvoColors.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (rect != null) _caret(caret, caretX, caretY),
        ],
      ),
    );
  }

  Widget _caret(_CaretSide side, double x, double y) {
    const cross = 14.0;
    const depth = 10.0;
    final horizontal = side == _CaretSide.top || side == _CaretSide.bottom;
    final paint = CustomPaint(
      size: horizontal ? const Size(cross, depth) : const Size(depth, cross),
      painter: _CoachCaretPainter(side: side),
    );
    return switch (side) {
      _CaretSide.top => Positioned(left: x, top: -6, child: paint),
      _CaretSide.bottom => Positioned(left: x, bottom: -6, child: paint),
      _CaretSide.left => Positioned(left: -6, top: y, child: paint),
      _CaretSide.right => Positioned(right: -6, top: y, child: paint),
    };
  }
}

class _Placement {
  const _Placement(this.rect, this.side, {required this.bias});
  final Rect rect;
  final _CaretSide side;
  final double bias;
}

/// Small triangle caret on the bubble edge facing the target.
class _CoachCaretPainter extends CustomPainter {
  const _CoachCaretPainter({required this.side});

  final _CaretSide side;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = switch (side) {
      _CaretSide.top => Path()
        ..moveTo(0, h)
        ..lineTo(w / 2, 0)
        ..lineTo(w, h)
        ..close(),
      _CaretSide.bottom => Path()
        ..moveTo(0, 0)
        ..lineTo(w / 2, h)
        ..lineTo(w, 0)
        ..close(),
      _CaretSide.left => Path()
        ..moveTo(w, 0)
        ..lineTo(0, h / 2)
        ..lineTo(w, h)
        ..close(),
      _CaretSide.right => Path()
        ..moveTo(0, 0)
        ..lineTo(w, h / 2)
        ..lineTo(0, h)
        ..close(),
    };
    canvas.drawPath(path, Paint()..color = NuvoColors.surface);
    canvas.drawPath(
      path,
      Paint()
        ..color = NuvoColors.navy
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    // Erase the base edge so the caret reads as part of the bubble.
    final (a, b) = switch (side) {
      _CaretSide.top => (Offset(1.5, h), Offset(w - 1.5, h)),
      _CaretSide.bottom => (const Offset(1.5, 0), Offset(w - 1.5, 0)),
      _CaretSide.left => (Offset(w, 1.5), Offset(w, h - 1.5)),
      _CaretSide.right => (const Offset(0, 1.5), Offset(0, h - 1.5)),
    };
    canvas.drawLine(
      a,
      b,
      Paint()
        ..color = NuvoColors.surface
        ..strokeWidth = 2.4,
    );
  }

  @override
  bool shouldRepaint(covariant _CoachCaretPainter oldDelegate) =>
      oldDelegate.side != side;
}

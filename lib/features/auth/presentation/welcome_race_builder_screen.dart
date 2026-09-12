import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/asset_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import 'welcome_onboarding_state.dart';

class WelcomeRaceBuilderScreen extends ConsumerStatefulWidget {
  const WelcomeRaceBuilderScreen({super.key});

  @override
  ConsumerState<WelcomeRaceBuilderScreen> createState() =>
      _WelcomeRaceBuilderScreenState();
}

class _WelcomeRaceBuilderScreenState
    extends ConsumerState<WelcomeRaceBuilderScreen>
    with TickerProviderStateMixin {
  static const _pageCount = 6;
  late final PageController _pageController;
  late final AnimationController _sceneController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 18000),
  )..forward();
  late final AnimationController _ambientController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  )..repeat();
  late final AnimationController _practiceController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  int _page = 0;
  FitnessGoal _selectedGoal = FitnessGoal.strength;
  bool _practiceStarted = false;
  bool _ready = false;
  Timer? _readyTimer;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    ref
        .read(welcomeOnboardingStateProvider.notifier)
        .selectFitnessGoal(_selectedGoal);
    _startReadyTimer();
  }

  @override
  void dispose() {
    _readyTimer?.cancel();
    _pageController.dispose();
    _sceneController.dispose();
    _ambientController.dispose();
    _practiceController.dispose();
    super.dispose();
  }

  void _startReadyTimer() {
    _readyTimer?.cancel();
    _ready = false;
    _readyTimer = Timer(const Duration(milliseconds: 2400), () {
      if (mounted) setState(() => _ready = true);
    });
  }

  void _goToPage(int page) {
    if (page < 0 || page >= _pageCount) return;
    HapticFeedback.selectionClick();
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 480),
      curve: Curves.easeOutCubic,
    );
  }

  void _next() {
    if (_page == _pageCount - 1) {
      if (_practiceController.value >= .99) {
        context.go('/welcome');
      } else {
        _startPractice();
      }
      return;
    }
    _goToPage(_page + 1);
  }

  void _selectGoal(FitnessGoal goal) {
    if (_selectedGoal == goal) return;
    HapticFeedback.selectionClick();
    ref.read(welcomeOnboardingStateProvider.notifier).selectFitnessGoal(goal);
    setState(() => _selectedGoal = goal);
  }

  void _onPageChanged(int page) {
    setState(() => _page = page);
    _sceneController.forward(from: 0);
    _startReadyTimer();
  }

  void _skipToAuth() {
    context.go('/welcome');
  }

  Future<void> _startPractice() async {
    if (_practiceStarted) return;
    HapticFeedback.mediumImpact();
    setState(() => _practiceStarted = true);
    await _practiceController.forward(from: 0);
    if (mounted) setState(() {});
  }

  String get _buttonLabel => switch (_page) {
    0 => 'See how it works',
    1 => 'Keep going',
    2 => 'See the board move',
    3 => 'Choose my direction',
    4 => 'Practice the move',
    _ =>
      _practiceController.value >= .99
          ? 'Create my first race'
          : 'Practice the move',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: Listenable.merge([
            _sceneController,
            _practiceController,
            _ambientController,
          ]),
          builder: (context, _) => LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 720;
              final atmosphereReveal = _page == 0
                  ? Curves.easeInOutCubic.transform(
                      ((_sceneController.value - .80) / .20).clamp(0.0, 1.0),
                    )
                  : 1.0;
              final chromeReveal = _page == 0
                  ? Curves.easeOutCubic.transform(
                      ((_sceneController.value - .995) / .005).clamp(0.0, 1.0),
                    )
                  : 1.0;
              return Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _AmbientPainter(
                        progress: _ambientController.value,
                        opacity: atmosphereReveal * .15,
                      ),
                    ),
                  ),
                  Column(
                    children: [
                      Opacity(
                        opacity: chromeReveal,
                        child: IgnorePointer(
                          ignoring: chromeReveal < .99,
                          child: _OnboardingHeader(
                            page: _page,
                            pageCount: _pageCount,
                            compact: compact,
                            onBack: _page == 0
                                ? null
                                : () => _goToPage(_page - 1),
                            onSkip: _page == 0 ? null : _skipToAuth,
                          ),
                        ),
                      ),
                      Expanded(
                        child: PageView(
                          controller: _pageController,
                          onPageChanged: _onPageChanged,
                          children: [
                            TickerMode(
                              enabled: _page == 0,
                              child: _WelcomePage(
                                compact: compact,
                                sceneProgress: _sceneController.value,
                              ),
                            ),
                            TickerMode(
                              enabled: _page == 1,
                              child: _LeaderboardPage(
                                compact: compact,
                                sceneProgress: _sceneController.value,
                              ),
                            ),
                            TickerMode(
                              enabled: _page == 2,
                              child: _ProofPage(compact: compact),
                            ),
                            TickerMode(
                              enabled: _page == 3,
                              child: _BoardMovePage(compact: compact),
                            ),
                            TickerMode(
                              enabled: _page == 4,
                              child: _GoalPage(
                                selected: _selectedGoal,
                                compact: compact,
                                onSelected: _selectGoal,
                              ),
                            ),
                            TickerMode(
                              enabled: _page == 5,
                              child: _PracticePage(
                                goal: _selectedGoal,
                                progress: _practiceController.value,
                                started: _practiceStarted,
                                compact: compact,
                              ),
                            ),
                          ],
                        ),
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 460),
                        curve: Curves.easeInOutCubic,
                        alignment: Alignment.topCenter,
                        clipBehavior: Clip.none,
                        child: _page == 0 && !_ready
                            ? const SizedBox.shrink()
                            : Opacity(
                                opacity: _page == 0 ? (_ready ? 1 : 0) : chromeReveal,
                                child: FadeTransition(
                                  opacity: CurvedAnimation(
                                    parent: _sceneController,
                                    curve: const Interval(
                                      .35,
                                      1,
                                      curve: Curves.easeOut,
                                    ),
                                  ),
                                  child: _OnboardingFooter(
                                    page: _page,
                                    pageCount: _pageCount,
                                    label: _buttonLabel,
                                    onPressed: _next,
                                    enabled: _ready,
                                    compact: compact,
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _OnboardingHeader extends StatelessWidget {
  const _OnboardingHeader({
    required this.page,
    required this.pageCount,
    required this.compact,
    required this.onBack,
    this.onSkip,
  });

  final int page;
  final int pageCount;
  final bool compact;
  final VoidCallback? onBack;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    if (page == 0) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.fromLTRB(22, compact ? 10 : 18, 22, 4),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            child: onBack == null
                ? Image.asset(
                    AssetPaths.splashFrame(90),
                    width: 34,
                    height: 34,
                    fit: BoxFit.contain,
                  )
                : IconButton(
                    tooltip: 'Back',
                    onPressed: onBack,
                    padding: EdgeInsets.zero,
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: NuvoColors.navy,
                      size: 24,
                    ),
                  ),
          ),
          Image.asset(
            'assets/branding/nuvotext.png',
            width: compact ? 86 : 104,
            height: compact ? 26 : 31,
            fit: BoxFit.contain,
          ),
          const Spacer(),
          if (onSkip != null)
            GestureDetector(
              onTap: onSkip,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  'Skip',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: NuvoColors.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            )
          else
            Text(
              '${page + 1} / $pageCount',
              style: AppTextStyles.labelLarge.copyWith(
                color: NuvoColors.muted,
                fontWeight: FontWeight.w800,
              ),
            ),
        ],
      ),
    );
  }
}

class _OnboardingFooter extends StatelessWidget {
  const _OnboardingFooter({
    required this.page,
    required this.pageCount,
    required this.label,
    required this.onPressed,
    required this.enabled,
    required this.compact,
  });

  final int page;
  final int pageCount;
  final String label;
  final VoidCallback onPressed;
  final bool enabled;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, compact ? 6 : 12, 20, compact ? 14 : 20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < pageCount; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == page ? 24 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == page ? NuvoColors.blue : NuvoColors.navy,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
            ],
          ),
          SizedBox(height: compact ? 10 : 14),
          NuvoPrimaryButton(
            label: label,
            icon: Icons.arrow_forward_rounded,
            expand: true,
            onPressed: enabled ? onPressed : null,
          ),
        ],
      ),
    );
  }
}

class _WelcomePage extends StatelessWidget {
  const _WelcomePage({required this.compact, required this.sceneProgress});

  final bool compact;
  final double sceneProgress;

  @override
  Widget build(BuildContext context) {
    final sceneSeconds = sceneProgress * 18;
    final immersiveReveal =
        1 -
        Curves.easeInOutCubic.transform(
          ((sceneSeconds - 11.6) / .8).clamp(0.0, 1.0),
        );
    final explanationProgress = Curves.easeInOutCubic.transform(
      ((sceneSeconds - 12.5) / 5.4).clamp(0.0, 1.0),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(22, compact ? 8 : 20, 22, 4),
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          IgnorePointer(
            child: Opacity(
              opacity: immersiveReveal,
              child: CustomPaint(
                painter: _ImmersiveRacePainter(progress: sceneProgress),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          Center(
            child: Opacity(
              opacity: explanationProgress,
              child: _TypedWelcomeExplanation(
                sceneSeconds: sceneSeconds,
                compact: compact,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypedWelcomeExplanation extends StatelessWidget {
  const _TypedWelcomeExplanation({
    required this.sceneSeconds,
    required this.compact,
  });

  final double sceneSeconds;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final firstLine = Curves.easeOutCubic.transform(
      ((sceneSeconds - 12.5) / 2.0).clamp(0.0, 1.0),
    );
    final secondLine = Curves.easeOutCubic.transform(
      ((sceneSeconds - 14.75) / 1.0).clamp(0.0, 1.0),
    );
    final thirdLine = Curves.easeOutCubic.transform(
      ((sceneSeconds - 16.0) / .75).clamp(0.0, 1.0),
    );
    final supportReveal = Curves.easeOutCubic.transform(
      ((sceneSeconds - 17.35) / .55).clamp(0.0, 1.0),
    );
    return SizedBox(
      width: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _CinematicLine(
            text: 'Your goals',
            reveal: firstLine,
            compact: compact,
          ),
          SizedBox(height: (compact ? 3 : 5) * secondLine),
          _CinematicRevealSlot(
            reveal: secondLine,
            child: _CinematicLine(
              text: 'are now',
              reveal: secondLine,
              compact: compact,
            ),
          ),
          SizedBox(height: (compact ? 3 : 5) * thirdLine),
          _CinematicRevealSlot(
            reveal: thirdLine,
            child: _CinematicLine(
              text: 'competition.',
              reveal: thirdLine,
              compact: compact,
              color: NuvoColors.blue,
            ),
          ),
          SizedBox(height: (compact ? 20 : 28) * supportReveal),
          _CinematicRevealSlot(
            reveal: supportReveal,
            child: Text(
              'Set a finish line, pull in your crew, and make every move visible.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyLarge.copyWith(
                color: NuvoColors.muted,
                height: 1.25,
                fontSize: compact ? 16 : 19,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CinematicRevealSlot extends StatelessWidget {
  const _CinematicRevealSlot({required this.reveal, required this.child});

  final double reveal;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Align(
        alignment: Alignment.topCenter,
        heightFactor: reveal,
        child: child,
      ),
    );
  }
}

class _CinematicLine extends StatelessWidget {
  const _CinematicLine({
    required this.text,
    required this.reveal,
    required this.compact,
    this.fontSize,
    this.color = NuvoColors.navy,
  });

  final String text;
  final double reveal;
  final bool compact;
  final double? fontSize;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: reveal,
      child: Transform.translate(
        offset: Offset(0, 20 * (1 - reveal)),
        child: Transform.scale(
          alignment: Alignment.center,
          scale: .94 + (.06 * reveal),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: AppTextStyles.displayMedium.copyWith(
              color: color,
              fontSize: fontSize ?? (compact ? 41 : 56),
              height: .94,
              letterSpacing: -1.6,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _ImmersiveRacePainter extends CustomPainter {
  const _ImmersiveRacePainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    // One motion language: the point settles, shrinks, and then becomes the
    // tip of the same route that grows behind it. The holds are intentional.
    final dotZoom = Curves.easeOutCubic.transform(
      ((progress - .03) / .10).clamp(0.0, 1.0),
    );
    final routeProgress = Curves.easeOutCubic.transform(
      ((progress - .13) / .37).clamp(0.0, 1.0),
    );
    final flagReveal = Curves.easeOutCubic.transform(
      ((progress - .47) / .09).clamp(0.0, 1.0),
    );
    final center = Offset(size.width / 2, size.height * .48);
    final target = _racePath(size);
    final targetMetrics = target.computeMetrics().toList();
    if (targetMetrics.isEmpty) return;
    final targetMetric = targetMetrics.first;

    final targetEnd = targetMetric.getTangentForOffset(targetMetric.length);
    final targetStart = targetMetric.getTangentForOffset(0);
    if (targetEnd == null || targetStart == null) return;

    final morphStart = Offset.lerp(
      center,
      targetStart.position,
      routeProgress,
    )!;
    final morphEnd = Offset.lerp(center, targetEnd.position, routeProgress)!;
    final morphControlOne = Offset.lerp(
      center,
      Offset(size.width * .24, size.height * .05),
      routeProgress,
    )!;
    final morphControlTwo = Offset.lerp(
      center,
      Offset(size.width * .55, size.height * .98),
      routeProgress,
    )!;
    final route = Path()
      ..moveTo(morphStart.dx, morphStart.dy)
      ..cubicTo(
        morphControlOne.dx,
        morphControlOne.dy,
        morphControlTwo.dx,
        morphControlTwo.dy,
        morphEnd.dx,
        morphEnd.dy,
      );
    final routeMetrics = route.computeMetrics().toList();
    if (routeMetrics.isEmpty) return;
    final routeMetric = routeMetrics.first;
    final tip = routeProgress > 0
        ? routeMetric.getTangentForOffset(routeMetric.length * routeProgress)
        : null;

    if (routeProgress > 0) {
      final revealedPath = routeMetric.extractPath(
        0,
        routeMetric.length * routeProgress,
      );
      canvas.drawPath(
        revealedPath,
        Paint()
          ..color = NuvoColors.navy
          ..style = PaintingStyle.stroke
          ..strokeWidth = 19
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawPath(
        revealedPath,
        Paint()
          ..color = NuvoColors.blue
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round,
      );

      if (flagReveal > 0) {
        _drawNuvoFlag(
          canvas,
          anchor: targetEnd.position,
          scale: 1.35,
          opacity: flagReveal,
        );
      }
    }

    final dotPosition = tip?.position ?? center;
    final zoomedRadius = Tween<double>(begin: 76, end: 12).transform(dotZoom);
    final dotRadius = routeProgress > 0
        ? Tween<double>(begin: 12, end: 10).transform(routeProgress)
        : zoomedRadius;
    final dotGlow = Paint()
      ..color = NuvoColors.blue.withValues(
        alpha: .18 + (.16 * (1 - routeProgress)),
      )
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28);
    canvas.drawCircle(dotPosition, dotRadius + 12, dotGlow);
    canvas.drawCircle(dotPosition, dotRadius, Paint()..color = NuvoColors.blue);
  }

  @override
  bool shouldRepaint(covariant _ImmersiveRacePainter oldDelegate) =>
      oldDelegate.progress != progress;
}

Path _racePath(Size size) => Path()
  ..moveTo(size.width * .05, size.height * .82)
  ..cubicTo(
    size.width * .25,
    size.height * .06,
    size.width * .62,
    size.height * .98,
    size.width * .78,
    size.height * .14,
  );

void _drawNuvoFlag(
  Canvas canvas, {
  required Offset anchor,
  required double scale,
  required double opacity,
}) {
  // Keep the marker just beyond the route endpoint so the finish reads as a
  // destination, rather than another blob sitting on top of the line.
  final poleX = anchor.dx + (12 * scale);
  final poleTop = anchor.dy - (24 * scale);
  final poleBottom = anchor.dy + (16 * scale);
  final polePaint = Paint()
    ..color = NuvoColors.navy.withValues(alpha: opacity)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.2 * scale
    ..strokeCap = StrokeCap.round;
  canvas.drawLine(Offset(poleX, poleTop), Offset(poleX, poleBottom), polePaint);

  // The pennant is deliberately separate from the route. Its rounded profile
  // keeps the finish marker legible when the route ends close to the edge.
  final flag = Path()
    ..moveTo(poleX + (1 * scale), poleTop + (1 * scale))
    ..cubicTo(
      poleX + (9 * scale),
      poleTop + (2 * scale),
      poleX + (19 * scale),
      poleTop + (7 * scale),
      poleX + (28 * scale),
      poleTop + (12 * scale),
    )
    ..cubicTo(
      poleX + (19 * scale),
      poleTop + (16 * scale),
      poleX + (9 * scale),
      poleTop + (18 * scale),
      poleX + (1 * scale),
      poleTop + (19 * scale),
    )
    ..close();
  canvas.drawPath(
    flag,
    Paint()
      ..color = NuvoColors.blue.withValues(alpha: opacity)
      ..style = PaintingStyle.fill,
  );
  canvas.drawPath(
    flag,
    Paint()
      ..color = NuvoColors.navy.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 * scale
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round,
  );
}

class _LeaderboardPage extends StatelessWidget {
  const _LeaderboardPage({required this.compact, required this.sceneProgress});

  final bool compact;
  final double sceneProgress;

  @override
  Widget build(BuildContext context) {
    // This page is intentionally a visual pause between the idea and proof
    // pages. The board owns the stage first; its explanation arrives later.
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 20),
      child: Center(
        child: _LeaderboardVisual(progress: sceneProgress, compact: compact),
      ),
    );
  }
}

class _ProofPage extends StatelessWidget {
  const _ProofPage({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return _PageBody(
      eyebrow: 'AI MOTION PROOF',
      title: 'Move real.\nCount real.',
      body: 'Nuvo checks the movement before it moves the board.',
      compact: compact,
      visual: const _ProofVisual(),
    );
  }
}

class _BoardMovePage extends StatelessWidget {
  const _BoardMovePage({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return _PageBody(
      eyebrow: 'THE MOVE',
      title: 'Proof turns\neffort into\nprogress.',
      body:
          'Submit proof, move up, and give your crew something real to chase.',
      compact: compact,
      visual: const _ProofFlowVisual(),
    );
  }
}

class _PageBody extends StatelessWidget {
  const _PageBody({
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.visual,
    required this.compact,
  });

  final String eyebrow;
  final String title;
  final String body;
  final Widget visual;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(22, compact ? 10 : 24, 22, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow,
            style: AppTextStyles.brandLabel.copyWith(
              color: NuvoColors.blue,
              letterSpacing: 2.2,
            ),
          ),
          SizedBox(height: compact ? 8 : 12),
          Text(
            title,
            style: AppTextStyles.displayMedium.copyWith(
              color: NuvoColors.navy,
              fontSize: compact ? 34 : 42,
              height: .95,
              letterSpacing: -1.2,
            ),
          ),
          SizedBox(height: compact ? 8 : 12),
          Text(
            body,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodyLarge.copyWith(
              color: NuvoColors.muted,
              height: 1.25,
            ),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.only(top: compact ? 4 : 12),
                child: visual,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Kept as a visual primitive for later race examples; page 1 now uses text.
// ignore: unused_element
class _HeroRaceVisual extends StatelessWidget {
  const _HeroRaceVisual({required this.progress, required this.compact});

  final double progress;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final boardProgress = Curves.easeOutCubic.transform(
      ((progress - .04) / .34).clamp(0.0, 1.0),
    );
    final pathProgress = Curves.easeInOutCubic.transform(
      ((progress - .2) / .48).clamp(0.0, 1.0),
    );
    final detailProgress = Curves.easeOutCubic.transform(
      ((progress - .58) / .26).clamp(0.0, 1.0),
    );
    final sequenceProgress = Curves.easeOutCubic.transform(
      ((progress - .72) / .2).clamp(0.0, 1.0),
    );

    return SizedBox(
      width: double.infinity,
      height: compact ? 316 : 350,
      child: Column(
        children: [
          Opacity(
            opacity: boardProgress,
            child: Transform.translate(
              offset: Offset(0, 18 * (1 - boardProgress)),
              child: Transform.scale(
                scale: .96 + (.04 * boardProgress),
                child: Container(
                  width: double.infinity,
                  height: compact ? 246 : 274,
                  padding: EdgeInsets.fromLTRB(
                    compact ? 16 : 18,
                    compact ? 15 : 18,
                    compact ? 16 : 18,
                    0,
                  ),
                  decoration: BoxDecoration(
                    color: NuvoColors.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: NuvoColors.navy, width: 1.8),
                    boxShadow: AppShadows.hardSmall,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'YOUR FIRST RACE',
                            style: AppTextStyles.brandLabel.copyWith(
                              color: NuvoColors.blue,
                              letterSpacing: 1.6,
                              fontSize: compact ? 10 : 11,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'START LINE',
                            style: AppTextStyles.labelSmall.copyWith(
                              color: NuvoColors.muted,
                              fontWeight: FontWeight.w800,
                              letterSpacing: .6,
                              fontSize: compact ? 9 : 10,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: compact ? 10 : 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Text(
                              'First to 10 pushups',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.titleLarge.copyWith(
                                color: NuvoColors.navy,
                                fontSize: compact ? 22 : 25,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '0 / 10',
                            style: AppTextStyles.titleMedium.copyWith(
                              color: NuvoColors.blue,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: compact ? 4 : 6),
                      Text(
                        'A finish line your crew can see.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: NuvoColors.muted,
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: compact ? 4 : 8,
                          ),
                          child: CustomPaint(
                            painter: _RacePathPainter(progress: pathProgress),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                      Opacity(
                        opacity: detailProgress,
                        child: Row(
                          children: [
                            Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: NuvoColors.navy,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.person_rounded,
                                color: NuvoColors.white,
                                size: 17,
                              ),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                'You are on the board.\nProof moves your place.',
                                style: AppTextStyles.labelMedium.copyWith(
                                  color: NuvoColors.navy,
                                  fontWeight: FontWeight.w700,
                                  height: 1.15,
                                ),
                              ),
                            ),
                            Text(
                              '1 racer',
                              style: AppTextStyles.labelSmall.copyWith(
                                color: NuvoColors.muted,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: compact ? 12 : 14),
                      Opacity(
                        opacity: sequenceProgress,
                        child: Container(
                          height: compact ? 34 : 38,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: const BoxDecoration(
                            color: NuvoColors.blue,
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(12),
                            ),
                          ),
                          child: Row(
                            children: [
                              Text(
                                'GOAL SET',
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: NuvoColors.white,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.1,
                                ),
                              ),
                              const Spacer(),
                              const Icon(
                                Icons.arrow_forward_rounded,
                                color: NuvoColors.white,
                                size: 19,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: compact ? 10 : 14),
          Opacity(
            opacity: detailProgress,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final label in ['GOAL', 'CREW', 'PROOF', 'BOARD']) ...[
                  Text(
                    label,
                    style: AppTextStyles.brandLabel.copyWith(
                      color: NuvoColors.navy,
                      letterSpacing: 1.3,
                      fontSize: compact ? 9 : 10,
                    ),
                  ),
                  if (label != 'BOARD')
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        color: NuvoColors.blue,
                        size: compact ? 13 : 15,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LeaderboardVisual extends StatelessWidget {
  const _LeaderboardVisual({required this.progress, required this.compact});

  final double progress;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final boardIn = Curves.easeOutCubic.transform(
      (progress / .06).clamp(0.0, 1.0),
    );
    final youMove = Curves.easeInOutCubic.transform(
      ((progress - .10) / .22).clamp(0.0, 1.0),
    );
    final mayaMove = Curves.easeOutCubic.transform(
      ((progress - .12) / .18).clamp(0.0, 1.0),
    );
    final priyaMove = Curves.easeInCubic.transform(
      ((progress - .12) / .22).clamp(0.0, 1.0),
    );
    final settle = Curves.easeOutBack.transform(
      ((progress - .32) / .08).clamp(0.0, 1.0),
    );
    final zoom = Curves.easeInOutCubic.transform(
      ((progress - .41) / .12).clamp(0.0, 1.0),
    );
    final boardOut = Curves.easeInCubic.transform(
      ((progress - .54) / .10).clamp(0.0, 1.0),
    );
    final textReveal = Curves.easeOutCubic.transform(
      ((progress - .62) / .10).clamp(0.0, 1.0),
    );
    final firstLine = Curves.easeOutCubic.transform(
      ((progress - .63) / .055).clamp(0.0, 1.0),
    );
    final secondLine = Curves.easeOutCubic.transform(
      ((progress - .71) / .06).clamp(0.0, 1.0),
    );
    final thirdLine = Curves.easeOutCubic.transform(
      ((progress - .80) / .065).clamp(0.0, 1.0),
    );
    final winner = youMove > .96;

    final rowHeight = compact ? 62.0 : 72.0;
    final rowGap = compact ? 9.0 : 12.0;
    final stageHeight = compact ? 328.0 : 360.0;
    final stageWidth = compact ? 320.0 : 348.0;
    final groupHeight = (rowHeight * 3) + (rowGap * 2);
    final groupTop = (stageHeight - groupHeight) / 2;
    final firstRow = groupTop;
    final secondRow = firstRow + rowHeight + rowGap;
    final thirdRow = secondRow + rowHeight + rowGap;
    final youTop = thirdRow - ((thirdRow - firstRow) * youMove);
    final mayaTop = firstRow + ((secondRow - firstRow) * mayaMove);
    final priyaTop = secondRow + ((thirdRow - secondRow) * priyaMove);

    return SizedBox(
      width: stageWidth,
      height: stageHeight,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: boardIn * (1 - boardOut),
              child: Transform.scale(
                alignment: Alignment.center,
                scale: 1 - (.18 * zoom),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      top: youTop,
                      left: 0,
                      right: 0,
                      child: Transform.scale(
                        scale: .96 + (.04 * boardIn) + (.025 * settle),
                        child: _RankRow(
                          height: rowHeight,
                          rank: winner ? '1' : '3',
                          name: 'You',
                          score: winner ? '6 / 10' : '2 / 10',
                          active: winner,
                          emphasis: winner || settle > .1,
                        ),
                      ),
                    ),
                    Positioned(
                      top: mayaTop,
                      left: 0,
                      right: 0,
                      child: _RankRow(
                        height: rowHeight,
                        rank: winner ? '2' : '1',
                        name: 'Maya Chen',
                        score: winner ? '4 / 10' : '6 / 10',
                      ),
                    ),
                    Positioned(
                      top: priyaTop,
                      left: 0,
                      right: 0,
                      child: _RankRow(
                        height: rowHeight,
                        rank: winner ? '3' : '2',
                        name: 'Priya Nair',
                        score: winner ? '2 / 10' : '4 / 10',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: 0,
            child: Opacity(
              opacity: textReveal,
              child: Transform.translate(
                offset: Offset(0, 14 * (1 - textReveal)),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _CinematicRevealSlot(
                      reveal: firstLine,
                      child: _CinematicLine(
                        text: 'Every rep',
                        reveal: firstLine,
                        compact: compact,
                        fontSize: compact ? 38 : 48,
                      ),
                    ),
                    SizedBox(height: compact ? 5 : 7),
                    _CinematicRevealSlot(
                      reveal: secondLine,
                      child: _CinematicLine(
                        text: 'changes your',
                        reveal: secondLine,
                        compact: compact,
                        fontSize: compact ? 38 : 48,
                      ),
                    ),
                    SizedBox(height: compact ? 5 : 7),
                    _CinematicRevealSlot(
                      reveal: thirdLine,
                      child: _CinematicLine(
                        text: 'position.',
                        reveal: thirdLine,
                        compact: compact,
                        fontSize: compact ? 38 : 48,
                        color: NuvoColors.blue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.rank,
    required this.name,
    required this.score,
    this.height = 58,
    this.active = false,
    this.emphasis = false,
  }) : ghost = false;

  final String rank;
  final String name;
  final String score;
  final double height;
  final bool active;
  final bool ghost;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final rankColor = switch (rank) {
      '1' => NuvoColors.gold,
      '2' => NuvoColors.silver,
      _ => NuvoColors.bronze,
    };

    return Container(
      height: height,
      padding: EdgeInsets.symmetric(horizontal: height * .22),
      decoration: BoxDecoration(
        color: NuvoColors.surface.withValues(alpha: ghost ? .7 : 1),
        borderRadius: BorderRadius.circular(height * .27),
        border: Border.all(color: NuvoColors.navy, width: active ? 2.4 : 1.6),
        boxShadow: active || emphasis ? AppShadows.hardSmall : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: height * .38,
            child: Text(
              rank,
              style: AppTextStyles.titleMedium.copyWith(
                color: ghost ? rankColor.withValues(alpha: .7) : rankColor,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          CircleAvatar(
            radius: height * .25,
            backgroundColor: rankColor.withValues(alpha: .14),
            child: Icon(
              Icons.person_rounded,
              size: height * .32,
              color: rankColor,
            ),
          ),
          SizedBox(width: height * .15),
          Expanded(
            child: Text(
              name,
              style: AppTextStyles.labelLarge.copyWith(
                color: NuvoColors.navy,
                fontWeight: active ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ),
          Text(
            score,
            style: AppTextStyles.labelMedium.copyWith(
              color: NuvoColors.blue,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProofVisual extends StatefulWidget {
  const _ProofVisual();

  @override
  State<_ProofVisual> createState() => _ProofVisualState();
}

class _ProofVisualState extends State<_ProofVisual>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final phase = _controller.value;
        final checked = phase > .68;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              height: 246,
              decoration: BoxDecoration(
                color: NuvoColors.navy,
                borderRadius: BorderRadius.circular(26),
                boxShadow: AppShadows.hardSmall,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(double.infinity, 246),
                    painter: _PosePainter(phase: phase),
                  ),
                  Positioned(
                    top: 16,
                    left: 18,
                    child: Text(
                      'EXAMPLE PROOF',
                      style: AppTextStyles.brandLabel.copyWith(
                        color: NuvoColors.white,
                        letterSpacing: 1.8,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 18,
                    top: 16,
                    child: Text(
                      checked ? 'VERIFIED' : 'CHECKING',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: checked ? NuvoColors.blue : NuvoColors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 18,
                    child: Text(
                      '${4 + (phase * 2).floor()} / 10 REPS',
                      style: AppTextStyles.titleMedium.copyWith(
                        color: NuvoColors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'AI reads the movement before the board moves.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
            ),
          ],
        );
      },
    );
  }
}

class _ProofFlowVisual extends StatefulWidget {
  const _ProofFlowVisual();

  @override
  State<_ProofFlowVisual> createState() => _ProofFlowVisualState();
}

class _ProofFlowVisualState extends State<_ProofFlowVisual>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final phase = _controller.value;
        final active = (phase * 3).floor().clamp(0, 2);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _FlowStep(label: 'SUBMIT\nPROOF', active: active == 0),
                _FlowConnector(active: active >= 1),
                _FlowStep(label: 'AI\nCHECKS IT', active: active == 1),
                _FlowConnector(active: active >= 2),
                _FlowStep(label: 'BOARD\nMOVES', active: active == 2),
              ],
            ),
            const SizedBox(height: 28),
            SizedBox(
              height: 72,
              child: CustomPaint(
                painter: _ProgressPainter(progress: phase),
                child: const SizedBox.expand(),
              ),
            ),
            const SizedBox(height: 6),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              child: Text(
                switch (active) {
                  0 => 'You show the work.',
                  1 => 'Nuvo checks the motion.',
                  _ => 'Your place changes.',
                },
                key: ValueKey(active),
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall.copyWith(
                  color: active == 2 ? NuvoColors.blue : NuvoColors.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FlowStep extends StatelessWidget {
  const _FlowStep({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        height: 92,
        padding: const EdgeInsets.all(8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? NuvoColors.blue : NuvoColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: NuvoColors.navy, width: 1.4),
          boxShadow: active ? AppShadows.hardSmall : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: AppTextStyles.labelSmall.copyWith(
            color: active ? NuvoColors.white : NuvoColors.navy,
            fontWeight: FontWeight.w900,
            letterSpacing: .7,
          ),
        ),
      ),
    );
  }
}

class _FlowConnector extends StatelessWidget {
  const _FlowConnector({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Icon(
        Icons.arrow_forward_rounded,
        size: 18,
        color: active ? NuvoColors.blue : NuvoColors.muted,
      ),
    );
  }
}

class _GoalPage extends StatelessWidget {
  const _GoalPage({
    required this.selected,
    required this.compact,
    required this.onSelected,
  });

  final FitnessGoal selected;
  final bool compact;
  final ValueChanged<FitnessGoal> onSelected;

  @override
  Widget build(BuildContext context) {
    final target = selected == FitnessGoal.endurance ? 50 : 10;
    return Padding(
      padding: EdgeInsets.fromLTRB(22, compact ? 10 : 24, 22, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'YOUR FIRST RACE',
            style: AppTextStyles.brandLabel.copyWith(
              color: NuvoColors.blue,
              letterSpacing: 2.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'What do you want\nto train for?',
            style: AppTextStyles.displayMedium.copyWith(
              color: NuvoColors.navy,
              fontSize: compact ? 34 : 42,
              height: .96,
              letterSpacing: -1.2,
            ),
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    selected.title.toUpperCase(),
                    style: AppTextStyles.brandLabel.copyWith(
                      color: NuvoColors.navy,
                      letterSpacing: 2.2,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '$target ${selected.suggestedActivity}',
                    style: AppTextStyles.headlineLarge.copyWith(
                      color: NuvoColors.navy,
                      fontSize: 28,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: compact ? 100 : 128,
                    width: double.infinity,
                    child: const CustomPaint(
                      painter: _RacePathPainter(progress: 0),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _GoalSelector(selected: selected, onSelected: onSelected),
        ],
      ),
    );
  }
}

class _GoalSelector extends StatelessWidget {
  const _GoalSelector({required this.selected, required this.onSelected});

  final FitnessGoal selected;
  final ValueChanged<FitnessGoal> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 5,
      runSpacing: 6,
      children: [
        for (final goal in FitnessGoal.values)
          GestureDetector(
            onTap: () => onSelected(goal),
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
              decoration: BoxDecoration(
                color: selected == goal ? NuvoColors.blue : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected == goal ? NuvoColors.blue : NuvoColors.navy,
                  width: 1.2,
                ),
                boxShadow: selected == goal ? AppShadows.hardSmall : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    goal.icon,
                    size: 15,
                    color: selected == goal
                        ? NuvoColors.white
                        : NuvoColors.navy,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _shortLabel(goal),
                    style: AppTextStyles.labelSmall.copyWith(
                      color: selected == goal
                          ? NuvoColors.white
                          : NuvoColors.navy,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  String _shortLabel(FitnessGoal goal) => switch (goal) {
    FitnessGoal.strength => 'Strength',
    FitnessGoal.endurance => 'Endurance',
    FitnessGoal.consistency => 'Consistency',
    FitnessGoal.crew => 'Crew',
    FitnessGoal.milestone => 'Milestone',
  };
}

class _PracticePage extends StatelessWidget {
  const _PracticePage({
    required this.goal,
    required this.progress,
    required this.started,
    required this.compact,
  });

  final FitnessGoal goal;
  final double progress;
  final bool started;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final reps = (progress * 3).floor().clamp(0, 3);
    return Padding(
      padding: EdgeInsets.fromLTRB(22, compact ? 10 : 24, 22, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PRACTICE MODE',
            style: AppTextStyles.brandLabel.copyWith(
              color: NuvoColors.blue,
              letterSpacing: 2.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'See how your\nmove becomes proof.',
            style: AppTextStyles.displayMedium.copyWith(
              color: NuvoColors.navy,
              fontSize: compact ? 34 : 42,
              height: .96,
              letterSpacing: -1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This is an example using ${goal.suggestedActivity}. Your real proof happens inside a race.',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.muted),
          ),
          Expanded(
            child: Center(
              child: SizedBox(
                width: double.infinity,
                height: compact ? 230 : 270,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: NuvoColors.navy,
                        borderRadius: BorderRadius.circular(26),
                        boxShadow: AppShadows.hardSmall,
                      ),
                    ),
                    CustomPaint(
                      size: Size.infinite,
                      painter: _PracticePosePainter(progress: progress),
                    ),
                    Positioned(
                      top: 15,
                      left: 17,
                      child: Text(
                        'EXAMPLE PROOF',
                        style: AppTextStyles.brandLabel.copyWith(
                          color: NuvoColors.white,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 15,
                      right: 17,
                      child: Text(
                        progress >= .99 ? 'READY' : 'PRACTICE',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: NuvoColors.blue,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 16,
                      child: Text(
                        '$reps / 3 REPS',
                        style: AppTextStyles.titleMedium.copyWith(
                          color: NuvoColors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Text(
            started
                ? progress >= .99
                      ? 'That is how proof moves the board.'
                      : 'Follow the movement as the example plays.'
                : 'Tap practice to watch three example reps.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.muted),
          ),
        ],
      ),
    );
  }
}

class _RacePathPainter extends CustomPainter {
  const _RacePathPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _racePath(size);
    final navy = Paint()
      ..color = NuvoColors.navy
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    final blue = Paint()
      ..color = NuvoColors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, navy);
    final metrics = path.computeMetrics().toList();
    if (metrics.isNotEmpty) {
      canvas.drawPath(
        metrics.first.extractPath(0, metrics.first.length * progress),
        blue,
      );
    }
    final metric = path.computeMetrics().first;
    final start = metric.getTangentForOffset(0);
    final end = metric.getTangentForOffset(metric.length);
    if (start == null || end == null) return;
    canvas.drawCircle(start.position, 8, Paint()..color = NuvoColors.blue);
    _drawNuvoFlag(canvas, anchor: end.position, scale: 1, opacity: 1);
  }

  @override
  bool shouldRepaint(covariant _RacePathPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _PosePainter extends CustomPainter {
  const _PosePainter({required this.phase});

  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // Keep the proof example visually related to the race path, rather than
    // presenting a disconnected pose skeleton in the middle of the card.
    final path = Path()
      ..moveTo(size.width * .16, size.height * .76)
      ..cubicTo(
        size.width * .30,
        size.height * .22,
        size.width * .61,
        size.height * .88,
        size.width * .79,
        size.height * .28,
      );
    final metric = path.computeMetrics().first;
    final travel = Curves.easeInOutCubic.transform(
      (phase * .86 + .07).clamp(0.0, 1.0).toDouble(),
    );
    final tangent = metric.getTangentForOffset(metric.length * travel);
    if (tangent == null) return;

    final direction = Offset(math.cos(tangent.angle), math.sin(tangent.angle));
    final normal = Offset(-direction.dy, direction.dx);
    final swing = math.sin(phase * math.pi * 2) * .18;
    final position = tangent.position + normal * 4;
    final scale = (size.shortestSide / 246).clamp(.78, 1.04).toDouble();
    final runnerAngle = tangent.angle + math.pi / 2 + swing;

    final tether = Paint()
      ..color = NuvoColors.white.withValues(alpha: .22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 13
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final tetherCore = Paint()
      ..color = NuvoColors.blue.withValues(alpha: .92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, tether);
    canvas.drawPath(path, tetherCore);

    canvas.save();
    canvas.translate(position.dx, position.dy);
    canvas.rotate(runnerAngle);
    canvas.scale(scale);

    final outer = Paint()
      ..color = NuvoColors.navy
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final inner = Paint()
      ..color = NuvoColors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final coral = Paint()..color = NuvoColors.coral;
    final highlight = Paint()..color = NuvoColors.white.withValues(alpha: .9);

    final chest = const Offset(0, -4);
    final head = const Offset(0, -34);
    final shoulder = const Offset(0, -10);
    final hip = const Offset(0, 22);
    final leftElbow = Offset(-25 - swing * 15, -2);
    final leftHand = Offset(-42 - swing * 20, 18);
    final rightElbow = Offset(24 + swing * 12, -19);
    final rightHand = Offset(45 + swing * 20, -43);
    final leftKnee = Offset(-19 - swing * 11, 43);
    final leftFoot = Offset(-47 - swing * 18, 65);
    final rightKnee = Offset(23 + swing * 11, 37);
    final rightFoot = Offset(48 + swing * 16, 55);
    final handOffset =
        Offset(
          rightHand.dx * math.cos(runnerAngle) -
              rightHand.dy * math.sin(runnerAngle),
          rightHand.dx * math.sin(runnerAngle) +
              rightHand.dy * math.cos(runnerAngle),
        ) *
        scale;
    final hand = position + handOffset;

    void limb(Offset start, Offset end) {
      canvas.drawLine(start, end, outer);
      canvas.drawLine(start, end, inner);
    }

    limb(shoulder, leftElbow);
    limb(leftElbow, leftHand);
    limb(shoulder, rightElbow);
    limb(rightElbow, rightHand);
    limb(hip, leftKnee);
    limb(leftKnee, leftFoot);
    limb(hip, rightKnee);
    limb(rightKnee, rightFoot);

    // A compact, layered body gives the figure the outlined game-piece read
    // without reverting to the generic joint-and-bones stick figure.
    canvas.drawCircle(chest, 17, Paint()..color = NuvoColors.navy);
    canvas.drawCircle(chest, 14, highlight);
    canvas.drawCircle(chest, 11, coral);
    canvas.drawCircle(head, 22, Paint()..color = NuvoColors.navy);
    canvas.drawCircle(head, 18, highlight);
    canvas.drawCircle(head, 15, coral);
    canvas.drawCircle(head.translate(-5, -6), 3.2, highlight);

    // The raised hand meets the tether with a small electric-blue hook point.
    canvas.drawCircle(rightHand, 7, Paint()..color = NuvoColors.navy);
    canvas.drawCircle(rightHand, 4, Paint()..color = NuvoColors.blue);
    canvas.restore();

    final hookPath = Path()
      ..moveTo(hand.dx, hand.dy)
      ..quadraticBezierTo(
        hand.dx + direction.dx * 13,
        hand.dy + direction.dy * 13,
        tangent.position.dx,
        tangent.position.dy,
      );
    canvas.drawPath(
      hookPath,
      Paint()
        ..color = NuvoColors.white.withValues(alpha: .7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _PosePainter oldDelegate) =>
      oldDelegate.phase != phase;
}

class _PracticePosePainter extends CustomPainter {
  const _PracticePosePainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // The practice visual is a small contained motion system: the runner,
    // hook, and tether share one path so the movement reads as intentional.
    final path = Path()
      ..moveTo(size.width * .14, size.height * .77)
      ..cubicTo(
        size.width * .24,
        size.height * .18,
        size.width * .47,
        size.height * .86,
        size.width * .78,
        size.height * .27,
      );
    final metric = path.computeMetrics().first;
    final travel = Curves.easeInOutCubic.transform(progress.clamp(0.0, 1.0));
    final tangent = metric.getTangentForOffset(metric.length * travel);
    if (tangent == null) return;

    final direction = Offset(math.cos(tangent.angle), math.sin(tangent.angle));
    final normal = Offset(-direction.dy, direction.dx);
    final swing = math.sin(progress * math.pi * 4);
    final bob = math.sin(progress * math.pi * 6) * 3;

    final tether = Paint()
      ..color = NuvoColors.navy.withValues(alpha: .96)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final tetherCore = Paint()
      ..color = NuvoColors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, tether);
    canvas.drawPath(path, tetherCore);

    final start = metric.getTangentForOffset(0)?.position;
    if (start != null) {
      canvas.drawCircle(start, 8, Paint()..color = NuvoColors.blue);
      canvas.drawCircle(
        start,
        11,
        Paint()
          ..color = NuvoColors.navy
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }

    final runnerPosition = tangent.position + normal * (10 + bob);
    final runnerAngle = tangent.angle + math.pi / 2 + swing * .1;
    canvas.save();
    canvas.translate(runnerPosition.dx, runnerPosition.dy);
    canvas.rotate(runnerAngle);
    _drawHookRunner(canvas, swing: swing, progress: progress);
    canvas.restore();

    // A short hook line gives the figure a physical connection to the course.
    final hookOffset = Offset(
      -math.sin(runnerAngle) * 23,
      math.cos(runnerAngle) * 23,
    );
    final hook = runnerPosition + hookOffset;
    final hookPath = Path()
      ..moveTo(hook.dx, hook.dy)
      ..quadraticBezierTo(
        hook.dx + direction.dx * 16,
        hook.dy + direction.dy * 16,
        tangent.position.dx,
        tangent.position.dy,
      );
    canvas.drawPath(
      hookPath,
      Paint()
        ..color = NuvoColors.white.withValues(alpha: .76)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawHookRunner(
    Canvas canvas, {
    required double swing,
    required double progress,
  }) {
    final outer = Paint()
      ..color = NuvoColors.navy
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final inner = Paint()
      ..color = NuvoColors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final joints = Paint()..color = NuvoColors.blue;
    final body = Paint()..color = NuvoColors.coral;
    final highlight = Paint()..color = NuvoColors.white.withValues(alpha: .8);

    final reach = math.sin(progress * math.pi * 2) * 5;
    final head = const Offset(0, -34);
    final chest = const Offset(0, -7);
    final hip = const Offset(0, 22);
    final shoulder = const Offset(0, -12);
    final leftElbow = Offset(-25 - swing * 5, -2 + reach);
    final rightElbow = Offset(27 + swing * 4, -18 - reach);
    final leftHand = Offset(-38 - swing * 8, 20 + reach * .4);
    final rightHand = Offset(44 + swing * 8, -38 - reach * .6);
    final leftKnee = Offset(-19 - swing * 5, 43);
    final rightKnee = Offset(24 + swing * 6, 37);
    final leftFoot = Offset(-48 - swing * 8, 64);
    final rightFoot = Offset(47 + swing * 6, 55);

    void limb(Offset a, Offset b) {
      canvas.drawLine(a, b, outer);
      canvas.drawLine(a, b, inner);
    }

    limb(shoulder, leftElbow);
    limb(leftElbow, leftHand);
    limb(shoulder, rightElbow);
    limb(rightElbow, rightHand);
    limb(hip, leftKnee);
    limb(leftKnee, leftFoot);
    limb(hip, rightKnee);
    limb(rightKnee, rightFoot);

    canvas.drawCircle(chest, 15, outer..style = PaintingStyle.fill);
    canvas.drawCircle(chest, 10, body);
    canvas.drawCircle(head, 21, outer..style = PaintingStyle.fill);
    canvas.drawCircle(head, 16, body);
    canvas.drawCircle(head.translate(-5, -5), 3, highlight);

    for (final point in [
      chest,
      leftElbow,
      rightElbow,
      leftKnee,
      rightKnee,
      rightHand,
    ]) {
      canvas.drawCircle(point, 6, joints);
      canvas.drawCircle(
        point,
        6,
        Paint()
          ..color = NuvoColors.navy
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PracticePosePainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _ProgressPainter extends CustomPainter {
  const _ProgressPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final start = Offset(12, y);
    final end = Offset(size.width - 12, y);
    final base = Paint()
      ..color = NuvoColors.navy.withValues(alpha: .18)
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    final active = Paint()
      ..color = NuvoColors.blue
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(start, end, base);
    canvas.drawLine(start, Offset.lerp(start, end, progress)!, active);
  }

  @override
  bool shouldRepaint(covariant _ProgressPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _AmbientPainter extends CustomPainter {
  const _AmbientPainter({required this.progress, required this.opacity});

  final double progress;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    final t = progress * math.pi * 2;
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = NuvoColors.page);

    final markCenter = Offset(size.width / 2, size.height * .43);
    final markField = Rect.fromCenter(
      center: markCenter,
      width: size.width * .66,
      height: size.height * .34,
    );
    canvas.drawOval(
      markField,
      Paint()
        ..shader = RadialGradient(
          // One hue (brand blue) at falling alpha, per the design guide —
          // no second palette for the glow effect.
          colors: [
            NuvoColors.blue.withValues(alpha: .27 * opacity),
            NuvoColors.blue.withValues(alpha: .13 * opacity),
            NuvoColors.blue.withValues(alpha: 0),
          ],
          stops: const [0, .45, 1],
        ).createShader(markField),
    );

    const columns = 18;
    const rows = 31;
    final spacingX = size.width / (columns + 1);
    final spacingY = size.height / (rows + 1);
    final dotPaint = Paint()..style = PaintingStyle.fill;
    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        final x = spacingX * (column + 1);
        final y = spacingY * (row + 1);
        final nx = column / (columns - 1);
        final ny = row / (rows - 1);
        final centerDistance = math.sqrt(
          math.pow(nx - .5, 2) + math.pow(ny - .46, 2),
        );
        final diagonal = nx * .9 + ny * 1.1;
        final expandingRing = math.sin(t * 2.8 - centerDistance * 20.0);
        final counterRing = math.sin(t * 2.2 - (1 - centerDistance) * 17.0);
        final diagonalBurst = math.sin(t * 2.1 - diagonal * 11.0);
        final pulse =
            (((expandingRing + 1) * .48) +
                    ((counterRing + 1) * .30) +
                    ((diagonalBurst + 1) * .22))
                .clamp(0.0, 1.0)
                .toDouble();
        final visibility = ((pulse - .22) / .78).clamp(0.0, 1.0).toDouble();
        final quietZone = centerDistance < .13 ? .28 : 1.0;
        final radius =
            (.28 + Curves.easeOut.transform(visibility) * 1.55) * quietZone;
        dotPaint.color = Color.lerp(
          NuvoColors.blueLight.withValues(alpha: .025 * opacity),
          NuvoColors.blue.withValues(alpha: .30 * opacity),
          visibility,
        )!;
        canvas.drawCircle(Offset(x, y), radius, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AmbientPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.opacity != opacity;
}

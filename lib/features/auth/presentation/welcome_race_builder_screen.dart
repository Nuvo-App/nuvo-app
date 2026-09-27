import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_flip_text.dart';
import '../../onboarding/data/first_use_store.dart';
import '../../races/domain/motion_activity.dart';
import '../../races/domain/motion_activity_catalog.dart';
import '../../races/presentation/widgets/rive_movement_preview.dart';
import 'welcome_auth_screen.dart';
import 'welcome_onboarding_state.dart';
import 'welcome_opening_cinematic.dart';

class WelcomeRaceBuilderScreen extends ConsumerStatefulWidget {
  const WelcomeRaceBuilderScreen({super.key});

  @override
  ConsumerState<WelcomeRaceBuilderScreen> createState() =>
      _WelcomeRaceBuilderScreenState();
}

class _WelcomeRaceBuilderScreenState
    extends ConsumerState<WelcomeRaceBuilderScreen>
    with TickerProviderStateMixin {
  static const _pageCount = 5;
  late final PageController _pageController;
  late final AnimationController _ambientController;
  late final List<_ActivityOption> _activityOptions;

  int _page = 0;
  // Jumping Jacks — the working Rive preview already supports it, and the
  // movement page already used it, so this keeps the same activity in view
  // through the rest of onboarding.
  int _selectedActivityIndex = 1;
  // Every page now manages its own one-time entrance/readiness locally (see
  // _onPageNReady below) instead of sharing one flag/timer driven by page
  // changes — sharing one previously meant leaving a page could silently
  // un-ready a different page that reused the same field. Each flag is set
  // once and never reset; returning to an already-ready page is never a
  // replay.
  bool _page0Ready = false;
  bool _page1Ready = false;
  bool _page2Ready = false;
  bool _page3Ready = false;

  bool get _pageReady => switch (_page) {
    0 => _page0Ready,
    1 => _page1Ready,
    2 => _page2Ready,
    3 => _page3Ready,
    // Page 4 (auth) owns its own actions directly and never shows the
    // shared footer, so its readiness is never actually read for rendering.
    _ => true,
  };

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _activityOptions = _buildOnboardingActivityOptions();
    // Constructed eagerly (not as a lazy `late final` field initializer) so
    // the onboarding page tree staying unbuilt behind the opening cinematic
    // can never make dispose() the first access — that would create a
    // ticker against an already-deactivated context.
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    );
    // Continuous decorative background; its own opacity is gated by page/
    // readiness state below, so it's safe to just let it run.
    _ambientController.repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Seeds the shared welcome-builder state that /welcome's own preview
      // reads (untouched auth-screen internals) — this pre-auth flow no
      // longer exposes a fitness-goal picker itself, so this is just a
      // stable default rather than a live selection.
      ref
          .read(welcomeOnboardingStateProvider.notifier)
          .selectFitnessGoal(FitnessGoal.strength);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _ambientController.dispose();
    super.dispose();
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

  void _next() => _goToPage(_page + 1);

  void _selectActivity(int index) {
    if (_selectedActivityIndex == index) return;
    HapticFeedback.selectionClick();
    // Illustrative onboarding selection only — local state, no backend call
    // and no real race is created.
    setState(() => _selectedActivityIndex = index);
  }

  /// Every page owns its own entrance (animation → hold → CTA) and reports
  /// back through one of these exactly once, when it's actually ready —
  /// never in response to a page change, timer, or rebuild.
  void _onPage0Ready() {
    if (_page0Ready) return;
    setState(() => _page0Ready = true);
  }

  void _onPage1Ready() {
    if (_page1Ready) return;
    setState(() => _page1Ready = true);
  }

  void _onPage2Ready() {
    if (_page2Ready) return;
    setState(() => _page2Ready = true);
  }

  void _onPage3Ready() {
    if (_page3Ready) return;
    setState(() => _page3Ready = true);
  }

  void _onPageChanged(int page) {
    // Every page manages its own one-time entrance/readiness locally (see
    // _onPageNReady) and is never rebuilt from scratch by the PageView —
    // returning to one is never a replay.
    setState(() => _page = page);
    // Reaching the auth page means the whole product narrative ran — the
    // cinematic never needs to replay on later signed-out launches.
    if (page == _pageCount - 1) {
      unawaited(ref.read(firstUseStoreProvider).markIntroSeen());
    }
  }

  void _skipToAuth() {
    // Skipping is a choice made after seeing the product story begins — the
    // install counts as onboarded to the intro either way.
    unawaited(ref.read(firstUseStoreProvider).markIntroSeen());
    context.go('/welcome');
  }

  String get _buttonLabel => switch (_page) {
    0 => 'See how it works',
    1 => 'Keep going',
    2 => 'Choose my direction',
    _ => 'Continue',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NuvoColors.page,
      body: SafeArea(child: _buildOnboarding(context)),
    );
  }

  Widget _buildOnboarding(BuildContext context) => AnimatedBuilder(
    animation: _ambientController,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 720;
        final ready = _pageReady;
        // Page 0's own atmosphere fades in with its own readiness.
        final atmosphereReveal = _page == 0 ? (ready ? 1.0 : 0.0) : 1.0;
        final isLastPage = _page == _pageCount - 1;
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
                _OnboardingHeader(
                  page: _page,
                  pageCount: _pageCount,
                  compact: compact,
                  onBack: _page == 0 ? null : () => _goToPage(_page - 1),
                  // The final auth screen has nowhere else to skip to.
                  onSkip: (_page == 0 || isLastPage) ? null : _skipToAuth,
                  showTrailing: !isLastPage,
                ),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    onPageChanged: _onPageChanged,
                    // The cinematic + first-screen entrance must not be
                    // bypassable by an accidental swipe — only once it has
                    // settled can the PageView move at all.
                    physics: _page == 0 && !ready
                        ? const NeverScrollableScrollPhysics()
                        : const PageScrollPhysics(),
                    children: [
                      TickerMode(
                        enabled: _page == 0,
                        child: _WelcomePage(
                          compact: compact,
                          onReady: _onPage0Ready,
                        ),
                      ),
                      TickerMode(
                        enabled: _page == 1,
                        child: _LeaderboardPage(
                          compact: compact,
                          onReady: _onPage1Ready,
                        ),
                      ),
                      TickerMode(
                        enabled: _page == 2,
                        child: _MovementPage(
                          compact: compact,
                          onReady: _onPage2Ready,
                        ),
                      ),
                      TickerMode(
                        enabled: _page == 3,
                        child: _ActivityPageContainer(
                          options: _activityOptions,
                          selectedIndex: _selectedActivityIndex,
                          compact: compact,
                          onSelected: _selectActivity,
                          onReady: _onPage3Ready,
                        ),
                      ),
                      TickerMode(enabled: _page == 4, child: const _AuthPage()),
                    ],
                  ),
                ),
                // The final auth screen owns its own Sign up / Log in
                // actions directly (see _AuthPage) — it never shows the
                // shared single-CTA footer.
                if (!isLastPage)
                  AnimatedSize(
                    duration: const Duration(milliseconds: 460),
                    curve: Curves.easeInOutCubic,
                    alignment: Alignment.topCenter,
                    clipBehavior: Clip.none,
                    child: !ready
                        ? const SizedBox.shrink()
                        // Every page's footer readiness IS that page's own
                        // entrance settling — never a page-unrelated shared
                        // timeline. The CTA slides up from the bottom once,
                        // the moment it's allowed to exist at all.
                        : _CtaReveal(
                            child: _OnboardingFooter(
                              page: _page,
                              pageCount: _pageCount,
                              label: _buttonLabel,
                              onPressed: _next,
                              enabled: ready,
                              compact: compact,
                            ),
                          ),
                  ),
              ],
            ),
          ],
        );
      },
    ),
  );
}

class _OnboardingHeader extends StatelessWidget {
  const _OnboardingHeader({
    required this.page,
    required this.pageCount,
    required this.compact,
    required this.onBack,
    this.onSkip,
    this.showTrailing = true,
  });

  final int page;
  final int pageCount;
  final bool compact;
  final VoidCallback? onBack;
  final VoidCallback? onSkip;

  /// False on the final auth screen: no Skip, and no "x / y" page count —
  /// there's nowhere else to go and nothing left to communicate as "still
  /// in progress".
  final bool showTrailing;

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
                ? null
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
          const Spacer(),
          if (showTrailing)
            if (onSkip != null)
              GestureDetector(
                onTap: onSkip,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
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

/// Plays a single slide-up + fade-in the moment it's first built — used for
/// every self-managed page's CTA, which only exists once that page's own
/// entrance has actually settled. An explicit controller (not an implicit
/// widget) is used deliberately: an implicit animation has no "before" value
/// to animate from on its first build, so it would just snap straight to
/// its target instead of visibly sliding in.
class _CtaReveal extends StatefulWidget {
  const _CtaReveal({required this.child});

  final Widget child;

  @override
  State<_CtaReveal> createState() => _CtaRevealState();
}

class _CtaRevealState extends State<_CtaReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      final t = Curves.easeOut.transform(_controller.value);
      return Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 22 * (1 - t)),
          child: widget.child,
        ),
      );
    },
  );
}

/// Screen 0 and Screen 1 are one continuous composition. The cinematic path
/// draws and holds at its finished frame (WelcomeOpeningCinematic never
/// unmounts or gets crossfaded away); once it's held, this page's own short
/// text/CTA entrance plays on top of that same still frame — no swap to a
/// different tree, no separate "slide".
class _WelcomePage extends StatefulWidget {
  const _WelcomePage({required this.compact, required this.onReady});

  final bool compact;
  final VoidCallback onReady;

  @override
  State<_WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<_WelcomePage>
    with AutomaticKeepAliveClientMixin {
  bool _textStarted = false;
  bool _readyReported = false;
  Timer? _holdTimer;

  // PageView disposes offscreen pages by default, which would replay this
  // page's one-shot cinematic/text entrance every time the user swiped back
  // to it. Its state must survive being scrolled away.
  @override
  bool get wantKeepAlive => true;

  void _onPathComplete() {
    setState(() => _textStarted = true);
  }

  void _onTextSettled() {
    if (_readyReported) return;
    // Every onboarding page holds its settled final state for a beat before
    // the CTA appears — the text finishing is not itself the cue.
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    _holdTimer = Timer(
      reducedMotion
          ? const Duration(milliseconds: 300)
          : const Duration(milliseconds: 1500),
      () {
        if (!mounted || _readyReported) return;
        _readyReported = true;
        widget.onReady();
      },
    );
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        WelcomeOpeningCinematic(onComplete: _onPathComplete),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, widget.compact ? 12 : 20),
            child: _WelcomeEntranceText(
              play: _textStarted,
              compact: widget.compact,
              onCompleted: _onTextSettled,
            ),
          ),
        ),
      ],
    );
  }
}

class _WelcomeEntranceText extends StatelessWidget {
  const _WelcomeEntranceText({
    required this.play,
    required this.compact,
    required this.onCompleted,
  });

  final bool play;
  final bool compact;
  final VoidCallback onCompleted;

  @override
  Widget build(BuildContext context) {
    // The cinematic's finish arriving is the trigger; the headline flips in
    // a beat later and the supporting line follows on its own short delay —
    // sequenced, not simultaneous. The support line reports settling so the
    // page can hold before the CTA.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        NuvoFlipText(
          'Welcome to Nuvo.',
          textAlign: TextAlign.center,
          style: AppTextStyles.displayMedium.copyWith(
            color: NuvoColors.navy,
            fontSize: compact ? 30 : 36,
            height: 1.05,
          ),
          play: play,
          delay: const Duration(milliseconds: 140),
          duration: const Duration(milliseconds: 1500),
        ),
        SizedBox(height: compact ? 8 : 12),
        NuvoFlipText(
          'Your goals are now something you can compete on with friends.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyLarge.copyWith(
            color: NuvoColors.muted,
            height: 1.3,
            fontSize: compact ? 16 : 19,
          ),
          play: play,
          delay: const Duration(milliseconds: 620),
          duration: const Duration(milliseconds: 1700),
          onCompleted: onCompleted,
        ),
      ],
    );
  }
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

class _LeaderboardPage extends StatefulWidget {
  const _LeaderboardPage({required this.compact, required this.onReady});

  final bool compact;
  final VoidCallback onReady;

  @override
  State<_LeaderboardPage> createState() => _LeaderboardPageState();
}

/// Isolated from the legacy 18s scene controller, same as page 0: the
/// overtake board plays and settles on its own, this page's own short text
/// entrance follows, then a deliberate hold before the CTA. Nothing here
/// ever advances the PageView on its own.
class _LeaderboardPageState extends State<_LeaderboardPage>
    with AutomaticKeepAliveClientMixin {
  bool _textStarted = false;
  Timer? _holdTimer;
  bool _readyReported = false;

  // Same reasoning as page 0: don't let PageView dispose this page (and
  // replay its overtake) just because the user swiped away and back.
  @override
  bool get wantKeepAlive => true;

  void _onBoardSettled() {
    setState(() => _textStarted = true);
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    // Hold the completed first-place board for a beat so the viewer
    // actually registers the overtake before the CTA appears.
    _holdTimer = Timer(
      reducedMotion
          ? const Duration(milliseconds: 300)
          : const Duration(milliseconds: 1550),
      () {
        if (!mounted || _readyReported) return;
        _readyReported = true;
        widget.onReady();
      },
    );
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.compact ? 14 : 20),
      // Top-aligned rather than `Center`-ed: the footer below the PageView
      // appears/disappears on its own (unrelated) 2.4s timer as pages
      // change, which shrinks or grows this page's available height. A
      // vertically centered layout would visibly re-center — and so shift
      // the board — every time that happens. Anchoring to the top makes
      // this page's position depend only on constant padding above it.
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Align(
              alignment: Alignment.topCenter,
              child: _LeaderboardVisual(
                play: _textStarted,
                compact: widget.compact,
                onBoardSettled: _onBoardSettled,
              ),
            ),
          ),
        ),
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
  const _LeaderboardVisual({
    required this.play,
    required this.compact,
    required this.onBoardSettled,
  });

  final bool play;
  final bool compact;
  final VoidCallback onBoardSettled;

  @override
  Widget build(BuildContext context) {
    // The board stays fully visible the whole time; once it settles the
    // three lines flip in underneath as one cascading statement — each
    // line's delay overlaps the previous line's flip so it reads as a wave,
    // not three separate entrances.
    final lineStyle = AppTextStyles.displayMedium.copyWith(
      color: NuvoColors.navy,
      fontSize: compact ? 32 : 42,
      height: .94,
      letterSpacing: -1.6,
      fontWeight: FontWeight.w800,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _OvertakeBoard(compact: compact, onSettled: onBoardSettled),
        SizedBox(height: compact ? 18 : 26),
        NuvoFlipText(
          'Every rep',
          textAlign: TextAlign.center,
          style: lineStyle,
          play: play,
          duration: const Duration(milliseconds: 1150),
        ),
        SizedBox(height: compact ? 4 : 6),
        NuvoFlipText(
          'changes your',
          textAlign: TextAlign.center,
          style: lineStyle,
          play: play,
          delay: const Duration(milliseconds: 350),
          duration: const Duration(milliseconds: 1150),
        ),
        SizedBox(height: compact ? 4 : 6),
        NuvoFlipText(
          'position.',
          textAlign: TextAlign.center,
          style: lineStyle.copyWith(color: NuvoColors.blue),
          play: play,
          delay: const Duration(milliseconds: 700),
          duration: const Duration(milliseconds: 1150),
        ),
      ],
    );
  }
}

/// The physical overtake: REST (registering "you're third") → the score
/// changes → GRAB → LIFT/CARRY above the stack → the other two rows shift
/// down underneath it → DROP into first → a tiny elastic settle. Plays once
/// per mount, then holds its final order. Deliberately slow — this is a
/// story the viewer watches, not a transition to wait out.
class _OvertakeBoard extends StatefulWidget {
  const _OvertakeBoard({required this.compact, required this.onSettled});

  final bool compact;
  final VoidCallback onSettled;

  @override
  State<_OvertakeBoard> createState() => _OvertakeBoardState();
}

class _OvertakeBoardState extends State<_OvertakeBoard>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 3150);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _duration,
  )..addStatusListener(_onStatus);
  bool _started = false;
  bool _settled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || _settled) return;
    _settled = true;
    widget.onSettled();
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_onStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) =>
        _OvertakeBoardScene(t: _controller.value, compact: widget.compact),
  );
}

class _OvertakeBoardScene extends StatelessWidget {
  const _OvertakeBoardScene({required this.t, required this.compact});

  final double t;
  final bool compact;

  // Phase boundaries as fractions of the 3150ms total (see class doc):
  // settle 0–700ms (register "you're third"), score change 700–1200ms,
  // grab 1200–1350ms, carry 1350–2500ms (rows shift down, gently staggered,
  // 1500–2350ms / 1580–2400ms within it), the card eases into first
  // 2500–2850ms, with a tiny placed-not-dropped settle in the final 300ms.
  static const _scoreStart = 700 / 3150;
  static const _scoreEnd = 1200 / 3150;
  static const _grabStart = 1200 / 3150;
  static const _grabEnd = 1350 / 3150;
  static const _carryStart = 1350 / 3150;
  static const _carryEnd = 2500 / 3150;
  static const _mayaDownStart = 1500 / 3150;
  static const _mayaDownEnd = 2350 / 3150;
  static const _priyaDownStart = 1580 / 3150;
  static const _priyaDownEnd = 2400 / 3150;
  static const _dropStart = 2500 / 3150;
  static const _settleStart = 2850 / 3150;

  @override
  Widget build(BuildContext context) {
    final rowHeight = compact ? 62.0 : 72.0;
    final rowGap = compact ? 9.0 : 12.0;
    final stageHeight = compact ? 300.0 : 330.0;
    final stageWidth = compact ? 320.0 : 348.0;
    final groupHeight = (rowHeight * 3) + (rowGap * 2);
    final groupTop = (stageHeight - groupHeight) / 2;
    final firstRow = groupTop;
    final secondRow = firstRow + rowHeight + rowGap;
    final thirdRow = secondRow + rowHeight + rowGap;
    // Lifted only modestly above the stack — this is a card being carried
    // up past the others, not launched into the air above them.
    final aboveRow = firstRow - 22;

    final scoreT = Curves.easeOut.transform(
      ((t - _scoreStart) / (_scoreEnd - _scoreStart)).clamp(0.0, 1.0),
    );
    final grab = Curves.easeOut.transform(
      ((t - _grabStart) / (_grabEnd - _grabStart)).clamp(0.0, 1.0),
    );
    final carryUp = Curves.easeInOutCubic.transform(
      ((t - _carryStart) / (_carryEnd - _carryStart)).clamp(0.0, 1.0),
    );
    final mayaDown = Curves.easeInOutCubic.transform(
      ((t - _mayaDownStart) / (_mayaDownEnd - _mayaDownStart)).clamp(0.0, 1.0),
    );
    final priyaDown = Curves.easeInOutCubic.transform(
      ((t - _priyaDownStart) / (_priyaDownEnd - _priyaDownStart)).clamp(
        0.0,
        1.0,
      ),
    );
    final drop = Curves.easeInOutCubic.transform(
      ((t - _dropStart) / (_settleStart - _dropStart)).clamp(0.0, 1.0),
    );
    // A gentle placed-not-dropped correction: easeOutBack's own overshoot is
    // scaled down to a couple of pixels rather than let ride at full size.
    final settle = Curves.easeOutBack.transform(
      ((t - _settleStart) / (1 - _settleStart)).clamp(0.0, 1.0),
    );
    final winner = t > _settleStart;
    final youScore = lerpDouble(2, 8, scoreT)!.round();

    // Grab lifts the card just 3px before the carry's own larger ascent
    // takes over — the two hand off smoothly since grab is already fully
    // settled (grab == 1) by the moment carryUp starts moving.
    final microLift = -3.0 * grab * (1 - carryUp);
    final ascendY = lerpDouble(thirdRow, aboveRow, carryUp)!;
    // A small placed correction rides on top of the fully-dropped position;
    // it decays to 0 by the end of the settle window.
    final landingCorrection = 3.0 * (settle - 1.0);
    final youTop = drop > 0
        ? lerpDouble(aboveRow, firstRow, drop)! + landingCorrection
        : ascendY + microLift;

    // A small horizontal deviation while carried keeps the card close to
    // its column — this is a carry, not a wide swing out and back.
    final arcT = carryUp * (1 - drop);
    final youDx = math.sin(arcT * math.pi) * 16;

    final carriedAmount = (((grab * .4) + (carryUp * .6)) * (1 - drop)).clamp(
      0.0,
      1.0,
    );
    // A very small elastic correction on scale, not a dramatic pulse.
    final settleWobble = .05 * (settle - 1.0);
    final youScale = drop > 0
        ? lerpDouble(1.02, 1.0, drop)! + settleWobble
        : 1.0 + (.02 * grab) + (.005 * carryUp);
    final youShadow = BoxShadow.lerp(
      AppShadows.hardSmall.first,
      AppShadows.hardMedium.first,
      carriedAmount,
    )!;

    // The other two rows shift down by exactly one slot to make room, with
    // a slight stagger between them. Their own scores never change — only
    // their rank does, once overtaken.
    final mayaTop = firstRow + ((secondRow - firstRow) * mayaDown);
    final priyaTop = secondRow + ((thirdRow - secondRow) * priyaDown);

    return SizedBox(
      width: stageWidth,
      height: stageHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: mayaTop,
            left: 0,
            right: 0,
            child: _RankRow(
              height: rowHeight,
              rank: winner ? '2' : '1',
              name: 'Maya Chen',
              score: '6 / 10',
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
              score: '4 / 10',
            ),
          ),
          // "You" is always the topmost Stack child — it must visibly pass
          // over the other two rows while carried, at every phase, not just
          // while its own opacity/scale happen to be highest.
          Positioned(
            top: youTop,
            left: 0,
            right: 0,
            child: Transform.translate(
              offset: Offset(youDx, 0),
              child: Transform.scale(
                scale: youScale,
                child: _RankRow(
                  height: rowHeight,
                  rank: winner ? '1' : '3',
                  name: 'You',
                  score: '$youScore / 10',
                  active: winner,
                  emphasis: true,
                  shadowOverride: [youShadow],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MovementPage extends StatefulWidget {
  const _MovementPage({required this.compact, required this.onReady});

  final bool compact;
  final VoidCallback onReady;

  @override
  State<_MovementPage> createState() => _MovementPageState();
}

/// "I do the real movement, Nuvo can understand/count it" — demonstrated
/// with the actual working Rive jumping-jack preview, not a fabricated proof
/// card. The rep counter is driven by this page's own short local timeline
/// (the preview loops continuously and exposes no per-rep callback), synced
/// to the preview's documented ~1s cycle. Isolated from the legacy 18s scene
/// controller, same as every other redesigned page.
class _MovementPageState extends State<_MovementPage>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  static const _duration = Duration(milliseconds: 4100);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _duration,
  )..addStatusListener(_onStatus);
  bool _started = false;
  bool _readyReported = false;
  Timer? _holdTimer;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    _holdTimer = Timer(
      reducedMotion
          ? const Duration(milliseconds: 300)
          : const Duration(milliseconds: 1400),
      () {
        if (!mounted || _readyReported) return;
        _readyReported = true;
        widget.onReady();
      },
    );
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _controller.removeStatusListener(_onStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // No `Expanded`/fixed layout here — short devices (the 320×568 class)
    // can't fit the headline + Rive preview + counter without scrolling,
    // and this page has no other safety net against that.
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(22, widget.compact ? 10 : 24, 22, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NuvoFlipText(
            'Just do the activity.',
            style: AppTextStyles.displayMedium.copyWith(
              color: NuvoColors.navy,
              fontSize: widget.compact ? 34 : 42,
              height: .95,
              letterSpacing: -1.2,
            ),
            delay: const Duration(milliseconds: 180),
            duration: const Duration(milliseconds: 1400),
          ),
          SizedBox(height: widget.compact ? 8 : 12),
          NuvoFlipText(
            'Nuvo verifies your movement and updates your progress.',
            style: AppTextStyles.bodyLarge.copyWith(
              color: NuvoColors.muted,
              height: 1.25,
            ),
            delay: const Duration(milliseconds: 700),
            duration: const Duration(milliseconds: 1600),
          ),
          SizedBox(height: widget.compact ? 16 : 24),
          Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => _MovementVisual(
                t: _controller.value,
                compact: widget.compact,
              ),
            ),
          ),
          SizedBox(height: widget.compact ? 8 : 16),
        ],
      ),
    );
  }
}

class _MovementVisual extends StatelessWidget {
  const _MovementVisual({required this.t, required this.compact});

  final double t;
  final bool compact;

  // Boundaries as fractions of the 4100ms total: 400ms settle, three ~1s
  // reps with short gaps between them, then a brief "Verified" reveal.
  static const _rep1At = 1400 / 4100;
  static const _rep2At = 2600 / 4100;
  static const _rep3At = 3800 / 4100;

  @override
  Widget build(BuildContext context) {
    final reps = t >= _rep3At
        ? 3
        : t >= _rep2At
        ? 2
        : t >= _rep1At
        ? 1
        : 0;
    final verified = t >= 1;
    final size = compact ? 210.0 : 280.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: RiveJumpingJackPreview(
            fallback: Icon(
              Icons.accessibility_new_rounded,
              size: size * .5,
              color: NuvoColors.navy.withValues(alpha: .3),
            ),
          ),
        ),
        SizedBox(height: compact ? 16 : 22),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: verified
              ? Row(
                  key: const ValueKey('verified'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: NuvoColors.blue,
                      size: 22,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Verified',
                      style: AppTextStyles.titleMedium.copyWith(
                        color: NuvoColors.navy,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                )
              : Text(
                  '$reps / 3',
                  key: ValueKey(reps),
                  style: AppTextStyles.titleMedium.copyWith(
                    color: NuvoColors.navy,
                    fontWeight: FontWeight.w900,
                  ),
                ),
        ),
      ],
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
    this.shadowOverride,
  }) : ghost = false;

  final String rank;
  final String name;
  final String score;
  final double height;
  final bool active;
  final bool ghost;
  final bool emphasis;
  final List<BoxShadow>? shadowOverride;

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
        boxShadow:
            shadowOverride ??
            (active || emphasis ? AppShadows.hardSmall : null),
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

class _ActivityOption {
  const _ActivityOption({
    required this.chipLabel,
    required this.eyebrow,
    required this.exampleLabel,
    required this.icon,
  });

  final String chipLabel;
  final String eyebrow;
  final String exampleLabel;
  final IconData icon;
}

/// Built from the production movement catalog (motion_activity_catalog.dart)
/// rather than a second, invented category system — titles, categories, and
/// icons here are the exact same ones the real race composer uses. Only
/// "Teach Nuvo" has no catalog entry (it produces a custom pose spec, not a
/// [MotionActivityType]), so it gets a simple illustrative label instead —
/// tapping it does not enter the real Teach Nuvo flow.
List<_ActivityOption> _buildOnboardingActivityOptions() {
  final pushUps = motionActivityForType(MotionActivityType.pushUps)!;
  final jumpingJacks = motionActivityForType(MotionActivityType.jumpingJacks)!;
  final plank = motionActivityForType(MotionActivityType.plankHold)!;
  final running = motionActivityForType(MotionActivityType.runningInPlace)!;

  return [
    _ActivityOption(
      chipLabel: pushUps.title,
      eyebrow: pushUps.category.label.toUpperCase(),
      // 50 is one of pushUps' own suggestedTargets — not invented.
      exampleLabel: '50 ${pushUps.title}',
      icon: pushUps.icon,
    ),
    _ActivityOption(
      chipLabel: jumpingJacks.title,
      eyebrow: jumpingJacks.category.label.toUpperCase(),
      exampleLabel: '50 ${jumpingJacks.title}',
      icon: jumpingJacks.icon,
    ),
    _ActivityOption(
      chipLabel: plank.title,
      eyebrow: plank.category.label.toUpperCase(),
      // Plank is a duration goal — targetLabel formats its own defaultTarget
      // as "20 seconds" the same way the composer would.
      exampleLabel: '${plank.title}: ${plank.targetLabel(plank.defaultTarget)}',
      icon: plank.icon,
    ),
    _ActivityOption(
      chipLabel: running.title,
      eyebrow: running.category.label.toUpperCase(),
      // runningInPlace's own defaultTarget/unit already read as "50 steps".
      exampleLabel:
          '${running.title}: ${running.targetLabel(running.defaultTarget)}',
      icon: running.icon,
    ),
    const _ActivityOption(
      chipLabel: 'Teach Nuvo',
      eyebrow: 'CUSTOM',
      exampleLabel: 'Your Own Movement',
      icon: Icons.auto_awesome_rounded,
    ),
  ];
}

class _ActivityPageContainer extends StatefulWidget {
  const _ActivityPageContainer({
    required this.options,
    required this.selectedIndex,
    required this.compact,
    required this.onSelected,
    required this.onReady,
  });

  final List<_ActivityOption> options;
  final int selectedIndex;
  final bool compact;
  final ValueChanged<int> onSelected;
  final VoidCallback onReady;

  @override
  State<_ActivityPageContainer> createState() => _ActivityPageContainerState();
}

/// Isolated from the legacy scene timeline, same as every other redesigned
/// page: a short settle, then hold, then the CTA slides up. This page's
/// content itself is static (no reveal choreography to run), so the only
/// state owned here is that hold.
class _ActivityPageContainerState extends State<_ActivityPageContainer>
    with AutomaticKeepAliveClientMixin {
  bool _started = false;
  bool _readyReported = false;
  Timer? _holdTimer;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    _holdTimer = Timer(
      reducedMotion
          ? const Duration(milliseconds: 300)
          : const Duration(milliseconds: 900),
      () {
        if (!mounted || _readyReported) return;
        _readyReported = true;
        widget.onReady();
      },
    );
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _ActivityPage(
      options: widget.options,
      selectedIndex: widget.selectedIndex,
      compact: widget.compact,
      onSelected: widget.onSelected,
    );
  }
}

class _ActivityPage extends StatelessWidget {
  const _ActivityPage({
    required this.options,
    required this.selectedIndex,
    required this.compact,
    required this.onSelected,
  });

  final List<_ActivityOption> options;
  final int selectedIndex;
  final bool compact;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final selected = options[selectedIndex];
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        key: const ValueKey('onboarding-activity-scroll'),
        padding: EdgeInsets.fromLTRB(22, compact ? 10 : 24, 22, 8),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: math.max(0, constraints.maxHeight - (compact ? 18 : 32)),
          ),
          child: IntrinsicHeight(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'YOUR FIRST RACE',
                  style: AppTextStyles.brandLabel.copyWith(
                    color: NuvoColors.blue,
                    letterSpacing: 2.2,
                  ),
                ),
                const SizedBox(height: 8),
                NuvoFlipText(
                  'What do you want\nto race on?',
                  style: AppTextStyles.displayMedium.copyWith(
                    color: NuvoColors.navy,
                    fontSize: constraints.maxWidth < 360
                        ? 28
                        : (compact ? 32 : 38),
                    height: .96,
                    letterSpacing: -1.2,
                  ),
                  delay: const Duration(milliseconds: 150),
                  duration: const Duration(milliseconds: 1400),
                ),
                // The eyebrow, example label, and path are one visual mass —
                // centering only the text while the path painter's own geometry
                // reads off-center (see _RacePathPainter) would still look
                // lopsided, so this whole block is centered as a unit and the
                // painter itself centers its rendered bounds within its box.
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: Column(
                        key: const ValueKey('onboarding-activity-visual'),
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            selected.eyebrow,
                            textAlign: TextAlign.center,
                            style: AppTextStyles.brandLabel.copyWith(
                              color: NuvoColors.navy,
                              letterSpacing: 2.2,
                            ),
                          ),
                          const SizedBox(height: 5),
                          NuvoFlipText(
                            selected.exampleLabel,
                            textAlign: TextAlign.center,
                            style: AppTextStyles.headlineLarge.copyWith(
                              color: NuvoColors.navy,
                              fontSize: 26,
                            ),
                            duration: const Duration(
                              milliseconds: 1200,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: compact ? 76 : 128,
                            width: double.infinity,
                            child: const CustomPaint(
                              key: ValueKey('onboarding-activity-path'),
                              painter: _RacePathPainter(progress: 0),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                _ActivityChips(
                  options: options,
                  selectedIndex: selectedIndex,
                  onSelected: onSelected,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivityChips extends StatelessWidget {
  const _ActivityChips({
    required this.options,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<_ActivityOption> options;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 5,
      runSpacing: 6,
      children: [
        for (var i = 0; i < options.length; i++)
          Semantics(
            key: ValueKey('onboarding-activity-$i'),
            button: true,
            selected: i == selectedIndex,
            child: InkWell(
              onTap: () => onSelected(i),
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                constraints: const BoxConstraints(minHeight: 44),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
                decoration: BoxDecoration(
                  color: i == selectedIndex
                      ? NuvoColors.blue
                      : NuvoColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: NuvoColors.navy, width: 1.2),
                  boxShadow: i == selectedIndex ? AppShadows.hardSmall : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (MediaQuery.sizeOf(context).width >= 360) ...[
                      Icon(
                        options[i].icon,
                        size: 15,
                        color: i == selectedIndex
                            ? NuvoColors.white
                            : NuvoColors.navy,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      options[i].chipLabel,
                      style: AppTextStyles.labelSmall.copyWith(
                        color: i == selectedIndex
                            ? NuvoColors.white
                            : NuvoColors.navy,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _AuthPage extends StatelessWidget {
  const _AuthPage();

  @override
  Widget build(BuildContext context) => const WelcomeAuthScreen(embedded: true);
}

class _RacePathPainter extends CustomPainter {
  const _RacePathPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _racePath(size);
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final metric = metrics.first;
    final start = metric.getTangentForOffset(0);
    final end = metric.getTangentForOffset(metric.length);
    if (start == null || end == null) return;

    // The route's own control points don't produce a visually centered
    // curve by themselves (a curve can be mathematically centered while its
    // rendered mass — plus the finish marker, which sits past the route's
    // own endpoint — reads as biased to one side). Measure the actual
    // rendered bounds, including the finish marker's extent, and translate
    // so that combined mass is centered in the given canvas.
    final flagExtent = Rect.fromLTRB(
      end.position.dx + 8,
      end.position.dy - 28,
      end.position.dx + 44,
      end.position.dy + 20,
    );
    final visualBounds = path
        .getBounds()
        .inflate(8)
        .expandToInclude(flagExtent);
    var pathCenterX = 0.0;
    for (var i = 0; i < 64; i++) {
      pathCenterX += metric
          .getTangentForOffset(metric.length * (i + .5) / 64)!
          .position
          .dx;
    }
    final pathArea = metric.length * 12;
    final visualCenterX =
        ((pathCenterX / 64) * pathArea +
            (end.position.dx + 25) * 350 +
            start.position.dx * 200) /
        (pathArea + 550);
    final scale = math.min(
      1.0,
      math.min(
        (size.width - 8) / visualBounds.width,
        (size.height - 8) / visualBounds.height,
      ),
    );
    final offsetX = (size.width / 2 - visualCenterX * scale).clamp(
      4 - visualBounds.left * scale,
      size.width - 4 - visualBounds.right * scale,
    );
    final centeringOffset = Offset(
      offsetX,
      size.height / 2 - visualBounds.center.dy * scale,
    );

    canvas.save();
    canvas.translate(centeringOffset.dx, centeringOffset.dy);
    canvas.scale(scale);

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
    canvas.drawPath(metric.extractPath(0, metric.length * progress), blue);
    canvas.drawCircle(start.position, 8, Paint()..color = NuvoColors.blue);
    _drawNuvoFlag(canvas, anchor: end.position, scale: 1, opacity: 1);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RacePathPainter oldDelegate) =>
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

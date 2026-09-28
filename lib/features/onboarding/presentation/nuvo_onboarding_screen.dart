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
import '../../../core/widgets/nuvo_avatar.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_flip_text.dart';
import '../../../core/widgets/nuvo_number_flow.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../auth/presentation/welcome_opening_cinematic.dart';
import '../../profile/application/progression_controller.dart';
import '../../races/presentation/widgets/rive_movement_preview.dart';
import 'first_use_guide.dart';

/// The canonical Nuvo first-use onboarding — runs AFTER account creation and
/// profile/legal setup, while `onboardingComplete` is still false. Its one
/// job is teaching the product loop:
///
///   RACE → MOVE → PROVE → CLIMB → LEVEL UP
///
/// Because it runs post-auth it can personalize with the real account
/// (first name on the opening and final pages, the real name on the demo
/// leaderboard, the real progression payload on the last page). It never
/// writes XP, races, or proof — every score/level animation is labelled
/// local presentation state; the only server write is completeOnboarding()
/// on the final CTA, which is what makes completion durable across
/// reinstall, new device, and logout/login.
class NuvoOnboardingScreen extends ConsumerStatefulWidget {
  const NuvoOnboardingScreen({super.key});

  @override
  ConsumerState<NuvoOnboardingScreen> createState() =>
      _NuvoOnboardingScreenState();
}

class _NuvoOnboardingScreenState extends ConsumerState<NuvoOnboardingScreen>
    with TickerProviderStateMixin {
  static const _pageCount = 8;
  static const _lastPage = _pageCount - 1;

  late final PageController _pageController;
  late final AnimationController _ambientController;

  int _page = 0;
  // Same contract as the retired pre-auth builder: every page owns its own
  // one-time entrance and reports readiness exactly once — returning to an
  // already-ready page is never a replay.
  final Set<int> _readyPages = {};
  bool get _pageReady => _readyPages.contains(_page);

  bool _finishing = false;
  String? _finishError;

  /// The user's real first name, or null when the account has no usable name
  /// (e.g. an Apple private-relay sign-up that skipped the name step). Every
  /// personalized string has a nameless fallback — onboarding must never
  /// stall on missing identity data.
  String? get _firstName {
    final name = ref.read(authControllerProvider).user?.fullName?.trim();
    if (name == null || name.isEmpty) return null;
    final first = name.split(RegExp(r'\s+')).first;
    return first[0].toUpperCase() + first.substring(1);
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat();
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

  /// Skip always lands on the payoff page — the user still owns the final
  /// "Start your first race" decision; skipping only compresses the story.
  void _skip() => _goToPage(_lastPage);

  void _markReady(int page) {
    if (_readyPages.contains(page)) return;
    setState(() => _readyPages.add(page));
  }

  String get _buttonLabel => switch (_page) {
    0 => 'Show me',
    _lastPage => 'Start your first race',
    _ => 'Keep going',
  };

  /// The graduation write. `completeOnboarding()` is the server-backed
  /// first-use flag — without it the next launch bounces the account back
  /// into setup. Demo replay never writes account state; it exits into the
  /// guided first-race tour instead.
  Future<void> _finish() async {
    if (_finishing) return;
    HapticFeedback.mediumImpact();
    if (ref.read(demoReplayProvider)) {
      ref.read(demoReplayProvider.notifier).state = false;
      ref.read(firstRaceGuideProvider.notifier).state =
          FirstRaceGuideStep.competeStart;
      if (mounted) context.go('/compete');
      return;
    }
    setState(() {
      _finishing = true;
      _finishError = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).completeOnboarding();
      if (mounted) context.go('/arena');
    } catch (_) {
      if (mounted) {
        setState(() {
          _finishing = false;
          _finishError =
              'Could not finish. Check your connection and try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // The capture boundary is how the QA harness snapshots every page
    // (NUVO_ONBOARDING_CAPTURE=true + test/nuvo_onboarding_test.dart) — keep
    // it at the screen root so captures include the full canvas.
    return RepaintBoundary(
      key: const ValueKey('onboarding-capture'),
      child: Scaffold(
        backgroundColor: NuvoColors.page,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _ambientController,
          builder: (context, _) => LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 720;
              final narrow = constraints.maxWidth < 360;
              final ready = _pageReady;
              final atmosphereReveal = _page == 0 ? (ready ? 1.0 : 0.0) : 1.0;
              final firstName = _firstName;
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
                        onSkip: (_page == 0 || _page == _lastPage)
                            ? null
                            : _skip,
                        showTrailing: _page != _lastPage,
                      ),
                      Expanded(
                        child: PageView(
                          controller: _pageController,
                          onPageChanged: (page) =>
                              setState(() => _page = page),
                          // The opening cinematic must not be bypassable by an
                          // accidental swipe — only once it has settled can the
                          // PageView move at all.
                          physics: _page == 0 && !ready
                              ? const NeverScrollableScrollPhysics()
                              : const PageScrollPhysics(),
                          children: [
                            TickerMode(
                              enabled: _page == 0,
                              child: _IntroPage(
                                firstName: firstName,
                                compact: compact,
                                onReady: () => _markReady(0),
                              ),
                            ),
                            TickerMode(
                              enabled: _page == 1,
                              child: _RaceAnythingPage(
                                compact: compact,
                                narrow: narrow,
                                onReady: () => _markReady(1),
                              ),
                            ),
                            TickerMode(
                              enabled: _page == 2,
                              child: _MovePage(
                                compact: compact,
                                onReady: () => _markReady(2),
                              ),
                            ),
                            TickerMode(
                              enabled: _page == 3,
                              child: _ClimbPage(
                                firstName: firstName,
                                compact: compact,
                                onReady: () => _markReady(3),
                              ),
                            ),
                            TickerMode(
                              enabled: _page == 4,
                              child: _LevelPage(
                                compact: compact,
                                onReady: () => _markReady(4),
                              ),
                            ),
                            TickerMode(
                              enabled: _page == 5,
                              child: _IdentityPage(
                                compact: compact,
                                onReady: () => _markReady(5),
                              ),
                            ),
                            TickerMode(
                              enabled: _page == 6,
                              child: _CrewPage(
                                firstName: firstName,
                                compact: compact,
                                onReady: () => _markReady(6),
                              ),
                            ),
                            TickerMode(
                              enabled: _page == 7,
                              child: _ReadyPage(
                                firstName: firstName,
                                compact: compact,
                                onReady: () => _markReady(7),
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
                        child: !ready
                            ? const SizedBox.shrink()
                            : _CtaReveal(
                                child: _OnboardingFooter(
                                  page: _page,
                                  pageCount: _pageCount,
                                  label: _buttonLabel,
                                  loading: _page == _lastPage && _finishing,
                                  error: _page == _lastPage
                                      ? _finishError
                                      : null,
                                  onPressed:
                                      _page == _lastPage ? _finish : _next,
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
        ),
      ),
      ),
    );
  }
}

// ── Chrome ────────────────────────────────────────────────────────────────────

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
    required this.compact,
    this.loading = false,
    this.error,
  });

  final int page;
  final int pageCount;
  final String label;
  final VoidCallback onPressed;
  final bool compact;
  final bool loading;
  final String? error;

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
            loading: loading,
            onPressed: loading ? null : onPressed,
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(
              error!,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(color: NuvoColors.danger),
            ),
          ],
        ],
      ),
    );
  }
}

/// Plays a single slide-up + fade-in the moment it's first built — used for
/// every self-managed page's CTA, which only exists once that page's own
/// entrance has actually settled.
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

// ── Page 1 · This is Nuvo ─────────────────────────────────────────────────────

/// The cinematic race-path opening, unchanged from the pre-auth presentation —
/// but now it greets a real person instead of an anonymous install.
class _IntroPage extends StatefulWidget {
  const _IntroPage({
    required this.firstName,
    required this.compact,
    required this.onReady,
  });

  final String? firstName;
  final bool compact;
  final VoidCallback onReady;

  @override
  State<_IntroPage> createState() => _IntroPageState();
}

class _IntroPageState extends State<_IntroPage>
    with AutomaticKeepAliveClientMixin {
  bool _textStarted = false;
  bool _readyReported = false;
  Timer? _holdTimer;

  @override
  bool get wantKeepAlive => true;

  void _onTextSettled() {
    if (_readyReported) return;
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
    final name = widget.firstName;
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        WelcomeOpeningCinematic(
          onComplete: () => setState(() => _textStarted = true),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, widget.compact ? 12 : 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                NuvoFlipText(
                  name != null ? 'Ready, $name?' : 'Ready?',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.displayMedium.copyWith(
                    color: NuvoColors.navy,
                    fontSize: widget.compact ? 32 : 40,
                    height: 1.05,
                  ),
                  play: _textStarted,
                  delay: const Duration(milliseconds: 140),
                  duration: const Duration(milliseconds: 1500),
                ),
                SizedBox(height: widget.compact ? 8 : 12),
                NuvoFlipText(
                  'Make real life a race.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: NuvoColors.muted,
                    height: 1.3,
                    fontSize: widget.compact ? 16 : 19,
                  ),
                  play: _textStarted,
                  delay: const Duration(milliseconds: 620),
                  duration: const Duration(milliseconds: 1700),
                  onCompleted: _onTextSettled,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Page 2 · Race anything ────────────────────────────────────────────────────

/// FlexiRace's whole idea in one glance: the finish line is whatever you set.
/// Examples cycle as animated text — deliberately NOT four cards — over a
/// race path that fills a little further with each one.
class _RaceAnythingPage extends StatefulWidget {
  const _RaceAnythingPage({
    required this.compact,
    required this.narrow,
    required this.onReady,
  });

  final bool compact;
  final bool narrow;
  final VoidCallback onReady;

  @override
  State<_RaceAnythingPage> createState() => _RaceAnythingPageState();
}

class _RaceAnythingPageState extends State<_RaceAnythingPage>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  static const _examples = [
    'First to 100 pushups',
    'Highest math grade',
    'Lowest golf score',
    'First to finish 5 books',
  ];
  static const _exampleWindow = Duration(milliseconds: 1600);

  int _index = 0;
  Timer? _cycle;
  Timer? _readyTimer;
  bool _readyReported = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_readyReported || _cycle != null) return;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    if (reducedMotion) {
      // Reduced motion: hold the first example, mark ready after a beat —
      // the story still reads, nothing cycles.
      _readyTimer = Timer(const Duration(milliseconds: 900), _reportReady);
      return;
    }
    _cycle = Timer.periodic(_exampleWindow, (_) {
      if (!mounted) return;
      if (_index >= _examples.length - 1) {
        _cycle?.cancel();
        // Hold the last example so the "anything" idea lands before the CTA.
        _readyTimer = Timer(const Duration(milliseconds: 1100), _reportReady);
        return;
      }
      setState(() => _index++);
    });
  }

  void _reportReady() {
    if (!mounted || _readyReported) return;
    _readyReported = true;
    widget.onReady();
  }

  @override
  void dispose() {
    _cycle?.cancel();
    _readyTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(22, widget.compact ? 10 : 24, 22, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'FLEXIRACE',
            style: AppTextStyles.brandLabel.copyWith(
              color: NuvoColors.blue,
              letterSpacing: 2.2,
            ),
          ),
          const SizedBox(height: 8),
          NuvoFlipText(
            'Race anything.',
            style: AppTextStyles.displayMedium.copyWith(
              color: NuvoColors.navy,
              fontSize: widget.compact ? 34 : 42,
              height: .96,
              letterSpacing: -1.2,
            ),
            delay: const Duration(milliseconds: 150),
            duration: const Duration(milliseconds: 1400),
          ),
          SizedBox(height: widget.compact ? 14 : 26),
          SizedBox(
            height: widget.compact ? 200 : 260,
            child: Column(
              children: [
                const Spacer(),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 420),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, .35),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: Text(
                    _examples[_index],
                    key: ValueKey(_index),
                    textAlign: TextAlign.center,
                    style: AppTextStyles.headlineLarge.copyWith(
                      color: NuvoColors.navy,
                      fontSize: widget.narrow ? 24 : 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.6,
                    ),
                  ),
                ),
                SizedBox(height: widget.compact ? 14 : 20),
                SizedBox(
                  height: widget.compact ? 64 : 92,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _RacePathPainter(
                      progress: (_index + 1) / _examples.length,
                    ),
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
          SizedBox(height: widget.compact ? 10 : 16),
          NuvoFlipText(
            'Set the finish line. Bring your crew.',
            style: AppTextStyles.bodyLarge.copyWith(
              color: NuvoColors.muted,
              height: 1.3,
            ),
            delay: const Duration(milliseconds: 700),
            duration: const Duration(milliseconds: 1600),
          ),
        ],
      ),
    );
  }
}

// ── Page 3 · Make your move ───────────────────────────────────────────────────

/// Proof turns real effort into race progress. The Rive preview is the
/// working jumping-jack rig (AI Motion Proof as one example); the counter
/// below it plays the acceptance beat: 7/10 → proof accepted → 8/10.
class _MovePage extends StatefulWidget {
  const _MovePage({required this.compact, required this.onReady});

  final bool compact;
  final VoidCallback onReady;

  @override
  State<_MovePage> createState() => _MovePageState();
}

class _MovePageState extends State<_MovePage>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  static const _duration = Duration(milliseconds: 4200);
  // Proof lands at ~45% of the timeline; the counter rolls over the next
  // 600ms, then the scene holds so "8 / 10" registers before the CTA.
  static const _proofAt = 1900 / 4200;
  static const _scoreEnd = 2500 / 4200;

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
          : const Duration(milliseconds: 1300),
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
    final size = widget.compact ? 180.0 : 240.0;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(22, widget.compact ? 10 : 24, 22, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NuvoFlipText(
            'Make your move.',
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
            'Real progress becomes race progress.',
            style: AppTextStyles.bodyLarge.copyWith(
              color: NuvoColors.muted,
              height: 1.25,
            ),
            delay: const Duration(milliseconds: 700),
            duration: const Duration(milliseconds: 1600),
          ),
          SizedBox(height: widget.compact ? 12 : 20),
          Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final t = _controller.value;
                final accepted = t >= _proofAt;
                final score = t >= _scoreEnd
                    ? 8
                    : accepted
                    ? 7 + ((t - _proofAt) / (_scoreEnd - _proofAt)).round()
                    : 7;
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
                    SizedBox(height: widget.compact ? 12 : 18),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: accepted
                          ? Row(
                              key: const ValueKey('accepted'),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: NuvoColors.blue,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Proof accepted',
                                  style: AppTextStyles.labelLarge.copyWith(
                                    color: NuvoColors.blue,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            )
                          : Text(
                              'EXAMPLE PROOF',
                              key: const ValueKey('pending'),
                              style: AppTextStyles.brandLabel.copyWith(
                                color: NuvoColors.muted,
                                letterSpacing: 1.6,
                                fontSize: 10,
                              ),
                            ),
                    ),
                    const SizedBox(height: 10),
                    NuvoNumberFlow(
                      value: score,
                      format: (v) => '$v / 10',
                      duration: const Duration(milliseconds: 500),
                      style: AppTextStyles.displayMedium.copyWith(
                        color: NuvoColors.navy,
                        fontSize: widget.compact ? 34 : 42,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1,
                      ),
                    ),
                    SizedBox(height: widget.compact ? 12 : 18),
                    Row(
                      children: [
                        for (final label in const [
                          'MOTION',
                          'PHOTO',
                          'RESULT',
                          'TIME',
                        ])
                          Expanded(
                            child: Text(
                              label,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              softWrap: false,
                              style: AppTextStyles.brandLabel.copyWith(
                                color: label == 'MOTION'
                                    ? NuvoColors.blue
                                    : NuvoColors.muted,
                                letterSpacing: 1.4,
                                fontSize: 10,
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
        ],
      ),
    );
  }
}

// ── Page 4 · Climb the board ──────────────────────────────────────────────────

/// The overtake, told with the person's real name: they start behind Noah,
/// a proof lands, the score rolls 7 → 9, and their row physically carries
/// past Noah into first. Same grab/carry/drop choreography the leaderboard
/// page used — the story the viewer watches, not a transition to wait out.
class _ClimbPage extends StatefulWidget {
  const _ClimbPage({
    required this.firstName,
    required this.compact,
    required this.onReady,
  });

  final String? firstName;
  final bool compact;
  final VoidCallback onReady;

  @override
  State<_ClimbPage> createState() => _ClimbPageState();
}

class _ClimbPageState extends State<_ClimbPage>
    with AutomaticKeepAliveClientMixin {
  bool _textStarted = false;
  Timer? _holdTimer;
  bool _readyReported = false;

  @override
  bool get wantKeepAlive => true;

  void _onBoardSettled() {
    setState(() => _textStarted = true);
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
    final headline = AppTextStyles.displayMedium.copyWith(
      color: NuvoColors.navy,
      fontSize: widget.compact ? 30 : 38,
      height: .96,
      letterSpacing: -1.4,
      fontWeight: FontWeight.w800,
    );
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(22, widget.compact ? 8 : 16, 22, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _OvertakeScene(
            playerName: widget.firstName ?? 'You',
            compact: widget.compact,
            onSettled: _onBoardSettled,
          ),
          SizedBox(height: widget.compact ? 16 : 24),
          NuvoFlipText(
            'Climb the board.',
            textAlign: TextAlign.center,
            style: headline,
            play: _textStarted,
            duration: const Duration(milliseconds: 1150),
          ),
          SizedBox(height: widget.compact ? 6 : 8),
          NuvoFlipText(
            'Every move can change the race.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyLarge.copyWith(
              color: NuvoColors.muted,
              height: 1.3,
            ),
            play: _textStarted,
            delay: const Duration(milliseconds: 400),
            duration: const Duration(milliseconds: 1300),
          ),
        ],
      ),
    );
  }
}

class _OvertakeScene extends StatefulWidget {
  const _OvertakeScene({
    required this.playerName,
    required this.compact,
    required this.onSettled,
  });

  final String playerName;
  final bool compact;
  final VoidCallback onSettled;

  @override
  State<_OvertakeScene> createState() => _OvertakeSceneState();
}

class _OvertakeSceneState extends State<_OvertakeScene>
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
    builder: (context, _) => _OvertakeSceneFrame(
      t: _controller.value,
      playerName: widget.playerName,
      compact: widget.compact,
    ),
  );
}

class _OvertakeSceneFrame extends StatelessWidget {
  const _OvertakeSceneFrame({
    required this.t,
    required this.playerName,
    required this.compact,
  });

  final double t;
  final String playerName;
  final bool compact;

  // Phase boundaries as fractions of the 3150ms total:
  // settle 0–700ms (register "you're second"), score rolls 700–1200ms,
  // grab 1200–1350ms, carry 1350–2500ms (Noah shifts down 1500–2350ms),
  // drop into first 2500–2850ms, elastic settle to end.
  static const _scoreStart = 700 / 3150;
  static const _scoreEnd = 1200 / 3150;
  static const _grabStart = 1200 / 3150;
  static const _grabEnd = 1350 / 3150;
  static const _carryStart = 1350 / 3150;
  static const _carryEnd = 2500 / 3150;
  static const _noahDownStart = 1500 / 3150;
  static const _noahDownEnd = 2350 / 3150;
  static const _dropStart = 2500 / 3150;
  static const _settleStart = 2850 / 3150;

  @override
  Widget build(BuildContext context) {
    final rowHeight = compact ? 60.0 : 70.0;
    final rowGap = compact ? 9.0 : 12.0;
    final stageWidth = compact ? 316.0 : 344.0;
    final pillHeight = compact ? 26.0 : 30.0;
    final groupHeight = (rowHeight * 3) + (rowGap * 2);
    final stageHeight = groupHeight + pillHeight + 40;
    final groupTop = pillHeight + 20.0;
    final firstRow = groupTop;
    final secondRow = firstRow + rowHeight + rowGap;
    final thirdRow = secondRow + rowHeight + rowGap;
    final aboveRow = firstRow - 20;

    final scoreT = Curves.easeOut.transform(
      ((t - _scoreStart) / (_scoreEnd - _scoreStart)).clamp(0.0, 1.0),
    );
    final grab = Curves.easeOut.transform(
      ((t - _grabStart) / (_grabEnd - _grabStart)).clamp(0.0, 1.0),
    );
    final carryUp = Curves.easeInOutCubic.transform(
      ((t - _carryStart) / (_carryEnd - _carryStart)).clamp(0.0, 1.0),
    );
    final noahDown = Curves.easeInOutCubic.transform(
      ((t - _noahDownStart) / (_noahDownEnd - _noahDownStart)).clamp(0.0, 1.0),
    );
    final drop = Curves.easeInOutCubic.transform(
      ((t - _dropStart) / (_settleStart - _dropStart)).clamp(0.0, 1.0),
    );
    final settle = Curves.easeOutBack.transform(
      ((t - _settleStart) / (1 - _settleStart)).clamp(0.0, 1.0),
    );
    final winner = t > _settleStart;
    final playerScore = lerpDouble(7, 9, scoreT)!.round();
    final proofPill = ((t - _scoreStart) / .1).clamp(0.0, 1.0);

    final microLift = -3.0 * grab * (1 - carryUp);
    final ascendY = lerpDouble(secondRow, aboveRow, carryUp)!;
    final landingCorrection = 3.0 * (settle - 1.0);
    final playerTop = drop > 0
        ? lerpDouble(aboveRow, firstRow, drop)! + landingCorrection
        : ascendY + microLift;

    final arcT = carryUp * (1 - drop);
    final playerDx = math.sin(arcT * math.pi) * 16;

    final carriedAmount = (((grab * .4) + (carryUp * .6)) * (1 - drop)).clamp(
      0.0,
      1.0,
    );
    final settleWobble = .05 * (settle - 1.0);
    final playerScale = drop > 0
        ? lerpDouble(1.02, 1.0, drop)! + settleWobble
        : 1.0 + (.02 * grab) + (.005 * carryUp);
    final playerShadow = BoxShadow.lerp(
      AppShadows.hardSmall.first,
      AppShadows.hardMedium.first,
      carriedAmount,
    )!;

    final noahTop = firstRow + ((secondRow - firstRow) * noahDown);

    return SizedBox(
      width: stageWidth,
      height: stageHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The acceptance beat — why the score is moving at all.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Opacity(
              opacity: proofPill,
              child: Center(
                child: Container(
                  height: pillHeight,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: NuvoColors.blue.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: NuvoColors.blue.withValues(alpha: .5),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        color: NuvoColors.blue,
                        size: 14,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'PROOF ACCEPTED',
                        style: AppTextStyles.brandLabel.copyWith(
                          color: NuvoColors.blue,
                          letterSpacing: 1.3,
                          fontSize: 9.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: noahTop,
            left: 0,
            right: 0,
            child: _RankRow(
              height: rowHeight,
              rank: winner ? '2' : '1',
              name: 'Noah',
              score: '8',
            ),
          ),
          Positioned(
            top: thirdRow,
            left: 0,
            right: 0,
            child: _RankRow(
              height: rowHeight,
              rank: '3',
              name: 'Maya',
              score: '5',
            ),
          ),
          // The player row stays the topmost Stack child — it must visibly
          // pass over Noah's row while carried, at every phase.
          Positioned(
            top: playerTop,
            left: 0,
            right: 0,
            child: Transform.translate(
              offset: Offset(playerDx, 0),
              child: Transform.scale(
                scale: playerScale,
                child: _RankRow(
                  height: rowHeight,
                  rank: winner ? '1' : '2',
                  name: playerName,
                  score: '$playerScore',
                  active: winner,
                  emphasis: true,
                  shadowOverride: [playerShadow],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Page 5 · Level up ─────────────────────────────────────────────────────────

/// Nuvo Levels, introduced with the real design tokens but explicitly framed
/// as an EXAMPLE: +10 XP, +50 XP, bar fills, LEVEL 1 rolls to LEVEL 2.
/// Nothing here writes progression — the final page shows the real payload.
class _LevelPage extends StatefulWidget {
  const _LevelPage({required this.compact, required this.onReady});

  final bool compact;
  final VoidCallback onReady;

  @override
  State<_LevelPage> createState() => _LevelPageState();
}

class _LevelPageState extends State<_LevelPage>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  static const _duration = Duration(milliseconds: 5200);
  // Storyboard: settle 0–1000ms, first award 1000–1900ms (+10, bar → 1/6),
  // second award 2100–3100ms (+50, bar → full), level rolls 3400–4100ms,
  // hold to end.
  static const _award1At = 1000 / 5200;
  static const _award2At = 2100 / 5200;
  static const _barFillEnd = 3100 / 5200;
  static const _levelUpAt = 3400 / 5200;
  static const _levelUpEnd = 4100 / 5200;

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
          : const Duration(milliseconds: 1200),
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
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(22, widget.compact ? 10 : 24, 22, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NuvoFlipText(
            'Every race builds\nyour Nuvo.',
            style: AppTextStyles.displayMedium.copyWith(
              color: NuvoColors.navy,
              fontSize: widget.compact ? 34 : 42,
              height: .96,
              letterSpacing: -1.2,
            ),
            delay: const Duration(milliseconds: 180),
            duration: const Duration(milliseconds: 1400),
          ),
          SizedBox(height: widget.compact ? 18 : 30),
          Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final t = _controller.value;
                final xp = t >= _barFillEnd
                    ? 60
                    : t >= _award2At
                    ? lerpDouble(10, 60, (t - _award2At) / .2)!.round()
                    : t >= _award1At
                    ? lerpDouble(0, 10, (t - _award1At) / .15)!.round()
                    : 0;
                final level = t >= _levelUpAt ? 2 : 1;
                final barFill = (xp / 60).clamp(0.0, 1.0);
                final levelPop = t >= _levelUpAt && t < _levelUpEnd
                    ? Curves.easeOutBack.transform(
                        (t - _levelUpAt) / (_levelUpEnd - _levelUpAt),
                      )
                    : 1.0;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'EXAMPLE',
                      style: AppTextStyles.brandLabel.copyWith(
                        color: NuvoColors.muted,
                        letterSpacing: 1.8,
                        fontSize: 10,
                      ),
                    ),
                    SizedBox(height: widget.compact ? 12 : 18),
                    Text(
                      'LEVEL',
                      style: AppTextStyles.brandLabel.copyWith(
                        color: NuvoColors.blue,
                        letterSpacing: 2.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Transform.scale(
                      scale: levelPop < 1 ? .9 + (.1 * levelPop) : 1,
                      child: NuvoNumberFlow(
                        value: level,
                        duration: const Duration(milliseconds: 600),
                        style: AppTextStyles.displayLarge.copyWith(
                          color: NuvoColors.navy,
                          fontSize: widget.compact ? 64 : 80,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -2,
                        ),
                      ),
                    ),
                    SizedBox(height: widget.compact ? 10 : 14),
                    NuvoNumberFlow(
                      value: xp,
                      format: (v) => '$v / 60 XP',
                      duration: const Duration(milliseconds: 400),
                      style: AppTextStyles.titleLarge.copyWith(
                        color: NuvoColors.blue,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: widget.compact ? 10 : 14),
                    SizedBox(
                      width: widget.compact ? 220 : 260,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: SizedBox(
                          height: 10,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: ColoredBox(
                                  color: NuvoColors.navy.withValues(alpha: .1),
                                ),
                              ),
                              FractionallySizedBox(
                                widthFactor: barFill,
                                child: const ColoredBox(
                                  color: NuvoColors.blue,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: widget.compact ? 14 : 18),
                    SizedBox(
                      height: 26,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 240),
                        child: t >= _levelUpAt
                            ? Row(
                                key: const ValueKey('leveled'),
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.north_rounded,
                                    color: NuvoColors.blue,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Level up',
                                    style: AppTextStyles.labelLarge.copyWith(
                                      color: NuvoColors.blue,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              )
                            : t >= _award2At
                            ? const _XpChip(
                                key: ValueKey('a2'),
                                label: '+50 XP',
                              )
                            : t >= _award1At
                            ? const _XpChip(
                                key: ValueKey('a1'),
                                label: '+10 XP',
                              )
                            : const SizedBox(key: ValueKey('none')),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          SizedBox(height: widget.compact ? 16 : 26),
          NuvoFlipText(
            'Race. Progress. Win. Earn XP and level up.',
            style: AppTextStyles.bodyLarge.copyWith(
              color: NuvoColors.muted,
              height: 1.3,
            ),
            delay: const Duration(milliseconds: 700),
            duration: const Duration(milliseconds: 1600),
          ),
        ],
      ),
    );
  }
}

class _XpChip extends StatelessWidget {
  const _XpChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: NuvoColors.blue.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      label,
      style: AppTextStyles.labelMedium.copyWith(
        color: NuvoColors.blue,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

// ── Page 6 · Build your identity ──────────────────────────────────────────────

/// Progression → identity: a miniature of the real Profile surface — the
/// user's own avatar/name, a level, and the achievement chips that travel
/// with them. Framed as EXAMPLE so nothing reads as earned state.
class _IdentityPage extends ConsumerStatefulWidget {
  const _IdentityPage({required this.compact, required this.onReady});

  final bool compact;
  final VoidCallback onReady;

  @override
  ConsumerState<_IdentityPage> createState() => _IdentityPageState();
}

class _IdentityPageState extends ConsumerState<_IdentityPage>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  static const _duration = Duration(milliseconds: 2600);

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
          : const Duration(milliseconds: 1200),
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

  double _segment(double start, double end) => Curves.easeOutCubic.transform(
    ((_controller.value - start) / (end - start)).clamp(0.0, 1.0),
  );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final user = ref.watch(authControllerProvider).user;
    final name = user?.fullName ?? 'You';
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(22, widget.compact ? 10 : 24, 22, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NuvoFlipText(
            'Make your name\nmean something.',
            style: AppTextStyles.displayMedium.copyWith(
              color: NuvoColors.navy,
              fontSize: widget.compact ? 32 : 40,
              height: .96,
              letterSpacing: -1.2,
            ),
            delay: const Duration(milliseconds: 150),
            duration: const Duration(milliseconds: 1400),
          ),
          SizedBox(height: widget.compact ? 18 : 30),
          Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final cardIn = _segment(0, .3);
                final levelIn = _segment(.3, .55);
                final badgeIn = _segment(.55, 1);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'EXAMPLE',
                      style: AppTextStyles.brandLabel.copyWith(
                        color: NuvoColors.muted,
                        letterSpacing: 1.8,
                        fontSize: 10,
                      ),
                    ),
                    SizedBox(height: widget.compact ? 12 : 16),
                    Opacity(
                      opacity: cardIn,
                      child: Transform.translate(
                        offset: Offset(0, 16 * (1 - cardIn)),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            NuvoAvatar(
                              initials: user?.avatarInitials ?? 'Y',
                              photoUrl: user?.profilePhotoUrl,
                              size: NuvoAvatarSizes.xl,
                              bgColor: nuvoAvatarColorFor(user?.id ?? ''),
                              textColor: NuvoColors.white,
                              borderColor: NuvoColors.navy,
                              borderWidth: 2,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              name,
                              style: AppTextStyles.titleLarge.copyWith(
                                color: NuvoColors.navy,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Opacity(
                              opacity: levelIn,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: NuvoColors.blue.withValues(alpha: .12),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Text(
                                  'LEVEL 8',
                                  style: AppTextStyles.brandLabel.copyWith(
                                    color: NuvoColors.blue,
                                    letterSpacing: 1.6,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: widget.compact ? 16 : 24),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var i = 0; i < _badges.length; i++)
                          Opacity(
                            opacity: ((badgeIn - i * .18) / .5).clamp(0.0, 1.0),
                            child: Transform.translate(
                              offset: Offset(
                                0,
                                14 *
                                    (1 -
                                        ((badgeIn - i * .18) / .5).clamp(
                                          0.0,
                                          1.0,
                                        )),
                              ),
                              child: _BadgeTile(
                                icon: _badges[i].$1,
                                label: _badges[i].$2,
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
          SizedBox(height: widget.compact ? 16 : 24),
          NuvoFlipText(
            'Your level and achievements go with you.',
            style: AppTextStyles.bodyLarge.copyWith(
              color: NuvoColors.muted,
              height: 1.3,
            ),
            delay: const Duration(milliseconds: 700),
            duration: const Duration(milliseconds: 1600),
          ),
        ],
      ),
    );
  }

  static const _badges = [
    (Icons.emoji_events_rounded, 'First W'),
    (Icons.local_fire_department_rounded, 'Five Deep'),
    (Icons.trending_up_rounded, 'Personal Best'),
  ];
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: NuvoColors.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: NuvoColors.navy, width: 1.6),
      boxShadow: AppShadows.hardSmall,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: NuvoColors.blue, size: 20),
        const SizedBox(height: 5),
        Text(
          label,
          style: AppTextStyles.labelSmall.copyWith(
            color: NuvoColors.navy,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

// ── Page 7 · Your crew ────────────────────────────────────────────────────────

/// The social beat: levels mean something because other people see them.
/// Four racers slide in — the user pinned at Lv. 1, the crew already out
/// ahead. That gap is the pull.
class _CrewPage extends StatefulWidget {
  const _CrewPage({
    required this.firstName,
    required this.compact,
    required this.onReady,
  });

  final String? firstName;
  final bool compact;
  final VoidCallback onReady;

  @override
  State<_CrewPage> createState() => _CrewPageState();
}

class _CrewPageState extends State<_CrewPage>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  static const _duration = Duration(milliseconds: 2400);

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
          : const Duration(milliseconds: 1100),
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
    final rows = <(String, int, bool)>[
      ('Shresh', 14, false),
      ('Maya', 9, false),
      ('Noah', 4, false),
      (widget.firstName ?? 'You', 1, true),
    ];
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(22, widget.compact ? 10 : 24, 22, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NuvoFlipText(
            'Better with\ncompetition.',
            style: AppTextStyles.displayMedium.copyWith(
              color: NuvoColors.navy,
              fontSize: widget.compact ? 32 : 40,
              height: .96,
              letterSpacing: -1.2,
            ),
            delay: const Duration(milliseconds: 150),
            duration: const Duration(milliseconds: 1400),
          ),
          SizedBox(height: widget.compact ? 16 : 26),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  _crewRow(rows[i], i),
                  if (i < rows.length - 1)
                    SizedBox(height: widget.compact ? 8 : 10),
                ],
              ],
            ),
          ),
          SizedBox(height: widget.compact ? 16 : 24),
          NuvoFlipText(
            'Race friends. Find rivals. Keep moving.',
            style: AppTextStyles.bodyLarge.copyWith(
              color: NuvoColors.muted,
              height: 1.3,
            ),
            delay: const Duration(milliseconds: 700),
            duration: const Duration(milliseconds: 1600),
          ),
        ],
      ),
    );
  }

  Widget _crewRow((String, int, bool) row, int index) {
    final appear = Curves.easeOutCubic.transform(
      ((_controller.value - index * .16) / .3).clamp(0.0, 1.0),
    );
    final (name, level, isYou) = row;
    return Opacity(
      opacity: appear,
      child: Transform.translate(
        offset: Offset(26 * (1 - appear), 0),
        child: Container(
          height: widget.compact ? 52 : 58,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: NuvoColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: NuvoColors.navy,
              width: isYou ? 2.2 : 1.4,
            ),
            boxShadow: isYou ? AppShadows.hardSmall : null,
          ),
          child: Row(
            children: [
              NuvoAvatar(
                initials: name[0],
                size: 34,
                bgColor: isYou
                    ? NuvoColors.blue
                    : nuvoAvatarColorFor(name),
                textColor: NuvoColors.white,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isYou ? '$name (you)' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelLarge.copyWith(
                    color: NuvoColors.navy,
                    fontWeight: isYou ? FontWeight.w900 : FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: isYou
                      ? NuvoColors.blue
                      : NuvoColors.navy.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Lv. $level',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: isYou ? NuvoColors.white : NuvoColors.navy,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Page 8 · Ready ────────────────────────────────────────────────────────────

/// The payoff — personalized, and anchored to the REAL progression payload:
/// whatever level/XP the server reports is what shows here (a fresh account
/// reads Level 1 / 0 XP). The only place onboarding touches real numbers,
/// precisely so "Your first move starts now" means it.
class _ReadyPage extends ConsumerStatefulWidget {
  const _ReadyPage({
    required this.firstName,
    required this.compact,
    required this.onReady,
  });

  final String? firstName;
  final bool compact;
  final VoidCallback onReady;

  @override
  ConsumerState<_ReadyPage> createState() => _ReadyPageState();
}

class _ReadyPageState extends ConsumerState<_ReadyPage>
    with AutomaticKeepAliveClientMixin {
  bool _readyReported = false;
  Timer? _holdTimer;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_readyReported) return;
    _readyReported = true;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    _holdTimer = Timer(
      reducedMotion
          ? const Duration(milliseconds: 300)
          : const Duration(milliseconds: 1000),
      () {
        if (!mounted) return;
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
    // A still-loading or failed read falls back to the canonical fresh-account
    // values — the alternative (a spinner or a blank stat) breaks the payoff.
    final progression = ref.watch(progressionControllerProvider).valueOrNull;
    final level = progression?.level ?? 1;
    final xp = progression?.totalXp ?? 0;
    final name = widget.firstName;
    return Padding(
      padding: EdgeInsets.fromLTRB(22, widget.compact ? 10 : 24, 22, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Spacer(),
          NuvoFlipText(
            name != null ? '$name, you\'re ready.' : 'You\'re ready.',
            textAlign: TextAlign.center,
            style: AppTextStyles.displayMedium.copyWith(
              color: NuvoColors.navy,
              fontSize: widget.compact ? 32 : 40,
              height: 1.02,
              letterSpacing: -1.2,
            ),
            delay: const Duration(milliseconds: 200),
            duration: const Duration(milliseconds: 1500),
          ),
          SizedBox(height: widget.compact ? 18 : 28),
          Text(
            'LEVEL',
            style: AppTextStyles.brandLabel.copyWith(
              color: NuvoColors.blue,
              letterSpacing: 2.6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$level',
            style: AppTextStyles.displayLarge.copyWith(
              color: NuvoColors.navy,
              fontSize: widget.compact ? 72 : 88,
              fontWeight: FontWeight.w900,
              letterSpacing: -2,
              height: 1,
            ),
          ),
          SizedBox(height: widget.compact ? 8 : 12),
          Text(
            '$xp XP',
            style: AppTextStyles.titleLarge.copyWith(
              color: NuvoColors.muted,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: widget.compact ? 18 : 28),
          NuvoFlipText(
            'Your first move starts now.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyLarge.copyWith(
              color: NuvoColors.muted,
              height: 1.3,
            ),
            delay: const Duration(milliseconds: 800),
            duration: const Duration(milliseconds: 1600),
          ),
          const Spacer(flex: 2),
        ],
      ),
    );
  }
}

// ── Shared visual pieces (carried over from the retired pre-auth builder) ─────

class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.rank,
    required this.name,
    required this.score,
    this.height = 58,
    this.active = false,
    this.emphasis = false,
    this.shadowOverride,
  });

  final String rank;
  final String name;
  final String score;
  final double height;
  final bool active;
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
        color: NuvoColors.surface,
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
                color: rankColor,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
  final poleX = anchor.dx + (12 * scale);
  final poleTop = anchor.dy - (24 * scale);
  final poleBottom = anchor.dy + (16 * scale);
  final polePaint = Paint()
    ..color = NuvoColors.navy.withValues(alpha: opacity)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.2 * scale
    ..strokeCap = StrokeCap.round;
  canvas.drawLine(Offset(poleX, poleTop), Offset(poleX, poleBottom), polePaint);

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

/// The curved navy route + blue progress stroke + finish flag, drawn beneath
/// the cycling race ideas — it fills a little more with each example so
/// "race anything" literally travels toward a finish line.
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

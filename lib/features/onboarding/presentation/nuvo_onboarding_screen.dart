import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/demo/presentation_demo.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_avatar.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../../core/widgets/nuvo_flip_text.dart';
import '../../../core/widgets/nuvo_number_flow.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../auth/presentation/welcome_opening_cinematic.dart';
import '../data/first_use_store.dart';
import '../../profile/application/progression_controller.dart';
import '../../profile/data/progression_models.dart';
import '../../profile/presentation/widgets/nuvo_badges.dart';
import '../../races/presentation/widgets/rive_movement_preview.dart';
import 'first_use_guide.dart';

/// The canonical XP economy, mirrored for teaching. The authoritative table
/// lives in server/worker/src/domain/progression.ts (XP_AWARDS) — onboarding
/// demonstrates the real awards, it never writes them.
const _xpLesson = [
  ('Proof accepted', 10),
  ('Finish a race', 25),
  ('Win bonus', 15),
  ('Personal best', 5),
];

/// Read-only adapter over the canonical achievement collection — onboarding
/// teaches with the REAL definitions (names, icons, thresholds), never an
/// invented second model. Fetch starts the moment the screen mounts so the
/// badge pages have defs ready well before the user reaches them.
final _onboardingAchievementDefsProvider =
    FutureProvider.autoDispose<Map<String, NuvoBadge>>((ref) async {
  final badges = await ref
      .watch(progressionControllerProvider.notifier)
      .getBadges();
  return {for (final b in badges) b.key: b};
});

/// Display literals mirroring shipped defs — used ONLY when the collection
/// can't be read (offline, cold start). Content matches migration 0042 so a
/// failed fetch degrades to the same lesson, not a dead screen.
const Map<String, NuvoBadge> _defFallbacks = {
  'first_move': NuvoBadge(
    unlockId: 'ach-first-move',
    type: 'achievement',
    key: 'first_move',
    name: 'First Move',
    description: 'Submit your first accepted progress.',
    requiredLevel: 0,
    unlocked: false,
    featured: false,
    category: 'racing',
    iconKey: 'arrow_forward',
    statKey: 'progresses_accepted',
    threshold: 1,
  ),
  'hat_trick': NuvoBadge(
    unlockId: 'ach-hat-trick',
    type: 'achievement',
    key: 'hat_trick',
    name: 'Hat Trick',
    description: 'Win 3 races.',
    requiredLevel: 0,
    unlocked: false,
    featured: false,
    category: 'winning',
    iconKey: 'trophy_3',
    statKey: 'races_won',
    threshold: 3,
  ),
  'first_w': NuvoBadge(
    unlockId: 'ach-first-w',
    type: 'achievement',
    key: 'first_w',
    name: 'First W',
    description: 'Win your first race.',
    requiredLevel: 0,
    unlocked: false,
    featured: false,
    category: 'winning',
    iconKey: 'trophy_1',
    statKey: 'races_won',
    threshold: 1,
  ),
  'five_deep': NuvoBadge(
    unlockId: 'ach-five-deep',
    type: 'achievement',
    key: 'five_deep',
    name: 'Five Deep',
    description: 'Finish 5 races.',
    requiredLevel: 0,
    unlocked: false,
    featured: false,
    category: 'racing',
    iconKey: 'flags_5',
    statKey: 'races_finished',
    threshold: 5,
  ),
  'personal_best': NuvoBadge(
    unlockId: 'ach-personal-best',
    type: 'achievement',
    key: 'personal_best',
    name: 'Personal Best',
    description: 'Set your first personal best.',
    requiredLevel: 0,
    unlocked: false,
    featured: false,
    category: 'performance',
    iconKey: 'spark_up',
    statKey: 'pbs_set',
    threshold: 1,
  ),
};

/// The level-2 capability from the canonical unlock ladder
/// (cap-badge-slot-2) — mirrored for the instructional level-up demo when
/// the live payload doesn't carry a level-2 `nextUnlock` (e.g. demo replay
/// at a higher level, or an offline read). Never a fictional reward.
const _levelTwoUnlockFallback = (
  name: 'Second badge slot',
  description: 'Feature a second achievement on your profile.',
);

/// `NuvoBadge` is immutable and has no copyWith — teaching states need
/// locally-mutated display copies (earned, partial progress). These are
/// purely visual; nothing here touches the account.
NuvoBadge _demoBadgeState(
  NuvoBadge base, {
  bool? unlocked,
  int? progressValue,
}) =>
    NuvoBadge(
      unlockId: base.unlockId,
      type: base.type,
      key: base.key,
      name: base.name,
      description: base.description,
      requiredLevel: base.requiredLevel,
      metadata: base.metadata,
      unlocked: unlocked ?? base.unlocked,
      unlockedAt: base.unlockedAt,
      featured: base.featured,
      position: base.position,
      category: base.category,
      iconKey: base.iconKey,
      statKey: base.statKey,
      threshold: base.threshold,
      progressValue: progressValue ?? base.progressValue,
    );

/// The onboarding pages render in the light-chrome visual language
/// (NuvoColors.* constants throughout). Badge widgets read themeColors —
/// pin light so a dark-mode device never drops dark panels onto this page.
Widget _asLightChrome(Widget child) => Theme(
      data: ThemeData(extensions: const [NuvoThemeColors.light]),
      child: child,
    );

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
  /// notification education step (store-review account) or the guided
  /// first-race tour instead.
  Future<void> _finish() async {
    if (_finishing) return;
    HapticFeedback.mediumImpact();
    if (ref.read(demoReplayProvider)) {
      final user = ref.read(authControllerProvider).user;
      final storeDemo = user != null && isNuvoStoreDemoEmail(user.email);
      if (storeDemo) {
        // The review account walks the full first-use sequence: story →
        // notification education → Arena → first-race guide. Mark the step
        // owed BEFORE disarming the replay — once the guard sees the replay
        // off, /onboarding/notifications is only reachable while it is owed.
        // The education screen itself checks live OS state: notDetermined
        // shows the primer and may prompt; already-decided states resolve
        // straight to /arena without re-prompting.
        await ref.read(firstUseStoreProvider).markNotificationPromptOwed();
      }
      ref.read(demoReplayProvider.notifier).state = false;
      if (storeDemo && !user.onboardingComplete) {
        // The server resets the review account to onboardingComplete=false on
        // every signUp-intent sign-in, so this replay finish performs the
        // REAL graduation write — the same completeOnboarding a genuine new
        // account makes.
        // Fall through to the normal finish path below; the replay flag is
        // already disarmed so the guard cannot bounce the session back into
        // the story while the write publishes.
      } else if (storeDemo) {
        // Already-complete demo session (e.g. the offline fallback) — no
        // server write is possible or needed.
        if (mounted) context.go('/onboarding/notifications');
        return;
      } else {
        ref.read(firstRaceGuideProvider.notifier).state =
            FirstRaceGuideStep.competeStart;
        if (mounted) context.go('/compete');
        return;
      }
    }
    setState(() {
      _finishing = true;
      _finishError = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).completeOnboarding();
      // The notification permission moment is the next first-run step —
      // mark it owed so a kill there resumes at it rather than skipping.
      await ref.read(firstUseStoreProvider).markNotificationPromptOwed();
      if (mounted) context.go('/onboarding/notifications');
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
      child: PopScope(
        // Back unwinds the story one page at a time — mirrors the UI back
        // button — and only leaves the flow from page 0.
        canPop: _page == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _page > 0) _goToPage(_page - 1);
        },
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
              // Warm the canonical defs read on mount — the badge pages
              // hit a resolved cache, never a spinner.
              ref.watch(_onboardingAchievementDefsProvider);
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

/// One race example = title + a metric that moves toward its own finish
/// line. `metric` maps race progress (0–1) to the score string, so counting
/// direction itself teaches the rule: books count up, golf counts down.
class _RaceExample {
  const _RaceExample({required this.title, required this.metric});

  final String title;
  final String Function(double progress) metric;
}

class _RaceAnythingPageState extends State<_RaceAnythingPage>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  static const _examples = [
    _RaceExample(
      title: 'First to finish 5 books',
      metric: _booksMetric,
    ),
    _RaceExample(
      title: 'First to 100 pushups',
      metric: _pushupsMetric,
    ),
    _RaceExample(
      title: 'Highest math grade',
      metric: _gradeMetric,
    ),
    _RaceExample(
      title: 'Lowest golf score',
      metric: _golfMetric,
    ),
  ];
  // Each example plays a full race in ~2.4s: progress runs to the finish
  // over the first ~80% and holds on the flag for the last beat.
  static const _exampleWindow = Duration(milliseconds: 2400);
  static const _holdBetween = Duration(milliseconds: 420);

  static String _booksMetric(double t) => '${(t * 5).round()} / 5';
  static String _pushupsMetric(double t) => '${(t * 100).round()} / 100';
  static String _gradeMetric(double t) => '${(82 + t * 13).round()}%';
  // Golf races score in strokes, lower-is-better — the number counts down
  // like a real round coming in. Same unit the race screen shows, never
  // score-to-par.
  static String _golfMetric(double t) =>
      '${(88 - t * 10).round()} strokes';

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _exampleWindow,
  )..addStatusListener(_onStatus);

  int _index = 0;
  Timer? _nextTimer;
  Timer? _readyTimer;
  bool _started = false;
  bool _readyReported = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      // Reduced motion: hold the last race at the finish line — the story
      // still reads, nothing cycles.
      _index = _examples.length - 1;
      _controller.value = 1;
      _readyTimer = Timer(const Duration(milliseconds: 900), _reportReady);
      return;
    }
    _controller.forward();
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (_index >= _examples.length - 1) return;
    _nextTimer = Timer(_holdBetween, () {
      if (!mounted) return;
      setState(() => _index++);
      _controller
        ..reset()
        ..forward();
      if (_index == _examples.length - 1) {
        // The last race keeps playing to its flag behind the revealed CTA —
        // the "anything" idea has landed once every rule has been shown.
        _readyTimer = Timer(const Duration(milliseconds: 1400), _reportReady);
      }
    });
  }

  void _reportReady() {
    if (!mounted || _readyReported) return;
    _readyReported = true;
    widget.onReady();
  }

  @override
  void dispose() {
    _nextTimer?.cancel();
    _readyTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final example = _examples[_index];
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
          ConstrainedBox(
            // minHeight, not height — the example block still fills the
            // stage (Center does what the Spacer pair did) but taller text
            // at accessibility scale grows into the page's scroll instead
            // of overflowing the fixed box.
            constraints: BoxConstraints(
              minHeight: widget.compact ? 210 : 270,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                  child: Column(
                    key: ValueKey(_index),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        example.title,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.headlineLarge.copyWith(
                          color: NuvoColors.navy,
                          fontSize: widget.narrow ? 24 : 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -.6,
                        ),
                      ),
                      SizedBox(height: widget.compact ? 4 : 6),
                      AnimatedBuilder(
                        animation: _controller,
                        builder: (context, _) {
                          final progress = Curves.easeInOutCubic.transform(
                            (_controller.value / .8).clamp(0.0, 1.0),
                          );
                          return Text(
                            example.metric(progress),
                            style: AppTextStyles.titleLarge.copyWith(
                              color: NuvoColors.blue,
                              fontWeight: FontWeight.w800,
                              fontSize: widget.narrow ? 17 : 19,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                SizedBox(height: widget.compact ? 10 : 16),
                SizedBox(
                  height: widget.compact ? 64 : 92,
                  width: double.infinity,
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) {
                      return CustomPaint(
                        painter: _RacePathPainter(
                          progress: Curves.easeInOutCubic.transform(
                            (_controller.value / .8).clamp(0.0, 1.0),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
              ),
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
/// below it plays three acceptance beats — 7 → 8 → 9 → 10 — then a small
/// finish-line payoff, and the loop restarts behind the CTA.
class _MovePage extends StatefulWidget {
  const _MovePage({required this.compact, required this.onReady});

  final bool compact;
  final VoidCallback onReady;

  @override
  State<_MovePage> createState() => _MovePageState();
}

class _MovePageState extends State<_MovePage>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  static const _duration = Duration(milliseconds: 6200);
  // Three rep beats: each rep "travels" while the figure jumps, then the
  // accept lands — pill pulses, score rolls, light haptic. The finish
  // payoff runs from _payoffAt to the end, then the loop restarts.
  static const _accepts = [1600 / 6200, 2900 / 6200, 4200 / 6200];
  static const _acceptFlash = 500 / 6200;
  static const _payoffAt = 4800 / 6200;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _duration,
  )..addStatusListener(_onStatus)
    ..addListener(_maybeHaptic);
  bool _started = false;
  bool _readyReported = false;
  int _acceptsFelt = 0;
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

  void _maybeHaptic() {
    if (MediaQuery.disableAnimationsOf(context)) return;
    final felt = _accepts.where((a) => _controller.value >= a).length;
    if (felt > _acceptsFelt) {
      _acceptsFelt = felt;
      HapticFeedback.lightImpact();
    }
    if (_acceptsFelt == _accepts.length && _controller.value >= _payoffAt) {
      _acceptsFelt++;
      HapticFeedback.mediumImpact();
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (!_readyReported) {
      _readyReported = true;
      widget.onReady();
    }
    if (MediaQuery.disableAnimationsOf(context)) return;
    // Loop the rep sequence so the demo stays alive behind the CTA.
    _holdTimer = Timer(const Duration(milliseconds: 1600), () {
      if (!mounted) return;
      _acceptsFelt = 0;
      _controller.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _controller.removeStatusListener(_onStatus);
    _controller.removeListener(_maybeHaptic);
    _controller.dispose();
    super.dispose();
  }

  int get _score => _accepts.where((a) => _controller.value >= a).length + 7;

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
                final score = _score;
                final finished = t >= _payoffAt;
                final inAcceptFlash = _accepts.any(
                  (a) => t >= a && t < a + _acceptFlash,
                );
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
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: Tween<double>(
                            begin: .8,
                            end: 1,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: finished
                          ? Row(
                              key: const ValueKey('finish'),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: NuvoColors.success,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                // Status pill — a tiny fixed artifact;
                                // clamped so 1.4 scale can't push it
                                // past the column's width.
                                Flexible(
                                  child: Text(
                                    'Race finished',
                                    maxLines: 1,
                                    style: AppTextStyles.labelLarge.copyWith(
                                      color: NuvoColors.successOn,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : inAcceptFlash
                          ? Row(
                              key: ValueKey('acc$score'),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: NuvoColors.blue,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    'Proof accepted',
                                    maxLines: 1,
                                    style: AppTextStyles.labelLarge.copyWith(
                                      color: NuvoColors.blue,
                                      fontWeight: FontWeight.w800,
                                    ),
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
                    // Completion beat: the score pops once and picks up a
                    // small green halo when the race finishes.
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 280),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: finished
                            ? [
                                BoxShadow(
                                  color: NuvoColors.success.withValues(
                                    alpha: .25,
                                  ),
                                  blurRadius: 30,
                                ),
                              ]
                            : const [],
                      ),
                      child: Transform.scale(
                        scale: finished
                            ? .95 +
                                (.05 *
                                    Curves.easeOutBack.transform(
                                      ((t - _payoffAt) / .07)
                                          .clamp(0.0, 1.0),
                                    ))
                            : 1,
                        // Fixed-width score artifact — "10 / 10" is
                        // decorative chrome, clamped so extreme text
                        // scale nudges instead of overflowing.
                        child: MediaQuery.withClampedTextScaling(
                          maxScaleFactor: 1.2,
                          child: NuvoNumberFlow(
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
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Race progress filling with the reps — number and bar
                    // move together, and the fill goes green at the finish.
                    SizedBox(
                      width: widget.compact ? 200 : 230,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: SizedBox(
                          height: 6,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: ColoredBox(
                                  color: NuvoColors.navy.withValues(
                                    alpha: .1,
                                  ),
                                ),
                              ),
                              FractionallySizedBox(
                                widthFactor: score / 10,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 280),
                                  color: finished
                                      ? NuvoColors.success
                                      : NuvoColors.blue,
                                ),
                              ),
                            ],
                          ),
                        ),
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
          // The handoff to the next page: the overtake you just watched is
          // also the +10 XP the level page opens with.
          NuvoFlipText(
            'That progress also builds your Nuvo.',
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
    // Settle phase hands off to the level page — the accepted proof that
    // won the position is also +10 XP toward the next level.
    final xpChip = Curves.easeOutBack.transform(
      ((t - (_settleStart + .06)) / .12).clamp(0.0, 1.0),
    );

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
                    color: NuvoColors.successSurface,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: NuvoColors.success.withValues(alpha: .5),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        color: NuvoColors.success,
                        size: 14,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'PROOF ACCEPTED',
                        style: AppTextStyles.brandLabel.copyWith(
                          color: NuvoColors.successOn,
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
          // The "+10 XP" the next page opens on — rises off the winning
          // row's score edge, clear of the centered proof pill.
          if (xpChip > 0)
            Positioned(
              top: firstRow + 10 - (34 * xpChip),
              right: 10,
              child: Opacity(
                opacity: xpChip.clamp(0.0, 1.0),
                child: const _XpChip(label: '+10 XP'),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Page 5 · Level up ─────────────────────────────────────────────────────────

/// Nuvo Levels told with the canonical economy: an accepted proof pays +10,
/// the other race moments cycle as one compact line, then a later +10 tips
/// 50/60 into LEVEL 2 — which reveals the real level-2 capability from the
/// unlock ladder ("Second badge slot"). Explicitly an EXAMPLE — nothing
/// writes progression; the final page shows the real payload.
class _LevelPage extends ConsumerStatefulWidget {
  const _LevelPage({required this.compact, required this.onReady});

  final bool compact;
  final VoidCallback onReady;

  @override
  ConsumerState<_LevelPage> createState() => _LevelPageState();
}

class _LevelPageState extends ConsumerState<_LevelPage>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  static const _duration = Duration(milliseconds: 5600);
  // Storyboard (fractions of 5600ms): settle 0–560, proof award +10
  // 670–1450, economy line cycles finish/win/PB 1700–2900, "one more race"
  // compress 3000–3400 (10 → 50), final proof +10 3450–3900 (50 → 60),
  // level rolls 4000–4600, unlock card 4700 → end.
  static const _award1At = 670 / 5600;
  static const _award1End = 1450 / 5600;
  static const _econAt = 1700 / 5600;
  static const _econEnd = 2900 / 5600;
  static const _laterAt = 3000 / 5600;
  static const _laterEnd = 3400 / 5600;
  static const _award2At = 3450 / 5600;
  static const _award2End = 3900 / 5600;
  static const _levelUpAt = 4000 / 5600;
  static const _levelUpEnd = 4600 / 5600;
  static const _unlockAt = 4700 / 5600;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _duration,
  )..addStatusListener(_onStatus)
    ..addListener(_maybeHaptic);
  bool _started = false;
  bool _readyReported = false;
  bool _levelHapticFired = false;
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

  void _maybeHaptic() {
    if (!_levelHapticFired && _controller.value >= _levelUpAt) {
      _levelHapticFired = true;
      HapticFeedback.lightImpact();
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
    _controller.removeListener(_maybeHaptic);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final progression = ref.watch(progressionControllerProvider).valueOrNull;
    // Canonical L1→L2 cost is 60 XP (LEVEL_BASE in progression.ts). When the
    // account is genuinely at Level 1 the live payload carries that same
    // number — read it there; the constant only stands in when the payload
    // can't (offline, or a replaying higher-level account where the demo is
    // explicitly illustrating the level-1 curve anyway).
    final xpGoal =
        (progression?.level == 1 ? progression?.nextLevelXp : null) ?? 60;
    // The unlock the demo reveals at Level 2: the live `nextUnlock` when it
    // is the level-2 def (a fresh account's always is), otherwise the
    // canonical cap-badge-slot-2 contents as a labeled example.
    final live = progression?.nextUnlock;
    final unlockName =
        live != null && live.level == 2 ? live.name : _levelTwoUnlockFallback.name;
    final unlockDesc = live != null && live.level == 2
        ? (live.description ?? '')
        : _levelTwoUnlockFallback.description;
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
          SizedBox(height: widget.compact ? 14 : 24),
          Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final t = _controller.value;
                final xp = t >= _award2End
                    ? xpGoal
                    : t >= _award2At
                    ? lerpDouble(
                        50,
                        xpGoal.toDouble(),
                        (t - _award2At) / (_award2End - _award2At),
                      )!.round()
                    : t >= _laterAt
                    ? lerpDouble(
                        10,
                        50,
                        (t - _laterAt) / (_laterEnd - _laterAt),
                      )!.round()
                    : t >= _award1At
                    ? lerpDouble(
                        0,
                        10,
                        (t - _award1At) / (_award1End - _award1At),
                      )!.round()
                    : 0;
                final level = t >= _levelUpAt ? 2 : 1;
                final barFill = (xp / xpGoal).clamp(0.0, 1.0);
                final levelPop = t >= _levelUpAt && t < _levelUpEnd
                    ? Curves.easeOutBack.transform(
                        (t - _levelUpAt) / (_levelUpEnd - _levelUpAt),
                      )
                    : 1.0;
                final econIndex = t < _econAt
                    ? -1
                    : (((t - _econAt) / ((_econEnd - _econAt) / 3)).floor())
                          .clamp(0, 2);
                final unlockIn = ((t - _unlockAt) / .1).clamp(0.0, 1.0);
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
                    SizedBox(height: widget.compact ? 10 : 14),
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
                          fontSize: widget.compact ? 56 : 68,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -2,
                        ),
                      ),
                    ),
                    SizedBox(height: widget.compact ? 8 : 12),
                    NuvoNumberFlow(
                      value: xp,
                      format: (v) => '$v / $xpGoal XP',
                      duration: const Duration(milliseconds: 400),
                      style: AppTextStyles.titleLarge.copyWith(
                        color: NuvoColors.blue,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: widget.compact ? 8 : 12),
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
                                // Blue for progress — gold once the level
                                // threshold is crossed.
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 280),
                                  color: level == 2
                                      ? NuvoColors.gold
                                      : NuvoColors.blue,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: widget.compact ? 12 : 16),
                    // One compact changing line carries the whole economy —
                    // what just happened, then the other canonical awards.
                    SizedBox(
                      height: 26,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 240),
                        child: _levelStatus(
                          t,
                          econIndex,
                        ),
                      ),
                    ),
                    SizedBox(height: widget.compact ? 10 : 14),
                    // The "why level" payoff — the real capability at Level 2.
                    Opacity(
                      opacity: unlockIn,
                      child: Transform.translate(
                        offset: Offset(0, 10 * (1 - unlockIn)),
                        child: unlockIn <= 0
                            ? const SizedBox(height: 56)
                            : _UnlockCard(
                                name: unlockName,
                                description: unlockDesc,
                                compact: widget.compact,
                              ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          SizedBox(height: widget.compact ? 12 : 20),
          NuvoFlipText(
            'Do real race things. Watch the level move.',
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

  /// Fixed-height status line: proof award → economy cycle → the tipping
  /// +10 → level-up verdict. One slot, so the page never jumps vertically.
  Widget _levelStatus(double t, int econIndex) {
    if (t >= _levelUpAt) {
      return Row(
        key: const ValueKey('leveled'),
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.north_rounded, color: NuvoColors.gold, size: 16),
          const SizedBox(width: 4),
          Text(
            'Level up',
            style: AppTextStyles.labelLarge.copyWith(
              color: NuvoColors.gold,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      );
    }
    if (t >= _award2At) {
      return const _XpChip(key: ValueKey('a2'), label: '+10 XP');
    }
    if (t >= _laterAt) {
      return Text(
        'One race later…',
        key: const ValueKey('later'),
        style: AppTextStyles.labelMedium.copyWith(
          color: NuvoColors.muted,
          fontWeight: FontWeight.w800,
        ),
      );
    }
    if (econIndex >= 0) {
      final (label, xp) = _xpLesson[econIndex + 1];
      return Row(
        key: ValueKey('econ-$econIndex'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: AppTextStyles.labelMedium.copyWith(
                color: NuvoColors.navy,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 6),
          _XpChip(label: '+$xp XP'),
        ],
      );
    }
    if (t >= _award1At) {
      return Row(
        key: const ValueKey('proof'),
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: NuvoColors.blue,
            size: 15,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              'Proof accepted',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.labelMedium.copyWith(
                color: NuvoColors.blue,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 6),
          const _XpChip(label: '+10 XP'),
        ],
      );
    }
    return const SizedBox(key: ValueKey('none'));
  }
}

/// The level-2 reveal — reads the real capability name/description from the
/// unlock ladder, not a fictional reward.
class _UnlockCard extends StatelessWidget {
  const _UnlockCard({
    required this.name,
    required this.description,
    required this.compact,
  });

  final String name;
  final String description;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxWidth: compact ? 300 : 330),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NuvoColors.navy, width: 1.6),
        boxShadow: AppShadows.hardSmall,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              // Gold = the level-up payoff, not progress blue.
              color: NuvoColors.gold.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: NuvoColors.gold, width: 1.4),
            ),
            child: const Icon(
              Icons.dashboard_customize_rounded,
              color: NuvoColors.gold,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'AT LEVEL 2',
                  style: AppTextStyles.brandLabel.copyWith(
                    color: NuvoColors.muted,
                    letterSpacing: 1.4,
                    fontSize: 9.5,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelLarge.copyWith(
                    color: NuvoColors.navy,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                // The complete thought — wrap to a second line before ever
                // clipping the capability copy.
                if (description.isNotEmpty)
                  Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: NuvoColors.muted,
                      height: 1.3,
                    ),
                  ),
              ],
            ),
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

/// Progression → identity: real achievement definitions, rendered with the
/// same NuvoAchievementBadge system Profile uses. First the featured set a
/// mid-level account might carry, then the two canonical goals a fresh
/// account actually starts with — First Move earns live (conceptually),
/// Hat Trick shows progress as a goal. All labelled EXAMPLE; no account
/// state is touched.
class _IdentityPage extends ConsumerStatefulWidget {
  const _IdentityPage({required this.compact, required this.onReady});

  final bool compact;
  final VoidCallback onReady;

  @override
  ConsumerState<_IdentityPage> createState() => _IdentityPageState();
}

class _IdentityPageState extends ConsumerState<_IdentityPage>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  static const _duration = Duration(milliseconds: 4200);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _duration,
  )..addStatusListener(_onStatus)
    ..addListener(_maybeHaptic);
  bool _started = false;
  bool _readyReported = false;
  bool _earnHapticFired = false;
  Timer? _holdTimer;

  // Storyboard: identity card 0–.18, featured badges .18–.40, First Move
  // goal row .42–.58, its earn beat .60–.72 (badge flips, 0/1 → 1/1),
  // Hat Trick progress row .76–.94.
  static const _featuredAt = .18;
  static const _featuredEnd = .40;
  static const _firstMoveAt = .42;
  static const _earnedAt = .60;
  static const _earnedEnd = .72;
  static const _goalAt = .76;
  static const _goalEnd = .94;

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

  void _maybeHaptic() {
    if (!_earnHapticFired && _controller.value >= _earnedAt) {
      _earnHapticFired = true;
      HapticFeedback.lightImpact();
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
    _controller.removeListener(_maybeHaptic);
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
    // Real defs keyed by unlock_key — fallback literals keep the lesson
    // intact offline.
    final defs =
        ref.watch(_onboardingAchievementDefsProvider).valueOrNull ?? const {};
    NuvoBadge def(String key) => defs[key] ?? _defFallbacks[key]!;
    final featured = [
      def('first_w'),
      def('five_deep'),
      def('personal_best'),
    ];
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(22, widget.compact ? 10 : 20, 22, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NuvoFlipText(
            'Make your name\nmean something.',
            style: AppTextStyles.displayMedium.copyWith(
              color: NuvoColors.navy,
              fontSize: widget.compact ? 30 : 38,
              height: .96,
              letterSpacing: -1.2,
            ),
            delay: const Duration(milliseconds: 150),
            duration: const Duration(milliseconds: 1400),
          ),
          SizedBox(height: widget.compact ? 10 : 18),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final cardIn = _segment(0, _featuredAt);
              final featuredIn = _segment(_featuredAt, _featuredEnd);
              final goalIn = _segment(_firstMoveAt, _firstMoveAt + .12);
              final earned = _controller.value >= _earnedAt;
              final earnPop = earned && _controller.value < _earnedEnd
                  ? Curves.easeOutBack.transform(
                      (_controller.value - _earnedAt) /
                          (_earnedEnd - _earnedAt),
                    )
                  : 1.0;
              final hatIn = _segment(_goalAt, _goalEnd);
              return _asLightChrome(
                Column(
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
                    SizedBox(height: widget.compact ? 8 : 12),
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
                              size: widget.compact
                                  ? NuvoAvatarSizes.lg
                                  : NuvoAvatarSizes.xl,
                              bgColor: nuvoAvatarColorFor(user?.id ?? ''),
                              textColor: NuvoColors.white,
                              borderColor: NuvoColors.navy,
                              borderWidth: 2,
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.titleMedium.copyWith(
                                      color: NuvoColors.navy,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        NuvoColors.blue.withValues(alpha: .12),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Text(
                                    'LEVEL 8',
                                    style: AppTextStyles.brandLabel.copyWith(
                                      color: NuvoColors.blue,
                                      letterSpacing: 1.6,
                                      fontSize: 10.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: widget.compact ? 10 : 14),
                    // A mid-level featured set — the real badge visual. Each
                    // gets an equal flex slot so names never push past 320.
                    Row(
                      children: [
                        for (var i = 0; i < featured.length; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          Expanded(
                            child: Opacity(
                              opacity:
                                  ((featuredIn - i * .3) / .7).clamp(0.0, 1.0),
                              child: _FeaturedBadge(
                                badge: _demoBadgeState(
                                  featured[i],
                                  unlocked: true,
                                ),
                                compact: widget.compact,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    SizedBox(height: widget.compact ? 12 : 16),
                    // First Move — the goal every fresh account actually
                    // starts with — earns live as a demonstration.
                    Opacity(
                      opacity: goalIn,
                      child: Transform.translate(
                        offset: Offset(0, 12 * (1 - goalIn)),
                        child: _GoalRow(
                          badge: _demoBadgeState(
                            def('first_move'),
                            unlocked: earned,
                            progressValue: earned ? 1 : 0,
                          ),
                          earned: earned,
                          earnPop: earnPop,
                          compact: widget.compact,
                        ),
                      ),
                    ),
                    SizedBox(height: widget.compact ? 8 : 10),
                    // And the longer goal: Hat Trick sits at 0 / 3 — the user
                    // builds wins, the explanation never implies they have
                    // any yet.
                    Opacity(
                      opacity: hatIn,
                      child: Transform.translate(
                        offset: Offset(0, 12 * (1 - hatIn)),
                        child: _GoalRow(
                          badge: _demoBadgeState(
                            def('hat_trick'),
                            progressValue: 0,
                          ),
                          compact: widget.compact,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          SizedBox(height: widget.compact ? 12 : 18),
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
}

/// Featured-achievement chip on the identity card — real badge + real name.
class _FeaturedBadge extends StatelessWidget {
  const _FeaturedBadge({required this.badge, required this.compact});

  final NuvoBadge badge;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        NuvoAchievementBadge(badge: badge, size: compact ? 44 : 52),
        const SizedBox(height: 4),
        Text(
          badge.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: AppTextStyles.labelSmall.copyWith(
            color: NuvoColors.navy,
            fontWeight: FontWeight.w800,
            fontSize: 10.5,
          ),
        ),
      ],
    );
  }
}

/// One canonical achievement as a goal — real badge, real description, real
/// progress. Used for both the First Move earn demo and Hat Trick's
/// mid-goal state.
class _GoalRow extends StatelessWidget {
  const _GoalRow({
    required this.badge,
    required this.compact,
    this.earned = false,
    this.earnPop = 1,
  });

  final NuvoBadge badge;
  final bool compact;

  /// True while the earn beat is playing/played — badge shows unlocked and
  /// the row reads 1 / 1 with an EARNED tag.
  final bool earned;
  final double earnPop;

  @override
  Widget build(BuildContext context) {
    final goal = badge.threshold ?? 0;
    final progress = badge.progressValue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: NuvoColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NuvoColors.navy, width: 1.6),
        boxShadow: AppShadows.hardSmall,
      ),
      child: Row(
        children: [
          Transform.scale(
            scale: earned ? .9 + (.1 * earnPop) : 1,
            child: NuvoAchievementBadge(badge: badge, size: 40),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        badge.name.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.brandLabel.copyWith(
                          color: NuvoColors.navy,
                          letterSpacing: 1.2,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    if (earned) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          // Earned = gold; the tag marks an achievement, not
                          // an action.
                          color: NuvoColors.gold,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: MediaQuery.withClampedTextScaling(
                          // Fixed 8.5px tag artifact — accessibility scale
                          // would double it and crowd the name row out.
                          maxScaleFactor: 1.0,
                          child: Text(
                            'EARNED',
                            style: AppTextStyles.brandLabel.copyWith(
                              color: NuvoColors.navy,
                              letterSpacing: 1.2,
                              fontSize: 8.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  badge.description ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: NuvoColors.muted,
                  ),
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: SizedBox(
                    height: 5,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: ColoredBox(
                            color: NuvoColors.navy.withValues(alpha: .1),
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor:
                              goal > 0 ? (progress / goal).clamp(0.0, 1.0) : 0,
                          child: const ColoredBox(color: NuvoColors.blue),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          MediaQuery.withClampedTextScaling(
            // The count is fixed-width chrome, not prose — at 1.4 scale it
            // would eat the name column's share of the card.
            maxScaleFactor: 1.15,
            child: Text(
              goal > 0 ? '$progress / $goal' : '',
              style: AppTextStyles.labelLarge.copyWith(
                color: earned ? NuvoColors.blue : NuvoColors.navy,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
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
    // (name, level, featured achievement iconKey, isYou) — each crew member
    // carries one featured badge, the same featured identity Profile shows.
    // Your row is deliberately clean: Level 1, nothing earned yet — the gap
    // is the pull.
    final rows = <(String, int, String?, bool)>[
      ('Shresh', 14, 'trophy_3', false),
      ('Maya', 9, 'flags_5', false),
      ('Noah', 4, 'trophy_1', false),
      (widget.firstName ?? 'You', 1, null, true),
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

  Widget _crewRow((String, int, String?, bool) row, int index) {
    final appear = Curves.easeOutCubic.transform(
      ((_controller.value - index * .16) / .3).clamp(0.0, 1.0),
    );
    final (name, level, badgeIcon, isYou) = row;
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
              if (badgeIcon != null) ...[
                _asLightChrome(
                  NuvoAchievementBadge(
                    badge: NuvoBadge(
                      unlockId: 'crew-demo-$badgeIcon',
                      type: 'achievement',
                      key: badgeIcon,
                      name: '',
                      requiredLevel: 0,
                      unlocked: true,
                      featured: true,
                      iconKey: badgeIcon,
                    ),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 8),
              ],
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
/// reads Level 1 / 0 of 60 XP), with the canonical first goal underneath —
/// First Move while it's still open, the server's "next up" once it's not.
/// The only place onboarding touches real numbers, precisely so "Your first
/// move starts now" means it.
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
    // The demo/presentation fixture (Level 8, mid-Hat-Trick) is for Profile
    // surfaces — onboarding's closing promise is always the user's real
    // first-run state, so a demo identity reads as the fresh account it is.
    final isDemo = isPresentationDemoUser(
      ref.watch(authControllerProvider).user,
    );
    final progression =
        isDemo ? null : ref.watch(progressionControllerProvider).valueOrNull;
    final defs = isDemo
        ? const <String, NuvoBadge>{}
        : ref.watch(_onboardingAchievementDefsProvider).valueOrNull ??
              const {};
    final level = progression?.level ?? 1;
    final current = progression?.currentLevelXp;
    final goal = progression?.nextLevelXp;
    // Real fraction when the payload landed; "0 XP" is the safe fresh-account
    // baseline otherwise — never a spinner, never a blank stat.
    final xpText = current != null && goal != null
        ? '$current / $goal XP'
        : '0 XP';
    // The first goal: First Move while it's still open — the exact promise
    // onboarding makes — then the server's canonical "next up" once it's
    // earned (returning/demo-replay accounts). Null on a total read failure.
    final firstMove = defs['first_move'] ?? _defFallbacks['first_move'];
    final fmDone = firstMove != null &&
        (firstMove.unlocked ||
            firstMove.progressValue >= (firstMove.threshold ?? 1));
    final firstGoal = fmDone ? progression?.nextAchievement : firstMove;
    final name = widget.firstName;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(22, widget.compact ? 10 : 24, 22, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(height: widget.compact ? 10 : 24),
          NuvoFlipText(
            name != null ? '$name, you\'re ready.' : 'You\'re ready.',
            textAlign: TextAlign.center,
            style: AppTextStyles.displayMedium.copyWith(
              color: NuvoColors.navy,
              fontSize: widget.compact ? 30 : 40,
              height: 1.02,
              letterSpacing: -1.2,
            ),
            delay: const Duration(milliseconds: 200),
            duration: const Duration(milliseconds: 1500),
          ),
          SizedBox(height: widget.compact ? 14 : 24),
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
              fontSize: widget.compact ? 56 : 80,
              fontWeight: FontWeight.w900,
              letterSpacing: -2,
              height: 1,
            ),
          ),
          SizedBox(height: widget.compact ? 6 : 10),
          Text(
            xpText,
            style: AppTextStyles.titleLarge.copyWith(
              color: NuvoColors.muted,
              fontWeight: FontWeight.w800,
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
                      widthFactor:
                          (progression?.progress ?? 0).clamp(0.0, 1.0),
                      child: const ColoredBox(color: NuvoColors.blue),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(height: widget.compact ? 12 : 18),
          // The first canonical goal — the promise this screen makes real.
          if (firstGoal != null)
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: widget.compact ? 300 : 330,
              ),
              child: _asLightChrome(
                _GoalRow(badge: firstGoal, compact: widget.compact),
              ),
            ),
          SizedBox(height: widget.compact ? 12 : 20),
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
          SizedBox(height: widget.compact ? 8 : 12),
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

    // The racer — a dot that physically travels the path as progress moves.
    if (progress > 0.02) {
      final at = metric.getTangentForOffset(
        (metric.length * progress).clamp(0.0, metric.length),
      );
      if (at != null) {
        canvas.drawCircle(
          at.position,
          11,
          Paint()..color = NuvoColors.blue.withValues(alpha: .25),
        );
        canvas.drawCircle(at.position, 6.5, Paint()..color = NuvoColors.navy);
        canvas.drawCircle(at.position, 3, Paint()..color = NuvoColors.white);
      }
    }

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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/motion.dart';
import '../../../core/v13/tokens.dart';
import '../../auth/presentation/auth_controller.dart';
import '../flow/onboarding_copy.dart';
import '../flow/onboarding_flow_controller.dart';
import '../shell/ob_progress.dart';
import 'intro_demos.dart';

/// The intro: five swipeable pages that explain the app (race, prove it on
/// camera, the board, your crew, levels). One flat animation per page that
/// plays ONCE and holds its last frame, one Continue button, Skip always
/// available, a progress bar from page 2 (see [ObProgress]). The color field
/// morphs with the swipe, soft shapes drift behind. When it ends (Get started
/// or Skip) the player lands on the create-account choice page. Shown on the
/// very first app open only.
class ObIntroPagesStep extends ConsumerStatefulWidget {
  const ObIntroPagesStep({super.key});

  @override
  ConsumerState<ObIntroPagesStep> createState() => _ObIntroPagesStepState();
}

class _Page {
  const _Page(this.color, this.title, this.body);
  final Color color;
  final String title;
  final String body;
}

const _pages = [
  _Page(V13.sky, ObCopy.introRaceTitle, ObCopy.introRaceSub),
  _Page(V13.mint, ObCopy.introProveTitle, ObCopy.introProveSub),
  _Page(V13.lilac, ObCopy.introClimbTitle, ObCopy.introClimbSub),
  _Page(V13.sun, ObCopy.introCrewTitle, ObCopy.introCrewSub),
  _Page(V13.sky, ObCopy.introLevelTitle, ObCopy.introLevelSub),
];

class _ObIntroPagesStepState extends ConsumerState<ObIntroPagesStep>
    with TickerProviderStateMixin {
  final _controller = PageController();
  late final AnimationController _play = AnimationController(
    vsync: this,
    duration: NuvoMotion.introPlay,
  );
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: NuvoMotion.introDrift,
  );

  /// Pages whose animation has already played (never replays on revisit).
  final Set<int> _played = {};
  int _page = 0;
  bool _started = false;
  bool _animatingPage = false;
  bool _lastReady = false;
  Timer? _dwell;

  @override
  void initState() {
    super.initState();
    ObProgress.reset();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (NuvoMotion.reduceMotionOf(context)) {
      _play.value = 1; // finished frames, no motion at all
    } else {
      _drift.repeat();
      _playPage(0);
    }
  }

  @override
  void dispose() {
    _dwell?.cancel();
    _controller.dispose();
    _play.dispose();
    _drift.dispose();
    super.dispose();
  }

  void _playPage(int i) {
    if (NuvoMotion.reduceMotionOf(context)) {
      _play.value = 1;
      return;
    }
    if (_played.add(i)) {
      _play.forward(from: 0); // first visit: play once
    } else {
      _play.value = 1; // revisit: hold the final frame
    }
  }

  bool get _last => _page == _pages.length - 1;

  void _onPage(int i) {
    _dwell?.cancel();
    setState(() {
      _page = i;
      _lastReady = false;
    });
    if (i == _pages.length - 1) {
      // The last page ignores the CTA for a beat after arriving.
      _dwell = Timer(NuvoMotion.introLastDwell, () {
        if (mounted) setState(() => _lastReady = true);
      });
    }
    _playPage(i);
  }

  Future<void> _next() async {
    if (_animatingPage) return; // a second tap mid-slide does nothing
    if (_last) {
      // The last page waits for a deliberate tap: ignore taps that arrive
      // right after the slide (a double tap on Next must not also fire this).
      if (!_lastReady) return;
      await _finish();
      return;
    }
    final reduce = NuvoMotion.reduceMotionOf(context);
    _animatingPage = true;
    try {
      await _controller.nextPage(
        duration: reduce ? Duration.zero : NuvoMotion.enter,
        curve: NuvoMotion.spring,
      );
    } finally {
      _animatingPage = false;
    }
  }

  /// Get started: into the account-choice page (Apple / Google / email).
  Future<void> _finish() async {
    final flow = ref.read(onboardingFlowProvider.notifier);
    await flow.finishIntro();
    ref.read(authIntentProvider.notifier).state = AuthIntent.signUp;
  }

  Future<void> _skip() async {
    final flow = ref.read(onboardingFlowProvider.notifier);
    await flow.finishIntro(skipped: true);
    ref.read(authIntentProvider.notifier).state = AuthIntent.signUp;
  }

  /// Fractional page position (works before the first layout).
  double get _pos =>
      _controller.hasClients && _controller.position.haveDimensions
      ? (_controller.page ?? _page.toDouble())
      : _page.toDouble();

  Color get _field {
    final p = _pos.clamp(0.0, _pages.length - 1.0);
    final i = p.floor();
    final j = (i + 1).clamp(0, _pages.length - 1);
    return Color.lerp(_pages[i].color, _pages[j].color, p - i)!;
  }

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      // Dynamic Type stays honoured, but capped so the page can't overflow.
      data: MediaQuery.of(context).copyWith(
        textScaler: MediaQuery.textScalerOf(
          context,
        ).clamp(minScaleFactor: 1.0, maxScaleFactor: 1.3),
      ),
      child: AnimatedBuilder(
        animation: Listenable.merge([_controller, _drift]),
        builder: (context, _) => ColoredBox(
          color: _field,
          child: Stack(
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: CloudsPainter(pos: _pos, drift: _drift.value),
                  ),
                ),
              ),
              SafeArea(child: _content()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 8, 0),
          child: SizedBox(
            height: 44,
            child: Row(
              children: [
                Expanded(
                  // Hidden on page 1; honest progress from page 2 on.
                  child: _page == 0
                      ? const SizedBox.shrink()
                      : Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 220),
                            child: ObProgressBar(
                              done: ObProgress.doneForIntroPage(_page),
                              light: true,
                            ),
                          ),
                        ),
                ),
                NuvoPressable(
                  onTap: _skip,
                  semanticLabel: ObCopy.skip,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Text(
                      ObCopy.skip,
                      key: const ValueKey('ob-intro-skip'),
                      style: V13.bodyStrong.copyWith(color: V13.navy),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: PageView.builder(
            key: const ValueKey('ob-intro-pages'),
            controller: _controller,
            itemCount: _pages.length,
            onPageChanged: _onPage,
            itemBuilder: (context, i) => _PageBody(
              page: _pages[i],
              kind: i,
              pos: _pos,
              index: i,
              t: i == _page
                  ? _play
                  : AlwaysStoppedAnimation(_played.contains(i) ? 1.0 : 0.0),
              onReplay: () {
                if (i == _page && !NuvoMotion.reduceMotionOf(context)) {
                  _play.forward(from: 0); // explicit tap only
                }
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: NuvoPressable(
            onTap: _next,
            borderRadius: BorderRadius.circular(V13.radiusButton),
            shadow: V13.shadow4,
            semanticLabel: _last ? ObCopy.introStart : ObCopy.next,
            child: Container(
              key: const ValueKey('onboarding-cta'),
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: V13.navy,
                borderRadius: BorderRadius.circular(V13.radiusButton),
                border: Border.all(color: V13.navy, width: V13.outlineThick),
              ),
              child: AnimatedSwitcher(
                duration: NuvoMotion.ctaFade,
                child: Text(
                  _last ? ObCopy.introStart : ObCopy.next,
                  key: ValueKey(_last),
                  style: V13.buttonLabel.copyWith(color: V13.white),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PageBody extends StatelessWidget {
  const _PageBody({
    required this.page,
    required this.kind,
    required this.pos,
    required this.index,
    required this.t,
    required this.onReplay,
  });

  final _Page page;
  final int kind;
  final double pos;
  final int index;
  final Animation<double> t;
  final VoidCallback onReplay;

  @override
  Widget build(BuildContext context) {
    // Parallax: the demo drifts against the swipe and softens as it leaves.
    final delta = (index - pos).clamp(-1.0, 1.0);
    final demoShift = delta * 90;
    final demoFade = (1 - delta.abs() * 0.8).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: LayoutBuilder(
        builder: (context, c) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onReplay,
                child: Opacity(
                  opacity: demoFade,
                  child: Transform.translate(
                    offset: Offset(demoShift, 0),
                    child: ClipRect(
                      child: AnimatedBuilder(
                        animation: t,
                        builder: (context, _) =>
                            IntroDemo(kind: kind, t: t.value),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Scales down (never overflows) on small screens / large type.
            Flexible(
              flex: 0,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: c.maxWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        page.title,
                        style: V13.title.copyWith(fontSize: 38, height: 1.05),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        page.body,
                        style: V13.body.copyWith(fontSize: 17, color: V13.navy),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

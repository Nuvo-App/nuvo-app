import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/motion.dart';
import '../../../core/v13/tokens.dart';
import '../flow/onboarding_copy.dart';
import '../flow/onboarding_flow_controller.dart';
import '../flow/onboarding_step.dart';
import '../shell/ob_progress.dart';
import '../shell/onboarding_shell.dart' show obAdvance;
import 'intro_demos.dart';

/// The intro: five swipeable pages that explain the app (race, prove it on
/// camera, the board, your crew, levels). One flat animation per page, one
/// Continue button, Skip always available, and a progress bar that only
/// appears from page 2 (see [ObProgress] for the exact formula). Shown on the
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
    with SingleTickerProviderStateMixin {
  final _controller = PageController();
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: NuvoMotion.introLoop,
  );
  int _page = 0;
  bool _started = false;

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
      _loop.value = 1; // the finished frame, static
    } else {
      _loop.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _loop.dispose();
    super.dispose();
  }

  bool get _last => _page == _pages.length - 1;

  void _onPage(int i) {
    setState(() => _page = i);
    if (!NuvoMotion.reduceMotionOf(context)) {
      _loop
        ..value = 0
        ..repeat();
    }
  }

  void _next() {
    if (_last) {
      obAdvance(context, ref, OnboardingStep.introRace);
      return;
    }
    final reduce = NuvoMotion.reduceMotionOf(context);
    _controller.nextPage(
      duration: reduce ? Duration.zero : NuvoMotion.enter,
      curve: NuvoMotion.spring,
    );
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.read(onboardingFlowProvider.notifier);
    return AnimatedContainer(
      duration: NuvoMotion.springDuration,
      color: _pages[_page].color,
      child: SafeArea(
        child: Column(
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
                                constraints: const BoxConstraints(
                                  maxWidth: 220,
                                ),
                                child: ObProgressBar(
                                  done: ObProgress.doneForIntroPage(_page),
                                  light: true,
                                ),
                              ),
                            ),
                    ),
                    NuvoPressable(
                      onTap: flow.skipIntros,
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
                  loop: _loop,
                  active: i == _page,
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
                    border: Border.all(
                      color: V13.navy,
                      width: V13.outlineThick,
                    ),
                  ),
                  child: Text(
                    _last ? ObCopy.introStart : ObCopy.next,
                    style: V13.buttonLabel.copyWith(color: V13.white),
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

class _PageBody extends StatelessWidget {
  const _PageBody({
    required this.page,
    required this.kind,
    required this.loop,
    required this.active,
  });

  final _Page page;
  final int kind;
  final Animation<double> loop;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: active
                ? AnimatedBuilder(
                    animation: loop,
                    builder: (context, _) =>
                        IntroDemo(kind: kind, t: loop.value),
                  )
                : IntroDemo(kind: kind, t: 1),
          ),
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
    );
  }
}

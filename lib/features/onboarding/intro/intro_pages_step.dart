import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/motion.dart';
import '../../../core/v13/tokens.dart';
import '../flow/onboarding_copy.dart';
import '../flow/onboarding_flow_controller.dart';
import '../flow/onboarding_step.dart';
import '../shell/onboarding_shell.dart' show obAdvance;

/// The whole intro: three swipeable value screens (what it is, how it
/// proves, why it's fun), one color field each, no cards and nothing to tap
/// through but the single button. Skip leaves at any time. Shown on the very
/// first app open only.
class ObIntroPagesStep extends ConsumerStatefulWidget {
  const ObIntroPagesStep({super.key});

  @override
  ConsumerState<ObIntroPagesStep> createState() => _ObIntroPagesStepState();
}

class _Page {
  const _Page(this.color, this.icon, this.title, this.body);
  final Color color;
  final IconData icon;
  final String title;
  final String body;
}

const _pages = [
  _Page(
    V13.sky,
    Icons.sports_score_rounded,
    ObCopy.introRaceTitle,
    ObCopy.introRaceSub,
  ),
  _Page(
    V13.mint,
    Icons.videocam_rounded,
    ObCopy.introProveTitle,
    ObCopy.introProveSub,
  ),
  _Page(
    V13.lilac,
    Icons.leaderboard_rounded,
    ObCopy.introClimbTitle,
    ObCopy.introClimbSub,
  ),
];

class _ObIntroPagesStepState extends ConsumerState<ObIntroPagesStep> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _last => _page == _pages.length - 1;

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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SizedBox(
                height: 44,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: NuvoPressable(
                    onTap: flow.skipIntros,
                    semanticLabel: ObCopy.skip,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Text(
                        ObCopy.skip,
                        key: const ValueKey('ob-intro-skip'),
                        style: V13.bodyStrong.copyWith(color: V13.navy),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView(
                key: const ValueKey('ob-intro-pages'),
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                children: [for (final p in _pages) _PageBody(page: p)],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _pages.length; i++)
                  AnimatedContainer(
                    duration: NuvoMotion.springDuration,
                    curve: NuvoMotion.spring,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _page ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _page ? V13.navy : Colors.transparent,
                      borderRadius: BorderRadius.circular(V13.radiusPill),
                      border: Border.all(color: V13.navy, width: V13.outline),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
  const _PageBody({required this.page});

  final _Page page;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(flex: 2),
          Icon(page.icon, size: 112, color: V13.navy),
          const Spacer(),
          Text(
            page.title,
            style: V13.title.copyWith(fontSize: 40, height: 1.05),
          ),
          const SizedBox(height: 12),
          Text(
            page.body,
            style: V13.body.copyWith(fontSize: 17, color: V13.navy),
          ),
          const Spacer(flex: 2),
        ],
      ),
    );
  }
}

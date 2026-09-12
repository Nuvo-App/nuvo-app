import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';

enum FirstRaceGuideStep {
  idle,
  competeStart,
  composerName,
  composerActivity,
  composerGoal,
  composerRacers,
  composerReview,
  raceDetail,
  complete,
}

final firstRaceGuideProvider = StateProvider<FirstRaceGuideStep>(
  (ref) => FirstRaceGuideStep.idle,
);

/// Temporary in-session flag used by the demo account to replay the complete
/// first-launch experience without destroying its authenticated session.
final demoReplayProvider = StateProvider<bool>((ref) => false);

abstract final class FirstRaceGuideKeys {
  static final competeStart = GlobalKey(debugLabel: 'guide-compete-start');
  static final composerName = GlobalKey(debugLabel: 'guide-composer-name');
  static final composerActivity = GlobalKey(
    debugLabel: 'guide-composer-activity',
  );
  static final composerGoal = GlobalKey(debugLabel: 'guide-composer-goal');
  static final composerRacers = GlobalKey(debugLabel: 'guide-composer-racers');
  static final composerReview = GlobalKey(debugLabel: 'guide-composer-review');
  static final racePrimary = GlobalKey(debugLabel: 'guide-race-primary');
}

class FirstRaceGuideCoach extends ConsumerStatefulWidget {
  const FirstRaceGuideCoach({
    super.key,
    required this.step,
    required this.targetKey,
    required this.eyebrow,
    required this.title,
    required this.body,
  });

  final FirstRaceGuideStep step;
  final GlobalKey targetKey;
  final String eyebrow;
  final String title;
  final String body;

  @override
  ConsumerState<FirstRaceGuideCoach> createState() =>
      _FirstRaceGuideCoachState();
}

class _FirstRaceGuideCoachState extends ConsumerState<FirstRaceGuideCoach>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat(reverse: true);
  Rect? _targetRect;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _locateTarget());
  }

  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _locateTarget());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) => _locateTarget());
  }

  @override
  void didUpdateWidget(covariant FirstRaceGuideCoach oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetKey != widget.targetKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _locateTarget());
      // The composer changes pages with an animated PageView. The target can
      // still be offscreen during the first frame, so measure again after the
      // page settles instead of leaving the coach mark on a stale rect.
      Future<void>.delayed(const Duration(milliseconds: 380), () {
        if (mounted) _locateTarget();
      });
    }
  }

  void _locateTarget() {
    final renderObject = widget.targetKey.currentContext?.findRenderObject();
    if (renderObject is RenderBox && renderObject.hasSize && mounted) {
      final origin = renderObject.localToGlobal(Offset.zero);
      final next = origin & renderObject.size;
      if (_targetRect != next) setState(() => _targetRect = next);
    }
  }

  void _skip() {
    ref.read(firstRaceGuideProvider.notifier).state =
        FirstRaceGuideStep.complete;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        children: [
          // Keep the rest of the app visually quiet while the coach mark is
          // active. The highlighted control remains tappable because this
          // scrim is intentionally below the target outline and callout.
          IgnorePointer(
            child: ColoredBox(
              color: NuvoColors.navy.withValues(alpha: .08),
              child: const SizedBox.expand(),
            ),
          ),
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) {
                final rect = _targetRect;
                if (rect == null) return const SizedBox.shrink();
                return Positioned(
                  left: rect.left - 6,
                  top: rect.top - 6,
                  width: rect.width + 12,
                  height: rect.height + 12,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: NuvoColors.blue.withValues(
                          alpha: .58 + _pulse.value * .42,
                        ),
                        width: 3,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: NuvoColors.blue.withValues(
                            alpha: .14 + _pulse.value * .16,
                          ),
                          blurRadius: 18,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          _GuideCallout(
            targetRect: _targetRect,
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

class _GuideCallout extends StatelessWidget {
  const _GuideCallout({
    required this.targetRect,
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.onSkip,
  });

  final Rect? targetRect;
  final String eyebrow;
  final String title;
  final String body;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final rect = targetRect;
        final panelWidth = math.min(constraints.maxWidth - 32, 360.0);
        final panelHeight = 142.0;
        final preferredTop = (rect?.bottom ?? constraints.maxHeight - 190) + 14;
        final top = preferredTop + panelHeight < constraints.maxHeight - 12
            ? preferredTop
            : math.max(12.0, (rect?.top ?? 150) - panelHeight - 14);
        return Positioned(
          left: (constraints.maxWidth - panelWidth) / 2,
          top: top,
          width: panelWidth,
          child: IgnorePointer(
            ignoring: false,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 14, 10),
                decoration: BoxDecoration(
                  color: NuvoColors.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: NuvoColors.navy, width: 1.8),
                  boxShadow: AppShadows.hardSmall,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(eyebrow, style: AppTextStyles.brandLabel),
                    const SizedBox(height: 4),
                    Text(title, style: AppTextStyles.titleMedium),
                    const SizedBox(height: 3),
                    Text(
                      body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: NuvoColors.muted,
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: NuvoTertiaryButton(
                        label: 'Skip guide',
                        small: true,
                        onPressed: onSkip,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

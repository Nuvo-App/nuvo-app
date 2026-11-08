import 'package:flutter/material.dart';

import '../../../../core/v13/v13.dart';
import '../../../../core/widgets/nuvo_number_flow.dart';
import '../../data/progression_models.dart';
import 'nuvo_badges.dart';

/// The level-up moment — short, physical, once per level (the server keeps
/// last_seen_level so it never replays across restarts or devices).
Future<void> showLevelUpMoment(
  BuildContext context, {
  required int level,
  NuvoBadge? badge,
}) {
  // One firm tap of haptics — the moment is physical, not noisy.
  V13Haptics.confirm();
  return showDialog<void>(
    context: context,
    barrierColor: V13.navy.withValues(alpha: 0.45),
    builder: (ctx) {
      return _MomentFrame(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'LEVEL UP',
              style: V13.label.copyWith(color: V13.blue, fontSize: 12),
            ),
            const SizedBox(height: V13.gapSm),
            _RollingLevel(
              level: level,
              style: V13.hugeNumber.copyWith(fontSize: 64),
            ),
            if (badge != null) ...[
              const SizedBox(height: V13.gapMd),
              Text('REWARD', style: V13.label.copyWith(fontSize: 10)),
              const SizedBox(height: V13.gapSm),
              NuvoBadgeDisc(badge: badge, size: 64),
              const SizedBox(height: V13.gapSm),
              Text(
                badge.name,
                style: V13.bodyStrong,
                textAlign: TextAlign.center,
              ),
              if (badge.description != null) ...[
                const SizedBox(height: 4),
                Text(
                  badge.description!,
                  style: V13.caption,
                  textAlign: TextAlign.center,
                ),
              ],
            ],
            const SizedBox(height: V13.gapXl),
            V13Button.primary(
              label: 'Nice',
              fullWidth: true,
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      );
    },
  );
}

/// The achievement-earned moment — a badge just landed in the collection.
/// Presented from whichever surface read the reconcile that granted it.
Future<void> showAchievementMoment(
  BuildContext context, {
  required NuvoBadge badge,
}) {
  V13Haptics.confirm();
  return showDialog<void>(
    context: context,
    barrierColor: V13.navy.withValues(alpha: 0.45),
    builder: (ctx) {
      return _MomentFrame(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'ACHIEVEMENT EARNED',
              style: V13.label.copyWith(color: V13.blue, fontSize: 12),
            ),
            const SizedBox(height: V13.gapMd),
            NuvoAchievementBadge(badge: badge, size: 72),
            const SizedBox(height: V13.gapSm),
            Text(
              badge.name,
              style: V13.bodyStrong,
              textAlign: TextAlign.center,
            ),
            if (badge.description != null) ...[
              const SizedBox(height: 4),
              Text(
                badge.description!,
                style: V13.caption,
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: V13.gapXl),
            V13Button.primary(
              label: 'Nice',
              fullWidth: true,
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      );
    },
  );
}

/// The shared reward-moment frame: a [V13Card] floating over the dimmed
/// page with a [V13Confetti] burst behind it. Confetti lives inside the
/// dialog (not the page overlay) so it paints above the barrier.
class _MomentFrame extends StatelessWidget {
  const _MomentFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: [
          const Positioned.fill(child: IgnorePointer(child: V13Confetti())),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: V13Card(
                radius: V13.radiusCardLg,
                shadow: V13.shadow6,
                padding: const EdgeInsets.fromLTRB(
                  V13.gapXxl,
                  28,
                  V13.gapXxl,
                  V13.gapXxl,
                ),
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// LEVEL N−1 rolls into LEVEL N — the climb is the point, so the moment
/// starts on the level you just left and the wheel carries it forward.
class _RollingLevel extends StatefulWidget {
  const _RollingLevel({required this.level, required this.style});

  final int level;
  final TextStyle style;

  @override
  State<_RollingLevel> createState() => _RollingLevelState();
}

class _RollingLevelState extends State<_RollingLevel> {
  late int _shown = widget.level - 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _shown = widget.level);
    });
  }

  @override
  Widget build(BuildContext context) {
    return NuvoNumberFlow(
      value: _shown,
      trend: NuvoNumberFlowTrend.increasing,
      style: widget.style,
      duration: const Duration(milliseconds: 500),
    );
  }
}

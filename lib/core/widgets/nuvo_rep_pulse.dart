import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/nuvo_responsive.dart';
import 'rep_burst_controller.dart';

/// The "Nuvo saw that" feedback for a live rep count.
///
/// Give it the verifier's current [count]. Every time [count] goes up it
/// replays a `+1` punch over the big running number and fires a haptic tick —
/// so the person believes Nuvo is watching them in real time. It NEVER changes
/// the count; it only mirrors it.
///
/// Used by the Teach Nuvo test screen and the live race verification screen so
/// both feel identical.
class NuvoRepPulse extends StatefulWidget {
  const NuvoRepPulse({
    super.key,
    required this.count,
    required this.target,
    this.accent = NuvoColors.blue,
    this.onColor = NuvoColors.navy,
    this.haptics = true,
    this.compact = false,
  });

  final int count;
  final int target;

  /// The `+1` flash colour.
  final Color accent;

  /// Colour of the running "N / target" number.
  final Color onColor;
  final bool haptics;

  /// Smaller number, for an inline HUD rather than a full-screen moment.
  final bool compact;

  @override
  State<NuvoRepPulse> createState() => _NuvoRepPulseState();
}

class _NuvoRepPulseState extends State<NuvoRepPulse> {
  int _shownCount = 0;
  int _pulseSeq = 0;
  bool _targetHit = false;
  final _burst = RepBurstController();

  @override
  void initState() {
    super.initState();
    _shownCount = widget.count;
    _targetHit = widget.target > 0 && widget.count >= widget.target;
  }

  @override
  void didUpdateWidget(covariant NuvoRepPulse old) {
    super.didUpdateWidget(old);
    if (widget.count > old.count) {
      _shownCount = widget.count;
      final event = _burst.update(widget.count);
      _pulseSeq = event?.sequence ?? _pulseSeq + 1;
      if (widget.haptics) HapticFeedback.lightImpact();
      final reached = widget.target > 0 && widget.count >= widget.target;
      if (reached && !_targetHit && widget.haptics) {
        HapticFeedback.heavyImpact();
      }
      _targetHit = reached;
    } else if (widget.count < old.count) {
      // A reset (new test / new attempt).
      _shownCount = widget.count;
      _targetHit = false;
      _burst.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.nuvoScale;
    final numberSize = (widget.compact ? 40.0 : 72.0) * s;
    final targetLabel = widget.target > 0 ? ' / ${widget.target}' : '';

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        // Running number.
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$_shownCount',
                style: AppTextStyles.displayLarge.copyWith(
                  fontSize: numberSize,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  color: _targetHit ? NuvoColors.success : widget.onColor,
                ),
              ),
              TextSpan(
                text: targetLabel,
                style: AppTextStyles.titleLarge.copyWith(
                  fontSize: numberSize * 0.42,
                  color: widget.onColor.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
        ),
        // "+N" punch — replays on every increment via the keyed animation.
        // N is the burst streak, not always 1: several reps landing close
        // together (a fast set) morph +1 -> +2 -> +3 instead of restarting.
        if (_pulseSeq > 0)
          Positioned(
            top: -numberSize * 0.55,
            child: IgnorePointer(
              child: Text(
                '+${_burst.streakCount > 0 ? _burst.streakCount : 1}',
                style: AppTextStyles.displayLarge.copyWith(
                  fontSize: numberSize * 0.7,
                  fontWeight: FontWeight.w900,
                  color: widget.accent,
                  shadows: const [
                    Shadow(
                      color: Color(0x33000000),
                      blurRadius: 12,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
              )
                  .animate(key: ValueKey(_pulseSeq))
                  .scale(
                    begin: const Offset(0.4, 0.4),
                    end: const Offset(1, 1),
                    duration: 260.ms,
                    curve: Curves.easeOutBack,
                  )
                  .fadeIn(duration: 90.ms)
                  .moveY(begin: 8, end: -18, duration: 520.ms)
                  .then()
                  .fadeOut(duration: 240.ms),
            ),
          ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../../../core/motion/motion.dart';
import '../../../core/v13/tokens.dart';

/// The single focal point of the login screen: one bold white race card on
/// the coral field — a Nuvo mark and three lanes where three racers run
/// the course on a loop and YOU (blue ring) wins. One element, no stack.
class ObLoginHero extends StatefulWidget {
  const ObLoginHero({super.key});

  @override
  State<ObLoginHero> createState() => _ObLoginHeroState();
}

class _ObLoginHeroState extends State<ObLoginHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: NuvoMotion.loginLoop,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!NuvoMotion.reduceMotionOf(context)) _clock.repeat();
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  // Each lane's pace: YOU finishes first, the others trail close behind.
  static const _pace = [1.0 / 0.82, 1.0 / 0.95, 1.0 / 0.70];
  static const _names = ['Maya', 'You', 'Leo'];

  @override
  Widget build(BuildContext context) {
    final reduce = NuvoMotion.reduceMotionOf(context);
    return NuvoFloat(
      child: Container(
        padding: const EdgeInsets.all(V13.gapXl),
        decoration: BoxDecoration(
          color: V13.white,
          borderRadius: BorderRadius.circular(V13.radiusCardLg),
          border: Border.all(color: V13.navy, width: V13.outlineThick),
          boxShadow: V13.shadow6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: V13.navy,
                    borderRadius: BorderRadius.circular(V13.radiusTile),
                  ),
                  child: Text(
                    'N',
                    style: V13.cardTitle.copyWith(color: V13.white),
                  ),
                ),
                const SizedBox(width: V13.gapSm),
                Text('Nuvo', style: V13.cardTitle),
              ],
            ),
            const SizedBox(height: V13.gapXl),
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(height: V13.gapLg),
              AnimatedBuilder(
                animation: _clock,
                builder: (context, _) {
                  final t = reduce ? 1.0 : _clock.value;
                  final p = (t * _pace[i]).clamp(0.0, 1.0);
                  return _Lane(name: _names[i], progress: p, isYou: i == 1);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Lane extends StatelessWidget {
  const _Lane({
    required this.name,
    required this.progress,
    required this.isYou,
  });

  final String name;
  final double progress;
  final bool isYou;

  static const double _token = 48;

  @override
  Widget build(BuildContext context) {
    final ring = isYou ? V13.blue : V13.navy;
    return SizedBox(
      height: _token,
      child: LayoutBuilder(
        builder: (context, c) {
          final run = c.maxWidth - _token - 28;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: _token / 2,
                right: 28,
                top: _token / 2 - 1.5,
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: isYou
                        ? V13.blue.withValues(alpha: 0.35)
                        : V13.divider,
                    borderRadius: BorderRadius.circular(V13.radiusPill),
                  ),
                ),
              ),
              Positioned(
                right: 0,
                top: 4,
                child: Icon(Icons.flag_rounded, size: 26, color: V13.navy),
              ),
              Positioned(
                left: run * progress,
                top: 0,
                child: Container(
                  width: _token,
                  height: _token,
                  decoration: BoxDecoration(
                    color: V13.bg,
                    shape: BoxShape.circle,
                    border: Border.all(color: ring, width: V13.outlineThick),
                  ),
                  child: Icon(
                    Icons.person_rounded,
                    size: 28,
                    color: isYou ? V13.blue : V13.muted,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

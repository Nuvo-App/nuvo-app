import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/motion/motion.dart';
import '../../../core/v13/tokens.dart';
import '../flow/onboarding_copy.dart';
import 'typewriter_text.dart';

/// The login hero: one confident brand statement. The real Nuvo logo mark
/// (spring scale-in, then a gentle vertical float) over one bold headline,
/// Nothing else: no path, no beads, nothing tilted or floating around.
class ObLoginHero extends StatefulWidget {
  const ObLoginHero({super.key});

  @override
  State<ObLoginHero> createState() => _ObLoginHeroState();
}

class _ObLoginHeroState extends State<ObLoginHero>
    with TickerProviderStateMixin {
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: NuvoMotion.enter,
  );
  late final AnimationController _float = AnimationController(
    vsync: this,
    duration: NuvoMotion.floatPeriod,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (NuvoMotion.reduceMotionOf(context)) {
      _in.value = 1;
    } else {
      _in.forward();
      _float.repeat();
    }
  }

  @override
  void dispose() {
    _in.dispose();
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final logoH = math.min(190.0, c.maxHeight * 0.44);
        return Stack(
          children: [
            Align(
              alignment: const Alignment(0, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: Listenable.merge([_in, _float]),
                    builder: (context, child) {
                      final t = NuvoMotion.spring.transform(_in.value);
                      final dy =
                          math.sin(_float.value * 2 * math.pi) *
                          NuvoMotion.floatAmplitude;
                      return Opacity(
                        opacity: _in.value.clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(0, dy),
                          child: Transform.scale(
                            scale: 0.6 + 0.4 * t,
                            child: child,
                          ),
                        ),
                      );
                    },
                    child: Image.asset(
                      'assets/branding/nuvo_logo_navy.png',
                      key: const ValueKey('ob-login-logo'),
                      height: logoH,
                      fit: BoxFit.contain,
                      semanticLabel: 'Nuvo',
                      errorBuilder: (_, _, _) => SizedBox(height: logoH),
                    ),
                  ),
                  SizedBox(height: logoH * 0.16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: ObTypewriter(
                      phrases: ObCopy.loginPhrases,
                      semanticLabel: ObCopy.loginHeadline,
                      style: V13.title.copyWith(
                        fontSize: 40,
                        height: 1.08,
                        color: V13.navy,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

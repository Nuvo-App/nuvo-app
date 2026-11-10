import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/motion/motion.dart';
import '../../../core/v13/tokens.dart';
import '../flow/onboarding_copy.dart';

/// The login hero: one confident brand statement. The real Nuvo logo mark
/// (spring scale-in, then a gentle vertical float) over one bold headline,
/// with a single thin race-path line (navy, white beads, checkered flag)
/// as the only secondary graphic. Nothing tilted, nothing floating around.
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
        final logoH = math.min(150.0, c.maxHeight * 0.36);
        return Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _PathPainter())),
            Align(
              alignment: const Alignment(0, -0.15),
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
                      'assets/branding/nuvo_logo_graphic.png',
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
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        ObCopy.loginHeadline,
                        key: const ValueKey('ob-login-headline'),
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        style: V13.title.copyWith(
                          fontSize: 42,
                          height: 1.05,
                          color: V13.white,
                        ),
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

/// One thin navy race path across the lower hero: white beads and a
/// checkered flag at the end. Static — it is texture, not a second focal
/// point.
class _PathPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final y0 = size.height * 0.90;
    final amp = size.height * 0.035;
    Offset at(double u) => Offset(
      24 + (size.width - 48 - 28) * u,
      y0 - math.sin(u * math.pi * 1.5) * amp * 2 + amp,
    );
    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i <= 60; i++) {
      final p = at(i / 60);
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = V13.white.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 2.5,
    );
    for (var i = 0; i < 6; i++) {
      final p = at(i / 5);
      canvas.drawCircle(p, 7, Paint()..color = V13.white);
      canvas.drawCircle(
        p,
        7,
        Paint()
          ..color = V13.blue
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
    // Checkered flag at the finish.
    final end = at(1);
    final pole = Offset(end.dx + 14, end.dy);
    canvas.drawLine(
      pole,
      pole.translate(0, -34),
      Paint()
        ..color = V13.white
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
    const cell = 6.0;
    for (var r = 0; r < 3; r++) {
      for (var cI = 0; cI < 3; cI++) {
        canvas.drawRect(
          Rect.fromLTWH(
            pole.dx + 1.5 + cI * cell,
            pole.dy - 34 + r * cell,
            cell,
            cell,
          ),
          Paint()..color = (r + cI).isEven ? V13.white : V13.blue,
        );
      }
    }
    canvas.drawRect(
      Rect.fromLTWH(pole.dx + 1.5, pole.dy - 34, cell * 3, cell * 3),
      Paint()
        ..color = V13.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_PathPainter old) => false;
}
